import AppKit
import SwiftUI

/// "Delete saved password?", in the Passwords window and in the settings.
/// A delete that fails is said, never shown as done.
struct PasswordDeleteConfirmation: ViewModifier {
    @Binding var pendingDelete: SavedPasswordSummary?
    let delete: (SavedPasswordSummary) throws -> Void

    func body(content: Content) -> some View {
        content.alert("Delete saved password?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    Self.perform(delete, on: pendingDelete) { title, error in
                        // After this alert: never a sheet over a closing sheet.
                        Task { @MainActor in
                            PasswordFailureAlert.present(title: title, error: error, in: NSApp.keyWindow)
                        }
                    }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            if let pendingDelete {
                Text("Remove the saved credential for \(pendingDelete.displayUsername) on \(pendingDelete.host)?")
            }
        }
    }

    /// Deletes `entry`; a failure goes to `onFailure` with its title.
    static func perform(
        _ delete: (SavedPasswordSummary) throws -> Void,
        on entry: SavedPasswordSummary,
        onFailure: (String, Error) -> Void
    ) {
        do {
            try delete(entry)
        } catch {
            // Logged with its status by the service.
            onFailure(deleteFailureTitle(username: entry.displayUsername, host: entry.host), error)
        }
    }

    nonisolated static func deleteFailureTitle(username: String, host: String) -> String {
        String(localized: "Ombre couldn't delete the password for \(username) on \(host)")
    }
}

extension View {
    func passwordDeleteConfirmation(
        _ pendingDelete: Binding<SavedPasswordSummary?>,
        delete: @escaping (SavedPasswordSummary) throws -> Void
    ) -> some View {
        modifier(PasswordDeleteConfirmation(pendingDelete: pendingDelete, delete: delete))
    }
}
