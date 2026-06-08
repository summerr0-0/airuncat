import SwiftUI
import AppKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var catImage: NSImage = CatRenderer.image(phase: 0, mode: .sleeping)
    @Published private var liveCwds: Set<String> = []

    let tagStore = TagStore()

    private var cache: [String: (mtime: Date, info: SessionInfo)] = [:]
    private var customNames: [String: String] = CustomNameStore.load()
    private var phase: Double = 0
    private var animTimer: Timer?
    private var scanTimer: Timer?

    private var prevActiveIds: Set<String> = []
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

    var activeCount: Int { visibleSessions.filter { if case .active = $0.status { return true }; return false }.count }
    var idleCount: Int { visibleSessions.filter { if case .idle = $0.status { return true }; return false }.count }

    /// Most recent session per live-process cwd, newest first.
    var visibleSessions: [SessionInfo] {
        let slash = CharacterSet(charactersIn: "/")
        let normalizedLive = Set(liveCwds.map { $0.trimmingCharacters(in: slash) })
        var seen = Set<String>()
        var result: [SessionInfo] = []
        for session in sessions { // sorted newest-first
            let cwd = session.cwd.trimmingCharacters(in: slash)
            guard normalizedLive.contains(cwd), !seen.contains(cwd) else { continue }
            seen.insert(cwd)
            result.append(session)
        }
        return result
    }

    func refresh() {
        var localCache = cache
        let names = customNames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var found = SessionScanner.scan(cache: &localCache)
            for i in found.indices {
                found[i].customName = names[found[i].sessionId]
            }
            let detected = ProcessDetector.liveCwds()
            DispatchQueue.main.async {
                guard let self else { return }
                self.cache = localCache
                self.sessions = found
                self.liveCwds = detected
                self.detectIdleTransitions()
            }
        }
    }

    private func detectIdleTransitions() {
        let currentActiveIds = Set(visibleSessions.compactMap { s -> String? in
            guard case .active = s.status else { return nil }
            return s.sessionId
        })

        defer { prevActiveIds = currentActiveIds }

        guard !isFirstScan else { isFirstScan = false; return }

        for session in visibleSessions {
            if case .active = session.status {
                // 다시 active → 이전 idle 알림 제거
                NotificationManager.shared.dismissIdleNotification(for: session.sessionId)
            } else if prevActiveIds.contains(session.sessionId) {
                // active → idle/resting 전환 → 알림 발송
                NotificationManager.shared.sendIdleNotification(for: session)
            }
        }
    }

    private func startScanning() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: animInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let busy = activeCount
        let mode: CatMode = busy > 0 ? .running(busy) : .sleeping
        // More busy sessions -> faster gait. Sleeping cat breathes slowly.
        let step: Double
        switch mode {
        case .running(let n): step = 0.28 + 0.16 * Double(min(n, 4))
        case .sleeping:       step = 0.05
        }
        phase += step
        catImage = CatRenderer.image(phase: phase, mode: mode)
    }
}
