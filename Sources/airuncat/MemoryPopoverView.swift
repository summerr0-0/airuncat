import SwiftUI

struct MemoryPopoverView: View {
    let jsonlPath: String
    @Binding var memoryCount: Int
    @State private var records: [MemoryRecord] = []
    @State private var isLoading = true
    @State private var errors: [(id: UUID, message: String)] = []

    private var memoryDir: String { MemoryScanner.memoryDir(forJsonl: jsonlPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            if !errors.isEmpty { errorBanner }
            if isLoading {
                Text("스캔 중…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else if records.isEmpty {
                Text("메모리 없음")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(MemoryType.allCasesOrdered, id: \.self) { type in
                            let group = records.filter { $0.type == type }
                            if !group.isEmpty {
                                typeSectionHeader(type, count: group.count)
                                ForEach(group) { record in
                                    MemoryRecordRow(record: record, onDelete: { delete(record) })
                                    Divider().opacity(0.3).padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            bottomBar
        }
        .frame(width: 280)
        .task { await reload() }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("Memory")
                .font(.system(size: 11, weight: .semibold))
            if !records.isEmpty {
                Text("(\(records.count))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: memoryDir))
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("memory 폴더 열기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private func typeSectionHeader(_ type: MemoryType, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(type.rawValue)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(typeColor(type).opacity(0.9))
            Text("(\(count))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("새로고침") { Task { await reload() } }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    @MainActor
    private func reload() async {
        isLoading = true
        let path = jsonlPath
        records = await Task.detached(priority: .userInitiated) {
            MemoryScanner.scan(forJsonl: path)
        }.value
        isLoading = false
    }

    private func delete(_ record: MemoryRecord) {
        let dir = memoryDir
        Task {
            let err = await Task.detached(priority: .userInitiated) {
                MemoryManager.delete(record, memoryDir: dir)
            }.value
            if let err {
                errors.append((id: UUID(), message: err))
            } else {
                records.removeAll { $0.id == record.id }
                memoryCount = max(0, memoryCount - 1)
            }
        }
    }

    private func typeColor(_ type: MemoryType) -> Color {
        switch type {
        case .user:      return .blue
        case .feedback:  return .orange
        case .project:   return .green
        case .reference: return .purple
        case .unknown:   return .secondary
        }
    }
}


// MARK: - Memory Record Row

private struct MemoryRecordRow: View {
    let record: MemoryRecord
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var expanded = false
    @State private var confirmingDelete = false
    @State private var previewLines: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.id)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(1)
                    if !record.description.isEmpty {
                        Text(record.description)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(expanded ? nil : 1)
                    }
                    if expanded && !previewLines.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(previewLines.indices, id: \.self) { i in
                                Text(previewLines[i])
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(record.mtime.relativeLabel)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))

                    if hovering && !confirmingDelete {
                        HStack(spacing: 6) {
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: record.path))
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
                    Text("메모리 항목을 삭제합니다")
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
        guard let content = try? String(contentsOfFile: record.path, encoding: .utf8) else { return }
        // Skip frontmatter, show body lines
        var lines = content.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = Array(lines.dropFirst())
            if let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                lines = Array(lines.dropFirst(end + 1))
            }
        }
        previewLines = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(5)
            .map { String($0) }
    }

}

// MARK: - Memory Badge Button

struct MemoryBadgeButton: NSViewRepresentable {
    let session: SessionInfo
    @Binding var memoryCount: Int

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
        context.coordinator.memoryCount = $memoryCount
    }

    private func applyLabel(to btn: NSButton) {
        guard memoryCount > 0 else {
            btn.title = ""
            btn.isHidden = true
            return
        }
        btn.isHidden = false
        btn.title = "M \(memoryCount)"
        btn.contentTintColor = .secondaryLabelColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, memoryCount: $memoryCount)
    }

    @MainActor
    final class Coordinator: NSObject {
        var session: SessionInfo
        var memoryCount: Binding<Int>
        private var popover: NSPopover?
        private var scanning = false

        init(session: SessionInfo, memoryCount: Binding<Int>) {
            self.session = session
            self.memoryCount = memoryCount
            super.init()
        }

        @objc func tapped(_ sender: NSButton) {
            if let p = popover, p.isShown { p.close(); return }
            guard !scanning else { return }
            scanning = true
            let jsonlPath = session.id
            Task {
                await MainActor.run {
                    scanning = false
                    let p = NSPopover()
                    p.behavior = .transient
                    p.contentViewController = NSHostingController(
                        rootView: MemoryPopoverView(
                            jsonlPath: jsonlPath,
                            memoryCount: memoryCount
                        )
                    )
                    p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                    self.popover = p
                }
            }
        }
    }
}
