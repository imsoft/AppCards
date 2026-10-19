import SwiftUI
import SwiftData

struct WishlistView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \WishlistItem.addedAt, order: .reverse) private var items: [WishlistItem]
    @State private var isChecking = false
    @State private var message: String?

    var body: some View {
        AdaptiveSplitView(for: WishlistItem.self) { item in
            WishlistItemView(item: item)
        } empty: {
            SplitPlaceholder(title: "Elige una carta", message: "Toca una carta de tus deseos para ver su precio y tu meta aquí.", color: .pink)
        } primary: {
            List {
                Section {
                    summary
                        .floatIn()
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                if items.isEmpty {
                    Section {
                        EmptyStateView(
                            title: "Sin cartas en deseos",
                            message: "Toca el corazón en el detalle de una carta y ponle un precio objetivo. Te avisamos cuando baje.",
                            color: .pink
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(items) { item in
                            ItemLink(value: item) {
                                WishlistRow(item: item)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(items[index]) }
                            try? context.save()
                        }
                    } footer: {
                        if let last = model.lastRefreshAt {
                            Text("Última revisión: \(last.formatted(date: .abbreviated, time: .shortened)). Se revisa sola una vez al día en segundo plano y al abrir la app.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ScreenBackground(color: .pink))
            .navigationTitle("Deseos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await checkNow() }
                    } label: {
                        if isChecking { ProgressView() } else { Label("Revisar ahora", systemImage: "arrow.clockwise") }
                    }
                    .disabled(isChecking || items.isEmpty)
                }
            }
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message).font(.footnote).padding(10).background(.thinMaterial, in: Capsule()).padding()
                }
            }
        }
    }

    private var summary: some View {
        let statuses = items.map { PriceRefreshService.status(of: $0, converter: model.converter) }
        let reached = statuses.filter { if case .reached = $0 { return true }; if case .dropped = $0 { return true }; return false }.count
        let total = items.reduce(0.0) { sum, item in
            sum + (item.lastPrice.flatMap { model.converted($0, from: item.lastCurrency) } ?? 0)
        }
        return SummaryCard(
            title: "Comprar todo lo que deseas",
            amount: total,
            currency: model.displayCurrency,
            colors: [.pink, Color.pink.opacity(0.7)],
            pills: [("\(items.count) cartas", "heart.fill"), ("\(reached) en tu precio", "checkmark.circle.fill")]
        )
    }

    private func checkNow() async {
        isChecking = true
        defer { isChecking = false }
        let report = await PriceRefreshService(model: model, context: context).runDaily(force: true)
        withAnimation { message = "\(report.wishlistUpdated) revisadas · \(report.notifications) avisos" }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation { message = nil }
    }
}

struct WishlistRow: View {
    let item: WishlistItem
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = PriceRefreshService.status(of: item, converter: model.converter)
        ItemRow(imageURL: item.imageURL, name: item.name, subtitle: item.setLine) {
            WishlistStatusLabel(status: status, item: item)
        } trailing: {
            VStack(alignment: .trailing, spacing: 4) {
                if let price = item.lastPrice {
                    PriceLabel(amount: price, currency: item.lastCurrency, style: .compact, updatedAt: item.lastCheckedAt)
                }
                if let target = item.targetPrice {
                    HStack(spacing: 3) {
                        Text("meta").font(.caption2).foregroundStyle(.secondary)
                        MoneyText(amount: target, currency: item.targetCurrency, font: .caption2, tagSize: .small, color: .secondary)
                    }
                }
            }
        }
    }
}

struct WishlistStatusLabel: View {
    let status: WishlistRule.Status
    let item: WishlistItem

    var body: some View {
        switch status {
        case .reached:
            Label("Ya está en tu precio", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.positive)
        case .dropped(let change):
            Label(String(format: "Bajó %.0f%%", -change * 100), systemImage: "arrow.down.circle.fill").font(.caption).foregroundStyle(Theme.positive)
        case .waiting:
            Label("Esperando baja", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
        case .unknown:
            Label("Sin precio aún", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WishlistItemView: View {
    @Bindable var item: WishlistItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var hasTarget: Bool
    @State private var targetDraft: Double

    init(item: WishlistItem) {
        self.item = item
        _hasTarget = State(initialValue: item.targetPrice != nil)
        _targetDraft = State(initialValue: item.targetPrice ?? 0)
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
                        Text(item.variantTitle).font(.caption).foregroundStyle(.tertiary)
                        Text("Toca la imagen para verla completa").font(.caption).foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 4)
                NavigationLink {
                    CardDetailView(card: item.summary)
                } label: {
                    Label("Ver perfil completo de la carta", systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
                if let price = item.lastPrice {
                    LabeledContent("Precio actual") { PriceLabel(amount: price, currency: item.lastCurrency, style: .compact, updatedAt: item.lastCheckedAt) }
                }
                if let checked = item.lastCheckedAt {
                    Text("Revisado \(checked.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Avisar al llegar a un precio", isOn: $hasTarget)
                if hasTarget {
                    HStack {
                        TextField("Precio objetivo", value: $targetDraft, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                        Text(item.targetCurrency).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(hasTarget ? "Te avisamos cuando el precio de mercado sea igual o menor." : "Sin objetivo te avisamos con cualquier baja de 5% o más entre revisiones.")
            }
            Section {
                CardPriceHistorySection(cardID: item.cardID, quoteID: item.quoteID)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                Button("Quitar de deseos", role: .destructive) {
                    SafeDeletion.delete(item, in: context, after: dismiss)
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: hasTarget) { _, _ in commit() }
        .onChange(of: targetDraft) { _, _ in commit() }
        .onDisappear { try? context.save() }
    }

    private func commit() {
        item.targetPrice = hasTarget ? targetDraft : nil
    }
}

/// Hoja para agregar una carta a deseos desde el detalle.
struct WishlistTargetSheet: View {
    let detail: CardDetail
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var hasTarget = true
    @State private var target: Double = 0
    @State private var quoteID: String

    init(detail: CardDetail) {
        self.detail = detail
        _quoteID = State(initialValue: detail.cheapestQuote()?.id ?? "")
    }

    private var quote: PriceQuote? { detail.quote(id: quoteID) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Precio a vigilar") {
                    Picker("Precio", selection: $quoteID) {
                        ForEach(detail.pricedQuotes) { quote in
                            Text("\(quote.title) · \(model.display(quote.reference ?? 0, currency: quote.currency))").tag(quote.id)
                        }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                Section {
                    Toggle("Avisar al llegar a", isOn: $hasTarget)
                    if hasTarget {
                        HStack {
                            TextField("Precio objetivo", value: $target, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                            Text(model.displayCurrency).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(hasTarget ? "Te avisamos cuando el precio sea igual o menor." : "Sin objetivo te avisamos con cualquier baja de 5% o más.")
                }
            }
            .navigationTitle("Agregar a deseos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") { save() }.disabled(hasTarget && target <= 0)
                }
            }
            .onAppear {
                if target == 0, let quote, let reference = quote.reference, let converted = model.converted(reference, from: quote.currency) {
                    target = (converted * 0.85 * 100).rounded() / 100
                }
            }
        }
        .sheetSize()
    }

    private func save() {
        let cardID = detail.summary.id
        let descriptor = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.cardID == cardID })
        if let existing = try? context.fetch(descriptor).first {
            existing.targetPrice = hasTarget ? target : nil
            existing.targetCurrency = model.displayCurrency
            if let quote { existing.record(quote: quote) }
        } else {
            let item = WishlistItem(card: detail.summary, quote: quote, targetPrice: hasTarget ? target : nil, targetCurrency: model.displayCurrency)
            context.insert(item)
        }
        try? context.save()
        model.showToast("\(detail.summary.name) en deseos")
        dismiss()
        Task { _ = await PriceRefreshService.requestNotificationPermission() }
    }
}
