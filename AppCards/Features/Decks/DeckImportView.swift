import SwiftUI
import SwiftData

/// Importa un deck de One Piece pegando una lista (OPTCGsim, egman, listas de torneo).
struct DeckImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var text = ""
    @State private var deckName = ""
    @State private var resolved: [ResolvedLine] = []
    @State private var isResolving = false
    @State private var didResolve = false

    struct ResolvedLine: Identifiable {
        let line: DeckListLine
        let detail: CardDetail?
        let quote: PriceQuote?
        var id: String { line.id }
        var isResolved: Bool { detail != nil }
    }

    private var found: [ResolvedLine] { resolved.filter(\.isResolved) }
    private var missing: [ResolvedLine] { resolved.filter { !$0.isResolved } }
    private var totalCards: Int { found.reduce(0) { $0 + $1.line.quantity } }
    private var total: DeckTotal {
        let lines = found.map { DeckLine(canonicalKey: $0.detail?.summary.canonicalKey ?? "", quantity: $0.line.quantity, unitPrice: $0.quote?.reference, currency: $0.quote?.currency ?? "USD") }
        return DeckMath.total(lines: lines, in: model.displayCurrency, converter: model.converter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre del deck", text: $deckName)
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Button("Pegar") {
                            if let pasted = UIPasteboard.general.string { text = pasted }
                        }
                        Spacer()
                        Button {
                            Task { await resolve() }
                        } label: {
                            if isResolving { ProgressView() } else { Text("Revisar lista") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
                    }
                } header: {
                    Text("Lista · One Piece")
                } footer: {
                    Text("Acepta \"4xOP01-003\", \"4 OP01-003\", \"4 Monkey.D.Luffy (OP01-003)\" o solo el nombre. Una carta por línea. Se usa la impresión más barata de cada número.")
                }

                if didResolve {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            MoneyText(amount: total.amount, currency: total.currency, font: .system(.title, design: .rounded).weight(.bold), tagSize: .large)
                            Text("\(totalCards) cartas · \(found.count) encontradas\(missing.isEmpty ? "" : " · \(missing.count) sin encontrar")")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    if !missing.isEmpty {
                        Section("No se encontraron") {
                            ForEach(missing) { item in
                                Text(item.line.raw).font(.callout).foregroundStyle(.red)
                            }
                        }
                    }

                    Section("Cartas") {
                        ForEach(found) { item in
                            if let detail = item.detail {
                                ItemRow(imageURL: detail.summary.thumbnailURL, name: detail.summary.name, subtitle: detail.summary.setLine) {
                                    EmptyView()
                                } trailing: {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("×\(item.line.quantity)").font(.subheadline.weight(.semibold))
                                        if let quote = item.quote, let reference = quote.reference {
                                            PriceLabel(amount: reference * Double(item.line.quantity), currency: quote.currency, style: .compact)
                                        } else {
                                            Text("Sin precio").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importar deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear deck") { createDeck() }
                        .disabled(found.isEmpty || deckName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func resolve() async {
        isResolving = true
        defer { isResolving = false; didResolve = true }
        let lines = DeckListParser.parse(text)
        var output: [ResolvedLine] = []
        for line in lines {
            var number = line.number
            if number == nil, let name = line.name {
                number = try? await model.onePiece.number(forName: name)
            }
            guard let number, let cheapest = try? await model.onePiece.cheapestPrinting(number: number) else {
                output.append(ResolvedLine(line: line, detail: nil, quote: nil))
                continue
            }
            let quote = cheapest.quote.reference == nil ? nil : cheapest.quote
            output.append(ResolvedLine(line: line, detail: cheapest.detail, quote: quote))
        }
        resolved = output
        if deckName.isEmpty, let leader = found.first(where: { $0.detail?.attributes.contains { $0.label == "Tipo" && $0.value == "Leader" } == true }) {
            deckName = leader.detail?.summary.name ?? ""
        }
    }

    private func createDeck() {
        let deck = Deck(name: deckName.trimmingCharacters(in: .whitespaces), game: .onePiece)
        context.insert(deck)
        for item in found {
            guard let detail = item.detail else { continue }
            let entry = DeckEntry(card: detail.summary, quantity: item.line.quantity, quote: item.quote)
            context.insert(entry)
            entry.deck = deck
        }
        try? context.save()
        model.showToast("Deck \"\(deck.name)\" creado con \(totalCards) cartas")
        dismiss()
    }
}
