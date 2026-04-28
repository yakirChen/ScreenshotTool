//
//  Annotation.swift
//  Shot
//
//  Created by yakir on 2026/3/24.
//

import Cocoa
import CoreImage

/// 标注基类
class Annotation {
  let id = UUID()
  var tool: AnnotationTool
  var color: NSColor
  var lineWidth: CGFloat
  var startPoint: CGPoint
  var endPoint: CGPoint
  var isSelected: Bool = false

  // 文字标注专用
  var text: String = ""
  var fontSize: CGFloat = 16
  var fontName: String = "Helvetica Neue"

  // 画笔专用
  var penPoints: [CGPoint] = []

  // 编号专用
  var number: Int = 1

  // 样式索引（0:圆角 1:直角 2:遮罩 3:实心 / 线条类 1:流线型）
  var styleIndex: Int = 0

  init(
    tool: AnnotationTool, startPoint: CGPoint, color: NSColor = .systemRed,
    lineWidth: CGFloat = 2
  ) {
    self.tool = tool
    self.startPoint = startPoint
    self.endPoint = startPoint
    self.color = color
    self.lineWidth = lineWidth
  }

  /// 标注的边界矩形
  var boundingRect: CGRect {
    switch tool {
    case .pen:
      guard !penPoints.isEmpty else { return .zero }
      let xs = penPoints.map { $0.x }
      let ys = penPoints.map { $0.y }
      let padding = lineWidth + 2
      return CGRect(
        x: xs.min()! - padding,
        y: ys.min()! - padding,
        width: (xs.max()! - xs.min()!) + padding * 2,
        height: (ys.max()! - ys.min()!) + padding * 2
      )
    case .number:
      let radius: CGFloat = fontSize * 1.0
      return CGRect(
        x: startPoint.x - radius,
        y: startPoint.y - radius,
        width: radius * 2,
        height: radius * 2
      )
    case .text:
      let attrs = textAttributes
      let size = (text as NSString).size(withAttributes: attrs)
      return CGRect(
        origin: startPoint,
        size: CGSize(width: max(size.width, 50), height: max(size.height, 20)))
    default:
      let rect = CGRect(
        x: min(startPoint.x, endPoint.x),
        y: min(startPoint.y, endPoint.y),
        width: abs(endPoint.x - startPoint.x),
        height: abs(endPoint.y - startPoint.y)
      )
      return rect.insetBy(dx: -(lineWidth + 2), dy: -(lineWidth + 2))
    }
  }

  /// 文字属性
  var textAttributes: [NSAttributedString.Key: Any] {
    let font: NSFont
    if fontName == "Monospaced" {
      font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
    } else if fontName == "Serif" {
      font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    } else {
      font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }
    
    return [
      .foregroundColor: color,
      .font: font,
    ]
  }

  /// 检测点是否在标注上
  func hitTest(point: CGPoint) -> Bool {
    return boundingRect.insetBy(dx: -5, dy: -5).contains(point)
  }

  // MARK: - 绘制

  func draw(in context: CGContext, imageSize: NSSize, originalImage: NSImage? = nil) {
    context.saveGState()

    switch tool {
    case .arrow:
      drawArrow(in: context)
    case .rectangle:
      drawRectangle(in: context)
    case .ellipse:
      drawEllipse(in: context)
    case .line:
      drawLine(in: context)
    case .highlight:
      drawHighlight(in: context)
    case .blur:
      drawBlur(in: context, imageSize: imageSize, originalImage: originalImage)
    case .number:
      drawNumber(in: context)
    case .pen:
      drawPen(in: context)
    case .text:
      drawText()
    case .measure:
      drawMeasure(in: context)
    case .select:
      break
    }

    // 选中状态：画虚线边框
    if isSelected {
      drawSelectionBorder(in: context)
    }

    context.restoreGState()
  }

  // MARK: - 各种标注的绘制方法

  private func drawArrow(in context: CGContext) {
    let dx = endPoint.x - startPoint.x
    let dy = endPoint.y - startPoint.y
    let length = sqrt(dx * dx + dy * dy)
    guard length > 5 else { return }

    let angle = atan2(dy, dx)
    
    // 箭头头部参数 (更锋利的锐角三角形)
    let headLength: CGFloat = max(14, lineWidth * 4)
    let headAngle: CGFloat = .pi / 7 

    context.saveGState()
    if styleIndex == 1 { // ✅ 流线型 (Tapered)
      context.setFillColor(color.cgColor)
      let path = CGMutablePath()
      let startWidth: CGFloat = 0.5
      let endWidth: CGFloat = lineWidth
      
      let p1 = CGPoint(x: startPoint.x + startWidth * cos(angle + .pi/2), y: startPoint.y + startWidth * sin(angle + .pi/2))
      let p2 = CGPoint(x: startPoint.x + startWidth * cos(angle - .pi/2), y: startPoint.y + startWidth * sin(angle - .pi/2))
      // 梯形线段停止在头部之前
      let stopDist = headLength * 0.3
      let p3 = CGPoint(x: (endPoint.x - stopDist * cos(angle)) + endWidth * cos(angle - .pi/2), y: (endPoint.y - stopDist * sin(angle)) + endWidth * sin(angle - .pi/2))
      let p4 = CGPoint(x: (endPoint.x - stopDist * cos(angle)) + endWidth * cos(angle + .pi/2), y: (endPoint.y - stopDist * sin(angle)) + endWidth * sin(angle + .pi/2))
      
      path.move(to: p1); path.addLine(to: p2); path.addLine(to: p3); path.addLine(to: p4); path.closeSubpath()
      context.addPath(path); context.fillPath()
    } else {
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(lineWidth)
      context.setLineCap(.butt) // ✅ 使用对接端点，避免 protrude
      context.move(to: startPoint)
      // 停止在距离终点一小段距离处，确保不从箭尖透出
      let stopPoint = CGPoint(x: endPoint.x - (headLength * 0.2) * cos(angle), y: endPoint.y - (headLength * 0.2) * sin(angle))
      context.addLine(to: stopPoint)
      context.strokePath()
    }

    // 绘制实心头部
    let hp1 = CGPoint(x: endPoint.x - headLength * cos(angle - headAngle), y: endPoint.y - headLength * sin(angle - headAngle))
    let hp2 = CGPoint(x: endPoint.x - headLength * cos(angle + headAngle), y: endPoint.y - headLength * sin(angle + headAngle))

    context.setFillColor(color.cgColor)
    context.setLineJoin(.miter) 
    context.move(to: endPoint)
    context.addLine(to: hp1)
    context.addLine(to: hp2)
    context.closePath()
    context.fillPath()
    context.restoreGState()
  }

  private func drawRectangle(in context: CGContext) {
    let rect = CGRect(
      x: min(startPoint.x, endPoint.x),
      y: min(startPoint.y, endPoint.y),
      width: abs(endPoint.x - startPoint.x),
      height: abs(endPoint.y - startPoint.y)
    )

    context.saveGState()

    if styleIndex == 2 {
      // 遮罩模式：半透明填充 + 边框
      context.setFillColor(color.withAlphaComponent(0.3).cgColor)
      context.fill(rect)
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(lineWidth)
      context.stroke(rect)
    } else if styleIndex == 3 {
      // 实心模式：全填充
      let expandedRect = rect.insetBy(dx: -lineWidth/2, dy: -lineWidth/2)
      context.setFillColor(color.cgColor)
      context.fill(expandedRect)
    } else {
      // 线框模式
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(lineWidth)
      if styleIndex == 0 {
        // 圆角矩形
        let cornerRadius: CGFloat = min(rect.width, rect.height) * 0.15
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.strokePath()
      } else {
        // 直角矩形
        context.stroke(rect)
      }
    }
    
    context.restoreGState()
  }

  private func drawEllipse(in context: CGContext) {
    let rect = CGRect(
      x: min(startPoint.x, endPoint.x),
      y: min(startPoint.y, endPoint.y),
      width: abs(endPoint.x - startPoint.x),
      height: abs(endPoint.y - startPoint.y)
    )

    context.saveGState()

    if styleIndex == 2 {
      // 遮罩模式
      context.setFillColor(color.withAlphaComponent(0.3).cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(lineWidth)
      context.strokeEllipse(in: rect)
    } else if styleIndex == 3 {
      // 实心模式
      let expandedRect = rect.insetBy(dx: -lineWidth/2, dy: -lineWidth/2)
      context.setFillColor(color.cgColor)
      context.fillEllipse(in: expandedRect)
    } else {
      // 线框模式
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(lineWidth)
      context.strokeEllipse(in: rect)
    }
    
    context.restoreGState()
  }

  private func drawLine(in context: CGContext) {
    let dx = endPoint.x - startPoint.x
    let dy = endPoint.y - startPoint.y
    let angle = atan2(dy, dx)
    
    if styleIndex == 1 { // ✅ 流线型/毛笔样式
      context.setFillColor(color.cgColor)
      let startWidth: CGFloat = 0.5
      let endWidth: CGFloat = lineWidth
      let path = CGMutablePath()
      path.move(to: CGPoint(x: startPoint.x + startWidth * cos(angle + .pi/2), y: startPoint.y + startWidth * sin(angle + .pi/2)))
      path.addLine(to: CGPoint(x: startPoint.x + startWidth * cos(angle - .pi/2), y: startPoint.y + startWidth * sin(angle - .pi/2)))
      path.addLine(to: CGPoint(x: endPoint.x + endWidth * cos(angle - .pi/2), y: endPoint.y + endWidth * sin(angle - .pi/2)))
      path.addLine(to: CGPoint(x: endPoint.x + endWidth * cos(angle + .pi/2), y: endPoint.y + endWidth * sin(angle + .pi/2)))
      path.closeSubpath()
      context.addPath(path)
      context.fillPath()
    } else {
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(lineWidth)
      context.setLineCap(.round)
      context.move(to: startPoint)
      context.addLine(to: endPoint)
      context.strokePath()
    }
  }

  private func drawHighlight(in context: CGContext) {
    let rect = CGRect(
      x: min(startPoint.x, endPoint.x),
      y: min(startPoint.y, endPoint.y),
      width: abs(endPoint.x - startPoint.x),
      height: abs(endPoint.y - startPoint.y)
    )

    context.saveGState()
    context.setBlendMode(.multiply)
    context.setFillColor(color.withAlphaComponent(0.4).cgColor)

    let cornerRadius: CGFloat = min(rect.width, rect.height) * 0.2
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    context.addPath(path)
    context.fillPath()
    context.restoreGState()
  }

  private func drawBlur(in context: CGContext, imageSize: NSSize, originalImage: NSImage?) {
    let rect = CGRect(
      x: min(startPoint.x, endPoint.x),
      y: min(startPoint.y, endPoint.y),
      width: abs(endPoint.x - startPoint.x),
      height: abs(endPoint.y - startPoint.y)
    )

    guard rect.width > 2 && rect.height > 2 else { return }

    context.saveGState()
    context.clip(to: rect)

    if let image = originalImage,
       let blurredImage = createBlurredImage(from: image, in: rect, viewSize: imageSize) {
      context.draw(blurredImage, in: rect)
    } else {
      drawPixelatedBlur(in: context, rect: rect)
    }

    context.restoreGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
    context.setLineWidth(0.5)
    context.stroke(rect)
  }

  private func createBlurredImage(from image: NSImage, in rect: CGRect, viewSize: NSSize) -> CGImage? {
    guard let tiffData = image.tiffRepresentation,
          let ciImage = CIImage(data: tiffData) else { return nil }

    let scaleX = ciImage.extent.width / viewSize.width
    let scaleY = ciImage.extent.height / viewSize.height

    let ciRect = CGRect(
      x: rect.origin.x * scaleX,
      y: rect.origin.y * scaleY,
      width: rect.width * scaleX,
      height: rect.height * scaleY
    )

    let cropped = ciImage.cropped(to: ciRect)
    let filter: CIFilter?
    if styleIndex == 3 { // 兼容逻辑：如果是实心模式，用高斯模糊
      filter = CIFilter(name: "CIGaussianBlur")
      filter?.setValue(cropped, forKey: kCIInputImageKey)
      filter?.setValue(max(5, lineWidth * 4), forKey: kCIInputRadiusKey)
    } else {
      filter = CIFilter(name: "CIPixellate")
      filter?.setValue(cropped, forKey: kCIInputImageKey)
      filter?.setValue(max(8, lineWidth * 5), forKey: kCIInputScaleKey)
    }

    guard let output = filter?.outputImage else { return nil }
    let ciContext = CIContext(options: nil)
    return ciContext.createCGImage(output, from: ciRect)
  }

  private func drawPixelatedBlur(in context: CGContext, rect: CGRect) {
    let pixelSize: CGFloat = max(10, min(rect.width, rect.height) / 6)
    var y = rect.origin.y
    while y < rect.maxY {
      var x = rect.origin.x
      while x < rect.maxX {
        let hash = Int(x / pixelSize) * 73856093 + Int(y / pixelSize) * 19349663
        let hue = CGFloat(hash % 360) / 360.0
        let color = NSColor(hue: hue, saturation: 0.15, brightness: 0.85, alpha: 0.95)
        let pixelRect = CGRect(x: x, y: y, width: min(pixelSize, rect.maxX - x), height: min(pixelSize, rect.maxY - y))
        context.setFillColor(color.cgColor)
        context.fill(pixelRect)
        x += pixelSize
      }
      y += pixelSize
    }
  }

  private func drawNumber(in context: CGContext) {
    let radius: CGFloat = fontSize * 0.9 // ✅ 根据字号动态调整圆圈大小
    let circleRect = CGRect(x: startPoint.x - radius, y: startPoint.y - radius, width: radius * 2, height: radius * 2)
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: circleRect)

    let text = "\(number)"
    let attrs: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.white,
      .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
    ]
    let textSize = (text as NSString).size(withAttributes: attrs)
    (text as NSString).draw(at: CGPoint(x: startPoint.x - textSize.width / 2, y: startPoint.y - textSize.height / 2), withAttributes: attrs)
  }

  private func drawPen(in context: CGContext) {
    guard penPoints.count >= 2 else { return }
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: penPoints[0])
    for i in 1..<penPoints.count { context.addLine(to: penPoints[i]) }
    context.strokePath()
  }

  private func drawText() {
    guard !text.isEmpty else { return }
    let attrs = textAttributes
    (text as NSString).draw(at: startPoint, withAttributes: attrs)
  }

  private func drawMeasure(in context: CGContext) {
    let dx = endPoint.x - startPoint.x
    let dy = endPoint.y - startPoint.y
    let distance = sqrt(dx * dx + dy * dy)
    guard distance > 1 else { return }

    context.setStrokeColor(color.cgColor)
    context.setLineWidth(1.5)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.move(to: startPoint)
    context.addLine(to: endPoint)
    context.strokePath()

    context.setLineDash(phase: 0, lengths: [])
    let markSize: CGFloat = 6
    context.move(to: CGPoint(x: startPoint.x - markSize, y: startPoint.y)); context.addLine(to: CGPoint(x: startPoint.x + markSize, y: startPoint.y))
    context.move(to: CGPoint(x: startPoint.x, y: startPoint.y - markSize)); context.addLine(to: CGPoint(x: startPoint.x, y: startPoint.y + markSize))
    context.move(to: CGPoint(x: endPoint.x - markSize, y: endPoint.y)); context.addLine(to: CGPoint(x: endPoint.x + markSize, y: endPoint.y))
    context.move(to: CGPoint(x: endPoint.x, y: endPoint.y - markSize)); context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y + markSize))
    context.strokePath()

    let label = abs(dx) < 2 ? "\(Int(abs(dy)))px" : (abs(dy) < 2 ? "\(Int(abs(dx)))px" : "↔\(Int(abs(dx))) ↕\(Int(abs(dy)))\n⤡\(Int(distance))px")
    let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]
    let size = (label as NSString).size(withAttributes: attrs)
    let mid = CGPoint(x: (startPoint.x + endPoint.x) / 2, y: (startPoint.y + endPoint.y) / 2)
    let bg = CGRect(x: mid.x - size.width / 2 - 4, y: mid.y + 8, width: size.width + 8, height: size.height + 4)
    context.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
    context.fill(bg)
    (label as NSString).draw(at: CGPoint(x: bg.minX + 4, y: bg.minY + 2), withAttributes: attrs)
  }

  private func drawSelectionBorder(in context: CGContext) {
    let rect = boundingRect.insetBy(dx: -3, dy: -3)
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)
    context.setLineDash(phase: 0, lengths: [4, 4])
    context.stroke(rect)
  }
}

extension NSColor {
  func darker(by amount: CGFloat) -> NSColor {
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    self.usingColorSpace(.genericRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return NSColor(hue: h, saturation: s, brightness: max(0, b - amount), alpha: a)
  }
}
