import SwiftUI

/// Offers to let a local page read its folder, when the images, styles or
/// scripts next to it are blocked by the sandbox.
struct LocalFolderAccessPromptView: View {
    let folderName: String
    let onAllow: () -> Void
    let onDismiss: () -> Void

    private let cornerRadius: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Text("Images and styles next to this file can't be shown.")
                .font(.subheadline)
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(2)

            Button("Allow Access to “\(folderName)”…", action: onAllow)
                .controlSize(.small)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
}
