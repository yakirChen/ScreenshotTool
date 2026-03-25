//
//  SelectionOverlayWindow.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class SelectionOverlayWindow: NSWindow {

    var onComplete: ((CGRect, NSScreen) -> Void)?
    var onCancel: (() -> Void)?

    let associatedScreen: NSScreen

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, detectWindows: Bool = false) {
        self.associatedScreen = screen

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        // ✅ 确保窗口完全覆盖目标屏幕
        self.setFrame(screen.frame, display: true)

        self.level = .statusBar + 1
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // ✅ view 使用局部坐标 (0, 0, w, h)
        let viewFrame = CGRect(origin: .zero, size: screen.frame.size)
        let selectionView = SelectionOverlayView(frame: viewFrame)
        selectionView.detectWindows = detectWindows
        selectionView.associatedScreen = screen
        selectionView.autoresizingMask = [.width, .height]
        self.contentView = selectionView

        selectionView.onComplete = { [weak self] rect in
            guard let self = self else { return }
            self.onComplete?(rect, self.associatedScreen)
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
        self.associatedScreen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }
}
