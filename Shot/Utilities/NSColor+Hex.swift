//
//  NSColor+Hex.swift
//  Shot
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

extension NSColor {
  /// 从十六进制字符串初始化颜色 (支持 #RRGGBB, RRGGBB, #RRGGBBAA)
  convenience init?(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if hexSanitized.hasPrefix("#") {
      hexSanitized.remove(at: hexSanitized.startIndex)
    }

    var rgb: UInt64 = 0
    guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

    let r, g, b, a: CGFloat
    if hexSanitized.count == 6 {
      r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
      g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
      b = CGFloat(rgb & 0x0000FF) / 255.0
      a = 1.0
    } else if hexSanitized.count == 8 {
      r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
      g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
      b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
      a = CGFloat(rgb & 0x000000FF) / 255.0
    } else {
      return nil
    }

    self.init(red: r, green: g, blue: b, alpha: a)
  }

  /// 返回十六进制字符串 (例如 #FF0000)
  var hexString: String {
    guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
    let r = Int(rgbColor.redComponent * 255)
    let g = Int(rgbColor.greenComponent * 255)
    let b = Int(rgbColor.blueComponent * 255)
    return String(format: "#%02X%02X%02X", r, g, b)
  }
}
