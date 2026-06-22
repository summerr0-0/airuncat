import CoreGraphics
import AppKit

// kVK_Space = 0x31 (Carbon keycode, stable across macOS versions)
private let kVKSpace: Int64 = 0x31

private final class HandlerBox {
    let fn: @MainActor () -> Void
    init(_ fn: @escaping @MainActor () -> Void) { self.fn = fn }
}

@MainActor
enum GlobalShortcut {

    static func register(handler: @escaping @MainActor () -> Void) -> CFMachPort? {
        let box = HandlerBox(handler)
        let ctx = Unmanaged.passRetained(box)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard type == .keyDown,
                      event.getIntegerValueField(.keyboardEventKeycode) == kVKSpace,
                      event.flags.contains(.maskAlternate),
                      !event.flags.contains(.maskCommand),
                      !event.flags.contains(.maskControl),
                      !event.flags.contains(.maskShift) else {
                    return Unmanaged.passRetained(event)
                }
                if let info = userInfo {
                    let b = Unmanaged<HandlerBox>.fromOpaque(info).takeUnretainedValue()
                    DispatchQueue.main.async { b.fn() }
                }
                return nil  // consume the event — prevents Spotlight from receiving ⌥Space
            },
            userInfo: ctx.toOpaque()
        )

        guard let tap else {
            ctx.release()
            return nil
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // ctx is retained for the tap's lifetime; released in unregister
        _ = ctx  // suppress "result of call is unused" if any
        return tap
    }

    static func unregister(_ tap: CFMachPort) {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        // HandlerBox is retained by the C tap; invalidation releases the run loop source
        // but the box itself leaks here by design (app-lifetime registration).
    }
}
