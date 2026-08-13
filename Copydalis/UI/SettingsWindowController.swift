import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum Category: String, CaseIterable {
        case general
        case history
        case appearance
        case privacy

        var title: String {
            switch self {
            case .general: "General"
            case .history: "History"
            case .appearance: "Appearance"
            case .privacy: "Privacy & Security"
            }
        }

        var subtitle: String {
            switch self {
            case .general: "Choose how Copydalis starts and how you open clipboard history."
            case .history: "Control retention, navigation, and what happens after selecting an entry."
            case .appearance: "Adjust the centered popup without changing the menu-bar menu."
            case .privacy: "Review local protection and the permission used for automatic paste."
            }
        }

        var symbolName: String {
            switch self {
            case .general: "gearshape"
            case .history: "clock.arrow.circlepath"
            case .appearance: "paintbrush"
            case .privacy: "lock.shield"
            }
        }

        var contentHeight: CGFloat {
            switch self {
            case .general: 320
            case .history: 470
            case .appearance: 340
            case .privacy: 400
            }
        }

        var toolbarIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier("settings.\(rawValue)")
        }

        init?(toolbarIdentifier: NSToolbarItem.Identifier) {
            guard
                let category = Self.allCases.first(where: {
                    $0.toolbarIdentifier == toolbarIdentifier
                })
            else { return nil }
            self = category
        }
    }

    private static let toolbarIdentifier = NSToolbar.Identifier("CopydalisSettingsToolbar")
    private static let contentWidth: CGFloat = 640

    private let settings: AppSettings
    private let pasteCoordinator: PasteCoordinator
    private let launchAtLogin = LaunchAtLoginController()
    private let onSettingsChanged: () -> Void
    private let onHotKeyRecordingStateChanged: (Bool) -> Void

    private let pageHost = NSView()
    private var pages: [Category: NSView] = [:]
    private var selectedCategory: Category = .general

    private let capacityValue = NSTextField(labelWithString: "")
    private let menuCountValue = NSTextField(labelWithString: "")
    private let popupCountValue = NSTextField(labelWithString: "")
    private let capacityStepper = NSStepper()
    private let menuCountStepper = NSStepper()
    private let popupCountStepper = NSStepper()
    private let appearancePopUp = NSPopUpButton()
    private let menuActionPopUp = NSPopUpButton()
    private let hotKeyRecorder = HotKeyRecorderButton()
    private let popupOpacitySlider = NSSlider()
    private let popupOpacityValue = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(wrappingLabelWithString: "")
    private let launchAtLoginButton = NSButton()
    private let wrapButton = NSButton()
    private let duplicateButton = NSButton()
    private let moveToNewestButton = NSButton()
    private let arrowsButton = NSButton()
    private let metadataButton = NSButton()
    private lazy var permissionButton = NSButton(
        title: "Request Accessibility Permission",
        target: self,
        action: #selector(requestPermission)
    )

    init(
        settings: AppSettings,
        pasteCoordinator: PasteCoordinator,
        onHotKeyRecordingStateChanged: @escaping (Bool) -> Void,
        onSettingsChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.pasteCoordinator = pasteCoordinator
        self.onHotKeyRecordingStateChanged = onHotKeyRecordingStateChanged
        self.onSettingsChanged = onSettingsChanged
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.contentWidth,
                height: Category.general.contentHeight
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Copydalis Settings"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self
        configureControls()
        configureToolbar()
        buildInterface()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        refreshValues()
        showCategory(selectedCategory)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        hotKeyRecorder.cancelRecording()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Category.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Category.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Category.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let category = Category(toolbarIdentifier: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = category.title
        item.paletteLabel = category.title
        item.image = NSImage(systemSymbolName: category.symbolName, accessibilityDescription: category.title)
        item.target = self
        item.action = #selector(categorySelected(_:))
        return item
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = selectedCategory.toolbarIdentifier
        window?.toolbar = toolbar
    }

    private func configureControls() {
        hotKeyRecorder.bezelStyle = .rounded
        hotKeyRecorder.onRecorded = { [weak self] configuration in
            self?.settings.hotKey = configuration
            self?.changed()
        }
        hotKeyRecorder.onRecordingStateChanged = { [weak self] isRecording in
            self?.onHotKeyRecordingStateChanged(isRecording)
        }

        configureStepper(
            capacityStepper,
            minimum: 10,
            maximum: 9_999,
            action: #selector(capacityChanged(_:))
        )
        configureStepper(
            menuCountStepper,
            minimum: 1,
            maximum: 30,
            action: #selector(menuCountChanged(_:))
        )
        configureStepper(
            popupCountStepper,
            minimum: 3,
            maximum: 20,
            action: #selector(popupCountChanged(_:))
        )

        appearancePopUp.addItems(withTitles: AppAppearance.allCases.map(\.displayName))
        appearancePopUp.target = self
        appearancePopUp.action = #selector(appearanceChanged(_:))
        appearancePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true

        menuActionPopUp.addItems(withTitles: ["Paste", "Copy only"])
        menuActionPopUp.target = self
        menuActionPopUp.action = #selector(menuActionChanged(_:))
        menuActionPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true

        popupOpacitySlider.minValue = PopupAppearanceConstraints.minimumOpacity
        popupOpacitySlider.maxValue = PopupAppearanceConstraints.maximumOpacity
        popupOpacitySlider.isContinuous = true
        popupOpacitySlider.numberOfTickMarks = 7
        popupOpacitySlider.allowsTickMarkValuesOnly = false
        popupOpacitySlider.target = self
        popupOpacitySlider.action = #selector(popupOpacityChanged(_:))
        popupOpacitySlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        popupOpacityValue.alignment = .right
        popupOpacityValue.widthAnchor.constraint(equalToConstant: 48).isActive = true

        configureCheckbox(
            launchAtLoginButton,
            title: "Launch Copydalis at login",
            action: #selector(loginChanged(_:))
        )
        configureCheckbox(
            wrapButton,
            title: "Wrap around at the beginning and end",
            action: #selector(wrapChanged(_:))
        )
        configureCheckbox(
            duplicateButton,
            title: "Remove exact duplicate entries",
            action: #selector(duplicatesChanged(_:))
        )
        configureCheckbox(
            moveToNewestButton,
            title: "Move a pasted entry to newest",
            action: #selector(moveToNewestChanged(_:))
        )
        configureCheckbox(
            arrowsButton,
            title: "Use left and right arrows as navigation aliases",
            action: #selector(arrowsChanged(_:))
        )
        configureCheckbox(
            metadataButton,
            title: "Show source application and time",
            action: #selector(metadataChanged(_:))
        )

        accessibilityStatus.font = .systemFont(ofSize: 12, weight: .medium)
        permissionButton.bezelStyle = .rounded
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageHost)
        NSLayoutConstraint.activate([
            pageHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        showCategory(.general)
    }

    private func page(for category: Category) -> NSView {
        if let page = pages[category] { return page }
        let page: NSView
        switch category {
        case .general:
            page = makePage(
                category: category,
                groups: [
                    makeGroup(
                        title: "Keyboard",
                        views: [
                            labeledControl(title: "Global shortcut", control: hotKeyRecorder),
                            helperText("Click the shortcut, then type a modified key. Press Escape to keep the previous shortcut.")
                        ]
                    ),
                    makeGroup(title: "Startup", views: [launchAtLoginButton])
                ]
            )
        case .history:
            page = makePage(
                category: category,
                groups: [
                    makeGroup(
                        title: "Storage and visibility",
                        views: [
                            stepperRow(title: "History capacity", valueLabel: capacityValue, stepper: capacityStepper),
                            stepperRow(title: "Items shown in menu", valueLabel: menuCountValue, stepper: menuCountStepper),
                            stepperRow(title: "Rows shown in popup", valueLabel: popupCountValue, stepper: popupCountStepper)
                        ]
                    ),
                    makeGroup(
                        title: "Selection behavior",
                        views: [
                            labeledControl(title: "Clicking a menu item", control: menuActionPopUp),
                            wrapButton,
                            duplicateButton,
                            moveToNewestButton,
                            arrowsButton
                        ]
                    )
                ]
            )
        case .appearance:
            let opacityControls = NSStackView(views: [popupOpacitySlider, popupOpacityValue])
            opacityControls.orientation = .horizontal
            opacityControls.alignment = .centerY
            opacityControls.spacing = 8
            page = makePage(
                category: category,
                groups: [
                    makeGroup(
                        title: "Centered popup",
                        views: [
                            labeledControl(title: "Color scheme", control: appearancePopUp),
                            labeledControl(title: "Popup opacity", control: opacityControls),
                            helperText("Opacity applies only to the centered clipboard popup. The menu-bar menu remains unchanged.")
                        ]
                    ),
                    makeGroup(title: "Entry details", views: [metadataButton])
                ]
            )
        case .privacy:
            page = makePage(
                category: category,
                groups: [
                    makeGroup(
                        title: "Local protection",
                        views: [
                            bodyText("Clipboard history is encrypted locally with a device-only Keychain key. Copydalis has no cloud synchronization, analytics, or network functionality."),
                            bodyText("Clearing history removes all stored entries and rotates the encryption key. The current macOS clipboard remains outside that operation.")
                        ]
                    ),
                    makeGroup(
                        title: "Automatic paste",
                        views: [
                            bodyText("Accessibility is used only to send the final Command-V to the verified target application."),
                            accessibilityStatus,
                            permissionButton
                        ]
                    )
                ]
            )
        }
        pages[category] = page
        return page
    }

    private func makePage(category: Category, groups: [NSView]) -> NSView {
        let page = NSView()
        let title = NSTextField(labelWithString: category.title)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: category.subtitle)
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle] + groups)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(22, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -24)
        ])
        return page
    }

    private func makeGroup(title: String, views: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        let surface = NSVisualEffectView()
        surface.material = .contentBackground
        surface.blendingMode = .withinWindow
        surface.state = .active
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 10
        surface.layer?.masksToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: views)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 11
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setContentHuggingPriority(.required, for: .vertical)
        contentStack.setContentCompressionResistancePriority(.required, for: .vertical)
        surface.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -14),
            surface.widthAnchor.constraint(equalToConstant: 584),
            surface.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])

        let group = NSStackView(views: [titleLabel, surface])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 5
        return group
    }

    private func labeledControl(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .left
        label.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func stepperRow(
        title: String,
        valueLabel: NSTextField,
        stepper: NSStepper
    ) -> NSView {
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let controls = NSStackView(views: [valueLabel, stepper])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6
        return labeledControl(title: title, control: controls)
    }

    private func helperText(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.maximumNumberOfLines = 2
        label.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return label
    }

    private func bodyText(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        label.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return label
    }

    private func configureStepper(
        _ stepper: NSStepper,
        minimum: Double,
        maximum: Double,
        action: Selector
    ) {
        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = 1
        stepper.target = self
        stepper.action = action
    }

    private func configureCheckbox(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.setButtonType(.switch)
        button.target = self
        button.action = action
    }

    private func refreshValues() {
        capacityValue.stringValue = String(settings.historyCapacity)
        menuCountValue.stringValue = String(settings.menuItemCount)
        popupCountValue.stringValue = String(settings.popupRowCount)
        capacityStepper.integerValue = settings.historyCapacity
        menuCountStepper.integerValue = settings.menuItemCount
        popupCountStepper.integerValue = settings.popupRowCount
        popupOpacitySlider.doubleValue = settings.popupOpacity
        popupOpacityValue.stringValue = "\(Int((settings.popupOpacity * 100).rounded()))%"
        hotKeyRecorder.setConfiguration(settings.hotKey)
        launchAtLoginButton.state = launchAtLogin.isEnabled ? .on : .off
        wrapButton.state = settings.wraparound ? .on : .off
        duplicateButton.state = settings.removeExactDuplicates ? .on : .off
        moveToNewestButton.state = settings.movePastedToNewest ? .on : .off
        arrowsButton.state = settings.horizontalArrowAliases ? .on : .off
        metadataButton.state = settings.showSourceMetadata ? .on : .off
        if let index = AppAppearance.allCases.firstIndex(of: settings.appearance) {
            appearancePopUp.selectItem(at: index)
        }
        menuActionPopUp.selectItem(at: settings.menuSelectionAction == .paste ? 0 : 1)
        refreshAccessibilityStatus()
    }

    private func showCategory(_ category: Category) {
        selectedCategory = category
        hotKeyRecorder.cancelRecording()
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        let page = page(for: category)
        page.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            page.topAnchor.constraint(equalTo: pageHost.topAnchor),
            page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)
        ])
        window?.toolbar?.selectedItemIdentifier = category.toolbarIdentifier
        resizeWindow(for: category)
    }

    private func resizeWindow(for category: Category) {
        guard let window else { return }
        let desiredContentRect = NSRect(
            origin: .zero,
            size: NSSize(
                width: Self.contentWidth,
                height: category.contentHeight
            )
        )
        let desiredFrame = window.frameRect(forContentRect: desiredContentRect)
        let currentFrame = window.frame
        let frame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.maxY - desiredFrame.height,
            width: desiredFrame.width,
            height: desiredFrame.height
        )
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    @objc private func categorySelected(_ sender: NSToolbarItem) {
        guard let category = Category(toolbarIdentifier: sender.itemIdentifier) else { return }
        showCategory(category)
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

    @objc private func popupOpacityChanged(_ sender: NSSlider) {
        settings.popupOpacity = sender.doubleValue
        changed()
    }

    @objc private func menuActionChanged(_ sender: NSPopUpButton) {
        settings.menuSelectionAction = sender.indexOfSelectedItem == 0 ? .paste : .copyOnly
        changed()
    }

    @objc private func wrapChanged(_ sender: NSButton) {
        settings.wraparound = sender.state == .on
        changed()
    }

    @objc private func duplicatesChanged(_ sender: NSButton) {
        settings.removeExactDuplicates = sender.state == .on
        changed()
    }

    @objc private func moveToNewestChanged(_ sender: NSButton) {
        settings.movePastedToNewest = sender.state == .on
        changed()
    }

    @objc private func arrowsChanged(_ sender: NSButton) {
        settings.horizontalArrowAliases = sender.state == .on
        changed()
    }

    @objc private func metadataChanged(_ sender: NSButton) {
        settings.showSourceMetadata = sender.state == .on
        changed()
    }

    @objc private func requestPermission() {
        pasteCoordinator.requestAccessibilityPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.refreshAccessibilityStatus()
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshAccessibilityStatus()
    }

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

    private func refreshAccessibilityStatus() {
        let trusted = pasteCoordinator.isAccessibilityTrusted
        accessibilityStatus.stringValue = trusted
            ? "Accessibility: Granted"
            : "Accessibility: Not granted — enable Copydalis in System Settings, then relaunch."
        accessibilityStatus.textColor = trusted ? .systemGreen : .systemOrange
        permissionButton.isEnabled = !trusted
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
