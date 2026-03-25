//
//  Annotation.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

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

    // 画笔专用
    var penPoints: [CGPoint] = []

    // 编号专用
    var number: Int = 1

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
            let radius: CGFloat = 14
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
        return [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ]
    }

    /// 检测点是否在标注上
    func hitTest(point: CGPoint) -> Bool {
        return boundingRect.insetBy(dx: -5, dy: -5).contains(point)
    }

    // MARK: - 绘制

    func draw(in context: CGContext, imageSize: NSSize) {
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
            drawBlur(in: context, imageSize: imageSize)
        case .number:
            drawNumber(in: context)
        case .pen:
            drawPen(in: context)
        case .text:
            drawText()
        case .measure:
            drawMeasure(in: context)
        case .ocr:
            break
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
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // 线段
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()

        // 箭头头部
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowLength: CGFloat = max(12, lineWidth * 5)
        let arrowAngle: CGFloat = .pi / 7

        let p1 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle - arrowAngle),
            y: endPoint.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle + arrowAngle),
            y: endPoint.y - arrowLength * sin(angle + arrowAngle)
        )

        // 实心箭头
        context.setFillColor(color.cgColor)
        context.move(to: endPoint)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    private func drawRectangle(in context: CGContext) {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.round)
        context.stroke(rect)
    }

    private func drawEllipse(in context: CGContext) {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: rect)
    }

    private func drawLine(in context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
    }

    private func drawHighlight(in context: CGContext) {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        context.setFillColor(color.withAlphaComponent(0.35).cgColor)
        context.fill(rect)
    }

    private func drawBlur(in context: CGContext, imageSize: NSSize) {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        guard rect.width > 2 && rect.height > 2 else { return }

        // 马赛克效果：用小方块填充
        let blockSize: CGFloat = max(8, min(rect.width, rect.height) / 8)

        context.saveGState()
        context.clip(to: rect)

        var y = rect.origin.y
        var row = 0
        while y < rect.maxY {
            var x = rect.origin.x
            var col = 0
            while x < rect.maxX {
                // 交替颜色产生马赛克效果
                let gray = (row + col) % 2 == 0 ? 0.7 : 0.85
                context.setFillColor(NSColor(white: gray, alpha: 0.9).cgColor)
                context.fill(CGRect(x: x, y: y, width: blockSize, height: blockSize))
                x += blockSize
                col += 1
            }
            y += blockSize
            row += 1
        }

        context.restoreGState()
    }

    private func drawNumber(in context: CGContext) {
        let radius: CGFloat = 14
        let circleRect = CGRect(
            x: startPoint.x - radius,
            y: startPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        // 圆形背景
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: circleRect)

        // 数字
        let text = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14, weight: .bold)
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textPoint = CGPoint(
            x: startPoint.x - textSize.width / 2,
            y: startPoint.y - textSize.height / 2
        )
        (text as NSString).draw(at: textPoint, withAttributes: attrs)
    }

    private func drawPen(in context: CGContext) {
        guard penPoints.count >= 2 else { return }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: penPoints[0])
        for i in 1..<penPoints.count {
            context.addLine(to: penPoints[i])
        }
        context.strokePath()
    }

    private func drawText() {
        guard !text.isEmpty else { return }
        (text as NSString).draw(at: startPoint, withAttributes: textAttributes)
    }

    private func drawSelectionBorder(in context: CGContext) {
        let rect = boundingRect.insetBy(dx: -3, dy: -3)

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(rect)
    }

    // 新增测量绘制方法：
    private func drawMeasure(in context: CGContext) {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > 1 else { return }

        // 虚线
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()

        // 端点标记
        context.setLineDash(phase: 0, lengths: [])
        let markSize: CGFloat = 6

        // 起点十字
        context.move(to: CGPoint(x: startPoint.x - markSize, y: startPoint.y))
        context.addLine(to: CGPoint(x: startPoint.x + markSize, y: startPoint.y))
        context.move(to: CGPoint(x: startPoint.x, y: startPoint.y - markSize))
        context.addLine(to: CGPoint(x: startPoint.x, y: startPoint.y + markSize))
        context.strokePath()

        // 终点十字
        context.move(to: CGPoint(x: endPoint.x - markSize, y: endPoint.y))
        context.addLine(to: CGPoint(x: endPoint.x + markSize, y: endPoint.y))
        context.move(to: CGPoint(x: endPoint.x, y: endPoint.y - markSize))
        context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y + markSize))
        context.strokePath()

        // 距离标签
        let absDx = abs(dx)
        let absDy = abs(dy)
        let text: String
        if absDx < 2 {
            text = "\(Int(absDy))px"
        } else if absDy < 2 {
            text = "\(Int(absDx))px"
        } else {
            text = "↔\(Int(absDx)) ↕\(Int(absDy))\n⤡\(Int(distance))px"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        ]

        let textSize = (text as NSString).size(withAttributes: attrs)
        let midPoint = CGPoint(
            x: (startPoint.x + endPoint.x) / 2,
            y: (startPoint.y + endPoint.y) / 2
        )

        let bgPadding: CGFloat = 4
        let bgRect = CGRect(
            x: midPoint.x - textSize.width / 2 - bgPadding,
            y: midPoint.y + 8,
            width: textSize.width + bgPadding * 2,
            height: textSize.height + bgPadding * 2
        )

        context.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + bgPadding, y: bgRect.origin.y + bgPadding),
            withAttributes: attrs
        )
    }
}
