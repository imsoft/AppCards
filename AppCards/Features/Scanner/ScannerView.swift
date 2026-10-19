import SwiftUI
import SwiftData

/// Apunta la cámara a una carta: lee el número (One Piece), nombre y número (Pokémon) o nombre y set (Magic).
struct ScannerView: View {
    var autoAddToCollection = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @StateObject private var scanner = CameraTextScanner()

    @State private var forcedGame: Game?
    @State private var autoAdd: Bool
    @State private var status = "Apunta a la carta con buena luz"
    @State private var lastHint: ScanHint?
    @State private var result: ScanResult?
    @State private var isResolving = false
    @State private var showOthers = false
    @State private var manualText = ""
    @State private var added: [String] = []

    init(autoAddToCollection: Bool = false) {
        self.autoAddToCollection = autoAddToCollection
        _autoAdd = State(initialValue: autoAddToCollection)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if scanner.permissionDenied {
                    ContentUnavailableView("Sin acceso a la cámara", systemImage: "camera.fill", description: Text("Actívalo en Ajustes > App Cards > Cámara."))
                } else if !scanner.isAvailable {
                    manualFallback
                } else {
                    CameraPreview(session: scanner.session) { layer in scanner.attach(previewLayer: layer) }.ignoresSafeArea()
                    guideOverlay
                }

                VStack {
                    GameSelector(selection: $forcedGame, allowsAll: true)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)

                    Spacer()

                    resultCard
                        .padding()
                }
            }
            .navigationTitle("Escanear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $autoAdd) { Label("+1 automático", systemImage: "plus.square.on.square") }
                        .toggleStyle(.button)
                }
            }
            .sheet(isPresented: $showOthers) {
                if let result {
                    OtherPrintingsSheet(cards: result.others) { chosen in
                        Task { await pick(chosen) }
                    }
                }
            }
            .onAppear {
                scanner.onLines = { lines in handle(lines) }
                scanner.start()
            }
            .onDisappear { scanner.stop() }
        }
    }

    // MARK: Vistas

    private var guideOverlay: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                .aspectRatio(0.716, contentMode: .fit)
                .frame(maxWidth: 260)
            Text(status)
                .font(.footnote.weight(.medium))
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var manualFallback: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("Sin cámara en este dispositivo", systemImage: "camera", description: Text("Escribe el número o nombre de la carta para probar el flujo."))
            HStack {
                TextField("OP01-003, Pikachu 25/102, Sol Ring", text: $manualText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button("Leer") {
                    handle(manualText.components(separatedBy: "\n").map { RecognizedLine(text: $0) })
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualText.isEmpty)
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private var resultCard: some View {
        if isResolving {
            HStack { ProgressView(); Text("Buscando carta…") }
                .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else if let result {
            VStack(spacing: 12) {
                NavigationLink {
                    CardDetailView(card: result.best.summary)
                } label: {
                    HStack(spacing: 12) {
                        CardThumbnail(url: result.best.summary.imageURL ?? result.best.summary.thumbnailURL, width: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.best.summary.name).font(.system(.headline, design: .rounded)).lineLimit(2)
                            Text(result.best.summary.setLine).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            if let quote = result.best.cheapestQuote(), let reference = quote.reference {
                                PriceLabel(amount: reference, currency: quote.currency, style: .compact, alignment: .leading)
                            } else {
                                Text("Sin precio").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text("Toca para ver toda la información")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .foregroundStyle(.primary)
                .accessibilityHint("Abre el perfil completo de la carta")
                HStack {
                    Button {
                        add(result.best)
                    } label: {
                        Label("+1 colección", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.borderedProminent)
                    if !result.others.isEmpty {
                        Button("Otra impresión (\(result.others.count))") { showOthers = true }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("Siguiente") { resume() }
                        .buttonStyle(.bordered)
                }
                if !added.isEmpty {
                    Text("Agregadas: \(added.suffix(3).joined(separator: ", "))\(added.count > 3 ? " y \(added.count - 3) más" : "")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else if !added.isEmpty {
            Text("Agregadas: \(added.count)")
                .font(.footnote).padding(10).background(.regularMaterial, in: Capsule())
        }
    }

    // MARK: Lógica

    private func handle(_ lines: [RecognizedLine]) {
        guard !isResolving, result == nil else { return }
        guard let hint = ScanInterpreter.interpret(lines: lines, forced: forcedGame) else {
            status = "Buscando texto legible…"
            return
        }
        guard hint != lastHint else { return }
        lastHint = hint
        status = describe(hint)
        scanner.isPaused = true
        isResolving = true
        Task {
            defer { isResolving = false }
            do {
                if let found = try await resolver.resolve(hint) {
                    result = found
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if autoAdd { add(found.best) }
                } else {
                    status = "No encontré esa carta. Intenta de nuevo."
                    scanner.isPaused = false
                }
            } catch {
                status = error.localizedDescription
                scanner.isPaused = false
            }
        }
    }

    private var resolver: ScanResolver {
        ScanResolver(scryfall: model.scryfall, tcgdex: model.tcgdex, onePiece: model.onePiece)
    }

    private func describe(_ hint: ScanHint) -> String {
        switch hint {
        case .onePiece(let number): "One Piece \(number)"
        case .pokemon(let names, let number, _): "Pokémon \(names.first ?? "") \(number.map { "#\($0)" } ?? "")"
        case .magic(let names, let set, _): "Magic \(names.first ?? "") \(set.map { "(\($0.uppercased()))" } ?? "")"
        }
    }

    private func add(_ detail: CardDetail) {
        let item = CollectionStore.add(detail, in: context)
        added.append(detail.summary.name)
        model.showToast("\(detail.summary.name) ×\(item.quantity) en colección")
        if autoAdd { resume() }
    }

    private func pick(_ card: CardSummary) async {
        showOthers = false
        isResolving = true
        defer { isResolving = false }
        if let detail = try? await model.provider(for: card.game).detail(providerID: card.providerID), let current = result {
            result = ScanResult(hint: current.hint, best: detail, others: current.others.filter { $0.id != card.id } + [current.best.summary])
        }
    }

    private func resume() {
        result = nil
        lastHint = nil
        status = "Apunta a la siguiente carta"
        scanner.isPaused = false
    }
}

struct OtherPrintingsSheet: View {
    let cards: [CardSummary]
    let onPick: (CardSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(cards) { card in
                Button {
                    onPick(card)
                    dismiss()
                } label: {
                    CardRow(card: card)
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Otra impresión")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .sheetSize(shortOnPhone: true)
    }
}
