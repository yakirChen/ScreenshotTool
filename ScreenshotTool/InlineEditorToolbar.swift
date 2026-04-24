//
//  InlineEditorToolbar.swift
//  ScreenshotTool
//

import Cocoa

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

final class InlineEditorToolbar: NSView {

    weak var delegate: InlineEditorToolbarDelegate?

    var currentTool: AnnotationTool = .arrow {
        didSet { updateToolButtons() }
    }
    var currentColor: NSColor = .systemRed {
        didSet { colorWell?.color = currentColor }
    }
    var currentLineWidth: CGFloat = 2 {
        didSet { lineWidthSlider?.doubleValue = Double(currentLineWidth) }
    }
    var currentFontSize: CGFloat = 16 {
        didSet { fontSizeSlider?.doubleValue = Double(currentFontSize) }
    }

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorWell: NSColorWell?
    private weak var contentStack: NSStackView?
    private var lineWidthSlider: NSSlider?
    private var fontSizeSlider: NSSlider?

    private let tools: [AnnotationTool] = [
        .arrow, .rectangle, .ellipse, .line,
        .text, .pen, .highlight, .blur, .number, .ocr
    ]

    static let barHeight: CGFloat = 36
    static let barWidth: CGFloat = 420

    override init(frame frameRect: NSRect) {
        let size = NSSize(width: Self.barWidth, height: Self.barHeight)
        super.init(frame: NSRect(origin: frameRect.origin, size: size))
        setupUI()
        resizeToFitContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true

        let visual = NSVisualEffectView(frame: bounds)
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 10
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]
        addSubview(visual)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        contentStack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Cancel
        let cancelBtn = createIconButton(
            icon: "xmark", action: #selector(cancelClicked), tooltip: "取消 ESC")
        stack.addArrangedSubview(cancelBtn)

        stack.addArrangedSubview(createDivider())

        // Tool buttons
        for tool in tools {
            let btn = createToolButton(tool: tool)
            toolButtons[tool] = btn
            stack.addArrangedSubview(btn)
        }

        stack.addArrangedSubview(createDivider())

        // Color
        let cw = NSColorWell(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        cw.color = currentColor
        cw.target = self
        cw.action = #selector(colorChanged(_:))
        if #available(macOS 13.0, *) {
            cw.colorWellStyle = .minimal
        }
        cw.translatesAutoresizingMaskIntoConstraints = false
        cw.widthAnchor.constraint(equalToConstant: 18).isActive = true
        cw.heightAnchor.constraint(equalToConstant: 18).isActive = true
        colorWell = cw
        stack.addArrangedSubview(cw)

        stack.addArrangedSubview(createDivider())

        let widthSlider = NSSlider(value: Double(currentLineWidth), minValue: 1, maxValue: 12, target: self, action: #selector(lineWidthChanged(_:)))
        widthSlider.controlSize = .small
        widthSlider.frame.size.width = 64
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthSlider.widthAnchor.constraint(equalToConstant: 64).isActive = true
        widthSlider.toolTip = "线宽"
        lineWidthSlider = widthSlider
        stack.addArrangedSubview(makeTagLabel("粗"))
        stack.addArrangedSubview(widthSlider)

        stack.addArrangedSubview(createDivider())

        let textSlider = NSSlider(value: Double(currentFontSize), minValue: 12, maxValue: 48, target: self, action: #selector(fontSizeChanged(_:)))
        textSlider.controlSize = .small
        textSlider.frame.size.width = 64
        textSlider.translatesAutoresizingMaskIntoConstraints = false
        textSlider.widthAnchor.constraint(equalToConstant: 64).isActive = true
        textSlider.toolTip = "字体大小"
        fontSizeSlider = textSlider
        stack.addArrangedSubview(makeTagLabel("字"))
        stack.addArrangedSubview(textSlider)

        stack.addArrangedSubview(createDivider())

        // Undo / Redo
        stack.addArrangedSubview(
            createIconButton(icon: "arrow.uturn.backward", action: #selector(undoClicked), tooltip: "撤销 ⌘Z"))
        stack.addArrangedSubview(
            createIconButton(icon: "arrow.uturn.forward", action: #selector(redoClicked), tooltip: "重做 ⌘⇧Z"))

        stack.addArrangedSubview(createDivider())
        stack.addArrangedSubview(createIconButton(icon: "doc.on.doc", action: #selector(copyClicked), tooltip: "复制"))
        stack.addArrangedSubview(createIconButton(icon: "pin", action: #selector(pinClicked), tooltip: "Pin"))
        stack.addArrangedSubview(createIconButton(icon: "checkmark", action: #selector(confirmClicked), tooltip: "完成"))

        updateToolButtons()
    }

    private func resizeToFitContent() {
        layoutSubtreeIfNeeded()
        let contentWidth = contentStack?.fittingSize.width ?? Self.barWidth
        let targetWidth = max(360, contentWidth + 16)
        setFrameSize(NSSize(width: targetWidth, height: Self.barHeight))
    }

    // MARK: - Button creation

    private func createToolButton(tool: AnnotationTool) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: tool.icon, accessibilityDescription: tool.rawValue)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = tool.rawValue
        btn.target = self
        btn.action = #selector(toolClicked(_:))
        btn.tag = AnnotationTool.allCases.firstIndex(of: tool) ?? 0
        btn.setButtonType(.toggle)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        return btn
    }

    private func createIconButton(icon: String, action: Selector, tooltip: String) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return btn
    }

    private func createDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return v
    }

    private func makeTagLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: - Update

    private func updateToolButtons() {
        for (tool, button) in toolButtons {
            let isActive = (tool == currentTool)
            button.state = isActive ? .on : .off
            button.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
            button.layer?.backgroundColor = isActive
                ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
        }
    }

    // MARK: - Actions

    @objc private func toolClicked(_ sender: NSButton) {
        let allCases = AnnotationTool.allCases
        guard sender.tag < allCases.count else { return }
        currentTool = allCases[sender.tag]
        delegate?.inlineToolbar(self, didSelectTool: currentTool)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        currentColor = sender.color
        delegate?.inlineToolbar(self, didChangeColor: sender.color)
    }

    @objc private func undoClicked() { delegate?.inlineToolbarDidUndo(self) }
    @objc private func redoClicked() { delegate?.inlineToolbarDidRedo(self) }
    @objc private func confirmClicked() { delegate?.inlineToolbarDidConfirm(self) }
    @objc private func cancelClicked() { delegate?.inlineToolbarDidCancel(self) }
    @objc private func copyClicked() { delegate?.inlineToolbarDidCopy(self) }
    @objc private func pinClicked() { delegate?.inlineToolbarDidPin(self) }
    @objc private func lineWidthChanged(_ sender: NSSlider) {
        currentLineWidth = CGFloat(sender.doubleValue)
        delegate?.inlineToolbar(self, didChangeLineWidth: currentLineWidth)
    }
    @objc private func fontSizeChanged(_ sender: NSSlider) {
        currentFontSize = CGFloat(sender.doubleValue)
        delegate?.inlineToolbar(self, didChangeFontSize: currentFontSize)
    }
}
