import Foundation

/// Reglas de sincronización, sin red ni base de datos (se prueban en tests).
enum SyncPlanner {
    struct LocalRecord: Equatable, Sendable {
        let id: String
        let payload: String
        let lastSyncedHash: String

        var isDirty: Bool { SyncCoding.hash(payload) != lastSyncedHash }
    }

    struct RemoteRecord: Equatable, Sendable {
        let id: String
        let payload: String
        let deleted: Bool
    }

    enum RemoteAction: Equatable {
        /// Crear o actualizar el registro local con lo que vino del servidor.
        case apply(id: String, payload: String)
        /// Borrar el registro local.
        case deleteLocal(id: String)
        /// Nada que hacer (ya lo tenemos igual, o cambiamos algo aquí que se va a subir y gana).
        case skip(id: String)
    }

    /// Decide qué hacer con cada fila que llegó del servidor.
    /// Si el registro local tiene cambios sin subir, gana el local (se sube enseguida).
    static func plan(remote: [RemoteRecord], local: [String: LocalRecord]) -> [RemoteAction] {
        remote.map { row in
            let localRecord = local[row.id]
            if row.deleted {
                if let localRecord, localRecord.isDirty { return .skip(id: row.id) }
                return localRecord == nil ? .skip(id: row.id) : .deleteLocal(id: row.id)
            }
            guard let localRecord else { return .apply(id: row.id, payload: row.payload) }
            if localRecord.isDirty { return .skip(id: row.id) }
            if SyncCoding.hash(row.payload) == localRecord.lastSyncedHash { return .skip(id: row.id) }
            return .apply(id: row.id, payload: row.payload)
        }
    }

    /// Qué subir: registros con cambios, y como borrados los que conocíamos y ya no existen aquí.
    static func pushes(local: [LocalRecord], knownIDs: Set<String>) -> (upserts: [LocalRecord], deletions: [String]) {
        let upserts = local.filter(\.isDirty)
        let present = Set(local.map(\.id))
        let deletions = knownIDs.subtracting(present).sorted()
        return (upserts, deletions)
    }
}
