import AppKit
import SwiftUI

/// How safe the connection of a page is, for its address.
enum PageSecurity: Equatable {
    /// HTTPS, and everything it loaded too.
    case secure
    /// HTTP, or an HTTPS page that loaded something over HTTP.
    case notSecure
    /// No connection of its own (`about:blank`, `blob:`, `data:`, a file).
    case local

    static func of(_ url: URL?, hasOnlySecureContent: Bool) -> PageSecurity {
        switch url?.scheme?.lowercased() {
        case "https": hasOnlySecureContent ? .secure : .notSecure
        case "http": .notSecure
        default: .local
        }
    }
}

/// An address as the popup's bar shows it: the site (host and port, never
/// any user name before it), then the rest. A long address is cut in the
/// rest, never in the site, so it can't hide the real domain
/// (`accounts.example.com.attacker.example`).
struct PopupDisplayAddress: Equatable {
    let site: String
    let rest: String

    init(_ url: URL?) {
        guard let url else {
            site = ""
            rest = ""
            return
        }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            site = url.absoluteString
            rest = ""
            return
        }
        // An IPv6 address keeps its brackets (`[::1]:8080`).
        let shownHost = host.contains(":") ? "[\(host)]" : host
        site = url.port.map { "\(shownHost):\($0)" } ?? shownHost
        // Read piece by piece: a path starting with `//` has no string of
        // its own in `URLComponents`.
        var rest = url.path(percentEncoded: true)
        if let query = url.query(percentEncoded: true) { rest += "?\(query)" }
        if let fragment = url.fragment(percentEncoded: true) { rest += "#\(fragment)" }
        self.rest = rest == "/" ? "" : rest
    }
}

/// A popup's address, like Safari's: read only, the site in full then the
/// rest of the address, each selectable (⌘C), the whole address with the
/// copy button and in its help tag, with the lock (or "Not Secure") before it,
/// so a popup can't pass for another site.
struct PopupAddressBar: View {
    @ObservedObject var popup: PopupPage

    var body: some View {
        HStack(spacing: 6) {
            securityLabel
            let display = PopupDisplayAddress(popup.address)
            let full = popup.address?.absoluteString ?? ""
            // The end of the site (its domain) shows first if it is too long.
            SelectableAddressField(text: display.site, help: full, isSite: true)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            SelectableAddressField(text: display.rest, help: full, isSite: false)
                .frame(maxWidth: .infinity)
            Button {
                guard let address = popup.address else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address.absoluteString, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(popup.address == nil)
            .help("Copy Address")
            .accessibilityLabel(Text("Copy Address"))
        }
        .padding(.horizontal, 10)
        .frame(height: PopupAddressBar.height)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    static let height: CGFloat = 28

    @ViewBuilder private var securityLabel: some View {
        switch popup.security {
        case .secure:
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("Secure connection")
                .accessibilityLabel(Text("Secure connection"))
        case .notSecure:
            Label("Not Secure", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize()
        case .local:
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// Read-only text that can be selected and copied (⌘C). The site is cut at
/// its start when too long (its domain stays), the rest at its end.
private struct SelectableAddressField: NSViewRepresentable {
    let text: String
    let help: String
    let isSite: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.isSelectable = true
        field.lineBreakMode = isSite ? .byTruncatingHead : .byTruncatingTail
        field.font = isSite ? .systemFont(ofSize: 12, weight: .medium) : .systemFont(ofSize: 12)
        field.textColor = isSite ? .labelColor : .secondaryLabelColor
        // The site gives way after the rest, before the security label and
        // the buttons (which must always show).
        let resistance = NSLayoutConstraint.Priority.defaultLow
        field.setContentCompressionResistancePriority(isSite ? resistance + 1 : resistance, for: .horizontal)
        field.toolTip = help
        field.setAccessibilityLabel(isSite ? String(localized: "Site") : String(localized: "Rest of the address"))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        if field.toolTip != help { field.toolTip = help }
    }
}
