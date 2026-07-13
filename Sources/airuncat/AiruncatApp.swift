import SwiftUI
import AppKit

@main
struct AiruncatApp: App {
    @StateObject private var store   = SessionStore()
    @StateObject private var appCtrl = ApplicationController()

    init() {
        // Debug path: `airuncat --render-frames [outPath]` dumps a contact sheet and exits.
        // Must run before NotificationManager.shared (requires a real app bundle).
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--render-frames") {
            _ = NSApplication.shared   // ensure AppKit is initialized for lockFocus
            let out = (idx + 1 < args.count) ? args[idx + 1] : "/tmp/airuncat_frames.png"
            DebugRender.contactSheet(to: out)
            print("wrote \(out)")
            exit(0)
        }
        // Debug path: `airuncat --wizard-sim <dir>` — Phase 16 마법사 적용 시퀀스 헤드리스 검증
        if let idx = args.firstIndex(of: "--wizard-sim"), idx + 1 < args.count {
            let dir = args[idx + 1]
            guard var info = HarnessScanner.scan(cwd: dir) else { print("scan 실패"); exit(1) }
            print("before: \(info.score.grade.rawValue) \(info.score.percent)%")
            _ = HarnessSetup.createClaudeMd(cwd: dir)
            _ = HarnessSetup.createStarterRule(cwd: dir)
            info = HarnessScanner.scan(cwd: dir) ?? info
            info = HarnessSetup.addSensitiveDenies(in: info)
            if let e = info.writeError { print("denies err: \(e)") }
            let types = ProjectTypeDetector.detect(cwd: dir)
            for id in ["build-on-edit", "block-sensitive"] {
                guard let r = ProjectHookRecipe.catalog.first(where: { $0.id == id }),
                      let cmd = r.command(for: types) else { print("recipe skip: \(id)"); continue }
                info = HarnessManager.addDisabledHookTemplate(event: r.event, matcher: r.matcher,
                                                              command: cmd, in: info)
                if let e = info.writeError { print("add \(id) err: \(e)") }
                let hid = HarnessScanner.hookHash(event: r.event, matcher: r.matcher, command: cmd)
                if let entry = info.hooks.first(where: { $0.id == hid && !$0.enabled }) {
                    info = HarnessManager.toggle(hook: entry, in: info)
                    if let e = info.writeError { print("toggle \(id) err: \(e)") }
                } else {
                    print("toggle \(id): entry not found (hooks=\(info.hooks.count))")
                }
            }
            info = HarnessScanner.scan(cwd: dir) ?? info
            print("after:  \(info.score.grade.rawValue) \(info.score.percent)%")
            exit(0)
        }
        // Debug path: `airuncat --rule-template <dir> <id>` — Phase 17a 템플릿 추가 헤드리스 검증
        if let idx = args.firstIndex(of: "--rule-template"), idx + 2 < args.count {
            let dir = args[idx + 1], id = args[idx + 2]
            guard let t = RuleTemplate.catalog.first(where: { $0.id == id }) else {
                print("unknown template"); exit(1)
            }
            let types = ProjectTypeDetector.detect(cwd: dir)
            guard t.applicable(to: types) else { print("해당 없음 (types: \(types.map(\.label)))"); exit(0) }
            let err = RuleManager.create(name: t.id, scope: .project, projectCwd: dir,
                                         body: t.body(for: types))
            print(err ?? "added: .claude/rules/\(t.id).md")
            exit(err == nil ? 0 : 1)
        }
        // Debug path: `airuncat --statusline status|install|remove` (R3 검증용 CLI)
        if let idx = args.firstIndex(of: "--statusline") {
            let sub = (idx + 1 < args.count) ? args[idx + 1] : "status"
            switch sub {
            case "install": print(StatuslineManager.install() ?? "install ok")
            case "remove":  print(StatuslineManager.remove() ?? "remove ok")
            default:
                switch StatuslineManager.status() {
                case .installed:        print("installed (airuncat)")
                case .foreign(let c):   print("foreign: \(c)")
                case .notInstalled:     print("not installed")
                }
            }
            exit(0)
        }
        // Debug path: `airuncat --hook-recipe list|install <id>|remove <id>` (R5 검증용 CLI)
        if let idx = args.firstIndex(of: "--hook-recipe") {
            let sub = (idx + 1 < args.count) ? args[idx + 1] : "list"
            let id  = (idx + 2 < args.count) ? args[idx + 2] : nil
            switch sub {
            case "install", "remove":
                guard let id, let recipe = HookRecipeManager.recipes.first(where: { $0.id == id }) else {
                    print("unknown recipe id"); exit(1)
                }
                let err = sub == "install" ? HookRecipeManager.install(recipe)
                                           : HookRecipeManager.uninstall(recipe)
                print(err ?? "\(sub) ok: \(recipe.id)")
                exit(err == nil ? 0 : 1)
            default:
                for r in HookRecipeManager.recipes {
                    print("\(HookRecipeManager.isInstalled(r) ? "[on] " : "[off]") \(r.id) — \(r.name) (\(r.event))")
                }
                exit(0)
            }
        }
        // Obsidian → ~/.airuncat 일회성 마이그레이션. 스캐너(읽기)에서 분리해 시작 시 1회만 수행.
        SkillManager.migrateFromObsidianIfNeeded()
        PromptManager.migrateFromObsidianIfNeeded()
        NotificationManager.shared.requestPermission()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store, tagStore: store.tagStore, usageStore: store.usageStore)
                .onAppear {
                    let s = store
                    appCtrl.registerShortcut {
                        QuickPalette.shared.show(sessions: s.sessions)
                    }
                }
        } label: {
            Image(nsImage: store.catImage)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Renders cat frames onto a light background so they can be eyeballed as a PNG.
enum DebugRender {
    static func contactSheet(to path: String) {
        let scale = 6.0
        let cellW = CatRenderer.canvas.width * scale
        let cellH = CatRenderer.canvas.height * scale

        var frames: [NSImage] = []
        for p in stride(from: 0.0, to: 3.6, by: 0.6) {
            frames.append(CatRenderer.image(phase: p, mode: .running(2)))
        }
        frames.append(CatRenderer.image(phase: 0.0, mode: .sleeping))
        // Bubble variants
        for p in stride(from: 0.0, to: 3.6, by: 0.6) {
            frames.append(CatRenderer.image(phase: p, mode: .running(2), waitingBubble: true))
        }
        frames.append(CatRenderer.image(phase: 0.0, mode: .sleeping, waitingBubble: true))

        let sheet = NSImage(size: NSSize(width: cellW * Double(frames.count), height: cellH))
        sheet.lockFocus()
        NSColor(white: 0.85, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: sheet.size.width, height: sheet.size.height)).fill()
        for (i, frame) in frames.enumerated() {
            let rect = NSRect(x: Double(i) * cellW, y: 0, width: cellW, height: cellH)
            frame.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        sheet.unlockFocus()

        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
