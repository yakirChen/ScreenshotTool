//
//  AnnotationPropertyOverlay.swift
//  Shot
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

protocol AnnotationPropertyDelegate: AnyObject {
    func propertyDidChange(color: NSColor?, lineWidth: CGFloat?, isFilled: Bool?, style: Int?, fontName: String?, fontSize: CGFloat?)
    func didRequestCloseOverlay()
}

/// 高保真悬浮属性设置面板 (深度复刻 Shottr 风格)
class AnnotationPropertyOverlay: NSView {
    
    weak var delegate: AnnotationPropertyDelegate?
    
    var color: NSColor = .systemRed { didSet { updateUI() } }
    var lineWidth: CGFloat = 2 { didSet { updateUI() } }
    
    // 文字/序号相关
    var showTextOptions = false
    var fontSize: CGFloat = 16 { didSet { updateUI() } }
    var fontName: String = "System" { didSet { updateUI() } }

    // 样式显示
    var showStyleOptions = false
    var styleIndex: Int = 0
    
    private var stackView: NSStackView!
    private var colorButton: NSButton!
    private var widthSlider: NSSlider!
    private var styleSegmented: NSSegmentedControl!
    
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
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.98).cgColor
        layer?.cornerRadius = 10
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.1
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 10
        
        if #available(macOS 10.14, *) {
            self.appearance = NSAppearance(named: .vibrantLight)
        }
        
        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 14
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            self.heightAnchor.constraint(equalToConstant: 42)
        ])
        
        rebuild()
    }
    
    func rebuild() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // 1. 返回按钮
        let backBtn = createIconButton(icon: "chevron.left", action: #selector(backClicked))
        backBtn.contentTintColor = NSColor.secondaryLabelColor
        stackView.addArrangedSubview(backBtn)
        
        // 2. 颜色选择按钮 (圆角色块)
        colorButton = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        colorButton.title = ""
        colorButton.bezelStyle = .recessed
        colorButton.isBordered = false
        colorButton.wantsLayer = true
        colorButton.layer?.backgroundColor = color.cgColor
        colorButton.layer?.cornerRadius = 6
        colorButton.target = self
        colorButton.action = #selector(showColorPopover(_:))
        colorButton.translatesAutoresizingMaskIntoConstraints = false
        colorButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        colorButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stackView.addArrangedSubview(colorButton)
        
        // 3. 梯形滑动条
        let sliderContainer = NSView()
        sliderContainer.translatesAutoresizingMaskIntoConstraints = false
        sliderContainer.widthAnchor.constraint(equalToConstant: 100).isActive = true
        sliderContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true
        
        let wedgeView = TaperedWedgeView(frame: NSRect(x: 0, y: 5, width: 100, height: 10))
        sliderContainer.addSubview(wedgeView)
        
        widthSlider = NSSlider(value: Double(lineWidth), minValue: 1, maxValue: 15, target: self, action: #selector(widthChanged(_:)))
        widthSlider.controlSize = .small
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        sliderContainer.addSubview(widthSlider)
        
        NSLayoutConstraint.activate([
            widthSlider.leadingAnchor.constraint(equalTo: sliderContainer.leadingAnchor),
            widthSlider.trailingAnchor.constraint(equalTo: sliderContainer.trailingAnchor),
            widthSlider.centerYAnchor.constraint(equalTo: sliderContainer.centerYAnchor)
        ])
        stackView.addArrangedSubview(sliderContainer)
        
        // 4. 样式选项 (0:圆角 1:流线/直角 2:遮罩 3:实心)
        if showStyleOptions {
            let config = NSSegmentedControl(labels: ["", "", "", ""], trackingMode: .selectOne, target: self, action: #selector(styleChanged(_:)))
            config.segmentStyle = .capsule
            config.setImage(NSImage(systemSymbolName: "square", accessibilityDescription: nil), forSegment: 0) // 圆角
            config.setImage(NSImage(systemSymbolName: "scribble", accessibilityDescription: nil), forSegment: 1) // 流线/直角
            config.setImage(NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: nil), forSegment: 2) // 遮罩
            config.setImage(NSImage(systemSymbolName: "square.fill", accessibilityDescription: nil), forSegment: 3) // 实心
            config.selectedSegment = styleIndex
            config.controlSize = .small
            styleSegmented = config
            stackView.addArrangedSubview(config)
        }
        
        // 5. 文字/序号 大小选项
        if showTextOptions {
            stackView.addArrangedSubview(createDivider())
            
            let sizeLabel = NSTextField(labelWithString: "\(Int(fontSize))pt")
            sizeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
            stackView.addArrangedSubview(sizeLabel)
            
            let stepper = NSStepper()
            stepper.minValue = 10
            stepper.maxValue = 100
            stepper.doubleValue = Double(fontSize)
            stepper.target = self
            stepper.action = #selector(fontSizeChanged(_:))
            stepper.controlSize = .small
            stackView.addArrangedSubview(stepper)
        }
    }
    
    private func createIconButton(icon: String, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return btn
    }

    private func createDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return v
    }
    
    private func updateUI() {
        colorButton?.layer?.backgroundColor = color.cgColor
        widthSlider?.doubleValue = Double(lineWidth)
        styleSegmented?.selectedSegment = styleIndex
    }
    
    @objc private func backClicked() {
        delegate?.didRequestCloseOverlay()
    }
    
    @objc private func showColorPopover(_ sender: NSButton) {
        let controller = ColorPickerViewController()
        controller.selectedColor = color
        controller.onColorSelected = { [weak self] newColor in
            self?.color = newColor
            self?.delegate?.propertyDidChange(color: newColor, lineWidth: nil, isFilled: nil, style: nil, fontName: nil, fontSize: nil)
        }
        
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    
    @objc private func widthChanged(_ sender: NSSlider) {
        lineWidth = CGFloat(sender.doubleValue)
        delegate?.propertyDidChange(color: nil, lineWidth: lineWidth, isFilled: nil, style: nil, fontName: nil, fontSize: nil)
    }
    
    @objc private func styleChanged(_ sender: NSSegmentedControl) {
        styleIndex = sender.selectedSegment
        delegate?.propertyDidChange(color: nil, lineWidth: nil, isFilled: (styleIndex == 3), style: styleIndex, fontName: nil, fontSize: nil)
    }

    @objc private func fontSizeChanged(_ sender: NSStepper) {
        fontSize = CGFloat(sender.doubleValue)
        delegate?.propertyDidChange(color: nil, lineWidth: nil, isFilled: nil, style: nil, fontName: nil, fontSize: fontSize)
    }
}

// MARK: - 高集成度颜色选择器

private var ColorKey: UInt8 = 0

class ColorPickerViewController: NSViewController, NSTextFieldDelegate {
    var selectedColor: NSColor = .systemRed
    var onColorSelected: ((NSColor) -> Void)?
    
    private var hexField: NSTextField!
    private var previewBox: NSView!
    private var hueRibbon: HueGradientView!
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 185))
        
        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        rootStack.alignment = .centerX
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        
        // 1. 预设颜色网格 (4x2)
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 10
        grid.distribution = .fillEqually
        
        let colors: [[NSColor]] = [
            [.systemRed, .systemPurple, .systemYellow, .systemPink],
            [.systemGreen, .systemBlue, .systemGray, .white]
        ]
        
        for rowColors in colors {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            for c in rowColors {
                row.addArrangedSubview(createColorBtn(color: c))
            }
            grid.addArrangedSubview(row)
        }
        rootStack.addArrangedSubview(grid)
        
        rootStack.addArrangedSubview(createDivider())
        
        // 2. 一体化 Hue 颜色条
        hueRibbon = HueGradientView(frame: .zero)
        hueRibbon.translatesAutoresizingMaskIntoConstraints = false
        hueRibbon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        hueRibbon.widthAnchor.constraint(equalToConstant: 172).isActive = true
        
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if let rgbColor = selectedColor.usingColorSpace(.deviceRGB) {
            rgbColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        }
        hueRibbon.currentHue = h
        
        hueRibbon.onHueChanged = { [weak self] h in
            self?.applyHue(h)
        }
        rootStack.addArrangedSubview(hueRibbon)
        
        // 3. HEX 输入和吸管
        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 10
        bottomRow.alignment = .centerY
        
        hexField = NSTextField(string: selectedColor.hexString)
        hexField.controlSize = .small
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.delegate = self
        hexField.isBezeled = true
        hexField.bezelStyle = .roundedBezel
        hexField.translatesAutoresizingMaskIntoConstraints = false
        hexField.widthAnchor.constraint(equalToConstant: 85).isActive = true
        bottomRow.addArrangedSubview(hexField)
        
        let eyedropperBtn = NSButton(image: NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)!, target: self, action: #selector(startEyedropper))
        eyedropperBtn.bezelStyle = .recessed
        eyedropperBtn.isBordered = false
        eyedropperBtn.controlSize = .small
        bottomRow.addArrangedSubview(eyedropperBtn)
        
        previewBox = NSView()
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = selectedColor.cgColor
        previewBox.layer?.cornerRadius = 6
        previewBox.translatesAutoresizingMaskIntoConstraints = false
        previewBox.widthAnchor.constraint(equalToConstant: 28).isActive = true
        previewBox.heightAnchor.constraint(equalToConstant: 28).isActive = true
        bottomRow.addArrangedSubview(previewBox)
        
        rootStack.addArrangedSubview(bottomRow)
        
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        self.view = view
    }
    
    private func createColorBtn(color: NSColor) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        btn.title = ""
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = color.cgColor
        btn.layer?.cornerRadius = 8
        if color.hexString == selectedColor.hexString {
            btn.layer?.borderWidth = 2.5
            btn.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
        btn.target = self
        btn.action = #selector(colorClicked(_:))
        objc_setAssociatedObject(btn, &ColorKey, color, .OBJC_ASSOCIATION_RETAIN)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 32).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return btn
    }
    
    private func createDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        v.widthAnchor.constraint(equalToConstant: 172).isActive = true
        return v
    }
    
    @objc private func colorClicked(_ sender: NSButton) {
        if let color = objc_getAssociatedObject(sender, &ColorKey) as? NSColor {
            updateSelection(color)
            onColorSelected?(color)
            dismiss(nil)
        }
    }

    private func applyHue(_ h: CGFloat) {
        let newColor = NSColor(hue: h, saturation: 0.9, brightness: 0.9, alpha: 1.0)
        updateSelection(newColor)
        onColorSelected?(newColor)
    }
    
    func controlTextDidChange(_ obj: Notification) {
        let hex = hexField.stringValue
        if let color = NSColor(hex: hex) {
            updateSelection(color)
            onColorSelected?(color)
        }
    }
    
    private func updateSelection(_ color: NSColor) {
        selectedColor = color
        previewBox.layer?.backgroundColor = color.cgColor
        hexField.stringValue = color.hexString
        
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if let rgbColor = color.usingColorSpace(.deviceRGB) {
            rgbColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            hueRibbon.currentHue = h
        }
    }
    
    @objc private func startEyedropper() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] color in
            if let color = color {
                DispatchQueue.main.async {
                    self?.updateSelection(color)
                    self?.onColorSelected?(color)
                    self?.dismiss(nil)
                }
            }
        }
    }
}

/// 一体化交互式色相条 (复刻高级取色器)
class HueGradientView: NSView {
    var onHueChanged: ((CGFloat) -> Void)?
    
    var currentHue: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // 1. 绘制背景彩虹
        let gradient = NSGradient(colors: (0...36).map { 
            NSColor(hue: CGFloat($0) / 36.0, saturation: 1, brightness: 1, alpha: 1)
        })
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        gradient?.draw(in: bgPath, angle: 0)
        
        // 2. 绘制极简圆形游标
        let cursorX = currentHue * bounds.width
        let cursorRect = NSRect(x: cursorX - 4, y: -2, width: 8, height: bounds.height + 4)
        
        NSGraphicsContext.saveGraphicsState()
        let ringPath = NSBezierPath(ovalIn: NSRect(x: cursorX - 6, y: bounds.midY - 6, width: 12, height: 12))
        NSColor.white.setStroke()
        ringPath.lineWidth = 2.5
        ringPath.stroke()
        
        // 加一点点阴影让白色圆环在亮色区也能看清
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        ringPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    
    override func mouseDown(with event: NSEvent) {
        handleMouse(event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        handleMouse(event)
    }
    
    private func handleMouse(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let percent = max(0, min(1, point.x / bounds.width))
        currentHue = percent
        onHueChanged?(percent)
    }
}

/// 绘制背景梯形以模拟线宽指示
class TaperedWedgeView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.quaternaryLabelColor.cgColor)
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: bounds.midY - 1))
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.midY - 4))
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.midY + 4))
        path.addLine(to: CGPoint(x: 0, y: bounds.midY + 1))
        path.closeSubpath()
        
        context.addPath(path)
        context.fillPath()
    }
}
