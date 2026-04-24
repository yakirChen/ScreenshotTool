import Cocoa

enum GeometryMapper {
    static func globalToLocal(_ point: CGPoint, in screen: NSScreen) -> CGPoint {
        CGPoint(x: point.x - screen.frame.origin.x, y: point.y - screen.frame.origin.y)
    }

    static func localToGlobal(_ point: CGPoint, in screen: NSScreen) -> CGPoint {
        CGPoint(x: point.x + screen.frame.origin.x, y: point.y + screen.frame.origin.y)
    }

    static func globalToLocal(_ rect: CGRect, in screen: NSScreen) -> CGRect {
        CGRect(
            x: rect.origin.x - screen.frame.origin.x,
            y: rect.origin.y - screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    static func localToGlobal(_ rect: CGRect, in screen: NSScreen) -> CGRect {
        CGRect(
            x: rect.origin.x + screen.frame.origin.x,
            y: rect.origin.y + screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitGlobalRect(fromCoreGraphicsRect rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
