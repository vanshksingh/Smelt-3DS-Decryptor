import AppKit
import SwiftUI

/// Sizes the SwiftUI hosting view to the window content rect.
/// Do not steal first responder after the first attach — that breaks
/// buttons, text fields, and open panels.
enum WindowInteraction {
    static func prepare(_ window: NSWindow, stealFirstResponder: Bool = false) {
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 840, height: 560)
        fillContentView(window)
        refreshTracking(in: window.contentView)
        if stealFirstResponder {
            window.makeFirstResponder(window.contentView)
        }
    }

    static func fillContentView(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        let size = window.contentRect(forFrameRect: window.frame).size
        guard size.width > 1, size.height > 1 else { return }
        content.autoresizingMask = [.width, .height]
        if abs(content.frame.width - size.width) > 0.5 || abs(content.frame.height - size.height) > 0.5 {
            content.setFrameSize(size)
        }
        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
        content.needsDisplay = true
    }

    static func refreshTracking(in view: NSView?) {
        guard let view else { return }
        view.updateTrackingAreas()
        view.subviews.forEach { refreshTracking(in: $0) }
    }
}

struct WindowSyncView: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {}

    final class AnchorView: NSView {
        private var didPrepare = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !didPrepare else { return }
            didPrepare = true
            WindowInteraction.prepare(window, stealFirstResponder: true)
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                WindowInteraction.fillContentView(window)
                WindowInteraction.refreshTracking(in: window.contentView)
            }
        }

        override func layout() {
            super.layout()
            if let window {
                WindowInteraction.fillContentView(window)
            }
        }
    }
}
