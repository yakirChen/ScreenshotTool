//
//  CaptureControlBar.swift
//  ScreenshotTool
//

import Cocoa

enum CaptureMode: Int {
    case area = 0
    case window = 1
    case fullScreen = 2
}

protocol CaptureControlBarDelegate: AnyObject {
    func controlBar(_ bar: CaptureControlBar, didSelect mode: CaptureMode)
    func controlBarDidTapCapture(_ bar: CaptureControlBar)
    func controlBarDidTapCancel(_ bar: CaptureControlBar)
    func controlBarDidChangeOptions(_ bar: CaptureControlBar)
}

/// macOS 原生 ⌘⇧5 风格的底部控制栏
/// 模式切换 · 选项菜单 · 取消 · 捕捉
final class CaptureControlBar: NSView {

    weak var delegate: CaptureControlBarDelegate?

    var mode: CaptureMode = .area {
        didSet { segmented?.selectedSegment = mode.rawValue; updateCaptureButton() }
    }

    private var segmented: NSSegmentedControl!
    private var optionsButton: NSButton!
    private var captureButton: NSButton!
    private var cancelButton: NSButton!

    static let height: CGFloat = 64

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBackground()
        setupControls()
        updateCaptureButton()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var allowsVibrancy: Bool { true }

    private func setupBackground() {
        wantsLayer = true
        let visual = NSVisualEffectView(frame: bounds)
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 14
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]
        addSubview(visual)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    private func setupControls() {
        // 取消按钮（X）
        cancelButton = NSButton()
        cancelButton.bezelStyle = .circular
        cancelButton.isBordered = false
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "取消")
        cancelButton.contentTintColor = NSColor.secondaryLabelColor
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        // 模式切换
        segmented = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "区域") ?? NSImage(),
            NSImage(systemSymbolName: "macwindow", accessibilityDescription: "窗口") ?? NSImage(),
            NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: "全屏") ?? NSImage()
        ], trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        segmented.setToolTip("区域截图", forSegment: 0)
        segmented.setToolTip("窗口截图", forSegment: 1)
        segmented.setToolTip("全屏截图", forSegment: 2)
        segmented.selectedSegment = 0
        segmented.segmentStyle = .texturedRounded
        segmented.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmented)

        // 选项
        optionsButton = NSButton()
        optionsButton.title = "选项"
        optionsButton.bezelStyle = .texturedRounded
        optionsButton.target = self
        optionsButton.action = #selector(optionsTapped)
        optionsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(optionsButton)

        // 捕捉
        captureButton = NSButton()
        captureButton.title = "捕捉"
        captureButton.bezelStyle = .rounded
        captureButton.keyEquivalent = "\r"
        captureButton.target = self
        captureButton.action = #selector(captureTapped)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captureButton)

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 22),
            cancelButton.heightAnchor.constraint(equalToConstant: 22),

            segmented.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 14),
            segmented.centerYAnchor.constraint(equalTo: centerYAnchor),

            optionsButton.leadingAnchor.constraint(equalTo: segmented.trailingAnchor, constant: 18),
            optionsButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            captureButton.leadingAnchor.constraint(equalTo: optionsButton.trailingAnchor, constant: 14),
            captureButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            captureButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            captureButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])
    }

    static func preferredSize() -> NSSize {
        return NSSize(width: 460, height: height)
    }

    private func updateCaptureButton() {
        switch mode {
        case .fullScreen:
            captureButton.title = "捕捉全屏"
        case .window:
            captureButton.title = "选窗口"
        case .area:
            captureButton.title = "捕捉"
        }
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard let m = CaptureMode(rawValue: sender.selectedSegment) else { return }
        mode = m
        delegate?.controlBar(self, didSelect: m)
    }

    @objc private func captureTapped() { delegate?.controlBarDidTapCapture(self) }
    @objc private func cancelTapped() { delegate?.controlBarDidTapCancel(self) }

    @objc private func optionsTapped() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let prefs = PreferencesManager.shared

        // 保存位置
        let locItem = NSMenuItem(title: "保存位置", action: nil, keyEquivalent: "")
        let locMenu = NSMenu()
        let desktop = NSHomeDirectory() + "/Desktop"
        let documents = NSHomeDirectory() + "/Documents"
        let current = prefs.defaultSaveLocation
        addLocationItem(to: locMenu, title: "桌面", path: desktop, current: current)
        addLocationItem(to: locMenu, title: "文稿", path: documents, current: current)
        locMenu.addItem(.separator())
        let other = NSMenuItem(title: "其他位置…", action: #selector(chooseOtherLocation), keyEquivalent: "")
        other.target = self
        locMenu.addItem(other)
        locItem.submenu = locMenu
        menu.addItem(locItem)

        // 倒计时
        let timerItem = NSMenuItem(title: "倒计时", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        addTimerItem(to: timerMenu, title: "无", seconds: 0, current: prefs.captureTimerSeconds)
        addTimerItem(to: timerMenu, title: "5 秒", seconds: 5, current: prefs.captureTimerSeconds)
        addTimerItem(to: timerMenu, title: "10 秒", seconds: 10, current: prefs.captureTimerSeconds)
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)

        menu.addItem(.separator())

        addToggleItem(to: menu, title: "记住上次选区", selector: #selector(toggleRememberSelection),
                      isOn: prefs.rememberLastSelection)
        addToggleItem(to: menu, title: "显示浮动缩略图", selector: #selector(toggleFloatingThumbnail),
                      isOn: prefs.showFloatingThumbnail)
        addToggleItem(to: menu, title: "显示鼠标指针", selector: #selector(toggleMouseCursor),
                      isOn: prefs.captureMouseCursor)
        addToggleItem(to: menu, title: "窗口模式单击即捕捉", selector: #selector(toggleWindowSingleClickCapture),
                      isOn: prefs.windowCaptureSingleClick)
        addToggleItem(to: menu, title: "截图后复制到剪贴板", selector: #selector(toggleClipboard),
                      isOn: prefs.copyToClipboardOnCapture)
        addToggleItem(to: menu, title: "保存到历史", selector: #selector(toggleHistory),
                      isOn: prefs.saveToHistory)

        let origin = NSPoint(x: optionsButton.frame.minX, y: optionsButton.frame.maxY + 4)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    // MARK: - Menu helpers

    private func addLocationItem(to menu: NSMenu, title: String, path: String, current: String) {
        let item = NSMenuItem(title: title, action: #selector(selectLocation(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = path
        item.state = (path == current) ? .on : .off
        menu.addItem(item)
    }

    private func addTimerItem(to menu: NSMenu, title: String, seconds: Int, current: Int) {
        let item = NSMenuItem(title: title, action: #selector(selectTimer(_:)), keyEquivalent: "")
        item.target = self
        item.tag = seconds
        item.state = (seconds == current) ? .on : .off
        menu.addItem(item)
    }

    private func addToggleItem(to menu: NSMenu, title: String, selector: Selector, isOn: Bool) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        menu.addItem(item)
    }

    @objc private func selectLocation(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        PreferencesManager.shared.defaultSaveLocation = path
        delegate?.controlBarDidChangeOptions(self)
    }

    @objc private func chooseOtherLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            PreferencesManager.shared.defaultSaveLocation = url.path
            delegate?.controlBarDidChangeOptions(self)
        }
    }

    @objc private func selectTimer(_ sender: NSMenuItem) {
        PreferencesManager.shared.captureTimerSeconds = sender.tag
        delegate?.controlBarDidChangeOptions(self)
    }

    @objc private func toggleRememberSelection() {
        PreferencesManager.shared.rememberLastSelection.toggle()
        delegate?.controlBarDidChangeOptions(self)
    }

    @objc private func toggleFloatingThumbnail() {
        PreferencesManager.shared.showFloatingThumbnail.toggle()
        delegate?.controlBarDidChangeOptions(self)
    }

    @objc private func toggleMouseCursor() {
        PreferencesManager.shared.captureMouseCursor.toggle()
        delegate?.controlBarDidChangeOptions(self)
    }

    @objc private func toggleWindowSingleClickCapture() {
        PreferencesManager.shared.windowCaptureSingleClick.toggle()
        delegate?.controlBarDidChangeOptions(self)
    }

    @objc private func toggleClipboard() {
        PreferencesManager.shared.copyToClipboardOnCapture.toggle()
        delegate?.controlBarDidChangeOptions(self)
    }

    @objc private func toggleHistory() {
        PreferencesManager.shared.saveToHistory.toggle()
        delegate?.controlBarDidChangeOptions(self)
    }
}
