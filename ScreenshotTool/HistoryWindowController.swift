//
//  HistoryWindowController.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

class HistoryWindowController: NSWindowController {

    private static var current: HistoryWindowController?

    private var tableView: HoverTableView!
    private var countLabel: NSTextField!
    private var previewPanel: NSPanel?
    private var previewImageView: NSImageView?
    private var hoveredRow: Int = -1

    static func show() {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = HistoryWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        current = controller
    }

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "截图历史"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 460, height: 320)

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        hidePreview()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let topBar = NSView(frame: CGRect(x: 0, y: contentView.bounds.height - 40, width: contentView.bounds.width, height: 40))
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        topBar.autoresizingMask = [.width, .minYMargin]

        countLabel = NSTextField(labelWithString: "")
        countLabel.frame = CGRect(x: 12, y: 10, width: 220, height: 20)
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        topBar.addSubview(countLabel)

        let clearButton = NSButton(title: "清空全部", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded
        clearButton.frame = CGRect(x: topBar.bounds.width - 92, y: 6, width: 80, height: 28)
        clearButton.autoresizingMask = [.minXMargin]
        topBar.addSubview(clearButton)

        contentView.addSubview(topBar)

        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - 40))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let table = HoverTableView(frame: scrollView.bounds)
        table.headerView = nil
        table.rowHeight = 42
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.allowsEmptySelection = true
        table.delegate = self
        table.dataSource = self
        table.hoverHandler = { [weak self] row, windowPoint in
            self?.handleHover(row: row, windowPoint: windowPoint)
        }

        let column = NSTableColumn(identifier: .init("HistoryColumn"))
        column.width = scrollView.bounds.width
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        scrollView.documentView = table
        contentView.addSubview(scrollView)
        tableView = table

        updateCountLabel()
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.messageText = "确认清空所有截图历史？"
        alert.informativeText = "此操作不可撤销"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            HistoryManager.shared.clearAll()
            tableView.reloadData()
            updateCountLabel()
            hidePreview()
        }
    }

    private func updateCountLabel() {
        countLabel.stringValue = "\(HistoryManager.shared.items.count) 张截图"
    }

    private func handleHover(row: Int, windowPoint: CGPoint) {
        guard row >= 0, row < HistoryManager.shared.items.count else {
            hoveredRow = -1
            hidePreview()
            return
        }
        if hoveredRow == row { return }

        hoveredRow = row
        let entry = HistoryManager.shared.items[row]
        guard let image = HistoryManager.shared.getImage(for: entry) else {
            hidePreview()
            return
        }
        let screenPoint = window?.convertPoint(toScreen: windowPoint) ?? windowPoint
        showPreview(image: image, near: screenPoint, title: entry.displayName)
    }

    private func showPreview(image: NSImage, near screenPoint: CGPoint, title: String) {
        let panel = previewPanel ?? createPreviewPanel()
        previewPanel = panel

        let maxPreview = NSSize(width: 360, height: 240)
        let scale = min(maxPreview.width / image.size.width, maxPreview.height / image.size.height, 1.0)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        let contentSize = NSSize(width: max(220, size.width + 20), height: size.height + 44)
        panel.setContentSize(contentSize)
        panel.setFrameTopLeftPoint(CGPoint(x: screenPoint.x + 18, y: screenPoint.y - 8))

        if let imageView = previewImageView {
            imageView.frame = CGRect(
                x: (contentSize.width - size.width) / 2,
                y: 14,
                width: size.width,
                height: size.height
            )
            imageView.image = image
        }
        if let label = panel.contentView?.viewWithTag(7001) as? NSTextField {
            label.stringValue = title
            label.frame = CGRect(x: 10, y: contentSize.height - 24, width: contentSize.width - 20, height: 16)
        }

        panel.orderFront(nil)
    }

    private func hidePreview() {
        previewPanel?.orderOut(nil)
    }

    private func createPreviewPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 280, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let label = NSTextField(labelWithString: "")
        label.tag = 7001
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        container.addSubview(label)

        let imageView = NSImageView(frame: CGRect(x: 10, y: 14, width: 260, height: 170))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)
        previewImageView = imageView

        panel.contentView = container
        return panel
    }
}

extension HistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        HistoryManager.shared.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("HistoryRow")
        let view = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryRowView)
            ?? HistoryRowView()
        view.identifier = id

        let entry = HistoryManager.shared.items[row]
        view.configure(with: entry)
        view.deleteHandler = { [weak self] in
            HistoryManager.shared.delete(item: entry)
            self?.tableView.reloadData()
            self?.updateCountLabel()
            self?.hidePreview()
        }
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < HistoryManager.shared.items.count else { return }
        let entry = HistoryManager.shared.items[row]
        if let image = HistoryManager.shared.getImage(for: entry) {
            EditorWindowController.show(with: image)
        }
    }
}

final class HistoryRowView: NSTableCellView {
    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    var deleteHandler: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        thumbnailView.frame = CGRect(x: 10, y: 5, width: 52, height: 32)
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 4
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.borderColor = NSColor.separatorColor.cgColor
        thumbnailView.layer?.borderWidth = 1
        addSubview(thumbnailView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.frame = CGRect(x: 72, y: 20, width: 340, height: 18)
        addSubview(titleLabel)

        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.frame = CGRect(x: 72, y: 4, width: 360, height: 15)
        addSubview(sizeLabel)

        deleteButton.frame = CGRect(x: 0, y: 10, width: 24, height: 24)
        deleteButton.autoresizingMask = [.minXMargin]
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        deleteButton.contentTintColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        addSubview(deleteButton)
    }

    override func layout() {
        super.layout()
        deleteButton.frame.origin.x = bounds.width - 34
    }

    func configure(with entry: HistoryManager.HistoryItem) {
        titleLabel.stringValue = entry.displayName
        sizeLabel.stringValue = "\(entry.width) × \(entry.height) · \(URL(fileURLWithPath: entry.filePath).lastPathComponent)"
        thumbnailView.image = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let image = HistoryManager.shared.getImage(for: entry)
            DispatchQueue.main.async { [weak self] in
                self?.thumbnailView.image = image
            }
        }
    }

    @objc private func deleteClicked() {
        deleteHandler?()
    }
}

final class HoverTableView: NSTableView {
    var hoverHandler: ((Int, CGPoint) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        hoverHandler?(row, event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        hoverHandler?(-1, .zero)
    }
}
