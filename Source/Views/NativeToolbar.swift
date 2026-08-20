import AppKit
import SwiftUI

struct ToolbarSnapshot: Equatable {
    var destinationTitle: String
    var suffix: String
    var format: OutputFormat
    var autoOpen: Bool
    var showConsole: Bool
    var hasDone: Bool
    var hasFiles: Bool
    var busy: Bool
}

/// Entire settings toolbar as one AppKit view. Built once; SwiftUI only pushes snapshots.
struct NativeToolbar: NSViewRepresentable {
    let settings: Settings
    let snapshot: ToolbarSnapshot
    let callbacks: HeaderCallbacks

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings, callbacks: callbacks)
    }

    func makeNSView(context: Context) -> ToolbarHostView {
        let view = ToolbarHostView(coordinator: context.coordinator)
        context.coordinator.host = view
        view.apply(snapshot, force: true)
        return view
    }

    func updateNSView(_ nsView: ToolbarHostView, context: Context) {
        context.coordinator.callbacks = callbacks
        nsView.apply(snapshot)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var host: ToolbarHostView?
        let settings: Settings
        var callbacks: HeaderCallbacks

        init(settings: Settings, callbacks: HeaderCallbacks) {
            self.settings = settings
            self.callbacks = callbacks
        }

        @objc func destinationMenu(_ sender: NSMenuItem) {
            switch sender.tag {
            case 1:
                DispatchQueue.main.async { self.callbacks.sameDestination() }
            case 2:
                DispatchQueue.main.async { self.callbacks.chooseDestination() }
            default:
                break
            }
        }

        @objc func formatChanged(_ sender: NSPopUpButton) {
            guard let raw = sender.selectedItem?.representedObject as? String,
                  let format = OutputFormat(rawValue: raw) else { return }
            guard settings.globalFormat != format else { return }
            settings.globalFormat = format
            DispatchQueue.main.async {
                self.callbacks.formatChanged(format)
            }
        }

        @objc func autoOpenToggled(_ sender: NSButton) {
            settings.autoOpen = sender.state == .on
        }

        @objc func consoleToggled(_ sender: NSButton) {
            settings.showConsole = sender.state == .on
        }

        @objc func clearDone(_ sender: Any?) {
            callbacks.clearDone()
        }

        @objc func clearAll(_ sender: Any?) {
            callbacks.clearAll()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            settings.suffix = field.stringValue
        }
    }
}

final class ToolbarHostView: NSView {
    private let coordinator: NativeToolbar.Coordinator

    private let stack = NSStackView()
    private let destinationButton = NSButton(title: "", target: nil, action: nil)
    private let suffixLabel = NSTextField(labelWithString: "Suffix:")
    private let suffixField = NSTextField(string: "")
    private let formatLabel = NSTextField(labelWithString: "Format:")
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let autoOpenToggle = NSButton(checkboxWithTitle: "Reveal in Finder", target: nil, action: nil)
    private let consoleToggle = NSButton(checkboxWithTitle: "Console", target: nil, action: nil)
    private let clearDoneButton = NSButton(title: "Clear Done", target: nil, action: nil)
    private let clearAllButton = NSButton(title: "Clear All", target: nil, action: nil)

    private var applied = ToolbarSnapshot(
        destinationTitle: "",
        suffix: "",
        format: .same,
        autoOpen: false,
        showConsole: false,
        hasDone: false,
        hasFiles: false,
        busy: false
    )

    init(coordinator: NativeToolbar.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 44)
    }

    func apply(_ snapshot: ToolbarSnapshot, force: Bool = false) {
        guard force || snapshot != applied else { return }

        if force || snapshot.destinationTitle != applied.destinationTitle {
            destinationButton.title = snapshot.destinationTitle
        }

        if force || snapshot.suffix != applied.suffix {
            if window?.firstResponder !== suffixField {
                suffixField.stringValue = snapshot.suffix
            }
        }

        if force || snapshot.format != applied.format {
            if formatPopup.titleOfSelectedItem != snapshot.format.rawValue {
                formatPopup.selectItem(withTitle: snapshot.format.rawValue)
            }
        }

        if force || snapshot.autoOpen != applied.autoOpen {
            autoOpenToggle.state = snapshot.autoOpen ? .on : .off
        }

        if force || snapshot.showConsole != applied.showConsole {
            consoleToggle.state = snapshot.showConsole ? .on : .off
        }

        if force || snapshot.hasDone != applied.hasDone {
            clearDoneButton.isHidden = !snapshot.hasDone
        }

        if force || snapshot.hasFiles != applied.hasFiles {
            clearAllButton.isHidden = !snapshot.hasFiles
        }

        if force || snapshot.busy != applied.busy {
            clearDoneButton.isEnabled = !snapshot.busy
            clearAllButton.isEnabled = !snapshot.busy
        }

        applied = snapshot
    }

    private func build() {
        wantsLayer = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configureDestinationButton()
        configureSuffixField()
        configureFormatPopup()
        configureToggles()
        configureActionButtons()

        stack.addArrangedSubview(destinationButton)
        stack.addArrangedSubview(makeGroup(suffixLabel, suffixField))
        stack.addArrangedSubview(makeGroup(formatLabel, formatPopup))
        stack.addArrangedSubview(autoOpenToggle)
        stack.addArrangedSubview(consoleToggle)
        stack.addArrangedSubview(clearDoneButton)
        stack.addArrangedSubview(clearAllButton)

        clearDoneButton.isHidden = true
        clearAllButton.isHidden = true
    }

    private func configureDestinationButton() {
        destinationButton.bezelStyle = .rounded
        destinationButton.controlSize = .small
        destinationButton.font = .systemFont(ofSize: 11, weight: .medium)
        destinationButton.setButtonType(.momentaryPushIn)

        let menu = NSMenu(title: "Destination")
        let same = NSMenuItem(title: "Same as Source", action: #selector(NativeToolbar.Coordinator.destinationMenu(_:)), keyEquivalent: "")
        same.target = coordinator
        same.tag = 1
        same.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)

        let choose = NSMenuItem(title: "Choose Custom Folder…", action: #selector(NativeToolbar.Coordinator.destinationMenu(_:)), keyEquivalent: "")
        choose.target = coordinator
        choose.tag = 2
        choose.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)

        menu.addItem(same)
        menu.addItem(choose)
        destinationButton.menu = menu
    }

    private func configureSuffixField() {
        styleLabel(suffixLabel)
        suffixField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        suffixField.controlSize = .small
        suffixField.bezelStyle = .roundedBezel
        suffixField.focusRingType = .none
        suffixField.delegate = coordinator
        suffixField.translatesAutoresizingMaskIntoConstraints = false
        suffixField.widthAnchor.constraint(equalToConstant: 92).isActive = true
    }

    private func configureFormatPopup() {
        styleLabel(formatLabel)
        formatPopup.controlSize = .small
        formatPopup.font = .systemFont(ofSize: 11, weight: .medium)
        formatPopup.autoenablesItems = false
        formatPopup.target = coordinator
        formatPopup.action = #selector(NativeToolbar.Coordinator.formatChanged(_:))
        formatPopup.removeAllItems()
        for format in OutputFormat.allCases {
            formatPopup.addItem(withTitle: format.rawValue)
            formatPopup.lastItem?.representedObject = format.rawValue
        }
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        formatPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
    }

    private func configureToggles() {
        for toggle in [autoOpenToggle, consoleToggle] {
            toggle.font = .systemFont(ofSize: 11, weight: .medium)
            toggle.target = coordinator
        }
        autoOpenToggle.action = #selector(NativeToolbar.Coordinator.autoOpenToggled(_:))
        consoleToggle.action = #selector(NativeToolbar.Coordinator.consoleToggled(_:))
    }

    private func configureActionButtons() {
        for button in [clearDoneButton, clearAllButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: .semibold)
            button.target = coordinator
        }
        clearDoneButton.action = #selector(NativeToolbar.Coordinator.clearDone(_:))
        clearAllButton.action = #selector(NativeToolbar.Coordinator.clearAll(_:))
    }

    private func styleLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
    }

    private func makeGroup(_ label: NSTextField, _ control: NSView) -> NSStackView {
        let group = NSStackView(views: [label, control])
        group.orientation = .horizontal
        group.spacing = 6
        group.alignment = .centerY
        return group
    }
}
