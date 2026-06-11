import SwiftUI
import AppKit

// MARK: - Filter Mode

private enum FilterMode: Equatable {
    case all, untagged
    case tag(String)
}

// MARK: - Main View

struct MenuContentView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var tagStore: TagStore
    @State private var filter: FilterMode = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !usedTags.isEmpty {
                filterBar
                Divider()
            }
            if filteredSessions.isEmpty && store.recentlyClosed.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSessions) { session in
                            SessionRow(
                                session: session,
                                tagStore: tagStore,
                                onTap: { store.resume(session) },
                                onRename: { name in store.setCustomName(sessionId: session.sessionId, name: name) }
                            )
                            Divider().opacity(0.4)
                        }
                        if !store.recentlyClosed.isEmpty {
                            recentlyClosedSection
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .onChange(of: tagStore.sessionTags) { _ in
            if case .tag(let t) = filter, !usedTags.contains(t) {
                filter = .all
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Text("airuncat")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text(summary)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                FilterChip("All", active: filter == .all) { filter = .all }
                FilterChip("Untagged", active: filter == .untagged) { filter = .untagged }
                ForEach(usedTags, id: \.self) { tag in
                    FilterChip(tag, active: filter == .tag(tag)) { filter = .tag(tag) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var recentlyClosedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.4)
            Text("Recently Closed")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(store.recentlyClosed, id: \.info.id) { item in
                RecentlyClosedRow(item: item, onTap: { store.resumeClosed(item.info) })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No sessions")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("The cat naps until Claude gets to work.")
                .font(.system(size: 11))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { store.refresh() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Computed

    private var summary: String {
        let a = store.activeCount, i = store.idleCount
        if a == 0 && i == 0 { return "all quiet" }
        return "\(a) active · \(i) idle"
    }

    private var usedTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for s in store.visibleSessions {
            for tag in tagStore.tags(for: s.sessionId) where seen.insert(tag).inserted {
                result.append(tag)
            }
        }
        return result
    }

    private var filteredSessions: [SessionInfo] {
        switch filter {
        case .all:        return store.visibleSessions
        case .untagged:   return store.visibleSessions.filter { tagStore.tags(for: $0.sessionId).isEmpty }
        case .tag(let t): return store.visibleSessions.filter { tagStore.tags(for: $0.sessionId).contains(t) }
        }
    }
}

// MARK: - Tag Color

private let tagPalette: [Color] = [
    .blue, .green, .orange, .purple, .red, .teal, .pink, .indigo
]

// DJB2: stable across launches (unlike hashValue which is randomized per process)
private func tagColor(_ tag: String) -> Color {
    var h: UInt32 = 5381
    for byte in tag.utf8 { h = h &* 31 &+ UInt32(byte) }
    return tagPalette[Int(h) % tagPalette.count]
}

private let tagIconEmpty  = NSImage(systemSymbolName: "tag",      accessibilityDescription: nil)!
private let tagIconFilled = NSImage(systemSymbolName: "tag.fill", accessibilityDescription: nil)!

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    init(_ label: String, active: Bool, action: @escaping () -> Void) {
        self.label = label
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(active ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundColor(active ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SessionInfo
    @ObservedObject var tagStore: TagStore
    let onTap: () -> Void
    let onRename: (String) -> Void

    @State private var hovering = false
    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Capsule()
                .fill(statusBarColor)
                .frame(width: 3, height: 28)
                .padding(.top, 3)

            Text(session.aiKind == .claude ? "C" : "G")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .foregroundColor(.secondary)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                titleArea
                if !session.lastUserMessage.isEmpty {
                    Text(session.lastUserMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let skill = session.activeSkill, session.workState == .working {
                    Text("/\(skill)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor.opacity(0.85))
                        .lineLimit(1)
                } else if !activity.isEmpty {
                    Text(activity)
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(relativeTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TagButton(sessionId: session.sessionId, tagStore: tagStore)
                    .frame(width: 14, height: 14)
                if hovering && !isEditing {
                    Text(session.aiKind == .claude ? "resume" : "new session")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onTap() } }
        .onHover { hovering = $0 }
        .help(session.aiKind == .claude
            ? "Resume: claude -r \(session.sessionId)"
            : "Opens a new Gemini session in: \(session.cwd)")
    }

    @ViewBuilder
    private var titleArea: some View {
        if isEditing {
            InlineNameField(
                initialText: session.customName ?? session.projectName,
                onCommit: { name in
                    isEditing = false
                    onRename(name)
                },
                onCancel: { isEditing = false }
            )
            .frame(height: 16)
        } else {
            HStack(spacing: 4) {
                Text(session.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { isEditing = true }
                ForEach(tagStore.tags(for: session.sessionId), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(tagColor(tag).opacity(0.18))
                        )
                        .foregroundColor(tagColor(tag))
                }
                if !session.gitBranch.isEmpty {
                    Text(session.gitBranch)
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    private var activity: String {
        guard !session.toolName.isEmpty else { return "" }
        return session.toolDetail.isEmpty ? session.toolName : "\(session.toolName): \(session.toolDetail)"
    }

    private var statusBarColor: Color {
        if case .resting = session.status { return Color.secondary.opacity(0.35) }
        switch session.workState {
        case .working:   return .green
        case .responded: return .orange
        }
    }

    private var relativeTime: String {
        let s = Int(Date().timeIntervalSince(session.lastActivity))
        if s < 60 { return "\(max(s, 0))s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}

// MARK: - Tag Button (NSPopover)

private struct TagButton: NSViewRepresentable {
    let sessionId: String
    @ObservedObject var tagStore: TagStore

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.setButtonType(.momentaryLight)
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.tapped(_:))
        applyImage(to: btn)
        return btn
    }

    func updateNSView(_ btn: NSButton, context: Context) {
        applyImage(to: btn)
        context.coordinator.sessionId = sessionId
    }

    private func applyImage(to btn: NSButton) {
        let tags = tagStore.tags(for: sessionId)
        if tags.isEmpty {
            btn.image = tagIconEmpty
            btn.contentTintColor = .tertiaryLabelColor
        } else {
            btn.image = tagIconFilled
            btn.contentTintColor = NSColor(tagColor(tags[0]))
        }
        btn.title = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, tagStore: tagStore)
    }

    @MainActor
    final class Coordinator: NSObject {
        var sessionId: String
        var tagStore: TagStore
        private var popover: NSPopover?

        init(sessionId: String, tagStore: TagStore) {
            self.sessionId = sessionId
            self.tagStore = tagStore
            super.init()
        }

        @objc func tapped(_ sender: NSButton) {
            if let p = popover, p.isShown { p.close(); return }
            let p = NSPopover()
            p.behavior = .transient
            let vc = NSHostingController(
                rootView: TagPopoverView(sessionId: sessionId, tagStore: tagStore)
            )
            p.contentViewController = vc
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            self.popover = p
        }
    }
}

// MARK: - Tag Popover

private struct TagPopoverView: View {
    let sessionId: String
    @ObservedObject var tagStore: TagStore
    @State private var newTag = ""
    @State private var editingTag: String? = nil
    @State private var editText = ""

    private var selected: Set<String> { Set(tagStore.tags(for: sessionId)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tagStore.tagPool, id: \.self) { tag in
                        tagRow(tag)
                    }
                }
            }
            .frame(maxHeight: 160)

            Divider()

            HStack(spacing: 4) {
                Text("+")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("new tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        tagStore.addTag(newTag, to: sessionId)
                        newTag = ""
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 200)
    }

    @ViewBuilder
    private func tagRow(_ tag: String) -> some View {
        let isSelected = selected.contains(tag)
        TagRowView(
            tag: tag,
            isSelected: isSelected,
            isEditing: editingTag == tag,
            editText: editingTag == tag ? $editText : .constant(""),
            onToggle: { toggleTag(tag) },
            onBeginEdit: { editingTag = tag; editText = tag },
            onCommitEdit: { commitRename(tag) }
        )
    }

    private func toggleTag(_ tag: String) {
        if selected.contains(tag) {
            tagStore.removeTag(tag, from: sessionId)
        } else {
            tagStore.addTag(tag, to: sessionId)
        }
    }

    private func commitRename(_ old: String) {
        tagStore.renameTag(old, to: editText)
        editingTag = nil
        editText = ""
    }
}

// MARK: - Tag Row

private struct TagRowView: View {
    let tag: String
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editText: String
    let onToggle: () -> Void
    let onBeginEdit: () -> Void
    let onCommitEdit: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit { onCommitEdit() }
                Spacer()
                Button(action: onCommitEdit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Text(tag)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? tagColor(tag) : .primary)
                Spacer()
                if hovering {
                    Button(action: onBeginEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? tagColor(tag).opacity(0.12)
                : (hovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onToggle() } }
        .onHover { hovering = $0 }
    }
}

// MARK: - Recently Closed Row

private struct RecentlyClosedRow: View {
    let item: (info: SessionInfo, closedAt: Date)
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text(item.info.aiKind == .claude ? "C" : "G")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .foregroundColor(Color.secondary.opacity(0.6))

            Text(item.info.projectName.isEmpty ? item.info.displayName : item.info.projectName)
                .font(.system(size: 11))
                .foregroundColor(Color.secondary.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 4)

            if hovering {
                Text(item.info.aiKind == .claude ? "Resume" : "Open new")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)
            } else {
                TimelineView(.periodic(from: item.closedAt, by: 1.0)) { ctx in
                    Text("\(Int(ctx.date.timeIntervalSince(item.closedAt)))s ago")
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering = $0 }
        .help(item.info.aiKind == .claude
            ? "Resume: claude -r \(item.info.sessionId)"
            : "Opens a new Gemini session in: \(item.info.cwd)")
    }
}

// MARK: - Inline Name Field

private struct InlineNameField: NSViewRepresentable {
    let initialText: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = initialText
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = .labelColor
        field.cell?.sendsActionOnEndEditing = false
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: InlineNameField
        private var handled = false

        init(_ parent: InlineNameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                handled = true
                parent.onCommit((control as? NSTextField)?.stringValue ?? parent.initialText)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                handled = true
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !handled else { return }
            handled = true
            parent.onCommit((obj.object as? NSTextField)?.stringValue ?? parent.initialText)
        }
    }
}
