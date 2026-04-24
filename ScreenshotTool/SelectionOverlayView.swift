//
//  SelectionOverlayView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class SelectionOverlayView: NSView {

    // MARK: - 回调
    var onComplete: ((CGRect, NSImage?) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - 屏幕/模式
    var associatedScreen: NSScreen?
    var detectWindows: Bool = false {
        didSet { if detectWindows != oldValue { needsDisplay = true } }
    }
    var frozenBackground: NSImage?
    var showControlBar: Bool = true
    var captureMode: CaptureMode = .area {
        didSet { handleModeChange() }
    }

    // MARK: - 选区状态
    private var selectionRect: CGRect = .zero
    private var startPoint: CGPoint = .zero
    private var isSelecting = false
    private var isDragging = false
    private var hasSelection = false
    private var dragOffset: CGPoint = .zero
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

    // MARK: - 窗口检测
    private let windowDetector = WindowDetector()
    private var detectedWindowFrame: CGRect?
    private var windowsLoaded = false

    // MARK: - 控制栏
    private var controlBar: CaptureControlBar?

    var overlayMessage: String {
        if !showControlBar {
            return detectWindows
                ? "点击窗口截图 · Space 返回选区 · ESC 取消"
                : "拖动选择区域 · Space 切换窗口 · ESC 取消"
        }
        return "拖动选择区域 · Return 截图 · ESC 取消"
    }

    // MARK: - 设置

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea)

        setupControlBar()
        restoreLastSelectionIfNeeded()

        if detectWindows {
            Task {
                await windowDetector.refresh(for: associatedScreen)
                await MainActor.run { windowsLoaded = true; needsDisplay = true }
            }
        }
    }

    private func setupControlBar() {
        guard showControlBar else { return }
        let bar = CaptureControlBar(frame: NSRect(origin: .zero, size: effectiveControlBarSize()))
        bar.delegate = self
        bar.mode = captureMode
        bar.translatesAutoresizingMaskIntoConstraints = true
        let size = effectiveControlBarSize()
        bar.frame = NSRect(
            x: (bounds.width - size.width) / 2,
            y: 40,
            width: size.width,
            height: size.height
        )
        bar.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        addSubview(bar)
        controlBar = bar
        updateControlBarPosition()
    }

    private func restoreLastSelectionIfNeeded() {
        guard PreferencesManager.shared.rememberLastSelection,
              let rect = PreferencesManager.shared.lastSelectionRect,
              bounds.contains(rect.origin),
              bounds.contains(CGPoint(x: rect.maxX, y: rect.maxY)),
              rect.width > 3, rect.height > 3 else { return }
        selectionRect = rect
        hasSelection = true
        needsDisplay = true
        updateControlBarPosition()
    }

    private func handleModeChange() {
        switch captureMode {
        case .fullScreen:
            selectionRect = bounds
            hasSelection = true
            detectWindows = false
        case .window:
            hasSelection = false
            selectionRect = .zero
            detectWindows = true
            if !windowsLoaded {
                Task {
                    await windowDetector.refresh(for: associatedScreen)
                    await MainActor.run { windowsLoaded = true; needsDisplay = true }
                }
            }
        case .area:
            hasSelection = false
            selectionRect = .zero
            detectWindows = false
        }
        updateControlBarPosition()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateControlBarPosition()
    }

    private func updateControlBarPosition() {
        guard showControlBar, let bar = controlBar else { return }

        let size = effectiveControlBarSize()
        if bar.frame.size != size {
            bar.frame.size = size
        }
        let margin: CGFloat = 12

        if (hasSelection || isSelecting) && captureMode != .fullScreen {
            let rect = normalizedRect(selectionRect)
            guard rect.width > 3, rect.height > 3 else {
                bar.frame = NSRect(
                    x: (bounds.width - size.width) / 2,
                    y: 40,
                    width: size.width,
                    height: size.height
                )
                return
            }
            var x = rect.midX - size.width / 2
            x = max(margin, min(x, bounds.width - size.width - margin))

            var y = rect.minY - size.height - 10
            if y < margin {
                y = rect.maxY + 10
            }
            y = min(y, bounds.height - size.height - margin)

            bar.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        } else {
            bar.frame = NSRect(
                x: (bounds.width - size.width) / 2,
                y: 40,
                width: size.width,
                height: size.height
            )
        }
    }

    private func effectiveControlBarSize() -> NSSize {
        let preferred = CaptureControlBar.preferredSize()
        let maxWidth = max(280, bounds.width - 24)
        return NSSize(width: min(preferred.width, maxWidth), height: preferred.height)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let bg = frozenBackground {
            drawFrozenBackground(bg, in: context)
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)

        if hasSelection || isSelecting {
            let rect = normalizedRect(selectionRect)
            guard rect.width > 0, rect.height > 0 else {
                drawWindowHighlightIfNeeded(context: context)
                drawCrosshair(context: context)
                return
            }

            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            if let bg = frozenBackground {
                context.saveGState()
                context.clip(to: rect)
                drawFrozenBackground(bg, in: context)
                context.restoreGState()
            }

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))

            drawRuleOfThirds(context: context, rect: rect)

            if hasSelection && captureMode != .fullScreen {
                drawResizeHandles(context: context, rect: rect)
            }
            drawSizeInfo(context: context, rect: rect)
        } else {
            drawWindowHighlightIfNeeded(context: context)
            drawCrosshair(context: context)
            drawInstructionText(context: context)
        }
    }

    private func drawInstructionText(context: CGContext) {
        let text = overlayMessage
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 12
        let bgWidth = textSize.width + padding * 2
        let bgHeight = textSize.height + padding
        let bgRect = CGRect(
            x: (bounds.width - bgWidth) / 2,
            y: bounds.height - bgHeight - 40,
            width: bgWidth, height: bgHeight
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path); context.fillPath()

        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs
        )
    }

    private func drawFrozenBackground(_ bg: NSImage, in context: CGContext) {
        bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    // MARK: - 窗口高亮

    private func drawWindowHighlightIfNeeded(context: CGContext) {
        guard detectWindows && !hasSelection && !isSelecting && windowsLoaded else { return }

        if let window = windowDetector.detectWindow(at: mouseLocation) {
            detectedWindowFrame = window.viewFrame
            let rect = window.viewFrame

            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            if let bg = frozenBackground {
                context.saveGState()
                context.clip(to: rect)
                bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                context.restoreGState()
            }

            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(2)
            context.stroke(rect)

            let labelText = window.appName.isEmpty ? "窗口" : window.appName
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
            let textSize = (labelText as NSString).size(withAttributes: attrs)
            let labelRect = CGRect(
                x: rect.origin.x, y: rect.maxY + 4,
                width: textSize.width + 12, height: textSize.height + 6
            )
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
            context.addPath(CGPath(roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.fillPath()
            (labelText as NSString).draw(
                at: CGPoint(x: labelRect.origin.x + 6, y: labelRect.origin.y + 3),
                withAttributes: attrs
            )
        } else {
            detectedWindowFrame = nil
        }
    }

    private func drawCrosshair(context: CGContext) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [5, 5])

        context.move(to: CGPoint(x: 0, y: mouseLocation.y))
        context.addLine(to: CGPoint(x: bounds.width, y: mouseLocation.y))
        context.move(to: CGPoint(x: mouseLocation.x, y: 0))
        context.addLine(to: CGPoint(x: mouseLocation.x, y: bounds.height))
        context.strokePath()

        let screenX = Int(mouseLocation.x)
        let screenY = Int(bounds.height - mouseLocation.y)
        let coordText = "(\(screenX), \(screenY))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        let textSize = (coordText as NSString).size(withAttributes: attrs)
        let bgRect = CGRect(
            x: mouseLocation.x + 15, y: mouseLocation.y + 10,
            width: textSize.width + 10, height: textSize.height + 6
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.setLineDash(phase: 0, lengths: [])
        context.addPath(CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()

        (coordText as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + 5, y: bgRect.origin.y + 3),
            withAttributes: attrs
        )
    }

    private func drawRuleOfThirds(context: CGContext, rect: CGRect) {
        guard rect.width > 30, rect.height > 30 else { return }
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

    private func drawSizeInfo(context: CGContext, rect: CGRect) {
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
        context.addPath(CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()
        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs
        )
    }

    // MARK: - 鼠标事件

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)

        if let myWindow = self.window as? SelectionOverlayWindow, !myWindow.isKeyWindow {
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

        // 点击底部控制栏由其自身处理，不进入选区逻辑
        if let bar = controlBar, bar.frame.contains(point) { return }

        if captureMode == .fullScreen { return }

        if event.clickCount == 2 && hasSelection {
            confirmSelection()
            return
        }

        if hasSelection {
            let rect = normalizedRect(selectionRect)
            let handle = hitTestHandle(point: point, rect: rect)
            if handle != .none {
                activeHandle = handle
                isDragging = true
                isSelecting = false
                startPoint = point
                return
            }
            if rect.contains(point) {
                isDragging = true
                isSelecting = false
                activeHandle = .none
                dragOffset = CGPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
                dragStartSize = rect.size
                return
            }
        }

        if detectWindows && !hasSelection, let windowFrame = detectedWindowFrame {
            selectionRect = windowFrame
            hasSelection = true
            detectedWindowFrame = nil
            updateControlBarPosition()
            needsDisplay = true
            if captureMode == .window, PreferencesManager.shared.windowCaptureSingleClick {
                confirmSelection()
            }
            return
        }

        isDragging = false
        activeHandle = .none
        startPoint = point
        selectionRect = CGRect(origin: point, size: .zero)
        isSelecting = true
        hasSelection = false
        updateControlBarPosition()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point

        if captureMode == .fullScreen { return }

        if isSelecting && !isDragging {
            selectionRect = CGRect(
                x: min(startPoint.x, point.x),
                y: min(startPoint.y, point.y),
                width: abs(point.x - startPoint.x),
                height: abs(point.y - startPoint.y)
            )
        } else if isDragging && !isSelecting {
            if activeHandle != .none {
                selectionRect = resizeRect(normalizedRect(selectionRect), handle: activeHandle, to: point)
            } else {
                var newX = point.x - dragOffset.x
                var newY = point.y - dragOffset.y
                newX = max(0, min(newX, bounds.width - dragStartSize.width))
                newY = max(0, min(newY, bounds.height - dragStartSize.height))
                selectionRect = CGRect(x: newX, y: newY, width: dragStartSize.width, height: dragStartSize.height)
            }
        }
        updateControlBarPosition()
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
        updateControlBarPosition()
        needsDisplay = true
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: // ESC
            if hasSelection && captureMode != .fullScreen {
                hasSelection = false
                selectionRect = .zero
                updateControlBarPosition()
                needsDisplay = true
            } else {
                onCancel?()
            }
        case 36, 76: // Return/Enter
            if captureMode == .fullScreen {
                selectionRect = bounds
                hasSelection = true
                confirmSelection()
            } else if hasSelection {
                confirmSelection()
            }
        case 49: // Space
            if !showControlBar && !hasSelection {
                // ⌘⇧4 + Space: 切换窗口高亮模式（对齐原生行为）
                detectWindows.toggle()
                if detectWindows && !windowsLoaded {
                    Task {
                        await windowDetector.refresh(for: associatedScreen)
                        await MainActor.run { windowsLoaded = true; needsDisplay = true }
                    }
                }
                needsDisplay = true
            } else if showControlBar {
                // 控制面板模式下，Space 不触发立即截图，避免误触。
                // 窗口模式下可用于进入/维持窗口高亮。
                if captureMode == .window && !detectWindows {
                    detectWindows = true
                    needsDisplay = true
                }
            }
        case 123: nudgeSelection(dx: shift ? -10 : -1, dy: 0)
        case 124: nudgeSelection(dx: shift ? 10 : 1, dy: 0)
        case 125: nudgeSelection(dx: 0, dy: shift ? -10 : -1)
        case 126: nudgeSelection(dx: 0, dy: shift ? 10 : 1)
        default: super.keyDown(with: event)
        }
    }

    // MARK: - 辅助

    private func confirmSelection() {
        let rect = normalizedRect(selectionRect)
        guard rect.width > 1, rect.height > 1 else { return }

        if PreferencesManager.shared.rememberLastSelection && captureMode == .area {
            PreferencesManager.shared.lastSelectionRect = rect
        }

        // 倒计时
        let seconds = PreferencesManager.shared.captureTimerSeconds
        if seconds > 0 {
            runCountdown(seconds: seconds) { [weak self] in
                self?.performCapture(rect: rect)
            }
        } else {
            performCapture(rect: rect)
        }
    }

    private func performCapture(rect: CGRect) {
        Task { @MainActor in
            do {
                guard let screen = associatedScreen else { return }
                let image = try await ScreenCaptureService.shared.captureArea(rect: rect, screen: screen)
                onComplete?(rect, image)
            } catch {
                print("❌ 截图失败: \(error)")
                onCancel?()
            }
        }
    }

    private func runCountdown(seconds: Int, completion: @escaping () -> Void) {
        controlBar?.isHidden = true
        let label = NSTextField(labelWithString: "\(seconds)")
        label.font = NSFont.systemFont(ofSize: 120, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: (bounds.width - label.frame.width) / 2,
            y: (bounds.height - label.frame.height) / 2
        )
        addSubview(label)

        var remaining = seconds
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak label] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                label?.removeFromSuperview()
                self?.controlBar?.isHidden = false
                completion()
            } else {
                guard let self = self, let label = label else { return }
                label.stringValue = "\(remaining)"
                label.sizeToFit()
                label.frame.origin = CGPoint(
                    x: (self.bounds.width - label.frame.width) / 2,
                    y: (self.bounds.height - label.frame.height) / 2
                )
            }
        }
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
            return CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: point.y - rect.minY)
        case .top:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
        case .topRight:
            return CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
        case .left:
            return CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: rect.height)
        case .right:
            return CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: rect.height)
        case .bottomLeft:
            return CGRect(x: point.x, y: point.y, width: rect.maxX - point.x, height: rect.maxY - point.y)
        case .bottom:
            return CGRect(x: rect.minX, y: point.y, width: rect.width, height: rect.maxY - point.y)
        case .bottomRight:
            return CGRect(x: rect.minX, y: point.y, width: point.x - rect.minX, height: rect.maxY - point.y)
        case .none: return rect
        }
    }

    private func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard hasSelection else { return }
        let rect = normalizedRect(selectionRect)
        let maxX = max(0, bounds.width - rect.width)
        let maxY = max(0, bounds.height - rect.height)
        let newX = min(max(0, rect.origin.x + dx), maxX)
        let newY = min(max(0, rect.origin.y + dy), maxY)
        selectionRect = CGRect(x: newX, y: newY, width: rect.width, height: rect.height)
        needsDisplay = true
    }
}

// MARK: - CaptureControlBarDelegate

extension SelectionOverlayView: CaptureControlBarDelegate {
    func controlBar(_ bar: CaptureControlBar, didSelect mode: CaptureMode) {
        captureMode = mode
    }

    func controlBarDidTapCapture(_ bar: CaptureControlBar) {
        switch captureMode {
        case .fullScreen:
            selectionRect = bounds
            hasSelection = true
            confirmSelection()
        case .area, .window:
            if hasSelection { confirmSelection() }
        }
    }

    func controlBarDidTapCancel(_ bar: CaptureControlBar) {
        onCancel?()
    }

    func controlBarDidChangeOptions(_ bar: CaptureControlBar) {
        // 偏好设置已同步，无需其它动作
    }
}
