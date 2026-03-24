//
//  ScreenCaptureService.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//


import Cocoa
import ScreenCaptureKit

/// 统一的屏幕截图服务，基于 ScreenCaptureKit
class ScreenCaptureService {
    
    static let shared = ScreenCaptureService()
    
    // MARK: - 截取全屏
    
    /// 截取主屏幕
    func captureFullScreen() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = createConfig(for: display)
        
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: display.width, height: display.height)
        )
    }
    
    // MARK: - 截取指定区域
    
    /// 截取屏幕上的指定区域
    /// - Parameters:
    ///   - rect: 区域矩形（NSView 坐标系，左下角原点）
    ///   - screenFrame: 所在屏幕的 frame
    func captureArea(rect: CGRect, screenFrame: CGRect) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = content.displays.first(where: { display in
            // 匹配对应的屏幕
            let displayFrame = CGRect(x: display.frame.origin.x,
                                       y: display.frame.origin.y,
                                       width: CGFloat(display.width),
                                       height: CGFloat(display.height))
            return displayFrame.intersects(screenFrame)
        }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = createConfig(for: display)
        
        // ScreenCaptureKit 使用左上角坐标系，需要转换
        // NSView 坐标系: 左下角原点, y 向上
        // SCKit 坐标系: 左上角原点, y 向下
        let flippedY = CGFloat(display.height) - rect.origin.y - rect.height
        
        let sourceRect = CGRect(
            x: rect.origin.x,
            y: flippedY,
            width: rect.width,
            height: rect.height
        )
        
        config.sourceRect = sourceRect
        config.width = Int(rect.width) * Int(NSScreen.main?.backingScaleFactor ?? 2)
        config.height = Int(rect.height) * Int(NSScreen.main?.backingScaleFactor ?? 2)
        
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: rect.width, height: rect.height)
        )
    }
    
    // MARK: - 截取指定窗口
    
    /// 截取指定窗口
    func captureWindow(_ scWindow: SCWindow) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        
        let filter = SCContentFilter(display: display, including: [scWindow])
        let config = SCStreamConfiguration()
        
        let frame = scWindow.frame
        let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
        config.width = Int(frame.width) * scale
        config.height = Int(frame.height) * scale
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.captureResolution = .best
        config.sourceRect = CGRect(origin: .zero, size: frame.size)
        
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: frame.width, height: frame.height)
        )
    }
    
    // MARK: - 获取屏幕上的窗口列表
    
    struct WindowInfo {
        let scWindow: SCWindow
        let title: String
        let appName: String
        let frame: CGRect
        let windowID: CGWindowID
    }
    
    /// 获取当前屏幕上的所有窗口
    func getOnScreenWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        
        return content.windows.compactMap { window in
            // 过滤掉太小的窗口和我们自己的窗口
            guard window.frame.width > 10,
                  window.frame.height > 10,
                  window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
            else {
                return nil
            }
            
            return WindowInfo(
                scWindow: window,
                title: window.title ?? "",
                appName: window.owningApplication?.applicationName ?? "",
                frame: window.frame,
                windowID: window.windowID
            )
        }
    }
    
    // MARK: - 权限检查
    
    /// 检查是否有屏幕录制权限
    func checkPermission() async -> Bool {
        do {
            // 尝试获取内容，如果没有权限会抛出错误
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }
    
  /// 请求权限
  /// ScreenCaptureKit 没有直接的 requestAccess API
  /// 触发一次截图操作会自动弹出系统权限对话框
  /// 如果用户已经拒绝过，则需要手动去系统设置中开启
  func requestPermission() {
      Task {
          do {
              // 尝试获取内容，系统会自动弹出权限请求对话框
              _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
          } catch {
              // 如果失败，引导用户去系统设置
              await MainActor.run {
                  openPermissionSettings()
              }
          }
      }
  }

    
    /// 打开系统偏好设置的屏幕录制权限页
    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Private
    
    private func createConfig(for display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
        
        config.width = display.width * scale
        config.height = display.height * scale
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
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
            case .noDisplay:
                return "未找到显示器"
            case .noPermission:
                return "没有屏幕录制权限，请在系统设置中授权"
            case .captureFailed(let reason):
                return "截图失败: \(reason)"
            }
        }
    }
}
