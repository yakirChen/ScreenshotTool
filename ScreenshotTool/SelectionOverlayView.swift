//
//  SelectionOverlayView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class SelectionOverlayView: NSView {

    // 回调
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    // 屏幕信息
    var associatedScreen: NSScreen?

    // 状态
    var detectWindows: Bool = false
    var frozenBackground: NSImage?

    private var selectionRect: CGRect = .zero
    private var startPoint: CGPoint = .zero
    private var isSelecting = false
    private var isDragging = false

    private var hasSelection = false
    private var dragOffset: CGPoint = .zero
    // ✅ 新增属性：拖拽时记录固定的选区尺寸
    private var dragStartSize: CGSize = .zero

    private enum ResizeHandle {
        case none
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }
    private var activeHandle: ResizeHandle = .none
    private let handleSize: CGFloat = 8

    private var mouseLocation: CGPoint = .zero

    private var cancelButtonRect: CGRect = .zero
    private var confirmButtonRect: CGRect = .zero

    // 窗口检测
    private let windowDetector = WindowDetector()
    private var detectedWindowFrame: CGRect?
    private var windowsLoaded = false

    // MARK: - 设置

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        if detectWindows {
            Task {
                await windowDetector.refresh(for: associatedScreen)
                await MainActor.run {
                    windowsLoaded = true
                }
            }
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 冻结背景
        if let bg = frozenBackground {
            // 多屏时需要只绘制当前屏幕对应的部分
            drawFrozenBackground(bg, in: context)
        }

        // 遮罩
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)

        if hasSelection || isSelecting {
            let rect = normalizedRect(selectionRect)
            guard rect.width > 0 && rect.height > 0 else {
                drawWindowHighlightIfNeeded(context: context)
                drawCrosshair(context: context)
                return
            }

            // 清除选区
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            // 选区内重绘背景
            if let bg = frozenBackground {
                context.saveGState()
                context.clip(to: rect)
                drawFrozenBackground(bg, in: context)
                context.restoreGState()
            }

            // 边框
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))

            drawRuleOfThirds(context: context, rect: rect)

            if hasSelection {
                drawResizeHandles(context: context, rect: rect)
                drawToolbar(context: context, rect: rect)
            }

            drawSizeInfo(context: context, rect: rect)
        } else {
            drawWindowHighlightIfNeeded(context: context)
            drawCrosshair(context: context)
        }
    }

    /// 绘制冻结背景（处理多屏偏移）
    private func drawFrozenBackground(_ bg: NSImage, in context: CGContext) {
        if let screen = associatedScreen {
            // 多屏幕时，冻结背景是主屏的截图
            // 如果当前是主屏，直接绘制
            // 如果是副屏，需要用该屏幕自己的冻结背景
            bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    // MARK: - 窗口检测高亮

    private func drawWindowHighlightIfNeeded(context: CGContext) {
        guard detectWindows && !hasSelection && !isSelecting && windowsLoaded else { return }

        if let window = windowDetector.detectWindow(at: mouseLocation) {
            detectedWindowFrame = window.viewFrame

            let rect = window.viewFrame

            // 清除遮罩
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            // 重绘背景
            if let bg = frozenBackground {
                context.saveGState()
                context.clip(to: rect)
                bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                context.restoreGState()
            }

            // 蓝色边框
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(2)
            context.stroke(rect)

            // 应用名标签
            let labelText = window.appName.isEmpty ? "窗口" : window.appName
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
            let textSize = (labelText as NSString).size(withAttributes: attrs)
            let labelRect = CGRect(
                x: rect.origin.x,
                y: rect.maxY + 4,
                width: textSize.width + 12,
                height: textSize.height + 6
            )

            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
            let bgPath = CGPath(
                roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.fillPath()

            (labelText as NSString).draw(
                at: CGPoint(x: labelRect.origin.x + 6, y: labelRect.origin.y + 3),
                withAttributes: attrs
            )
        } else {
            detectedWindowFrame = nil
        }
    }

    // MARK: - 十字线

    private func drawCrosshair(context: CGContext) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [5, 5])

        context.move(to: CGPoint(x: 0, y: mouseLocation.y))
        context.addLine(to: CGPoint(x: bounds.width, y: mouseLocation.y))
        context.move(to: CGPoint(x: mouseLocation.x, y: 0))
        context.addLine(to: CGPoint(x: mouseLocation.x, y: bounds.height))
        context.strokePath()

        // 坐标（显示屏幕坐标）
        let screenX = Int(mouseLocation.x)
        let screenY = Int(bounds.height - mouseLocation.y)
        let coordText = "(\(screenX), \(screenY))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]

        let textSize = (coordText as NSString).size(withAttributes: attrs)
        let bgRect = CGRect(
            x: mouseLocation.x + 15,
            y: mouseLocation.y + 10,
            width: textSize.width + 10,
            height: textSize.height + 6
        )

        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.setLineDash(phase: 0, lengths: [])
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        (coordText as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + 5, y: bgRect.origin.y + 3),
            withAttributes: attrs
        )
    }

    // MARK: - 三分线

    private func drawRuleOfThirds(context: CGContext, rect: CGRect) {
        guard rect.width > 30 && rect.height > 30 else { return }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [])

        for i in 1...2 {
            let xOff = rect.width * CGFloat(i) / 3
            let yOff = rect.height * CGFloat(i) / 3

            context.move(to: CGPoint(x: rect.origin.x + xOff, y: rect.origin.y))
            context.addLine(to: CGPoint(x: rect.origin.x + xOff, y: rect.maxY))
            context.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y + yOff))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.origin.y + yOff))
        }
        context.strokePath()
    }

    // MARK: - 手柄

    private func drawResizeHandles(context: CGContext, rect: CGRect) {
        let handles = getHandleRects(for: rect)
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1)

        for handleRect in handles.values {
            context.fillEllipse(in: handleRect)
            context.strokeEllipse(in: handleRect)
        }
    }

    private func getHandleRects(for rect: CGRect) -> [ResizeHandle: CGRect] {
        let s = handleSize
        let hs = s / 2
        return [
            .topLeft: CGRect(x: rect.minX - hs, y: rect.maxY - hs, width: s, height: s),
            .top: CGRect(x: rect.midX - hs, y: rect.maxY - hs, width: s, height: s),
            .topRight: CGRect(x: rect.maxX - hs, y: rect.maxY - hs, width: s, height: s),
            .left: CGRect(x: rect.minX - hs, y: rect.midY - hs, width: s, height: s),
            .right: CGRect(x: rect.maxX - hs, y: rect.midY - hs, width: s, height: s),
            .bottomLeft: CGRect(x: rect.minX - hs, y: rect.minY - hs, width: s, height: s),
            .bottom: CGRect(x: rect.midX - hs, y: rect.minY - hs, width: s, height: s),
            .bottomRight: CGRect(x: rect.maxX - hs, y: rect.minY - hs, width: s, height: s)
        ]
    }

    // MARK: - 尺寸信息

    private func drawSizeInfo(context: CGContext, rect: CGRect) {
        // 显示实际像素尺寸（考虑 Retina）
        let scale = associatedScreen?.backingScaleFactor ?? 2
        let pixelW = Int(rect.width * scale)
        let pixelH = Int(rect.height * scale)
        let text = "\(Int(rect.width))×\(Int(rect.height)) (\(pixelW)×\(pixelH)px)"

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        ]

        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let bgWidth = textSize.width + padding * 2
        let bgHeight = textSize.height + padding

        var bgOrigin = CGPoint(x: rect.origin.x, y: rect.maxY + 6)
        if bgOrigin.y + bgHeight > bounds.height {
            bgOrigin.y = rect.maxY - bgHeight - 4
        }

        let bgRect = CGRect(origin: bgOrigin, size: CGSize(width: bgWidth, height: bgHeight))

        context.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs
        )
    }

    // MARK: - 工具栏

    private func drawToolbar(context: CGContext, rect: CGRect) {
        let buttonSize: CGFloat = 28
        let spacing: CGFloat = 8
        let toolbarWidth: CGFloat = buttonSize * 2 + spacing * 3
        let toolbarHeight: CGFloat = buttonSize + spacing * 2

        var toolbarOrigin = CGPoint(
            x: rect.maxX - toolbarWidth,
            y: rect.minY - toolbarHeight - 8
        )
        if toolbarOrigin.y < 0 {
            toolbarOrigin.y = rect.minY + 8
        }

        let toolbarRect = CGRect(
            origin: toolbarOrigin, size: CGSize(width: toolbarWidth, height: toolbarHeight))

        context.setFillColor(NSColor(white: 0.15, alpha: 0.9).cgColor)
        let bgPath = CGPath(
            roundedRect: toolbarRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        // 取消 ✕
        let cancelRect = CGRect(
            x: toolbarRect.origin.x + spacing, y: toolbarRect.origin.y + spacing, width: buttonSize,
            height: buttonSize)
        context.setFillColor(NSColor.systemRed.withAlphaComponent(0.8).cgColor)
        context.addPath(
            CGPath(roundedRect: cancelRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()

        let cancelAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 16, weight: .bold)
        ]
        let cancelSize = ("✕" as NSString).size(withAttributes: cancelAttrs)
        ("✕" as NSString).draw(
            at: CGPoint(
                x: cancelRect.midX - cancelSize.width / 2,
                y: cancelRect.midY - cancelSize.height / 2), withAttributes: cancelAttrs)

        // 确认 ✓
        let confirmRect = CGRect(
            x: cancelRect.maxX + spacing, y: toolbarRect.origin.y + spacing, width: buttonSize,
            height: buttonSize)
        context.setFillColor(NSColor.systemGreen.withAlphaComponent(0.8).cgColor)
        context.addPath(
            CGPath(roundedRect: confirmRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()

        let confirmAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 16, weight: .bold)
        ]
        let confirmSize = ("✓" as NSString).size(withAttributes: confirmAttrs)
        ("✓" as NSString).draw(
            at: CGPoint(
                x: confirmRect.midX - confirmSize.width / 2,
                y: confirmRect.midY - confirmSize.height / 2), withAttributes: confirmAttrs)

        self.cancelButtonRect = cancelRect.insetBy(dx: -4, dy: -4)
        self.confirmButtonRect = confirmRect.insetBy(dx: -4, dy: -4)
    }

    // MARK: - 鼠标事件

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)

        // ✅ 多屏：鼠标移入时自动获取焦点
        if let myWindow = self.window as? SelectionOverlayWindow,
           !myWindow.isKeyWindow {
            myWindow.makeKeyAndOrderFront(nil)
            myWindow.makeFirstResponder(self)
        }

        if hasSelection {
            let rect = normalizedRect(selectionRect)
            let handle = hitTestHandle(point: mouseLocation, rect: rect)
            updateCursor(for: handle, point: mouseLocation, rect: rect)
        }

        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 双击确认
        if event.clickCount == 2 && hasSelection {
            confirmSelection()
            return
        }

        if hasSelection {
            // 检查工具栏按钮
            if confirmButtonRect.contains(point) {
                confirmSelection()
                return
            }
            if cancelButtonRect.contains(point) {
                onCancel?()
                return
            }

            let rect = normalizedRect(selectionRect)

            // 检查调整手柄
            let handle = hitTestHandle(point: point, rect: rect)
            if handle != .none {
                activeHandle = handle
                isDragging = true
                isSelecting = false  // ✅ 确保不会同时选择
                startPoint = point
                return
            }

            // 检查是否在选区内（拖拽移动）
            if rect.contains(point) {
                isDragging = true
                isSelecting = false  // ✅ 确保不会同时选择
                activeHandle = .none
                // ✅ 记录鼠标相对于选区 origin 的偏移
                dragOffset = CGPoint(
                    x: point.x - rect.origin.x,
                    y: point.y - rect.origin.y
                )
                // ✅ 记录拖拽开始时的选区尺寸（固定不变）
                dragStartSize = rect.size
                return
            }
        }

        // 窗口检测点击
        if detectWindows && !hasSelection {
            if let windowFrame = detectedWindowFrame {
                selectionRect = windowFrame
                hasSelection = true
                detectedWindowFrame = nil
                needsDisplay = true
                return
            }
        }

        // ✅ 开始全新的选区（确保清除拖拽状态）
        isDragging = false
        activeHandle = .none
        startPoint = point
        selectionRect = CGRect(origin: point, size: .zero)
        isSelecting = true
        hasSelection = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point

        if isSelecting && !isDragging {
            // ✅ 拉新选区
            selectionRect = CGRect(
                x: min(startPoint.x, point.x),
                y: min(startPoint.y, point.y),
                width: abs(point.x - startPoint.x),
                height: abs(point.y - startPoint.y)
            )
        } else if isDragging && !isSelecting {
            if activeHandle != .none {
                // ✅ 调整大小
                selectionRect = resizeRect(
                    normalizedRect(selectionRect), handle: activeHandle, to: point)
            } else {
                // ✅ 移动选区：用固定的 dragStartSize，不从当前 selectionRect 取
                var newX = point.x - dragOffset.x
                var newY = point.y - dragOffset.y

                // 限制在屏幕范围内
                newX = max(0, min(newX, bounds.width - dragStartSize.width))
                newY = max(0, min(newY, bounds.height - dragStartSize.height))

                selectionRect = CGRect(
                    x: newX,
                    y: newY,
                    width: dragStartSize.width,
                    height: dragStartSize.height
                )
            }
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isSelecting {
            isSelecting = false
            let rect = normalizedRect(selectionRect)
            if rect.width > 3 && rect.height > 3 {
                hasSelection = true
                selectionRect = rect
            } else {
                selectionRect = .zero
                hasSelection = false
            }
        }

        isDragging = false
        activeHandle = .none
        needsDisplay = true
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            if hasSelection {
                hasSelection = false
                selectionRect = .zero
                needsDisplay = true
            } else {
                onCancel?()
            }
        case 36, 76:
            if hasSelection { confirmSelection() }
        case 49:
            if !hasSelection {
                selectionRect = bounds
                confirmSelection()
            }
        case 123: nudgeSelection(dx: event.modifierFlags.contains(.shift) ? -10 : -1, dy: 0)
        case 124: nudgeSelection(dx: event.modifierFlags.contains(.shift) ? 10 : 1, dy: 0)
        case 125: nudgeSelection(dx: 0, dy: event.modifierFlags.contains(.shift) ? -10 : -1)
        case 126: nudgeSelection(dx: 0, dy: event.modifierFlags.contains(.shift) ? 10 : 1)
        default: super.keyDown(with: event)
        }
    }

    // MARK: - 辅助

    private func confirmSelection() {
        let rect = normalizedRect(selectionRect)
        guard rect.width > 1 && rect.height > 1 else { return }
        let completionRect = rect
        hasSelection = false
        selectionRect = .zero
        onComplete?(completionRect)
    }

    private func normalizedRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(rect.origin.x, rect.origin.x + rect.width),
            y: min(rect.origin.y, rect.origin.y + rect.height),
            width: abs(rect.width), height: abs(rect.height)
        ).integral
    }

    private func hitTestHandle(point: CGPoint, rect: CGRect) -> ResizeHandle {
        let handles = getHandleRects(for: rect)
        for (handle, handleRect) in handles {
            if handleRect.insetBy(dx: -6, dy: -6).contains(point) { return handle }
        }
        return .none
    }

    private func updateCursor(for handle: ResizeHandle, point: CGPoint, rect: CGRect) {
        switch handle {
        case .top, .bottom: NSCursor.resizeUpDown.set()
        case .left, .right: NSCursor.resizeLeftRight.set()
        case .none: rect.contains(point) ? NSCursor.openHand.set() : NSCursor.crosshair.set()
        default: NSCursor.crosshair.set()
        }
    }

    private func resizeRect(_ rect: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        switch handle {
        case .topLeft:
            return CGRect(
                x: point.x, y: rect.minY, width: rect.maxX - point.x, height: point.y - rect.minY)
        case .top:
            return CGRect(
                x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
        case .topRight:
            return CGRect(
                x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
        case .left:
            return CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: rect.height)
        case .right:
            return CGRect(
                x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: rect.height)
        case .bottomLeft:
            return CGRect(
                x: point.x, y: point.y, width: rect.maxX - point.x, height: rect.maxY - point.y)
        case .bottom:
            return CGRect(x: rect.minX, y: point.y, width: rect.width, height: rect.maxY - point.y)
        case .bottomRight:
            return CGRect(
                x: rect.minX, y: point.y, width: point.x - rect.minX, height: rect.maxY - point.y)
        case .none: return rect
        }
    }

    private func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard hasSelection else { return }
        selectionRect.origin.x += dx
        selectionRect.origin.y += dy
        needsDisplay = true
    }
}
