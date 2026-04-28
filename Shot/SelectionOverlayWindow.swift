//
//  SelectionOverlayWindow.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

class SelectionOverlayWindow: NSWindow {

    var onComplete: ((CGRect, NSScreen, NSImage?, CaptureExportAction) -> Void)?
    var onCancel: (() -> Void)?
    var onStateChange: ((SelectionCaptureManager.State) -> Void)?

    let associatedScreen: NSScreen

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(
        screen: NSScreen,
        session: CaptureSession,
        showControlBar: Bool = true,
        initialMode: CaptureMode = .area,
        enableAnnotationAfterCapture: Bool = true
    ) {
        self.associatedScreen = screen

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        self.setFrame(screen.frame, display: true)
        self.level = .statusBar + 1
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let viewFrame = CGRect(origin: .zero, size: screen.frame.size)
        let selectionView = SelectionOverlayView(frame: viewFrame)
        selectionView.associatedScreen = screen
        selectionView.captureMode = initialMode
        selectionView.showControlBar = showControlBar
        selectionView.enableAnnotationAfterCapture = enableAnnotationAfterCapture
        selectionView.session = session
        selectionView.autoresizingMask = [.width, .height]
        self.contentView = selectionView

        selectionView.onComplete = { [weak self] rect, image, action in
            guard let self = self else { return }
            self.onComplete?(rect, self.associatedScreen, image, action)
        }
        selectionView.onCancel = { [weak self] in
            self?.onCancel?()
        }
        selectionView.onStateChange = { [weak self] state in
            self?.onStateChange?(state)
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
