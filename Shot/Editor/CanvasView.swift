//
//  CanvasView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

/// 画布视图：承载 EditorView，支持拖拽平移和居中显示
class CanvasView: NSView {

  var editorView: EditorView?

  private var isPanning = false
  private var panStartPoint: NSPoint = .zero
  private var panOffset: CGPoint = .zero
  
  // 缩放相关
  private var zoomLevel: CGFloat = 1.0
  private let minZoom: CGFloat = 0.1
  private let maxZoom: CGFloat = 5.0

  override init(frame: NSRect) {
    super.init(frame: frame)
    setup()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  private func setup() {
    wantsLayer = true
    // 禁用隐式动画确保窗口移动时无延迟
    layer?.actions = ["": NSNull()]
    // 启用异步绘制提升性能
    layer?.drawsAsynchronously = true
  }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }

  override var acceptsFirstResponder: Bool { true }

  // MARK: - 居中

  func centerEditor() {
    panOffset = .zero
    applyPanOffset()
  }

  private func applyPanOffset() {
    guard let editor = editorView else { return }
    // 直接设置 transform，setup 中已经禁用隐式动画
    let transform = CGAffineTransform(translationX: panOffset.x, y: panOffset.y)
      .scaledBy(x: zoomLevel, y: zoomLevel)
    editor.layer?.setAffineTransform(transform)
    
    // 异步更新工具栏，避免阻塞渲染
    let zoom = zoomLevel
    DispatchQueue.main.async { [weak self] in
      (self?.window?.windowController as? EditorWindowController)?.updateToolbarZoomLevel(zoom)
    }
  }
  
  /// 设置缩放级别（由工具栏调用）
  func setZoomLevel(_ level: CGFloat) {
    zoomLevel = max(minZoom, min(maxZoom, level))
    applyPanOffset()
  }
  
  /// 以指定点为中心缩放
  private func zoomAtPoint(point: NSPoint, delta: CGFloat) {
    guard let editor = editorView else { return }
    
    // 计算新的缩放级别
    let zoomFactor: CGFloat = 0.1
    let newZoom = max(minZoom, min(maxZoom, zoomLevel + (delta > 0 ? zoomFactor : -zoomFactor)))
    
    // 如果缩放没变，不做任何事
    guard newZoom != zoomLevel else { return }
    
    // 将点转换到编辑器坐标系
    let editorPoint = NSPoint(
      x: (point.x - panOffset.x) / zoomLevel,
      y: (point.y - panOffset.y) / zoomLevel
    )
    
    // 计算新的偏移，使该点保持在屏幕上的同一位置
    panOffset.x = point.x - editorPoint.x * newZoom
    panOffset.y = point.y - editorPoint.y * newZoom
    
    zoomLevel = newZoom
    applyPanOffset()
  }

  // MARK: - 平移

  private func startPanning(at point: NSPoint) {
    isPanning = true
    panStartPoint = point
    NSCursor.closedHand.push()
  }

  private func panTo(event: NSEvent) {
    guard isPanning else { return }
    let point = convert(event.locationInWindow, from: nil)
    panOffset.x += point.x - panStartPoint.x
    panOffset.y += point.y - panStartPoint.y
    panStartPoint = point
    applyPanOffset()
  }

  private func stopPanning() {
    isPanning = false
    NSCursor.pop()
  }

  // MARK: - 鼠标事件

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let editor = editorView else { return }

    if editor.frame.contains(point) {
      editor.mouseDown(with: event)
    } else {
      // ✅ 点击截图以外的区域：取消选中 + 切换回选择工具
      editor.deselectAll()
      editor.currentTool = .select
      if let wc = window?.windowController as? EditorWindowController {
        wc.syncToolbarTool(.select)
      }
      startPanning(at: point)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    if isPanning { panTo(event: event) } else { editorView?.mouseDragged(with: event) }
  }

  override func mouseUp(with event: NSEvent) {
    if isPanning { stopPanning() } else { editorView?.mouseUp(with: event) }
  }

  override func rightMouseDown(with event: NSEvent) {
    startPanning(at: convert(event.locationInWindow, from: nil))
  }

  override func rightMouseDragged(with event: NSEvent) {
    if isPanning { panTo(event: event) }
  }

  override func rightMouseUp(with event: NSEvent) {
    if isPanning { stopPanning() }
  }

  override func scrollWheel(with event: NSEvent) {
    // 滚轮缩放（以鼠标位置为中心）
    let point = convert(event.locationInWindow, from: nil)
    let delta = event.scrollingDeltaY
    zoomAtPoint(point: point, delta: delta)
  }

  // MARK: - 键盘传递

  override func keyDown(with event: NSEvent) {
    editorView?.keyDown(with: event)
  }

  override func keyUp(with event: NSEvent) {
    // 空实现
  }
}
