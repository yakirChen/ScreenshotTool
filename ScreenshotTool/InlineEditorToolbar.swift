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
}

final class InlineEditorToolbar: NSView {

    weak var delegate: InlineEditorToolbarDelegate?

    var currentTool: AnnotationTool = .arrow {
        didSet { updateToolButtons() }
    }
    var currentColor: NSColor = .systemRed {
        didSet { colorWell?.color = currentColor }
    }

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorWell: NSColorWell?

    private let tools: [AnnotationTool] = [
        .arrow, .rectangle, .ellipse, .line,
        .text, .pen, .highlight, .blur, .number
    ]

    static let barHeight: CGFloat = 36
    static let barWidth: CGFloat = 520

    override init(frame frameRect: NSRect) {
        let size = NSSize(width: Self.barWidth, height: Self.barHeight)
        super.init(frame: NSRect(origin: frameRect.origin, size: size))
        setupUI()
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
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

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

        // Undo / Redo
        stack.addArrangedSubview(
            createIconButton(icon: "arrow.uturn.backward", action: #selector(undoClicked), tooltip: "撤销 ⌘Z"))
        stack.addArrangedSubview(
            createIconButton(icon: "arrow.uturn.forward", action: #selector(redoClicked), tooltip: "重做 ⌘⇧Z"))

        stack.addArrangedSubview(createDivider())

        // Confirm
        let confirmBtn = NSButton(title: "完成", target: self, action: #selector(confirmClicked))
        confirmBtn.bezelStyle = .rounded
        confirmBtn.controlSize = .small
        confirmBtn.keyEquivalent = ""
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false
        confirmBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        stack.addArrangedSubview(confirmBtn)

        updateToolButtons()
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
}
