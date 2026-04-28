//
//  InlineEditorToolbar.swift
//  ScreenshotTool
//

import Cocoa
import Combine
import SwiftUI

protocol InlineEditorToolbarDelegate: AnyObject {
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didSelectTool tool: AnnotationTool)
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didChangeColor color: NSColor)
    func inlineToolbarDidUndo(_ toolbar: InlineEditorToolbar)
    func inlineToolbarDidRedo(_ toolbar: InlineEditorToolbar)
    func inlineToolbarDidConfirm(_ toolbar: InlineEditorToolbar)
    func inlineToolbarDidCancel(_ toolbar: InlineEditorToolbar)
    func inlineToolbarDidCopy(_ toolbar: InlineEditorToolbar)
    func inlineToolbarDidPin(_ toolbar: InlineEditorToolbar)
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didChangeLineWidth width: CGFloat)
    func inlineToolbar(_ toolbar: InlineEditorToolbar, didChangeFontSize size: CGFloat)
}

@MainActor
final class InlineEditorToolbar: NSObject {

    weak var delegate: InlineEditorToolbarDelegate?

    var currentTool: AnnotationTool {
        get { state.currentTool }
        set { state.currentTool = newValue }
    }

    var currentColor: NSColor {
        get { state.currentColor }
        set { state.currentColor = newValue }
    }

    var currentLineWidth: CGFloat {
        get { state.currentLineWidth }
        set { state.currentLineWidth = newValue }
    }

    var currentFontSize: CGFloat {
        get { state.currentFontSize }
        set { state.currentFontSize = newValue }
    }

    private let state = ToolbarState()
    private let panel = InlineToolbarPanel()
    private var hostingView: NSHostingView<InlineToolbarRootView>?
    private var lastOverlayBounds: CGRect = .zero
    private weak var currentParentWindow: NSWindow?

    private let tools: [AnnotationTool] = [
        .select, .arrow, .rectangle, .ellipse, .line, .text, .pen, .highlight, .blur, .number, .ocr
    ]

    override init() {
        super.init()
        configurePanel()
    }

    deinit {
        panel.orderOut(nil)
    }

    func present(
        in parentWindow: NSWindow, overlayBounds: CGRect, selectionRect: CGRect, screen: NSScreen,
        animated: Bool = false
    ) {
        state.selectionRect = selectionRect
        lastOverlayBounds = overlayBounds
        currentParentWindow = parentWindow

        if hostingView == nil {
            let root = InlineToolbarRootView(state: state, tools: tools, handler: self)
            let host = NSHostingView(rootView: root)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.layer?.backgroundColor = .clear
            panel.contentView = host
            hostingView = host
        }

        updatePosition(
            overlayBounds: overlayBounds, selectionRect: selectionRect, screen: screen,
            animated: false)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }

    func updatePosition(
        overlayBounds: CGRect, selectionRect: CGRect, screen: NSScreen, animated: Bool = true
    ) {
        guard let hostingView else { return }
        state.selectionRect = selectionRect
        lastOverlayBounds = overlayBounds

        let toolbarSize = hostingView.fittingSize
        let targetLocalOrigin = Self.computeMagneticOrigin(
            selectionRect: selectionRect, overlayBounds: overlayBounds, toolbarSize: toolbarSize)

        let targetFrame = CGRect(
            origin: CGPoint(
                x: screen.frame.origin.x + targetLocalOrigin.x,
                y: screen.frame.origin.y + targetLocalOrigin.y),
            size: toolbarSize
        )

        if animated {
            panel.animator().setFrame(targetFrame, display: true)
        } else {
            panel.setFrame(targetFrame, display: true)
        }
        panel.invalidateShadow()
    }

    func updateSelectionRect(_ rect: CGRect) {
        state.selectionRect = rect
        // 💡 修复：使用 currentParentWindow 而不是 panel.parent
        guard let screen = currentParentWindow?.screen ?? NSScreen.main else { return }
        updatePosition(
            overlayBounds: lastOverlayBounds, selectionRect: rect, screen: screen, animated: false)
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle
        ]
    }

    fileprivate func perform(_ action: ToolbarAction) {
        switch action {
        case .cancel: delegate?.inlineToolbarDidCancel(self)
        case .undo: delegate?.inlineToolbarDidUndo(self)
        case .redo: delegate?.inlineToolbarDidRedo(self)
        case .copy: delegate?.inlineToolbarDidCopy(self)
        case .pin: delegate?.inlineToolbarDidPin(self)
        case .confirm: delegate?.inlineToolbarDidConfirm(self)
        case .selectTool(let tool):
            state.currentTool = tool
            delegate?.inlineToolbar(self, didSelectTool: tool)
        case .setColor(let color):
            state.currentColor = color
            delegate?.inlineToolbar(self, didChangeColor: color)
        case .setLineWidth(let width):
            state.currentLineWidth = width
            delegate?.inlineToolbar(self, didChangeLineWidth: width)
        case .setFontSize(let size):
            state.currentFontSize = size
            delegate?.inlineToolbar(self, didChangeFontSize: size)
        case .toggleStylePanel:
            state.styleExpanded.toggle()
        }
    }

    static func computeMagneticOrigin(
        selectionRect: CGRect, overlayBounds: CGRect, toolbarSize: NSSize
    ) -> CGPoint {
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        
        // Calculate preferred X position (centered on selection)
        var preferredX = selectionRect.midX - toolbarSize.width / 2
        
        // Clamp X to stay within screen bounds
        let minX = margin
        let maxX = overlayBounds.width - toolbarSize.width - margin
        var clampedX = min(max(preferredX, minX), maxX)
        
        // Calculate Y positions
        let belowY = selectionRect.minY - toolbarSize.height - gap
        let aboveY = selectionRect.maxY + gap
        
        // Determine best Y position with anti-occlusion logic
        var preferredY: CGFloat
        let spaceBelow = selectionRect.minY - margin
        let spaceAbove = overlayBounds.height - selectionRect.maxY - margin
        
        // Prefer the side with more space
        if spaceBelow >= toolbarSize.height + gap && spaceAbove >= toolbarSize.height + gap {
            // Both sides have enough space, prefer below
            preferredY = belowY
        } else if spaceBelow >= toolbarSize.height + gap {
            // Only below has enough space
            preferredY = belowY
        } else if spaceAbove >= toolbarSize.height + gap {
            // Only above has enough space
            preferredY = aboveY
        } else {
            // Neither side has enough space, use the larger side
            preferredY = spaceBelow > spaceAbove ? belowY : aboveY
        }
        
        // Ensure Y stays within bounds
        let minY = margin
        let maxY = overlayBounds.height - toolbarSize.height - margin
        let clampedY = min(max(preferredY, minY), maxY)
        
        // Final anti-occlusion: if toolbar would overlap selection, flip to other side
        let toolbarRect = CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: toolbarSize)
        if toolbarRect.intersects(selectionRect) {
            // Try flipping to the other side
            let flippedY = (clampedY < selectionRect.midY) ? aboveY : belowY
            let flippedClampedY = min(max(flippedY, minY), maxY)
            let flippedRect = CGRect(origin: CGPoint(x: clampedX, y: flippedClampedY), size: toolbarSize)
            
            // Use flipped position if it doesn't overlap
            if !flippedRect.intersects(selectionRect) {
                return CGPoint(x: clampedX, y: flippedClampedY)
            }
        }
        
        return CGPoint(x: clampedX, y: clampedY)
    }
}

@MainActor
private final class ToolbarState: ObservableObject {
    @Published var currentTool: AnnotationTool = .arrow
    @Published var currentColor: NSColor = .systemRed
    @Published var currentLineWidth: CGFloat = 2
    @Published var currentFontSize: CGFloat = 16
    @Published var styleExpanded: Bool = false
    @Published var selectionRect: CGRect = .zero
}

private enum ToolbarAction {
    case cancel, undo, redo, copy, pin, confirm
    case selectTool(AnnotationTool)
    case setColor(NSColor)
    case setLineWidth(CGFloat)
    case setFontSize(CGFloat)
    case toggleStylePanel
}

private struct InlineToolbarRootView: View {
    @ObservedObject var state: ToolbarState
    let tools: [AnnotationTool]
    weak var handler: InlineEditorToolbar?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                toolIconButton(icon: "xmark", help: "取消 (ESC)") { handler?.perform(.cancel) }
                toolIconButton(icon: "arrow.uturn.backward", help: "撤销 (⌘Z)") {
                    handler?.perform(.undo)
                }
            }

            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18)

            HStack(spacing: 6) {
                ForEach(tools, id: \.self) { tool in
                    Button {
                        handler?.perform(.selectTool(tool))
                    } label: {
                        Image(systemName: tool.icon)
                            .font(
                                .system(
                                    size: 13, weight: state.currentTool == tool ? .bold : .medium)
                            )
                            .foregroundStyle(
                                state.currentTool == tool ? Color.white : Color.primary
                            )
                            .frame(width: 28, height: 28)
                            .background(state.currentTool == tool ? Color.accentColor : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(tool.rawValue)
                }
            }

            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18)

            Button {
                state.styleExpanded.toggle()
            } label: {
                ZStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                    Circle()
                        .fill(Color(state.currentColor))
                        .frame(width: 6, height: 6)
                        .offset(x: 7, y: -7)
                }
                .frame(width: 28, height: 28)
                .background(state.styleExpanded ? Color.primary.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $state.styleExpanded, arrowEdge: .top) {
                StylePickerView(state: state, handler: handler)
            }
            .help("颜色与粗细")

            Group {
                toolIconButton(icon: "doc.on.doc", help: "复制 (Return)") { handler?.perform(.copy) }
                toolIconButton(icon: "pin", help: "贴图 (P)") { handler?.perform(.pin) }
                toolIconButton(icon: "checkmark", help: "完成") { handler?.perform(.confirm) }
                    .foregroundStyle(.white)
                    .background(Color.accentColor)
                    .cornerRadius(6)
            }
        }
        .frame(height: 38)  // 💡 锁定高度
        .padding(5)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private func toolIconButton(icon: String, help: String, action: @escaping () -> Void)
    -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct StylePickerView: View {
    @ObservedObject var state: ToolbarState
    weak var handler: InlineEditorToolbar?

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
    private let widths: [CGFloat] = [2, 4, 6, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                        .overlay(
                            state.currentColor == NSColor(color)
                                ? Image(systemName: "checkmark").font(
                                    .system(size: 10, weight: .bold)
                                ).foregroundColor(color == .white ? .black : .white) : nil
                        )
                        .onTapGesture { handler?.perform(.setColor(NSColor(color))) }
                }
            }

            HStack(spacing: 12) {
                Text("粗细").font(.system(size: 11)).foregroundColor(.secondary)
                ForEach(widths, id: \.self) { w in
                    ZStack {
                        Circle().fill(Color.primary.opacity(state.currentLineWidth == w ? 1 : 0.1))
                            .frame(width: 20, height: 20)
                        Circle().fill(state.currentLineWidth == w ? Color.white : Color.primary)
                            .frame(width: w / 2 + 2, height: w / 2 + 2)
                    }
                    .onTapGesture { handler?.perform(.setLineWidth(w)) }
                }
            }

            if state.currentTool == .text {
                VStack(alignment: .leading, spacing: 4) {
                    Text("字号").font(.system(size: 11)).foregroundColor(.secondary)
                    Slider(
                        value: Binding(
                            get: { state.currentFontSize },
                            set: { handler?.perform(.setFontSize($0)) }), in: 12...64)
                }
            }
        }
        .padding(14)
        .frame(width: 250)
    }
}

private final class InlineToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }  // 💡 恢复为 false，防止抢占主窗口焦点
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }
}
