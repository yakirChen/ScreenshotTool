//
//  HistoryListViewController.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/4/30.
//

import Cocoa

/// 历史记录列表视图控制器 - 列表布局 + 悬浮预览
class HistoryListViewController: NSViewController {

  private var tableView: NSTableView!
  private var scrollView: NSScrollView!
  private var previewWindow: NSWindow?
  private var previewImageView: NSImageView?

  // 悬浮预览延迟计时器（避免快速移动时频繁闪烁）
  private var previewDelayTimer: Timer?
  private var currentHoverRow: Int = -1

  // 预览窗口最大尺寸
  private let maxPreviewSize = CGSize(width: 480, height: 360)
  private let minPreviewSize = CGSize(width: 160, height: 120)
  private let previewDelay: TimeInterval = 0.15  // 150ms 延迟

  override func loadView() {
    self.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    setupUI()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    loadHistoryData()
  }

  // MARK: - 公开方法

  func reloadData() {
    loadHistoryData()
  }

  @objc func clearAll() {
    let alert = NSAlert()
    alert.messageText = "确认清空所有截图历史？"
    alert.informativeText = "此操作不可撤销"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "清空")
    alert.addButton(withTitle: "取消")

    if alert.runModal() == .alertFirstButtonReturn {
      HistoryManager.shared.clearAll()
      loadHistoryData()
    }
  }

  // MARK: - UI 设置

  private func setupUI() {
    // 滚动视图
    scrollView = NSScrollView(frame: view.bounds)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    view.addSubview(scrollView)

    // 表格视图
    tableView = NSTableView()
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    tableView.rowHeight = 60
    tableView.intercellSpacing = NSSize(width: 0, height: 2)
    tableView.delegate = self
    tableView.dataSource = self
    tableView.doubleAction = #selector(handleDoubleClick)
    tableView.target = self
    tableView.headerView = nil  // 隐藏表头

    // 配置列
    setupColumns()

    scrollView.documentView = tableView

    // 注册通知监听历史数据变化
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(historyDidChange),
      name: .historyDidChange,
      object: nil
    )
  }

  private func setupColumns() {
    // 缩略图列 (固定宽度)
    let thumbnailColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Thumbnail"))
    thumbnailColumn.title = ""
    thumbnailColumn.width = 80
    thumbnailColumn.minWidth = 80
    thumbnailColumn.maxWidth = 80
    thumbnailColumn.resizingMask = .userResizingMask
    tableView.addTableColumn(thumbnailColumn)

    // 信息列 (自适应宽度)
    let infoColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Info"))
    infoColumn.title = "截图信息"
    infoColumn.width = 320
    infoColumn.resizingMask = [.autoresizingMask, .userResizingMask]
    tableView.addTableColumn(infoColumn)

    // 尺寸列 (固定宽度)
    let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
    sizeColumn.title = "尺寸"
    sizeColumn.width = 100
    sizeColumn.minWidth = 80
    sizeColumn.maxWidth = 120
    sizeColumn.resizingMask = .userResizingMask
    tableView.addTableColumn(sizeColumn)

    // 操作列 (删除按钮，固定宽度)
    let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Action"))
    actionColumn.title = ""
    actionColumn.width = 44
    actionColumn.minWidth = 44
    actionColumn.maxWidth = 44
    actionColumn.resizingMask = .userResizingMask
    tableView.addTableColumn(actionColumn)
  }

  // MARK: - 数据加载

  func loadHistoryData() {
    tableView.reloadData()
    updateWindowTitle()
  }

  @objc private func historyDidChange() {
    DispatchQueue.main.async {
      self.loadHistoryData()
    }
  }

  private func updateWindowTitle() {
    let count = HistoryManager.shared.items.count
    view.window?.title = "截图历史 (\(count) 张)"
  }

  // MARK: - 交互处理

  @objc private func handleDoubleClick() {
    let clickedRow = tableView.clickedRow
    guard clickedRow >= 0 && clickedRow < HistoryManager.shared.items.count else { return }

    let entry = HistoryManager.shared.items[clickedRow]
    if let image = HistoryManager.shared.getImage(for: entry) {
      EditorWindowController.show(with: image)
    }
  }

  // MARK: - 悬浮预览

  /// 显示悬浮预览窗口
  private func showPreview(for row: Int, at screenPoint: NSPoint) {
    guard row >= 0 && row < HistoryManager.shared.items.count else { return }

    let entry = HistoryManager.shared.items[row]
    guard let image = HistoryManager.shared.getImage(for: entry) else { return }

    // 每次重新创建窗口以适配图片尺寸
    createPreviewWindow(for: image.size)

    // 更新图片
    previewImageView?.image = image

    // 计算预览窗口位置（不遮挡当前行）
    let windowSize = previewWindow?.frame.size ?? maxPreviewSize
    let windowFrame = calculatePreviewFrame(
      hoverScreenPoint: screenPoint,
      previewSize: windowSize
    )
    previewWindow?.setFrame(windowFrame, display: true)
    previewWindow?.orderFront(nil)

    currentHoverRow = row
  }

  /// 隐藏预览窗口
  private func hidePreview() {
    previewDelayTimer?.invalidate()
    previewDelayTimer = nil
    previewWindow?.orderOut(nil)
    currentHoverRow = -1
  }

  /// 创建自适应预览窗口
  private func createPreviewWindow(for imageSize: CGSize) {
    // 清理旧引用，避免访问已释放内存
    previewImageView = nil

    // 关闭旧窗口（使用 orderOut 避免立即释放导致的竞争）
    previewWindow?.orderOut(nil)
    previewWindow = nil

    // 计算自适应尺寸（保持宽高比）
    let aspectRatio = imageSize.width / imageSize.height
    var previewWidth: CGFloat
    var previewHeight: CGFloat

    if aspectRatio >= 1 {
      // 宽图：以最大宽度为基准
      previewWidth = min(imageSize.width, maxPreviewSize.width)
      previewHeight = previewWidth / aspectRatio
      if previewHeight > maxPreviewSize.height {
        previewHeight = maxPreviewSize.height
        previewWidth = previewHeight * aspectRatio
      }
    } else {
      // 高图：以最大高度为基准
      previewHeight = min(imageSize.height, maxPreviewSize.height)
      previewWidth = previewHeight * aspectRatio
      if previewWidth > maxPreviewSize.width {
        previewWidth = maxPreviewSize.width
        previewHeight = previewWidth / aspectRatio
      }
    }

    // 确保不小于最小尺寸
    previewWidth = max(previewWidth, minPreviewSize.width)
    previewHeight = max(previewHeight, minPreviewSize.height)

    let finalSize = CGSize(width: previewWidth + 16, height: previewHeight + 16)

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: finalSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isOpaque = false
    window.hasShadow = true
    window.backgroundColor = .clear
    window.level = .popUpMenu
    window.ignoresMouseEvents = true

    // 内容视图 - 使用系统外观背景
    let contentView = NSVisualEffectView(frame: NSRect(origin: .zero, size: finalSize))
    contentView.material = .popover
    contentView.blendingMode = .behindWindow
    contentView.state = .active
    contentView.wantsLayer = true
    contentView.layer?.cornerRadius = 12
    contentView.layer?.borderWidth = 0.5
    contentView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

    // 图片视图
    let imageView = NSImageView(frame: NSRect(x: 8, y: 8, width: previewWidth, height: previewHeight))
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 4
    imageView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.05).cgColor
    contentView.addSubview(imageView)
    previewImageView = imageView

    window.contentView = contentView
    previewWindow = window
  }

  /// 计算预览窗口位置（智能避让）
  private func calculatePreviewFrame(hoverScreenPoint: NSPoint, previewSize: CGSize) -> NSRect {
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(hoverScreenPoint) })
          ?? NSScreen.main else {
      return NSRect(origin: hoverScreenPoint, size: previewSize)
    }

    let screenFrame = screen.visibleFrame
    let padding: CGFloat = 16

    // 默认显示在鼠标右侧
    var originX = hoverScreenPoint.x + padding
    var originY = hoverScreenPoint.y - previewSize.height / 2

    // 右侧超出屏幕则显示在左侧
    if originX + previewSize.width > screenFrame.maxX {
      originX = hoverScreenPoint.x - previewSize.width - padding
    }

    // 底部超出屏幕则向上调整
    if originY < screenFrame.minY {
      originY = screenFrame.minY + padding
    }

    // 顶部超出屏幕则向下调整
    if originY + previewSize.height > screenFrame.maxY {
      originY = screenFrame.maxY - previewSize.height - padding
    }

    return NSRect(x: originX, y: originY, width: previewSize.width, height: previewSize.height)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    hidePreview()
  }
}

// MARK: - NSTableViewDataSource

extension HistoryListViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return HistoryManager.shared.items.count
  }
}

// MARK: - NSTableViewDelegate

extension HistoryListViewController: NSTableViewDelegate {

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let column = tableColumn else { return nil }
    guard row >= 0 && row < HistoryManager.shared.items.count else { return nil }

    let entry = HistoryManager.shared.items[row]
    let cellIdentifier = NSUserInterfaceItemIdentifier("HistoryCell_\(column.identifier.rawValue)")

    // 复用或创建单元格
    if let existingCell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) {
      configureCell(existingCell, for: column, row: row, with: entry)
      return existingCell
    }

    let cell = createCell(for: column, identifier: cellIdentifier)
    configureCell(cell, for: column, row: row, with: entry)
    return cell
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard row >= 0 && row < HistoryManager.shared.items.count else { return nil }

    let rowView = HoverableTableRowView()
    rowView.onHover = { [weak self] isHovering, screenPoint in
      self?.handleRowHover(row: row, isHovering: isHovering, screenPoint: screenPoint)
    }
    return rowView
  }

  // MARK: - 单元格创建与配置

  private func createCell(for column: NSTableColumn, identifier: NSUserInterfaceItemIdentifier) -> NSView {
    switch column.identifier.rawValue {
    case "Thumbnail":
      let imageView = NSImageView(frame: NSRect(x: 8, y: 6, width: 64, height: 48))
      imageView.identifier = identifier
      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.wantsLayer = true
      imageView.layer?.cornerRadius = 4
      imageView.layer?.borderWidth = 0.5
      imageView.layer?.borderColor = NSColor.separatorColor.cgColor
      return imageView

    case "Info":
      let textField = NSTextField(labelWithString: "")
      textField.identifier = identifier
      textField.font = .systemFont(ofSize: 13)
      textField.textColor = .labelColor
      textField.lineBreakMode = .byTruncatingTail
      return textField

    case "Size":
      let textField = NSTextField(labelWithString: "")
      textField.identifier = identifier
      textField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
      textField.textColor = .secondaryLabelColor
      textField.alignment = .right
      return textField

    case "Action":
      // 创建容器视图
      let container = NSView(frame: NSRect(x: 0, y: 0, width: 44, height: 60))
      container.identifier = identifier

      // 删除按钮
      let deleteButton = NSButton(frame: NSRect(x: 8, y: 18, width: 24, height: 24))
      deleteButton.bezelStyle = .inline
      deleteButton.isBordered = false
      deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
      deleteButton.contentTintColor = .secondaryLabelColor
      deleteButton.target = self
      deleteButton.action = #selector(deleteButtonClicked(_:))
      deleteButton.tag = -1  // 将在配置时设置正确的行号
      container.addSubview(deleteButton)

      return container

    default:
      return NSTextField(labelWithString: "")
    }
  }

  private func configureCell(_ cell: NSView, for column: NSTableColumn, row: Int, with entry: HistoryManager.HistoryItem) {
    switch column.identifier.rawValue {
    case "Thumbnail":
      guard let imageView = cell as? NSImageView else { return }
      // 异步加载缩略图
      DispatchQueue.global(qos: .userInitiated).async {
        let image = HistoryManager.shared.getImage(for: entry)
        DispatchQueue.main.async {
          imageView.image = image
        }
      }

    case "Info":
      guard let textField = cell as? NSTextField else { return }
      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      textField.stringValue = "\(dateFormatter.string(from: entry.date))"

    case "Size":
      guard let textField = cell as? NSTextField else { return }
      textField.stringValue = "\(entry.width) × \(entry.height)"

    case "Action":
      // 更新删除按钮的 tag 为当前行号，用于识别点击的是哪一行
      if let container = cell as? NSView,
         let deleteButton = container.subviews.first as? NSButton {
        deleteButton.tag = row
      }

    default:
      break
    }
  }

  @objc private func deleteButtonClicked(_ sender: NSButton) {
    let row = sender.tag
    guard row >= 0 && row < HistoryManager.shared.items.count else { return }

    let entry = HistoryManager.shared.items[row]

    let alert = NSAlert()
    alert.messageText = "确认删除这张截图？"
    alert.informativeText = entry.displayName
    alert.alertStyle = .warning
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")

    if alert.runModal() == .alertFirstButtonReturn {
      HistoryManager.shared.delete(item: entry)
      loadHistoryData()
    }
  }

  // MARK: - 悬浮处理

  private func handleRowHover(row: Int, isHovering: Bool, screenPoint: NSPoint) {
    previewDelayTimer?.invalidate()

    if isHovering {
      // 延迟显示预览，避免快速滑动时频繁闪烁
      previewDelayTimer = Timer.scheduledTimer(withTimeInterval: previewDelay, repeats: false) { [weak self] _ in
        self?.showPreview(for: row, at: screenPoint)
      }
    } else {
      // 立即隐藏（如果是离开当前悬浮的行）
      if currentHoverRow == row {
        hidePreview()
      }
    }
  }

  // 右键菜单
  func tableView(_ tableView: NSTableView, menuForRows rows: IndexSet, clickedRow: Int) -> NSMenu? {
    guard clickedRow >= 0 else { return nil }

    let menu = NSMenu()

    let openItem = NSMenuItem(title: "在编辑器中打开", action: #selector(openSelectedItem), keyEquivalent: "")
    openItem.target = self
    menu.addItem(openItem)

    let copyItem = NSMenuItem(title: "复制到剪贴板", action: #selector(copySelectedItem), keyEquivalent: "")
    copyItem.target = self
    menu.addItem(copyItem)

    menu.addItem(NSMenuItem.separator())

    let showInFinderItem = NSMenuItem(title: "在 Finder 中显示", action: #selector(showInFinder), keyEquivalent: "")
    showInFinderItem.target = self
    menu.addItem(showInFinderItem)

    menu.addItem(NSMenuItem.separator())

    let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteSelectedItem), keyEquivalent: "")
    deleteItem.target = self
    menu.addItem(deleteItem)

    return menu
  }

  // MARK: - 右键菜单动作

  @objc private func openSelectedItem() {
    let row = tableView.clickedRow
    guard row >= 0 else { return }

    let entry = HistoryManager.shared.items[row]
    if let image = HistoryManager.shared.getImage(for: entry) {
      EditorWindowController.show(with: image)
    }
  }

  @objc private func copySelectedItem() {
    let row = tableView.clickedRow
    guard row >= 0 else { return }

    let entry = HistoryManager.shared.items[row]
    if let image = HistoryManager.shared.getImage(for: entry) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([image])
    }
  }

  @objc private func showInFinder() {
    let row = tableView.clickedRow
    guard row >= 0 else { return }

    let entry = HistoryManager.shared.items[row]
    NSWorkspace.shared.selectFile(entry.filePath, inFileViewerRootedAtPath: "")
  }

  @objc private func deleteSelectedItem() {
    let row = tableView.clickedRow
    guard row >= 0 else { return }

    let entry = HistoryManager.shared.items[row]

    let alert = NSAlert()
    alert.messageText = "确认删除这张截图？"
    alert.informativeText = entry.displayName
    alert.alertStyle = .warning
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")

    if alert.runModal() == .alertFirstButtonReturn {
      HistoryManager.shared.delete(item: entry)
      tableView.reloadData()
      updateWindowTitle()
    }
  }
}

// MARK: - 可检测悬浮的行视图

class HoverableTableRowView: NSTableRowView {
  var onHover: ((_ isHovering: Bool, _ screenPoint: NSPoint) -> Void)?

  private var trackingArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let trackingArea = trackingArea {
      removeTrackingArea(trackingArea)
    }

    let newTrackingArea = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .mouseMoved],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(newTrackingArea)
    trackingArea = newTrackingArea
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    // 转换为屏幕坐标
    let windowPoint = event.locationInWindow
    let screenPoint = convertToScreen(windowPoint)
    onHover?(true, screenPoint)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    let windowPoint = event.locationInWindow
    let screenPoint = convertToScreen(windowPoint)
    onHover?(false, screenPoint)
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    // 鼠标在行内移动时更新位置
    let windowPoint = event.locationInWindow
    let screenPoint = convertToScreen(windowPoint)
    onHover?(true, screenPoint)
  }

  private func convertToScreen(_ windowPoint: NSPoint) -> NSPoint {
    guard let window = self.window else { return windowPoint }
    let screenOrigin = window.convertPoint(toScreen: NSPoint(x: 0, y: 0))
    return NSPoint(
      x: screenOrigin.x + windowPoint.x,
      y: screenOrigin.y + windowPoint.y
    )
  }
}

// MARK: - 通知扩展

extension Notification.Name {
  static let historyDidChange = Notification.Name("HistoryDidChange")
}
