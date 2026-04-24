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
        let globalAppKitFrame: CGRect  // AppKit 全局坐标（左下角原点）
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

                let globalAppKitFrame = GeometryMapper.appKitGlobalRect(
                    fromCoreGraphicsRect: window.frame,
                    primaryScreenHeight: primaryHeight
                )

                // 检查窗口中心是否在目标屏幕范围内
                let windowCenter = CGPoint(x: globalAppKitFrame.midX, y: globalAppKitFrame.midY)
                guard targetScreen.frame.contains(windowCenter) else { return nil }

                return DetectedWindow(
                    windowID: window.windowID,
                    frame: window.frame,
                    globalAppKitFrame: globalAppKitFrame,
                    title: window.title ?? "",
                    appName: window.owningApplication?.applicationName ?? "",
                    scWindow: window
                )
            }

            // 按面积从小到大排序（优先匹配小窗口）
            cachedWindows.sort {
                $0.globalAppKitFrame.width * $0.globalAppKitFrame.height
                    < $1.globalAppKitFrame.width * $1.globalAppKitFrame.height
            }

        } catch {
            print("⚠️ 获取窗口列表失败: \(error)")
        }
    }

    /// 根据鼠标位置找窗口（AppKit 全局坐标）
    func detectWindow(globalPoint: CGPoint) -> DetectedWindow? {
        for window in cachedWindows where window.globalAppKitFrame.contains(globalPoint) {
            return window
        }
        return nil
    }
}
