import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query private var collection: [CollectionItem]
    @AppStorage("deckViewMode") private var viewMode: DeckViewMode = .list
    @AppStorage("deckSort") private var sort: DeckSort = .missingFirst
    @State private var isUpdating = false
    @State private var updateMessage: String?
    @State private var editing: DeckEntry?
    @State private var showColorSheet = false
    @State private var showRename = false
    @State private var newName = ""
    @State private var dropTarget: DropZone?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    /// Zona sobre la que se está arrastrando una carta.
    enum DropZone { case deck, options }

    private var accent: Color { deck.accentColor }

    private var mainEntries: [DeckEntry] { DeckEntrySorter.sort(deck.mainEntries, by: sort) }
    /// Primero las sustituciones enlazadas, luego las demás opciones.
    private var alternatives: [DeckEntry] {
        DeckEntrySorter.sort(deck.alternativeEntries, by: .name).sorted { a, b in
            let la = DeckSubstitution.target(of: a, in: deck.entryList) != nil
            let lb = DeckSubstitution.target(of: b, in: deck.entryList) != nil
            return la && !lb
        }
    }

    private var ownedInCollection: [String: Int] {
        CollectionMath.owned(collection.filter { $0.game == deck.game }.map(\.line))
    }

    /// Cuántas copias de cada carta cubriría la colección (sugerencia, no reemplaza tu conteo).
    private var coveredByEntry: [PersistentIdentifier: Int] {
        let entries = deck.mainEntries
        let covered = DeckMath.coveredByCollection(lines: entries.map(\.line), owned: ownedInCollection)
        return Dictionary(uniqueKeysWithValues: zip(entries.map(\.persistentModelID), covered))
    }

    private var total: DeckTotal {
        DeckMath.total(lines: deck.lines, in: model.displayCurrency, converter: model.converter)
    }

    private var alternativesTotal: Double {
        alternatives.reduce(0) { sum, entry in
            sum + (entry.unitPrice.flatMap { model.converted($0 * Double(entry.quantity), from: entry.currency) } ?? 0)
        }
    }

    private var collectionCanFill: Bool {
        deck.mainEntries.contains { (coveredByEntry[$0.persistentModelID] ?? 0) > $0.ownedQuantity }
    }

    var body: some View {
        if deck.isGone {
            DeletedPlaceholder(title: "Este deck ya no existe")
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DeckTotalHeader(total: total, colors: deck.accentColors, oldestPrice: deck.entryList.compactMap(\.priceUpdatedAt).min())
                    .floatIn()

                if !deck.entryList.isEmpty {
                    controls
                }

                mainSections

                DeckSectionCard(
                    title: "Opciones y sustituciones",
                    count: alternatives.reduce(0) { $0 + $1.quantity },
                    symbol: "arrow.triangle.swap",
                    tint: .secondary,
                    accent: accent,
                    zone: .options,
                    dropTarget: $dropTarget,
                    onDrop: { moveDropped($0, to: .options) }
                ) {
                    if alternatives.isEmpty {
                        emptyHint("Arrastra aquí una carta del deck, o guarda cartas que podrías incluir. Si una sustituiría a otra, enlázala y haz el cambio con un toque. No cuentan en el total.")
                    } else {
                        rows(alternatives)
                    }
                } footer: {
                    if !alternatives.isEmpty {
                        HStack(spacing: 4) {
                            Text("No cuentan en el total. Comprarlas todas:")
                            MoneyText(amount: alternativesTotal, currency: model.displayCurrency, font: .footnote.weight(.semibold), tagSize: .small)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(ScreenBackground(color: accent))
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $editing) { entry in
            DeckEntryEditSheet(entry: entry, color: accent, inCollection: coveredByEntry[entry.persistentModelID] ?? 0)
        }
        .sheet(isPresented: $showColorSheet) {
            DeckColorSheet(deck: deck)
        }
        .confirmationDialog("¿Eliminar \(deck.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar deck", role: .destructive) {
                SafeDeletion.delete(deck, in: context, after: dismiss)
            }
        } message: {
            Text("Se borran sus \(deck.cardCount) cartas y opciones, también en tu otro dispositivo. Tu colección no cambia.")
        }
        .alert("Nombre del deck", isPresented: $showRename) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") {
                let trimmed = newName.trimmed
                if !trimmed.isEmpty { deck.name = trimmed; try? context.save() }
            }
        }
        .overlay(alignment: .bottom) {
            if let updateMessage {
                Text(updateMessage)
                    .font(.footnote)
                    .padding(10)
                    .background(.thinMaterial, in: Capsule())
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.gentle, value: viewMode)
        .animation(Motion.gentle, value: sort)
        .animation(Motion.spring, value: deck.entryList.map(\.isAlternative))
        .onAppear {
            // Cada carta necesita un identificador estable para poder arrastrarla.
            var changed = false
            for entry in deck.entryList where entry.syncID.isEmpty {
                DeckSubstitution.ensureID(entry)
                changed = true
            }
            if changed { try? context.save() }
        }
    }

    /// Secciones de las cartas del deck según la vista elegida.
    @ViewBuilder
    private var mainSections: some View {
        let dropToDeck: ([String]) -> Bool = { moveDropped($0, to: .deck) }
        if mainEntries.isEmpty {
            DeckSectionCard(title: "Cartas", count: 0, accent: accent, zone: .deck, dropTarget: $dropTarget, onDrop: dropToDeck) {
                emptyHint("Agrega cartas desde Buscar o desde tu Colección, o arrastra aquí una opción.")
            }
        } else {
            switch viewMode {
            case .list:
                DeckSectionCard(title: "Cartas", count: total.totalCards, accent: accent, zone: .deck, dropTarget: $dropTarget, onDrop: dropToDeck) {
                    rows(mainEntries)
                }
            case .grid:
                DeckSectionCard(title: "Cartas", count: total.totalCards, accent: accent, zone: .deck, dropTarget: $dropTarget, onDrop: dropToDeck) {
                    grid(mainEntries).padding(12)
                }
            case .status:
                let missing = mainEntries.filter { $0.missingQuantity > 0 }
                let complete = mainEntries.filter { $0.missingQuantity == 0 }
                if !missing.isEmpty {
                    DeckSectionCard(title: "Me faltan", count: missing.reduce(0) { $0 + $1.missingQuantity }, symbol: "cart.fill",
                                    tint: Theme.negative, accent: accent, zone: .deck, dropTarget: $dropTarget, onDrop: dropToDeck) {
                        rows(missing)
                    }
                }
                if !complete.isEmpty {
                    DeckSectionCard(title: "Ya las tengo", count: complete.reduce(0) { $0 + $1.quantity }, symbol: "checkmark.circle.fill",
                                    tint: Theme.positive, accent: accent, zone: .deck, dropTarget: $dropTarget, onDrop: dropToDeck) {
                        rows(complete)
                    }
                }
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Label(text, systemImage: "hand.draw")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    // MARK: Controles

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Vista", selection: $viewMode) {
                ForEach(DeckViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Picker("Ordenar", selection: $sort) {
                    ForEach(DeckSort.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 32)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .accessibilityLabel("Ordenar: \(sort.title)")
        }
        .padding(.vertical, 4)
    }

    private func sectionHeader(_ title: String, count: Int, symbol: String? = nil, tint: Color? = nil) -> some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint ?? accent) }
            Text(title)
            Text("\(count)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background((tint ?? accent).opacity(0.15), in: Capsule())
                .foregroundStyle(tint ?? accent)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section("Deck") {
                    Button { showColorSheet = true } label: { Label("Color del deck", systemImage: "paintpalette") }
                    Button { newName = deck.name; showRename = true } label: { Label("Cambiar nombre", systemImage: "pencil") }
                }
                Section("Lo que tengo") {
                    Button { fillFromCollection() } label: {
                        Label("Rellenar desde mi colección", systemImage: "square.stack.3d.up.fill")
                    }
                    .disabled(!collectionCanFill)
                    Button {
                        for entry in deck.mainEntries { entry.ownedQuantity = entry.quantity }
                        try? context.save()
                    } label: { Label("Marcar todo como que lo tengo", systemImage: "checkmark.circle") }
                    Button {
                        for entry in deck.mainEntries { entry.ownedQuantity = 0 }
                        try? context.save()
                    } label: { Label("Reiniciar conteo", systemImage: "arrow.counterclockwise") }
                }
                Section("Precios") {
                    Button { Task { await updatePrices(switchToCheapest: false) } } label: {
                        Label("Actualizar precios", systemImage: "arrow.clockwise")
                    }
                    Button { Task { await updatePrices(switchToCheapest: true) } } label: {
                        Label("Cambiar todo a la impresión más barata", systemImage: "arrow.down.circle")
                    }
                }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Eliminar deck", systemImage: "trash")
                    }
                }
            } label: {
                if isUpdating { ProgressView() } else { Image(systemName: "ellipsis.circle") }
            }
            .accessibilityLabel("Opciones del deck")
            .accessibilityIdentifier("deck-menu")
            .disabled(isUpdating)
        }
    }

    // MARK: Contenido

    /// Filas de cartas: tocar abre la hoja, mantener presionado y arrastrar mueve entre secciones.
    private func rows(_ entries: [DeckEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                DeckEntryRow(entry: entry, color: accent)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = entry }
                    .draggable(entry.syncID) {
                        DragPreview(entry: entry, color: accent)
                    }
                    .accessibilityAction(named: entry.isAlternative ? "Mover al deck" : "Mover a opciones") { toggleAlternative(entry) }
                if index < entries.count - 1 {
                    Divider().padding(.leading, 84)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func grid(_ entries: [DeckEntry]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12)], spacing: 16) {
            ForEach(entries) { entry in
                DeckEntryTile(entry: entry, color: accent)
                    .onTapGesture { editing = entry }
                    .draggable(entry.syncID) { DragPreview(entry: entry, color: accent) }
            }
        }
    }

    /// Fondo de las filas cuando arrastras una carta encima de su sección.
    private func dropHighlight(_ zone: DropZone) -> Color {
        dropTarget == zone ? accent.opacity(0.14) : Color(.secondarySystemGroupedBackground)
    }

    /// Soltar cartas en una sección: al deck o a opciones.
    @discardableResult
    private func moveDropped(_ ids: [String], to zone: DropZone) -> Bool {
        DiagnosticsLog.event("deck drop zone=\(zone == .options ? "options" : "deck") ids=\(ids)")
        dropTarget = nil
        let toOptions = zone == .options
        let moved = deck.entryList.filter { ids.contains($0.syncID) && $0.isAlternative != toOptions }
        guard !moved.isEmpty else { return false }
        withAnimation(Motion.spring) {
            for entry in moved {
                entry.isAlternative = toOptions
                if !toOptions { entry.replacesID = "" }
            }
        }
        try? context.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let names = moved.map(\.name).joined(separator: ", ")
        model.showToast(toOptions ? "\(names) a opciones" : "\(names) al deck")
        return true
    }

    private func doSwap(_ option: DeckEntry) {
        guard let target = DeckSubstitution.target(of: option, in: deck.entryList) else { return }
        withAnimation(Motion.spring) { DeckSubstitution.swap(option, in: deck.entryList) }
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.showToast("Cambiaste \(target.name) por \(option.name)")
    }

    private func toggleAlternative(_ entry: DeckEntry) {
        withAnimation(Motion.snappy) { entry.isAlternative.toggle() }
        try? context.save()
        model.showToast(entry.isAlternative ? "\(entry.name) movida a opciones" : "\(entry.name) movida al deck")
    }

    // MARK: Acciones

    private func fillFromCollection() {
        let covered = coveredByEntry
        for entry in deck.mainEntries {
            let fromCollection = covered[entry.persistentModelID] ?? 0
            if fromCollection > entry.ownedQuantity { entry.ownedQuantity = min(fromCollection, entry.quantity) }
        }
        try? context.save()
        model.showToast("Conteo actualizado desde tu colección")
    }

    private func updatePrices(switchToCheapest: Bool) async {
        isUpdating = true
        defer { isUpdating = false }
        let provider = model.provider(for: deck.game)
        var failures = 0
        for entry in deck.entryList {
            do {
                let detail = try await provider.detail(providerID: entry.providerID)
                if switchToCheapest, let cheapest = try await provider.cheapestPrinting(of: detail) {
                    entry.apply(summary: cheapest.detail.summary, quote: cheapest.quote)
                } else if let quote = detail.quote(id: entry.quoteID) ?? detail.cheapestQuote() {
                    entry.apply(quote: quote)
                }
            } catch {
                failures += 1
            }
        }
        try? context.save()
        withAnimation { updateMessage = failures == 0 ? "Precios actualizados" : "\(failures) cartas no se pudieron actualizar" }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation { updateMessage = nil }
    }
}

/// Orden de las cartas dentro de un deck.
enum DeckEntrySorter {
    static func sort(_ entries: [DeckEntry], by sort: DeckSort) -> [DeckEntry] {
        switch sort {
        case .name:
            return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .priceDesc:
            return entries.sorted { ($0.unitPrice ?? -1) > ($1.unitPrice ?? -1) }
        case .set:
            return entries.sorted {
                $0.setName == $1.setName
                    ? $0.number.localizedStandardCompare($1.number) == .orderedAscending
                    : $0.setName.localizedStandardCompare($1.setName) == .orderedAscending
            }
        case .missingFirst:
            return entries.sorted {
                if ($0.missingQuantity > 0) != ($1.missingQuantity > 0) { return $0.missingQuantity > 0 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
}

struct DeckTotalHeader: View {
    let total: DeckTotal
    let colors: [Color]
    let oldestPrice: Date?

    private var foreground: Color { DeckColors.foreground(colors) }
    private var gradientColors: [Color] {
        colors.count > 1 ? colors : [colors.first ?? .gray, (colors.first ?? .gray).opacity(0.7)]
    }

    var body: some View {
        GradientCard(colors: gradientColors, foreground: foreground) {
            VStack(alignment: .leading, spacing: 16) {
                BigAmountView(title: "Te falta comprar", amount: total.missingAmount, currency: total.currency, onGradient: true)
                if total.missingAmount > 0 {
                    StorePriceLine(amount: total.missingAmount, currency: total.currency, onGradient: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(total.ownedCards) de \(total.totalCards) cartas").font(.subheadline.weight(.semibold)).animatedNumber(total.ownedCards)
                        Spacer()
                        Text(total.totalCards == 0 ? "" : "\(Int((Double(total.ownedCards) / Double(total.totalCards) * 100).rounded()))%")
                            .font(.subheadline.weight(.semibold))
                    }
                    ProgressView(value: Double(total.ownedCards), total: Double(max(total.totalCards, 1)))
                        .tint(foreground)
                        .scaleEffect(x: 1, y: 2.2, anchor: .center)
                        .padding(.vertical, 4)
                        .animation(Motion.spring, value: total.ownedCards)
                }
                HStack(spacing: 10) {
                    pill("\(total.ownedCards) tengo", "checkmark.circle.fill")
                    pill("\(total.missingCards) me faltan", "cart.fill")
                }
                Divider().overlay(foreground.opacity(0.45))
                HStack {
                    Text("Deck completo").font(.subheadline).opacity(0.9)
                    Spacer()
                    MoneyText(amount: total.amount, currency: total.currency, font: .headline, onGradient: true)
                }
                StorePriceLine(amount: total.amount, currency: total.currency, onGradient: true, compact: true)
                if total.unpricedCards > 0 || oldestPrice != nil {
                    Text(footnote).font(.caption).opacity(0.85)
                }
            }
        }
    }

    private func pill(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(foreground.opacity(0.22), in: Capsule())
    }

    private var footnote: String {
        var parts: [String] = []
        if total.unpricedCards > 0 { parts.append("\(total.unpricedCards) sin precio") }
        if let oldestPrice { parts.append("precios del \(oldestPrice.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }
}


/// Vista que acompaña al dedo mientras arrastras una carta.
struct DragPreview: View {
    let entry: DeckEntry
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            CardThumbnail(url: entry.imageURL, width: 34)
            Text(entry.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color, lineWidth: 2))
    }
}

/// Sección del deck como tarjeta. Toda la tarjeta acepta cartas arrastradas y se ilumina al pasar encima.
struct DeckSectionCard<Content: View, Footer: View>: View {
    let title: String
    let count: Int
    var symbol: String? = nil
    var tint: Color? = nil
    let accent: Color
    let zone: DeckDetailView.DropZone
    @Binding var dropTarget: DeckDetailView.DropZone?
    let onDrop: ([String]) -> Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(title: String, count: Int, symbol: String? = nil, tint: Color? = nil, accent: Color,
         zone: DeckDetailView.DropZone, dropTarget: Binding<DeckDetailView.DropZone?>, onDrop: @escaping ([String]) -> Bool,
         @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.title = title
        self.count = count
        self.symbol = symbol
        self.tint = tint
        self.accent = accent
        self.zone = zone
        self._dropTarget = dropTarget
        self.onDrop = onDrop
        self.content = content
        self.footer = footer
    }

    private var isTargeted: Bool { dropTarget == zone }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).foregroundStyle(tint ?? accent) }
                Text(title)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background((tint ?? accent).opacity(0.15), in: Capsule())
                    .foregroundStyle(tint ?? accent)
                    .contentTransition(.numericText())
                Spacer()
                if isTargeted {
                    Label("Suelta aquí", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .transition(.opacity)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(accent, style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
                        .opacity(isTargeted ? 1 : 0)
                }
                .scaleEffect(isTargeted ? 1.015 : 1)

            footer()
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            onDrop(ids)
        } isTargeted: { targeted in
            withAnimation(Motion.snappy) {
                if targeted { dropTarget = zone } else if dropTarget == zone { dropTarget = nil }
            }
        }
        .animation(Motion.snappy, value: isTargeted)
        .accessibilityIdentifier("deck-section-\(title)")
    }
}
