//
//  PreferencesWindowController.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

class PreferencesWindowController: NSWindowController {

    private static var current: PreferencesWindowController?

    static func show() {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = PreferencesWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        current = controller
    }

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 450, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "偏好设置"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let prefs = PreferencesManager.shared
        var y: CGFloat = 340
        let leftMargin: CGFloat = 20
        let labelWidth: CGFloat = 160
        let controlX: CGFloat = 190

        // 标题
        let titleLabel = NSTextField(labelWithString: "截图设置")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.frame = CGRect(x: leftMargin, y: y, width: 300, height: 24)
        contentView.addSubview(titleLabel)
        y -= 40

        // 截图后复制到剪贴板
        y = addCheckbox(
            to: contentView, y: y,
            title: "截图后自动复制到剪贴板",
            isChecked: prefs.copyToClipboardOnCapture,
            action: #selector(toggleCopyToClipboard(_:))
        )

        // 截图音效
        y = addCheckbox(
            to: contentView, y: y,
            title: "截图时播放音效",
            isChecked: prefs.playSoundOnCapture,
            action: #selector(togglePlaySound(_:))
        )

        // 保存到历史
        y = addCheckbox(
            to: contentView, y: y,
            title: "自动保存到截图历史",
            isChecked: prefs.saveToHistory,
            action: #selector(toggleSaveHistory(_:))
        )

        // 捕获鼠标指针
        y = addCheckbox(
            to: contentView, y: y,
            title: "截图包含鼠标指针",
            isChecked: prefs.captureMouseCursor,
            action: #selector(toggleCaptureCursor(_:))
        )

        y -= 15

        // 分隔线
        let separator = NSBox(frame: CGRect(x: leftMargin, y: y, width: 410, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)
        y -= 25

        // 默认保存格式
        let formatLabel = NSTextField(labelWithString: "保存格式:")
        formatLabel.frame = CGRect(x: leftMargin, y: y, width: labelWidth, height: 20)
        contentView.addSubview(formatLabel)

        let formatPopup = NSPopUpButton(
            frame: CGRect(x: controlX, y: y - 2, width: 100, height: 26))
        formatPopup.addItems(withTitles: ["PNG", "JPEG", "TIFF"])
        formatPopup.selectItem(withTitle: prefs.saveFormat.uppercased())
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        contentView.addSubview(formatPopup)
        y -= 35

        // 默认线宽
        let lineWidthLabel = NSTextField(labelWithString: "默认标注线宽:")
        lineWidthLabel.frame = CGRect(x: leftMargin, y: y, width: labelWidth, height: 20)
        contentView.addSubview(lineWidthLabel)

        let lineWidthSlider = NSSlider(
            value: Double(prefs.defaultLineWidth), minValue: 1, maxValue: 10, target: self,
            action: #selector(lineWidthChanged(_:)))
        lineWidthSlider.frame = CGRect(x: controlX, y: y, width: 120, height: 20)
        contentView.addSubview(lineWidthSlider)

        let lineWidthValue = NSTextField(
            labelWithString: String(format: "%.0f px", prefs.defaultLineWidth))
        lineWidthValue.frame = CGRect(x: controlX + 130, y: y, width: 50, height: 20)
        lineWidthValue.tag = 200
        contentView.addSubview(lineWidthValue)
        y -= 35

        // 默认颜色
        let colorLabel = NSTextField(labelWithString: "默认标注颜色:")
        colorLabel.frame = CGRect(x: leftMargin, y: y, width: labelWidth, height: 20)
        contentView.addSubview(colorLabel)

        let colorWell = NSColorWell(frame: CGRect(x: controlX, y: y - 2, width: 44, height: 26))
        colorWell.color = prefs.defaultAnnotationColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        if #available(macOS 13.0, *) {
            colorWell.colorWellStyle = .expanded
        }
        contentView.addSubview(colorWell)
        y -= 35

        // 历史数量
        let historyLabel = NSTextField(labelWithString: "最大历史数量:")
        historyLabel.frame = CGRect(x: leftMargin, y: y, width: labelWidth, height: 20)
        contentView.addSubview(historyLabel)

        let historyField = NSTextField(frame: CGRect(x: controlX, y: y - 2, width: 60, height: 24))
        historyField.integerValue = prefs.maxHistoryCount
        historyField.formatter = NumberFormatter()
        historyField.target = self
        historyField.action = #selector(historyCountChanged(_:))
        contentView.addSubview(historyField)

        let historyUnit = NSTextField(labelWithString: "张")
        historyUnit.frame = CGRect(x: controlX + 65, y: y, width: 30, height: 20)
        contentView.addSubview(historyUnit)
        y -= 45

        // 快捷键提示
        let separator2 = NSBox(frame: CGRect(x: leftMargin, y: y, width: 410, height: 1))
        separator2.boxType = .separator
        contentView.addSubview(separator2)
        y -= 25

        let shortcutTitle = NSTextField(labelWithString: "快捷键")
        shortcutTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        shortcutTitle.frame = CGRect(x: leftMargin, y: y, width: 200, height: 18)
        contentView.addSubview(shortcutTitle)
        y -= 22

        let shortcuts = [
            ("⌘⇧4", "区域截图"),
            ("⌘⇧5", "全屏截图"),
            ("⌘⇧6", "窗口截图"),
            ("⌘⇧7", "取色器"),
            ("⌘⇧H", "截图历史")
        ]

        for (key, desc) in shortcuts {
            let keyLabel = NSTextField(labelWithString: key)
            keyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            keyLabel.frame = CGRect(x: leftMargin + 10, y: y, width: 60, height: 16)
            contentView.addSubview(keyLabel)

            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = .systemFont(ofSize: 11)
            descLabel.textColor = .secondaryLabelColor
            descLabel.frame = CGRect(x: leftMargin + 80, y: y, width: 200, height: 16)
            contentView.addSubview(descLabel)
            y -= 18
        }
    }

    // MARK: - Helper

    private func addCheckbox(
        to view: NSView, y: CGFloat, title: String, isChecked: Bool, action: Selector
    ) -> CGFloat {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: action)
        checkbox.frame = CGRect(x: 20, y: y, width: 400, height: 20)
        checkbox.state = isChecked ? .on : .off
        view.addSubview(checkbox)
        return y - 28
    }

    // MARK: - Actions

    @objc private func toggleCopyToClipboard(_ sender: NSButton) {
        PreferencesManager.shared.copyToClipboardOnCapture = (sender.state == .on)
    }

    @objc private func togglePlaySound(_ sender: NSButton) {
        PreferencesManager.shared.playSoundOnCapture = (sender.state == .on)
    }

    @objc private func toggleSaveHistory(_ sender: NSButton) {
        PreferencesManager.shared.saveToHistory = (sender.state == .on)
    }

    @objc private func toggleCaptureCursor(_ sender: NSButton) {
        PreferencesManager.shared.captureMouseCursor = (sender.state == .on)
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        PreferencesManager.shared.saveFormat = sender.titleOfSelectedItem?.lowercased() ?? "png"
    }

    @objc private func lineWidthChanged(_ sender: NSSlider) {
        PreferencesManager.shared.defaultLineWidth = CGFloat(sender.doubleValue)
        if let label = window?.contentView?.viewWithTag(200) as? NSTextField {
            label.stringValue = String(format: "%.0f px", sender.doubleValue)
        }
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        PreferencesManager.shared.defaultAnnotationColor = sender.color
    }

    @objc private func historyCountChanged(_ sender: NSTextField) {
        PreferencesManager.shared.maxHistoryCount = max(5, sender.integerValue)
    }
}
