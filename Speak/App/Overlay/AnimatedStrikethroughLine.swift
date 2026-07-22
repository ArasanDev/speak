import SwiftUI

/// An animatable shape that draws a horizontal strikethrough line from left to right.
struct AnimatedStrikethroughLine: Shape {
    var progress: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startPoint = CGPoint(x: rect.minX, y: rect.midY)
        let endPoint = CGPoint(x: rect.minX + rect.width * progress, y: rect.midY)

        path.move(to: startPoint)
        path.addLine(to: endPoint)

        return path
    }
}
