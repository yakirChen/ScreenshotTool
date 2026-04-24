//
//  AppDelegate.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa
import ScreenCaptureKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 设置为 Agent 应用（只在菜单栏显示，不在 Dock 显示）
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupHotkeys()
        requestScreenCapturePermission()
    }

    // MARK: - 状态栏
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Screenshot Tool")
        }

        let menu = NSMenu()

        // 截图功能（对齐 macOS 原生快捷键）
        let fullItem = menu.addItem(
            withTitle: "全屏截图", action: #selector(captureFullScreen), keyEquivalent: "3")
        fullItem.keyEquivalentModifierMask = [.command, .shift]
        fullItem.target = self

        let areaItem = menu.addItem(
            withTitle: "区域截图", action: #selector(captureArea), keyEquivalent: "4")
        areaItem.keyEquivalentModifierMask = [.command, .shift]
        areaItem.target = self

        let panelItem = menu.addItem(
            withTitle: "截图和录制选项", action: #selector(openCapturePanel), keyEquivalent: "5")
        panelItem.keyEquivalentModifierMask = [.command, .shift]
        panelItem.target = self

        let scrollItem = menu.addItem(
            withTitle: "滚动截图", action: #selector(scrollCapture), keyEquivalent: "8")
        scrollItem.keyEquivalentModifierMask = [.command, .shift]
        scrollItem.target = self

        menu.addItem(NSMenuItem.separator())

        // 工具
        let colorItem = menu.addItem(
            withTitle: "取色器", action: #selector(startColorPicker), keyEquivalent: "7")
        colorItem.keyEquivalentModifierMask = [.command, .shift]
        colorItem.target = self

        menu.addItem(NSMenuItem.separator())

        // 历史 & 设置
        let historyItem = menu.addItem(
            withTitle: "截图历史", action: #selector(showHistory), keyEquivalent: "h")
        historyItem.keyEquivalentModifierMask = [.command, .shift]
        historyItem.target = self

        let prefItem = menu.addItem(
            withTitle: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self

        menu.addItem(NSMenuItem.separator())

        // 关于 & 退出
        let aboutItem = menu.addItem(
            withTitle: "关于 ScreenshotTool", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self

        let quitItem = menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        statusItem.menu = menu
    }

    @objc func startColorPicker() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ColorPickerController.shared.start()
        }
    }

    // MARK: - 快捷键
    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()

        // ⌘⇧3 即时全屏截图
        hotkeyManager.register(keyCode: 0x14, modifiers: [.command, .shift]) { [weak self] in
            self?.captureFullScreen()
        }

        // ⌘⇧4 轻量十字光标选区
        hotkeyManager.register(keyCode: 0x15, modifiers: [.command, .shift]) { [weak self] in
            self?.captureArea()
        }

        // ⌘⇧5 统一控制面板
        hotkeyManager.register(keyCode: 0x17, modifiers: [.command, .shift]) { [weak self] in
            self?.openCapturePanel()
        }

        // ⌘⇧7 取色器
        hotkeyManager.register(keyCode: 0x1A, modifiers: [.command, .shift]) { [weak self] in
            self?.startColorPicker()
        }
    }

    // MARK: - 权限
    private func requestScreenCapturePermission() {
        Task {
            let hasPermission = await ScreenCaptureService.shared.checkPermission()
            if !hasPermission {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "需要屏幕录制权限"
                    alert.informativeText = "截图工具需要屏幕录制权限才能正常工作。\n请在系统设置中授予权限。"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "打开系统设置")
                    alert.addButton(withTitle: "稍后")

                    if alert.runModal() == .alertFirstButtonReturn {
                        ScreenCaptureService.shared.requestPermission()
                    }
                }
            }
        }
    }

    // MARK: - Actions
    @objc func captureArea() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SelectionCaptureManager.shared.startCapture(lightweight: true)
        }
    }

    @objc func captureFullScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            FullScreenCaptureManager.shared.capture()
        }
    }

    @objc func openCapturePanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SelectionCaptureManager.shared.startCapture(lightweight: false)
        }
    }

    @objc func scrollCapture() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ScrollCaptureManager.shared.start()
        }
    }

    @objc func openPreferences() {
        PreferencesWindowController.show()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func showHistory() {
        HistoryWindowController.show()
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ScreenshotTool"
        alert.informativeText = "版本 1.0.0\n\n一个轻量级的 macOS 截图工具\n支持区域截图、标注编辑、OCR、取色器等功能"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
