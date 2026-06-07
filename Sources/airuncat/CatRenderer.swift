import AppKit

/// Drawing mode for the menu bar cat.
enum CatMode: Equatable {
    case running(Int)   // associated value = how many sessions are busy (drives speed)
    case sleeping       // nothing is working -> the cat naps
}

/// Renders a small silhouette cat as a *template* NSImage, frame by frame.
/// Everything is drawn with vectors so we can animate continuously by phase
/// instead of shipping sprite assets. Template image => auto light/dark tint.
struct CatRenderer {

    static let canvas = NSSize(width: 26, height: 18)

    /// Build one frame. `phase` advances over time; legs + tail are derived from it.
    static func image(phase: Double, mode: CatMode) -> NSImage {
        let img = NSImage(size: canvas)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.black.setFill()
        NSColor.black.setStroke()

        switch mode {
        case .running:
            drawRunning(phase: phase)
        case .sleeping:
            drawSleeping(phase: phase)
        }

        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    // MARK: - Running pose

    private static func drawRunning(phase: Double) {
        let ground = 3.0

        // Body
        oval(NSRect(x: 4, y: 6, width: 13, height: 8))
        // Head
        oval(NSRect(x: 14.5, y: 7.5, width: 9, height: 9))
        // Ears
        triangle((16.2, 15.0), (17.4, 18.6), (18.8, 15.0))
        triangle((19.0, 15.0), (20.6, 18.6), (21.8, 15.0))

        // Tail: a thick curved stroke off the back, flicking with phase
        let wag = sin(phase * 0.9) * 2.0
        let tail = NSBezierPath()
        tail.lineWidth = 2.6
        tail.lineCapStyle = .round
        tail.lineJoinStyle = .round
        tail.move(to: p(4.5, 9))
        tail.curve(to: p(0.8, 13 + wag),
                   controlPoint1: p(1.5, 8),
                   controlPoint2: p(0.5, 10.5))
        tail.stroke()

        // Four legs: feet oscillate around their hips -> galloping.
        let hips: [Double] = [6.0, 8.5, 12.5, 15.0]
        let offs:  [Double] = [0.0, .pi, .pi, 0.0]   // diagonal trot
        let amp = 3.0, lift = 3.2, hipY = 7.0
        for i in 0..<4 {
            let ph = phase + offs[i]
            let fx = hips[i] + cos(ph) * amp
            let fy = ground + max(0.0, sin(ph)) * lift
            let leg = NSBezierPath()
            leg.lineWidth = 2.2
            leg.lineCapStyle = .round
            leg.move(to: p(hips[i], hipY))
            leg.line(to: p(fx, fy))
            leg.stroke()
        }

        // Eye (punched hole)
        punch(NSRect(x: 19.4, y: 10.6, width: 1.9, height: 1.9))
    }

    // MARK: - Sleeping pose

    private static func drawSleeping(phase: Double) {
        // A curled, sitting cat resting low.
        // Body (flatter, lower)
        oval(NSRect(x: 4, y: 4, width: 15, height: 7))
        // Head resting to the right
        oval(NSRect(x: 14.5, y: 4.5, width: 8.5, height: 8.5))
        // Ears (slightly drooped)
        triangle((15.8, 12.0), (16.8, 15.0), (18.2, 12.2))
        triangle((18.6, 12.2), (20.0, 15.0), (21.2, 12.0))

        // Tail curled around the body, gently waving (slow)
        let wag = sin(phase * 0.5) * 1.2
        let tail = NSBezierPath()
        tail.lineWidth = 2.6
        tail.lineCapStyle = .round
        tail.lineJoinStyle = .round
        tail.move(to: p(5, 6))
        tail.curve(to: p(11 + wag, 3.0),
                   controlPoint1: p(2, 3),
                   controlPoint2: p(7, 2.5))
        tail.stroke()

        // Tucked paws (short stubs)
        for hx in [7.5, 11.0] {
            let leg = NSBezierPath()
            leg.lineWidth = 2.2
            leg.lineCapStyle = .round
            leg.move(to: p(hx, 5))
            leg.line(to: p(hx + 1.2, 3.2))
            leg.stroke()
        }

        // Closed eye (punched thin line)
        punch(NSRect(x: 18.6, y: 8.2, width: 2.6, height: 0.9))
    }

    // MARK: - Primitives

    private static func p(_ x: Double, _ y: Double) -> NSPoint {
        NSPoint(x: x, y: y)
    }

    private static func oval(_ r: NSRect) {
        NSBezierPath(ovalIn: r).fill()
    }

    private static func triangle(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) {
        let path = NSBezierPath()
        path.move(to: p(a.0, a.1))
        path.line(to: p(b.0, b.1))
        path.line(to: p(c.0, c.1))
        path.close()
        path.fill()
    }

    /// Cut a transparent hole (for eyes) out of what's already drawn.
    private static func punch(_ r: NSRect) {
        let ctx = NSGraphicsContext.current
        let prev = ctx?.compositingOperation
        ctx?.compositingOperation = .clear
        NSBezierPath(ovalIn: r).fill()
        ctx?.compositingOperation = prev ?? .sourceOver
    }
}
