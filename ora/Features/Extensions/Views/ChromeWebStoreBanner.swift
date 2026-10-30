import SwiftUI
@preconcurrency import WebKit

/// On an extension's page in the Chrome Web Store (which asks for Chrome):
/// "Add to Ora". Not in private windows, nor before macOS 15.4.
struct ChromeWebStoreBanner: View {
    let tab: Tab

    var body: some View {
        if #available(macOS 15.4, *), !tab.isPrivate, let storeID = ChromeWebStore.extensionID(from: tab.url) {
            ChromeWebStoreBannerContent(storeID: storeID)
                .id(storeID)
        }
    }
}

@available(macOS 15.4, *)
private struct ChromeWebStoreBannerContent: View {
    let storeID: String
    @ObservedObject private var manager = WebExtensionsManager.shared
    @State private var isDismissed = false
    @State private var isDownloading = false
    @State private var review: WebExtensionsManager.Review?
    @State private var failure: String?

    private let cornerRadius: CGFloat = 14

    var body: some View {
        if !isDismissed {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                if let record = manager.installed(storeID: storeID) {
                    Text("“\(record.name)” is in Ora.")
                        .font(.subheadline)
                    Button("Manage…") { BrowserWindows.showSettings(.extensions) }
                        .controlSize(.small)
                        .pointerStyle(.link)
                } else if let failure {
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Button("Try Again") { add() }
                        .controlSize(.small)
                        .pointerStyle(.link)
                } else {
                    Text("Add this extension to Ora.")
                        .font(.subheadline)
                    // The banner's one action: stands out, and the pointer says
                    // it can be clicked.
                    Button(isDownloading ? "Downloading…" : "Add to Ora…") { add() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isDownloading)
                        .pointerStyle(.link)
                }

                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
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
            .sheet(item: $review) { review in
                ExtensionReviewSheet(review: review) { allowAllSites in
                    manager.install(review, allowAllSites: allowAllSites)
                    self.review = nil
                } cancel: {
                    manager.discard(review)
                    self.review = nil
                }
            }
        }
    }

    private func add() {
        failure = nil
        isDownloading = true
        Task {
            do {
                review = try await manager.reviewFromWebStore(storeID)
            } catch {
                failure = "Couldn't add it: \(error.localizedDescription)"
            }
            isDownloading = false
        }
    }
}
