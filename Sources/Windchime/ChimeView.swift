import SwiftUI

struct ChimeView: View {
    @ObservedObject var engine: ChimeEngine

    let light = Color(red: 0.925, green: 0.784, blue: 0.475)
    let mid   = Color(red: 0.788, green: 0.612, blue: 0.263)
    let dark  = Color(red: 0.490, green: 0.361, blue: 0.118)
    let canopyC = Color(red: 0.36, green: 0.27, blue: 0.13)
    let stringC = Color(red: 0.24, green: 0.17, blue: 0.06).opacity(0.85)
    let accent = Color(red: 0.851, green: 0.678, blue: 0.322)

    // Y of the lowest point of the chime, so the control bar can sit just below.
    static func chimeBottomY(_ size: CGSize) -> CGFloat {
        let u = min(size.width / 190, size.height / 250)
        let ringPx = min(size.width * 0.24, 58 * u)
        let canR = ringPx + 8 * u
        let y0 = size.height * 0.085
        let maxLen = (58 + 105 * 0.8) * u    // longest string (max frac ≈ 0.8)
        let maxBR = 11 * u                   // bell radius at full scale
        return y0 + canR * 0.2 + maxLen + maxBR
    }

    var body: some View {
        // Reading engine.frame makes the body depend on it, so the Canvas
        // repaints every physics tick — independent of window focus.
        let _ = engine.frame
        Canvas { ctx, size in draw(ctx, size) }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let u = min(w / 190, h / 250)      // same design basis as the web build
        let cx = w / 2
        let y0 = h * 0.085
        let ringPx = min(w * 0.24, 58 * u)
        let canR = ringPx + 8 * u

        // hanger
        var hang = Path()
        hang.move(to: CGPoint(x: cx, y: 0))
        hang.addLine(to: CGPoint(x: cx, y: y0 - 6 * u))
        ctx.stroke(hang, with: .color(stringC), lineWidth: 1.1 * u)

        // canopy
        var canopy = Path()
        canopy.addEllipse(in: CGRect(x: cx - canR, y: y0 - canR * 0.24,
                                     width: canR * 2, height: canR * 0.48))
        ctx.fill(canopy, with: .linearGradient(
            Gradient(colors: [dark, canopyC, light.opacity(0.6), dark]),
            startPoint: CGPoint(x: cx - canR, y: y0),
            endPoint: CGPoint(x: cx + canR, y: y0)))

        // wind motes behind the chime
        for m in engine.motes {
            let a = min(0.22, m.life * 0.22)
            let r: CGFloat = 1.4
            var p = Path()
            p.addEllipse(in: CGRect(x: CGFloat(m.x) * w - r, y: CGFloat(m.y) * h - r,
                                    width: r * 2, height: r * 2))
            ctx.fill(p, with: .color(.white.opacity(a)))
        }

        let bells = engine.bells
        let order = bells.indices.sorted { cos(bells[$0].az) < cos(bells[$1].az) }

        for i in order {
            let b = bells[i]
            let depth = cos(b.az)
            let scale = 0.85 + 0.15 * depth
            let bx = cx + CGFloat(sin(b.az)) * ringPx + CGFloat(b.swing) * u * 1.6
            let frac = (b.freq * 13).truncatingRemainder(dividingBy: 5) / 5
            let len = (58 + 105 * CGFloat(frac)) * u
            let by = y0 + canR * 0.2 + len
            let bR = 11 * u * scale

            var s = Path()
            s.move(to: CGPoint(x: cx + CGFloat(sin(b.az)) * ringPx * 0.9, y: y0 + 2 * u))
            s.addLine(to: CGPoint(x: bx, y: by - bR))
            ctx.stroke(s, with: .color(stringC), lineWidth: 0.9 * u)

            var bctx = ctx
            bctx.translateBy(x: bx, y: by)
            bctx.rotate(by: .radians(b.swing * 0.02))
            bctx.opacity = 0.85 + 0.15 * depth

            var bell = Path()
            bell.move(to: CGPoint(x: -bR, y: bR * 0.55))
            bell.addCurve(to: CGPoint(x: 0, y: -bR),
                          control1: CGPoint(x: -bR * 1.05, y: -bR * 0.4),
                          control2: CGPoint(x: -bR * 0.5, y: -bR))
            bell.addCurve(to: CGPoint(x: bR, y: bR * 0.55),
                          control1: CGPoint(x: bR * 0.5, y: -bR),
                          control2: CGPoint(x: bR * 1.05, y: -bR * 0.4))
            bell.closeSubpath()
            bctx.fill(bell, with: .radialGradient(
                Gradient(colors: [light, mid, dark]),
                center: CGPoint(x: -bR * 0.3, y: -bR * 0.3),
                startRadius: bR * 0.15, endRadius: bR * 1.3))

            var rim = Path()
            rim.addEllipse(in: CGRect(x: -bR, y: bR * 0.42, width: bR * 2, height: bR * 0.34))
            bctx.fill(rim, with: .color(Color(red: 0.16, green: 0.10, blue: 0.03).opacity(0.5)))
            var clap = Path()
            clap.addEllipse(in: CGRect(x: -bR * 0.16, y: bR * 0.56, width: bR * 0.32, height: bR * 0.32))
            bctx.fill(clap, with: .color(dark))

            // glow flash on strike
            if b.glow > 0 {
                var g = Path()
                g.addEllipse(in: CGRect(x: -bR * 0.55, y: -bR * 0.7, width: bR * 1.1, height: bR * 1.1))
                bctx.fill(g, with: .color(Color(red: 1, green: 0.96, blue: 0.84).opacity(b.glow * 0.55)))
            }

            // expanding ripple on strike
            if b.ripple > 0 {
                var r = Path()
                let rr = bR + CGFloat(b.ripple) * 26 * u
                r.addEllipse(in: CGRect(x: bx - rr, y: by - rr, width: rr * 2, height: rr * 2))
                ctx.stroke(r, with: .color(accent.opacity((1 - b.ripple) * 0.3)), lineWidth: 1.2)
            }
        }
    }
}
