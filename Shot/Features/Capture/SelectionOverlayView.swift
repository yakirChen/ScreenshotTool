//
//  SelectionOverlayView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class SelectionOverlayView: NSView {

    // MARK: - 回调
    var onComplete: ((CGRect, NSImage?, CaptureExportAction) -> Void)?
    var onCancel: (() -> Void)?
    var onStateChange: ((SelectionCaptureManager.State) -> Void)?

    // MARK: - 屏幕/模式
    var associatedScreen: NSScreen?
    var frozenBackground: NSImage?
    var showControlBar: Bool = true
    var enableAnnotationAfterCapture: Bool = true
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
    private var annotationEditorView: EditorView?
    private var inlineToolbar: InlineEditorToolbar?
    private var annotationRect: CGRect = .zero
    private var isAnnotating = false

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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        let bar = CaptureControlBar(
            frame: NSRect(origin: .zero, size: CaptureControlBar.preferredSize()))
        bar.delegate = self
        bar.mode = captureMode
        bar.translatesAutoresizingMaskIntoConstraints = true
        let size = CaptureControlBar.preferredSize()
        bar.frame = NSRect(
            x: (bounds.width - size.width) / 2, y: 40, width: size.width, height: size.height)
        bar.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        addSubview(bar)
        controlBar = bar
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let bg = frozenBackground {
            bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
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

            // 标注模式下，选区由 EditorView 负责绘制，不处理
            if isAnnotating {
                return
            }

            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            if let bg = frozenBackground {
                context.saveGState()
                context.clip(to: rect)
                bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                context.restoreGState()
            }

            // 只在完成框选后且不在标注模式下才显示边框和手柄
            if renderModel.hasSelection && !renderModel.isSelecting && !isAnnotating {
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(1.5)
                context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))

                drawRuleOfThirds(context: context, rect: rect)

                if renderModel.captureMode != .fullScreen {
                    drawResizeHandles(context: context, rect: rect)
                }
                drawSizeInfo(context: context, rect: rect)
            }
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
            x: (bounds.width - bgWidth) / 2, y: bounds.height - bgHeight - 40, width: bgWidth,
            height: bgHeight)
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.addPath(
            CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs)
    }

    private func drawWindowHighlightIfNeeded(context: CGContext) {
        guard renderModel.detectWindows, let rect = renderModel.detectedWindowFrame else { return }
        
        // Enhanced window highlighting with visual feedback
        context.saveGState()
        
        // Clear the mask area to show the window
        context.setBlendMode(.clear)
        context.fill(rect)
        context.setBlendMode(.normal)
        
        // Draw the frozen background in the window area
        if let bg = frozenBackground {
            context.saveGState()
            context.clip(to: rect)
            bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.restoreGState()
        }
        
        // Draw enhanced border with glow effect
        context.setShadow(offset: CGSize(width: 0, height: 0), blur: 8, color: NSColor.systemBlue.cgColor)
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2.5)
        context.stroke(rect)
        
        // Draw corner accents for better visibility
        let cornerSize: CGFloat = 12
        let cornerLineWidth: CGFloat = 3
        
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(cornerLineWidth)
        context.setLineCap(.round)
        
        // Top-left corner
        context.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerSize))
        context.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.minX + cornerSize, y: rect.minY))
        context.strokePath()
        
        // Top-right corner
        context.move(to: CGPoint(x: rect.maxX - cornerSize, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerSize))
        context.strokePath()
        
        // Bottom-left corner
        context.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerSize))
        context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.minX + cornerSize, y: rect.maxY))
        context.strokePath()
        
        // Bottom-right corner
        context.move(to: CGPoint(x: rect.maxX - cornerSize, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerSize))
        context.strokePath()
        
        context.restoreGState()
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
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1), blur: 3,
            color: NSColor.black.withAlphaComponent(0.4).cgColor)
        for handleRect in handles.values {
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: handleRect)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: handleRect.insetBy(dx: 0.5, dy: 0.5))
        }
        context.restoreGState()
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
        if bgOrigin.y + bgHeight > bounds.height { bgOrigin.y = rect.maxY - bgHeight - 4 }
        let bgRect = CGRect(origin: bgOrigin, size: CGSize(width: bgWidth, height: bgHeight))
        context.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        context.addPath(
            CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()
        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs)
    }

    // MARK: - 鼠标事件

    override func mouseMoved(with event: NSEvent) {
        guard !isAnnotating else { return }
        guard let session, let screen = associatedScreen else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = GeometryMapper.localToGlobal(localPoint, in: screen)
        renderModel = session.handleMouseMoved(globalPoint: globalPoint, on: screen)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if let win = self.window, !win.isKeyWindow { win.makeKeyAndOrderFront(nil) }
        guard !isAnnotating else {
            super.mouseDown(with: event)
            return
        }
        guard let session, let screen = associatedScreen else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let bar = controlBar, bar.frame.contains(point) { return }

        if event.clickCount == 2 && renderModel.hasSelection {
            confirmSelection()
            return
        }

        let globalPoint = GeometryMapper.localToGlobal(point, in: screen)
        renderModel = session.handleMouseDown(
            globalPoint: globalPoint, clickCount: event.clickCount, on: screen)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isAnnotating else { return }
        guard let session, let screen = associatedScreen else { return }
        let point = convert(event.locationInWindow, from: nil)
        let globalPoint = GeometryMapper.localToGlobal(point, in: screen)
        renderModel = session.handleMouseDragged(globalPoint: globalPoint, on: screen)
        needsDisplay = true

        if renderModel.hasSelection {
            let rect = normalizedRect(renderModel.selectionRect)
            inlineToolbar?.updateSelectionRect(rect)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !isAnnotating else { return }
        guard let session, let screen = associatedScreen else { return }
        let wasSelecting = renderModel.isSelecting
        renderModel = session.handleMouseUp(on: screen)
        needsDisplay = true
        if wasSelecting && renderModel.hasSelection {
            showSelectionToolbar()
        }
    }

    private func showSelectionToolbar() {
        let rect = normalizedRect(renderModel.selectionRect)
        if let toolbar = inlineToolbar {
            toolbar.updateSelectionRect(rect)
            return
        }
        let toolbar = InlineEditorToolbar()
        toolbar.delegate = self
        toolbar.currentTool = .select
        toolbar.updateSelectionRect(rect)
        if let window = self.window, let screen = associatedScreen {
            toolbar.present(
                in: window, overlayBounds: bounds, selectionRect: rect, screen: screen,
                animated: false)
        }
        self.inlineToolbar = toolbar
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !isAnnotating else { return }
        let point = convert(event.locationInWindow, from: nil)
        if renderModel.hasSelection {
            let rect = normalizedRect(renderModel.selectionRect)
            let handles = getHandleRects(for: rect)
            for (handle, handleRect) in handles {
                if handleRect.insetBy(dx: -4, dy: -4).contains(point) {
                    switch handle {
                    case .topLeft, .bottomRight:
                        NSCursor.columnResize.set()
                        return
                    case .topRight, .bottomLeft:
                        NSCursor.columnResize.set()
                        return
                    case .top, .bottom:
                        NSCursor.resizeUpDown.set()
                        return
                    case .left, .right:
                        NSCursor.resizeLeftRight.set()
                        return
                    case .none: break
                    }
                }
            }
            if rect.contains(point) {
                NSCursor.openHand.set()
                return
            }
        }
        NSCursor.crosshair.set()
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        guard let session, let screen = associatedScreen else { return }
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        if isAnnotating {
            if command && event.keyCode == 6 {
                if shift { annotationEditorView?.redo() } else { annotationEditorView?.undo() }
                return
            }
            handleAnnotationKeyDown(event)
            return
        }

        switch event.keyCode {
        case 36, 76: if renderModel.hasSelection { confirmSelection() }
        default: super.keyDown(with: event)
        }
    }

    private func handleAnnotationKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 36, 76: exportCopy()
        case 8 where event.modifierFlags.contains(.command): exportCopy()
        default: annotationEditorView?.keyDown(with: event)
        }
    }

    // MARK: - 辅助

    private func confirmSelection() {
        guard let session, let screen = associatedScreen else { return }
        let rect = session.normalizedSelectionRect(in: screen)
        guard rect.width > 1, rect.height > 1 else { return }
        onStateChange?(.captured)
        performCapture(rect: rect)
    }

    private func performCapture(rect: CGRect, initialTool: AnnotationTool? = nil) {
        Task { @MainActor in
            do {
                guard let screen = associatedScreen else { return }
                
                let image = try await ScreenCaptureService.shared.captureArea(
                    rect: rect, screen: screen)
                
                session?.freezeSelection(image: image, localRect: rect, in: screen)
                if enableAnnotationAfterCapture {
                    enterAnnotationMode(image: image, rect: rect, initialTool: initialTool)
                } else {
                    onComplete?(rect, image, .copy)
                }
            } catch {
                print("DEBUG: Capture failed: \(error)")
                onCancel?()
            }
        }
    }

    private func performCaptureAndPin(rect: CGRect) {
        Task { @MainActor in
            do {
                guard let screen = associatedScreen else { return }
                
                // 截图前完全隐藏覆盖窗口，避免UI元素被截入
                window?.orderOut(nil)
                
                // 等待窗口完全隐藏
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                
                let image = try await ScreenCaptureService.shared.captureArea(
                    rect: rect, screen: screen)
                
                PinWindow.pin(image: image)
                onCancel?()
            } catch {
                print("DEBUG: Capture failed for pin: \(error)")
                onCancel?()
            }
        }
    }

    private func enterAnnotationMode(
        image: NSImage, rect: CGRect, initialTool: AnnotationTool? = nil
    ) {
        isAnnotating = true
        annotationRect = rect
        onStateChange?(.annotating)
        controlBar?.isHidden = true

        let editor = EditorView(frame: rect)
        editor.image = image
        editor.currentColor = PreferencesManager.shared.defaultAnnotationColor
        editor.currentLineWidth = PreferencesManager.shared.defaultLineWidth
        editor.currentTool = initialTool ?? .select

        editor.onUndoToEmpty = { [weak self] in
            guard let self = self, let editor = self.annotationEditorView else { return }
            if editor.annotations.isEmpty { self.exitAnnotationModeToSelection() }
        }

        addSubview(editor)
        annotationEditorView = editor

        // 💡 核心修复：复用已有的工具栏，不再重新创建，彻底消除闪烁
        if let toolbar = inlineToolbar {
            toolbar.currentTool = editor.currentTool
            toolbar.currentColor = editor.currentColor
            toolbar.updateSelectionRect(rect)
        } else {
            let toolbar = InlineEditorToolbar()
            toolbar.delegate = self
            toolbar.currentTool = editor.currentTool
            toolbar.currentColor = editor.currentColor
            toolbar.updateSelectionRect(rect)
            if let window = self.window, let screen = associatedScreen {
                toolbar.present(
                    in: window, overlayBounds: bounds, selectionRect: rect, screen: screen,
                    animated: false)
            }
            inlineToolbar = toolbar
        }
        window?.makeFirstResponder(editor)
    }

    private func exitAnnotationModeToSelection() {
        isAnnotating = false
        onStateChange?(.selecting)
        annotationEditorView?.removeFromSuperview()
        annotationEditorView = nil
        controlBar?.isHidden = false
        inlineToolbar?.currentTool = .select
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    @objc private func exportCopy() {
        inlineToolbar?.dismiss()
        guard let image = annotationEditorView?.exportImage() else { return }
        onComplete?(annotationRect, image, .copy)
    }

  @objc private func exportPin() {
      inlineToolbar?.dismiss()

      // 尝试从编辑器导出
      if let image = annotationEditorView?.exportImage() {
          // 标注模式下，直接 Pin
          PinWindow.pin(image: image)
          // Pin 后关闭会话
          onCancel?()
      } else if let baseImage = frozenBackground, let screen = associatedScreen {
          // 兜底：从全屏背景中裁剪出选区内容
          let rect = annotationRect
          guard let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
              onCancel?()
              return
          }
          
          // 转换坐标系（NSImage 坐标 y 轴翻转）
          let flippedY = CGFloat(cgImage.height) - rect.origin.y - rect.height
          let flippedRect = CGRect(
              x: rect.origin.x,
              y: flippedY,
              width: rect.width,
              height: rect.height
          )
          
          guard let croppedCG = cgImage.cropping(to: flippedRect) else {
              onCancel?()
              return
          }
          
          let croppedImage = NSImage(cgImage: croppedCG, size: rect.size)
          PinWindow.pin(image: croppedImage)
          // Pin 后关闭会话
          onCancel?()
      } else {
          onCancel?()
      }
  }

    @objc private func cancelAnnotation() {
        inlineToolbar?.dismiss()
        onCancel?()
    }

    private func normalizedRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(rect.origin.x, rect.origin.x + rect.width),
            y: min(rect.origin.y, rect.origin.y + rect.height), width: abs(rect.width),
            height: abs(rect.height)
        ).integral
    }
}

extension SelectionOverlayView: CaptureControlBarDelegate {
    func controlBar(_ bar: CaptureControlBar, didSelect mode: CaptureMode) { captureMode = mode }
    func controlBarDidTapCapture(_ bar: CaptureControlBar) {
        if renderModel.hasSelection { confirmSelection() }
    }
    func controlBarDidTapCancel(_ bar: CaptureControlBar) { onCancel?() }
    func controlBarDidChangeOptions(_ bar: CaptureControlBar) {}
}

extension SelectionOverlayView: InlineEditorToolbarDelegate {
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didSelectTool tool: AnnotationTool) {
        if !isAnnotating {
            let rect = normalizedRect(renderModel.selectionRect)
            performCapture(rect: rect, initialTool: tool)
            return
        }
        annotationEditorView?.currentTool = tool
        self.window?.makeKey()
    }
    
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didChangeColor color: NSColor) {
        annotationEditorView?.currentColor = color
    }
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didChangeLineWidth width: CGFloat) {
        annotationEditorView?.currentLineWidth = width
    }
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didChangeFontSize size: CGFloat) {
        annotationEditorView?.currentFontSize = size
    }
    func inlineToolbarDidUndo(_ toolbar: InlineEditorToolbar) { annotationEditorView?.undo() }
    func inlineToolbarDidRedo(_ toolbar: InlineEditorToolbar) { annotationEditorView?.redo() }
    func inlineToolbarDidConfirm(_ toolbar: InlineEditorToolbar) { exportCopy() }
    func inlineToolbarDidCancel(_ toolbar: InlineEditorToolbar) { cancelAnnotation() }
    func inlineToolbarDidCopy(_ toolbar: InlineEditorToolbar) { exportCopy() }
    func inlineToolbarDidPin(_ toolbar: InlineEditorToolbar) {
      print("DEBUG: Delegate received Pin tap")
        if !isAnnotating {
            // 非标注模式下，先截图再 Pin
            let rect = normalizedRect(renderModel.selectionRect)
            performCaptureAndPin(rect: rect)
        } else {
            // 标注模式下，直接 Pin
            exportPin()
        }
    }
}
