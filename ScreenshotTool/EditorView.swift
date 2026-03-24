//
//  EditorView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//


import Cocoa

class EditorView: NSView {
    
    // 截图
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    
    // 标注
    var annotations: [Annotation] = []
    var currentAnnotation: Annotation?
    
    // 当前工具和样式
    var currentTool: AnnotationTool = .select
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 2
    
    // 撤销/重做栈
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    
    // 编号计数器
    private var nextNumber: Int = 1
    
    // 选择工具：拖拽
    private var selectedAnnotation: Annotation?
    private var selectionDragOffset: CGPoint = .zero
    
    // 文字编辑
    private var textField: NSTextField?
    private var editingAnnotation: Annotation?
    
    // MARK: - 设置
    
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    
    // MARK: - 绘制
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 棋盘格背景
        drawCheckerboard(in: bounds, context: context)
        
        // 截图
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        // 所有已完成的标注
        for annotation in annotations {
            annotation.draw(in: context, imageSize: bounds.size)
        }
        
        // 正在绘制的标注
        currentAnnotation?.draw(in: context, imageSize: bounds.size)
    }
    
    private func drawCheckerboard(in rect: NSRect, context: CGContext) {
        let size: CGFloat = 10
        let light = NSColor(white: 0.95, alpha: 1).cgColor
        let dark = NSColor(white: 0.85, alpha: 1).cgColor
        
        var y: CGFloat = 0
        var row = 0
        while y < rect.height {
            var x: CGFloat = 0
            var col = 0
            while x < rect.width {
                context.setFillColor((row + col) % 2 == 0 ? light : dark)
                context.fill(CGRect(x: x, y: y, width: size, height: size))
                x += size
                col += 1
            }
            y += size
            row += 1
        }
    }
    
    // MARK: - 鼠标事件
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // 如果正在编辑文字，先结束
        finishTextEditing()
        
        switch currentTool {
        case .select:
            handleSelectMouseDown(point: point)
            
        case .text:
            handleTextMouseDown(point: point)
            
        case .number:
            handleNumberMouseDown(point: point)
            
        default:
            // 开始新标注
            saveUndoState()
            let annotation = Annotation(
                tool: currentTool,
                startPoint: point,
                color: currentColor,
                lineWidth: currentLineWidth
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
                // 检查标注是否有效（不是零大小）
                let dx = abs(annotation.endPoint.x - annotation.startPoint.x)
                let dy = abs(annotation.endPoint.y - annotation.startPoint.y)
                
                let isValid: Bool
                switch annotation.tool {
                case .pen:
                    isValid = annotation.penPoints.count >= 2
                case .number:
                    isValid = true
                case .text:
                    isValid = true
                default:
                    isValid = dx > 2 || dy > 2
                }
                
                if isValid {
                    annotations.append(annotation)
                }
                currentAnnotation = nil
            }
        }
        
        needsDisplay = true
    }
    
    // MARK: - 选择工具处理
    
    private func handleSelectMouseDown(point: CGPoint) {
        // 取消之前的选择
        selectedAnnotation?.isSelected = false
        selectedAnnotation = nil
        
        // 从顶部开始检测（后画的在上面）
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
        
        // 画笔的点也要移动
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
    
    // MARK: - 文字工具处理
    
    private func handleTextMouseDown(point: CGPoint) {
        saveUndoState()
        
        let annotation = Annotation(
            tool: .text,
            startPoint: point,
            color: currentColor,
            lineWidth: currentLineWidth
        )
        annotation.fontSize = max(12, currentLineWidth * 6)
        
        editingAnnotation = annotation
        
        // 创建文字输入框
        let tf = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 200, height: 24))
        tf.font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .medium)
        tf.textColor = currentColor
        tf.backgroundColor = NSColor.white.withAlphaComponent(0.8)
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
    
    // MARK: - 编号工具处理
    
    private func handleNumberMouseDown(point: CGPoint) {
        saveUndoState()
        
        let annotation = Annotation(
            tool: .number,
            startPoint: point,
            color: currentColor,
            lineWidth: currentLineWidth
        )
        annotation.number = nextNumber
        nextNumber += 1
        
        annotations.append(annotation)
        needsDisplay = true
    }
    
    // MARK: - 键盘事件
    
    override func keyDown(with event: NSEvent) {
        // 如果正在编辑文字，不处理快捷键
        if textField != nil {
            super.keyDown(with: event)
            return
        }
        
        let hasCommand = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)
        
        switch event.keyCode {
        case 51, 117:  // Delete / Forward Delete
            deleteSelectedAnnotation()
            
        case 6:  // Z
            if hasCommand && hasShift {
                redo()
            } else if hasCommand {
                undo()
            }
            
        case 8:  // C - 复制
            if hasCommand {
                copyToClipboard()
            }
            
        case 1:  // S - 保存
            if hasCommand {
                // 由 EditorWindowController 处理
            }
            
        case 53:  // ESC
            if let annotation = selectedAnnotation {
                annotation.isSelected = false
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
        // 深拷贝当前标注状态
        undoStack.append(annotations)
        redoStack.removeAll()
        
        // 限制撤销栈大小
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
    
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
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
    
    /// 导出带标注的最终图片
    func exportImage() -> NSImage? {
        guard let image = image else { return nil }
        
        // 取消所有选中状态
        annotations.forEach { $0.isSelected = false }
        
        let size = image.size
        let exportImage = NSImage(size: size)
        
        exportImage.lockFocus()
        
        if let context = NSGraphicsContext.current?.cgContext {
            // 画原图
            image.draw(in: CGRect(origin: .zero, size: size))
            
            // 画所有标注
            for annotation in annotations {
                annotation.draw(in: context, imageSize: size)
            }
        }
        
        exportImage.unlockFocus()
        
        return exportImage
    }
    
    /// 复制到剪贴板
    func copyToClipboard() {
        guard let exportedImage = exportImage() else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([exportedImage])
    }
   
}

// MARK: - NSTextFieldDelegate

extension EditorView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        finishTextEditing()
    }
}
