import SwiftUI
import AppKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var catImage: NSImage = CatRenderer.image(phase: 0, mode: .sleeping)
    @Published private var liveCwds: Set<String> = []
    @Published var recentlyClosed: [(info: SessionInfo, closedAt: Date)] = []

    let tagStore = TagStore()

    private var cache: [String: (mtime: Date, info: SessionInfo)] = [:]
    private var geminiCache: [String: (mtime: Date, info: SessionInfo)] = [:]
    private var customNames: [String: String] = CustomNameStore.load()
    private var phase: Double = 0
    private var animTimer: Timer?
    private var scanTimer: Timer?

    private var liveGeminiCwds: Set<String> = []

    private var prevActiveIds: Set<String> = []
    private var prevVisibleSessions: [SessionInfo] = []
    private var isFirstScan = true

    private let scanInterval: TimeInterval = 3.0
    private let animInterval: TimeInterval = 0.07

    init() {
        refresh()
        startScanning()
        startAnimating()
    }

    func setCustomName(sessionId: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            customNames.removeValue(forKey: sessionId)
        } else {
            customNames[sessionId] = trimmed
        }
        CustomNameStore.save(customNames)
        // Reflect immediately without waiting for next scan tick.
        for i in sessions.indices where sessions[i].sessionId == sessionId {
            sessions[i].customName = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Open a session: focus its existing iTerm tab, else open a new one.
    func resume(_ session: SessionInfo) {
        ITermController.open(session)
    }

    /// Reopen a recently-closed session: always opens a new tab (skip focus, the tab is gone).
    func resumeClosed(_ session: SessionInfo) {
        ITermController.openNew(session)
    }

    var activeCount: Int { visibleSessions.filter { if case .active = $0.status { return true }; return false }.count }
    var idleCount: Int { visibleSessions.filter { if case .idle = $0.status { return true }; return false }.count }
    var claudeActiveCount: Int {
        visibleSessions.filter { $0.aiKind == .claude }.filter { if case .active = $0.status { return true }; return false }.count
    }
    var geminiActiveCount: Int {
        visibleSessions.filter { $0.aiKind == .gemini }.filter { if case .active = $0.status { return true }; return false }.count
    }
    var hasWaitingSession: Bool {
        visibleSessions.contains { $0.workState == .responded && $0.status != .resting }
    }

    /// Visible sessions: both Claude and Gemini require a live process to be visible.
    var visibleSessions: [SessionInfo] {
        let claudeSessions = sessions.filter { $0.aiKind == .claude }
        let geminiSessions = sessions.filter { $0.aiKind == .gemini }
        let visible = filterByLiveProcess(claudeSessions, liveCwds: liveCwds)
                    + filterByLiveProcess(geminiSessions, liveCwds: liveGeminiCwds)
        return visible.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Claude-style filter: only sessions with a matching live process cwd.
    private func filterByLiveProcess(_ sessions: [SessionInfo], liveCwds: Set<String>) -> [SessionInfo] {
        let slash = CharacterSet(charactersIn: "/")
        let normalizedLive = Set(liveCwds.map { $0.trimmingCharacters(in: slash) })
        var seenSessionCwds = Set<String>()
        var seenLiveCwds = Set<String>()
        var result: [SessionInfo] = []
        for session in sessions { // sorted newest-first
            let scwd = session.cwd.trimmingCharacters(in: slash)
            var matchedLive: String? = nil
            if normalizedLive.contains(scwd) {
                matchedLive = scwd
            } else {
                for liveCwd in normalizedLive where scwd.hasPrefix(liveCwd + "/") {
                    if matchedLive == nil || liveCwd.count > matchedLive!.count {
                        matchedLive = liveCwd
                    }
                }
            }
            guard let matched = matchedLive,
                  !seenSessionCwds.contains(scwd),
                  !seenLiveCwds.contains(matched) else { continue }
            seenSessionCwds.insert(scwd)
            seenLiveCwds.insert(matched)
            result.append(session)
        }
        return result
    }


    func refresh() {
        var localCache = cache
        var localGeminiCache = geminiCache
        let names = customNames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var found = SessionScanner.scan(cache: &localCache)
            let geminiFound = GeminiScanner.scan(cache: &localGeminiCache)
            for i in found.indices {
                found[i].customName = names[found[i].sessionId]
            }
            let allFound = (found + geminiFound).sorted { $0.lastActivity > $1.lastActivity }
            let detected = ProcessDetector.liveCwds()
            let detectedGemini = ProcessDetector.liveGeminiCwds()
            DispatchQueue.main.async {
                guard let self else { return }
                self.cache = localCache
                self.geminiCache = localGeminiCache
                self.sessions = allFound
                self.liveCwds = detected
                self.liveGeminiCwds = detectedGemini
                let visible = self.visibleSessions   // compute once per scan
                self.detectIdleTransitions(visible: visible)
                self.detectClosedSessions(visible: visible)
            }
        }
    }

    private func detectIdleTransitions(visible: [SessionInfo]) {
        let currentActiveIds = Set(visible.compactMap { s -> String? in
            guard case .active = s.status else { return nil }
            return s.sessionId
        })
        let currentSessionIds = Set(visible.map { $0.sessionId })

        defer { prevActiveIds = currentActiveIds }

        guard !isFirstScan else { isFirstScan = false; return }

        for session in visible {
            let isNowActive: Bool
            if case .active = session.status { isNowActive = true } else { isNowActive = false }
            let wasActive = prevActiveIds.contains(session.sessionId)

            if wasActive && !isNowActive {
                NotificationManager.shared.sendIdleNotification(for: session)
            } else if !wasActive && isNowActive {
                NotificationManager.shared.dismissIdleNotification(for: session.sessionId)
            }
        }

        for id in prevActiveIds where !currentSessionIds.contains(id) {
            NotificationManager.shared.dismissIdleNotification(for: id)
        }
    }

    private func detectClosedSessions(visible: [SessionInfo]) {
        let currentIds = Set(visible.map { $0.sessionId })

        defer { prevVisibleSessions = visible }
        guard !isFirstScan else { return }

        for session in prevVisibleSessions where !currentIds.contains(session.sessionId) {
            guard !session.cwd.isEmpty else { continue }
            guard !recentlyClosed.contains(where: { $0.info.sessionId == session.sessionId }) else { continue }
            recentlyClosed.insert((info: session, closedAt: Date()), at: 0)
            if recentlyClosed.count > 5 { recentlyClosed.removeLast() }
        }

        recentlyClosed.removeAll { currentIds.contains($0.info.sessionId) }
        // Expire entries older than 30s here (scan cadence is sufficient, no need for tick()).
        recentlyClosed.removeAll { Date().timeIntervalSince($0.closedAt) >= 30 }
    }

    private func startScanning() {
        let t = Timer(timeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        scanTimer = t
    }

    private func startAnimating() {
        let t = Timer(timeInterval: animInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    private func tick() {
        let busy = activeCount
        let mode: CatMode = busy > 0 ? .running(busy) : .sleeping
        let step: Double
        switch mode {
        case .running(let n): step = 0.28 + 0.16 * Double(min(n, 4))
        case .sleeping:       step = 0.05
        }
        phase += step
        catImage = CatRenderer.image(phase: phase, mode: mode, waitingBubble: hasWaitingSession)
    }
}
