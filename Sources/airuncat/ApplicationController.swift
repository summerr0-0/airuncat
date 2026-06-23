import AppKit

@MainActor
final class ApplicationController: ObservableObject {
    private var tap: CFMachPort?

    func registerShortcut(handler: @escaping @Sendable @MainActor () -> Void) {
        guard tap == nil else { return }
        tap = GlobalShortcut.register(handler: handler)
        if tap == nil {
            openAccessibilitySettings()
        }
    }

    func unregisterShortcut() {
        if let t = tap { GlobalShortcut.unregister(t) }
        tap = nil
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
