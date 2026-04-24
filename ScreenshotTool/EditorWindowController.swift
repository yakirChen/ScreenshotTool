//
//  EditorWindowController.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa
import UniformTypeIdentifiers

class EditorWindowController: NSWindowController {

    private static var current: EditorWindowController?

    private var editorView: EditorView!
    private var toolbarView: EditorToolbarView!
    private var scrollView: NSScrollView!
    private var eventMonitor: Any?

    static func show(with image: NSImage, asFallback: Bool = true) {
        guard asFallback else { return }
        current?.close()

        let controller = EditorWindowController(image: image)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        current = controller
    }

    convenience init(image: NSImage) {
        let maxSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1920, height: 1080)

        let scale: CGFloat = min(
            1.0,
            min(
                maxSize.width * 0.8 / image.size.width,
                maxSize.height * 0.8 / image.size.height)
        )
        let imageDisplaySize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let windowSize = CGSize(
            width: max(imageDisplaySize.width + 80, 580),
            height: max(imageDisplaySize.height + 80, 300)
        )

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = ""
        window.titleVisibility = .hidden
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 200, height: 80)

        self.init(window: window)

        setupViews(image: image, windowSize: windowSize)
        setupKeyboardMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupViews(image: NSImage, windowSize: CGSize) {
        guard let window = self.window,
              let contentView = window.contentView
        else { return }

        // ✅ 用 NSToolbar 把自定义 view 嵌入标题栏
        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = true
        window.toolbar = toolbar

        // ✅ 让工具栏和标题栏融为一体
        window.titlebarAppearsTransparent = false

        // ✅ 画布占满 contentView
        let canvasView = CanvasView(frame: contentView.bounds)
        canvasView.autoresizingMask = [.width, .height]
        contentView.addSubview(canvasView)

        editorView = EditorView(frame: CGRect(origin: .zero, size: image.size))
        editorView.image = image
        editorView.currentColor = PreferencesManager.shared.defaultAnnotationColor
        editorView.currentLineWidth = PreferencesManager.shared.defaultLineWidth

        canvasView.editorView = editorView
        canvasView.addSubview(editorView)

        DispatchQueue.main.async {
            canvasView.centerEditor()
        }
    }

    @objc private func windowDidResize(_ notification: Notification) {
        // 工具栏由 NSToolbar 管理，自动适应
        if let canvasView = window?.contentView?.subviews.first(where: { $0 is CanvasView })
            as? CanvasView {
            canvasView.centerEditor()
        }
    }

    // MARK: - 快捷键

    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow == true else { return event }

            let cmd = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)

            switch event.keyCode {
            case 6 where cmd && shift:
                self.editorView.redo()
                return nil
            case 6 where cmd:
                self.editorView.undo()
                return nil
            case 8 where cmd:
                self.copyImage()
                return nil
            case 1 where cmd:
                self.saveImage()
                return nil
            default: return event
            }
        }
    }

    // MARK: - 操作

    private func saveImage() {
        guard let image = editorView.exportImage() else { return }

        let format = PreferencesManager.shared.saveFormat
        let ext = format == "jpeg" ? "jpg" : format

        let savePanel = NSSavePanel()
        switch format {
        case "jpeg": savePanel.allowedContentTypes = [.jpeg]
        case "tiff": savePanel.allowedContentTypes = [.tiff]
        default: savePanel.allowedContentTypes = [.png]
        }
        savePanel.nameFieldStringValue = "Screenshot_\(dateString()).\(ext)"

        savePanel.beginSheetModal(for: self.window!) { response in
            if response == .OK, let url = savePanel.url {
                self.saveImageToFile(image: image, url: url, format: format)
            }
        }
    }

    private func copyImage() {
        editorView.copyToClipboard()
        showFeedback("✓ 已复制")
    }

    private func performOCR() {
        guard let image = editorView.exportImage() else { return }
        showFeedback("🔍 识别中...")

        OCRManager.shared.recognizeText(from: image) { [weak self] text in
            guard let self = self else { return }
            if text.isEmpty {
                self.showFeedback("❌ 未识别到文字")
                return
            }
            self.showOCRResult(text)
        }
    }

    private func showOCRResult(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "文字识别结果"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "复制文字")
        alert.addButton(withTitle: "关闭")

        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        sv.hasVerticalScroller = true
        let tv = NSTextView(frame: sv.bounds)
        tv.string = text
        tv.isEditable = true
        tv.isSelectable = true
        tv.font = .systemFont(ofSize: 13)
        tv.autoresizingMask = [.width, .height]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        sv.documentView = tv
        alert.accessoryView = sv

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showFeedback("✓ 文字已复制")
        }
    }

    private func pinToDesktop() {
        guard let image = editorView.exportImage() else { return }
        PinWindow.pin(image: image)
        showFeedback("📌 已钉到桌面")
    }

    // MARK: - 辅助

    private func saveImageToFile(image: NSImage, url: URL, format: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData)
        else { return }

        let fileType: NSBitmapImageRep.FileType
        switch format {
        case "jpeg": fileType = .jpeg
        case "tiff": fileType = .tiff
        default: fileType = .png
        }

        guard let data = bitmapRep.representation(using: fileType, properties: [:]) else { return }

        do {
            try data.write(to: url)
            showFeedback("✓ 已保存")
        } catch {
            showFeedback("❌ 保存失败")
        }
    }

    private func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }

    private func showFeedback(_ message: String) {
        guard let contentView = window?.contentView else { return }
        contentView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }

        let label = NSTextField(labelWithString: message)
        label.tag = 999
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        label.layer?.cornerRadius = 8
        label.sizeToFit()
        label.frame.size.width += 30
        label.frame.size.height += 14
        label.frame.origin = CGPoint(
            x: (contentView.bounds.width - label.frame.width) / 2,
            y: (contentView.bounds.height - label.frame.height) / 2
        )
        contentView.addSubview(label)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSAnimationContext.runAnimationGroup(
                { ctx in
                    ctx.duration = 0.3
                    label.animator().alphaValue = 0
                },
                completionHandler: {
                    label.removeFromSuperview()
                })
        }
    }
}

// MARK: - NSToolbarDelegate

extension EditorWindowController: NSToolbarDelegate {

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {

        if itemIdentifier == .init("EditorTools") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)

            toolbarView = EditorToolbarView(frame: NSRect(x: 0, y: 0, width: 800, height: 38))
            toolbarView.delegate = self as EditorToolbarDelegate  // ✅ 显式转换
            toolbarView.currentColor = PreferencesManager.shared.defaultAnnotationColor
            toolbarView.imageSize = editorView?.image?.size ?? .zero
            toolbarView.zoomLevel = 1.0

            item.view = toolbarView
            item.minSize = NSSize(width: 200, height: 38)
            item.maxSize = NSSize(width: 2000, height: 38)

            return item
        }

        return nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.init("EditorTools")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.init("EditorTools")]
    }
}

// MARK: - EditorToolbarDelegate

extension EditorWindowController: EditorToolbarDelegate {
    func toolDidChange(_ tool: AnnotationTool) { editorView.currentTool = tool }
    func colorDidChange(_ color: NSColor) { editorView.currentColor = color }
    func lineWidthDidChange(_ width: CGFloat) { editorView.currentLineWidth = width }
    func undoAction() { editorView.undo() }
    func redoAction() { editorView.redo() }
    func saveAction() { saveImage() }
    func copyAction() { copyImage() }
    func closeAction() {
        window?.close()
        EditorWindowController.current = nil
    }
    func ocrAction() { performOCR() }
    func pinAction() { pinToDesktop() }
}
