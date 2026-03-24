//
//  SelectionOverlayWindow.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//


import Cocoa

class SelectionOverlayWindow: NSWindow {
    
    var onComplete: ((CGRect, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private let selectionView: SelectionOverlayView
    private let screenFrame: CGRect
    
    // ✅ 关键：允许 borderless 窗口成为 key window，接收键盘事件
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(screen: NSScreen, detectWindows: Bool = false) {
        self.screenFrame = screen.frame
        self.selectionView = SelectionOverlayView(frame: screen.frame)
        
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        self.level = .statusBar + 1
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        selectionView.detectWindows = detectWindows
        self.contentView = selectionView
        
        selectionView.onComplete = { [weak self] rect in
            guard let self = self else { return }
            self.onComplete?(rect, self.screenFrame)
        }
        
        selectionView.onCancel = { [weak self] in
            self?.onCancel?()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.screenFrame = contentRect
        self.selectionView = SelectionOverlayView(frame: contentRect)
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.contentView = selectionView
    }
}
