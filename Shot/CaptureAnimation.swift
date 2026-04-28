//
//  CaptureAnimation.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

class CaptureAnimation {

    // ✅ 持有窗口引用，防止动画过程中被释放
    private static var flashWindow: NSWindow?
    private static var thumbWindow: NSWindow?

    /// 截图完成后的闪光动画
    static func playFlash(in screenFrame: CGRect) {
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar + 10
        window.isOpaque = false
        window.backgroundColor = NSColor.white.withAlphaComponent(0.5)
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces]

        // ✅ 先持有引用
        flashWindow = window
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.15
                window.animator().alphaValue = 0
            },
            completionHandler: {
                window.orderOut(nil)
                flashWindow = nil  // ✅ 动画完成后释放
            })
    }

    /// 截图缩略图飞到右下角的动画
    static func playThumbnailAnimation(image: NSImage, from sourceRect: CGRect) {
        guard let screen = NSScreen.main else { return }

        let thumbSize: CGFloat = 120
        let aspectRatio = image.size.width / max(image.size.height, 1)
        let thumbWidth = aspectRatio > 1 ? thumbSize : thumbSize * aspectRatio
        let thumbHeight = aspectRatio > 1 ? thumbSize / aspectRatio : thumbSize

        guard thumbWidth > 0 && thumbHeight > 0 else { return }

        // 起始位置
        let startFrame = CGRect(
            x: max(0, sourceRect.midX - thumbWidth / 2),
            y: max(0, sourceRect.midY - thumbHeight / 2),
            width: thumbWidth,
            height: thumbHeight
        )

        // 终点位置
        let endFrame = CGRect(
            x: screen.frame.maxX - thumbWidth - 20,
            y: 20,
            width: thumbWidth,
            height: thumbHeight
        )

        let window = NSWindow(
            contentRect: startFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar + 5
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: startFrame.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        imageView.autoresizingMask = [.width, .height]

        window.contentView = imageView

        // ✅ 先持有引用
        thumbWindow = window
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(endFrame, display: true)
            },
            completionHandler: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NSAnimationContext.runAnimationGroup(
                        { context in
                            context.duration = 0.3
                            window.animator().alphaValue = 0
                        },
                        completionHandler: {
                            window.orderOut(nil)
                            thumbWindow = nil  // ✅ 动画完成后释放
                        })
                }
            })
    }
}
