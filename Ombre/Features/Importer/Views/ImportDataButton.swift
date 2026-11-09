import SwiftUI

/// The browsers Ombre imports from.
enum ImportSource: String, Identifiable {
    case zen
    case safari
    case arc

    var id: String {
        rawValue
    }
}

/// File › Import Data.
struct ImportDataButton: View {
    var body: some View {
        Menu("Import Data") {
            Button("Safari…") { BrowserWindows.showImport(from: .safari) }
            Button("Arc…") { BrowserWindows.showImport(from: .arc) }
            Button("Zen…") { BrowserWindows.showImport(from: .zen) }
        }
    }
}
