import AppKit
import SwiftUI

struct BrowseFilesButton: NSViewRepresentable {
    var title: String = "Browse Files..."
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeNSView(context: Context) -> NativeBrowseButton {
        let button = NativeBrowseButton(title: title)
        button.target = context.coordinator
        button.action = #selector(Coordinator.open)
        button.apply(palette: context.environment.palette)
        return button
    }

    func updateNSView(_ nsView: NativeBrowseButton, context: Context) {
        context.coordinator.onPick = onPick
        nsView.titleText = title
        nsView.target = context.coordinator
        nsView.action = #selector(Coordinator.open)
        nsView.apply(palette: context.environment.palette)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeBrowseButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        @objc func open(_ sender: Any?) {
            let window = (sender as? NSView)?.window
            FilePickerService.openFiles(from: window) { [weak self] urls in
                guard let self, !urls.isEmpty else { return }
                DispatchQueue.main.async {
                    self.onPick(urls)
                }
            }
        }
    }
}

final class NativeBrowseButton: NSButton {
    var titleText: String = "Browse Files..." {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    private var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    private var palette = Palette(scheme: .dark)
    private let horizontalPadding: CGFloat = 28
    private let verticalPadding: CGFloat = 12

    init(title: String) {
        super.init(frame: .zero)
        self.titleText = title
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        isBordered = false
        isTransparent = false
        focusRingType = .none
        imagePosition = .noImage
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let text = titleSize()
        return NSSize(
            width: ceil(text.width + horizontalPadding * 2),
            height: ceil(text.height + verticalPadding * 2)
        )
    }

    override var alignmentRectInsets: NSEdgeInsets { .init() }

    func apply(palette: Palette) {
        self.palette = palette
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
        if let window {
            WindowInteraction.prepare(window)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        NSCursor.arrow.set()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let pressed = isHighlighted

        if hovered || pressed {
            NSGradient(
                starting: NSColor(Palette.blue),
                ending: NSColor(Palette.purple)
            )?.draw(in: path, angle: 0)
        } else {
            NSColor(palette.fieldFill).setFill()
            path.fill()
        }

        NSColor(hovered ? Palette.blue.opacity(0.9) : palette.border).setStroke()
        path.lineWidth = hovered ? 1.5 : 1
        path.stroke()

        let color = NSColor((hovered || pressed) ? palette.onAccent : palette.textPrimary)
        let text = NSAttributedString(string: titleText, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: color
        ])
        let size = text.size()
        text.draw(at: NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ))
    }

    private func titleSize() -> NSSize {
        (titleText as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold)
        ])
    }
}
