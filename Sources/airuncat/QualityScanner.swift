import Foundation

// MARK: - Phase 17b: LLM 내용 품질 진단

/// 진단 결과 (내부 JSON 계약).
struct QualityReport: Codable, Equatable {
    var placeholders: [String] = []
    var contradictions: [String] = []
    var vague: [String] = []
    var score: Int = 0
    // 메타
    var inputHash: String = ""
    var at: TimeInterval = 0
}

/// CLAUDE.md/rules 내용 품질을 `claude -p`(headless, --bare, haiku)로 1회 진단한다.
/// 비용 헌법(스펙): 수동 트리거만·입력 4KB 캡·해시 캐시. 자동 실행 경로 없음.
@MainActor
final class QualityScanner: ObservableObject {
    static let shared = QualityScanner()

    enum Phase: Equatable {
        case idle
        case running
        case done(QualityReport, cached: Bool)
        case failed(String)
    }

    /// projectPath -> 진단 상태. 팝오버(.transient)가 닫혀도 여기 살아있다(뷰 밖 상태).
    @Published private(set) var phases: [String: Phase] = [:]

    func phase(for projectPath: String) -> Phase { phases[projectPath] ?? .idle }

    /// 버튼 핸들러. force=false면 캐시 히트 시 프로세스 실행 없음.
    func diagnose(projectPath: String, force: Bool = false) {
        if case .running = phase(for: projectPath) { return }   // 연타 방지
        guard let input = Self.collectInput(projectPath: projectPath) else {
            phases[projectPath] = .failed("진단할 CLAUDE.md 없음")
            return
        }
        let hash = Self.hash(of: input)
        if !force, let cached = Self.loadCache(projectPath: projectPath), cached.inputHash == hash {
            phases[projectPath] = .done(cached, cached: true)
            return
        }
        phases[projectPath] = .running
        Task.detached(priority: .userInitiated) {
            let result = Self.runHeadless(input: input, hash: hash)
            await MainActor.run {
                switch result {
                case .success(let report):
                    Self.saveCache(projectPath: projectPath, report: report)
                    self.phases[projectPath] = .done(report, cached: false)
                case .failure(let msg):
                    self.phases[projectPath] = .failed(msg)
                }
            }
        }
    }

    // MARK: - 입력 수집 (4KB 캡, CLAUDE.md + 프로젝트 rules만)

    nonisolated static let inputCap = 4096
    nonisolated static let promptVersion = "v1"
    nonisolated static let model = "haiku"

    struct Input { let text: String; let truncated: Bool }

    nonisolated static func collectInput(projectPath: String) -> Input? {
        let fm = FileManager.default
        let root = (projectPath as NSString).appendingPathComponent("CLAUDE.md")
        let sub = (projectPath as NSString).appendingPathComponent(".claude/CLAUDE.md")
        let mdPath = fm.fileExists(atPath: root) ? root : (fm.fileExists(atPath: sub) ? sub : nil)
        guard let mdPath, var md = try? String(contentsOfFile: mdPath, encoding: .utf8) else { return nil }

        var truncated = false
        if md.utf8.count > inputCap { md = String(md.prefix(inputCap)); truncated = true }

        var rulesText = ""
        let rulesDir = (projectPath as NSString).appendingPathComponent(".claude/rules")
        if let files = try? fm.contentsOfDirectory(atPath: rulesDir) {
            for f in files.sorted() where f.hasSuffix(".md") {
                let p = (rulesDir as NSString).appendingPathComponent(f)
                guard var body = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
                if body.utf8.count > inputCap { body = String(body.prefix(inputCap)); truncated = true }
                rulesText += "\n### \(f)\n\(body)\n"
            }
        }
        return Input(text: "--- CLAUDE.md ---\n\(md)\n--- rules ---\(rulesText)", truncated: truncated)
    }

    nonisolated static func hash(of input: Input) -> String {
        // 프롬프트 버전+모델 포함(스펙: 프롬프트 변경 시 캐시 무효화)
        var h = Hasher()
        h.combine(promptVersion); h.combine(model); h.combine(input.text)
        return String(format: "%016x", UInt64(bitPattern: Int64(h.finalize())))
    }

    // MARK: - claude 바이너리 발견 (셸 PATH 미상속 대응 — 1회 캐시)

    nonisolated(unsafe) private static var cachedBinary: String??

    nonisolated static func claudeBinary() -> String? {
        if let cached = cachedBinary { return cached }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        var found: String? = nil
        if (try? proc.run()) != nil {
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let path = String(data: out, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if proc.terminationStatus == 0, !path.isEmpty { found = path }
        }
        cachedBinary = .some(found)
        return found
    }

    // MARK: - 실행 (블로킹 — 반드시 백그라운드 스레드에서)

    enum RunResult { case success(QualityReport), failure(String) }

    nonisolated static func runHeadless(input: Input, hash: String) -> RunResult {
        guard let binary = claudeBinary() else {
            return .failure("Claude Code CLI를 찾지 못함")
        }
        let prompt = """
        다음은 한 프로젝트의 CLAUDE.md와 rules다. 아래 4가지만 JSON으로 평가하라:
        {"placeholders": ["TODO/빈 껍데기로 방치된 부분"], "contradictions": ["서로 모순되는 지시"], \
        "vague": ["강제 불가능하게 모호한 지시"], "score": 0-10 정수}
        각 배열 항목은 한 줄 한국어. 없으면 빈 배열. JSON만 출력.

        \(input.text)
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        // argv 직접 전달(무셸) + --bare(프로젝트 컨텍스트/MCP/훅 미로딩) + 중립 cwd(재귀 완화)
        proc.arguments = ["-p", prompt, "--output-format", "json", "--model", model, "--bare"]
        proc.currentDirectoryURL = URL(fileURLWithPath: PathConstants.airuncatBase)
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch {
            return .failure("실행 실패: \(error.localizedDescription)")
        }

        // 60s 타임아웃 (블로킹 폴링 — detached 스레드 전용)
        let deadline = Date().addingTimeInterval(60)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if proc.isRunning {
            proc.terminate()
            return .failure("타임아웃(60s)")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()

        // 2층 파싱: 래퍼 JSON → (is_error 확인) → result → 펜스 제거 → 내부 JSON
        guard let wrapper = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let resultText = wrapper["result"] as? String else {
            return .failure("응답 래퍼 파싱 실패")
        }
        // CLI 레벨 오류(미인증·권한 등)는 result에 사람용 메시지가 담김 — 그대로 표면화.
        if (wrapper["is_error"] as? Bool) == true {
            return .failure(resultText)
        }
        var inner = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.hasPrefix("```") {   // ```json ... ``` 펜스 제거
            inner = inner.components(separatedBy: "\n").dropFirst()
                .joined(separator: "\n")
            if let fenceEnd = inner.range(of: "```", options: .backwards) {
                inner = String(inner[..<fenceEnd.lowerBound])
            }
        }
        guard let innerData = inner.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: innerData)) as? [String: Any] else {
            return .failure("진단 JSON 파싱 실패: \(String(inner.prefix(120)))")
        }
        var report = QualityReport()
        report.placeholders = obj["placeholders"] as? [String] ?? []
        report.contradictions = obj["contradictions"] as? [String] ?? []
        report.vague = obj["vague"] as? [String] ?? []
        report.score = (obj["score"] as? NSNumber)?.intValue ?? 0
        report.inputHash = hash
        report.at = Date().timeIntervalSince1970
        return .success(report)
    }

    // MARK: - 캐시 IO (~/.airuncat/quality-cache.json, projectPath 키)

    nonisolated private static var cachePath: String {
        (PathConstants.airuncatBase as NSString).appendingPathComponent("quality-cache.json")
    }

    nonisolated static func loadCache(projectPath: String) -> QualityReport? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
              let all = try? JSONDecoder().decode([String: QualityReport].self, from: data) else { return nil }
        return all[projectPath]
    }

    nonisolated static func saveCache(projectPath: String, report: QualityReport) {
        var all: [String: QualityReport] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
           let decoded = try? JSONDecoder().decode([String: QualityReport].self, from: data) {
            all = decoded
        }
        all[projectPath] = report
        guard let out = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(atPath: PathConstants.airuncatBase,
                                                 withIntermediateDirectories: true)
        try? out.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
    }
}
