//
//  ColorPickerController.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa
import ScreenCaptureKit

class ColorPickerController {

    static let shared = ColorPickerController()

    private var overlayWindow: NSWindow?
    private var magnifierWindow: MagnifierWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var frozenImage: NSImage?

    func start() {
        Task { @MainActor in
            // 先截一张全屏图
            do {
                frozenImage = try await ScreenCaptureService.shared.captureFullScreen()
            } catch {
                print("取色器截图失败: \(error)")
                return
            }

            guard let screen = NSScreen.main else { return }

            // 全屏透明覆盖窗口（捕获鼠标事件）
            let overlay = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            overlay.level = .statusBar + 2
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.ignoresMouseEvents = false
            overlay.acceptsMouseMovedEvents = true
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let overlayView = ColorPickerOverlayView(frame: screen.frame)
            overlayView.frozenImage = frozenImage
            overlay.contentView = overlayView
            overlay.makeKeyAndOrderFront(nil)
            overlayWindow = overlay

            // 放大镜窗口
            let mag = MagnifierWindow()
            mag.orderFront(nil)
            magnifierWindow = mag

            NSApp.activate(ignoringOtherApps: true)
            NSCursor.crosshair.push()

            // 监听鼠标事件
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .mouseMoved, .leftMouseDown, .keyDown
            ]) { [weak self] event in
                return self?.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .mouseMoved:
            updateMagnifier(at: NSEvent.mouseLocation)
            return event

        case .leftMouseDown:
            pickColor(at: NSEvent.mouseLocation)
            return nil

        case .keyDown:
            if event.keyCode == 53 {  // ESC
                stop()
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func updateMagnifier(at screenPoint: NSPoint) {
        guard let magnifier = magnifierWindow else { return }

        // 放大镜跟随鼠标
        magnifier.setFrameOrigin(
            NSPoint(
                x: screenPoint.x + 20,
                y: screenPoint.y - magnifier.frame.height - 20
            ))

        // 更新放大镜内容
        if let view = magnifier.contentView as? MagnifierView {
            view.screenPoint = screenPoint
            view.frozenImage = frozenImage
            view.needsDisplay = true
        }
    }

    private func pickColor(at screenPoint: NSPoint) {
        guard let image = frozenImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            stop()
            return
        }

        guard let screen = NSScreen.main else {
            stop()
            return
        }

        // 转换坐标
        let scale = CGFloat(cgImage.width) / screen.frame.width
        let pixelX = Int(screenPoint.x * scale)
        let pixelY = Int((screen.frame.height - screenPoint.y) * scale)

        // 从 CGImage 取像素颜色
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let pointer = CFDataGetBytePtr(data)
        else {
            stop()
            return
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        let clampedX = max(0, min(pixelX, cgImage.width - 1))
        let clampedY = max(0, min(pixelY, cgImage.height - 1))
        let offset = clampedY * bytesPerRow + clampedX * bytesPerPixel

        let b = CGFloat(pointer[offset]) / 255.0
        let g = CGFloat(pointer[offset + 1]) / 255.0
        let r = CGFloat(pointer[offset + 2]) / 255.0

        let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        let rgb = "rgb(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))"

        // 复制到剪贴板
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)

        print("🎨 取色: \(hex) / \(rgb)")

        stop()

        // 显示通知
        showColorNotification(hex: hex, r: r, g: g, b: b)
    }

    private func showColorNotification(hex: String, r: CGFloat, g: CGFloat, b: CGFloat) {
        let alert = NSAlert()
        alert.messageText = "颜色已复制"
        alert.informativeText = "\(hex)\nrgb(\(Int(r*255)), \(Int(g*255)), \(Int(b*255)))"
        alert.alertStyle = .informational
        alert.icon = createColorSwatch(r: r, g: g, b: b)
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func createColorSwatch(r: CGFloat, g: CGFloat, b: CGFloat) -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: r, green: g, blue: b, alpha: 1).setFill()
        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8)
        path.fill()
        NSColor.gray.setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        return image
    }

    func stop() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        NSCursor.pop()
        overlayWindow?.close()
        overlayWindow = nil
        magnifierWindow?.close()
        magnifierWindow = nil
        frozenImage = nil
    }
}

// MARK: - 取色器覆盖视图

class ColorPickerOverlayView: NSView {
    var frozenImage: NSImage?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 透明，只用来捕获事件
        NSColor.clear.setFill()
        dirtyRect.fill()
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - 放大镜窗口

class MagnifierWindow: NSWindow {

    override var canBecomeKey: Bool { false }

    init() {
        let size: CGFloat = 140
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: size, height: size + 30),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar + 3
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = true

        let view = MagnifierView(frame: CGRect(x: 0, y: 0, width: size, height: size + 30))
        self.contentView = view
    }
}

// MARK: - 放大镜视图

class MagnifierView: NSView {

    var screenPoint: NSPoint = .zero
    var frozenImage: NSImage?

    private let magnification: CGFloat = 8
    private let gridSize: CGFloat = 140

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext,
              let image = frozenImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = NSScreen.main
        else { return }

        let scale = CGFloat(cgImage.width) / screen.frame.width

        // 要显示的区域（原图像素坐标）
        let pixelsToShow = gridSize / magnification
        let srcX = screenPoint.x * scale - pixelsToShow * scale / 2
        let srcY = (screen.frame.height - screenPoint.y) * scale - pixelsToShow * scale / 2

        let srcRect = CGRect(
            x: max(0, srcX),
            y: max(0, srcY),
            width: pixelsToShow * scale,
            height: pixelsToShow * scale
        )

        // 圆形裁剪
        let circleRect = CGRect(x: 0, y: 30, width: gridSize, height: gridSize)
        let circlePath = CGPath(ellipseIn: circleRect, transform: nil)

        // 背景
        context.saveGState()
        context.addPath(circlePath)
        context.clip()

        // 绘制放大的图像
        if let cropped = cgImage.cropping(to: srcRect) {
            context.draw(cropped, in: circleRect)
        }

        // 网格线
        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5)

        let step = magnification
        var pos: CGFloat = 0
        while pos <= gridSize {
            context.move(to: CGPoint(x: pos, y: 30))
            context.addLine(to: CGPoint(x: pos, y: 30 + gridSize))
            context.move(to: CGPoint(x: 0, y: 30 + pos))
            context.addLine(to: CGPoint(x: gridSize, y: 30 + pos))
            pos += step
        }
        context.strokePath()

        // 中心十字
        let center = CGPoint(x: gridSize / 2, y: 30 + gridSize / 2)
        context.setStrokeColor(NSColor.red.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: center.x - step / 2, y: center.y))
        context.addLine(to: CGPoint(x: center.x + step / 2, y: center.y))
        context.move(to: CGPoint(x: center.x, y: center.y - step / 2))
        context.addLine(to: CGPoint(x: center.x, y: center.y + step / 2))
        context.strokePath()

        context.restoreGState()

        // 圆形边框
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: circleRect.insetBy(dx: 1, dy: 1))

        // 底部颜色信息
        let hex = getColorHex()
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        ]

        let textRect = CGRect(x: 0, y: 0, width: gridSize, height: 26)
        context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        let bgPath = CGPath(roundedRect: textRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        let textSize = (hex as NSString).size(withAttributes: attrs)
        (hex as NSString).draw(
            at: CGPoint(x: (gridSize - textSize.width) / 2, y: (26 - textSize.height) / 2),
            withAttributes: attrs
        )
    }

    private func getColorHex() -> String {
        guard let image = frozenImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = NSScreen.main
        else { return "#------" }

        let scale = CGFloat(cgImage.width) / screen.frame.width
        let pixelX = Int(screenPoint.x * scale)
        let pixelY = Int((screen.frame.height - screenPoint.y) * scale)

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let pointer = CFDataGetBytePtr(data)
        else { return "#------" }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        let x = max(0, min(pixelX, cgImage.width - 1))
        let y = max(0, min(pixelY, cgImage.height - 1))
        let offset = y * bytesPerRow + x * bytesPerPixel

        let b = pointer[offset]
        let g = pointer[offset + 1]
        let r = pointer[offset + 2]

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
