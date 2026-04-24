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
    var frozenBackground: NSImage?
    var showControlBar: Bool = true
    var captureMode: CaptureMode = .area {
        didSet {
            guard let screen = associatedScreen else { return }
            session?.setMode(captureMode, on: screen)
            controlBar?.mode = captureMode
            needsDisplay = true
        }
    }

    var session: CaptureSession? {
        didSet {
            guard let screen = associatedScreen, let session else { return }
            session.showControlBar = showControlBar
            session.setMode(captureMode, on: screen)
            renderModel = session.renderModel(for: screen)
        }
    }

    private var renderModel = CaptureSession.RenderModel()

    // MARK: - 控制栏
    private var controlBar: CaptureControlBar?

    var overlayMessage: String {
        if !showControlBar {
            return renderModel.detectWindows
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

        if let session, let screen = associatedScreen {
            session.ensureWindowsLoaded(for: screen)
            renderModel = session.renderModel(for: screen)
            needsDisplay = true
        }
    }

    private func setupControlBar() {
        guard showControlBar else { return }
        let bar = CaptureControlBar(frame: NSRect(origin: .zero, size: CaptureControlBar.preferredSize()))
        bar.delegate = self
        bar.mode = captureMode
        bar.translatesAutoresizingMaskIntoConstraints = true
        let size = CaptureControlBar.preferredSize()
        bar.frame = NSRect(
            x: (bounds.width - size.width) / 2,
            y: 40,
            width: size.width,
            height: size.height
        )
        bar.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        addSubview(bar)
        controlBar = bar
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

        if renderModel.hasSelection || renderModel.isSelecting {
            let rect = normalizedRect(renderModel.selectionRect)
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

            if renderModel.hasSelection && renderModel.captureMode != .fullScreen {
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

    private func drawWindowHighlightIfNeeded(context: CGContext) {
        guard renderModel.detectWindows, let rect = renderModel.detectedWindowFrame else { return }

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
    }

    private func drawCrosshair(context: CGContext) {
        let mouseLocation = renderModel.mouseLocation
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

    private func getHandleRects(for rect: CGRect) -> [CaptureSession.ResizeHandle: CGRect] {
        let s: CGFloat = 8
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
        guard let session, let screen = associatedScreen else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = GeometryMapper.localToGlobal(localPoint, in: screen)

        if let myWindow = self.window as? SelectionOverlayWindow, !myWindow.isKeyWindow {
            myWindow.makeKeyAndOrderFront(nil)
            myWindow.makeFirstResponder(self)
        }

        renderModel = session.handleMouseMoved(globalPoint: globalPoint, on: screen)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let session, let screen = associatedScreen else { return }
        let point = convert(event.locationInWindow, from: nil)

        if let bar = controlBar, bar.frame.contains(point) { return }

        if event.clickCount == 2 && renderModel.hasSelection {
            confirmSelection()
            return
        }

        let globalPoint = GeometryMapper.localToGlobal(point, in: screen)
        renderModel = session.handleMouseDown(globalPoint: globalPoint, clickCount: event.clickCount, on: screen)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session, let screen = associatedScreen else { return }
        let point = convert(event.locationInWindow, from: nil)
        let globalPoint = GeometryMapper.localToGlobal(point, in: screen)
        renderModel = session.handleMouseDragged(globalPoint: globalPoint, on: screen)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let session, let screen = associatedScreen else { return }
        renderModel = session.handleMouseUp(on: screen)
        needsDisplay = true
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        guard let session, let screen = associatedScreen else { return }

        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53:
            if renderModel.hasSelection && renderModel.captureMode != .fullScreen {
                session.clearSelection()
                renderModel = session.renderModel(for: screen)
                needsDisplay = true
            } else {
                onCancel?()
            }
        case 36, 76:
            if renderModel.captureMode == .fullScreen {
                session.setMode(.fullScreen, on: screen)
                renderModel = session.renderModel(for: screen)
                confirmSelection()
            } else if renderModel.hasSelection {
                confirmSelection()
            }
        case 49:
            if !showControlBar && !renderModel.hasSelection {
                session.detectWindows.toggle()
                session.ensureWindowsLoaded(for: screen)
                renderModel = session.renderModel(for: screen)
                needsDisplay = true
            } else if !renderModel.hasSelection {
                session.setMode(.fullScreen, on: screen)
                renderModel = session.renderModel(for: screen)
                confirmSelection()
            }
        case 123:
            session.nudgeSelection(dx: shift ? -10 : -1, dy: 0)
            renderModel = session.renderModel(for: screen)
            needsDisplay = true
        case 124:
            session.nudgeSelection(dx: shift ? 10 : 1, dy: 0)
            renderModel = session.renderModel(for: screen)
            needsDisplay = true
        case 125:
            session.nudgeSelection(dx: 0, dy: shift ? -10 : -1)
            renderModel = session.renderModel(for: screen)
            needsDisplay = true
        case 126:
            session.nudgeSelection(dx: 0, dy: shift ? 10 : 1)
            renderModel = session.renderModel(for: screen)
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 辅助

    private func confirmSelection() {
        guard let session, let screen = associatedScreen else { return }
        let rect = session.normalizedSelectionRect(in: screen)
        guard rect.width > 1, rect.height > 1 else { return }

        if PreferencesManager.shared.rememberLastSelection && captureMode == .area {
            PreferencesManager.shared.lastSelectionRect = rect
        }

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
}

extension SelectionOverlayView: CaptureControlBarDelegate {
    func controlBar(_ bar: CaptureControlBar, didSelect mode: CaptureMode) {
        captureMode = mode
    }

    func controlBarDidTapCapture(_ bar: CaptureControlBar) {
        switch captureMode {
        case .fullScreen:
            if let session, let screen = associatedScreen {
                session.setMode(.fullScreen, on: screen)
                renderModel = session.renderModel(for: screen)
            }
            confirmSelection()
        case .area, .window:
            if renderModel.hasSelection { confirmSelection() }
        }
    }

    func controlBarDidTapCancel(_ bar: CaptureControlBar) {
        onCancel?()
    }

    func controlBarDidChangeOptions(_ bar: CaptureControlBar) {
    }
}
