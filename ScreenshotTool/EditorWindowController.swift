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
    
    static func show(with image: NSImage) {
        // 关闭之前的编辑器
        current?.close()
        
        let controller = EditorWindowController(image: image)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        current = controller
    }
    
    convenience init(image: NSImage) {
        // 计算窗口大小
        let maxSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1920, height: 1080)
        let toolbarHeight: CGFloat = 44
        
        let scale: CGFloat = min(
            1.0,
            min(maxSize.width * 0.8 / image.size.width,
                (maxSize.height * 0.8 - toolbarHeight) / image.size.height)
        )
        let imageDisplaySize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let windowSize = CGSize(
            width: max(imageDisplaySize.width, 500),
            height: imageDisplaySize.height + toolbarHeight
        )
        
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "截图编辑 - \(Int(image.size.width))×\(Int(image.size.height))"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 400, height: 300)
        
        self.init(window: window)
        
        setupViews(image: image, windowSize: windowSize, toolbarHeight: toolbarHeight)
        setupKeyboardShortcuts()
    }
    
    private func setupViews(image: NSImage, windowSize: CGSize, toolbarHeight: CGFloat) {
        guard let contentView = window?.contentView else { return }
        
        // 编辑器视图（上方）
        editorView = EditorView(frame: CGRect(
            x: 0,
            y: toolbarHeight,
            width: windowSize.width,
            height: windowSize.height - toolbarHeight
        ))
        editorView.image = image
        editorView.autoresizingMask = [.width, .height]
        contentView.addSubview(editorView)
        
        // 工具栏视图（底部）
        toolbarView = EditorToolbarView(frame: CGRect(
            x: 0,
            y: 0,
            width: windowSize.width,
            height: toolbarHeight
        ))
        toolbarView.autoresizingMask = [.width, .maxYMargin]
        toolbarView.delegate = self
        contentView.addSubview(toolbarView)
    }
    
    private func setupKeyboardShortcuts() {
        // 通过 NSEvent monitor 监听快捷键
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.window?.isKeyWindow == true else {
                return event
            }
            
            let hasCommand = event.modifierFlags.contains(.command)
            let hasShift = event.modifierFlags.contains(.shift)
            
            switch event.keyCode {
            case 6:  // Z
                if hasCommand && hasShift {
                    self.editorView.redo()
                    return nil
                } else if hasCommand {
                    self.editorView.undo()
                    return nil
                }
            case 8:  // C
                if hasCommand {
                    self.copyImage()
                    return nil
                }
            case 1:  // S
                if hasCommand {
                    self.saveImage()
                    return nil
                }
            default:
                break
            }
            
            return event
        }
    }
    
    // MARK: - 保存
    
    private func saveImage() {
        guard let image = editorView.exportImage() else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Screenshot_\(dateString()).png"
        
        savePanel.beginSheetModal(for: self.window!) { response in
            if response == .OK, let url = savePanel.url {
                self.saveImageToFile(image: image, url: url)
            }
        }
    }
    
    // MARK: - 复制
    
    private func copyImage() {
        editorView.copyToClipboard()
        showFeedback("✓ 已复制到剪贴板")
    }
    
    // MARK: - 辅助方法
    
    private func saveImageToFile(image: NSImage, url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }
        
        do {
            try pngData.write(to: url)
            showFeedback("✓ 已保存")
        } catch {
            print("保存失败: \(error)")
        }
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
    
    private func showFeedback(_ message: String) {
        guard let contentView = window?.contentView else { return }
        
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        label.layer?.cornerRadius = 8
        label.sizeToFit()
        label.frame.size.width += 30
        label.frame.size.height += 14
        
        let x = (contentView.bounds.width - label.frame.width) / 2
        let y = (contentView.bounds.height - label.frame.height) / 2
        label.frame.origin = CGPoint(x: x, y: y)
        
        contentView.addSubview(label)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                label.animator().alphaValue = 0
            } completionHandler: {
                label.removeFromSuperview()
            }
        }
    }
}

// MARK: - EditorToolbarDelegate

extension EditorWindowController: EditorToolbarDelegate {
    
    func toolDidChange(_ tool: AnnotationTool) {
        editorView.currentTool = tool
    }
    
    func colorDidChange(_ color: NSColor) {
        editorView.currentColor = color
    }
    
    func lineWidthDidChange(_ width: CGFloat) {
        editorView.currentLineWidth = width
    }
    
    func undoAction() {
        editorView.undo()
    }
    
    func redoAction() {
        editorView.redo()
    }
    
    func saveAction() {
        saveImage()
    }
    
    func copyAction() {
        copyImage()
    }
    
    func closeAction() {
        self.window?.close()
        EditorWindowController.current = nil
    }
}
