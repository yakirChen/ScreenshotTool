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
  func fillModeDidChange(_ isFilled: Bool)  // 填充模式切换
  func zoomDidChange(_ level: CGFloat)  // 缩放级别变化
  func undoAction()
  func redoAction()
  func saveAction()
  func quickSaveAction()  // 快速保存
  func copyAction()
  func closeAction()
  func ocrAction()
  func pinAction()
}
