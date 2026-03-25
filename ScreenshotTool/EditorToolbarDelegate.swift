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
    func ocrAction()
    func pinAction()
}
