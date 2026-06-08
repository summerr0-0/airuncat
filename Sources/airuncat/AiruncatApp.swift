import SwiftUI
import AppKit

@main
struct AiruncatApp: App {
    @StateObject private var store = SessionStore()

    init() {
        // Debug path: `airuncat --render-frames [outPath]` dumps a contact sheet and exits.
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--render-frames") {
            _ = NSApplication.shared   // ensure AppKit is initialized for lockFocus
            let out = (idx + 1 < args.count) ? args[idx + 1] : "/tmp/airuncat_frames.png"
            DebugRender.contactSheet(to: out)
            print("wrote \(out)")
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store, tagStore: store.tagStore)
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
