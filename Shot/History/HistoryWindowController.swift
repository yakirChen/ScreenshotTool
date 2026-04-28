//
//  HistoryWindowController.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

/// 截图历史窗口控制器 - 使用列表布局
class HistoryWindowController: NSWindowController {

  private static var current: HistoryWindowController?

  private var listViewController: HistoryListViewController!

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
    window.center()
    window.isReleasedWhenClosed = false
    window.minSize = CGSize(width: 480, height: 300)

    super.init(window: window)

    setupUI()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupUI() {
    guard let contentView = window?.contentView else { return }
    let contentHeight = contentView.bounds.height

    // 顶部工具栏
    let toolbar = NSView(frame: NSRect(x: 0, y: contentHeight - 40, width: contentView.bounds.width, height: 40))
    toolbar.wantsLayer = true
    toolbar.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1).cgColor
    toolbar.autoresizingMask = [.width, .minYMargin]
    contentView.addSubview(toolbar)

    // 清空全部按钮
    let clearButton = NSButton(title: "清空全部", target: self, action: #selector(clearAll))
    clearButton.bezelStyle = .toolbar
    clearButton.translatesAutoresizingMaskIntoConstraints = false
    toolbar.addSubview(clearButton)

    NSLayoutConstraint.activate([
      clearButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
      clearButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
      clearButton.widthAnchor.constraint(equalToConstant: 80),
      clearButton.heightAnchor.constraint(equalToConstant: 28),
    ])

    // 截图数量标签
    let countLabel = NSTextField(labelWithString: "\(HistoryManager.shared.items.count) 张截图")
    countLabel.font = .systemFont(ofSize: 12, weight: .medium)
    countLabel.textColor = .secondaryLabelColor
    countLabel.translatesAutoresizingMaskIntoConstraints = false
    countLabel.tag = 100
    toolbar.addSubview(countLabel)

    NSLayoutConstraint.activate([
      countLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
      countLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
    ])

    // 创建列表视图控制器
    listViewController = HistoryListViewController()
    listViewController.view.frame = NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentHeight - 40)
    listViewController.view.autoresizingMask = [.width, .height]

    contentView.addSubview(listViewController.view)

    // 设置窗口代理
    window?.delegate = self

    updateWindowTitle()
  }

  @objc private func clearAll() {
    listViewController.clearAll()
    updateCountLabel()
  }

  private func updateCountLabel() {
    if let toolbar = window?.contentView?.subviews.first,
       let label = toolbar.viewWithTag(100) as? NSTextField {
      label.stringValue = "\(HistoryManager.shared.items.count) 张截图"
    }
  }

  private func updateWindowTitle() {
    let count = HistoryManager.shared.items.count
    window?.title = "截图历史 (\(count) 张)"
  }

  override func close() {
    HistoryWindowController.current = nil
    super.close()
  }
}

// MARK: - NSWindowDelegate

extension HistoryWindowController: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    HistoryWindowController.current = nil
  }
}
