import SwiftUI
import SwiftData

/// Pantalla de inicio de sesión y creación de cuenta para sincronizar iPhone y iPad.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp
        var id: String { rawValue }
        var title: String { self == .signIn ? "Iniciar sesión" : "Crear cuenta" }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Como candado de la app: sin botón de cerrar.
    var isGate = false

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var awaitingConfirmation = false
    @State private var resendMessage: String?
    @State private var resetMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case name, email, password }

    private var emailLooksValid: Bool {
        let trimmed = email.trimmed
        return trimmed.contains("@") && trimmed.contains(".") && !trimmed.contains(" ")
    }
    private var nameLooksValid: Bool { mode == .signIn || name.trimmed.count >= 2 }
    private var canSubmit: Bool { nameLooksValid && emailLooksValid && password.count >= 6 && !isWorking }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    if awaitingConfirmation {
                        confirmationCard
                    } else {
                        form
                    }
                    benefits
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ScreenBackground())
            .toolbar {
                if !isGate {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: Piezas

    private var hero: some View {
        VStack(spacing: 14) {
            FannedCards(color: .vaultBlue, size: 96)
            Text(awaitingConfirmation ? "Revisa tu correo" : (mode == .signIn ? (isGate ? "Bienvenido a Vault" : "Bienvenido de vuelta") : "Crea tu cuenta"))
                .font(.system(.title, design: .rounded).weight(.bold))
                .contentTransition(.opacity)
            Text(awaitingConfirmation
                 ? "Te mandamos un enlace a \(email.trimmed). Tócalo para confirmar tu cuenta y luego inicia sesión aquí."
                 : "Tu colección, decks y deseos, iguales en tu iPhone y tu iPad.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .animation(Motion.gentle, value: mode)
        .animation(Motion.gentle, value: awaitingConfirmation)
    }

    private var form: some View {
        VStack(spacing: 16) {
            Picker("Modo", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in errorMessage = nil }

            VStack(spacing: 12) {
                if mode == .signUp {
                    field(icon: "person.fill") {
                        TextField("Tu nombre", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focused = .email }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                field(icon: "envelope.fill") {
                    TextField("Correo", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }
                field(icon: "lock.fill") {
                    Group {
                        if showPassword {
                            TextField("Contraseña", text: $password)
                        } else {
                            SecureField("Contraseña", text: $password)
                        }
                    }
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { Task { await submit() } } }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Ocultar contraseña" : "Mostrar contraseña")
                }
                if mode == .signUp {
                    Label("Mínimo 6 caracteres", systemImage: password.count >= 6 ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(password.count >= 6 ? Theme.positive : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.negative)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.negative.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            primaryButton(mode.title, action: { Task { await submit() } })
                .accessibilityIdentifier("auth-submit")
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)

            if mode == .signIn {
                Button("¿Olvidaste tu contraseña?") { Task { await forgotPassword() } }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isWorking)
                    .accessibilityIdentifier("auth-forgot")
                if let resetMessage {
                    Label(resetMessage, systemImage: "envelope.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .animation(Motion.gentle, value: errorMessage)
        .animation(Motion.gentle, value: mode)
    }

    private var confirmationCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: awaitingConfirmation)
            Text("Si el enlace abre una página que no carga, no pasa nada: tu cuenta ya quedó confirmada.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            primaryButton("Ya confirmé, iniciar sesión") {
                awaitingConfirmation = false
                mode = .signIn
                Task { await submit() }
            }
            Button("Reenviar correo") { Task { await resend() } }
                .font(.subheadline.weight(.semibold))
            if let resendMessage {
                Text(resendMessage).font(.caption).foregroundStyle(.secondary)
            }
            Button("Usar otro correo") {
                awaitingConfirmation = false
                mode = .signUp
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit("arrow.triangle.2.circlepath", "Se sincroniza solo", "Al abrir la app y a los pocos segundos de cada cambio.")
            benefit("internaldrive", "No usa tu iCloud", "Tus datos viven en tu propio proyecto de Supabase.")
            benefit("lock.shield", "Solo tú los ves", "Cada cuenta solo puede leer y escribir sus propios datos.")
        }
        .padding(.horizontal, 4)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.vaultBlue.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isWorking { ProgressView().tint(.white) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(LinearGradient(colors: [.vaultBlue, .vaultBlueDark], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Acciones

    private func submit() async {
        focused = nil
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn:
                try await model.sync.signIn(email: email, password: password)
                await finish()
            case .signUp:
                if try await model.sync.signUp(name: name, email: email, password: password) {
                    await finish()
                } else {
                    withAnimation(Motion.gentle) { awaitingConfirmation = true }
                }
            }
        } catch {
            errorMessage = SyncService.friendlyMessage(error)
        }
    }

    private func finish() async {
        password = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let greeting = model.sync.displayName.map { "¡Hola, \($0.components(separatedBy: " ").first ?? $0)!" } ?? "Sesión iniciada"
        model.showToast("\(greeting) Sincronizando…")
        if !isGate { dismiss() }
        await model.sync.sync(context: context)
    }

    private func forgotPassword() async {
        guard emailLooksValid else {
            errorMessage = "Escribe tu correo arriba y vuelve a tocar \"¿Olvidaste tu contraseña?\"."
            focused = .email
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await model.sync.requestPasswordReset(email: email)
            withAnimation { resetMessage = "Te mandamos un correo a \(email.trimmed). Ábrelo en este dispositivo y toca el enlace para poner una contraseña nueva." }
        } catch {
            errorMessage = SyncService.friendlyMessage(error)
        }
    }

    private func resend() async {
        do {
            try await model.sync.resendConfirmation(email: email)
            resendMessage = "Listo, te lo mandamos de nuevo."
        } catch {
            resendMessage = SyncService.friendlyMessage(error)
        }
    }
}

/// Tu cuenta cuando ya iniciaste sesión.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var collection: [CollectionItem]
    @Query private var decks: [Deck]
    @Query private var wishlist: [WishlistItem]
    @State private var confirmSignOut = false
    @State private var showChangePassword = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: model.sync.lastError == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(model.sync.lastError == nil ? Theme.positive : Theme.negative)
                        .symbolEffect(.pulse, isActive: model.sync.isSyncing)
                    if let name = model.sync.displayName {
                        Text(name).font(.system(.title3, design: .rounded).weight(.bold))
                    }
                    if case .signedIn(let email) = model.sync.status {
                        Text(email).font(model.sync.displayName == nil ? .headline : .subheadline)
                            .foregroundStyle(model.sync.displayName == nil ? .primary : .secondary)
                    }
                    Text(statusText).font(.subheadline).foregroundStyle(.secondary)
                    if let error = model.sync.lastError {
                        Text(error).font(.footnote).foregroundStyle(Theme.negative).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Lo que se sincroniza") {
                LabeledContent("Cartas en colección", value: "\(collection.count)")
                LabeledContent("Decks", value: "\(decks.count)")
                LabeledContent("Deseos", value: "\(wishlist.count)")
            }

            Section {
                Button {
                    Task { await model.sync.sync(context: context) }
                } label: {
                    HStack {
                        Label("Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
                        if model.sync.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.sync.isSyncing)
            } footer: {
                Text("Se sincroniza sola al abrir la app, unos segundos después de cada cambio y cada minuto mientras está abierta. El historial de precios se queda en cada dispositivo.")
            }

            Section {
                Button { showChangePassword = true } label: {
                    Label("Cambiar contraseña", systemImage: "key.fill")
                }
                .accessibilityIdentifier("account-change-password")
            }

            Section {
                Button("Cerrar sesión", role: .destructive) { confirmSignOut = true }
            } footer: {
                Text("Al cerrar sesión tus cartas se quedan en este dispositivo, solo dejan de sincronizarse.")
            }
        }
        .sheet(isPresented: $showChangePassword) { NewPasswordView(context: .change) }
        .navigationTitle("Tu cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) {
                Task {
                    await model.sync.signOut()
                    dismiss()
                }
            }
        } message: {
            Text("Tus datos se quedan en este dispositivo, pero necesitarás iniciar sesión de nuevo para usar la app.")
        }
    }

    private var statusText: String {
        if model.sync.isSyncing { return "Sincronizando…" }
        if let last = model.sync.lastSyncAt { return "Sincronizado \(last.formatted(.relative(presentation: .named)))" }
        return "Aún no se ha sincronizado"
    }
}

/// Poner contraseña nueva: al venir del correo de recuperación o desde "Tu cuenta".
struct NewPasswordView: View {
    enum Context { case recovery, change }
    let context: Context

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var show = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var valid: Bool { password.count >= 6 && password == confirm && !isWorking }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        if show {
                            TextField("Contraseña nueva", text: $password)
                            TextField("Repite la contraseña", text: $confirm)
                        } else {
                            SecureField("Contraseña nueva", text: $password)
                            SecureField("Repite la contraseña", text: $confirm)
                        }
                    }
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Toggle("Mostrar contraseña", isOn: $show)
                } header: {
                    Text(context == .recovery ? "Elige tu contraseña nueva" : "Cambiar contraseña")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Mínimo 6 caracteres", systemImage: password.count >= 6 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(password.count >= 6 ? Theme.positive : .secondary)
                        Label("Las dos coinciden", systemImage: !confirm.isEmpty && password == confirm ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(!confirm.isEmpty && password == confirm ? Theme.positive : .secondary)
                        Text("Úsala para entrar en tu iPhone y en tu iPad.")
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.negative) }
                }
            }
            .navigationTitle("Contraseña")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(context == .recovery ? "Después" : "Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isWorking { ProgressView() } else { Text("Guardar").fontWeight(.semibold) }
                    }
                    .disabled(!valid)
                    .accessibilityIdentifier("new-password-save")
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await model.sync.updatePassword(password)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            model.showToast("Contraseña actualizada")
            dismiss()
        } catch {
            errorMessage = SyncService.friendlyMessage(error)
        }
    }
}
