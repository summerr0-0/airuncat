import SwiftUI
import AppKit

struct MCPView: View {
    @State private var records: [MCPRecord] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var errors: [(id: UUID, message: String)] = []
    @State private var showCreateForm = false
    @State private var createName = ""
    @State private var createCommand = ""
    @State private var createArgsText = ""
    @State private var createError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            if isLoading {
                loadingRow
            } else if filtered.isEmpty && !showCreateForm {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { rec in
                            MCPRow(
                                record: rec,
                                onToggle: { toggle(rec) },
                                onDelete: { delete(rec) }
                            )
                            Divider().opacity(0.4)
                        }
                        if !errors.isEmpty { errorBanner }
                    }
                }
                .frame(maxHeight: 340)
            }
            if showCreateForm {
                Divider()
                createFormSection
            }
            Divider()
            bottomBar
        }
        .task { await reload() }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Search MCP servers", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var loadingRow: some View {
        Text("Scanning…")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("MCP 서버 없음")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text("+ 추가로 첫 서버를 등록하세요")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
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
    }

    @ViewBuilder
    private var createFormSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("이름")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
                TextField("my-server", text: $createName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: createName) {
                        let s = createName.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                        if s != createName { createName = s }
                    }
            }
            HStack(spacing: 8) {
                Text("명령어")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
                TextField("npx", text: $createCommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
            }
            HStack(spacing: 8) {
                Text("인수")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
                TextField("-y @my/mcp@latest", text: $createArgsText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
            }
            if let err = createError {
                Text(err).font(.system(size: 10)).foregroundColor(.red).padding(.leading, 44)
            }
            HStack {
                Spacer()
                let canCreate = !createName.isEmpty && !createCommand.isEmpty
                Button("추가") { Task { await performCreate() } }
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

    private var bottomBar: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: MCPScanner.mcpJsonPath))
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("~/.mcp.json 열기")

            Spacer()

            Button(showCreateForm ? "취소" : "+ 추가") {
                if showCreateForm { resetForm() } else { showCreateForm = true }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(showCreateForm ? .secondary : .accentColor)

            Button("Refresh") { Task { await reload() } }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Computed

    private var filtered: [MCPRecord] {
        guard !searchText.isEmpty else { return records }
        let q = searchText.lowercased()
        return records.filter { $0.id.lowercased().contains(q) || $0.command.lowercased().contains(q) }
    }

    // MARK: - Actions

    @MainActor
    private func reload() async {
        isLoading = true
        records = await Task.detached(priority: .userInitiated) {
            MCPScanner.scan()
        }.value
        errors = []
        isLoading = false
    }

    private func appendError(_ msg: String) {
        errors.append((id: UUID(), message: msg))
    }

    private func toggle(_ record: MCPRecord) {
        Task {
            let err = await Task.detached(priority: .userInitiated) {
                MCPManager.toggle(record)
            }.value
            if let err {
                appendError(err)
            } else if let idx = records.firstIndex(where: { $0.id == record.id }) {
                records[idx].enabled.toggle()
            }
        }
    }

    private func delete(_ record: MCPRecord) {
        Task {
            let err = await Task.detached(priority: .userInitiated) {
                MCPManager.delete(record)
            }.value
            if let err {
                appendError(err)
            } else {
                records.removeAll { $0.id == record.id }
            }
        }
    }

    @MainActor
    private func performCreate() async {
        createError = nil
        let name = createName
        let command = createCommand
        let args = createArgsText.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let err = await Task.detached(priority: .userInitiated) {
            MCPManager.create(name: name, command: command, args: args)
        }.value
        if let err {
            createError = err
            return
        }
        resetForm()
        await reload()
    }

    private func resetForm() {
        showCreateForm = false
        createName = ""
        createCommand = ""
        createArgsText = ""
        createError = nil
    }
}

// MARK: - MCP Row

private struct MCPRow: View {
    let record: MCPRecord
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                // Enable/disable indicator
                Circle()
                    .fill(record.enabled ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.id)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(([record.command] + record.args).joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if hovering && !confirmingDelete {
                        Button(action: onToggle) {
                            Text(record.enabled ? "비활성" : "활성")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(record.enabled
                                    ? Color.secondary.opacity(0.15)
                                    : Color.green.opacity(0.15))
                                .foregroundColor(record.enabled ? .secondary : .green)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .help(record.enabled ? "비활성화" : "활성화")

                        Button { confirmingDelete = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("서버 삭제")
                    } else if !hovering {
                        Text(record.enabled ? "활성" : "비활성")
                            .font(.system(size: 9))
                            .foregroundColor(record.enabled ? .green : .secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hovering && !confirmingDelete ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }

            if confirmingDelete {
                Divider().opacity(0.4)
                HStack(spacing: 0) {
                    Button("취소") { confirmingDelete = false }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Text("서버 및 활성화 목록에서 제거합니다")
                        .font(.system(size: 10)).foregroundColor(.red.opacity(0.8))
                    Spacer()
                    Button("삭제") { confirmingDelete = false; onDelete() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red.opacity(0.05))
            }
        }
    }
}
