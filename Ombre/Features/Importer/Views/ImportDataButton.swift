import SwiftUI

/// File › Import Data. Arc's import is gone until it is redone with real
/// data: it read a file the sandbox never lets the app see.
struct ImportDataButton: View {
    var body: some View {
        Menu("Import Data") {
            Button("Zen…") {
                BrowserWindows.showImport()
            }
        }
    }
}
