//
//  WindowDetector.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa
import ScreenCaptureKit

class WindowDetector {

    struct DetectedWindow {
        let windowID: CGWindowID
        let frame: CGRect  // SCWindow 原始 frame（全局，左上角原点）
        let viewFrame: CGRect  // 相对于目标屏幕的 NSView 坐标（左下角原点）
        let title: String
        let appName: String
        let scWindow: SCWindow?
    }

    private var cachedWindows: [DetectedWindow] = []

    /// 刷新窗口列表（相对于指定屏幕）
    func refresh(for screen: NSScreen? = nil) async {
        let targetScreen = screen ?? NSScreen.main!

        // 获取主屏幕高度（用于全局坐标翻转）
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true)

            cachedWindows = content.windows.compactMap { window in
                guard window.frame.width > 50,
                      window.frame.height > 50,
                      window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                else { return nil }

                // SCWindow.frame: 全局坐标，左上角原点 (Core Graphics)
                // NSScreen.frame: 全局坐标，左下角原点 (AppKit)
                //
                // 转换步骤：
                // 1. CG 全局 → AppKit 全局
                let globalAppKitY = primaryHeight - window.frame.origin.y - window.frame.height

                // 2. AppKit 全局 → 相对于目标屏幕
                let localX = window.frame.origin.x - targetScreen.frame.origin.x
                let localY = globalAppKitY - targetScreen.frame.origin.y

                let viewFrame = CGRect(
                    x: localX,
                    y: localY,
                    width: window.frame.width,
                    height: window.frame.height
                )

                // 检查窗口中心是否在目标屏幕范围内
                let screenBounds = CGRect(origin: .zero, size: targetScreen.frame.size)
                let windowCenter = CGPoint(x: viewFrame.midX, y: viewFrame.midY)
                guard screenBounds.contains(windowCenter) else { return nil }

                return DetectedWindow(
                    windowID: window.windowID,
                    frame: window.frame,
                    viewFrame: viewFrame,
                    title: window.title ?? "",
                    appName: window.owningApplication?.applicationName ?? "",
                    scWindow: window
                )
            }

            // 按面积从小到大排序（优先匹配小窗口）
            cachedWindows.sort {
                $0.viewFrame.width * $0.viewFrame.height < $1.viewFrame.width * $1.viewFrame.height
            }

        } catch {
            print("⚠️ 获取窗口列表失败: \(error)")
        }
    }

    /// 根据鼠标位置找窗口（局部 view 坐标）
    func detectWindow(at viewPoint: CGPoint) -> DetectedWindow? {
        for window in cachedWindows {
            if window.viewFrame.contains(viewPoint) {
                return window
            }
        }
        return nil
    }
}
