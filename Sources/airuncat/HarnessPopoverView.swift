import SwiftUI

struct HarnessPopoverView: View {
    @State var info: HarnessInfo
    @State private var showCreateForm = false
    @State private var createName = ""
    @State private var createScope: RuleScope = .project
    @State private var createError: String? = nil
    @State private var showPermCreateForm = false
    @State private var permPattern = ""
    @State private var permKind: PermissionKind = .allow
    @State private var permCreateError: String? = nil
    @State private var errors: [(id: UUID, message: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !errors.isEmpty { errorBanner }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    rulesSection
                    if !info.hooks.isEmpty {
                        Divider().padding(.vertical, 4)
                        hooksSection
                    }
                    Divider().padding(.vertical, 4)
                    permissionsSection
                    if showPermCreateForm {
                        Divider().padding(.vertical, 2)
                        permCreateFormSection
                    }
                    Divider().padding(.vertical, 4)
                    footerRow
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 480)
            if showCreateForm {
                Divider()
                createFormSection
            }
        }
        .frame(width: 280)
    }

    // MARK: - Sections

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let globals = info.rules.filter { $0.scope == .global }
            let projects = info.rules.filter { $0.scope == .project }

            sectionHeader("rules", count: info.rules.count,
                          subtitle: globals.isEmpty ? nil : "글로벌 \(globals.count) + 프로젝트 \(projects.count)")

            if info.rules.isEmpty {
                HStack(spacing: 6) {
                    Text("없음")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    Spacer()
                    Button("+ 새 Rule") { showCreateForm = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                        .padding(.trailing, 12)
                }
            } else {
                if !globals.isEmpty {
                    scopeLabel("글로벌", color: .secondary)
                    ForEach(globals) { rule in
                        RuleRow(rule: rule, onDelete: { delete(rule) }, onRescan: rescan)
                        Divider().opacity(0.3).padding(.leading, 12)
                    }
                }
                if !projects.isEmpty {
                    if !globals.isEmpty { Divider().opacity(0.3) }
                    scopeLabel("프로젝트", color: .accentColor)
                    ForEach(projects) { rule in
                        RuleRow(rule: rule, onDelete: { delete(rule) }, onRescan: rescan)
                        Divider().opacity(0.3).padding(.leading, 12)
                    }
                }
                HStack {
                    Spacer()
                    Button("+ 새 Rule") { showCreateForm.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(showCreateForm ? .secondary : .accentColor)
                        .padding(.trailing, 12)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func scopeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 1)
    }

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("hooks", count: info.hooks.count, subtitle: "\(info.enabledHookCount) 활성")
            ForEach(info.hooks) { hook in
                HookRow(
                    hook: hook,
                    onToggle: { toggled in
                        info = HarnessManager.toggle(hook: toggled, in: info)
                    },
                    onDelete: { toDelete in
                        info = HarnessManager.deleteHook(hook: toDelete, in: info)
                    }
                )
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        let allows = info.permissions.filter { $0.kind == .allow }
        let denies = info.permissions.filter { $0.kind == .deny }
        let subtitle: String? = info.permissions.isEmpty ? nil : "allow \(allows.count) · deny \(denies.count)"
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionHeader("permissions", count: info.permissions.count, subtitle: subtitle)
                Spacer()
                Button(showPermCreateForm ? "취소" : "+ 추가") {
                    showPermCreateForm.toggle()
                    if !showPermCreateForm { resetPermForm() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundColor(showPermCreateForm ? .secondary : .accentColor)
                .padding(.trailing, 12)
            }
            if info.permissions.isEmpty {
                Text("없음")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
            } else {
                ForEach(info.permissions) { entry in
                    PermissionRow(entry: entry) {
                        info = HarnessManager.removePermission(entry, in: info)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var permCreateFormSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("패턴")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)
                TextField("Bash(npm *)", text: $permPattern)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
            }
            HStack(spacing: 6) {
                Text("종류")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)
                HStack(spacing: 8) {
                    permKindToggle("allow", kind: .allow, color: .green)
                    permKindToggle("deny", kind: .deny, color: .red)
                }
            }
            if let err = permCreateError {
                Text(err).font(.system(size: 9)).foregroundColor(.red).padding(.leading, 34)
            }
            HStack {
                Spacer()
                Button("추가") {
                    let result = HarnessManager.addPermission(pattern: permPattern.trimmingCharacters(in: .whitespaces), kind: permKind, in: info)
                    if let err = result.writeError {
                        permCreateError = err
                    } else {
                        info = result
                        resetPermForm()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(permPattern.isEmpty ? Color.secondary.opacity(0.5) : .accentColor)
                .disabled(permPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func permKindToggle(_ label: String, kind: PermissionKind, color: Color) -> some View {
        Button(action: { permKind = kind }) {
            HStack(spacing: 3) {
                Image(systemName: permKind == kind ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundColor(permKind == kind ? color : .secondary.opacity(0.5))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(permKind == kind ? color : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func resetPermForm() {
        showPermCreateForm = false
        permPattern = ""
        permKind = .allow
        permCreateError = nil
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            if info.omcPresent {
                Text("~OMC 활성")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.purple.opacity(0.8))
            } else {
                Text("OMC 비활성")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("settings.json") {
                NSWorkspace.shared.open(URL(fileURLWithPath: info.settingsPath))
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var createFormSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("이름")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
                TextField("my-rule", text: $createName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: createName) { v in
                        let s = v.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                        if s != v { createName = s }
                    }
            }
            HStack(spacing: 8) {
                Text("범위")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
                HStack(spacing: 10) {
                    scopeToggle("글로벌", scope: .global)
                    scopeToggle("프로젝트", scope: .project)
                }
            }
            if let err = createError {
                Text(err).font(.system(size: 10)).foregroundColor(.red).padding(.leading, 38)
            }
            HStack {
                Button("취소") { resetForm() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                let canCreate = !createName.isEmpty
                Button("생성") { Task { await performCreate() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(canCreate ? .accentColor : Color.secondary.opacity(0.5))
                    .disabled(!canCreate)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private func scopeToggle(_ label: String, scope: RuleScope) -> some View {
        Button(action: { createScope = scope }) {
            HStack(spacing: 4) {
                Image(systemName: createScope == scope ? "circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundColor(createScope == scope ? .accentColor : .secondary.opacity(0.5))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(createScope == scope ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(errors, id: \.id) { err in
                Text(err.message)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.04))
    }

    private func sectionHeader(_ title: String, count: Int, subtitle: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            Text("(\(count))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
            if let sub = subtitle {
                Text("·")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.5))
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 3)
    }

    // MARK: - Actions

    private func rescan() {
        let cwd = info.projectPath
        Task {
            let updated = await Task.detached(priority: .userInitiated) {
                HarnessScanner.scan(cwd: cwd)
            }.value
            if let updated { info = updated }
        }
    }

    private func delete(_ rule: RuleFile) {
        Task {
            let err = await Task.detached(priority: .userInitiated) {
                RuleManager.delete(rule)
            }.value
            if let err {
                errors.append((id: UUID(), message: err))
            } else {
                rescan()
            }
        }
    }

    @MainActor
    private func performCreate() async {
        createError = nil
        let name = createName
        let scope = createScope

        // In-memory duplicate check before touching filesystem
        if info.rules.contains(where: { $0.scope == scope && $0.stem == name }) {
            createError = "이미 존재하는 Rule: \(name)"
            return
        }

        let cwd = info.projectPath
        let err = await Task.detached(priority: .userInitiated) {
            RuleManager.create(name: name, scope: scope, projectCwd: cwd)
        }.value
        if let err {
            createError = err
            return
        }
        resetForm()
        rescan()
    }

    private func resetForm() {
        showCreateForm = false
        createName = ""
        createScope = .project
        createError = nil
    }
}

// MARK: - Rule Row

private struct RuleRow: View {
    let rule: RuleFile
    let onDelete: () -> Void
    let onRescan: () -> Void
    @State private var hovering = false
    @State private var expanded = false
    @State private var confirmingDelete = false
    @State private var previewLines: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                // Scope badge
                Text(rule.scope == .global ? "G" : "P")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(rule.scope == .global ? .secondary : .accentColor)
                    .frame(width: 12)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.stem)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                    if !rule.summary.isEmpty {
                        Text(rule.summary)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(expanded ? nil : 1)
                    }
                    if expanded && !previewLines.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(previewLines.indices, id: \.self) { i in
                                Text(previewLines[i])
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(mtimeLabel(rule.mtime))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))

                    if hovering && !confirmingDelete {
                        HStack(spacing: 6) {
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: rule.path))
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Finder에서 열기")

                            Button { confirmingDelete = true } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("삭제")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(hovering && !confirmingDelete ? Color.primary.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                if !expanded { loadPreview() }
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            }

            if confirmingDelete {
                Divider().opacity(0.4)
                HStack(spacing: 0) {
                    Button("취소") { confirmingDelete = false }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Text(rule.scope == .global ? "모든 프로젝트에 영향을 줍니다" : "이 프로젝트에서 제거됩니다")
                        .font(.system(size: 9)).foregroundColor(.red.opacity(0.8))
                    Spacer()
                    Button("삭제") { confirmingDelete = false; onDelete() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.red.opacity(0.04))
            }
        }
    }

    private func loadPreview() {
        guard let content = try? String(contentsOfFile: rule.path, encoding: .utf8) else { return }
        previewLines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(5)
            .map { String($0) }
    }

    private func mtimeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 30 { return "\(days)일 전" }
        return "\(days / 30)개월 전"
    }
}

// MARK: - Hook Row

private struct HookRow: View {
    let hook: HookEntry
    let onToggle: (HookEntry) -> Void
    let onDelete: (HookEntry) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: { onToggle(hook) }) {
                Image(systemName: hook.enabled ? "circle.fill" : "circle")
                    .font(.system(size: 10))
                    .foregroundColor(hook.enabled ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(hook.event)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(hook.enabled ? .primary : .secondary)
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(hook.matcher)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(hook.commandSummary)
                    .font(.system(size: 10))
                    .foregroundColor(hook.enabled ? .primary.opacity(0.75) : .secondary.opacity(0.5))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // Disabled hook only: show delete button on hover
            if hovering && !hook.enabled {
                Button { onDelete(hook) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("hook 완전 삭제")
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let entry: PermissionEntry
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.kind == .allow ? "checkmark.circle.fill" : "minus.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(entry.kind == .allow ? .green : .red)
            Text(entry.pattern)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("권한 삭제")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Badge Button (NSViewRepresentable for SessionRow)

struct HarnessBadgeButton: NSViewRepresentable {
    let session: SessionInfo
    @Binding var harness: HarnessInfo?

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.setButtonType(.momentaryLight)
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.tapped(_:))
        btn.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        applyLabel(to: btn)
        return btn
    }

    func updateNSView(_ btn: NSButton, context: Context) {
        applyLabel(to: btn)
        context.coordinator.session = session
        context.coordinator.harness = $harness
    }

    private func applyLabel(to btn: NSButton) {
        guard let h = harness, !h.badgeLabel.isEmpty else {
            btn.title = ""
            btn.isHidden = true
            return
        }
        btn.isHidden = false
        btn.title = h.badgeLabel
        btn.contentTintColor = h.hasDisabledHook ? NSColor.systemOrange : NSColor.secondaryLabelColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, harness: $harness)
    }

    @MainActor
    final class Coordinator: NSObject {
        var session: SessionInfo
        var harness: Binding<HarnessInfo?>
        private var popover: NSPopover?
        private var scanning = false

        init(session: SessionInfo, harness: Binding<HarnessInfo?>) {
            self.session = session
            self.harness = harness
            super.init()
        }

        @objc func tapped(_ sender: NSButton) {
            if let p = popover, p.isShown { p.close(); return }
            guard !scanning else { return }
            scanning = true
            // Async scan to avoid blocking main thread with file I/O
            let cwd = session.cwd
            Task {
                let info = await Task.detached(priority: .userInitiated) {
                    HarnessScanner.scan(cwd: cwd)
                }.value
                await MainActor.run {
                    scanning = false
                    harness.wrappedValue = info
                    guard let info else { return }
                    let p = NSPopover()
                    p.behavior = .transient
                    p.contentViewController = NSHostingController(
                        rootView: HarnessPopoverView(info: info)
                    )
                    p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                    self.popover = p
                }
            }
        }
    }
}
