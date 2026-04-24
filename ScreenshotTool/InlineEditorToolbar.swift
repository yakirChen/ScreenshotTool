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
        didSet { lineWidthPopup?.selectItem(withTitle: widthOptionTitle(currentLineWidth)) }
    }
    var currentFontSize: CGFloat = 16 {
        didSet { fontSizePopup?.selectItem(withTitle: fontOptionTitle(currentFontSize)) }
    }

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorWell: NSColorWell?
    private weak var contentStack: NSStackView?
    private var lineWidthPopup: NSPopUpButton?
    private var fontSizePopup: NSPopUpButton?

    private let tools: [AnnotationTool] = [
        .select, .arrow, .rectangle, .ellipse, .line,
        .text, .pen, .highlight, .blur, .number, .ocr
    ]

    static let barHeight: CGFloat = 42
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
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]
        addSubview(visual)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
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

        let widthPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 64, height: 22), pullsDown: false)
        widthPopup.addItems(withTitles: [1, 2, 3, 4, 6, 8, 10, 12].map { widthOptionTitle(CGFloat($0)) })
        widthPopup.selectItem(withTitle: widthOptionTitle(currentLineWidth))
        widthPopup.controlSize = .small
        widthPopup.target = self
        widthPopup.action = #selector(lineWidthChanged(_:))
        widthPopup.toolTip = "线宽"
        widthPopup.translatesAutoresizingMaskIntoConstraints = false
        widthPopup.widthAnchor.constraint(equalToConstant: 64).isActive = true
        lineWidthPopup = widthPopup
        stack.addArrangedSubview(makeTagLabel("粗"))
        stack.addArrangedSubview(widthPopup)

        stack.addArrangedSubview(createDivider())

        let textPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 72, height: 22), pullsDown: false)
        textPopup.addItems(withTitles: [12, 14, 16, 18, 20, 24, 28, 32, 40, 48].map { fontOptionTitle(CGFloat($0)) })
        textPopup.selectItem(withTitle: fontOptionTitle(currentFontSize))
        textPopup.controlSize = .small
        textPopup.target = self
        textPopup.action = #selector(fontSizeChanged(_:))
        textPopup.toolTip = "字体大小"
        textPopup.translatesAutoresizingMaskIntoConstraints = false
        textPopup.widthAnchor.constraint(equalToConstant: 72).isActive = true
        fontSizePopup = textPopup
        stack.addArrangedSubview(makeTagLabel("字"))
        stack.addArrangedSubview(textPopup)

        stack.addArrangedSubview(createDivider())

        // Undo / Redo
        stack.addArrangedSubview(
            createIconButton(icon: "arrow.uturn.backward", action: #selector(undoClicked), tooltip: "撤销 ⌘Z"))
        stack.addArrangedSubview(
            createIconButton(icon: "arrow.uturn.forward", action: #selector(redoClicked), tooltip: "重做 ⌘⇧Z"))

        stack.addArrangedSubview(createDivider())
        stack.addArrangedSubview(createActionButton(title: "复制", icon: "doc.on.doc", action: #selector(copyClicked)))
        stack.addArrangedSubview(createActionButton(title: "Pin", icon: "pin", action: #selector(pinClicked)))
        stack.addArrangedSubview(createActionButton(title: "完成", icon: "checkmark", action: #selector(confirmClicked), accent: true))

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
        btn.bezelStyle = .texturedRounded
        btn.isBordered = true
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 26).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        return btn
    }

    private func createActionButton(
        title: String,
        icon: String,
        action: Selector,
        accent: Bool = false
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = accent ? .white : .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if accent {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            button.layer?.cornerRadius = 6
            button.layer?.borderWidth = 0
            button.isBordered = false
        }
        return button
    }

    private func createDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 16).isActive = true
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
    @objc private func lineWidthChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title,
              let value = Double(title.replacingOccurrences(of: "px", with: ""))
        else { return }
        currentLineWidth = CGFloat(value)
        delegate?.inlineToolbar(self, didChangeLineWidth: currentLineWidth)
    }
    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title,
              let value = Double(title.replacingOccurrences(of: "pt", with: ""))
        else { return }
        currentFontSize = CGFloat(value)
        delegate?.inlineToolbar(self, didChangeFontSize: currentFontSize)
    }

    private func widthOptionTitle(_ value: CGFloat) -> String {
        "\(Int(value))px"
    }

    private func fontOptionTitle(_ value: CGFloat) -> String {
        "\(Int(value))pt"
    }
}
