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

  var currentTool: AnnotationTool = .select {
    didSet {
      updatePropertyOverlay()
      needsDisplay = true
    }
  }
  var currentColor: NSColor = .systemRed {
    didSet { updatePropertyOverlay() }
  }
  var currentLineWidth: CGFloat = 2 {
    didSet { updatePropertyOverlay() }
  }
  var currentFillMode: Bool = false {  // 填充模式开关
    didSet { updatePropertyOverlay() }
  }

  private var undoStack: [[Annotation]] = []
  private var redoStack: [[Annotation]] = []

  private var nextNumber: Int = 1

  private var selectedAnnotation: Annotation? {
    didSet {
      updatePropertyOverlay()
    }
  }
  private var selectionDragOffset: CGPoint = .zero

  private var propertyOverlay: AnnotationPropertyOverlay?
  private var textField: NSTextField?
  private var editingAnnotation: Annotation?

  // MARK: - 设置

  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { false }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
    wantsLayer = true
    layer?.actions = ["": NSNull()]  // 禁用隐式动画
    setupPropertyOverlay()
  }

  private func setupPropertyOverlay() {
    guard let contentView = window?.contentView else { return }
    
    let overlay = AnnotationPropertyOverlay()
    overlay.delegate = self
    overlay.isHidden = true
    overlay.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(overlay) // ✅ 添加到窗口的 contentView，而不是 EditorView
    propertyOverlay = overlay

    NSLayoutConstraint.activate([
      overlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      // ✅ 考虑到全尺寸内容视图和标题栏工具栏，向下偏移
      overlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50),
    ])
  }

  private func updatePropertyOverlay() {
    guard let overlay = propertyOverlay else { return }

    if let annotation = selectedAnnotation {
      overlay.isHidden = false
      overlay.color = annotation.color
      overlay.lineWidth = annotation.lineWidth
      overlay.styleIndex = annotation.styleIndex
      overlay.showStyleOptions = (annotation.tool == .rectangle || annotation.tool == .ellipse || annotation.tool == .blur || annotation.tool == .arrow)
      overlay.showTextOptions = (annotation.tool == .text || annotation.tool == .number)
      overlay.fontSize = annotation.fontSize
      overlay.rebuild()
    } else if currentTool != .select {
      // ✅ 当工具激活但未选中任何物体时，也显示面板以调节默认值
      overlay.isHidden = false
      overlay.color = currentColor
      overlay.lineWidth = currentLineWidth
      overlay.styleIndex = currentFillMode ? 3 : 0
      overlay.showStyleOptions = (currentTool == .rectangle || currentTool == .ellipse || currentTool == .blur || currentTool == .arrow)
      overlay.showTextOptions = (currentTool == .text || currentTool == .number)
      overlay.fontSize = 24 // 默认字号预览
      overlay.rebuild()
    } else {
      overlay.isHidden = true
    }
  }



  func deselectAll() {
    selectedAnnotation?.isSelected = false
    selectedAnnotation = nil
    needsDisplay = true
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
      annotation.draw(in: context, imageSize: bounds.size, originalImage: image)
    }
    currentAnnotation?.draw(in: context, imageSize: bounds.size, originalImage: image)
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
      // 设置默认样式
      if currentTool == .rectangle || currentTool == .ellipse {
        annotation.styleIndex = currentFillMode ? 3 : 0
      }
      
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

        if isValid {
          // ✅ 标记为选中状态并切换到选择状态
          annotation.isSelected = true
          annotations.append(annotation)
          selectedAnnotation = annotation
        }
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

    // Option 键切换填充模式（仅对矩形/椭圆工具有效）
    if event.modifierFlags.contains(.option) {
      if currentTool == .rectangle || currentTool == .ellipse {
        currentFillMode.toggle()
        showFillModeFeedback()
        return
      }
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

  /// 显示填充模式切换反馈
  private func showFillModeFeedback() {
    let message = currentFillMode ? "填充模式开启" : "填充模式关闭"
    showFeedback(message)
  }

  /// 在编辑器中心显示临时反馈
  private func showFeedback(_ message: String) {
    let label = NSTextField(labelWithString: message)
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .white
    label.alignment = .center
    label.wantsLayer = true
    label.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    label.layer?.cornerRadius = 8
    label.sizeToFit()
    label.frame.size.width += 24
    label.frame.size.height += 12
    label.frame.origin = CGPoint(
      x: (bounds.width - label.frame.width) / 2,
      y: (bounds.height - label.frame.height) / 2
    )
    label.alphaValue = 0
    addSubview(label)

    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.15
      label.animator().alphaValue = 1
    }) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        NSAnimationContext.runAnimationGroup({ ctx in
          ctx.duration = 0.2
          label.animator().alphaValue = 0
        }) {
          label.removeFromSuperview()
        }
      }
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
// MARK: - AnnotationPropertyDelegate

extension EditorView: AnnotationPropertyDelegate {
  func propertyDidChange(
    color: NSColor?, lineWidth: CGFloat?, isFilled: Bool?, style: Int?, fontName: String?,
    fontSize: CGFloat?
  ) {
    saveUndoState()

    if let annotation = selectedAnnotation {
      if let color = color { annotation.color = color }
      if let lineWidth = lineWidth { annotation.lineWidth = lineWidth }
      if let style = style { annotation.styleIndex = style }
      if let fontName = fontName { annotation.fontName = fontName }
      if let fontSize = fontSize { annotation.fontSize = fontSize }
    } else {
      // 更新当前工具默认值
      if let color = color { currentColor = color }
      if let lineWidth = lineWidth { currentLineWidth = lineWidth }
      if let style = style { currentFillMode = (style == 3) }
      // fontSize 默认值处理等
    }

    needsDisplay = true
  }

  func didRequestCloseOverlay() {

    selectedAnnotation?.isSelected = false
    selectedAnnotation = nil
    currentTool = .select
    needsDisplay = true
  }
}

// MARK: - NSTextFieldDelegate

extension EditorView: NSTextFieldDelegate {
  func controlTextDidEndEditing(_ obj: Notification) {
    finishTextEditing()
  }
}
