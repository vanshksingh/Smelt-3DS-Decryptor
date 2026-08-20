import AppKit
import SwiftUI

/// Sizes the SwiftUI hosting view to the window content rect.
/// Never force a layout pass from `layout()` — that deadlocks menus and pickers.
enum WindowInteraction {
    static func prepare(_ window: NSWindow, stealFirstResponder: Bool = false) {
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 840, height: 560)
        fillContentView(window)
        if stealFirstResponder, window.firstResponder == nil {
            window.makeFirstResponder(window.contentView)
        }
    }

    static func fillContentView(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        let size = window.contentRect(forFrameRect: window.frame).size
        guard size.width > 1, size.height > 1 else { return }
        content.autoresizingMask = [.width, .height]
        guard abs(content.frame.width - size.width) > 0.5
                || abs(content.frame.height - size.height) > 0.5 else {
            return
        }
        content.setFrameSize(size)
    }
}

struct WindowSyncView: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {}

    final class AnchorView: NSView {
        private var didPrepare = false
        private var resizeObserver: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            guard let window else { return }

            if !didPrepare {
                didPrepare = true
                WindowInteraction.prepare(window, stealFirstResponder: false)
            } else {
                WindowInteraction.fillContentView(window)
            }

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                WindowInteraction.fillContentView(window)
            }
        }

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }
    }
}
