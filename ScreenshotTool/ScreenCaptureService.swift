//
//  ScreenCaptureService.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa
import ScreenCaptureKit

class ScreenCaptureService {

    static let shared = ScreenCaptureService()

    // MARK: - 截取指定屏幕

    func captureFullScreen(screen: NSScreen? = nil) async throws -> NSImage {
        let targetScreen = screen ?? NSScreen.main!
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        guard let display = findDisplay(for: targetScreen, in: content.displays) else {
            print("❌ 找不到匹配的 display for screen: \(targetScreen.localizedName)")
            print("  可用的 displays:")
            for d in content.displays {
                print("    displayID=\(d.displayID), frame=\(d.frame), \(d.width)×\(d.height)")
            }
            throw CaptureError.noDisplay
        }

        print("✅ 匹配 display: id=\(display.displayID) for screen: \(targetScreen.localizedName)")

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = createConfig(for: display, screen: targetScreen)

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: targetScreen.frame.width, height: targetScreen.frame.height)
        )
    }

    // MARK: - 截取指定区域

    func captureArea(rect: CGRect, screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        guard let display = findDisplay(for: screen, in: content.displays) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = screen.backingScaleFactor

        // NSView 局部坐标 (左下角原点) → SCKit (左上角原点)
        let flippedY = screen.frame.height - rect.origin.y - rect.height

        let sourceRect = CGRect(
            x: rect.origin.x,
            y: flippedY,
            width: rect.width,
            height: rect.height
        )

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = PreferencesManager.shared.captureMouseCursor
        config.captureResolution = .best

        print("📸 captureArea:")
        print("  screen: \(screen.localizedName) (scale=\(scale))")
        print("  viewRect: \(rect)")
        print("  sourceRect: \(sourceRect)")
        print("  output: \(config.width)×\(config.height)")
        print("  display: id=\(display.displayID) \(display.width)×\(display.height)")

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: rect.width, height: rect.height)
        )
    }

    // 兼容旧签名
    func captureArea(rect: CGRect, screenFrame: CGRect) async throws -> NSImage {
        let screen = findScreen(for: screenFrame) ?? NSScreen.main!
        return try await captureArea(rect: rect, screen: screen)
    }

    // MARK: - 截取窗口

    func captureWindow(_ scWindow: SCWindow) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, including: [scWindow])
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let frame = scWindow.frame

        let config = SCStreamConfiguration()
        config.width = max(1, Int(frame.width * scale))
        config.height = max(1, Int(frame.height * scale))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: frame.width, height: frame.height)
        )
    }

    // MARK: - 窗口列表

    struct WindowInfo {
        let scWindow: SCWindow
        let title: String
        let appName: String
        let frame: CGRect
        let windowID: CGWindowID
    }

    func getOnScreenWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true)

        return content.windows.compactMap { window in
            guard window.frame.width > 10,
                  window.frame.height > 10,
                  window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return nil }

            return WindowInfo(
                scWindow: window,
                title: window.title ?? "",
                appName: window.owningApplication?.applicationName ?? "",
                frame: window.frame,
                windowID: window.windowID
            )
        }
    }

    // MARK: - 权限

    func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    func requestPermission() {
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
            } catch {
                await MainActor.run { openPermissionSettings() }
            }
        }
    }

    func openPermissionSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 屏幕匹配（核心）

    private func findDisplay(for screen: NSScreen, in displays: [SCDisplay]) -> SCDisplay? {
        // ✅ 方法1：通过 CGDirectDisplayID 精确匹配
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID {
            for display in displays {
                if display.displayID == screenNumber {
                    return display
                }
            }
        }

        // ✅ 方法2：通过分辨率 + 位置匹配
        // NSScreen.frame 是 AppKit 坐标系 (主屏左下角为原点)
        // SCDisplay.frame 是 CG 坐标系 (主屏左上角为原点)
        // 宽高应该一致，用宽高匹配
        let screenW = screen.frame.width
        let screenH = screen.frame.height

        // 如果只有宽高完全一样的唯一 display
        let sizeMatches = displays.filter {
            abs(CGFloat($0.width) - screenW) < 2 && abs(CGFloat($0.height) - screenH) < 2
        }
        if sizeMatches.count == 1 {
            return sizeMatches[0]
        }

        // ✅ 方法3：如果多个尺寸一样（比如两个一样的外接显示器），用 x 坐标区分
        // 需要把 NSScreen 的坐标转换到 CG 坐标系来比较
        if sizeMatches.count > 1 {
            let primaryScreenHeight = NSScreen.screens[0].frame.height
            // NSScreen y 翻转为 CG y
            let cgY = primaryScreenHeight - screen.frame.origin.y - screen.frame.height

            for display in sizeMatches {
                if abs(display.frame.origin.x - screen.frame.origin.x) < 10
                    && abs(display.frame.origin.y - cgY) < 10 {
                    return display
                }
            }
        }

        // 最后兜底
        print("⚠️ findDisplay: 无法精确匹配，使用第一个 display")
        return displays.first
    }

    private func findScreen(for frame: CGRect) -> NSScreen? {
        return NSScreen.screens.first { screen in
            abs(screen.frame.origin.x - frame.origin.x) < 2
                && abs(screen.frame.origin.y - frame.origin.y) < 2
        } ?? NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    private func createConfig(for display: SCDisplay, screen: NSScreen) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor

        config.width = max(1, Int(CGFloat(display.width) * scale))
        config.height = max(1, Int(CGFloat(display.height) * scale))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = PreferencesManager.shared.captureMouseCursor
        config.captureResolution = .best

        return config
    }

    // MARK: - Errors

    enum CaptureError: LocalizedError {
        case noDisplay
        case noPermission
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "未找到显示器"
            case .noPermission: return "没有屏幕录制权限"
            case .captureFailed(let reason): return "截图失败: \(reason)"
            }
        }
    }
}
