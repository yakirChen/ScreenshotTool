//
//  FloatingThumbnail.swift
//  ScreenshotTool
//

import Cocoa
import UniformTypeIdentifiers

/// macOS 原生风格的右下角浮动缩略图
/// - 从截图区域飞入 → 停留 4s → 淡出并执行自动动作
/// - 单击打开编辑器；右键菜单含 Pin / 保存 / 复制 / 删除
/// - 拖拽即把图片作为 PNG 文件拖出
final class FloatingThumbnail: NSWindow {

    private static var current: FloatingThumbnail?

    private let image: NSImage
    private var dismissWorkItem: DispatchWorkItem?

    private static let dismissDelay: TimeInterval = 4.0
    private static let longSide: CGFloat = 160

    static func show(image: NSImage, sourceRect: CGRect) {
        current?.immediatelyDismiss()

        let win = FloatingThumbnail(image: image)
        win.presentFlying(from: sourceRect)
        current = win
    }

    private init(image: NSImage) {
        self.image = image

        let aspect = max(image.size.width / max(image.size.height, 1), 0.01)
        let w: CGFloat = aspect >= 1 ? Self.longSide : Self.longSide * aspect
        let h: CGFloat = aspect >= 1 ? Self.longSide / aspect : Self.longSide

        super.init(
            contentRect: CGRect(x: 0, y: 0, width: w, height: h),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar + 5
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = ThumbnailView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        view.image = image
        view.onClick = { [weak self] in self?.openInEditor() }
        view.onRequestMenu = { [weak self] in self?.contextMenu() }
        view.onHoverChanged = { [weak self] hovering in
            hovering ? self?.pauseDismiss() : self?.scheduleDismiss()
        }
        self.contentView = view
    }

    // MARK: - 生命周期

    private func presentFlying(from sourceRect: CGRect) {
        guard let screen = NSScreen.main else { return }

        let size = self.frame.size
        let startFrame = CGRect(
            x: sourceRect.midX - size.width / 2,
            y: sourceRect.midY - size.height / 2,
            width: size.width, height: size.height
        )
        let endFrame = CGRect(
            x: screen.visibleFrame.maxX - size.width - 20,
            y: screen.visibleFrame.minY + 20,
            width: size.width, height: size.height
        )

        self.setFrame(startFrame, display: true)
        self.alphaValue = 1.0
        self.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            self?.scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissWithAutoAction() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissDelay, execute: work)
    }

    private func pauseDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func dismissWithAutoAction() {
        performAutoAction()
        fadeOutAndClose()
    }

    private func immediatelyDismiss() {
        dismissWorkItem?.cancel()
        orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    private func fadeOutAndClose() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            self.orderOut(nil)
            if Self.current === self { Self.current = nil }
        }
    }

    /// 无操作倒计时结束时执行：自动保存文件到默认位置（对齐 macOS 原生行为）。
    private func performAutoAction() {
        let savePath = PreferencesManager.shared.defaultSaveLocation
        let fileName = "截屏 \(Self.dateString()).png"
        let fileURL = URL(fileURLWithPath: savePath).appendingPathComponent(fileName)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return }

        try? data.write(to: fileURL)
    }

    // MARK: - 用户操作

    fileprivate func openInEditor() {
        let img = self.image
        immediatelyDismiss()
        EditorWindowController.show(with: img)
    }

    fileprivate func pinToDesktop() {
        let img = self.image
        immediatelyDismiss()
        PinWindow.pin(image: img)
    }

    fileprivate func saveToFile() {
        let img = self.image
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "截屏 \(Self.dateString()).png"
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url,
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
            self?.fadeOutAndClose()
        }
    }

    fileprivate func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([self.image])
        fadeOutAndClose()
    }

    fileprivate func discard() { fadeOutAndClose() }

    private func contextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "在编辑器中打开", action: #selector(menuOpen), keyEquivalent: "").target =
            self
        menu.addItem(.separator())
        menu.addItem(withTitle: "复制到剪贴板", action: #selector(menuCopy), keyEquivalent: "").target =
            self
        menu.addItem(withTitle: "保存到文件…", action: #selector(menuSave), keyEquivalent: "").target =
            self
        menu.addItem(withTitle: "钉到桌面", action: #selector(menuPin), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "删除", action: #selector(menuDiscard), keyEquivalent: "").target =
            self

        pauseDismiss()
        if let view = self.contentView {
            let loc = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            menu.popUp(positioning: nil, at: loc, in: view)
        }
        scheduleDismiss()
    }

    @objc private func menuOpen() { openInEditor() }
    @objc private func menuCopy() { copyToClipboard() }
    @objc private func menuSave() { saveToFile() }
    @objc private func menuPin() { pinToDesktop() }
    @objc private func menuDiscard() { discard() }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd ahh.mm.ss"
        return f.string(from: Date())
    }
}

// MARK: - ThumbnailView

private final class ThumbnailView: NSView, NSFilePromiseProviderDelegate {

    var image: NSImage? { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onRequestMenu: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var dragStartPoint: NSPoint?
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let path = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(bounds)

        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)

        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartPoint, !isDragging else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard hypot(dx, dy) > 5 else { return }
        isDragging = true
        beginFilePromiseDrag(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStartPoint = nil }
        if !isDragging { onClick?() }
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) { onRequestMenu?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        onRequestMenu?()
        return nil
    }

    // MARK: - 文件拖拽

    private func beginFilePromiseDrag(from event: NSEvent) {
        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
        let dragItem = NSDraggingItem(pasteboardWriter: provider)
        let thumbSize = NSSize(width: bounds.width * 0.8, height: bounds.height * 0.8)
        let origin = NSPoint(
            x: (bounds.width - thumbSize.width) / 2,
            y: (bounds.height - thumbSize.height) / 2
        )
        dragItem.setDraggingFrame(NSRect(origin: origin, size: thumbSize), contents: image)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String
    ) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd ahh.mm.ss"
        return "截屏 \(f.string(from: Date())).png"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let image = image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else {
            completionHandler(NSError(domain: "FloatingThumbnail", code: -1))
            return
        }
        do {
            try data.write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }
}

extension ThumbnailView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return [.copy]
    }
}
