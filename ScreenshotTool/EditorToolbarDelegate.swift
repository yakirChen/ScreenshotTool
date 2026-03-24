//
//  EditorToolbarDelegate.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//


import Cocoa

protocol EditorToolbarDelegate: AnyObject {
    func toolDidChange(_ tool: AnnotationTool)
    func colorDidChange(_ color: NSColor)
    func lineWidthDidChange(_ width: CGFloat)
    func undoAction()
    func redoAction()
    func saveAction()
    func copyAction()
    func closeAction()
}

class EditorToolbarView: NSView {
    
    weak var delegate: EditorToolbarDelegate?
    
    var currentTool: AnnotationTool = .select {
        didSet { updateToolButtons() }
    }
    var currentColor: NSColor = .systemRed {
        didSet { colorWell?.color = currentColor }
    }
    
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorWell: NSColorWell?
    private var lineWidthSlider: NSSlider?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.95, alpha: 1).cgColor
        
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 2
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 32),
        ])
        
        // 工具按钮
        let tools: [AnnotationTool] = [.select, .arrow, .rectangle, .ellipse, .line, .pen, .text, .highlight, .blur, .number]
        
        for tool in tools {
            let button = createToolButton(tool: tool)
            toolButtons[tool] = button
            stackView.addArrangedSubview(button)
        }
        
        // 分隔线
        stackView.addArrangedSubview(createSeparator())
        
        // 颜色选择
        let cw = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        cw.color = currentColor
        cw.target = self
        cw.action = #selector(colorChanged(_:))
        if #available(macOS 13.0, *) {
            cw.colorWellStyle = .minimal
        }
        cw.translatesAutoresizingMaskIntoConstraints = false
        cw.widthAnchor.constraint(equalToConstant: 28).isActive = true
        cw.heightAnchor.constraint(equalToConstant: 28).isActive = true
        colorWell = cw
        stackView.addArrangedSubview(cw)
        
        // 线宽滑块
        let slider = NSSlider(value: 2, minValue: 1, maxValue: 10, target: self, action: #selector(lineWidthChanged(_:)))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        lineWidthSlider = slider
        stackView.addArrangedSubview(slider)
        
        // 分隔线
        stackView.addArrangedSubview(createSeparator())
        
        // 撤销/重做
        stackView.addArrangedSubview(createActionButton(icon: "arrow.uturn.backward", action: #selector(undoClicked), tooltip: "撤销 ⌘Z"))
        stackView.addArrangedSubview(createActionButton(icon: "arrow.uturn.forward", action: #selector(redoClicked), tooltip: "重做 ⌘⇧Z"))
        
        // 分隔线
        stackView.addArrangedSubview(createSeparator())
        
        // 保存/复制/关闭
        stackView.addArrangedSubview(createActionButton(icon: "doc.on.clipboard", action: #selector(copyClicked), tooltip: "复制 ⌘C"))
        stackView.addArrangedSubview(createActionButton(icon: "square.and.arrow.down", action: #selector(saveClicked), tooltip: "保存 ⌘S"))
        stackView.addArrangedSubview(createActionButton(icon: "xmark", action: #selector(closeClicked), tooltip: "关闭"))
        
        updateToolButtons()
    }
    
    private func createToolButton(tool: AnnotationTool) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.image = NSImage(systemSymbolName: tool.icon, accessibilityDescription: tool.rawValue)
        button.toolTip = tool.rawValue
        button.target = self
        button.action = #selector(toolClicked(_:))
        button.tag = AnnotationTool.allCases.firstIndex(of: tool) ?? 0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        // 使用 setButtonType 来支持 toggle 效果
        button.setButtonType(.toggle)
        return button
    }
    
    private func createActionButton(icon: String, action: Selector, tooltip: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }
    
    private func createSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return sep
    }
    
    private func updateToolButtons() {
        for (tool, button) in toolButtons {
            button.state = (tool == currentTool) ? .on : .off
            button.contentTintColor = (tool == currentTool) ? .systemBlue : .labelColor
        }
    }
    
    // MARK: - Actions
    
    @objc private func toolClicked(_ sender: NSButton) {
        let tool = AnnotationTool.allCases[sender.tag]
        currentTool = tool
        delegate?.toolDidChange(tool)
    }
    
    @objc private func colorChanged(_ sender: NSColorWell) {
        currentColor = sender.color
        delegate?.colorDidChange(sender.color)
    }
    
    @objc private func lineWidthChanged(_ sender: NSSlider) {
        delegate?.lineWidthDidChange(CGFloat(sender.doubleValue))
    }
    
    @objc private func undoClicked() { delegate?.undoAction() }
    @objc private func redoClicked() { delegate?.redoAction() }
    @objc private func saveClicked() { delegate?.saveAction() }
    @objc private func copyClicked() { delegate?.copyAction() }
    @objc private func closeClicked() { delegate?.closeAction() }
}