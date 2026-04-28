//
//  SelectionOverlayView.swift
//  Shot
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

  // 放大镜
  private let magnifierSize: CGFloat = 120
  private let magnifierScale: CGFloat = 8
  private var showMagnifier = false

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

    // 1. 冻结背景
    if let bg = frozenBackground {
      bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    // 2. 遮罩
    context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
    context.fill(bounds)

    if hasSelection || isSelecting {
      let rect = normalizedRect(selectionRect)
      guard rect.width > 0 && rect.height > 0 else {
        drawWindowHighlightIfNeeded(context: context)
        drawCrosshair(context: context)
        if showMagnifier { drawMagnifier(context: context) }
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
        bg.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.restoreGState()
      }

      // 边框
      context.setStrokeColor(NSColor.systemBlue.cgColor)
      context.setLineWidth(1.0)
      context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))

      drawRuleOfThirds(context: context, rect: rect)

      if hasSelection {
        drawResizeHandles(context: context, rect: rect)
      }

      drawSizeInfo(context: context, rect: rect)
    } else {
      drawWindowHighlightIfNeeded(context: context)
      drawCrosshair(context: context)
    }

    if showMagnifier {
      drawMagnifier(context: context)
    }
  }

  // MARK: - 窗口检测高亮

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
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      ]
      let textSize = (labelText as NSString).size(withAttributes: attrs)
      let labelRect = CGRect(
        x: rect.origin.x,
        y: rect.maxY + 4,
        width: textSize.width + 12,
        height: textSize.height + 6
      )

      context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
      let bgPath = CGPath(roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
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
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
    context.setLineWidth(0.5)
    context.setLineDash(phase: 0, lengths: [4, 4])

    context.move(to: CGPoint(x: 0, y: mouseLocation.y))
    context.addLine(to: CGPoint(x: bounds.width, y: mouseLocation.y))
    context.move(to: CGPoint(x: mouseLocation.x, y: 0))
    context.addLine(to: CGPoint(x: mouseLocation.x, y: bounds.height))
    context.strokePath()
  }

  // MARK: - 放大镜

  private func drawMagnifier(context: CGContext) {
    guard let bg = frozenBackground else { return }

    let size = magnifierSize
    let zoom = magnifierScale

    var magRect = CGRect(
      x: mouseLocation.x + 24,
      y: mouseLocation.y + 24,
      width: size,
      height: size
    )

    if magRect.maxX > bounds.width { magRect.origin.x = mouseLocation.x - size - 24 }
    if magRect.maxY > bounds.height { magRect.origin.y = mouseLocation.y - size - 24 }

    context.saveGState()

    let path = CGPath(ellipseIn: magRect, transform: nil)
    context.addPath(path)
    context.clip()

    let sourceSize = size / zoom
    let sourceRect = CGRect(
      x: mouseLocation.x - sourceSize / 2,
      y: mouseLocation.y - sourceSize / 2,
      width: sourceSize,
      height: sourceSize
    )

    bg.draw(in: magRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
    context.setLineWidth(0.5)
    for i in 0...Int(sourceSize) {
      let offset = CGFloat(i) * zoom
      context.move(to: CGPoint(x: magRect.minX + offset, y: magRect.minY))
      context.addLine(to: CGPoint(x: magRect.minX + offset, y: magRect.maxY))
      context.move(to: CGPoint(x: magRect.minX, y: magRect.minY + offset))
      context.addLine(to: CGPoint(x: magRect.maxX, y: magRect.minY + offset))
    }
    context.strokePath()

    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1.5)
    let centerX = magRect.midX
    let centerY = magRect.midY
    let halfZoom = zoom / 2
    context.stroke(CGRect(x: centerX - halfZoom, y: centerY - halfZoom, width: zoom, height: zoom))

    context.restoreGState()

    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(2)
    context.strokeEllipse(in: magRect)

    let infoText = String(format: "%d, %d", Int(mouseLocation.x), Int(bounds.height - mouseLocation.y))
    let attrs: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.white,
      .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
    ]

    let infoSize = (infoText as NSString).size(withAttributes: attrs)
    let infoBgRect = CGRect(
      x: magRect.midX - infoSize.width / 2 - 6,
      y: magRect.minY - infoSize.height - 10,
      width: infoSize.width + 12,
      height: infoSize.height + 4
    )

    context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
    let infoPath = CGPath(roundedRect: infoBgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
    context.addPath(infoPath)
    context.fillPath()
    (infoText as NSString).draw(at: CGPoint(x: infoBgRect.minX + 6, y: infoBgRect.minY + 2), withAttributes: attrs)
  }

  // MARK: - 其他绘制辅助

  private func drawRuleOfThirds(context: CGContext, rect: CGRect) {
    guard rect.width > 60 && rect.height > 60 else { return }
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
    context.setLineWidth(0.5)
    for i in 1...2 {
      let xOff = rect.width * CGFloat(i) / 3
      let yOff = rect.height * CGFloat(i) / 3
      context.move(to: CGPoint(x: rect.minX + xOff, y: rect.minY))
      context.addLine(to: CGPoint(x: rect.minX + xOff, y: rect.maxY))
      context.move(to: CGPoint(x: rect.minX, y: rect.minY + yOff))
      context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + yOff))
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
      .bottomRight: CGRect(x: rect.maxX - hs, y: rect.minY - hs, width: s, height: s),
    ]
  }

  private func drawSizeInfo(context: CGContext, rect: CGRect) {
    let scale = associatedScreen?.backingScaleFactor ?? 2
    let text = "\(Int(rect.width))×\(Int(rect.height)) (\(Int(rect.width * scale))×\(Int(rect.height * scale))px)"
    let attrs: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.white,
      .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
    ]
    let textSize = (text as NSString).size(withAttributes: attrs)
    let bgRect = CGRect(x: rect.minX, y: rect.maxY + 6, width: textSize.width + 12, height: textSize.height + 6)
    context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
    context.fill(bgRect)
    (text as NSString).draw(at: CGPoint(x: bgRect.minX + 6, y: bgRect.minY + 3), withAttributes: attrs)
  }

  // MARK: - 鼠标事件

  override func mouseMoved(with event: NSEvent) {
    mouseLocation = convert(event.locationInWindow, from: nil)
    
    if let myWindow = self.window as? SelectionOverlayWindow, !myWindow.isKeyWindow {
      myWindow.makeKeyAndOrderFront(nil)
    }

    if hasSelection {
      let rect = normalizedRect(selectionRect)
      let handle = hitTestHandle(point: mouseLocation, rect: rect)
      updateCursor(for: handle, point: mouseLocation, rect: rect)
      showMagnifier = (handle != .none)
    } else {
      showMagnifier = true
    }
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    showMagnifier = true

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
      needsDisplay = true
      return
    }

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

    if isSelecting {
      selectionRect = CGRect(
        x: min(startPoint.x, point.x),
        y: min(startPoint.y, point.y),
        width: abs(point.x - startPoint.x),
        height: abs(point.y - startPoint.y)
      )
    } else if isDragging {
      if activeHandle != .none {
        selectionRect = resizeRect(normalizedRect(selectionRect), handle: activeHandle, to: point)
      } else {
        var newX = point.x - dragOffset.x
        var newY = point.y - dragOffset.y
        newX = max(0, min(newX, bounds.width - dragStartSize.width))
        newY = max(0, min(newY, bounds.height - dragStartSize.height))
        selectionRect = CGRect(origin: CGPoint(x: newX, y: newY), size: dragStartSize)
      }
    }
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    showMagnifier = false
    if isSelecting {
      isSelecting = false
      let rect = normalizedRect(selectionRect)
      if rect.width > 3 && rect.height > 3 {
        // 框选完成后直接进入编辑，无需额外确认
        confirmSelection()
        return
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
    let isCmd = event.modifierFlags.contains(.command)
    switch event.keyCode {
    case 53: // ESC
      if hasSelection {
        hasSelection = false
        selectionRect = .zero
        needsDisplay = true
      } else {
        onCancel?()
      }
    case 36, 76: // Enter
      if hasSelection { confirmSelection() }
    case 49: // Space
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
    onComplete?(rect)
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
    var newRect = rect
    switch handle {
    case .topLeft:
      newRect = CGRect(x: point.x, y: point.y, width: rect.maxX - point.x, height: rect.maxY - point.y)
    case .top:
      newRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
    case .topRight:
      newRect = CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
    case .left:
      newRect = CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: rect.height)
    case .right:
      newRect = CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: rect.height)
    case .bottomLeft:
      newRect = CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: point.y - rect.minY)
    case .bottom:
      newRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
    case .bottomRight:
      newRect = CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
    case .none: break
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
