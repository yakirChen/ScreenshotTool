//
//  EditorView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class EditorView: NSView {

    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var annotations: [Annotation] = []
    var currentAnnotation: Annotation?

    var currentTool: AnnotationTool = .select
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 2

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    private var nextNumber: Int = 1

    private var selectedAnnotation: Annotation?
    private var selectionDragOffset: CGPoint = .zero

    private var textField: NSTextField?
    private var editingAnnotation: Annotation?

    // MARK: - 设置

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

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

        // 白色底
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)

        // 图片
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)

        // 标注
        for annotation in annotations {
            annotation.draw(in: context, imageSize: bounds.size)
        }
        currentAnnotation?.draw(in: context, imageSize: bounds.size)

        // 细边框
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(0.5)
        context.stroke(bounds)
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        finishTextEditing()

        switch currentTool {
        case .select:
            handleSelectMouseDown(point: point)
        case .text:
            handleTextMouseDown(point: point)
        case .number:
            handleNumberMouseDown(point: point)
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
        default:
            currentAnnotation?.endPoint = point
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch currentTool {
        case .select:
            break
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
        annotation.fontSize = max(12, currentLineWidth * 6)
        editingAnnotation = annotation

        let tf = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 200, height: 24))
        tf.font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .medium)
        tf.textColor = currentColor
        tf.backgroundColor = NSColor.white.withAlphaComponent(0.9)
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.isEditable = true
        tf.placeholderString = "输入文字..."
        tf.delegate = self
        tf.target = self
        tf.action = #selector(textFieldAction(_:))

        addSubview(tf)
        tf.becomeFirstResponder()
        textField = tf
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        finishTextEditing()
    }

    private func finishTextEditing() {
        guard let tf = textField, let annotation = editingAnnotation else { return }

        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            annotation.text = text
            annotations.append(annotation)
        }

        tf.removeFromSuperview()
        textField = nil
        editingAnnotation = nil
        needsDisplay = true
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
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 51, 117:  // Delete
            deleteSelectedAnnotation()
        case 53:  // ESC
            if let a = selectedAnnotation {
                a.isSelected = false
                selectedAnnotation = nil
                needsDisplay = true
            } else {
                finishTextEditing()
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 撤销/重做

    private func saveUndoState() {
        undoStack.append(annotations)
        redoStack.removeAll()
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
        needsDisplay = true
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
        needsDisplay = true
    }

    // MARK: - 导出

    func exportImage() -> NSImage? {
        guard let image = image else { return nil }

        annotations.forEach { $0.isSelected = false }

        let exportImage = NSImage(size: image.size)
        exportImage.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            image.draw(in: CGRect(origin: .zero, size: image.size))

            // ✅ 标注坐标需要从 view 坐标转换到图片坐标
            let scaleX = image.size.width / bounds.width
            let scaleY = image.size.height / bounds.height

            context.saveGState()
            context.scaleBy(x: scaleX, y: scaleY)

            for annotation in annotations {
                annotation.draw(in: context, imageSize: bounds.size)
            }

            context.restoreGState()
        }

        exportImage.unlockFocus()
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
    func controlTextDidEndEditing(_ obj: Notification) {
        finishTextEditing()
    }
}
