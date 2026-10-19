import SwiftUI
import SwiftData

struct DecksView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @State private var showNewDeck = false
    @State private var showImport = false
    @State private var deckToDelete: Deck?

    var body: some View {
        AdaptiveSplitView(for: Deck.self) { deck in
            DeckDetailView(deck: deck)
        } empty: {
            SplitPlaceholder(title: "Elige un deck", message: "Toca un deck para ver qué tienes y cuánto te falta comprar.")
        } primary: {
            ScrollView {
                VStack(spacing: 16) {
                    summary
                        .floatIn()
                    if decks.isEmpty {
                        EmptyStateView(
                            title: "Sin decks todavía",
                            message: "Crea un deck o pega una lista de One Piece. Verás cuánto te falta comprar y qué ya tienes.",
                            color: .vaultBlue
                        )
                        .padding(.top, 40)
                    }
                    ForEach(Array(decks.enumerated()), id: \.element.persistentModelID) { index, deck in
                        ItemLink(value: deck) {
                            DeckCard(deck: deck)
                        }
                        .buttonStyle(PressableStyle())
                        .staggeredAppear(index: index + 1)
                        .contextMenu {
                            Button(role: .destructive) { deckToDelete = deck } label: {
                                Label("Eliminar deck", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
                .padding(.bottom, 40)
            }
            .background(ScreenBackground())
            .navigationTitle("Decks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showImport = true } label: { Label("Importar lista", systemImage: "doc.on.clipboard") }
                    Button { showNewDeck = true } label: { Label("Nuevo deck", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showNewDeck) { NewDeckSheet() }
            .confirmationDialog("¿Eliminar \(deckToDelete?.name ?? "deck")?", isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { deckToDelete = nil } }), titleVisibility: .visible) {
                Button("Eliminar deck", role: .destructive) {
                    if let deck = deckToDelete, !deck.isGone {
                        context.delete(deck)
                        try? context.save()
                    }
                    deckToDelete = nil
                }
            } message: {
                Text("Se borran sus cartas y opciones, también en tu otro dispositivo. Tu colección no cambia.")
            }
            .sheet(isPresented: $showImport) { DeckImportView() }
        }
    }
}

extension DecksView {
    private var summary: some View {
        let totals = decks.map { DeckMath.total(lines: $0.lines, in: model.displayCurrency, converter: model.converter) }
        let missing = totals.reduce(0) { $0 + $1.missingAmount }
        let complete = totals.filter { $0.totalCards > 0 && $0.missingCards == 0 }.count
        return SummaryCard(
            title: "Te falta comprar en todos tus decks",
            amount: missing,
            currency: model.displayCurrency,
            pills: [("\(decks.count) \(decks.count == 1 ? "deck" : "decks")", "rectangle.stack.fill"), ("\(complete) \(complete == 1 ? "completo" : "completos")", "checkmark.circle.fill")]
        )
    }
}

/// Tarjeta de deck: franja de color del juego, progreso de "tengo" y lo que falta comprar.
struct DeckCard: View {
    let deck: Deck
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = DeckMath.total(lines: deck.lines, in: model.displayCurrency, converter: model.converter)
        let progress = total.totalCards == 0 ? 0 : Double(total.ownedCards) / Double(total.totalCards)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(deck.name).font(.system(.title3, design: .rounded).weight(.bold)).lineLimit(1)
                            DeckColorDots(colors: deck.accentColors)
                        }
                        HStack(spacing: 8) {
                            GameChip(game: deck.game)
                            Text("\(total.totalCards) \(total.totalCards == 1 ? "carta" : "cartas")").font(.caption).foregroundStyle(.secondary)
                            if !deck.alternativeEntries.isEmpty {
                                Text("· \(deck.alternativeEntries.count) \(deck.alternativeEntries.count == 1 ? "opción" : "opciones")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    DeckCountBadge(count: total.totalCards, colors: deck.accentColors)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(progress >= 1 ? Theme.positive : deck.accentColor)
                        .scaleEffect(x: 1, y: 1.8, anchor: .center)
                        .animation(Motion.spring, value: progress)
                    HStack {
                        Text(progress >= 1 ? "Deck completo" : "\(total.ownedCards) de \(total.totalCards) · tienes \(Int((progress * 100).rounded()))%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(progress >= 1 ? Theme.positive : .secondary)
                        Spacer()
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Te falta comprar").font(.caption).foregroundStyle(.secondary)
                        MoneyText(amount: total.missingAmount, currency: total.currency, font: .system(.title2, design: .rounded).weight(.bold),
                                  color: total.missingAmount > 0 ? Theme.negative : Theme.positive)
                        if total.missingAmount > 0 {
                            StorePriceLine(amount: total.missingAmount, currency: total.currency, compact: true)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Deck completo").font(.caption).foregroundStyle(.secondary)
                        MoneyText(amount: total.amount, currency: total.currency, font: .subheadline.weight(.semibold), tagSize: .small, color: .secondary)
                    }
                }
            }
            .padding(16)
        .background {
            // Sin barrita lateral: el deck se distingue por un fondo suave con sus colores.
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: deck.accentColors.map { $0.opacity(0.16) } + [.clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: deck.accentColors.map { $0.opacity(0.45) }, startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
        }
        .shadow(color: deck.accentColor.opacity(0.14), radius: 10, y: 5)
    }
}

struct NewDeckSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var game: Game = .magic
    @State private var colorHex = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Section("Juego") {
                    SingleGameSelector(game: $game)
                        .listRowInsets(EdgeInsets())
                }
                Section("Color") {
                    DeckColorPicker(colorHex: $colorHex, gameColor: game.color)
                        .padding(.vertical, 6)
                }
            }
            .navigationTitle("Nuevo deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        let deck = Deck(name: name.trimmingCharacters(in: .whitespaces), game: game)
                        deck.colorHex = colorHex
                        context.insert(deck)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .sheetSize()
    }
}

/// Número grande de cartas del deck, con el degradado de sus colores.
struct DeckCountBadge: View {
    let count: Int
    var colors: [Color]

    var body: some View {
        VStack(spacing: 0) {
            Text("\(count)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(count == 1 ? "carta" : "cartas")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .opacity(0.85)
        }
        .frame(minWidth: 56)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(DeckColors.gradient(colors), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(DeckColors.foreground(colors))
        .animation(Motion.snappy, value: count)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(count == 1 ? "carta" : "cartas") en el deck")
    }
}

/// Puntitos con los colores del deck.
struct DeckColorDots: View {
    let colors: [Color]

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
