import SwiftUI

/// Ombre's little planet, drawn from the layers of `Ombre.icon`: the globe
/// in its peach-to-violet gradient, its meridians, and the shadow with its
/// wavy peach edge. `shadow` 0 is full sun, 1 the icon exactly, more is a
/// deeper shade.
struct OmbrePlanet: View {
    var size: CGFloat
    var shadow: Double = 1
    var ring = false

    var body: some View {
        ZStack {
            if ring {
                PlanetRing(half: .back)
                    .stroke(Self.ringGradient, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                    .frame(width: size * 1.81, height: size * 0.36)
                    .rotationEffect(.degrees(-12))
            }
            globe
            if ring {
                PlanetRing(half: .front)
                    .stroke(Self.ringGradient, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                    .frame(width: size * 1.81, height: size * 0.36)
                    .rotationEffect(.degrees(-12))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var globe: some View {
        ZStack {
            Circle().fill(LinearGradient(
                stops: [
                    .init(color: Color(hex: "#FFD6A5"), location: 0),
                    .init(color: Color(hex: "#FF8A5C"), location: 0.3),
                    .init(color: Color(hex: "#E8459B"), location: 0.62),
                    .init(color: Color(hex: "#7A3BE0"), location: 1)
                ],
                startPoint: UnitPoint(x: 0.85, y: 0.05),
                endPoint: UnitPoint(x: 0.2, y: 0.9)
            ))
            PlanetMeridians()
                .stroke(Color.white.opacity(0.45), lineWidth: size * 13 / 640)
            ZStack {
                PlanetShadowEdge(closed: true)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: Color(hex: "#2A1A6E").opacity(0.72), location: 0),
                            .init(color: Color(hex: "#170E47").opacity(0.92), location: 0.55),
                            .init(color: Color(hex: "#0B0728").opacity(0.98), location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0.45),
                        endPoint: UnitPoint(x: 0.5, y: 1.106)
                    ))
                PlanetShadowEdge(closed: false)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: "#FF9E7A"), location: 0),
                                .init(color: Color(hex: "#FFE2BC"), location: 0.5),
                                .init(color: Color(hex: "#FFB08A"), location: 1)
                            ],
                            startPoint: UnitPoint(x: -0.034, y: 0.5),
                            endPoint: UnitPoint(x: 1.044, y: 0.5)
                        ),
                        style: StrokeStyle(lineWidth: size * 16 / 640, lineCap: .round)
                    )
            }
            .offset(y: Self.shadowOffset(shadow) * size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// How far below the icon's shadow this one sits, in diameters: far
    /// enough at 0 that none of it shows.
    static func shadowOffset(_ shadow: Double) -> CGFloat {
        CGFloat(1 - shadow) * 0.62
    }

    private static let ringGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "#FFD3B0").opacity(0.2), location: 0),
            .init(color: Color(hex: "#FFD3B0").opacity(0.95), location: 0.5),
            .init(color: Color(hex: "#F58AB8").opacity(0.2), location: 1)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Shapes

/// The icon's points (1024 wide, globe of radius 320 at the center) in
/// fractions of the globe.
private func globePoint(_ iconX: CGFloat, _ iconY: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + (iconX - 192) / 640 * rect.width, y: rect.minY + (iconY - 192) / 640 * rect.height)
}

/// The meridian, its two neighbours and three parallels of the icon.
private struct PlanetMeridians: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(
            origin: globePoint(372, 192, in: rect),
            size: CGSize(width: rect.width * 280 / 640, height: rect.height)
        ))
        path.move(to: globePoint(512, 180, in: rect))
        path.addLine(to: globePoint(512, 840, in: rect))
        // Lower halves of ellipses: (center y, x radius, y radius).
        for (centerY, radiusX, radiusY) in [(470.0, 320.0, 78.0), (330.0, 282.0, 58.0), (640.0, 282.0, 70.0)] {
            let steps = 32
            for step in 0 ... steps {
                let angle = Double(step) / Double(steps) * .pi
                let point = globePoint(512 + radiusX * cos(angle), centerY + radiusY * sin(angle), in: rect)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path
    }
}

/// The shadow's wavy top edge; closed, the shadow itself, reaching far down
/// so it still covers the bottom when raised.
private struct PlanetShadowEdge: Shape {
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: globePoint(170, 575, in: rect))
        path.addCurve(
            to: globePoint(610, 610, in: rect),
            control1: globePoint(330, 480, in: rect),
            control2: globePoint(450, 700, in: rect)
        )
        path.addCurve(
            to: globePoint(860, 535, in: rect),
            control1: globePoint(730, 545, in: rect),
            control2: globePoint(800, 575, in: rect)
        )
        if closed {
            path.addLine(to: globePoint(900, 2200, in: rect))
            path.addLine(to: globePoint(130, 2200, in: rect))
            path.closeSubpath()
        }
        return path
    }
}

/// Half of a ring's ellipse: the back one goes behind the globe.
private struct PlanetRing: Shape {
    enum Half { case back, front }
    let half: Half

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        let start = half == .front ? 0.0 : Double.pi
        for step in 0 ... steps {
            let angle = start + Double(step) / Double(steps) * .pi
            let point = CGPoint(
                x: rect.midX + rect.width / 2 * cos(angle),
                y: rect.midY + rect.height / 2 * sin(angle)
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
