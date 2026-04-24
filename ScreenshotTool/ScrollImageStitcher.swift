// ScrollImageStitcher.swift

import Cocoa

class ScrollImageStitcher {

    private struct OverlapMatch {
        let overlapPx: Int
        let confidence: Double
    }
    
    /// 拼接多张图片
    static func stitch(images: [NSImage]) -> NSImage {
        guard images.count >= 2 else { return images.first ?? NSImage() }
        
        var result = images[0]
        
        for i in 1..<images.count {
            result = stitchPair(top: result, bottom: images[i])
        }
        
        return result
    }
    
    /// 拼接两张图片，自动检测重叠
    static func stitchPair(top: NSImage, bottom: NSImage) -> NSImage {
        guard let topBitmap = getBitmap(from: top),
              let bottomBitmap = getBitmap(from: bottom) else {
            return simpleStitch(top: top, bottom: bottom)
        }

        let match = findOverlap(topBitmap: topBitmap, bottomBitmap: bottomBitmap)
        let overlapPx = match.overlapPx

        // 像素转为 point
        let topScale = topBitmap.pixelsHigh > 0 ? top.size.height / CGFloat(topBitmap.pixelsHigh) : 1
        let overlapPt = CGFloat(overlapPx) * topScale

        // 低置信度时不裁掉重叠，避免误删内容
        if match.confidence < 0.88 {
            return simpleStitch(top: top, bottom: bottom)
        }

        return mergeVertically(top: top, bottom: bottom, overlapPoints: overlapPt)
    }
    
    /// 获取 NSBitmapImageRep
    private static func getBitmap(from image: NSImage) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
    
    // MARK: - 重叠检测（参考 ScrollSnap 的行级匹配）
    
    /// 从 top 图底部和 bottom 图顶部找重叠行数
    private static func findOverlap(topBitmap: NSBitmapImageRep, bottomBitmap: NSBitmapImageRep) -> OverlapMatch {
        let topW = topBitmap.pixelsWide
        let topH = topBitmap.pixelsHigh
        let botW = bottomBitmap.pixelsWide
        let botH = bottomBitmap.pixelsHigh

        guard topW == botW, topH > 10, botH > 10 else {
            return OverlapMatch(overlapPx: 0, confidence: 0)
        }
        
        // 预计算 bottom 图顶部每行的"指纹"（行哈希）
        let maxSearch = min(topH, botH) * 80 / 100
        // 允许更大滚动步长，避免快速滚动时找不到重叠
        let searchRange = min(1600, maxSearch)
        
        guard searchRange > 10 else {
            return OverlapMatch(overlapPx: 0, confidence: 0)
        }
        
        // 采样列
        let sampleCols = buildSampleColumns(width: topW, count: 20)
        guard !sampleCols.isEmpty else {
            return OverlapMatch(overlapPx: 0, confidence: 0)
        }
        
        // ✅ 参考 ScrollSnap：从大重叠到小重叠搜索
        // 找到 top 图最底下一行在 bottom 图顶部的匹配位置
        
        // 先获取 top 图底部一行的颜色指纹
        let topBottomRowColors = getRowColors(bitmap: topBitmap, row: topH - 1, cols: sampleCols)
        guard !topBottomRowColors.isEmpty else {
            return OverlapMatch(overlapPx: 0, confidence: 0)
        }
        
        // 在 bottom 图的前 searchRange 行中搜索匹配行
        var bestOverlap = 0
        var bestScore: Double = 0
        
        for bottomRow in 0..<searchRange {
            let bottomRowColors = getRowColors(bitmap: bottomBitmap, row: bottomRow, cols: sampleCols)
            
            let similarity = compareRowColors(topBottomRowColors, bottomRowColors)
            
            if similarity > 0.85 && similarity > bestScore {
                // 找到候选匹配，验证更多行
                let overlap = bottomRow + 1
                let fullScore = validateOverlap(
                    topBitmap: topBitmap,
                    bottomBitmap: bottomBitmap,
                    overlap: overlap,
                    sampleCols: sampleCols
                )
                
                if fullScore > 0.8 && fullScore > bestScore {
                    bestScore = fullScore
                    bestOverlap = overlap
                }
            }
        }
        
        // 小于 8px 的重叠通常不稳定，按无重叠处理
        if bestOverlap < 8 || bestScore < 0.75 {
            return OverlapMatch(overlapPx: 0, confidence: bestScore)
        }

        let clampedOverlap = min(bestOverlap, max(0, min(topH, botH) - 1))
        return OverlapMatch(overlapPx: clampedOverlap, confidence: bestScore)
    }
    
    /// 获取一行的颜色采样
    private static func getRowColors(bitmap: NSBitmapImageRep, row: Int, cols: [Int]) -> [(r: CGFloat, g: CGFloat, b: CGFloat)] {
        var colors: [(r: CGFloat, g: CGFloat, b: CGFloat)] = []
        
        for col in cols {
            guard let color = bitmap.colorAt(x: col, y: row)?.usingColorSpace(.sRGB) else { continue }
            colors.append((r: color.redComponent, g: color.greenComponent, b: color.blueComponent))
        }
        
        return colors
    }
    
    /// 比较两行颜色的相似度
    private static func compareRowColors(
        _ a: [(r: CGFloat, g: CGFloat, b: CGFloat)],
        _ b: [(r: CGFloat, g: CGFloat, b: CGFloat)]
    ) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        
        var matchCount = 0
        for i in 0..<count {
            let dr = abs(a[i].r - b[i].r)
            let dg = abs(a[i].g - b[i].g)
            let db = abs(a[i].b - b[i].b)
            
            if dr < 0.04 && dg < 0.04 && db < 0.04 {
                matchCount += 1
            }
        }
        
        return Double(matchCount) / Double(count)
    }
    
    /// 验证整个重叠区域的匹配度
    private static func validateOverlap(
        topBitmap: NSBitmapImageRep,
        bottomBitmap: NSBitmapImageRep,
        overlap: Int,
        sampleCols: [Int]
    ) -> Double {
        let topH = topBitmap.pixelsHigh
        
        // 检查多行
        let checkCount = min(overlap, 10)
        let rowStep = max(1, overlap / checkCount)
        
        var totalMatch = 0
        var totalCount = 0
        
        var row = 0
        while row < overlap {
            let topRow = topH - overlap + row
            let bottomRow = row
            
            let topColors = getRowColors(bitmap: topBitmap, row: topRow, cols: sampleCols)
            let bottomColors = getRowColors(bitmap: bottomBitmap, row: bottomRow, cols: sampleCols)
            
            let count = min(topColors.count, bottomColors.count)
            for i in 0..<count {
                let dr = abs(topColors[i].r - bottomColors[i].r)
                let dg = abs(topColors[i].g - bottomColors[i].g)
                let db = abs(topColors[i].b - bottomColors[i].b)
                
                totalCount += 1
                if dr < 0.04 && dg < 0.04 && db < 0.04 {
                    totalMatch += 1
                }
            }
            
            row += rowStep
        }
        
        return totalCount > 0 ? Double(totalMatch) / Double(totalCount) : 0
    }
    
    /// 构建采样列索引
    private static func buildSampleColumns(width: Int, count: Int) -> [Int] {
        let step = max(1, width / count)
        var cols: [Int] = []
        var x = step / 2
        while x < width {
            cols.append(x)
            x += step
        }
        return cols
    }
    
    // MARK: - 拼接
    
    /// 垂直拼接两张图
    private static func mergeVertically(top: NSImage, bottom: NSImage, overlapPoints: CGFloat) -> NSImage {
        let newWidth = max(top.size.width, bottom.size.width)
        let newHeight = top.size.height + bottom.size.height - overlapPoints
        
        guard newHeight > 0, newWidth > 0 else { return top }
        
        let result = NSImage(size: NSSize(width: newWidth, height: newHeight))
        result.lockFocus()
        
        // 底部图
        bottom.draw(
            in: CGRect(x: 0, y: 0, width: bottom.size.width, height: bottom.size.height),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        
        // 顶部图（画在上面，覆盖重叠区域）
        top.draw(
            in: CGRect(x: 0, y: newHeight - top.size.height, width: top.size.width, height: top.size.height),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        
        result.unlockFocus()
        return result
    }
    
    /// 简单拼接（无重叠检测）
    private static func simpleStitch(top: NSImage, bottom: NSImage) -> NSImage {
        let newWidth = max(top.size.width, bottom.size.width)
        let newHeight = top.size.height + bottom.size.height
        
        let result = NSImage(size: NSSize(width: newWidth, height: newHeight))
        result.lockFocus()
        
        bottom.draw(
            in: CGRect(x: 0, y: 0, width: bottom.size.width, height: bottom.size.height),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        top.draw(
            in: CGRect(x: 0, y: bottom.size.height, width: top.size.width, height: top.size.height),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        
        result.unlockFocus()
        return result
    }
}
