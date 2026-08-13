import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private let pasteCoordinator: PasteCoordinator
    private let launchAtLogin = LaunchAtLoginController()
    private let onSettingsChanged: () -> Void

    private let capacityValue = NSTextField(labelWithString: "")
    private let menuCountValue = NSTextField(labelWithString: "")
    private let popupCountValue = NSTextField(labelWithString: "")
    private let capacityStepper = NSStepper()
    private let menuCountStepper = NSStepper()
    private let popupCountStepper = NSStepper()
    private let appearancePopUp = NSPopUpButton()
    private let menuActionPopUp = NSPopUpButton()
    private let hotKeyRecorder = HotKeyRecorderButton()

    init(
        settings: AppSettings,
        pasteCoordinator: PasteCoordinator,
        onSettingsChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.pasteCoordinator = pasteCoordinator
        self.onSettingsChanged = onSettingsChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Copydalis Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        refreshValues()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        let title = NSTextField(labelWithString: "General")
        title.font = .boldSystemFont(ofSize: 16)

        hotKeyRecorder.bezelStyle = .rounded
        hotKeyRecorder.onRecorded = { [weak self] configuration in
            self?.settings.hotKey = configuration
            self?.changed()
        }
        let hotkey = labeledControl(title: "Global shortcut", control: hotKeyRecorder)
        let login = checkbox("Launch at login", state: launchAtLogin.isEnabled, action: #selector(loginChanged(_:)))

        let capacity = makeStepperRow(
            title: "History capacity",
            valueLabel: capacityValue,
            stepper: capacityStepper,
            minimum: 10,
            maximum: 9_999,
            action: #selector(capacityChanged(_:))
        )
        let menuCount = makeStepperRow(
            title: "Items shown in menu",
            valueLabel: menuCountValue,
            stepper: menuCountStepper,
            minimum: 1,
            maximum: 30,
            action: #selector(menuCountChanged(_:))
        )
        let popupCount = makeStepperRow(
            title: "Rows shown in popup",
            valueLabel: popupCountValue,
            stepper: popupCountStepper,
            minimum: 3,
            maximum: 20,
            action: #selector(popupCountChanged(_:))
        )

        appearancePopUp.addItems(withTitles: AppAppearance.allCases.map(\.displayName))
        appearancePopUp.target = self
        appearancePopUp.action = #selector(appearanceChanged(_:))
        let appearanceRow = labeledControl(title: "Appearance", control: appearancePopUp)

        menuActionPopUp.addItems(withTitles: ["Paste", "Copy only"])
        menuActionPopUp.target = self
        menuActionPopUp.action = #selector(menuActionChanged(_:))
        let menuActionRow = labeledControl(title: "Clicking a menu item", control: menuActionPopUp)

        let wrap = checkbox("Wrap around history", state: settings.wraparound, action: #selector(wrapChanged(_:)))
        let duplicate = checkbox("Remove exact duplicates", state: settings.removeExactDuplicates, action: #selector(duplicatesChanged(_:)))
        let moveToNewest = checkbox("Move pasted item to newest", state: settings.movePastedToNewest, action: #selector(moveToNewestChanged(_:)))
        let arrows = checkbox("Use left/right arrow aliases", state: settings.horizontalArrowAliases, action: #selector(arrowsChanged(_:)))
        let metadata = checkbox("Show source application and time", state: settings.showSourceMetadata, action: #selector(metadataChanged(_:)))

        let privacy = NSTextField(labelWithString: "Privacy & Security")
        privacy.font = .boldSystemFont(ofSize: 16)
        let privacyText = NSTextField(wrappingLabelWithString: "History is encrypted locally. Copydalis has no cloud synchronization, analytics, or network entitlement. Automatic paste requires Accessibility permission.")
        privacyText.textColor = .secondaryLabelColor
        let permission = NSButton(title: "Request Accessibility Permission", target: self, action: #selector(requestPermission))

        let stack = NSStackView(views: [
            title, hotkey, login, capacity, menuCount, popupCount, appearanceRow, menuActionRow,
            wrap, duplicate, moveToNewest, arrows, metadata,
            privacy, privacyText, permission
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24)
        ])
        refreshValues()
    }

    private func makeStepperRow(
        title: String,
        valueLabel: NSTextField,
        stepper: NSStepper,
        minimum: Double,
        maximum: Double,
        action: Selector
    ) -> NSView {
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = 1
        stepper.target = self
        stepper.action = action
        stepper.identifier = NSUserInterfaceItemIdentifier(title)
        let controls = NSStackView(views: [valueLabel, stepper])
        controls.orientation = .horizontal
        return labeledControl(title: title, control: controls)
    }

    private func labeledControl(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func checkbox(_ title: String, state: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = state ? .on : .off
        return button
    }

    private func refreshValues() {
        capacityValue.stringValue = String(settings.historyCapacity)
        menuCountValue.stringValue = String(settings.menuItemCount)
        popupCountValue.stringValue = String(settings.popupRowCount)
        capacityStepper.integerValue = settings.historyCapacity
        menuCountStepper.integerValue = settings.menuItemCount
        popupCountStepper.integerValue = settings.popupRowCount
        hotKeyRecorder.setConfiguration(settings.hotKey)
        if let index = AppAppearance.allCases.firstIndex(of: settings.appearance) {
            appearancePopUp.selectItem(at: index)
        }
        menuActionPopUp.selectItem(at: settings.menuSelectionAction == .paste ? 0 : 1)
    }

    @objc private func capacityChanged(_ sender: NSStepper) {
        settings.historyCapacity = sender.integerValue
        changed()
    }
    @objc private func menuCountChanged(_ sender: NSStepper) {
        settings.menuItemCount = sender.integerValue
        changed()
    }
    @objc private func popupCountChanged(_ sender: NSStepper) {
        settings.popupRowCount = sender.integerValue
        changed()
    }
    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        settings.appearance = AppAppearance.allCases[safe: sender.indexOfSelectedItem] ?? .system
        changed()
    }
    @objc private func menuActionChanged(_ sender: NSPopUpButton) {
        settings.menuSelectionAction = sender.indexOfSelectedItem == 0 ? .paste : .copyOnly
        changed()
    }
    @objc private func wrapChanged(_ sender: NSButton) { settings.wraparound = sender.state == .on; changed() }
    @objc private func duplicatesChanged(_ sender: NSButton) { settings.removeExactDuplicates = sender.state == .on; changed() }
    @objc private func moveToNewestChanged(_ sender: NSButton) { settings.movePastedToNewest = sender.state == .on; changed() }
    @objc private func arrowsChanged(_ sender: NSButton) { settings.horizontalArrowAliases = sender.state == .on; changed() }
    @objc private func metadataChanged(_ sender: NSButton) { settings.showSourceMetadata = sender.state == .on; changed() }
    @objc private func requestPermission() { pasteCoordinator.requestAccessibilityPermission() }
    @objc private func loginChanged(_ sender: NSButton) {
        do {
            try launchAtLogin.setEnabled(sender.state == .on)
        } catch {
            sender.state = launchAtLogin.isEnabled ? .on : .off
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Launch at Login could not be updated."
            alert.informativeText = "Check Login Items in System Settings and try again."
            alert.runModal()
        }
    }

    private func changed() {
        refreshValues()
        onSettingsChanged()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
