//
//  PinWindow.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

class PinWindow: NSWindow {

    private static var pinnedWindows: [PinWindow] = []

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var originalImageSize: NSSize
    private var isExpanded = false
    private var collapsedSize: NSSize
    private var expandedSize: NSSize

    static func pin(image: NSImage) {
        let window = PinWindow(image: image)
        window.makeKeyAndOrderFront(nil)
        pinnedWindows.append(window)
    }

    init(image: NSImage) {
        self.originalImageSize = image.size
        self.collapsedSize = PinWindow.aspectFitSize(for: image.size, max: NSSize(width: 400, height: 400))
        self.expandedSize = PinWindow.aspectFitSize(for: image.size, max: NSSize(width: 800, height: 800))

        super.init(
            contentRect: CGRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.center()
        self.contentAspectRatio = image.size

        let pinView = PinView(frame: CGRect(origin: .zero, size: collapsedSize))
        pinView.wantsLayer = true
        pinView.image = image
        pinView.onDoubleClick = { [weak self] in
            self?.toggleExpand()
        }
        self.contentView = pinView
    }

    private func toggleExpand() {
        isExpanded.toggle()
        let targetSize = isExpanded ? expandedSize : collapsedSize
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(CGRect(origin: self.frame.origin, size: targetSize), display: true)
        }
        
        if let pinView = contentView as? PinView {
            pinView.frame = CGRect(origin: .zero, size: targetSize)
        }
    }

    private static func aspectFitSize(for original: NSSize, max: NSSize) -> NSSize {
        guard original.width > 0, original.height > 0 else { return max }
        let scale = min(max.width / original.width, max.height / original.height, 1.0)
        return NSSize(width: original.width * scale, height: original.height * scale)
    }
}

class PinView: NSView {

    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    
    var onDoubleClick: (() -> Void)?
    
    private var opacity: CGFloat = 1.0
    private var clickCount = 0
    private var lastClickTime: Date?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 圆角矩形裁剪
        let path = CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.clip()

        // 背景
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)

        // 图片
        if let image {
            let drawRect = aspectFitRect(imageSize: image.size, in: bounds)
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: opacity)
        }

        // 边框
        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let now = Date()
        if let lastTime = lastClickTime, now.timeIntervalSince(lastTime) < 0.5 {
            clickCount += 1
            if clickCount >= 2 {
                onDoubleClick?()
                clickCount = 0
            }
        } else {
            clickCount = 1
        }
        lastClickTime = now
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:  // ESC - 关闭
            window?.close()

        case 24:  // + 增加透明度
            opacity = min(1.0, opacity + 0.1)
            needsDisplay = true

        case 27:  // - 减少透明度
            opacity = max(0.1, opacity - 0.1)
            needsDisplay = true

        default:
            super.keyDown(with: event)
        }
    }

    // 右键菜单
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        menu.addItem(withTitle: "复制", action: #selector(copyImage), keyEquivalent: "c")
            .target = self
        menu.addItem(withTitle: "关闭", action: #selector(closePin), keyEquivalent: "")
            .target = self

        menu.addItem(NSMenuItem.separator())

        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        
        // More granular opacity options
        let opacityValues: [CGFloat] = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]
        for value in opacityValues {
            let item = NSMenuItem(
                title: "\(Int(value * 100))%",
                action: #selector(setOpacity(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(value * 100)
            if abs(opacity - CGFloat(value)) < 0.05 {
                item.state = .on
            }
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add scale options
        let scaleItem = NSMenuItem(title: "缩放", action: nil, keyEquivalent: "")
        let scaleMenu = NSMenu()
        let scales = ["50%", "75%", "100%", "150%", "200%"]
        for scale in scales {
            let item = NSMenuItem(
                title: scale,
                action: #selector(setScale(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = scale
            scaleMenu.addItem(item)
        }
        scaleItem.submenu = scaleMenu
        menu.addItem(scaleItem)

        return menu
    }

    @objc private func copyImage() {
        guard let image = image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    @objc private func closePin() {
        window?.close()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        opacity = CGFloat(sender.tag) / 100.0
        needsDisplay = true
    }
    
    @objc private func setScale(_ sender: NSMenuItem) {
        guard let scaleString = sender.representedObject as? String,
              let scaleValue = Float(scaleString.replacingOccurrences(of: "%", with: "")),
              let window = window as? PinWindow else { return }
        
        let scaleFactor = CGFloat(scaleValue) / 100.0
        let newSize = NSSize(
            width: window.originalImageSize.width * scaleFactor,
            height: window.originalImageSize.height * scaleFactor
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(CGRect(origin: window.frame.origin, size: newSize), display: true)
        }
        
        frame = CGRect(origin: .zero, size: newSize)
        needsDisplay = true
    }

    private func aspectFitRect(imageSize: NSSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
