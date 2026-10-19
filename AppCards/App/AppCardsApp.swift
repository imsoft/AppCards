import SwiftUI
import SwiftData

@main
struct AppCardsApp: App {
    @State private var model: AppModel
    private let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var syncDebounce: Task<Void, Never>?

    init() {
        let model = AppModel()
        let container = AppCardsApp.makeContainer()
        _model = State(initialValue: model)
        self.container = container
        BackgroundRefresh.register(container: container, model: model)
        Self.applyAppearance()
        // Caché de imágenes: 64 MB en memoria, 512 MB en disco, para que las cartas no se vuelvan a descargar.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    /// Títulos con tipografía redondeada en toda la app.
    static func applyAppearance() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }
        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.font: rounded(17, .bold)]
        nav.largeTitleTextAttributes = [.font: rounded(34, .bold)]
    }

    var body: some Scene {
        WindowGroup {
            AuthGate { RootView() }
                .environment(model)
                .task {
                    await model.sync.restoreSession()
                    await model.sync.sync(context: container.mainContext)
                    await model.refreshRatesIfNeeded()
                    await runDailyRefreshIfNeeded()
                }
                .task(id: scenePhase) {
                    // Mientras la app está abierta: revisa cambios del otro dispositivo cada minuto.
                    guard scenePhase == .active else { return }
                    await model.sync.sync(context: container.mainContext)
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        guard !Task.isCancelled else { break }
                        await model.sync.sync(context: container.mainContext)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    // Cada cambio tuyo se sube a los pocos segundos.
                    guard !model.sync.isApplyingRemote else { return }
                    syncDebounce?.cancel()
                    syncDebounce = Task {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        await model.sync.sync(context: container.mainContext)
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }

    /// Al abrir la app: refresca precios viejos (más de 20 h) de colección y deseos, y guarda la foto del día.
    @MainActor
    private func runDailyRefreshIfNeeded() async {
        if let last = model.lastRefreshAt, Date().timeIntervalSince(last) < 6 * 60 * 60 { return }
        model.isRefreshingPrices = true
        defer { model.isRefreshingPrices = false }
        await PriceRefreshService(model: model, context: container.mainContext).runDaily()
    }

    /// Intenta iCloud (requiere el entitlement de CloudKit firmado con tu team); si no se puede, usa solo local.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Deck.self, DeckEntry.self, CollectionItem.self, PricePoint.self, WishlistItem.self, CollectionSnapshot.self])
        let cloud = ModelConfiguration("AppCards", schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
            resetForUITestsIfNeeded(container)
            return container
        }
        let local = ModelConfiguration("AppCards", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            resetForUITestsIfNeeded(container)
            return container
        }
        // Si la base local no abre (por ejemplo, dañada), se aparta y se crea una nueva.
        // Tus datos vuelven desde Supabase al iniciar sesión.
        DiagnosticsLog.event("database failed to open; moving it aside")
        let url = local.url
        let backup = url.deletingLastPathComponent().appendingPathComponent("AppCards-dañada-\(Int(Date().timeIntervalSince1970)).store")
        try? FileManager.default.moveItem(at: url, to: backup)
        for suffix in ["-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            return container
        }
        // Último recurso: en memoria, para que la app abra de todos modos.
        let memory = ModelConfiguration("AppCards", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return (try? ModelContainer(for: schema, configurations: [memory])) ?? {
            preconditionFailure("SwiftData no pudo crear ni una base en memoria")
        }()
    }

    /// Las pruebas de interfaz pueden arrancar con la app vacía (solo en compilaciones de desarrollo).
    private static func resetForUITestsIfNeeded(_ container: ModelContainer) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-uiTestsResetData") else { return }
        let context = ModelContext(container)
        try? context.delete(model: DeckEntry.self)
        try? context.delete(model: Deck.self)
        try? context.delete(model: CollectionItem.self)
        try? context.delete(model: WishlistItem.self)
        try? context.delete(model: PricePoint.self)
        try? context.delete(model: CollectionSnapshot.self)
        try? context.save()
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTab: String = RootView.initialTab

    /// `-tab collection` como argumento de lanzamiento abre esa pestaña (útil para capturas y pruebas).
    private static var initialTab: String {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-tab"), index + 1 < args.count { return args[index + 1] }
        return "search"
    }

    var body: some View {
        // En iPhone son pestañas abajo; en iPad se vuelve barra lateral (o pestañas arriba).
        TabView(selection: $selectedTab) {
            Tab("Buscar", systemImage: "magnifyingglass", value: "search") { SearchView() }
            Tab("Colección", systemImage: "square.stack.3d.up", value: "collection") { CollectionView() }
            Tab("Decks", systemImage: "rectangle.stack", value: "decks") { DecksView() }
            Tab("Deseos", systemImage: "heart", value: "wishlist") { WishlistView() }
            Tab("Ajustes", systemImage: "gearshape", value: "settings") { SettingsView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(LinearGradient(colors: [.vaultBlue, .vaultBlueDark], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .shadow(color: .vaultBlue.opacity(0.4), radius: 10, y: 5)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.toast)
        .tint(contextColor)
        .animation(.easeInOut(duration: 0.3), value: selectedTab)
        .animation(.easeInOut(duration: 0.3), value: model.searchGame)
        .animation(.easeInOut(duration: 0.3), value: model.collectionGame)
    }

    /// Color de la pantalla activa: tiñe la pestaña seleccionada y los botones.
    private var contextColor: Color {
        switch selectedTab {
        case "search": model.searchGame.color
        case "collection": model.collectionGame?.color ?? .vaultBlue
        case "wishlist": .pink
        default: .vaultBlue
        }
    }
}

/// Sin sesión iniciada solo se ve la pantalla de entrar o crear cuenta.
/// Si el proyecto de Supabase no está configurado (desarrollo), la app abre normal.
struct AuthGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var showNewPassword = false
    @State private var linkError: String?

    /// Las pruebas de interfaz pueden saltarse el candado (solo en compilaciones de desarrollo).
    private var skipForTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTestsSkipAuth")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            switch model.sync.status {
            case .signedIn, .notConfigured:
                content()
                    .transition(.opacity)
            case .signedOut:
                if skipForTests {
                    content()
                } else if model.sync.isRestoring {
                    launchScreen
                } else {
                    AuthView(isGate: true)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.sync.status)
        .animation(.easeInOut(duration: 0.3), value: model.sync.isRestoring)
        // Enlaces de los correos de Supabase: confirmar cuenta o cambiar contraseña.
        .onOpenURL { url in
            guard url.scheme == SyncService.callbackURL.scheme else { return }
            Task { await handle(url) }
        }
        .sheet(isPresented: $showNewPassword) { NewPasswordView(context: .recovery) }
        .alert("No se pudo abrir el enlace", isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linkError ?? "")
        }
    }

    private func handle(_ url: URL) async {
        do {
            switch try await model.sync.handleAuthLink(url) {
            case .passwordRecovery:
                showNewPassword = true
            case .signedIn:
                let greeting = model.sync.displayName.map { "¡Cuenta confirmada, \($0.components(separatedBy: " ").first ?? $0)!" } ?? "¡Cuenta confirmada!"
                model.showToast(greeting)
                await model.sync.sync(context: context)
            }
        } catch {
            linkError = SyncService.friendlyMessage(error)
        }
    }

    private var launchScreen: some View {
        VStack(spacing: 16) {
            FannedCards(color: .vaultBlue, size: 96)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScreenBackground())
    }
}
