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

    static func pin(image: NSImage) {
        let window = PinWindow(image: image)
        window.makeKeyAndOrderFront(nil)
        pinnedWindows.append(window)
    }

    init(image: NSImage) {
        let size = NSSize(
            width: min(image.size.width, 600),
            height: min(image.size.height, 600)
        )

        super.init(
            contentRect: CGRect(origin: .zero, size: size),
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

        let pinView = PinView(frame: CGRect(origin: .zero, size: size))
        pinView.image = image
        self.contentView = pinView
    }
}

class PinView: NSView {

    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    private var opacity: CGFloat = 1.0

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
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: opacity)

        // 边框
        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
    }

    override var acceptsFirstResponder: Bool { true }

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
        for value in stride(from: 1.0, through: 0.1, by: -0.1) {
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
}
