import SwiftUI

struct HarnessPopoverView: View {
    @State var info: HarnessInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = info.writeError {
                errorBanner(err)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    rulesSection
                    if !info.hooks.isEmpty {
                        Divider().padding(.vertical, 4)
                        hooksSection
                    }
                    Divider().padding(.vertical, 4)
                    footerRow
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 260)
    }

    // MARK: - Sections

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("rules", count: info.rules.count)
            if info.rules.isEmpty {
                Text("없음")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(info.rules) { rule in
                    Text(rule.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("hooks", count: info.hooks.count, subtitle: "\(info.enabledHookCount) 활성")
            ForEach(info.hooks) { hook in
                HookRow(hook: hook) { toggled in
                    info = HarnessManager.toggle(hook: toggled, in: info)
                }
            }
        }
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

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

// MARK: - Hook Row

private struct HookRow: View {
    let hook: HookEntry
    let onToggle: (HookEntry) -> Void
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
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

        init(session: SessionInfo, harness: Binding<HarnessInfo?>) {
            self.session = session
            self.harness = harness
            super.init()
        }

        @objc func tapped(_ sender: NSButton) {
            if let p = popover, p.isShown { p.close(); return }
            // Fresh scan on open
            let info = HarnessScanner.scan(cwd: session.cwd)
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
