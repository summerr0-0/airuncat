import SwiftUI
import AppKit

// MARK: - Popover View

struct ClaudeMdPopoverView: View {
    let cwd: String
    @State private var info: ClaudeMdInfo? = nil
    @State private var selectedTab: ClaudeMdTab = .project
    @State private var isLoading = true
    @State private var createError: String? = nil

    private enum ClaudeMdTab { case global, project }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            tabBar
            Divider()
            if isLoading {
                loadingRow
            } else if let info {
                contentArea(info: info)
            }
        }
        .frame(width: 300)
        .task { await reload() }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("CLAUDE.md")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Button {
                if selectedTab == .global {
                    NSWorkspace.shared.open(URL(fileURLWithPath: ClaudeMdScanner.globalPath)
                        .deletingLastPathComponent())
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Finder에서 열기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("글로벌", tab: .global)
            tabButton("프로젝트", tab: .project)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tabButton(_ label: String, tab: ClaudeMdTab) -> some View {
        Button(action: { selectedTab = tab }) {
            Text(label)
                .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var loadingRow: some View {
        Text("스캔 중…")
            .font(.system(size: 11)).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }

    @ViewBuilder
    private func contentArea(info: ClaudeMdInfo) -> some View {
        if selectedTab == .global {
            entryView(entry: info.globalEntry, allowCreate: false)
        } else {
            let existing = info.projectEntries.filter { $0.exists }
            let missing  = info.projectEntries.filter { !$0.exists }
            if existing.isEmpty {
                noProjectFileView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(existing) { entry in
                            entryView(entry: entry, allowCreate: false)
                            if entry.id != existing.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            if !missing.isEmpty {
                Divider()
                ForEach(missing) { entry in
                    createMissingRow(entry: entry)
                }
            }
        }
        if let err = createError {
            Divider()
            Text(err).font(.system(size: 10)).foregroundColor(.red)
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func entryView(entry: ClaudeMdEntry, allowCreate: Bool) -> some View {
        if !entry.exists {
            if allowCreate {
                noProjectFileView
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // Meta row
                HStack(spacing: 8) {
                    Text(entry.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let mtime = entry.mtime {
                        Text(mtimeLabel(mtime))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Text("\(entry.wordCount)단어")
                        .font(.system(size: 9))
                        .foregroundColor(entry.wordCount >= 500 ? .orange : .secondary.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if entry.wordCount >= 500 {
                    Text("컨텍스트가 큽니다 (\(entry.wordCount)단어)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                }

                Divider().padding(.horizontal, 12)

                // Preview
                if let lines = previewLines(path: entry.path) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(lines.indices, id: \.self) { i in
                            Text(lines[i])
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }

                // Actions
                HStack(spacing: 10) {
                    Spacer()
                    Button("에디터에서 열기") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private var noProjectFileView: some View {
        VStack(spacing: 4) {
            Text("CLAUDE.md 없음")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("프로젝트 루트에 생성하세요")
                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 12)
    }

    private func createMissingRow(entry: ClaudeMdEntry) -> some View {
        HStack {
            Text(entry.label)
                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.6))
            Spacer()
            Button("+ 생성") { Task { await createFile(at: entry.path) } }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Actions

    @MainActor
    private func reload() async {
        isLoading = true
        let cwd = cwd
        info = await Task.detached(priority: .userInitiated) {
            ClaudeMdScanner.scan(cwd: cwd)
        }.value
        isLoading = false
    }

    @MainActor
    private func createFile(at path: String) async {
        createError = nil
        let projectName = (cwd as NSString).lastPathComponent
        let template = HarnessSetup.claudeMdTemplate(projectName: projectName)
        let err: String? = await Task.detached(priority: .userInitiated) { () -> String? in
            let dir = (path as NSString).deletingLastPathComponent
            let fm = FileManager.default
            if !fm.fileExists(atPath: dir) {
                do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
                catch { return "디렉토리 생성 실패: \(error.localizedDescription)" }
            }
            do { try template.write(toFile: path, atomically: true, encoding: .utf8) }
            catch { return "파일 생성 실패: \(error.localizedDescription)" }
            return nil
        }.value
        if let err {
            createError = err
        } else {
            await reload()
            selectedTab = .project
        }
    }

    // MARK: - Helpers

    private func previewLines(path: String) -> [String]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(20)
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

// MARK: - CLAUDE.md Badge Button

struct ClaudeMdBadgeButton: NSViewRepresentable {
    let session: SessionInfo

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.setButtonType(.momentaryLight)
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.tapped(_:))
        btn.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        btn.title = "C"
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    func updateNSView(_ btn: NSButton, context: Context) {
        context.coordinator.session = session
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    final class Coordinator: NSObject {
        var session: SessionInfo
        private var popover: NSPopover?
        private var scanning = false

        init(session: SessionInfo) {
            self.session = session
            super.init()
        }

        @objc func tapped(_ sender: NSButton) {
            if let p = popover, p.isShown { p.close(); return }
            guard !scanning else { return }
            scanning = true
            let cwd = session.cwd
            Task {
                await MainActor.run {
                    scanning = false
                    let p = NSPopover()
                    p.behavior = .transient
                    p.contentViewController = NSHostingController(
                        rootView: ClaudeMdPopoverView(cwd: cwd)
                    )
                    p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                    self.popover = p
                }
            }
        }
    }
}
