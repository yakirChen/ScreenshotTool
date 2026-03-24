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
            
            // 先截一张冻结背景
            let frozenBackground: NSImage?
            do {
                frozenBackground = try await ScreenCaptureService.shared.captureFullScreen()
            } catch {
                frozenBackground = nil
                print("⚠️ 冻结背景截取失败: \(error)")
            }
            
            for screen in NSScreen.screens {
                let window = SelectionOverlayWindow(screen: screen, detectWindows: detectWindows)
                
                if let view = window.contentView as? SelectionOverlayView {
                    view.frozenBackground = frozenBackground
                }
                
                window.onComplete = { [weak self] rect, screenFrame in
                    self?.finishCapture(selectionRect: rect, screenFrame: screenFrame)
                }
                window.onCancel = { [weak self] in
                    self?.cancelCapture()
                }
                window.makeKeyAndOrderFront(nil)
                overlayWindows.append(window)
            }
            
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func finishCapture(selectionRect: CGRect, screenFrame: CGRect) {
        print("📐 选区: \(selectionRect)")
        print("📐 屏幕: \(screenFrame)")
        
        // ✅ 1. 先关闭所有覆盖窗口
        closeOverlays()
        
        guard selectionRect.width > 1 && selectionRect.height > 1 else {
            print("⚠️ 选区太小，忽略")
            return
        }
        
        // ✅ 2. 延迟截图，确保窗口完全关闭
        Task { @MainActor in
            // 等覆盖窗口完全消失
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            
            do {
                print("📸 开始截图...")
                let image = try await ScreenCaptureService.shared.captureArea(
                    rect: selectionRect,
                    screenFrame: screenFrame
                )
                print("✅ 截图成功: \(image.size)")
                
                // 复制到剪贴板
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
                
                // 打开编辑器
                EditorWindowController.show(with: image)
                
                // 音效
                NSSound(named: "Tink")?.play()
                
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
        print("🔒 关闭 \(overlayWindows.count) 个覆盖窗口")
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}
