//
//  PreferencesManager.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

class PreferencesManager {

    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case saveFormat = "saveFormat"
        case defaultSaveLocation = "defaultSaveLocation"
        case playSoundOnCapture = "playSoundOnCapture"
        case copyToClipboardOnCapture = "copyToClipboardOnCapture"
        case showInMenuBar = "showInMenuBar"
        case defaultAnnotationColor = "defaultAnnotationColor"
        case defaultLineWidth = "defaultLineWidth"
        case saveToHistory = "saveToHistory"
        case maxHistoryCount = "maxHistoryCount"
        case captureMouseCursor = "captureMouseCursor"
        case rememberLastSelection = "rememberLastSelection"
        case lastSelectionRect = "lastSelectionRect"
        case showFloatingThumbnail = "showFloatingThumbnail"
        case captureTimerSeconds = "captureTimerSeconds"
        case windowCaptureSingleClick = "windowCaptureSingleClick"
        case openEditorAfterCapture = "openEditorAfterCapture"
    }

    // MARK: - Properties

    var saveFormat: String {
        get { defaults.string(forKey: Key.saveFormat.rawValue) ?? "png" }
        set { defaults.set(newValue, forKey: Key.saveFormat.rawValue) }
    }

    var defaultSaveLocation: String {
        get {
            defaults.string(forKey: Key.defaultSaveLocation.rawValue) ?? NSHomeDirectory()
                + "/Desktop"
        }
        set { defaults.set(newValue, forKey: Key.defaultSaveLocation.rawValue) }
    }

    var playSoundOnCapture: Bool {
        get { defaults.object(forKey: Key.playSoundOnCapture.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.playSoundOnCapture.rawValue) }
    }

    var copyToClipboardOnCapture: Bool {
        get { defaults.object(forKey: Key.copyToClipboardOnCapture.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.copyToClipboardOnCapture.rawValue) }
    }

    var saveToHistory: Bool {
        get { defaults.object(forKey: Key.saveToHistory.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.saveToHistory.rawValue) }
    }

    var defaultLineWidth: CGFloat {
        get {
            CGFloat(
                defaults.double(forKey: Key.defaultLineWidth.rawValue) != 0
                    ? defaults.double(forKey: Key.defaultLineWidth.rawValue) : 2)
        }
        set { defaults.set(Double(newValue), forKey: Key.defaultLineWidth.rawValue) }
    }

    var captureMouseCursor: Bool {
        get { defaults.object(forKey: Key.captureMouseCursor.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.captureMouseCursor.rawValue) }
    }

    var maxHistoryCount: Int {
        get {
            let v = defaults.integer(forKey: Key.maxHistoryCount.rawValue)
            return v > 0 ? v : 50
        }
        set { defaults.set(newValue, forKey: Key.maxHistoryCount.rawValue) }
    }

    var rememberLastSelection: Bool {
        get { defaults.object(forKey: Key.rememberLastSelection.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.rememberLastSelection.rawValue) }
    }

    var showFloatingThumbnail: Bool {
        get { defaults.object(forKey: Key.showFloatingThumbnail.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showFloatingThumbnail.rawValue) }
    }

    /// 截图倒计时秒数：0 = 无，5、10 = 延迟秒数
    var captureTimerSeconds: Int {
        get { defaults.integer(forKey: Key.captureTimerSeconds.rawValue) }
        set { defaults.set(newValue, forKey: Key.captureTimerSeconds.rawValue) }
    }

    /// 窗口截图模式下，是否单击窗口即立即捕捉
    var windowCaptureSingleClick: Bool {
        get { defaults.object(forKey: Key.windowCaptureSingleClick.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.windowCaptureSingleClick.rawValue) }
    }

    /// 截图完成后是否自动打开编辑器
    var openEditorAfterCapture: Bool {
        get { defaults.object(forKey: Key.openEditorAfterCapture.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.openEditorAfterCapture.rawValue) }
    }

    /// 上次选区（屏幕局部坐标）。仅用于同一屏幕同尺寸恢复，超出边界时会被调用方忽略。
    var lastSelectionRect: CGRect? {
        get {
            guard let data = defaults.data(forKey: Key.lastSelectionRect.rawValue),
                  let dict = try? JSONDecoder().decode([String: CGFloat].self, from: data),
                  let x = dict["x"], let y = dict["y"],
                  let w = dict["w"], let h = dict["h"] else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        set {
            guard let rect = newValue else {
                defaults.removeObject(forKey: Key.lastSelectionRect.rawValue)
                return
            }
            let dict: [String: CGFloat] = [
                "x": rect.origin.x, "y": rect.origin.y,
                "w": rect.width, "h": rect.height
            ]
            if let data = try? JSONEncoder().encode(dict) {
                defaults.set(data, forKey: Key.lastSelectionRect.rawValue)
            }
        }
    }

    // MARK: - 默认标注颜色

    var defaultAnnotationColor: NSColor {
        get {
            if let data = defaults.data(forKey: Key.defaultAnnotationColor.rawValue),
               let color = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self, from: data) {
                return color
            }
            return .systemRed
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: newValue, requiringSecureCoding: true) {
                defaults.set(data, forKey: Key.defaultAnnotationColor.rawValue)
            }
        }
    }
}
