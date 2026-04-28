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
    private var eventMonitor: Any?  // 💡 监视器引用
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
                } catch {
                    print("⚠️ 冻结背景失败: \(error)")
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
                    screen: screen, session: session, showControlBar: !lightweight)

                if let view = window.contentView as? SelectionOverlayView {
                    view.frozenBackground = frozenImages[displayID]
                }

                window.onComplete = { [weak self] rect, captureScreen, editedImage, action in
                    self?.finishCapture(
                        selectionRect: rect, screen: captureScreen, editedImage: editedImage,
                        action: action)
                }
                window.onCancel = { [weak self] in
                    self?.cancelCapture()
                }
                window.onStateChange = { [weak self] newState in
                    self?.state = newState
                }
                overlayWindows.append(window)
            }

            for window in overlayWindows {
                window.orderFrontRegardless()
            }

            let mouseLocation = NSEvent.mouseLocation
            let activeWindow =
                overlayWindows.first { $0.associatedScreen.frame.contains(mouseLocation) }
                ?? overlayWindows.first
            activeWindow?.makeKeyAndOrderFront(nil)

            NSApp.activate(ignoringOtherApps: true)

            // 💡 核心修复：注册全局唯一的 ESC 监听器
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                if event.keyCode == 53 {  // ESC
                    self?.cancelCapture()
                    return nil
                }
                return event
            }
            
            // 💡 多显示器优化：预加载窗口信息以支持跨屏磁贴
            for screen in NSScreen.screens {
                session.ensureWindowsLoaded(for: screen)
            }
        }
    }

    private func finishCapture(
        selectionRect: CGRect, screen: NSScreen, editedImage: NSImage?, action: CaptureExportAction
    ) {
        guard let image = editedImage else { return }
        state = .exporting

        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        case .pin:
            PinWindow.pin(image: image)
        case .save: break
        }

        let prefs = PreferencesManager.shared
        if prefs.saveToHistory { HistoryManager.shared.save(image: image) }
        if prefs.playSoundOnCapture { NSSound(named: "Tink")?.play() }

        if prefs.showFloatingThumbnail {
            let globalRect = CGRect(
                x: screen.frame.origin.x + selectionRect.origin.x,
                y: screen.frame.origin.y + selectionRect.origin.y,
                width: selectionRect.width,
                height: selectionRect.height
            )
            FloatingThumbnail.show(image: image, sourceRect: globalRect)
        }

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
        // 💡 核心修复：销毁时移除监听器
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        captureSession = nil
    }
}
