//
//  EditorView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

private final class TightTextFieldCell: NSTextFieldCell {
    private let inset = CGSize(width: 4, height: 2)
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return super.drawingRect(forBounds: rect).insetBy(dx: inset.width, dy: inset.height)
    }
}

class EditorView: NSView {

    var image: NSImage? { didSet { needsDisplay = true } }
    var annotations: [Annotation] = []
    var currentAnnotation: Annotation?
    var associatedScreenSize: CGSize = .zero

    var currentTool: AnnotationTool = .select
    var currentColor: NSColor = .systemRed { didSet { if let selectedAnnotation { selectedAnnotation.color = currentColor; needsDisplay = true } } }
    var currentLineWidth: CGFloat = 2 { didSet { if let selectedAnnotation { selectedAnnotation.lineWidth = currentLineWidth; needsDisplay = true } } }
    var currentFontSize: CGFloat = 16 {
        didSet {
            if let selectedAnnotation, selectedAnnotation.tool == .text {
                selectedAnnotation.fontSize = currentFontSize
                needsDisplay = true
            }
            updateActiveTextFieldMetrics()
        }
    }

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var nextNumber: Int = 1
    private var selectedAnnotation: Annotation?
    private var selectionDragOffset: CGPoint = .zero
    private var textField: NSTextField?
    private var editingAnnotation: Annotation?
    private var ocrSelectionRect: CGRect = .zero
    private var isOCRSelecting = false
    var ocrStartPoint: CGPoint = .zero
    var onEscape: (() -> Void)?
    var onSelectionStyleChange: ((Annotation?) -> Void)?
    var onUndoToEmpty: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        // ✅ 开启 layer-backed，提升渲染性能
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 图片
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)

        // 标注
        for annotation in annotations {
            annotation.draw(in: context, imageSize: bounds.size)
        }
        currentAnnotation?.draw(in: context, imageSize: bounds.size)

        // OCR 选区
        if isOCRSelecting && ocrSelectionRect.width > 0 && ocrSelectionRect.height > 0 {
            drawOCRSelection(context: context)
        }
    }

    // MARK: 绘制 OCR 选区
    private func drawOCRSelection(context: CGContext) {
        // 半透明蓝色填充
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.08).cgColor)
        context.fill(ocrSelectionRect)

        // 蓝色虚线边框
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [6, 3])
        context.stroke(ocrSelectionRect)
        context.setLineDash(phase: 0, lengths: [])

        // 提示文字
        let text = "松开识别文字"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let bgWidth = textSize.width + padding * 2
        let bgHeight = textSize.height + padding

        // ✅ 放在选框上方，如果上方空间不够就放下方
        var bgOrigin: CGPoint
        if ocrSelectionRect.maxY + bgHeight + 6 < bounds.height {
            // 上方（NSView 坐标系 y 向上）
            bgOrigin = CGPoint(
                x: ocrSelectionRect.midX - bgWidth / 2,
                y: ocrSelectionRect.maxY + 6
            )
        } else if ocrSelectionRect.minY - bgHeight - 6 > 0 {
            // 下方
            bgOrigin = CGPoint(
                x: ocrSelectionRect.midX - bgWidth / 2,
                y: ocrSelectionRect.minY - bgHeight - 6
            )
        } else {
            // 都放不下，放选框右侧外面
            bgOrigin = CGPoint(
                x: ocrSelectionRect.maxX + 6,
                y: ocrSelectionRect.midY - bgHeight / 2
            )
        }

        // 限制在视图范围内
        bgOrigin.x = max(4, min(bgOrigin.x, bounds.width - bgWidth - 4))
        bgOrigin.y = max(4, min(bgOrigin.y, bounds.height - bgHeight - 4))

        let bgRect = CGRect(origin: bgOrigin, size: CGSize(width: bgWidth, height: bgHeight))

        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        (text as NSString).draw(
            at: CGPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2),
            withAttributes: attrs
        )
    }

    // MARK: 对选区进行 OCR
    private func performOCROnSelection() {
        guard let image = image else { return }

        // 从原图裁剪选区
        let scaleX = image.size.width / bounds.width
        let scaleY = image.size.height / bounds.height

        let cropRect = CGRect(
            x: ocrSelectionRect.origin.x * scaleX,
            y: ocrSelectionRect.origin.y * scaleY,
            width: ocrSelectionRect.width * scaleX,
            height: ocrSelectionRect.height * scaleY
        )

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        // NSImage 坐标 y 轴翻转
        let flippedY = CGFloat(cgImage.height) - cropRect.origin.y - cropRect.height
        let flippedRect = CGRect(
            x: cropRect.origin.x,
            y: flippedY,
            width: cropRect.width,
            height: cropRect.height
        )

        guard let croppedCG = cgImage.cropping(to: flippedRect) else { return }
        let croppedImage = NSImage(cgImage: croppedCG, size: cropRect.size)

        OCRManager.shared.recognizeText(from: croppedImage) { [weak self] text in
            if text.isEmpty {
                self?.showOCRToast("未识别到文字")
                return
            }
            self?.showOCRPopover(text: text, at: self?.ocrSelectionRect ?? .zero)
        }
    }

    // MARK: OCR 结果弹出
    private func showOCRPopover(text: String, at rect: CGRect) {
        // 复制到剪贴板
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // 创建弹出视图
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 200)

        let vc = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))

        // 文字视图
        let scrollView = NSScrollView(frame: NSRect(x: 8, y: 36, width: 304, height: 156))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        container.addSubview(scrollView)

        // 底部提示
        let hint = NSTextField(labelWithString: "✓ 已复制到剪贴板")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .systemGreen
        hint.frame = NSRect(x: 8, y: 8, width: 200, height: 20)
        container.addSubview(hint)

        // 关闭按钮
        let closeBtn = NSButton(title: "关闭", target: popover, action: #selector(NSPopover.close))
        closeBtn.bezelStyle = .rounded
        closeBtn.frame = NSRect(x: 250, y: 6, width: 60, height: 24)
        container.addSubview(closeBtn)

        vc.view = container
        popover.contentViewController = vc

        // 在选区位置弹出
        let showRect = NSRect(x: rect.midX - 5, y: rect.midY - 5, width: 10, height: 10)
        popover.show(relativeTo: showRect, of: self, preferredEdge: .maxY)
    }

    private func showOCRToast(_ message: String) {
        // 简单提示
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        // 💡 修复：确保点击即激活窗口焦点
        if let win = self.window, !win.isKeyWindow {
            win.makeKeyAndOrderFront(nil)
        }

        let point = convert(event.locationInWindow, from: nil)

        finishTextEditing()

        switch currentTool {
        case .select:
            handleSelectMouseDown(point: point)
        case .text:
            handleTextMouseDown(point: point)
        case .number:
            handleNumberMouseDown(point: point)
        case .ocr:
            ocrStartPoint = point
            ocrSelectionRect = CGRect(origin: point, size: .zero)
            isOCRSelecting = true
        default:
            saveUndoState()
            let annotation = Annotation(
                tool: currentTool, startPoint: point,
                color: currentColor, lineWidth: currentLineWidth
            )
            if currentTool == .pen {
                annotation.penPoints = [point]
            }
            currentAnnotation = annotation
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .select:
            handleSelectMouseDragged(point: point)
        case .pen:
            currentAnnotation?.penPoints.append(point)
        case .ocr:
            ocrSelectionRect = CGRect(
                x: min(ocrStartPoint.x, point.x),
                y: min(ocrStartPoint.y, point.y),
                width: abs(point.x - ocrStartPoint.x),
                height: abs(point.y - ocrStartPoint.y)
            )
        default:
            currentAnnotation?.endPoint = point
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch currentTool {
        case .select:
            break
        case .ocr:
            if isOCRSelecting && ocrSelectionRect.width > 5 && ocrSelectionRect.height > 5 {
                performOCROnSelection()
            }
            isOCRSelecting = false
            ocrSelectionRect = .zero
            needsDisplay = true
        default:
            if let annotation = currentAnnotation {
                let dx = abs(annotation.endPoint.x - annotation.startPoint.x)
                let dy = abs(annotation.endPoint.y - annotation.startPoint.y)

                let isValid: Bool
                switch annotation.tool {
                case .pen: isValid = annotation.penPoints.count >= 2
                case .number: isValid = true
                case .text: isValid = true
                default: isValid = dx > 2 || dy > 2
                }

                if isValid { annotations.append(annotation) }
                currentAnnotation = nil
            }
        }
        needsDisplay = true
    }

    // MARK: - 选择工具

    private func handleSelectMouseDown(point: CGPoint) {
        selectedAnnotation?.isSelected = false
        selectedAnnotation = nil

        for annotation in annotations.reversed() {
            if annotation.hitTest(point: point) {
                annotation.isSelected = true
                selectedAnnotation = annotation
                selectionDragOffset = CGPoint(
                    x: point.x - annotation.startPoint.x,
                    y: point.y - annotation.startPoint.y
                )
                break
            }
        }

        if let selectedAnnotation {
            currentColor = selectedAnnotation.color
            currentLineWidth = selectedAnnotation.lineWidth
            if selectedAnnotation.tool == .text {
                currentFontSize = selectedAnnotation.fontSize
            }
        }
        onSelectionStyleChange?(selectedAnnotation)
    }

    private func handleSelectMouseDragged(point: CGPoint) {
        guard let annotation = selectedAnnotation else { return }

        saveUndoState()

        let dx = point.x - selectionDragOffset.x - annotation.startPoint.x
        let dy = point.y - selectionDragOffset.y - annotation.startPoint.y

        annotation.startPoint.x += dx
        annotation.startPoint.y += dy
        annotation.endPoint.x += dx
        annotation.endPoint.y += dy

        if annotation.tool == .pen {
            annotation.penPoints = annotation.penPoints.map {
                CGPoint(x: $0.x + dx, y: $0.y + dy)
            }
        }

        selectionDragOffset = CGPoint(
            x: point.x - annotation.startPoint.x,
            y: point.y - annotation.startPoint.y
        )

        needsDisplay = true
    }

    // MARK: - 文字工具

    private func handleTextMouseDown(point: CGPoint) {
        saveUndoState()

        let annotation = Annotation(
            tool: .text, startPoint: point, color: currentColor, lineWidth: currentLineWidth)
        annotation.fontSize = currentFontSize
        editingAnnotation = annotation

        let initialHeight = max(22, currentFontSize + 6)
        let tf = NSTextField(
            frame: CGRect(x: point.x, y: point.y, width: 200, height: initialHeight))
        tf.cell = TightTextFieldCell(textCell: "")
        tf.font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .medium)
        tf.textColor = currentColor
        tf.isBezeled = false
        tf.isBordered = false
        tf.drawsBackground = false
        tf.isEditable = true
        tf.placeholderString = "输入文字..."
        tf.focusRingType = .none
        tf.wantsLayer = true
        tf.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        tf.layer?.cornerRadius = 4
        tf.layer?.borderWidth = 0.5
        tf.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.3).cgColor
        tf.delegate = self
        tf.target = self
        tf.action = #selector(textFieldAction(_:))
        addSubview(tf)
        tf.becomeFirstResponder()
        textField = tf
    }

    @objc private func textFieldAction(_ sender: NSTextField) { finishTextEditing() }

    private func finishTextEditing() {
        guard let tf = textField, let annotation = editingAnnotation else { return }
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            annotation.text = text
            annotation.fontSize = tf.font?.pointSize ?? currentFontSize
            annotation.startPoint = tf.frame.origin
            annotations.append(annotation)
        }
        tf.removeFromSuperview()
        textField = nil
        editingAnnotation = nil
        needsDisplay = true
    }

    private func updateActiveTextFieldMetrics() {
        guard let tf = textField else { return }
        let font = NSFont.systemFont(ofSize: currentFontSize, weight: .medium)
        tf.font = font
        let measureText = tf.stringValue.isEmpty ? (tf.placeholderString ?? "输入文字...") : tf.stringValue
        let textSize = (measureText as NSString).size(withAttributes: [.font: font])
        tf.frame.size = CGSize(width: max(120, textSize.width + 24), height: NSLayoutManager().defaultLineHeight(for: font) + 6)
    }

    // MARK: - 编号工具

    private func handleNumberMouseDown(point: CGPoint) {
        saveUndoState()

        let annotation = Annotation(
            tool: .number, startPoint: point, color: currentColor, lineWidth: currentLineWidth)
        annotation.number = nextNumber
        nextNumber += 1

        annotations.append(annotation)
        needsDisplay = true
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        if textField != nil {
            if event.keyCode == 53 { // ESC while editing text
                finishTextEditing()
                return
            }
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 51, 117:  // Delete
            deleteSelectedAnnotation()
        case 53:  // ESC
            if let onEscape {
                onEscape()
            }
            return
        default:
            super.keyDown(with: event)
        }
    }
    private func saveUndoState() { undoStack.append(annotations); redoStack.removeAll() }

    func undo() {
        guard let prev = undoStack.popLast() else { if annotations.isEmpty { onUndoToEmpty?() }; return }
        redoStack.append(annotations)
        annotations = prev
        needsDisplay = true
        if annotations.isEmpty { onUndoToEmpty?() }
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        needsDisplay = true
    }
    // MARK: - 删除

    private func deleteSelectedAnnotation() {
        guard let annotation = selectedAnnotation else { return }
        saveUndoState()
        annotations.removeAll { $0.id == annotation.id }
        selectedAnnotation = nil
        onSelectionStyleChange?(nil)
        needsDisplay = true
    }
    
    // ...其余方法省略...
    
    func exportImage() -> NSImage? {
        guard let image = image else { return nil }
        
        // 使用图像的实际尺寸
        let exportImage = NSImage(size: image.size)
        exportImage.lockFocus()
        defer { exportImage.unlockFocus() }
        
        // 直接绘制图像
        let drawRect = CGRect(origin: .zero, size: image.size)
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        if let context = NSGraphicsContext.current?.cgContext {
            // 临时取消选中状态，避免导出选中边框
            let selectedAnnotations = annotations.filter { $0.isSelected }
            selectedAnnotations.forEach { $0.isSelected = false }
            
            for annotation in annotations {
                annotation.draw(in: context, imageSize: image.size)
            }
            
            // 恢复选中状态
            selectedAnnotations.forEach { $0.isSelected = true }
        }
        return exportImage
    }

    func copyToClipboard() {
        guard let exportedImage = exportImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([exportedImage])
    }
}

// MARK: - NSTextFieldDelegate

extension EditorView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateActiveTextFieldMetrics()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishTextEditing()
    }
}
