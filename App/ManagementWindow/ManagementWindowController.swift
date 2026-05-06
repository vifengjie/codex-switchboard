import AppKit
import SwiftUI

@MainActor
final class ManagementWindowController {
    static let shared = ManagementWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let contentView = ManagementRootView()
            let hostingController = NSHostingController(rootView: contentView)
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "Codex Quota Manager"
            newWindow.setContentSize(NSSize(width: 860, height: 560))
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
