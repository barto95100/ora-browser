import SwiftUI

/// Asks whether the current site may use the camera and/or the microphone, or
/// send notifications.
///
/// There is deliberately no keyboard shortcut for "Allow": a reflex press of
/// Return must never hand a capture device to a website.
struct SitePermissionPromptView: View {
    let request: SitePermissionRequest
    let isPrivate: Bool
    let onAnswer: (_ granted: Bool, _ remember: Bool) -> Void

    @State private var remember = true

    init(
        request: SitePermissionRequest,
        isPrivate: Bool,
        onAnswer: @escaping (_ granted: Bool, _ remember: Bool) -> Void
    ) {
        self.request = request
        self.isPrivate = isPrivate
        self.onAnswer = onAnswer
        // Screen sharing is asked each time unless chosen otherwise, like
        // Safari: the screen shows more than a site needs to know.
        _remember = State(initialValue: !request.types.contains(.screen))
    }

    private let width: CGFloat = 340
    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(nsColor: .labelColor).opacity(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.origin.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(requestDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }

            Toggle(isPrivate ? "Remember until Ombre quits" : "Remember for this site", isOn: $remember)
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack(spacing: 8) {
                Spacer()
                OmbreButton(label: String(localized: "Don't Allow"), variant: .secondary, size: .sm) {
                    onAnswer(false, remember)
                }
                OmbreButton(label: String(localized: "Allow"), size: .sm) {
                    onAnswer(true, remember)
                }
            }
        }
        .padding(14)
        .frame(width: width)
        .background {
            ZStack {
                BlurEffectView(material: .popover, blendingMode: .withinWindow)
                Color(nsColor: .windowBackgroundColor).opacity(0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
    }

    private var requestDescription: String {
        if request.types == [.notifications] {
            return String(localized: "wants to send you notifications")
        }
        if request.types == [.location] {
            return String(localized: "wants to know your location")
        }
        if request.types == [.screen] {
            return String(localized: "wants to share your screen")
        }
        if request.types == [.downloads] {
            return String(localized: "wants to download files")
        }
        return capabilityRequest
    }

    private var capabilityRequest: String {
        switch (request.types.contains(.camera), request.types.contains(.microphone)) {
        case (true, true): String(localized: "wants to use your camera and microphone")
        case (true, false): String(localized: "wants to use your camera")
        default: String(localized: "wants to use your microphone")
        }
    }

    private var symbolName: String {
        if request.types.contains(.notifications) {
            return "bell.fill"
        }
        if request.types.contains(.location) {
            return "location.fill"
        }
        if request.types.contains(.screen) {
            return "rectangle.inset.filled.on.rectangle"
        }
        if request.types.contains(.downloads) {
            return "arrow.down.circle.fill"
        }
        return request.types.contains(.camera) ? "video.fill" : "mic.fill"
    }
}
