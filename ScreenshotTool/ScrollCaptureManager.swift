// ScrollCaptureManager.swift

import Cocoa

class ScrollCaptureManager {
    
    static let shared = ScrollCaptureManager()
    
    private var capturedImages: [NSImage] = []
    private var overlayWindow: NSWindow?
    private var statusLabel: NSTextField?
    private var isCapturing = false
    private var captureTimer: Timer?
    private var lastImageHash: Int = 0
    
    // MARK: - 开始滚动截图
    
    func start() {
        Task { @MainActor in
            let hasPermission = await ScreenCaptureService.shared.checkPermission()
            if !hasPermission {
                ScreenCaptureService.shared.requestPermission()
                return
            }
            
            capturedImages.removeAll()
            isCapturing = true
            lastImageHash = 0
            
            showOverlay()
            startCaptureLoop()
        }
    }
    
    // MARK: - 覆盖窗口（提示 + 控制按钮）
    
    private func showOverlay() {
        guard let screen = NSScreen.main else { return }
        
        // 底部控制条
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
        
        // 状态文字
        let label = NSTextField(labelWithString: "📸 请开始滚动页面，截图会自动捕获...")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = CGRect(x: 16, y: 22, width: 280, height: 20)
        container.addSubview(label)
        statusLabel = label
        
        // 计数
        let countLabel = NSTextField(labelWithString: "已捕获: 0 张")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = NSColor(white: 0.7, alpha: 1)
        countLabel.frame = CGRect(x: 16, y: 6, width: 150, height: 16)
        countLabel.tag = 101
        container.addSubview(countLabel)
        
        // 完成按钮
        let doneButton = NSButton(title: "完成拼接", target: self, action: #selector(finishScrollCapture))
        doneButton.bezelStyle = .rounded
        doneButton.frame = CGRect(x: 290, y: 10, width: 90, height: 30)
        doneButton.keyEquivalent = "\r"  // Enter
        container.addSubview(doneButton)
        
        // ESC 取消 - 用键盘监听
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // ESC
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
        // 每 0.5 秒检测一次屏幕变化
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.captureCurrentScreen()
        }
        
        // 先截一张初始图
        captureCurrentScreen()
    }
    
    private func captureCurrentScreen() {
        guard isCapturing else { return }
        
        Task { @MainActor in
            do {
                let image = try await ScreenCaptureService.shared.captureFullScreen()
                
                // 计算简单 hash 判断画面是否变化
                let hash = imageHash(image)
                if hash != lastImageHash {
                    lastImageHash = hash
                    capturedImages.append(image)
                    
                    // 更新计数
                    if let countLabel = overlayWindow?.contentView?.viewWithTag(101) as? NSTextField {
                        countLabel.stringValue = "已捕获: \(capturedImages.count) 张"
                    }
                    statusLabel?.stringValue = "📸 继续滚动... (已捕获 \(capturedImages.count) 张)"
                }
            } catch {
                print("滚动截图失败: \(error)")
            }
        }
    }
    
    /// 简单的图片 hash（用于判断画面是否变化）
    private func imageHash(_ image: NSImage) -> Int {
        guard let tiff = image.tiffRepresentation else { return 0 }
        // 只取前几千字节做 hash，速度快
        let sampleSize = min(tiff.count, 4096)
        let sample = tiff.prefix(sampleSize)
        return sample.hashValue
    }
    
    // MARK: - 完成拼接
    
    @objc private func finishScrollCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        overlayWindow?.close()
        overlayWindow = nil
        
        guard capturedImages.count >= 2 else {
            if capturedImages.count == 1 {
                // 只有一张，直接打开编辑器
                EditorWindowController.show(with: capturedImages[0])
            } else {
                let alert = NSAlert()
                alert.messageText = "没有捕获到图片"
                alert.informativeText = "请在点击开始后滚动页面"
                alert.runModal()
            }
            return
        }
        
        statusLabel?.stringValue = "🔗 正在拼接..."
        
        // 拼接图片
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let result = self.stitchImages(self.capturedImages) {
                DispatchQueue.main.async {
                    EditorWindowController.show(with: result)
                    
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
                }
            }
        }
    }
    
    private func cancelScrollCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        overlayWindow?.close()
        overlayWindow = nil
        capturedImages.removeAll()
    }
    
    // MARK: - 图片拼接（垂直方向，自动去重叠）
    
    private func stitchImages(_ images: [NSImage]) -> NSImage? {
        guard images.count >= 2 else { return images.first }
        
        var result = images[0]
        
        for i in 1..<images.count {
            guard let stitched = stitchTwo(top: result, bottom: images[i]) else {
                continue
            }
            result = stitched
        }
        
        return result
    }
    
    /// 拼接两张图，自动检测重叠区域
    private func stitchTwo(top: NSImage, bottom: NSImage) -> NSImage? {
        guard let topCG = top.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bottomCG = bottom.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let topWidth = topCG.width
        let topHeight = topCG.height
        let bottomWidth = bottomCG.width
        let bottomHeight = bottomCG.height
        
        // 宽度必须一样
        guard topWidth == bottomWidth else { return nil }
        
        // 查找重叠区域（从底部的图的顶部开始，和顶部的图的底部比较）
        let overlapHeight = findOverlap(topCG: topCG, bottomCG: bottomCG)
        
        // 新图高度 = 顶部图高度 + 底部图高度 - 重叠
        let newHeight = topHeight + bottomHeight - overlapHeight
        let newWidth = topWidth
        
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // 画顶部图（在上面）
        context.draw(topCG, in: CGRect(x: 0, y: newHeight - topHeight, width: topWidth, height: topHeight))
        
        // 画底部图（在下面，去掉重叠部分）
        context.draw(bottomCG, in: CGRect(x: 0, y: 0, width: bottomWidth, height: bottomHeight))
        
        guard let resultCG = context.makeImage() else { return nil }
        
        return NSImage(
            cgImage: resultCG,
            size: NSSize(width: CGFloat(newWidth) / 2, height: CGFloat(newHeight) / 2)  // Retina
        )
    }
    
    /// 查找两张图的重叠像素行数
    private func findOverlap(topCG: CGImage, bottomCG: CGImage) -> Int {
        guard let topData = topCG.dataProvider?.data,
              let bottomData = bottomCG.dataProvider?.data else {
            return 0
        }
        
        let topPtr = CFDataGetBytePtr(topData)!
        let bottomPtr = CFDataGetBytePtr(bottomData)!
        
        let width = topCG.width
        let topBPR = topCG.bytesPerRow
        let bottomBPR = bottomCG.bytesPerRow
        let topHeight = topCG.height
        let bottomHeight = bottomCG.height
        
        // 最大检查重叠高度（不超过两张图较小高度的 80%）
        let maxOverlap = min(topHeight, bottomHeight) * 80 / 100
        
        // 从大重叠到小重叠搜索
        // 比较 top 图的底部 N 行和 bottom 图的顶部 N 行
        let sampleStep = 4  // 每隔几个像素采样，加速
        
        for overlap in stride(from: min(200, maxOverlap), through: 10, by: -5) {
            var matchCount = 0
            var totalCount = 0
            
            // 只检查几行做快速判断
            let checkRows = [0, overlap / 4, overlap / 2, overlap * 3 / 4, overlap - 1]
            
            for row in checkRows {
                if row >= overlap { continue }
                
                let topRow = topHeight - overlap + row
                let bottomRow = row
                
                if topRow >= topHeight || bottomRow >= bottomHeight { continue }
                
                for x in stride(from: 0, to: width * 4, by: sampleStep * 4) {
                    let topOffset = topRow * topBPR + x
                    let bottomOffset = bottomRow * bottomBPR + x
                    
                    if topOffset + 2 < CFDataGetLength(topData) &&
                       bottomOffset + 2 < CFDataGetLength(bottomData) {
                        let dr = abs(Int(topPtr[topOffset]) - Int(bottomPtr[bottomOffset]))
                        let dg = abs(Int(topPtr[topOffset + 1]) - Int(bottomPtr[bottomOffset + 1]))
                        let db = abs(Int(topPtr[topOffset + 2]) - Int(bottomPtr[bottomOffset + 2]))
                        
                        totalCount += 1
                        if dr < 10 && dg < 10 && db < 10 {
                            matchCount += 1
                        }
                    }
                }
            }
            
            if totalCount > 0 {
                let matchRate = Double(matchCount) / Double(totalCount)
                if matchRate > 0.85 {  // 85% 以上像素匹配
                    return overlap
                }
            }
        }
        
        // 没找到重叠，返回 0（直接拼接）
        return 0
    }
}