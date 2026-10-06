import Foundation
import UIKit
import Display

// Transparent line icons for the WewPagram menu (no coloured tile behind them),
// in the style of the ghost glyph.
enum WewGlyph {
    case ghost, trash, person, star, drop, cube, globe, chart, phone, gift
}

func wewGlyph(_ glyph: WewGlyph) -> UIImage? {
    let side: CGFloat = 30.0
    let color = UIColor(rgb: 0x8E7BFF)
    return generateImage(CGSize(width: side, height: side), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(1.9)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let w = size.width
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: x * w, y: y * w)
        }
        func stroke(_ path: UIBezierPath) {
            context.addPath(path.cgPath)
            context.strokePath()
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            context.fillEllipse(in: CGRect(x: x * w - r * w, y: y * w - r * w, width: 2.0 * r * w, height: 2.0 * r * w))
        }
        func lines(_ points: [CGPoint]) {
            let path = UIBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            stroke(path)
        }

        switch glyph {
        case .ghost:
            let path = UIBezierPath()
            path.move(to: p(0.2, 0.84))
            path.addLine(to: p(0.2, 0.46))
            path.addArc(withCenter: p(0.5, 0.46), radius: 0.3 * w, startAngle: .pi, endAngle: 2.0 * .pi, clockwise: true)
            path.addLine(to: p(0.8, 0.84))
            path.addLine(to: p(0.65, 0.72))
            path.addLine(to: p(0.5, 0.84))
            path.addLine(to: p(0.35, 0.72))
            path.addLine(to: p(0.2, 0.84))
            stroke(path)
            dot(0.4, 0.45, 0.045)
            dot(0.6, 0.45, 0.045)
        case .trash:
            lines([p(0.18, 0.27), p(0.82, 0.27)])
            lines([p(0.4, 0.27), p(0.4, 0.17), p(0.6, 0.17), p(0.6, 0.27)])
            lines([p(0.26, 0.27), p(0.31, 0.85), p(0.69, 0.85), p(0.74, 0.27)])
            lines([p(0.45, 0.42), p(0.45, 0.7)])
            lines([p(0.55, 0.42), p(0.55, 0.7)])
        case .person:
            context.strokeEllipse(in: CGRect(x: 0.35 * w, y: 0.17 * w, width: 0.3 * w, height: 0.3 * w))
            let path = UIBezierPath()
            path.addArc(withCenter: p(0.5, 0.86), radius: 0.3 * w, startAngle: .pi, endAngle: 2.0 * .pi, clockwise: true)
            stroke(path)
        case .star:
            let path = UIBezierPath()
            for i in 0 ..< 10 {
                let radius: CGFloat = (i % 2 == 0) ? 0.38 : 0.16
                let angle = -CGFloat.pi / 2.0 + CGFloat(i) * CGFloat.pi / 5.0
                let point = CGPoint(x: (0.5 + radius * cos(angle)) * w, y: (0.54 + radius * sin(angle)) * w)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.close()
            stroke(path)
        case .drop:
            let path = UIBezierPath()
            path.move(to: p(0.5, 0.12))
            path.addQuadCurve(to: p(0.24, 0.6), controlPoint: p(0.3, 0.36))
            path.addArc(withCenter: p(0.5, 0.6), radius: 0.26 * w, startAngle: .pi, endAngle: 0.0, clockwise: false)
            path.addQuadCurve(to: p(0.5, 0.12), controlPoint: p(0.7, 0.36))
            stroke(path)
        case .cube:
            let path = UIBezierPath()
            path.move(to: p(0.5, 0.12))
            path.addLine(to: p(0.82, 0.3))
            path.addLine(to: p(0.82, 0.7))
            path.addLine(to: p(0.5, 0.88))
            path.addLine(to: p(0.18, 0.7))
            path.addLine(to: p(0.18, 0.3))
            path.close()
            stroke(path)
            lines([p(0.18, 0.3), p(0.5, 0.5), p(0.82, 0.3)])
            lines([p(0.5, 0.5), p(0.5, 0.88)])
        case .globe:
            context.strokeEllipse(in: CGRect(x: 0.16 * w, y: 0.16 * w, width: 0.68 * w, height: 0.68 * w))
            context.strokeEllipse(in: CGRect(x: 0.36 * w, y: 0.16 * w, width: 0.28 * w, height: 0.68 * w))
            lines([p(0.16, 0.5), p(0.84, 0.5)])
        case .chart:
            lines([p(0.22, 0.84), p(0.22, 0.56)])
            lines([p(0.5, 0.84), p(0.5, 0.18)])
            lines([p(0.78, 0.84), p(0.78, 0.4)])
        case .phone:
            let path = UIBezierPath(roundedRect: CGRect(x: 0.3 * w, y: 0.1 * w, width: 0.4 * w, height: 0.8 * w), cornerRadius: 0.08 * w)
            stroke(path)
            lines([p(0.44, 0.78), p(0.56, 0.78)])
        case .gift:
            let path = UIBezierPath(roundedRect: CGRect(x: 0.18 * w, y: 0.4 * w, width: 0.64 * w, height: 0.44 * w), cornerRadius: 0.05 * w)
            stroke(path)
            stroke(UIBezierPath(roundedRect: CGRect(x: 0.14 * w, y: 0.28 * w, width: 0.72 * w, height: 0.12 * w), cornerRadius: 0.04 * w))
            lines([p(0.5, 0.28), p(0.5, 0.84)])
            let bow = UIBezierPath()
            bow.move(to: p(0.5, 0.28))
            bow.addQuadCurve(to: p(0.34, 0.16), controlPoint: p(0.4, 0.14))
            bow.move(to: p(0.5, 0.28))
            bow.addQuadCurve(to: p(0.66, 0.16), controlPoint: p(0.6, 0.14))
            stroke(bow)
        }
    })
}
