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

        // 复制到剪贴板
        copyToClipboard(image: image)

        // 打开编辑器
        EditorWindowController.show(with: image)

        // ✅ 保存到历史
        HistoryManager.shared.save(image: image)

        // 音效
        NSSound(named: "Tink")?.play()

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
