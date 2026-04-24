//
//  SelectionCaptureManager.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

enum CaptureExportAction {
    case copy
    case save
    case pin
}

class SelectionCaptureManager {

    static let shared = SelectionCaptureManager()

    private var overlayWindows: [SelectionOverlayWindow] = []
    private var captureSession: CaptureSession?
    private(set) var state: State = .idle

    enum State {
        case idle
        case selecting
        case captured
        case annotating
        case exporting
        case cancelled
    }

    /// - Parameter lightweight: true = ⌘⇧4 风格（无底部控制栏，Space 切窗口），false = ⌘⇧5 风格（带控制面板）
    func startCapture(lightweight: Bool = false) {
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

            let session = CaptureSession()
            session.showControlBar = !lightweight
            captureSession = session
            state = .selecting

            // 为每个屏幕创建覆盖窗口
            for screen in NSScreen.screens {
                let displayID =
                    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID ?? 0

                let window = SelectionOverlayWindow(
                    screen: screen,
                    session: session,
                    showControlBar: !lightweight
                )

                if let view = window.contentView as? SelectionOverlayView {
                    view.frozenBackground = frozenImages[displayID]
                }

                window.onComplete = { [weak self] rect, captureScreen, editedImage, action in
                    self?.finishCapture(
                        selectionRect: rect,
                        screen: captureScreen,
                        editedImage: editedImage,
                        action: action
                    )
                }
                window.onCancel = { [weak self] in
                    self?.cancelCapture()
                }
                window.onStateChange = { [weak self] newState in
                    self?.state = newState
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

    private func finishCapture(
        selectionRect: CGRect,
        screen: NSScreen,
        editedImage: NSImage?,
        action: CaptureExportAction
    ) {
        guard selectionRect.width > 1 && selectionRect.height > 1 else { return }

        print("📐 finishCapture:")
        print("  selectionRect: \(selectionRect)")
        print(
            "  screen: \(screen.localizedName) frame=\(screen.frame) scale=\(screen.backingScaleFactor)"
        )

        guard let image = editedImage else { return }

        print("✅ 截图成功: \(image.size)")
        state = .exporting

        let isPinAction = (action == .pin)
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        case .save:
            break
        case .pin:
            PinWindow.pin(image: image)
        }

        let prefs = PreferencesManager.shared
        if prefs.saveToHistory { HistoryManager.shared.save(image: image) }
        if prefs.playSoundOnCapture { NSSound(named: "Tink")?.play() }

        // 右下角浮动缩略图（用户点击/右键进入下一步）
        if prefs.showFloatingThumbnail && !isPinAction {
            let globalRect = CGRect(
                x: screen.frame.origin.x + selectionRect.origin.x,
                y: screen.frame.origin.y + selectionRect.origin.y,
                width: selectionRect.width,
                height: selectionRect.height
            )
            FloatingThumbnail.show(image: image, sourceRect: globalRect)
        }

        // 闪屏动画
        CaptureAnimation.playFlash(in: screen.frame)
        closeOverlays()
        state = .idle
    }

    func cancelCapture() {
        state = .cancelled
        closeOverlays()
        state = .idle
    }

    private func closeOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        captureSession = nil
    }
}
