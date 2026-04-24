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
        set {
            state.currentTool = newValue
            state.styleExpanded = newValue == .pen || newValue == .text
        }
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
    private var cancellables = Set<AnyCancellable>()

    private let tools: [AnnotationTool] = [.select, .arrow, .rectangle, .ellipse, .line, .text, .pen, .highlight, .blur, .number, .ocr]

    override init() {
        super.init()
        configurePanel()
        bindState()
    }

    deinit {
        panel.orderOut(nil)
    }

    func present(in parentWindow: NSWindow, overlayBounds: CGRect, selectionRect: CGRect, screen: NSScreen, animated: Bool = false) {
        if hostingView == nil {
            let root = InlineToolbarRootView(state: state, tools: tools, handler: self)
            let host = NSHostingView(rootView: root)
            host.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = host
            hostingView = host
        }

        if panel.parent == nil {
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        updatePosition(overlayBounds: overlayBounds, selectionRect: selectionRect, screen: screen, animated: animated)
        panel.orderFrontRegardless()
    }

    func updatePosition(overlayBounds: CGRect, selectionRect: CGRect, screen: NSScreen, animated: Bool = true) {
        guard let hostingView else { return }

        let fitting = hostingView.fittingSize
        let toolbarSize = NSSize(width: max(440, fitting.width), height: max(48, fitting.height))
        resizePanel(to: toolbarSize)

        let targetLocalOrigin = Self.computeMagneticOrigin(
            selectionRect: selectionRect,
            overlayBounds: overlayBounds,
            toolbarSize: toolbarSize
        )

        let targetFrame = CGRect(
            origin: CGPoint(
                x: screen.frame.origin.x + targetLocalOrigin.x,
                y: screen.frame.origin.y + targetLocalOrigin.y
            ),
            size: toolbarSize
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    func dismiss() {
        guard panel.parent != nil || panel.isVisible else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    private func bindState() {
        state.$styleExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshLayoutSize()
            }
            .store(in: &cancellables)
    }

    private func refreshLayoutSize() {
        guard let parent = panel.parent, let screen = parent.screen else { return }
        updatePosition(
            overlayBounds: CGRect(origin: .zero, size: screen.frame.size),
            selectionRect: state.selectionRect,
            screen: screen,
            animated: true
        )
    }

    private func resizePanel(to size: NSSize) {
        var frame = panel.frame
        frame.size = size
        panel.setContentSize(size)
        panel.setFrame(frame, display: true)
    }

    fileprivate func perform(_ action: ToolbarAction) {
        switch action {
        case .cancel:
            delegate?.inlineToolbarDidCancel(self)
        case .undo:
            delegate?.inlineToolbarDidUndo(self)
        case .redo:
            delegate?.inlineToolbarDidRedo(self)
        case .copy:
            delegate?.inlineToolbarDidCopy(self)
        case .pin:
            delegate?.inlineToolbarDidPin(self)
        case .confirm:
            delegate?.inlineToolbarDidConfirm(self)
        case .selectTool(let tool):
            state.currentTool = tool
            delegate?.inlineToolbar(self, didSelectTool: tool)
            if tool == .pen || tool == .text {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    state.styleExpanded = true
                }
            } else {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    state.styleExpanded = false
                }
            }
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                state.styleExpanded.toggle()
            }
        }
    }

    static func computeMagneticOrigin(selectionRect: CGRect, overlayBounds: CGRect, toolbarSize: NSSize) -> CGPoint {
        let margin: CGFloat = 12
        let gap: CGFloat = 10

        let clampedX = min(
            max(selectionRect.midX - toolbarSize.width / 2, margin),
            max(margin, overlayBounds.width - toolbarSize.width - margin)
        )

        let belowY = selectionRect.minY - toolbarSize.height - gap
        let aboveY = selectionRect.maxY + gap
        let insideBottomY = selectionRect.minY + gap

        let fitsBelow = belowY >= margin
        let fitsAbove = (aboveY + toolbarSize.height) <= (overlayBounds.height - margin)
        let fitsInside = (insideBottomY + toolbarSize.height) <= (selectionRect.maxY - gap)

        let spaceBelow = selectionRect.minY
        let spaceAbove = overlayBounds.height - selectionRect.maxY

        let y: CGFloat
        if fitsBelow && (spaceBelow > 120 || spaceBelow >= spaceAbove) {
            y = belowY
        } else if fitsAbove {
            y = aboveY
        } else if fitsInside {
            y = insideBottomY
        } else {
            y = min(max(belowY, margin), overlayBounds.height - toolbarSize.height - margin)
        }

        return CGPoint(x: clampedX, y: y)
    }

    func updateSelectionRect(_ rect: CGRect) {
        state.selectionRect = rect
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
    case cancel
    case undo
    case redo
    case copy
    case pin
    case confirm
    case selectTool(AnnotationTool)
    case setColor(NSColor)
    case setLineWidth(CGFloat)
    case setFontSize(CGFloat)
    case toggleStylePanel
}

private struct ToolbarToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: tool.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.1 : 0.001)))
                }
                .scaleEffect(hovering ? 1.03 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: hovering)
        }
        .buttonStyle(.plain)
        .help(tool.rawValue)
        .onHover { hovering = $0 }
    }
}

private struct InlineToolbarRootView: View {
    @ObservedObject var state: ToolbarState
    let tools: [AnnotationTool]
    weak var handler: InlineEditorToolbar?

    private let swatches: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white]
    private let widths: [CGFloat] = [1, 2, 3, 4, 6, 8, 10, 12]
    private let fontSizes: [CGFloat] = [12, 14, 16, 18, 20, 24, 28, 32]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                smallButton(icon: "xmark") { handler?.perform(.cancel) }
                smallButton(icon: "arrow.uturn.backward") { handler?.perform(.undo) }
                smallButton(icon: "arrow.uturn.forward") { handler?.perform(.redo) }

                ForEach(tools, id: \.self) { tool in
                    ToolbarToolButton(tool: tool, isSelected: state.currentTool == tool) {
                        handler?.perform(.selectTool(tool))
                    }
                }

                Button {
                    handler?.perform(.toggleStylePanel)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(state.styleExpanded ? 0.14 : 0.001), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                smallButton(icon: "doc.on.doc") { handler?.perform(.copy) }
                smallButton(icon: "pin") { handler?.perform(.pin) }
                smallButton(icon: "checkmark") { handler?.perform(.confirm) }
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if state.styleExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(swatches, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                                .frame(width: 18, height: 18)
                                .onTapGesture {
                                    handler?.perform(.setColor(NSColor(color)))
                                }
                        }
                    }

                    HStack(spacing: 8) {
                        Text("线宽")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        ForEach(widths, id: \.self) { width in
                            Button("\(Int(width))") {
                                handler?.perform(.setLineWidth(width))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(state.currentLineWidth == width ? .accentColor : nil)
                        }

                        if state.currentTool == .text {
                            Text("字号")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                            ForEach(fontSizes, id: \.self) { size in
                                Button("\(Int(size))") {
                                    handler?.perform(.setFontSize(size))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(state.currentFontSize == size ? .accentColor : nil)
                            }
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.34), radius: 8, x: 0, y: 2)
                .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 14)
        }
        .compositingGroup()
    }

    @Environment(\.colorScheme) private var colorScheme

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.15) : .black.opacity(0.1)
    }

    private func smallButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.001), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private final class InlineToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        worksWhenModal = true
    }
}
