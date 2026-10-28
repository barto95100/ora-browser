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

            Toggle(isPrivate ? "Remember until Ora quits" : "Remember for this site", isOn: $remember)
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack(spacing: 8) {
                Spacer()
                OraButton(label: "Don't Allow", variant: .secondary, size: .sm) {
                    onAnswer(false, remember)
                }
                OraButton(label: "Allow", size: .sm) {
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
            return "wants to send you notifications"
        }
        return "wants to use your \(capabilityDescription)"
    }

    private var capabilityDescription: String {
        switch (request.types.contains(.camera), request.types.contains(.microphone)) {
        case (true, true): "camera and microphone"
        case (true, false): "camera"
        default: "microphone"
        }
    }

    private var symbolName: String {
        if request.types.contains(.notifications) {
            return "bell.fill"
        }
        return request.types.contains(.camera) ? "video.fill" : "mic.fill"
    }
}
