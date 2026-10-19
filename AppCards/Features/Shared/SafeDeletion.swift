import SwiftUI
import SwiftData

/// Borrar algo desde su propia pantalla sin que la app se cierre:
/// primero se cierra la pantalla y, cuando ya no se dibuja, se borra.
@MainActor
enum SafeDeletion {
    static func delete(_ model: any PersistentModel, in context: ModelContext, after dismiss: DismissAction) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard !model.isDeleted else { return }
            context.delete(model)
            try? context.save()
        }
    }
}

extension PersistentModel {
    /// `true` si ya se borró (aquí o desde el otro dispositivo); leer sus datos cerraría la app.
    var isGone: Bool { isDeleted || modelContext == nil }
}

/// Lo que se ve si lo que estabas viendo se borró, por ejemplo desde tu otro dispositivo.
struct DeletedPlaceholder: View {
    var title = "Ya no existe"
    var message = "Se borró, tal vez desde tu otro dispositivo."

    var body: some View {
        ContentUnavailableView(title, systemImage: "trash.slash", description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
