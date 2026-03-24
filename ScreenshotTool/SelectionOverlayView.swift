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
    
    // 状态
    var detectWindows: Bool = false
    var frozenBackground: NSImage?
    
    private var selectionRect: CGRect = .zero
    private var startPoint: CGPoint = .zero
    private var isSelecting = false
    private var isDragging = false
    
    // 拖拽已完成的选区
    private var hasSelection = false
    private var dragOffset: CGPoint = .zero
    
    // 调整大小的句柄
    private enum ResizeHandle {
        case none
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }
    private var activeHandle: ResizeHandle = .none
    private let handleSize: CGFloat = 8
    
    // 十字线跟踪
    private var mouseLocation: CGPoint = .zero
    
    // 工具栏按钮区域
    private var cancelButtonRect: CGRect = .zero
    private var confirmButtonRect: CGRect = .zero
    
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
    }
    
    // MARK: - 绘制
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 0. 冻结背景
        if let bg = frozenBackground {
            bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        // 1. 半透明遮罩
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)
        
        if hasSelection || isSelecting {
            let rect = normalizedRect(selectionRect)
            guard rect.width > 0 && rect.height > 0 else {
                drawCrosshair(context: context)
                return
            }
            
            // 2. 清除选区
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)
            
            // 如果有冻结背景，在选区内重绘
            if let bg = frozenBackground {
                context.saveGState()
                context.clip(to: rect)
                bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                context.restoreGState()
            }
            
            // 3. 选区边框
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
            
            // 4. 三分线
            drawRuleOfThirds(context: context, rect: rect)
            
            // 5. 手柄
            if hasSelection {
                drawResizeHandles(context: context, rect: rect)
            }
            
            // 6. 尺寸信息
            drawSizeInfo(context: context, rect: rect)
            
            // 7. 工具栏
            if hasSelection {
                drawToolbar(context: context, rect: rect)
            }
        } else {
            drawCrosshair(context: context)
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
        
        // 坐标信息
        let coordText = "(\(Int(mouseLocation.x)), \(Int(bounds.height - mouseLocation.y)))"
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
            let xOffset = rect.width * CGFloat(i) / 3
            let yOffset = rect.height * CGFloat(i) / 3
            
            context.move(to: CGPoint(x: rect.origin.x + xOffset, y: rect.origin.y))
            context.addLine(to: CGPoint(x: rect.origin.x + xOffset, y: rect.maxY))
            context.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y + yOffset))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.origin.y + yOffset))
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
            .topLeft:     CGRect(x: rect.minX - hs, y: rect.maxY - hs, width: s, height: s),
            .top:         CGRect(x: rect.midX - hs, y: rect.maxY - hs, width: s, height: s),
            .topRight:    CGRect(x: rect.maxX - hs, y: rect.maxY - hs, width: s, height: s),
            .left:        CGRect(x: rect.minX - hs, y: rect.midY - hs, width: s, height: s),
            .right:       CGRect(x: rect.maxX - hs, y: rect.midY - hs, width: s, height: s),
            .bottomLeft:  CGRect(x: rect.minX - hs, y: rect.minY - hs, width: s, height: s),
            .bottom:      CGRect(x: rect.midX - hs, y: rect.minY - hs, width: s, height: s),
            .bottomRight: CGRect(x: rect.maxX - hs, y: rect.minY - hs, width: s, height: s),
        ]
    }
    
    // MARK: - 尺寸信息
    
    private func drawSizeInfo(context: CGContext, rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        
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
    
    // MARK: - 工具栏（确认/取消按钮）
    
    private func drawToolbar(context: CGContext, rect: CGRect) {
        let buttonSize: CGFloat = 28
        let spacing: CGFloat = 8
        let toolbarWidth: CGFloat = buttonSize * 2 + spacing * 3
        let toolbarHeight: CGFloat = buttonSize + spacing * 2
        
        // 放在选区下方右侧
        var toolbarOrigin = CGPoint(
            x: rect.maxX - toolbarWidth,
            y: rect.minY - toolbarHeight - 8
        )
        
        // 如果超出屏幕底部，放在选区内部底部
        if toolbarOrigin.y < 0 {
            toolbarOrigin.y = rect.minY + 8
        }
        
        let toolbarRect = CGRect(
            origin: toolbarOrigin,
            size: CGSize(width: toolbarWidth, height: toolbarHeight)
        )
        
        // 工具栏背景
        context.setFillColor(NSColor(white: 0.15, alpha: 0.9).cgColor)
        let bgPath = CGPath(roundedRect: toolbarRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(bgPath)
        context.fillPath()
        
        // 取消按钮 ✕
        let cancelRect = CGRect(
            x: toolbarRect.origin.x + spacing,
            y: toolbarRect.origin.y + spacing,
            width: buttonSize,
            height: buttonSize
        )
        
        // 取消按钮背景
        context.setFillColor(NSColor.systemRed.withAlphaComponent(0.8).cgColor)
        let cancelPath = CGPath(roundedRect: cancelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(cancelPath)
        context.fillPath()
        
        let cancelAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 16, weight: .bold)
        ]
        let cancelTextSize = ("✕" as NSString).size(withAttributes: cancelAttrs)
        ("✕" as NSString).draw(
            at: CGPoint(
                x: cancelRect.midX - cancelTextSize.width / 2,
                y: cancelRect.midY - cancelTextSize.height / 2
            ),
            withAttributes: cancelAttrs
        )
        
        // 确认按钮 ✓
        let confirmRect = CGRect(
            x: cancelRect.maxX + spacing,
            y: toolbarRect.origin.y + spacing,
            width: buttonSize,
            height: buttonSize
        )
        
        // 确认按钮背景
        context.setFillColor(NSColor.systemGreen.withAlphaComponent(0.8).cgColor)
        let confirmPath = CGPath(roundedRect: confirmRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(confirmPath)
        context.fillPath()
        
        let confirmAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 16, weight: .bold)
        ]
        let confirmTextSize = ("✓" as NSString).size(withAttributes: confirmAttrs)
        ("✓" as NSString).draw(
            at: CGPoint(
                x: confirmRect.midX - confirmTextSize.width / 2,
                y: confirmRect.midY - confirmTextSize.height / 2
            ),
            withAttributes: confirmAttrs
        )
        
        // ✅ 保存按钮区域用于点击检测（扩大点击区域）
        self.cancelButtonRect = cancelRect.insetBy(dx: -4, dy: -4)
        self.confirmButtonRect = confirmRect.insetBy(dx: -4, dy: -4)
    }
    
    // MARK: - 鼠标事件
    
    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        
        if hasSelection {
            let rect = normalizedRect(selectionRect)
            let handle = hitTestHandle(point: mouseLocation, rect: rect)
            updateCursor(for: handle, point: mouseLocation, rect: rect)
        }
        
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // ✅ 1. 最先检查：双击确认
        if event.clickCount == 2 && hasSelection {
            confirmSelection()
            return
        }
        
        // ✅ 2. 检查工具栏按钮（只在有选区时）
        if hasSelection {
            if confirmButtonRect.contains(point) {
                confirmSelection()
                return  // ← 关键：return 防止继续执行
            }
            if cancelButtonRect.contains(point) {
                onCancel?()
                return  // ← 关键：return 防止继续执行
            }
        }
        
        // ✅ 3. 检查调整大小手柄
        if hasSelection {
            let rect = normalizedRect(selectionRect)
            let handle = hitTestHandle(point: point, rect: rect)
            if handle != .none {
                activeHandle = handle
                isDragging = true
                startPoint = point
                return
            }
            
            // ✅ 4. 检查是否在选区内（拖拽移动）
            if rect.contains(point) {
                isDragging = true
                dragOffset = CGPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
                activeHandle = .none
                startPoint = point
                return
            }
        }
        
        // ✅ 5. 最后：开始新的选区
        startPoint = point
        selectionRect = CGRect(origin: point, size: .zero)
        isSelecting = true
        hasSelection = false
        activeHandle = .none
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point
        
        if isSelecting {
            selectionRect = CGRect(
                x: min(startPoint.x, point.x),
                y: min(startPoint.y, point.y),
                width: abs(point.x - startPoint.x),
                height: abs(point.y - startPoint.y)
            )
        } else if isDragging {
            let rect = normalizedRect(selectionRect)
            
            if activeHandle != .none {
                selectionRect = resizeRect(rect, handle: activeHandle, to: point)
            } else {
                var newOrigin = CGPoint(
                    x: point.x - dragOffset.x,
                    y: point.y - dragOffset.y
                )
                newOrigin.x = max(0, min(newOrigin.x, bounds.width - rect.width))
                newOrigin.y = max(0, min(newOrigin.y, bounds.height - rect.height))
                selectionRect = CGRect(origin: newOrigin, size: rect.size)
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
                // 选区太小，重置
                selectionRect = .zero
                hasSelection = false
            }
        }
        isDragging = false
        activeHandle = .none
        needsDisplay = true
    }
    
    // MARK: - 键盘事件
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:  // ESC
            if hasSelection {
                hasSelection = false
                selectionRect = .zero
                needsDisplay = true
            } else {
                onCancel?()
            }
            
        case 36, 76:  // Enter / Return
            if hasSelection {
                confirmSelection()
            }
            
        case 49:  // Space - 全屏截图
            if !hasSelection {
                selectionRect = bounds
                confirmSelection()
            }
            
        case 123:  // ←
            nudgeSelection(dx: event.modifierFlags.contains(.shift) ? -10 : -1, dy: 0)
        case 124:  // →
            nudgeSelection(dx: event.modifierFlags.contains(.shift) ? 10 : 1, dy: 0)
        case 125:  // ↓
            nudgeSelection(dx: 0, dy: event.modifierFlags.contains(.shift) ? -10 : -1)
        case 126:  // ↑
            nudgeSelection(dx: 0, dy: event.modifierFlags.contains(.shift) ? 10 : 1)
            
        default:
            super.keyDown(with: event)
        }
    }
    
    // MARK: - 确认选区
    
    private func confirmSelection() {
        let rect = normalizedRect(selectionRect)
        guard rect.width > 1 && rect.height > 1 else { return }
        
        // ✅ 先重置状态，防止重复触发
        let completionRect = rect
        hasSelection = false
        selectionRect = .zero
        
        onComplete?(completionRect)
    }
    
    // MARK: - 辅助方法
    
    private func normalizedRect(_ rect: CGRect) -> CGRect {
        return CGRect(
            x: min(rect.origin.x, rect.origin.x + rect.width),
            y: min(rect.origin.y, rect.origin.y + rect.height),
            width: abs(rect.width),
            height: abs(rect.height)
        ).integral  // ✅ 对齐到整数像素，避免亚像素问题
    }
    
    private func hitTestHandle(point: CGPoint, rect: CGRect) -> ResizeHandle {
        let handles = getHandleRects(for: rect)
        let hitArea: CGFloat = 12
        
        for (handle, handleRect) in handles {
            let expandedRect = handleRect.insetBy(dx: -hitArea / 2, dy: -hitArea / 2)
            if expandedRect.contains(point) {
                return handle
            }
        }
        return .none
    }
    
    private func updateCursor(for handle: ResizeHandle, point: CGPoint, rect: CGRect) {
        switch handle {
        case .topLeft, .bottomRight:
            NSCursor.crosshair.set()
        case .topRight, .bottomLeft:
            NSCursor.crosshair.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .none:
            if rect.contains(point) {
                NSCursor.openHand.set()
            } else {
                NSCursor.crosshair.set()
            }
        }
    }
    
    private func resizeRect(_ rect: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var newRect = rect
        
        switch handle {
        case .topLeft:
            newRect = CGRect(x: point.x, y: rect.minY,
                            width: rect.maxX - point.x, height: point.y - rect.minY)
        case .top:
            newRect = CGRect(x: rect.minX, y: rect.minY,
                            width: rect.width, height: point.y - rect.minY)
        case .topRight:
            newRect = CGRect(x: rect.minX, y: rect.minY,
                            width: point.x - rect.minX, height: point.y - rect.minY)
        case .left:
            newRect = CGRect(x: point.x, y: rect.minY,
                            width: rect.maxX - point.x, height: rect.height)
        case .right:
            newRect = CGRect(x: rect.minX, y: rect.minY,
                            width: point.x - rect.minX, height: rect.height)
        case .bottomLeft:
            newRect = CGRect(x: point.x, y: point.y,
                            width: rect.maxX - point.x, height: rect.maxY - point.y)
        case .bottom:
            newRect = CGRect(x: rect.minX, y: point.y,
                            width: rect.width, height: rect.maxY - point.y)
        case .bottomRight:
            newRect = CGRect(x: rect.minX, y: point.y,
                            width: point.x - rect.minX, height: rect.maxY - point.y)
        case .none:
            break
        }
        
        return newRect
    }
    
    private func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard hasSelection else { return }
        selectionRect.origin.x += dx
        selectionRect.origin.y += dy
        needsDisplay = true
    }
}
