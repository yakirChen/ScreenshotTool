import Cocoa

final class CaptureSession {
    struct SnapTargets {
        var screenEdges: [CGRect] = []
        var windowEdges: [CGRect] = []
        var windowCenters: [CGPoint] = []
    }

    struct RenderModel {
        var mouseLocation: CGPoint = .zero
        var selectionRect: CGRect = .zero
        var hasSelection = false
        var isSelecting = false
        var detectedWindowFrame: CGRect?
        var detectWindows = false
        var captureMode: CaptureMode = .area
    }

    enum ResizeHandle {
        case none
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }

    private(set) var globalSelectionRect: CGRect = .zero
    private(set) var frozenSelectionImage: NSImage?
    private(set) var frozenSelectionRect: CGRect = .zero
    private(set) var activeScreen: NSScreen?
    private(set) var hoverWindow: WindowDetector.DetectedWindow?
    private(set) var captureMode: CaptureMode = .area
    private(set) var snapTargets = SnapTargets()

    var showControlBar: Bool = true
    var detectWindows = false

    private let windowDetector = WindowDetector()
    private var windowsLoaded = false

    private var startPointGlobal: CGPoint = .zero
    private(set) var isSelecting = false
    private var isDragging = false
    private(set) var hasSelection = false
    private var dragOffset: CGPoint = .zero
    private var dragStartSize: CGSize = .zero
    private(set) var activeHandle: ResizeHandle = .none
    private(set) var mouseLocationGlobal: CGPoint = .zero

    func setInitialSelection(_ globalRect: CGRect) {
        guard globalRect.width > 3, globalRect.height > 3 else { return }
        globalSelectionRect = globalRect.integral
        hasSelection = true
    }

    func setMode(_ mode: CaptureMode, on screen: NSScreen) {
        activeScreen = screen
        captureMode = mode
        switch mode {
        case .fullScreen:
            globalSelectionRect = screen.frame.integral
            hasSelection = true
            detectWindows = false
        case .window:
            hasSelection = false
            globalSelectionRect = .zero
            detectWindows = true
        case .area:
            hasSelection = false
            globalSelectionRect = .zero
            detectWindows = false
        }
    }

    func ensureWindowsLoaded(for screen: NSScreen) {
        guard detectWindows && !windowsLoaded else { return }
        Task {
            await windowDetector.refresh(for: screen)
            await MainActor.run {
                self.windowsLoaded = true
            }
        }
    }

    func renderModel(for screen: NSScreen) -> RenderModel {
        activeScreen = screen
        let localMouse = GeometryMapper.globalToLocal(mouseLocationGlobal, in: screen)
        let localSelection = GeometryMapper.globalToLocal(globalSelectionRect, in: screen)
        let localWindow = hoverWindow.map {
            GeometryMapper.globalToLocal($0.globalAppKitFrame, in: screen)
        }
        return RenderModel(
            mouseLocation: localMouse,
            selectionRect: localSelection,
            hasSelection: hasSelection,
            isSelecting: isSelecting,
            detectedWindowFrame: localWindow,
            detectWindows: detectWindows && !hasSelection && !isSelecting && windowsLoaded,
            captureMode: captureMode
        )
    }

    func handleMouseMoved(globalPoint: CGPoint, on screen: NSScreen) -> RenderModel {
        activeScreen = screen
        mouseLocationGlobal = globalPoint
        if detectWindows && !hasSelection && !isSelecting && windowsLoaded {
            hoverWindow = windowDetector.detectWindow(globalPoint: globalPoint)
            refreshSnapTargets(for: screen)
        } else {
            hoverWindow = nil
            refreshSnapTargets(for: screen)
        }
        return renderModel(for: screen)
    }

    func handleMouseDown(globalPoint: CGPoint, clickCount: Int, on screen: NSScreen) -> RenderModel {
        activeScreen = screen
        mouseLocationGlobal = globalPoint

        if captureMode == .fullScreen { return renderModel(for: screen) }

        if clickCount == 2 && hasSelection {
            return renderModel(for: screen)
        }

        let localPoint = GeometryMapper.globalToLocal(globalPoint, in: screen)

        // 💡 关键修复：优先判定句柄点击
        if hasSelection {
            let localRect = GeometryMapper.globalToLocal(
                normalizedRect(globalSelectionRect), in: screen)
            let handle = hitTestHandle(point: localPoint, rect: localRect)
            if handle != .none {
                activeHandle = handle
                isDragging = true
                isSelecting = false
                startPointGlobal = globalPoint
                return renderModel(for: screen)
            }

            // 💡 其次判定选区内拖拽
            if localRect.contains(localPoint) {
                isDragging = true
                isSelecting = false
                activeHandle = .none
                dragOffset = CGPoint(
                    x: localPoint.x - localRect.origin.x, y: localPoint.y - localRect.origin.y)
                dragStartSize = localRect.size
                return renderModel(for: screen)
            }
        }

        // 如果点击在外部，则重新开始画框
        if detectWindows && !hasSelection, let hoverWindow {
            globalSelectionRect = hoverWindow.globalAppKitFrame.integral
            hasSelection = true
            self.hoverWindow = nil
            return renderModel(for: screen)
        }

        isDragging = false
        activeHandle = .none
        startPointGlobal = globalPoint
        globalSelectionRect = CGRect(origin: globalPoint, size: .zero)
        isSelecting = true
        hasSelection = false

        return renderModel(for: screen)
    }

    func handleMouseDragged(globalPoint: CGPoint, on screen: NSScreen) -> RenderModel {
        activeScreen = screen
        mouseLocationGlobal = globalPoint
        if captureMode == .fullScreen { return renderModel(for: screen) }

        let localPoint = GeometryMapper.globalToLocal(globalPoint, in: screen)
        let threshold: CGFloat = 10.0

        if isSelecting && !isDragging {
            // 新建选区逻辑 with enhanced snapping
            var snappedPoint = localPoint
            
            // Snap to screen edges
            if abs(localPoint.x) < threshold { snappedPoint.x = 0 }
            if abs(localPoint.x - screen.frame.width) < threshold { snappedPoint.x = screen.frame.width }
            if abs(localPoint.y) < threshold { snappedPoint.y = 0 }
            if abs(localPoint.y - screen.frame.height) < threshold { snappedPoint.y = screen.frame.height }
            
            // Snap to window edges
            for edge in snapTargets.windowEdges {
                if abs(localPoint.x - edge.minX) < threshold && localPoint.y >= edge.minY && localPoint.y <= edge.maxY {
                    snappedPoint.x = edge.minX
                }
                if abs(localPoint.x - edge.maxX) < threshold && localPoint.y >= edge.minY && localPoint.y <= edge.maxY {
                    snappedPoint.x = edge.maxX
                }
                if abs(localPoint.y - edge.minY) < threshold && localPoint.x >= edge.minX && localPoint.x <= edge.maxX {
                    snappedPoint.y = edge.minY
                }
                if abs(localPoint.y - edge.maxY) < threshold && localPoint.x >= edge.minX && localPoint.x <= edge.maxX {
                    snappedPoint.y = edge.maxY
                }
            }
            
            let snappedGlobal = GeometryMapper.localToGlobal(snappedPoint, in: screen)
            globalSelectionRect = CGRect(
                x: min(startPointGlobal.x, snappedGlobal.x),
                y: min(startPointGlobal.y, snappedGlobal.y),
                width: abs(snappedGlobal.x - startPointGlobal.x),
                height: abs(snappedGlobal.y - startPointGlobal.y)
            )
        } else if isDragging && !isSelecting {
            let localRect = GeometryMapper.globalToLocal(
                normalizedRect(globalSelectionRect), in: screen)

            if activeHandle != .none {
                // 💡 句柄缩放：增加磁贴吸附到窗口边缘
                var snappedPoint = localPoint
                
                // Snap to screen edges
                if abs(localPoint.x) < threshold { snappedPoint.x = 0 }
                if abs(localPoint.x - screen.frame.width) < threshold { snappedPoint.x = screen.frame.width }
                if abs(localPoint.y) < threshold { snappedPoint.y = 0 }
                if abs(localPoint.y - screen.frame.height) < threshold { snappedPoint.y = screen.frame.height }
                
                // Snap to window edges
                for edge in snapTargets.windowEdges {
                    if abs(localPoint.x - edge.minX) < threshold && localPoint.y >= edge.minY && localPoint.y <= edge.maxY {
                        snappedPoint.x = edge.minX
                    }
                    if abs(localPoint.x - edge.maxX) < threshold && localPoint.y >= edge.minY && localPoint.y <= edge.maxY {
                        snappedPoint.x = edge.maxX
                    }
                    if abs(localPoint.y - edge.minY) < threshold && localPoint.x >= edge.minX && localPoint.x <= edge.maxX {
                        snappedPoint.y = edge.minY
                    }
                    if abs(localPoint.y - edge.maxY) < threshold && localPoint.x >= edge.minX && localPoint.x <= edge.maxX {
                        snappedPoint.y = edge.maxY
                    }
                }

                let resized = resizeRect(localRect, handle: activeHandle, to: snappedPoint)
                globalSelectionRect = GeometryMapper.localToGlobal(resized, in: screen)
            } else {
                // 💡 选区移动 with enhanced snapping
                var newX = localPoint.x - dragOffset.x
                var newY = localPoint.y - dragOffset.y

                // 移动时的边界吸附
                if abs(newX) < threshold { newX = 0 }
                if abs((newX + dragStartSize.width) - screen.frame.width) < threshold {
                    newX = screen.frame.width - dragStartSize.width
                }
                if abs(newY) < threshold { newY = 0 }
                if abs((newY + dragStartSize.height) - screen.frame.height) < threshold {
                    newY = screen.frame.height - dragStartSize.height
                }
                
                // Snap to window edges during move
                for edge in snapTargets.windowEdges {
                    if abs(newX - edge.minX) < threshold && newY >= edge.minY && newY <= edge.maxY {
                        newX = edge.minX
                    }
                    if abs((newX + dragStartSize.width) - edge.maxX) < threshold && newY >= edge.minY && newY <= edge.maxY {
                        newX = edge.maxX - dragStartSize.width
                    }
                    if abs(newY - edge.minY) < threshold && newX >= edge.minX && newX <= edge.maxX {
                        newY = edge.minY
                    }
                    if abs((newY + dragStartSize.height) - edge.maxY) < threshold && newX >= edge.minX && newX <= edge.maxX {
                        newY = edge.maxY - dragStartSize.height
                    }
                }

                let movedRect = CGRect(
                    x: newX, y: newY, width: dragStartSize.width, height: dragStartSize.height)
                globalSelectionRect = GeometryMapper.localToGlobal(movedRect, in: screen)
            }
        }
        return renderModel(for: screen)
    }

    func handleMouseUp(on screen: NSScreen) -> RenderModel {
        if isSelecting {
            isSelecting = false
            let rect = normalizedRect(globalSelectionRect)
            if rect.width > 3 && rect.height > 3 {
                hasSelection = true
                globalSelectionRect = rect
            } else {
                globalSelectionRect = .zero
                hasSelection = false
            }
        }
        isDragging = false
        activeHandle = .none
        return renderModel(for: screen)
    }

    func clearSelection() {
        hasSelection = false
        globalSelectionRect = .zero
    }

    func freezeSelection(image: NSImage, localRect: CGRect, in screen: NSScreen) {
        frozenSelectionImage = image
        frozenSelectionRect = GeometryMapper.localToGlobal(localRect, in: screen)
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard hasSelection else { return }
        globalSelectionRect.origin.x += dx
        globalSelectionRect.origin.y += dy
    }

    func normalizedSelectionRect(in screen: NSScreen) -> CGRect {
        GeometryMapper.globalToLocal(normalizedRect(globalSelectionRect), in: screen)
    }

    private func normalizedRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(rect.origin.x, rect.origin.x + rect.width),
            y: min(rect.origin.y, rect.origin.y + rect.height),
            width: abs(rect.width),
            height: abs(rect.height)
        ).integral
    }

    private func refreshSnapTargets(for screen: NSScreen) {
        let b = CGRect(origin: .zero, size: screen.frame.size)
        snapTargets.screenEdges = [
            CGRect(x: b.minX, y: b.minY, width: b.width, height: 1),
            CGRect(x: b.minX, y: b.maxY, width: b.width, height: 1),
            CGRect(x: b.minX, y: b.minY, width: 1, height: b.height),
            CGRect(x: b.maxX, y: b.minY, width: 1, height: b.height)
        ]
        
        // Add window edges for magnetic snapping
        snapTargets.windowEdges = []
        snapTargets.windowCenters = []
        
        if detectWindows {
            let windows = windowDetector.cachedWindows
            for window in windows {
                let localFrame = GeometryMapper.globalToLocal(window.globalAppKitFrame, in: screen)
                // Add window edges
                snapTargets.windowEdges.append(
                    CGRect(x: localFrame.minX, y: localFrame.minY, width: localFrame.width, height: 1)
                )
                snapTargets.windowEdges.append(
                    CGRect(x: localFrame.minX, y: localFrame.maxY, width: localFrame.width, height: 1)
                )
                snapTargets.windowEdges.append(
                    CGRect(x: localFrame.minX, y: localFrame.minY, width: 1, height: localFrame.height)
                )
                snapTargets.windowEdges.append(
                    CGRect(x: localFrame.maxX, y: localFrame.minY, width: 1, height: localFrame.height)
                )
                // Add window center for center snapping
                snapTargets.windowCenters.append(CGPoint(x: localFrame.midX, y: localFrame.midY))
            }
        }
    }

    private func hitTestHandle(point: CGPoint, rect: CGRect) -> ResizeHandle {
        let handles = getHandleRects(for: rect)
        for (handle, handleRect) in handles where handleRect.insetBy(dx: -8, dy: -8).contains(point) {
            return handle
        }
        return .none
    }

    private func getHandleRects(for rect: CGRect) -> [ResizeHandle: CGRect] {
        let handleSize: CGFloat = 12  // 💡 增大点击判定区域
        let hs = handleSize / 2
        return [
            .topLeft: CGRect(
                x: rect.minX - hs, y: rect.maxY - hs, width: handleSize, height: handleSize),
            .top: CGRect(
                x: rect.midX - hs, y: rect.maxY - hs, width: handleSize, height: handleSize),
            .topRight: CGRect(
                x: rect.maxX - hs, y: rect.maxY - hs, width: handleSize, height: handleSize),
            .left: CGRect(
                x: rect.minX - hs, y: rect.midY - hs, width: handleSize, height: handleSize),
            .right: CGRect(
                x: rect.maxX - hs, y: rect.midY - hs, width: handleSize, height: handleSize),
            .bottomLeft: CGRect(
                x: rect.minX - hs, y: rect.minY - hs, width: handleSize, height: handleSize),
            .bottom: CGRect(
                x: rect.midX - hs, y: rect.minY - hs, width: handleSize, height: handleSize),
            .bottomRight: CGRect(
                x: rect.maxX - hs, y: rect.minY - hs, width: handleSize, height: handleSize)
        ]
    }

    private func resizeRect(_ rect: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var r = rect
        switch handle {
        case .topLeft:
            r = CGRect(
                x: point.x, y: rect.minY, width: rect.maxX - point.x, height: point.y - rect.minY)
        case .top:
            r = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
        case .topRight:
            r = CGRect(
                x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
        case .left:
            r = CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: rect.height)
        case .right:
            r = CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: rect.height)
        case .bottomLeft:
            r = CGRect(
                x: point.x, y: point.y, width: rect.maxX - point.x, height: rect.maxY - point.y)
        case .bottom:
            r = CGRect(x: rect.minX, y: point.y, width: rect.width, height: rect.maxY - point.y)
        case .bottomRight:
            r = CGRect(
                x: rect.minX, y: point.y, width: point.x - rect.minX, height: rect.maxY - point.y)
        case .none: break
        }
        return r
    }
}
