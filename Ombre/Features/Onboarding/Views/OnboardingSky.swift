import AppKit
import SwiftUI

// MARK: - Clock

/// Whether the endless animations (stars, orbits, confetti) are stopped:
/// while the window is hidden, covered or minimized.
private struct OnboardingAnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onboardingAnimationsPaused: Bool {
        get { self[OnboardingAnimationsPausedKey.self] }
        set { self[OnboardingAnimationsPausedKey.self] = newValue }
    }
}

/// The time for the assistant's endless animations. It stops while the
/// window can't be seen, and stays at 0 with Reduce Motion: everything is
/// drawn still. 30 frames a second are plenty for these slow motions.
struct OnboardingClock<Content: View>: View {
    var minimumInterval: Double? = 1.0 / 30
    @ViewBuilder let content: (TimeInterval) -> Content

    @Environment(\.onboardingAnimationsPaused) private var isPaused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(0)
        } else {
            TimelineView(.animation(minimumInterval: minimumInterval, paused: isPaused)) { context in
                content(context.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

/// Tells whether the window holding it can be seen (its occlusion state).
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        var onChange: ((Bool) -> Void)?
        private nonisolated(unsafe) var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] notification in
                // Delivered on the main queue (`queue: .main`).
                nonisolated(unsafe) let notification = notification
                MainActor.assumeIsolated {
                    guard let window = notification.object as? NSWindow else { return }
                    self?.onChange?(window.occlusionState.contains(.visible))
                }
            }
            let isVisible = window.occlusionState.contains(.visible)
            // Not during the view update that added it.
            DispatchQueue.main.async { [weak self] in self?.onChange?(isVisible) }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

// MARK: - Sky

/// The step's sky. The skies fade into each other: each one is a layer,
/// only the current one shown.
struct OnboardingSkyBackground: View {
    let step: OnboardingStep

    var body: some View {
        ZStack {
            ForEach(OnboardingStep.allCases, id: \.self) { sky in
                LinearGradient(stops: Self.stops(for: sky), startPoint: .top, endPoint: .bottom)
                    .opacity(sky == step ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private static func stops(for step: OnboardingStep) -> [Gradient.Stop] {
        let sky = OnboardingNightfall.sky(for: step)
        return zip(sky.colors, sky.locations).map { Gradient.Stop(color: Color(hex: $0), location: $1) }
    }
}

/// The stars: they come out one after the other as `shown` grows, and twinkle.
struct OnboardingStarField: View, Animatable {
    var shown: Double

    nonisolated var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    private static let starColor = Color(hex: "#FFF8F0")

    var body: some View {
        Group {
            if shown > 0 {
                OnboardingClock { time in
                    stars(at: time)
                }
            } else {
                // No star yet: nothing to keep drawing.
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stars(at time: TimeInterval) -> some View {
        Canvas { context, size in
            for (index, star) in OnboardingNightfall.starField.enumerated() {
                let visibility = OnboardingNightfall.visibility(ofStar: index, shown: shown)
                guard visibility > 0 else { continue }
                let twinkle = time == 0 ? 0.75 : OnboardingNightfall.twinkle(star, at: time)
                let rect = CGRect(
                    x: star.left * size.width,
                    y: star.top * size.height,
                    width: star.size,
                    height: star.size
                )
                context.opacity = visibility * twinkle
                context.fill(Path(ellipseIn: rect), with: .color(Self.starColor))
            }
        }
    }
}

/// Floats its content up and down. Only the offset follows the clock: the
/// content isn't drawn again each frame.
struct OnboardingFloat: ViewModifier {
    var distance: CGFloat
    /// Seconds for a full rise and fall.
    var period: Double
    var isActive = true

    func body(content: Content) -> some View {
        if isActive {
            OnboardingClock { time in
                content.offset(y: -distance * (0.5 - 0.5 * cos(time / period * 2 * .pi)))
            }
        } else {
            content
        }
    }
}
