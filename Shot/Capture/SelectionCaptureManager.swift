//
//  SelectionCaptureManager.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class SelectionCaptureManager {

  static let shared = SelectionCaptureManager()

  private var overlayWindows: [SelectionOverlayWindow] = []

  func startCapture(detectWindows: Bool = false) {
    Task { @MainActor in
      let hasPermission = await ScreenCaptureService.shared.checkPermission()
      if !hasPermission {
        ScreenCaptureService.shared.requestPermission()
        return
      }

      print("========== 屏幕信息 ==========")
      for (i, screen) in NSScreen.screens.enumerated() {
        let number =
          screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? CGDirectDisplayID ?? 0
        print(
          "屏幕\(i): \(screen.localizedName) displayID=\(number) frame=\(screen.frame) scale=\(screen.backingScaleFactor)"
        )
      }
      print("主屏幕: \(NSScreen.main?.localizedName ?? "nil")")
      print("================================")

      // 为每个屏幕单独截冻结背景
      var frozenImages: [CGDirectDisplayID: NSImage] = [:]
      for screen in NSScreen.screens {
        let displayID =
          screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? CGDirectDisplayID ?? 0
        do {
          let image = try await ScreenCaptureService.shared.captureFullScreen(
            screen: screen)
          frozenImages[displayID] = image
          print("✅ 冻结背景 屏幕\(screen.localizedName): \(image.size)")
        } catch {
          print("⚠️ 冻结背景失败 屏幕\(screen.localizedName): \(error)")
        }
      }

      // 为每个屏幕创建覆盖窗口
      for screen in NSScreen.screens {
        let displayID =
          screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? CGDirectDisplayID ?? 0

        let window = SelectionOverlayWindow(screen: screen, detectWindows: detectWindows)

        if let view = window.contentView as? SelectionOverlayView {
          view.frozenBackground = frozenImages[displayID]
        }

        window.onComplete = { [weak self] rect, captureScreen in
          self?.finishCapture(selectionRect: rect, screen: captureScreen)
        }
        window.onCancel = { [weak self] in
          self?.cancelCapture()
        }

        overlayWindows.append(window)

        print("📌 创建覆盖窗口: screen=\(screen.localizedName) windowFrame=\(window.frame)")
      }

      // 显示所有窗口
      for window in overlayWindows {
        window.orderFrontRegardless()
      }

      // 让鼠标所在屏幕的窗口成为 key window
      let mouseLocation = NSEvent.mouseLocation
      let activeWindow =
        overlayWindows.first { $0.associatedScreen.frame.contains(mouseLocation) }
        ?? overlayWindows.first
      activeWindow?.makeKeyAndOrderFront(nil)

      NSApp.activate(ignoringOtherApps: true)

      print("🖱️ 鼠标位置: \(mouseLocation)")
      print("🔑 key window screen: \(activeWindow?.associatedScreen.localizedName ?? "nil")")
    }
  }

  private func finishCapture(selectionRect: CGRect, screen: NSScreen) {
    closeOverlays()

    guard selectionRect.width > 1 && selectionRect.height > 1 else { return }

    print("📐 finishCapture:")
    print("  selectionRect: \(selectionRect)")
    print(
      "  screen: \(screen.localizedName) frame=\(screen.frame) scale=\(screen.backingScaleFactor)"
    )

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 200_000_000)

      do {
        let image = try await ScreenCaptureService.shared.captureArea(
          rect: selectionRect,
          screen: screen
        )

        print("✅ 截图成功: \(image.size)")

        // 移除所有动画效果（闪屏和缩略图飞入）

        if PreferencesManager.shared.copyToClipboardOnCapture {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.writeObjects([image])
        }

        EditorWindowController.show(with: image)

        if PreferencesManager.shared.saveToHistory {
          HistoryManager.shared.save(image: image)
        }

        if PreferencesManager.shared.playSoundOnCapture {
          NSSound(named: "Tink")?.play()
        }

      } catch {
        print("❌ 截图失败: \(error)")
        let alert = NSAlert()
        alert.messageText = "截图失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
      }
    }
  }

  func cancelCapture() {
    closeOverlays()
  }

  private func closeOverlays() {
    for window in overlayWindows {
      window.orderOut(nil)
    }
    overlayWindows.removeAll()
  }
}
