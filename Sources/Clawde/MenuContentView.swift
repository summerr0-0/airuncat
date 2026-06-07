import SwiftUI

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
                            SessionRow(session: session) { store.resume(session) }
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

private struct SessionRow: View {
    let session: SessionInfo
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

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
                    if hovering {
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
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Resume in Warp: claude -r \(session.sessionId)")
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
