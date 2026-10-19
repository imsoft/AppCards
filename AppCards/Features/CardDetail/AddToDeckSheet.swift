import SwiftUI
import SwiftData

struct AddToDeckSheet: View {
    let detail: CardDetail

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(sort: \Deck.createdAt, order: .reverse) private var allDecks: [Deck]

    @State private var selectedDeck: Deck?
    @State private var newDeckName = ""
    @State private var quantity = 1
    @State private var asAlternative = false
    @State private var note = ""
    @State private var replacesTarget: PersistentIdentifier?
    /// Por defecto se respeta la impresión que elegiste (arte normal, alterno, paralela…).
    @State private var useCheapest = false
    @State private var quoteID: String
    @State private var cheapest: (detail: CardDetail, quote: PriceQuote)?
    @State private var isLoadingCheapest = false

    init(detail: CardDetail) {
        self.detail = detail
        _quoteID = State(initialValue: detail.cheapestQuote()?.id ?? "")
    }

    private var decks: [Deck] { allDecks.filter { $0.game == detail.summary.game } }
    private var canSave: Bool {
        selectedDeck != nil || !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Impresión y precio que se van a guardar.
    private var chosen: (summary: CardSummary, quote: PriceQuote?) {
        if useCheapest, let cheapest { return (cheapest.detail.summary, cheapest.quote) }
        return (detail.summary, detail.quote(id: quoteID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck") {
                    Picker("Deck", selection: $selectedDeck) {
                        Text("Nuevo deck").tag(Deck?.none)
                        ForEach(decks) { deck in
                            Text(deck.name).tag(Optional(deck))
                        }
                    }
                    .accessibilityIdentifier("deck-picker")
                    if selectedDeck == nil {
                        TextField("Nombre del deck nuevo", text: $newDeckName)
                    }
                }

                Section("Cantidad") {
                    Stepper("\(quantity) \(quantity == 1 ? "copia" : "copias")", value: $quantity, in: 1...99)
                }

                Section {
                    Toggle(isOn: $asAlternative.animation()) {
                        Label("Como opción o sustitución", systemImage: "arrow.triangle.swap")
                    }
                    if asAlternative {
                        if let deck = selectedDeck, !deck.mainEntries.isEmpty {
                            SubstituteTargetPicker(candidates: deck.mainEntries, selection: $replacesTarget)
                        }
                        TextField("Nota", text: $note, prompt: Text("Por qué la considerarías"), axis: .vertical)
                            .lineLimit(1...3)
                    }
                } footer: {
                    Text(asAlternative ? "Irá a \"Opciones y sustituciones\" y no contará en el total del deck." : "Contará en el total del deck.")
                }

                Section {
                    HStack(spacing: 12) {
                        CardThumbnail(url: chosen.summary.imageURL ?? chosen.summary.thumbnailURL, width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(chosen.summary.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                PrintingStyleChip(name: chosen.summary.name)
                            }
                            Text(chosen.summary.setLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let quote = chosen.quote {
                                UnitPriceText(unit: quote.reference, currency: quote.currency)
                            }
                        }
                    }
                    if isLoadingCheapest {
                        HStack { Text("Buscando otras impresiones…").foregroundStyle(.secondary); Spacer(); ProgressView() }
                    } else if let cheapest, cheapest.detail.summary.id != detail.summary.id {
                        Toggle(isOn: $useCheapest.animation()) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Usar la impresión más barata")
                                Text("\(cheapest.detail.summary.name) · \(cheapest.detail.summary.setLine)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if let savings { Text("Ahorras \(savings) por copia").font(.caption.weight(.semibold)).foregroundStyle(Theme.positive) }
                            }
                        }
                    }
                    if !useCheapest, detail.pricedQuotes.count > 1 {
                        Picker("Precio", selection: $quoteID) {
                            ForEach(detail.pricedQuotes) { quote in
                                Text("\(quote.title) · \(MoneyFormatter.string(quote.reference ?? 0, currency: quote.currency))")
                                    .tag(quote.id)
                            }
                            Text("Sin precio").tag("")
                        }
                    }
                } header: {
                    Text("Impresión")
                } footer: {
                    if let quote = chosen.quote, let reference = quote.reference {
                        Text("Subtotal: \(model.display(reference * Double(quantity), currency: quote.currency))")
                    }
                }
            }
            .navigationTitle("Agregar a deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") { save() }.disabled(!canSave || isLoadingCheapest)
                }
            }
            .onAppear {
                if selectedDeck == nil { selectedDeck = decks.first }
            }
            .task { await loadCheapest() }
        }
        .sheetSize()
    }

    /// Cuánto ahorras por copia con la impresión más barata, en tu moneda.
    private var savings: String? {
        guard let cheapest, let cheap = cheapest.quote.reference,
              let current = detail.quote(id: quoteID)?.reference ?? detail.cheapestQuote()?.reference,
              let a = model.converted(current, from: detail.quote(id: quoteID)?.currency ?? "USD"),
              let b = model.converted(cheap, from: cheapest.quote.currency), a - b > 0.005 else { return nil }
        return MoneyFormatter.string(a - b, currency: model.displayCurrency)
    }

    private func loadCheapest() async {
        isLoadingCheapest = true
        defer { isLoadingCheapest = false }
        let provider = model.provider(for: detail.summary.game)
        if let found = try? await provider.cheapestPrinting(of: detail) {
            cheapest = found
        } else if let quote = detail.cheapestQuote() {
            cheapest = (detail, quote)
        }
    }

    private func save() {
        let deck: Deck
        if let selectedDeck {
            deck = selectedDeck
        } else {
            deck = Deck(name: newDeckName.trimmingCharacters(in: .whitespaces), game: detail.summary.game)
            context.insert(deck)
        }

        let (summary, quote) = chosen
        let quoteID = quote?.id ?? ""
        if let existing = deck.entryList.first(where: { $0.cardID == summary.id && $0.quoteID == quoteID && $0.isAlternative == asAlternative }) {
            existing.quantity += quantity
            if !note.trimmed.isEmpty { existing.note = note.trimmed }
        } else {
            let entry = DeckEntry(card: summary, quantity: quantity, quote: quote)
            entry.isAlternative = asAlternative
            entry.note = asAlternative ? note.trimmed : ""
            context.insert(entry)
            entry.deck = deck
            if asAlternative, let id = replacesTarget,
               let target = deck.mainEntries.first(where: { $0.persistentModelID == id }) {
                DeckSubstitution.link(entry, to: target)
            }
        }
        try? context.save()
        model.showToast(asAlternative ? "\(summary.name) agregada a opciones de \(deck.name)" : "\(quantity)× \(summary.name) en \(deck.name)")
        dismiss()
    }
}

/// Carga los datos de una carta (por ejemplo, desde Colección) y abre "Agregar a deck".
struct AddToDeckLoader: View {
    let card: CardSummary
    @Environment(AppModel.self) private var model
    @State private var detail: CardDetail?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                AddToDeckSheet(detail: detail)
            } else if let errorMessage {
                ContentUnavailableView("No se pudo cargar la carta", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
            } else {
                ProgressView("Cargando \(card.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            do {
                detail = try await model.provider(for: card.game).detail(providerID: card.providerID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
