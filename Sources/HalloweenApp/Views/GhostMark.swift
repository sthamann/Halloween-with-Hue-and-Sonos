import SwiftUI

/// Haunt's own vector mark, also used by the application icon generator.
struct GhostMark: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            var ghost = Path()
            ghost.move(to: p(0.18, 0.91)); ghost.addLine(to: p(0.18, 0.40))
            ghost.addCurve(to: p(0.82, 0.40), control1: p(0.18, -0.06), control2: p(0.82, -0.06))
            ghost.addLine(to: p(0.82, 0.91))
            for (x,y) in [(0.69,0.81),(0.59,0.96),(0.48,0.81),(0.37,0.96),(0.27,0.81)] { ghost.addLine(to: p(x,y)) }
            ghost.closeSubpath()
            context.fill(ghost, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.65, green: 0.58, blue: 0.9)]), startPoint: p(0.3,0), endPoint: p(0.7,1)))
            var eyes = Path()
            eyes.move(to: p(0.30,0.37)); eyes.addLine(to: p(0.45,0.43)); eyes.addLine(to: p(0.41,0.55)); eyes.addLine(to: p(0.30,0.51)); eyes.closeSubpath()
            eyes.move(to: p(0.70,0.37)); eyes.addLine(to: p(0.55,0.43)); eyes.addLine(to: p(0.59,0.55)); eyes.addLine(to: p(0.70,0.51)); eyes.closeSubpath()
            context.fill(eyes, with: .color(.orange))
            context.fill(Path(ellipseIn: CGRect(x: w*0.44, y: h*0.60, width: w*0.12, height: h*0.17)), with: .color(Color(red: 0.13, green: 0.06, blue: 0.20)))
        }.accessibilityLabel("Haunt")
    }
}
