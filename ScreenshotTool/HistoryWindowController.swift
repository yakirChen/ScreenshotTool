//
//  HistoryWindowController.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

class HistoryWindowController: NSWindowController {

    private static var current: HistoryWindowController?

    private var collectionView: NSCollectionView!

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
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "截图历史"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 400, height: 300)

        super.init(window: window)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 顶部工具栏
        let topBar = NSView(frame: CGRect(x: 0, y: 462, width: 600, height: 38))
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1).cgColor
        topBar.autoresizingMask = [.width, .minYMargin]

        let clearButton = NSButton(title: "清空全部", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .toolbar
        clearButton.frame = CGRect(x: 500, y: 5, width: 80, height: 28)
        clearButton.autoresizingMask = [.minXMargin]
        topBar.addSubview(clearButton)

        let countLabel = NSTextField(labelWithString: "\(HistoryManager.shared.items.count) 张截图")
        countLabel.frame = CGRect(x: 12, y: 8, width: 200, height: 20)
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.tag = 100
        topBar.addSubview(countLabel)

        contentView.addSubview(topBar)

        // ScrollView + CollectionView
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 600, height: 462))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 180, height: 140)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColors = [.controlBackgroundColor]
        collectionView.isSelectable = true
        collectionView.register(
            HistoryCollectionViewItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("HistoryItem"))

        scrollView.documentView = collectionView
        contentView.addSubview(scrollView)
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
            collectionView.reloadData()
            updateCountLabel()
        }
    }

    private func updateCountLabel() {
        if let topBar = window?.contentView?.subviews.last,
           let label = topBar.viewWithTag(100) as? NSTextField {
            label.stringValue = "\(HistoryManager.shared.items.count) 张截图"
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension HistoryWindowController: NSCollectionViewDataSource {

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
    -> Int {
        return HistoryManager.shared.items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier("HistoryItem"), for: indexPath)

        guard let historyItem = item as? HistoryCollectionViewItem else { return item }

        let historyEntry = HistoryManager.shared.items[indexPath.item]
        historyItem.configure(with: historyEntry)

        return historyItem
    }
}

// MARK: - NSCollectionViewDelegate

extension HistoryWindowController: NSCollectionViewDelegate {

    func collectionView(
        _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard let indexPath = indexPaths.first else { return }
        let entry = HistoryManager.shared.items[indexPath.item]

        if let image = HistoryManager.shared.getImage(for: entry) {
            EditorWindowController.show(with: image)
        }
    }
}

// MARK: - Collection View Item

class HistoryCollectionViewItem: NSCollectionViewItem {

    private var thumbnailView: NSImageView!
    private var label: NSTextField!
    private var historyEntry: HistoryManager.HistoryItem?

    override func loadView() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 180, height: 140))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 6
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        thumbnailView = NSImageView(frame: CGRect(x: 5, y: 25, width: 170, height: 110))
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 4
        container.addSubview(thumbnailView)

        label = NSTextField(labelWithString: "")
        label.frame = CGRect(x: 5, y: 3, width: 130, height: 18)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)

        // 删除按钮
        let deleteButton = NSButton(frame: CGRect(x: 155, y: 2, width: 20, height: 20))
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        deleteButton.contentTintColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteItem)
        container.addSubview(deleteButton)

        self.view = container
    }

    func configure(with entry: HistoryManager.HistoryItem) {
        self.historyEntry = entry
        label.stringValue = entry.displayName

        // 异步加载缩略图
        DispatchQueue.global(qos: .userInitiated).async {
            let image = HistoryManager.shared.getImage(for: entry)
            DispatchQueue.main.async {
                self.thumbnailView.image = image
            }
        }
    }

    @objc private func deleteItem() {
        guard let entry = historyEntry else { return }
        HistoryManager.shared.delete(item: entry)

        // 刷新 collection view
        if let collectionView = self.collectionView {
            collectionView.reloadData()
        }
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderColor =
                isSelected
                ? NSColor.systemBlue.cgColor
                : NSColor.separatorColor.cgColor
            view.layer?.borderWidth = isSelected ? 2 : 1
        }
    }
}
