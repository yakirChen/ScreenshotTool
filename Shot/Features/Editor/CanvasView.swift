//
//  CanvasView.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

/// 画布视图：承载 EditorView，支持拖拽平移和居中显示
class CanvasView: NSView {

    var editorView: EditorView? {
        didSet {
            if let editor = editorView {
                editor.wantsLayer = true

                // ✅ 阴影
                editor.shadow = NSShadow()
                editor.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.3)
                editor.shadow?.shadowOffset = CGSize(width: 0, height: -3)
                editor.shadow?.shadowBlurRadius = 12
                editor.layer?.cornerRadius = 2
                editor.layer?.masksToBounds = false
            }
        }
    }

    private var isPanning = false
    private var panStartPoint: NSPoint = .zero
    private var editorStartOrigin: NSPoint = .zero

    // ✅ 预渲染的背景 pattern
    private var patternImage: NSImage?
    private var cachedAppearanceIsDark: Bool?

    private let followNaturalScroll = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // ✅ 使用 layer-backed view，所有子 view 移动走 GPU
        wantsLayer = true
        layer?.drawsAsynchronously = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - 背景绘制（只在需要时重绘）

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // ✅ 只在明暗切换时重新生成 pattern
        if cachedAppearanceIsDark != isDark {
            cachedAppearanceIsDark = isDark
            patternImage = createPatternImage(isDark: isDark)
        }

        if let pattern = patternImage {
            layer?.backgroundColor = NSColor(patternImage: pattern).cgColor
        } else {
            let bgColor = isDark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.88, alpha: 1)
            layer?.backgroundColor = bgColor.cgColor
        }
    }

    /// 预渲染一个 20x20 的 pattern tile
    private func createPatternImage(isDark: Bool) -> NSImage {
        let tileSize: CGFloat = 20
        let image = NSImage(size: NSSize(width: tileSize, height: tileSize))

        image.lockFocus()

        // 背景色
        let bgColor =
            isDark
            ? NSColor(white: 0.15, alpha: 1)
            : NSColor(white: 0.88, alpha: 1)
        bgColor.setFill()
        NSRect(x: 0, y: 0, width: tileSize, height: tileSize).fill()

        // 一个点
        let dotColor =
            isDark
            ? NSColor(white: 0.22, alpha: 1)
            : NSColor(white: 0.78, alpha: 1)
        dotColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()

        image.unlockFocus()

        return image
    }

    // MARK: - 居中

    func centerEditor() {
        guard let editor = editorView else { return }

        let x = (bounds.width - editor.frame.width) / 2
        let y = (bounds.height - editor.frame.height) / 2

        editor.frame.origin = CGPoint(x: max(20, x), y: max(20, y))
    }

    // MARK: - 左键

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let editor = editorView else { return }

        if !editor.frame.contains(point) {
            startPanning(at: point)
        } else {
            editor.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            panTo(event: event)
        } else {
            editorView?.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            stopPanning()
        } else {
            editorView?.mouseUp(with: event)
        }
    }

    // MARK: - 右键拖拽

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPanning(at: point)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if isPanning { panTo(event: event) }
    }

    override func rightMouseUp(with event: NSEvent) {
        if isPanning { stopPanning() }
    }

    // MARK: - 滚轮

    override func scrollWheel(with event: NSEvent) {
        guard let editor = editorView else { return }

        let dx: CGFloat
        let dy: CGFloat

        if event.isDirectionInvertedFromDevice {
            dx = event.scrollingDeltaX
            dy = -event.scrollingDeltaY
        } else {
            dx = -event.scrollingDeltaX
            dy = event.scrollingDeltaY
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        editor.frame.origin = CGPoint(
            x: editor.frame.origin.x + dx,
            y: editor.frame.origin.y + dy
        )
        CATransaction.commit()
    }

    // MARK: - 平移核心逻辑

    private func startPanning(at point: NSPoint) {
        guard let editor = editorView else { return }
        isPanning = true
        panStartPoint = point
        editorStartOrigin = editor.frame.origin
        NSCursor.closedHand.push()
    }

    private func panTo(event: NSEvent) {
        guard isPanning, let editor = editorView else { return }
        let point = convert(event.locationInWindow, from: nil)

        let dx = point.x - panStartPoint.x
        let dy = point.y - panStartPoint.y

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        editor.frame.origin = CGPoint(
            x: editorStartOrigin.x + dx,
            y: editorStartOrigin.y + dy
        )
        CATransaction.commit()
    }

    private func stopPanning() {
        isPanning = false
        NSCursor.pop()
    }

    // MARK: - 键盘传递

    override func keyDown(with event: NSEvent) {
        editorView?.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        // 空实现
    }
}
