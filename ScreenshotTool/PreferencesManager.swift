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
