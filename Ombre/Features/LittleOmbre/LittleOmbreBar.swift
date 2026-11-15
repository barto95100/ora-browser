import SwiftUI

/// Little Ombre's bar: the page's site (never hidden by a long address) and
/// its lock, the address to type when clicked (⌘L), and "Open in Ombre"
/// (⌘O) with the spaces to open it in.
struct LittleOmbreBar: View {
    @ObservedObject var popup: PopupPage
    @ObservedObject var model: LittleOmbreModel
    @State private var text = ""
    @FocusState private var isEditing: Bool

    static let height: CGFloat = 36

    var body: some View {
        HStack(spacing: 8) {
            PageSecurityLabel(security: popup.security)
            ZStack(alignment: .leading) {
                TextField("Search or enter address", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isEditing)
                    .opacity(isEditing || popup.address == nil ? 1 : 0)
                    .onSubmit {
                        model.owner?.navigate(to: text)
                        isEditing = false
                    }
                    .onExitCommand { isEditing = false }
                    .accessibilityLabel(Text("Address"))
                if !isEditing, popup.address != nil {
                    shownAddress
                        .contentShape(Rectangle())
                        .onTapGesture { isEditing = true }
                }
            }
            .frame(maxWidth: .infinity)
            openInOmbreButton
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: isEditing) { _, editing in
            if editing { text = popup.address?.absoluteString ?? "" }
        }
        .onChange(of: model.addressFocusRequest) {
            isEditing = true
        }
    }

    /// The site in full, then the rest of the address, like a popup's.
    private var shownAddress: some View {
        let display = PopupDisplayAddress(popup.address)
        return HStack(spacing: 0) {
            Text(display.site)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(1)
            Text(display.rest)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .help(popup.address?.absoluteString ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Address"))
        .accessibilityValue(Text(popup.address?.absoluteString ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isEditing = true }
    }

    /// The page in a tab: of Little Ombre's space at once (the page kept as
    /// it is), or of another space from the menu.
    private var openInOmbreButton: some View {
        Menu {
            ForEach(model.owner?.spaces ?? []) { space in
                Button(space.emoji.isEmpty ? space.name : "\(space.emoji) \(space.name)") {
                    model.owner?.openInOmbre(space: space)
                }
            }
        } label: {
            Label("Open in Ombre", systemImage: "arrow.up.forward.app")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12))
        } primaryAction: {
            model.owner?.openInOmbre()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(popup.address == nil)
        .help("Open in Ombre (⌘O)")
    }
}
