import SwiftUI
import SwiftData

struct CollectionItemView: View {
    @Bindable var item: CollectionItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var showAddToDeck = false
    @State private var isRefreshing = false
    @State private var hasLocalPrice: Bool
    @State private var localPriceDraft: Double
    @State private var localDateDraft: Date

    init(item: CollectionItem) {
        self.item = item
        _hasLocalPrice = State(initialValue: item.localPrice != nil)
        _localPriceDraft = State(initialValue: item.localPrice ?? 0)
        _localDateDraft = State(initialValue: item.localPriceDate ?? .now)
    }

    var body: some View {
        if item.isGone {
            DeletedPlaceholder()
        } else {
            itemContent
        }
    }

    private var itemContent: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    CardImageButton(url: item.fullImageURL, title: item.name, color: item.game.color, width: 96, fallback: item.artworkFallback)
                    VStack(alignment: .leading, spacing: 6) {
                        GameChip(game: item.game)
                        Text(item.name).font(.system(.title3, design: .rounded).weight(.bold))
                        Text(item.setLine).font(.subheadline).foregroundStyle(.secondary)
                        Text("Toca la imagen para verla completa").font(.caption).foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 4)
                Stepper("Cantidad: \(item.quantity)", value: $item.quantity, in: 1...999)
                Button {
                    showAddToDeck = true
                } label: {
                    Label("Agregar a un deck", systemImage: "plus.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("collection-add-to-deck")
                NavigationLink {
                    CardDetailView(card: item.summary)
                } label: {
                    Label("Ver perfil completo de la carta", systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
            }

            Section {
                if let price = item.referencePrice {
                    LabeledContent(item.referenceVariant) { PriceLabel(amount: price, currency: item.referenceCurrency, style: .compact) }
                    LabeledContent("Total ×\(item.quantity)") { PriceLabel(amount: price * Double(item.quantity), currency: item.referenceCurrency, style: .compact) }
                    StorePriceLine(amount: price, currency: item.referenceCurrency)
                    if let date = item.priceUpdatedAt {
                        Text("Actualizado \(date.formatted(date: .abbreviated, time: .shortened))\(Theme.isStale(date) ? " · precio viejo" : "")")
                            .font(.footnote).foregroundStyle(Theme.isStale(date) ? Theme.stale : .secondary)
                    }
                } else {
                    Text("Sin precio de referencia").foregroundStyle(.secondary)
                }
                Button {
                    Task { await refreshReference() }
                } label: {
                    HStack {
                        Text("Actualizar precio de mercado")
                        if isRefreshing { Spacer(); ProgressView() }
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text("Precio de mercado")
            }

            Section {
                Toggle("Registrar lo que pagué / me cotizaron", isOn: $hasLocalPrice)
                if hasLocalPrice {
                    HStack {
                        TextField("Precio", value: $localPriceDraft, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                        Picker("Moneda", selection: $item.localCurrency) {
                            ForEach(CurrencyConverter.supported, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    TextField("Tienda o vendedor", text: $item.store)
                    DatePicker("Fecha", selection: $localDateDraft, displayedComponents: .date)
                    if let price = item.referencePrice,
                       let reference = model.converted(price, from: item.referenceCurrency),
                       let local = model.converted(localPriceDraft, from: item.localCurrency),
                       let diff = StoreMarkup.percentAbove(market: reference, quoted: local) {
                        let markup = model.storeMarkupPercent
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diff >= 0
                                 ? String(format: "%.0f%% arriba del precio de mercado", diff)
                                 : String(format: "%.0f%% abajo del precio de mercado", -diff))
                                .font(.footnote.weight(.semibold))
                            Text(diff <= 0 ? "Más barato que el mercado. Buen precio."
                                 : diff <= markup ? "Dentro del margen normal de tienda (\(Int(markup))%)."
                                 : "Más caro que el margen normal de tienda (\(Int(markup))%).")
                                .font(.caption)
                        }
                        .foregroundStyle(diff <= 0 ? Theme.positive : (diff <= markup ? Color.secondary : Theme.negative))
                    }
                }
            } header: {
                Text("Precio local (por unidad)")
            } footer: {
                Text("Este precio no se actualiza solo; la fecha te dice qué tan viejo es.")
            }

            Section {
                CardPriceHistorySection(cardID: item.cardID, quoteID: item.referenceQuoteID)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Button("Eliminar de la colección", role: .destructive) {
                    SafeDeletion.delete(item, in: context, after: dismiss)
                }
            }
        }
        .sheet(isPresented: $showAddToDeck) { AddToDeckLoader(card: item.summary) }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: hasLocalPrice) { _, _ in commitLocal() }
        .onChange(of: localPriceDraft) { _, _ in commitLocal() }
        .onChange(of: localDateDraft) { _, _ in commitLocal() }
        .onDisappear { if !item.isGone { try? context.save() } }
    }

    private func commitLocal() {
        if hasLocalPrice {
            item.localPrice = localPriceDraft
            item.localPriceDate = localDateDraft
        } else {
            item.localPrice = nil
            item.localPriceDate = nil
        }
    }

    private func refreshReference() async {
        isRefreshing = true
        defer { isRefreshing = false }
        guard let detail = try? await model.provider(for: item.game).detail(providerID: item.providerID) else { return }
        if let quote = detail.quote(id: item.referenceQuoteID) ?? detail.cheapestQuote() {
            item.apply(quote: quote)
            PriceRefreshService(model: model, context: context).recordPoint(cardID: item.cardID, game: item.game, quote: quote)
            try? context.save()
        }
    }
}
