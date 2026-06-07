import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.visibleSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.visibleSessions) { session in
                            SessionRow(
                                session: session,
                                onTap: { store.resume(session) },
                                onRename: { name in store.setCustomName(sessionId: session.sessionId, name: name) }
                            )
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Clawde")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text(summary)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var summary: String {
        let a = store.activeCount, i = store.idleCount
        if a == 0 && i == 0 { return "all quiet" }
        return "\(a) active · \(i) idle"
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No recent sessions")
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
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SessionInfo
    let onTap: () -> Void
    let onRename: (String) -> Void

    @State private var hovering = false
    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                titleArea
                subtitleRow
                if !activity.isEmpty {
                    Text(activity)
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(relativeTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                if hovering && !isEditing {
                    Text("resume")
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
        .help("Resume: claude -r \(session.sessionId)")
    }

    @ViewBuilder
    private var titleArea: some View {
        if isEditing {
            InlineNameField(
                initialText: session.customName ?? session.title,
                onCommit: { name in
                    isEditing = false
                    onRename(name)
                },
                onCancel: { isEditing = false }
            )
            .frame(height: 16)
        } else {
            Text(session.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { isEditing = true }
        }
    }

    private var subtitleRow: some View {
        HStack(spacing: 5) {
            Text(session.projectName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            categoryTag
            if !session.gitBranch.isEmpty {
                Text(session.gitBranch)
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }

    private var activity: String {
        guard !session.toolName.isEmpty else { return "" }
        return session.toolDetail.isEmpty ? session.toolName : "\(session.toolName): \(session.toolDetail)"
    }

    private var categoryTag: some View {
        Text(session.category.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(session.category == .dev ? Color.blue.opacity(0.18) : Color.purple.opacity(0.18))
            )
            .foregroundColor(session.category == .dev ? .blue : .purple)
    }

    private var statusColor: Color {
        switch session.status {
        case .active:  return .green
        case .idle:    return .orange
        case .resting: return .gray
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

// MARK: - Inline name editor (NSTextField wrapper for Enter/Escape support on macOS 13+)

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
        // Defer first responder assignment until the view is in the window hierarchy.
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

        // Fired when the field loses focus (window dismissed, tab, etc.).
        func controlTextDidEndEditing(_ obj: Notification) {
            guard !handled else { return }
            handled = true
            parent.onCommit((obj.object as? NSTextField)?.stringValue ?? parent.initialText)
        }
    }
}
