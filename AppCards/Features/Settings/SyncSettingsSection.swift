import SwiftUI

/// Tarjeta de cuenta en Ajustes: abre la pantalla de inicio de sesión o la de tu cuenta.
struct SyncSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var showAuth = false

    var body: some View {
        Section {
            switch model.sync.status {
            case .notConfigured:
                Label("Falta conectar el proyecto de Supabase", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.secondary)
            case .signedOut:
                Button { showAuth = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(LinearGradient(colors: [.vaultBlue, .vaultBlueDark], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sincroniza tu iPhone y iPad").font(.headline).foregroundStyle(.primary)
                            Text("Inicia sesión o crea tu cuenta").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-auth")
                .sheet(isPresented: $showAuth) { AuthView() }
            case .signedIn(let email):
                NavigationLink {
                    AccountView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: model.sync.lastError == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background((model.sync.lastError == nil ? Theme.positive : Theme.negative).gradient,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.sync.displayName ?? email).font(.headline).lineLimit(1)
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Cuenta")
        }
        .task { await model.sync.restoreSession() }
    }

    private var subtitle: String {
        if model.sync.isSyncing { return "Sincronizando…" }
        if model.sync.lastError != nil { return "Hubo un problema al sincronizar" }
        if let last = model.sync.lastSyncAt { return "Sincronizado \(last.formatted(.relative(presentation: .named)))" }
        return "Sesión iniciada"
    }
}
