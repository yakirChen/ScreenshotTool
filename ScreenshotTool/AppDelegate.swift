//
//  AppDelegate.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为 Agent 应用（只在菜单栏显示，不在 Dock 显示）
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusBar()
        setupHotkeys()
        requestScreenCapturePermission()
    }
    
    // MARK: - 状态栏
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "Screenshot Tool")
        }
        
        let menu = NSMenu()
        
        menu.addItem(withTitle: "区域截图",
                     action: #selector(captureArea),
                     keyEquivalent: "4")
            .keyEquivalentModifierMask = [.command, .shift]
        
        menu.addItem(withTitle: "全屏截图",
                     action: #selector(captureFullScreen),
                     keyEquivalent: "5")
            .keyEquivalentModifierMask = [.command, .shift]
        
        menu.addItem(withTitle: "窗口截图",
                     action: #selector(captureWindow),
                     keyEquivalent: "6")
            .keyEquivalentModifierMask = [.command, .shift]
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(withTitle: "偏好设置...",
                     action: #selector(openPreferences),
                     keyEquivalent: ",")
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(withTitle: "退出",
                     action: #selector(quitApp),
                     keyEquivalent: "q")
        
        // 设置所有菜单项的 target
        for item in menu.items {
            item.target = self
        }
        
        statusItem.menu = menu
    }
    
    // MARK: - 快捷键
    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()
        
        hotkeyManager.register(keyCode: 0x15, modifiers: [.command, .shift]) { [weak self] in
            // ⌘⇧4 -> keyCode 0x15 = "4" (实际使用时可能需要调整)
            self?.captureArea()
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
        // 延迟一点点，让菜单消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SelectionCaptureManager.shared.startCapture()
        }
    }
    
    @objc func captureFullScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            FullScreenCaptureManager.shared.capture()
        }
    }
    
    @objc func captureWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SelectionCaptureManager.shared.startCapture(detectWindows: true)
        }
    }
    
    @objc func openPreferences() {
        // TODO: Phase 4
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
