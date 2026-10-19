import Foundation
import Observation
import SwiftData
import Supabase

/// Dónde está el proyecto de Supabase. Se lee de Config/Supabase.xcconfig (no se sube al repo).
enum SupabaseConfig {
    static var url: URL? {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String,
              !host.isEmpty, !host.contains("$(") else { return nil }
        // `SUPABASE_SCHEME = http` solo para pruebas con Supabase local.
        let scheme = (Bundle.main.object(forInfoDictionaryKey: "SupabaseScheme") as? String).flatMap { $0.isEmpty || $0.contains("$(") ? nil : $0 } ?? "https"
        return URL(string: "\(scheme)://\(host)")
    }

    static var anonKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !key.isEmpty, !key.contains("$(") else { return nil }
        return key
    }

    static var isConfigured: Bool { url != nil && anonKey != nil }
}

enum SyncError: LocalizedError {
    case sessionNotStored
    case linkError(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotStored: "Se inició sesión pero no se pudo guardar en este dispositivo. Intenta de nuevo."
        case .linkError(let message): message
        }
    }
}

/// Qué pasó al abrir un enlace de correo de Supabase.
enum AuthLinkResult: Equatable {
    case signedIn
    case passwordRecovery
}

/// Inicio de sesión y sincronización de colección, decks y deseos con Supabase.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case notConfigured
        case signedOut
        case signedIn(email: String)
    }

    private(set) var status: Status = .notConfigured
    /// Nombre de la persona (se pide al crear la cuenta).
    private(set) var displayName: String?
    /// `true` hasta revisar si hay sesión guardada; mientras, la app muestra una pantalla de carga.
    private(set) var isRestoring = true
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    /// Mientras se aplican cambios que vienen del servidor, los guardados no disparan otra sincronización.
    private(set) var isApplyingRemote = false

    private let client: SupabaseClient?
    private let defaults: UserDefaults
    private static let table = "sync_records"
    private static let pageSize = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
            status = .signedOut
        } else {
            client = nil
        }
        lastSyncAt = defaults.object(forKey: "sync.lastSyncAt") as? Date
    }

    // MARK: Sesión

    /// Revisa la sesión guardada en el dispositivo. No necesita internet: si la sesión expiró,
    /// la sincronización la renueva cuando haya conexión.
    func restoreSession() async {
        defer { isRestoring = false }
        guard let client else { return }
        if let session = client.auth.currentSession {
            apply(session.user)
        } else {
            status = .signedOut
            displayName = nil
        }
    }

    private func apply(_ user: User) {
        status = .signedIn(email: user.email ?? "")
        let name = user.userMetadata["full_name"]?.stringValue?.trimmingCharacters(in: .whitespaces)
        displayName = (name?.isEmpty ?? true) ? nil : name
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { return }
        let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        // Confirma que la sesión quedó guardada en el llavero; si no, dilo en vez de fallar en silencio.
        guard client.auth.currentSession != nil else {
            throw SyncError.sessionNotStored
        }
        apply(session.user)
        lastError = nil
    }

    /// Regresa `true` si ya quedó con sesión; `false` si hay que confirmar el correo primero.
    /// A dónde regresan los enlaces de los correos (confirmar cuenta, cambiar contraseña).
    /// Debe estar en Supabase > Authentication > URL Configuration > Redirect URLs.
    static let callbackURL = URL(string: "imsoft-vault://auth-callback")!
    private static let pendingRecoveryKey = "auth.pendingRecovery"

    func signUp(name: String, email: String, password: String) async throws -> Bool {
        guard let client else { return false }
        let response = try await client.auth.signUp(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password,
            data: ["full_name": .string(name.trimmingCharacters(in: .whitespaces))],
            redirectTo: Self.callbackURL
        )
        if let session = response.session {
            apply(session.user)
            return true
        }
        return false
    }

    /// Manda el correo para cambiar la contraseña. El enlace abre Vault en este dispositivo.
    func requestPasswordReset(email: String) async throws {
        guard let client else { return }
        try await client.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespaces), redirectTo: Self.callbackURL)
        defaults.set(true, forKey: Self.pendingRecoveryKey)
    }

    /// Abre un enlace de correo: confirma la cuenta o inicia la recuperación de contraseña, y deja la sesión iniciada.
    func handleAuthLink(_ url: URL) async throws -> AuthLinkResult {
        guard let client else { throw SyncError.linkError("Falta conectar el proyecto de Supabase.") }
        if let message = Self.linkErrorMessage(url) { throw SyncError.linkError(message) }
        let session = try await client.auth.session(from: url)
        apply(session.user)
        lastError = nil
        if defaults.bool(forKey: Self.pendingRecoveryKey) || url.absoluteString.contains("type=recovery") {
            defaults.removeObject(forKey: Self.pendingRecoveryKey)
            return .passwordRecovery
        }
        return .signedIn
    }

    /// Cambia la contraseña de la cuenta con sesión iniciada.
    func updatePassword(_ newPassword: String) async throws {
        guard let client else { return }
        _ = try await client.auth.update(user: UserAttributes(password: newPassword))
    }

    /// Supabase manda los errores del enlace en la URL (por ejemplo, enlace vencido).
    static func linkErrorMessage(_ url: URL) -> String? {
        let pieces = [URLComponents(url: url, resolvingAgainstBaseURL: false)?.query, url.fragment].compactMap { $0 }
        for piece in pieces {
            let items = URLComponents(string: "?" + piece)?.queryItems ?? []
            let code = items.first { $0.name == "error_code" }?.value
            let description = items.first { $0.name == "error_description" }?.value
            guard code != nil || items.contains(where: { $0.name == "error" }) else { continue }
            if code == "otp_expired" { return "Ese enlace ya venció o ya se usó. Pide uno nuevo." }
            return description?.replacingOccurrences(of: "+", with: " ") ?? "El enlace no es válido. Pide uno nuevo."
        }
        return nil
    }

    /// Vuelve a mandar el correo de confirmación de cuenta.
    func resendConfirmation(email: String) async throws {
        guard let client else { return }
        try await client.auth.resend(email: email.trimmingCharacters(in: .whitespaces), type: .signup, emailRedirectTo: Self.callbackURL)
    }

    /// Traduce los errores de Supabase a mensajes claros.
    static func friendlyMessage(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login credentials") { return "Correo o contraseña incorrectos." }
        if raw.contains("email not confirmed") { return "Aún no confirmas tu correo. Revisa tu bandeja de entrada." }
        if raw.contains("already registered") || raw.contains("already exists") { return "Ya existe una cuenta con ese correo. Inicia sesión." }
        if raw.contains("password") && raw.contains("6") { return "La contraseña debe tener al menos 6 caracteres." }
        if raw.contains("rate limit") || raw.contains("too many") { return "Demasiados intentos. Espera un minuto e intenta de nuevo." }
        if raw.contains("should be different") || raw.contains("same password") { return "La contraseña nueva debe ser distinta a la anterior." }
        if raw.contains("code verifier") || raw.contains("pkce") { return "Abre el enlace del correo en el mismo dispositivo donde lo pediste." }
        if raw.contains("offline") || raw.contains("network") || raw.contains("internet") { return "Sin conexión a internet." }
        if raw.contains("invalid") && raw.contains("email") { return "Ese correo no es válido." }
        return error.localizedDescription
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
        status = .signedOut
        displayName = nil
        lastSyncAt = nil
        defaults.removeObject(forKey: "sync.lastSyncAt")
    }

    // MARK: Sincronización

    private struct Row: Codable {
        let user_id: UUID
        let kind: String
        let id: String
        let payload: String
        let deleted: Bool
        var updated_at: String?
    }

    private struct UpsertRow: Encodable {
        let user_id: UUID
        let kind: String
        let id: String
        let payload: String
        let deleted: Bool
    }

    private func cursorKey(_ user: UUID) -> String { "sync.cursor.\(user.uuidString)" }
    private func knownKey(_ user: UUID, _ kind: SyncKind) -> String { "sync.known.\(user.uuidString).\(kind.rawValue)" }

    private func known(_ user: UUID, _ kind: SyncKind) -> Set<String> {
        Set(defaults.stringArray(forKey: knownKey(user, kind)) ?? [])
    }

    private func setKnown(_ ids: Set<String>, _ user: UUID, _ kind: SyncKind) {
        defaults.set(Array(ids), forKey: knownKey(user, kind))
    }

    /// Baja lo nuevo del servidor, lo aplica, y sube lo que cambió aquí.
    func sync(context: ModelContext) async {
        guard let client, !isSyncing, case .signedIn = status else { return }
        guard let user = try? await client.auth.session.user else {
            status = .signedOut
            lastError = "Tu sesión expiró. Vuelve a iniciar sesión."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        DiagnosticsLog.event("sync start")

        do {
            assignMissingIDs(context: context)
            try await pull(client: client, user: user.id, context: context)
            try await push(client: client, user: user.id, context: context)
            lastSyncAt = .now
            defaults.set(lastSyncAt, forKey: "sync.lastSyncAt")
            lastError = nil
            DiagnosticsLog.event("sync ok")
        } catch {
            lastError = error.localizedDescription
            DiagnosticsLog.event("sync error \(error.localizedDescription)")
        }
    }

    private func assignMissingIDs(context: ModelContext) {
        var changed = false
        for deck in (try? context.fetch(FetchDescriptor<Deck>())) ?? [] where deck.syncID.isEmpty { deck.syncID = UUID().uuidString; changed = true }
        for entry in (try? context.fetch(FetchDescriptor<DeckEntry>())) ?? [] where entry.syncID.isEmpty { entry.syncID = UUID().uuidString; changed = true }
        for item in (try? context.fetch(FetchDescriptor<CollectionItem>())) ?? [] where item.syncID.isEmpty { item.syncID = UUID().uuidString; changed = true }
        for item in (try? context.fetch(FetchDescriptor<WishlistItem>())) ?? [] where item.syncID.isEmpty { item.syncID = UUID().uuidString; changed = true }
        if changed { saveQuietly(context) }
    }

    private func pull(client: SupabaseClient, user: UUID, context: ModelContext) async throws {
        let cursor = defaults.string(forKey: cursorKey(user))
        var rows: [Row] = []
        var offset = 0
        while true {
            var query = client.from(Self.table).select()
            if let cursor { query = query.gt("updated_at", value: cursor) }
            let page: [Row] = try await query
                .order("updated_at", ascending: true)
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute()
                .value
            rows.append(contentsOf: page)
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
        guard !rows.isEmpty else { return }

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        for kind in SyncKind.applyOrder {
            let remote = rows.filter { $0.kind == kind.rawValue }
                .map { SyncPlanner.RemoteRecord(id: $0.id, payload: $0.payload, deleted: $0.deleted) }
            guard !remote.isEmpty else { continue }
            apply(remote, kind: kind, user: user, context: context)
        }
        saveQuietly(context)
        if let newest = rows.compactMap(\.updated_at).last {
            defaults.set(newest, forKey: cursorKey(user))
        }
        DiagnosticsLog.event("sync pulled \(rows.count)")
    }

    private func apply(_ remote: [SyncPlanner.RemoteRecord], kind: SyncKind, user: UUID, context: ModelContext) {
        var knownIDs = known(user, kind)
        switch kind {
        case .deck:
            let local = Dictionary((try? context.fetch(FetchDescriptor<Deck>())) ?? [], keyedBy: \.syncID)
            for action in SyncPlanner.plan(remote: remote, local: local.mapValues { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }) {
                switch action {
                case .apply(let id, let payload):
                    guard let p = SyncCoding.decode(DeckPayload.self, from: payload) else { continue }
                    let model = local[id] ?? { let m = Deck(syncID: id); context.insert(m); return m }()
                    model.apply(p)
                    model.lastSyncedHash = SyncCoding.hash(SyncCoding.encode(model.syncPayload))
                    knownIDs.insert(id)
                case .deleteLocal(let id):
                    if let model = local[id] { context.delete(model) }
                    knownIDs.remove(id)
                case .skip(let id):
                    if remote.first(where: { $0.id == id })?.deleted == true { knownIDs.remove(id) } else { knownIDs.insert(id) }
                }
            }
        case .deckEntry:
            let local = Dictionary((try? context.fetch(FetchDescriptor<DeckEntry>())) ?? [], keyedBy: \.syncID)
            let decks = Dictionary((try? context.fetch(FetchDescriptor<Deck>())) ?? [], keyedBy: \.syncID)
            for action in SyncPlanner.plan(remote: remote, local: local.mapValues { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }) {
                switch action {
                case .apply(let id, let payload):
                    guard let p = SyncCoding.decode(DeckEntryPayload.self, from: payload) else { continue }
                    let model = local[id] ?? { let m = DeckEntry(syncID: id); context.insert(m); return m }()
                    model.apply(p)
                    if let deck = decks[p.deckID] { model.deck = deck }
                    model.lastSyncedHash = SyncCoding.hash(SyncCoding.encode(model.syncPayload))
                    knownIDs.insert(id)
                case .deleteLocal(let id):
                    if let model = local[id] { context.delete(model) }
                    knownIDs.remove(id)
                case .skip(let id):
                    if remote.first(where: { $0.id == id })?.deleted == true { knownIDs.remove(id) } else { knownIDs.insert(id) }
                }
            }
        case .collectionItem:
            let local = Dictionary((try? context.fetch(FetchDescriptor<CollectionItem>())) ?? [], keyedBy: \.syncID)
            for action in SyncPlanner.plan(remote: remote, local: local.mapValues { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }) {
                switch action {
                case .apply(let id, let payload):
                    guard let p = SyncCoding.decode(CollectionItemPayload.self, from: payload) else { continue }
                    let model = local[id] ?? { let m = CollectionItem(syncID: id); context.insert(m); return m }()
                    model.apply(p)
                    model.lastSyncedHash = SyncCoding.hash(SyncCoding.encode(model.syncPayload))
                    knownIDs.insert(id)
                case .deleteLocal(let id):
                    if let model = local[id] { context.delete(model) }
                    knownIDs.remove(id)
                case .skip(let id):
                    if remote.first(where: { $0.id == id })?.deleted == true { knownIDs.remove(id) } else { knownIDs.insert(id) }
                }
            }
        case .wishlistItem:
            let local = Dictionary((try? context.fetch(FetchDescriptor<WishlistItem>())) ?? [], keyedBy: \.syncID)
            for action in SyncPlanner.plan(remote: remote, local: local.mapValues { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }) {
                switch action {
                case .apply(let id, let payload):
                    guard let p = SyncCoding.decode(WishlistItemPayload.self, from: payload) else { continue }
                    let model = local[id] ?? { let m = WishlistItem(syncID: id); context.insert(m); return m }()
                    model.apply(p)
                    model.lastSyncedHash = SyncCoding.hash(SyncCoding.encode(model.syncPayload))
                    knownIDs.insert(id)
                case .deleteLocal(let id):
                    if let model = local[id] { context.delete(model) }
                    knownIDs.remove(id)
                case .skip(let id):
                    if remote.first(where: { $0.id == id })?.deleted == true { knownIDs.remove(id) } else { knownIDs.insert(id) }
                }
            }
        }
        setKnown(knownIDs, user, kind)
    }

    private func push(client: SupabaseClient, user: UUID, context: ModelContext) async throws {
        for kind in SyncKind.applyOrder {
            let records = localRecords(kind: kind, context: context)
            let knownIDs = known(user, kind)
            let plan = SyncPlanner.pushes(local: records, knownIDs: knownIDs)
            let rows = plan.upserts.map { UpsertRow(user_id: user, kind: kind.rawValue, id: $0.id, payload: $0.payload, deleted: false) }
                + plan.deletions.map { UpsertRow(user_id: user, kind: kind.rawValue, id: $0, payload: "{}", deleted: true) }
            guard !rows.isEmpty else { continue }

            for chunk in stride(from: 0, to: rows.count, by: Self.pageSize).map({ Array(rows[$0..<min($0 + Self.pageSize, rows.count)]) }) {
                try await client.from(Self.table).upsert(chunk, onConflict: "user_id,kind,id").execute()
            }

            markSynced(plan.upserts, kind: kind, context: context)
            setKnown(knownIDs.union(plan.upserts.map(\.id)).subtracting(plan.deletions), user, kind)
            DiagnosticsLog.event("sync pushed \(kind.rawValue) \(plan.upserts.count) cambios, \(plan.deletions.count) borrados")
        }
        saveQuietly(context)
    }

    private func localRecords(kind: SyncKind, context: ModelContext) -> [SyncPlanner.LocalRecord] {
        switch kind {
        case .deck:
            return ((try? context.fetch(FetchDescriptor<Deck>())) ?? []).filter { !$0.syncID.isEmpty }
                .map { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }
        case .deckEntry:
            return ((try? context.fetch(FetchDescriptor<DeckEntry>())) ?? []).filter { !$0.syncID.isEmpty }
                .map { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }
        case .collectionItem:
            return ((try? context.fetch(FetchDescriptor<CollectionItem>())) ?? []).filter { !$0.syncID.isEmpty }
                .map { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }
        case .wishlistItem:
            return ((try? context.fetch(FetchDescriptor<WishlistItem>())) ?? []).filter { !$0.syncID.isEmpty }
                .map { .init(id: $0.syncID, payload: SyncCoding.encode($0.syncPayload), lastSyncedHash: $0.lastSyncedHash) }
        }
    }

    private func markSynced(_ records: [SyncPlanner.LocalRecord], kind: SyncKind, context: ModelContext) {
        let hashes = Dictionary(records.map { ($0.id, SyncCoding.hash($0.payload)) }, uniquingKeysWith: { a, _ in a })
        switch kind {
        case .deck: for m in (try? context.fetch(FetchDescriptor<Deck>())) ?? [] { if let h = hashes[m.syncID] { m.lastSyncedHash = h } }
        case .deckEntry: for m in (try? context.fetch(FetchDescriptor<DeckEntry>())) ?? [] { if let h = hashes[m.syncID] { m.lastSyncedHash = h } }
        case .collectionItem: for m in (try? context.fetch(FetchDescriptor<CollectionItem>())) ?? [] { if let h = hashes[m.syncID] { m.lastSyncedHash = h } }
        case .wishlistItem: for m in (try? context.fetch(FetchDescriptor<WishlistItem>())) ?? [] { if let h = hashes[m.syncID] { m.lastSyncedHash = h } }
        }
    }

    private func saveQuietly(_ context: ModelContext) {
        isApplyingRemote = true
        try? context.save()
        isApplyingRemote = false
    }
}

private extension Dictionary {
    init(_ values: [Value], keyedBy key: (Value) -> Key) {
        self.init(values.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }
}
