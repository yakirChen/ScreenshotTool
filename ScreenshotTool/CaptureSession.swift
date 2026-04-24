import Cocoa

final class CaptureSession {
    struct SnapTargets {
        var screenEdges: [CGRect] = []
        var windowEdges: [CGRect] = []
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
        let localWindow = hoverWindow.map { GeometryMapper.globalToLocal($0.globalAppKitFrame, in: screen) }
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

        if hasSelection {
            let localRect = GeometryMapper.globalToLocal(normalizedRect(globalSelectionRect), in: screen)
            let handle = hitTestHandle(point: localPoint, rect: localRect)
            if handle != .none {
                activeHandle = handle
                isDragging = true
                isSelecting = false
                startPointGlobal = globalPoint
                return renderModel(for: screen)
            }
            if localRect.contains(localPoint) {
                isDragging = true
                isSelecting = false
                activeHandle = .none
                dragOffset = CGPoint(x: localPoint.x - localRect.origin.x, y: localPoint.y - localRect.origin.y)
                dragStartSize = localRect.size
                return renderModel(for: screen)
            }
        }

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

        if isSelecting && !isDragging {
            globalSelectionRect = CGRect(
                x: min(startPointGlobal.x, globalPoint.x),
                y: min(startPointGlobal.y, globalPoint.y),
                width: abs(globalPoint.x - startPointGlobal.x),
                height: abs(globalPoint.y - startPointGlobal.y)
            )
        } else if isDragging && !isSelecting {
            let localRect = GeometryMapper.globalToLocal(normalizedRect(globalSelectionRect), in: screen)
            if activeHandle != .none {
                let resized = resizeRect(localRect, handle: activeHandle, to: localPoint)
                globalSelectionRect = GeometryMapper.localToGlobal(resized, in: screen)
            } else {
                var newX = localPoint.x - dragOffset.x
                var newY = localPoint.y - dragOffset.y
                newX = max(0, min(newX, screen.frame.width - dragStartSize.width))
                newY = max(0, min(newY, screen.frame.height - dragStartSize.height))
                let movedLocalRect = CGRect(
                    x: newX,
                    y: newY,
                    width: dragStartSize.width,
                    height: dragStartSize.height
                )
                globalSelectionRect = GeometryMapper.localToGlobal(movedLocalRect, in: screen)
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
        if let hoverWindow {
            let local = GeometryMapper.globalToLocal(hoverWindow.globalAppKitFrame, in: screen)
            snapTargets.windowEdges = [
                CGRect(x: local.minX, y: local.minY, width: local.width, height: 1),
                CGRect(x: local.minX, y: local.maxY, width: local.width, height: 1),
                CGRect(x: local.minX, y: local.minY, width: 1, height: local.height),
                CGRect(x: local.maxX, y: local.minY, width: 1, height: local.height)
            ]
        } else {
            snapTargets.windowEdges = []
        }
    }

    private func hitTestHandle(point: CGPoint, rect: CGRect) -> ResizeHandle {
        let handles = getHandleRects(for: rect)
        for (handle, handleRect) in handles where handleRect.insetBy(dx: -6, dy: -6).contains(point) {
            return handle
        }
        return .none
    }

    private func getHandleRects(for rect: CGRect) -> [ResizeHandle: CGRect] {
        let handleSize: CGFloat = 8
        let hs = handleSize / 2
        return [
            .topLeft: CGRect(x: rect.minX - hs, y: rect.maxY - hs, width: handleSize, height: handleSize),
            .top: CGRect(x: rect.midX - hs, y: rect.maxY - hs, width: handleSize, height: handleSize),
            .topRight: CGRect(x: rect.maxX - hs, y: rect.maxY - hs, width: handleSize, height: handleSize),
            .left: CGRect(x: rect.minX - hs, y: rect.midY - hs, width: handleSize, height: handleSize),
            .right: CGRect(x: rect.maxX - hs, y: rect.midY - hs, width: handleSize, height: handleSize),
            .bottomLeft: CGRect(x: rect.minX - hs, y: rect.minY - hs, width: handleSize, height: handleSize),
            .bottom: CGRect(x: rect.midX - hs, y: rect.minY - hs, width: handleSize, height: handleSize),
            .bottomRight: CGRect(x: rect.maxX - hs, y: rect.minY - hs, width: handleSize, height: handleSize),
        ]
    }

    private func resizeRect(_ rect: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        switch handle {
        case .topLeft:
            return CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: point.y - rect.minY)
        case .top:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
        case .topRight:
            return CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
        case .left:
            return CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: rect.height)
        case .right:
            return CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: rect.height)
        case .bottomLeft:
            return CGRect(x: point.x, y: point.y, width: rect.maxX - point.x, height: rect.maxY - point.y)
        case .bottom:
            return CGRect(x: rect.minX, y: point.y, width: rect.width, height: rect.maxY - point.y)
        case .bottomRight:
            return CGRect(x: rect.minX, y: point.y, width: point.x - rect.minX, height: rect.maxY - point.y)
        case .none:
            return rect
        }
    }
}
