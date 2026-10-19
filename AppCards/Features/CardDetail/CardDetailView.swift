import SwiftUI
import SwiftData

struct CardDetailView: View {
    let card: CardSummary

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var collection: [CollectionItem]
    @Query private var wishlist: [WishlistItem]
    @State private var detail: CardDetail?
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var showWishlistSheet = false
    @State private var showZoom = false

    private var owned: Int { OwnershipIndex(collection: collection, wishlist: wishlist).owned(card) }
    private var wished: Bool { wishlist.contains { $0.cardID == card.id } }

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad: la carta se queda fija a la izquierda y solo la información se desplaza.
                HStack(alignment: .top, spacing: 32) {
                    VStack {
                        heroImage
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        Spacer(minLength: 0)
                    }
                    .frame(width: 400)
                    .padding(.top, Theme.screenPadding + 8)
                    .padding(.leading, Theme.screenPadding + 8)

                    ScrollView {
                        infoColumn
                            .frame(maxWidth: 620, alignment: .leading)
                            .padding(.vertical, Theme.screenPadding + 8)
                            .padding(.trailing, Theme.screenPadding + 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: Theme.sectionSpacing) {
                        heroImage
                        infoColumn
                            .padding(.horizontal, Theme.screenPadding)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .background(ScreenBackground(color: card.game.color))
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showWishlistSheet = true } label: {
                    Label("Deseos", systemImage: wished ? "heart.fill" : "heart")
                        .symbolEffect(.bounce, value: wished)
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(detail == nil)
                Button {
                    guard let detail else { return }
                    let item = CollectionStore.add(detail, in: context)
                    model.showToast("\(card.name) ×\(item.quantity) en colección")
                } label: {
                    Label("+1 colección", systemImage: "plus.square.on.square")
                }
                .disabled(detail == nil)
                Button { showAddSheet = true } label: {
                    Label("Agregar a deck", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(detail == nil)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            if let detail { AddToDeckSheet(detail: detail) }
        }
        .sheet(isPresented: $showWishlistSheet) {
            if let detail { WishlistTargetSheet(detail: detail) }
        }
        .fullScreenCover(isPresented: $showZoom) {
            CardViewer(url: ImageQuality.best(card.imageURL ?? card.thumbnailURL, size: .full), title: card.name, color: card.game.color, fallback: ArtworkFallback(card)) {
                showZoom = false
            }
        }
        .onChange(of: showZoom) { _, value in DiagnosticsLog.event("detail showZoom=\(value)") }
        .task { await load() }
        .onAppear { DiagnosticsLog.event("detail appeared card=\(card.id)") }
    }


    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            headline
                .floatIn(delay: 0.08)
            if let detail {
                PricesSection(prices: detail.prices).floatIn(delay: 0.05)
                CardPriceHistorySection(cardID: card.id, quoteID: detail.cheapestQuote()?.id).floatIn(delay: 0.1)
                AttributesSection(attributes: detail.attributes).floatIn(delay: 0.15)
                if let text = detail.text, !text.isEmpty {
                    SectionCard(title: "Texto", systemImage: "text.alignleft", tint: .gray) {
                        Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let url = detail.externalURL {
                    Link(destination: url) {
                        Label("Ver en \(card.game.sourceName)", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView("No se pudo cargar", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("Cargando precios…").frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    private var heroImage: some View {
        // Todo el bloque es un botón: siempre recibe el toque, con imagen cargada o no.
        Button(action: openViewer) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: ImageQuality.best(card.imageURL ?? card.thumbnailURL, size: .full), fallback: ArtworkFallback(card)) { phase in
                    if let image = phase.image {
                        image.resizable().interpolation(.high).antialiased(true).scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.25)).aspectRatio(0.716, contentMode: .fit).overlay { ProgressView().tint(.white) }
                    }
                }
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                .floatIn()
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    if owned > 0 {
                        Label("Tienes ×\(owned)", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.positive, in: Capsule())
                            .foregroundStyle(.white)
                            .animatedNumber(owned)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .padding(9)
                        .background(.regularMaterial, in: Circle())
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .animation(Motion.spring, value: owned > 0)
            }
            // El fondo mide lo mismo que la carta (no se estira), así en iPad queda arriba y fija.
            .background(card.game.gradient)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Imagen de \(card.name)")
        .accessibilityHint("Abre la carta en pantalla completa")
        .accessibilityIdentifier("card-hero-image")
    }

    private func openViewer() {
        DiagnosticsLog.event("detail hero tapped card=\(card.id)")
        showZoom = true
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                GameChip(game: card.game)
                if let rarity = card.rarity {
                    Text(rarity)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            Text(card.name).font(.title.bold())
            Text(card.setLine).font(.subheadline).foregroundStyle(.secondary)
            if let quote = detail?.cheapestQuote(), let reference = quote.reference {
                GradientCard(colors: [card.game.color, card.game.color.opacity(0.7)], foreground: card.game.onColor) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Precio más bajo · \(quote.title)").font(.subheadline.weight(.medium)).opacity(0.9)
                        let shown = model.converted(reference, from: quote.currency).map { ($0, model.displayCurrency) } ?? (reference, quote.currency)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            MoneyText(amount: shown.0, currency: shown.1, font: .system(.largeTitle, design: .rounded).weight(.bold), tagSize: .large, onGradient: true)
                                .minimumScaleFactor(0.6).lineLimit(1)
                            if shown.1 != quote.currency {
                                MoneyText(amount: reference, currency: quote.currency, font: .subheadline, tagSize: .small, onGradient: true)
                                    .opacity(0.9)
                            }
                        }
                        StorePriceLine(amount: reference, currency: quote.currency, onGradient: true)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            let loaded = try await model.provider(for: card.game).detail(providerID: card.providerID)
            detail = loaded
            let service = PriceRefreshService(model: model, context: context)
            for quote in loaded.pricedQuotes { service.recordPoint(cardID: card.id, game: card.game, quote: quote) }
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PricesSection: View {
    let prices: [PriceQuote]
    @Environment(AppModel.self) private var model

    private var visible: [PriceQuote] { prices.filter { !$0.isEmpty } }

    var body: some View {
        SectionCard(title: "Precios", systemImage: "tag.fill", tint: Theme.positive) {
            if visible.isEmpty {
                Text("Sin precios disponibles para esta impresión.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 14) {
                    ForEach(visible) { quote in
                        PriceQuoteRow(quote: quote)
                        if quote.id != visible.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

struct PriceQuoteRow: View {
    let quote: PriceQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(quote.title).font(.subheadline.weight(.semibold))
                Spacer()
                if let reference = quote.reference {
                    PriceLabel(amount: reference, currency: quote.currency, style: .regular)
                }
            }
            if let reference = quote.reference {
                StorePriceLine(amount: reference, currency: quote.currency, compact: true)
            }
            HStack(spacing: 12) {
                metric("Mercado", quote.market)
                metric("Bajo", quote.low)
                metric("Medio", quote.mid)
                metric("Alto", quote.high)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: Double?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                Text(MoneyFormatter.string(value, currency: quote.currency)).monospacedDigit()
            }
        }
    }
}

struct AttributesSection: View {
    let attributes: [CardAttribute]

    var body: some View {
        if !attributes.isEmpty {
            SectionCard(title: "Detalles", systemImage: "info.circle.fill", tint: .vaultBlue) {
                VStack(spacing: 10) {
                    ForEach(attributes) { attribute in
                        HStack(alignment: .top) {
                            Text(attribute.label).foregroundStyle(.secondary)
                            Spacer()
                            Text(attribute.value).multilineTextAlignment(.trailing)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
