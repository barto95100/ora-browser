import SwiftUI

// MARK: - Size

enum OmbreIconSize {
    case xs, sm, md, lg, xl
    case custom(CGFloat)

    var dimension: CGFloat {
        switch self {
        case .xs: 10
        case .sm: 12
        case .md: 16
        case .lg: 20
        case .xl: 24
        case let .custom(value): value
        }
    }
}

// MARK: - Type-erased shape wrapper

struct AnyOmbreShape: Shape {
    private let _path: @Sendable (CGRect) -> Path

    init(_ shape: some Shape & Sendable) {
        _path = { shape.path(in: $0) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

// MARK: - Icon registry

enum OmbreIconType {
    case star
    case circle
    case spaceCards
    case spaceCardsDelete
    case spaceCardsEdit
    case autofill
    case copy
    case brush1
    case brush2
    case downloadBox
    case downloadBox2
    case shieldLock
    case shieldBan
    case custom(AnyOmbreShape)

    var shape: AnyOmbreShape {
        switch self {
        case .star:             AnyOmbreShape(StarIcon())
        case .circle:           AnyOmbreShape(Circle())
        case .spaceCards:       AnyOmbreShape(SpaceCardsIcon())
        case .spaceCardsDelete: AnyOmbreShape(SpaceCardsDeleteIcon())
        case .spaceCardsEdit:   AnyOmbreShape(SpaceCardsEditIcon())
        case .autofill:         AnyOmbreShape(AutofillIcon())
        case .copy:             AnyOmbreShape(CopyIcon())
        case .brush1:           AnyOmbreShape(Brush1())
        case .brush2:           AnyOmbreShape(Brush2())
        case .downloadBox:      AnyOmbreShape(DownloadBox())
        case .downloadBox2:     AnyOmbreShape(DownloadBox2())
        case .shieldLock:       AnyOmbreShape(ShieldLockIcon())
        case .shieldBan:        AnyOmbreShape(ShieldBanIcon())
        case let .custom(shape): shape
        }
    }
}

// MARK: - View

struct OmbreIcons: View {
    let icon: OmbreIconType
    var size: OmbreIconSize = .md
    var color: Color?

    @Environment(\.theme) private var theme

    var body: some View {
        icon.shape
            .fill(color ?? theme.foreground)
            .frame(width: size.dimension, height: size.dimension)
    }
}

// MARK: - Built-in icon shapes

private struct StarIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let centerX = rect.midX
        let centerY = rect.midY
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.4
        var path = Path()
        for index in 0 ..< 10 {
            let angle = (Double(index) * .pi / 5) - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: centerX + CGFloat(cos(angle)) * radius,
                y: centerY + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            OmbreIcons(icon: .star, size: .xs)
            OmbreIcons(icon: .star, size: .sm)
            OmbreIcons(icon: .star, size: .md)
            OmbreIcons(icon: .star, size: .lg)
            OmbreIcons(icon: .star, size: .xl)
        }
        HStack(spacing: 16) {
            OmbreIcons(icon: .circle, size: .xl)
            OmbreIcons(icon: .star, size: .xl, color: .orange)
            OmbreIcons(icon: .custom(AnyOmbreShape(RoundedRectangle(cornerRadius: 4))), size: .xl)
        }
    }
    .padding(40)
    .withTheme()
}
