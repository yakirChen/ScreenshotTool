//
//  OCRManager.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa
import Vision

class OCRManager {

  static let shared = OCRManager()

  /// 识别图片中的文字
  func recognizeText(from image: NSImage, completion: @escaping (String) -> Void) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      completion("")
      return
    }

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        print("OCR 错误: \(error)")
        DispatchQueue.main.async { completion("") }
        return
      }

      guard let observations = request.results as? [VNRecognizedTextObservation] else {
        DispatchQueue.main.async { completion("") }
        return
      }

      let text =
        observations
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")

      DispatchQueue.main.async {
        completion(text)
      }
    }

    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        print("OCR 执行失败: \(error)")
        DispatchQueue.main.async { completion("") }
      }
    }
  }
}
