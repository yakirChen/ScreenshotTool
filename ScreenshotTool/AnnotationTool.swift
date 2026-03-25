//
//  AnnotationTool.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Cocoa

enum AnnotationTool: String, CaseIterable {
    case select = "选择"
    case arrow = "箭头"
    case rectangle = "矩形"
    case ellipse = "椭圆"
    case line = "直线"
    case text = "文字"
    case highlight = "高亮"
    case blur = "模糊"
    case number = "编号"
    case pen = "画笔"
    case measure = "测量"
    case ocr = "文字识别"

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .blur: return "drop.halffull"
        case .number: return "1.circle.fill"
        case .pen: return "pencil.tip"
        case .measure: return "ruler"
        case .ocr: return "text.viewfinder"
        }
    }
}
