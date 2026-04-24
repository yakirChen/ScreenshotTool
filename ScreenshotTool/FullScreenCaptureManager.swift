//
//  FullScreenCaptureManager.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class FullScreenCaptureManager {

    static let shared = FullScreenCaptureManager()

    func capture() {
        Task { @MainActor in
            do {
                let image = try await ScreenCaptureService.shared.captureFullScreen()

                let prefs = PreferencesManager.shared

                if prefs.copyToClipboardOnCapture {
                    copyToClipboard(image: image)
                }
                if prefs.saveToHistory {
                    HistoryManager.shared.save(image: image)
                }
                if prefs.playSoundOnCapture {
                    NSSound(named: "Tink")?.play()
                }

                if let screen = NSScreen.main {
                    CaptureAnimation.playFlash(in: screen.frame)
                }

                // 全屏截图后直接进入编辑器，统一后置工具栏体验
                EditorWindowController.show(with: image)

            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func copyToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "截图失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCaptureService.shared.openPermissionSettings()
        }
    }
}
