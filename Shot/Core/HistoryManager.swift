//
//  HistoryManager.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/25.
//

import Cocoa

class HistoryManager {

    static let shared = HistoryManager()

    struct HistoryItem: Codable {
        let id: String
        let date: Date
        let width: Int
        let height: Int
        let filePath: String

        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return "\(formatter.string(from: date)) - \(width)×\(height)"
        }
    }

    private(set) var items: [HistoryItem] = []
    private let maxItems = 50
    private let historyDirectory: URL
    private let indexFile: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        historyDirectory = appSupport.appendingPathComponent(
            "ScreenshotTool/History", isDirectory: true)
        indexFile = historyDirectory.appendingPathComponent("index.json")

        // 创建目录
        try? FileManager.default.createDirectory(
            at: historyDirectory, withIntermediateDirectories: true)

        // 加载历史
        loadIndex()
    }

    // MARK: - 保存截图到历史

    func save(image: NSImage) {
        let id = UUID().uuidString
        let fileName = "\(id).png"
        let filePath = historyDirectory.appendingPathComponent(fileName)

        // 保存图片
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else {
            return
        }

        do {
            try pngData.write(to: filePath)
        } catch {
            print("历史保存失败: \(error)")
            return
        }

        let item = HistoryItem(
            id: id,
            date: Date(),
            width: Int(image.size.width),
            height: Int(image.size.height),
            filePath: filePath.path
        )

        items.insert(item, at: 0)

        // 限制数量
        while items.count > maxItems {
            let removed = items.removeLast()
            try? FileManager.default.removeItem(atPath: removed.filePath)
        }

        saveIndex()
    }

    // MARK: - 获取历史图片

    func getImage(for item: HistoryItem) -> NSImage? {
        return NSImage(contentsOfFile: item.filePath)
    }

    // MARK: - 删除

    func delete(item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(atPath: item.filePath)
        saveIndex()
    }

    func clearAll() {
        for item in items {
            try? FileManager.default.removeItem(atPath: item.filePath)
        }
        items.removeAll()
        saveIndex()
    }

    // MARK: - 持久化

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFile) else { return }
        items = (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []

        // 清理不存在的文件
        items = items.filter { FileManager.default.fileExists(atPath: $0.filePath) }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexFile)
    }
}
