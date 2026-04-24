// ScrollCaptureManager.swift

import Cocoa

class ScrollCaptureManager {

    static let shared = ScrollCaptureManager()

    private var stitchedImage: NSImage?
    private var lastCapturedImage: NSImage?
    private var captureCount = 0
    private var overlayWindow: NSWindow?
    private var statusLabel: NSTextField?
    private var isCapturing = false
    private var isFrameCaptureInProgress = false
    private var captureTimer: Timer?
    private var eventMonitor: Any?

    // 区域捕获参数
    private var captureRect: CGRect = .zero
    private var captureScreen: NSScreen?

    // MARK: - 开始滚动截图

    func start() {
        Task { @MainActor in
            let hasPermission = await ScreenCaptureService.shared.checkPermission()
            if !hasPermission {
                ScreenCaptureService.shared.requestPermission()
                return
            }

            // 先让用户选择截图区域
            promptAreaSelection()
        }
    }

    /// 弹出轻量选区，用户选完后开始滚动捕获
    private func promptAreaSelection() {
        guard let screen = NSScreen.main else { return }

        let window = SelectionOverlayWindow(
            screen: screen,
            showControlBar: false
        )

        if let view = window.contentView as? SelectionOverlayView {
            Task {
                let frozenBg = try? await ScreenCaptureService.shared.captureFullScreen(screen: screen)
                await MainActor.run {
                    view.frozenBackground = frozenBg
                }
            }
        }

        window.onComplete = { [weak self] rect, captureScreen, _ in
            self?.beginScrollCapture(rect: rect, screen: captureScreen)
            window.orderOut(nil)
        }
        window.onCancel = {
            window.orderOut(nil)
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 区域确认后，开始滚动捕获
    private func beginScrollCapture(rect: CGRect, screen: NSScreen) {
        guard rect.width > 1, rect.height > 1 else { return }

        captureRect = rect
        captureScreen = screen
        stitchedImage = nil
        lastCapturedImage = nil
        captureCount = 0
        isCapturing = true
        isFrameCaptureInProgress = false

        showOverlay()
        startCaptureLoop()
    }

    // MARK: - 覆盖窗口（提示 + 控制按钮）

    private func showOverlay() {
        guard let screen = NSScreen.main else { return }

        let barHeight: CGFloat = 60
        let barWidth: CGFloat = 400

        let window = NSWindow(
            contentRect: CGRect(
                x: screen.frame.midX - barWidth / 2,
                y: screen.frame.origin.y + 20,
                width: barWidth,
                height: barHeight
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces]

        let container = NSView(frame: CGRect(x: 0, y: 0, width: barWidth, height: barHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
        container.layer?.cornerRadius = 12

        let label = NSTextField(labelWithString: "请开始滚动页面，截图会自动捕获...")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = CGRect(x: 16, y: 22, width: 280, height: 20)
        container.addSubview(label)
        statusLabel = label

        let countLabel = NSTextField(labelWithString: "已捕获: 0 帧")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = NSColor(white: 0.7, alpha: 1)
        countLabel.frame = CGRect(x: 16, y: 6, width: 150, height: 16)
        countLabel.tag = 101
        container.addSubview(countLabel)

        let doneButton = NSButton(title: "完成拼接", target: self, action: #selector(finishScrollCapture))
        doneButton.bezelStyle = .rounded
        doneButton.frame = CGRect(x: 290, y: 10, width: 90, height: 30)
        doneButton.keyEquivalent = "\r"
        container.addSubview(doneButton)

        // ESC 取消 — 保存引用以便移除
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelScrollCapture()
                return nil
            }
            return event
        }

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
    }

    // MARK: - 定时截图循环

    private func startCaptureLoop() {
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.captureSelectedArea()
        }

        // 先截一张初始图
        captureSelectedArea()
    }

    private func captureSelectedArea() {
        guard isCapturing, let screen = captureScreen else { return }
        guard !isFrameCaptureInProgress else { return }
        isFrameCaptureInProgress = true

        Task { @MainActor in
            defer { self.isFrameCaptureInProgress = false }
            do {
                let image = try await ScreenCaptureService.shared.captureArea(
                    rect: captureRect, screen: screen
                )

                let hash = pixelSampleHash(image)
                let lastHash = lastCapturedImage.map { pixelSampleHash($0) } ?? 0

                if hash != lastHash {
                    captureCount += 1

                    // 增量拼接：立即与累积结果合并，释放原始帧
                    if let existing = stitchedImage {
                        stitchedImage = ScrollImageStitcher.stitchPair(top: existing, bottom: image)
                    } else {
                        stitchedImage = image
                    }
                    lastCapturedImage = image

                    if let countLabel = overlayWindow?.contentView?.viewWithTag(101) as? NSTextField {
                        countLabel.stringValue = "已捕获: \(captureCount) 帧"
                    }
                    statusLabel?.stringValue = "继续滚动... (已捕获 \(captureCount) 帧)"
                }
            } catch {
                print("滚动截图失败: \(error)")
            }
        }
    }

    /// 基于像素采样的 hash（避免 TIFF header 元数据干扰）
    private func pixelSampleHash(_ image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let dataLength = CFDataGetLength(data)

        var hasher = Hasher()
        let sampleCount = 100
        let stepX = max(1, width / 10)
        let stepY = max(1, height / 10)

        var sampled = 0
        var y = stepY / 2
        while y < height && sampled < sampleCount {
            var x = stepX / 2
            while x < width && sampled < sampleCount {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if offset + 2 < dataLength {
                    hasher.combine(ptr[offset])
                    hasher.combine(ptr[offset + 1])
                    hasher.combine(ptr[offset + 2])
                    sampled += 1
                }
                x += stepX
            }
            y += stepY
        }

        return hasher.finalize()
    }

    // MARK: - 完成拼接

    @objc private func finishScrollCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        removeEventMonitor()
        overlayWindow?.close()
        overlayWindow = nil

        guard let result = stitchedImage else {
            let alert = NSAlert()
            alert.messageText = "没有捕获到图片"
            alert.informativeText = "请在点击开始后滚动页面"
            alert.runModal()
            cleanup()
            return
        }

        if PreferencesManager.shared.openEditorAfterCapture {
            EditorWindowController.show(with: result)
        } else if PreferencesManager.shared.showFloatingThumbnail {
            let sourceRect: CGRect
            if let screen = captureScreen, captureRect.width > 0, captureRect.height > 0 {
                sourceRect = CGRect(
                    x: screen.frame.origin.x + captureRect.origin.x,
                    y: screen.frame.origin.y + captureRect.origin.y,
                    width: captureRect.width,
                    height: captureRect.height
                )
            } else {
                sourceRect = captureScreen?.frame ?? NSScreen.main?.frame ?? .zero
            }
            FloatingThumbnail.show(image: result, sourceRect: sourceRect)
        }

        if PreferencesManager.shared.copyToClipboardOnCapture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([result])
        }

        if PreferencesManager.shared.saveToHistory {
            HistoryManager.shared.save(image: result)
        }

        if PreferencesManager.shared.playSoundOnCapture {
            NSSound(named: "Tink")?.play()
        }

        cleanup()
    }

    private func cancelScrollCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        removeEventMonitor()
        overlayWindow?.close()
        overlayWindow = nil
        cleanup()
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func cleanup() {
        stitchedImage = nil
        lastCapturedImage = nil
        captureCount = 0
        isFrameCaptureInProgress = false
        captureRect = .zero
        captureScreen = nil
    }
}
