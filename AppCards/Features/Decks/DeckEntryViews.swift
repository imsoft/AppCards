import SwiftUI
import SwiftData

/// Anillo de progreso "tengo / quiero". Lleno y verde cuando ya tienes todas.
struct OwnershipRing: View {
    let owned: Int
    let wanted: Int
    var color: Color
    var size: CGFloat = 34

    private var progress: Double { wanted == 0 ? 0 : min(Double(owned) / Double(wanted), 1) }
    private var complete: Bool { wanted > 0 && owned >= wanted }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(complete ? Theme.positive : color, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if complete {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.38, weight: .heavy))
                    .foregroundStyle(Theme.positive)
            } else {
                Text("\(owned)/\(wanted)")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.spring, value: owned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(complete ? "Completa, tienes \(owned)" : "Tienes \(owned) de \(wanted)")
    }
}

/// Fila de una carta del deck: imagen, datos, precio de lo que falta y contador para subir o bajar lo que tienes.
struct DeckEntryRow: View {
    @Bindable var entry: DeckEntry
    var color: Color
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CardImageButton(url: entry.imageURL, title: entry.name, color: color, width: 54, fallback: entry.artworkFallback)
                .overlay(alignment: .topLeading) {
                    CopiesBadge(count: entry.quantity, color: color)
                        .offset(x: -8, y: -8)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                Text(entry.setLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                PrintingStyleChip(name: entry.name)
                if let target = DeckSubstitution.target(of: entry, in: entry.deck?.entryList ?? []) {
                    SubstitutionSummary(option: entry, target: target, compact: true)
                } else if !entry.isAlternative, !DeckSubstitution.substitutes(for: entry, in: entry.deck?.entryList ?? []).isEmpty {
                    Label("Tiene sustituto en opciones", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !entry.note.isEmpty {
                    Label(entry.note, systemImage: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                priceLine
            }

            Spacer(minLength: 4)

            counter
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var priceLine: some View {
        if let unit = entry.unitPrice {
            let pending = entry.missingQuantity
            VStack(alignment: .leading, spacing: 1) {
                if pending > 1 {
                    // Total de lo que falta en tu moneda y, abajo, el precio por unidad.
                    PriceLabel(amount: unit * Double(pending), currency: entry.currency, style: .compact,
                               updatedAt: entry.priceUpdatedAt, alignment: .leading, showsOriginal: false)
                    UnitPriceText(unit: unit, currency: entry.currency)
                } else {
                    UnitPriceText(unit: unit, currency: entry.currency)
                        .opacity(pending == 0 ? 0.5 : 1)
                }
            }
        } else {
            Text("Sin precio").font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// − anillo + : sube o baja cuántas tienes sin abrir nada.
    private var counter: some View {
        HStack(spacing: 6) {
            stepButton("minus", enabled: entry.ownedQuantity > 0) { entry.ownedQuantity -= 1 }
            OwnershipRing(owned: entry.ownedQuantity, wanted: entry.quantity, color: color)
            stepButton("plus", enabled: entry.ownedQuantity < entry.quantity) { entry.ownedQuantity += 1 }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            try? context.save()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 26, height: 26)
                .background(Color(.tertiarySystemFill), in: Circle())
                .foregroundStyle(enabled ? color : .secondary)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Tengo una más" : "Tengo una menos")
    }
}

/// Carta del deck en la vista de cuadrícula.
struct DeckEntryTile: View {
    let entry: DeckEntry
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: entry.imageURL, fallback: entry.artworkFallback) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().interpolation(.high).scaledToFit()
                case .failure:
                    MissingArtwork(name: entry.name, number: entry.number, color: color).aspectRatio(0.716, contentMode: .fit)
                default:
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary).aspectRatio(0.716, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(entry.missingQuantity == 0 ? 1 : 0.92)
            .shadow(color: color.opacity(0.3), radius: 5, y: 3)
            .overlay(alignment: .topTrailing) {
                OwnershipRing(owned: entry.ownedQuantity, wanted: entry.quantity, color: color, size: 30)
                    .padding(4)
                    .background(.regularMaterial, in: Circle())
                    .padding(4)
            }
            .overlay(alignment: .topLeading) {
                CopiesBadge(count: entry.quantity, color: color, large: true)
                    .padding(6)
            }
            Text(entry.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            PrintingStyleChip(name: entry.name)
            if let unit = entry.unitPrice, entry.missingQuantity > 0 {
                PriceLabel(amount: unit * Double(entry.missingQuantity), currency: entry.currency, style: .compact, alignment: .leading)
                    .scaleEffect(0.9, anchor: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Editar una carta del deck: cantidades, nota, si es opción, impresión.
struct DeckEntryEditSheet: View {
    @Bindable var entry: DeckEntry
    var color: Color
    var inCollection: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    private var allEntries: [DeckEntry] { entry.deck?.entryList ?? [] }
    private var mainEntries: [DeckEntry] {
        (entry.deck?.mainEntries ?? []).filter { $0 !== entry }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// La carta del deck elegida se traduce a `replacesID`.
    private var replacesBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { DeckSubstitution.target(of: entry, in: allEntries)?.persistentModelID },
            set: { id in
                let target = mainEntries.first { $0.persistentModelID == id }
                DeckSubstitution.link(entry, to: target)
            }
        )
    }

    var body: some View {
        if entry.isGone {
            DeletedPlaceholder()
        } else {
            sheetContent
        }
    }

    private var sheetContent: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        CardImageButton(url: entry.fullImageURL, title: entry.name, color: color, width: 88, fallback: entry.artworkFallback)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.name).font(.system(.title3, design: .rounded).weight(.bold))
                            Text(entry.setLine).font(.subheadline).foregroundStyle(.secondary)
                            Text(entry.variantTitle).font(.caption).foregroundStyle(.tertiary)
                            PrintingStyleChip(name: entry.name)
                            if let unit = entry.unitPrice {
                                PriceLabel(amount: unit, currency: entry.currency, style: .compact, updatedAt: entry.priceUpdatedAt, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    NavigationLink {
                        PrintingChoiceList(entry: entry)
                    } label: {
                        Label(entry.quantity > 1 ? "Cambiar o separar impresión" : "Cambiar impresión", systemImage: "rectangle.on.rectangle.angled")
                    }
                    .accessibilityIdentifier("change-printing")
                }

                if let target = DeckSubstitution.target(of: entry, in: allEntries) {
                    Section {
                        SubstitutionSummary(option: entry, target: target)
                        Button {
                            DeckSubstitution.swap(entry, in: allEntries)
                            try? context.save()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            model.showToast("Cambiaste \(target.name) por \(entry.name)")
                            dismiss()
                        } label: {
                            Label("Hacer el cambio", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .accessibilityIdentifier("do-substitution")
                    } footer: {
                        Text("\(entry.name) entra al deck y \(target.name) pasa a opciones, por si te arrepientes.")
                    }
                }

                Section {
                    Stepper(value: $entry.quantity, in: 1...99) {
                        LabeledContent("Quiero", value: "\(entry.quantity)")
                    }
                    Stepper(value: $entry.ownedQuantity, in: 0...entry.quantity) {
                        HStack {
                            Text("Tengo")
                            Spacer()
                            OwnershipRing(owned: entry.ownedQuantity, wanted: entry.quantity, color: color, size: 30)
                        }
                    }
                    .accessibilityIdentifier("owned-stepper")
                    if inCollection > entry.ownedQuantity {
                        Button("Usar las \(min(inCollection, entry.quantity)) de mi colección") {
                            entry.ownedQuantity = min(inCollection, entry.quantity)
                        }
                    }
                } header: {
                    Text("Copias")
                } footer: {
                    if entry.isAlternative {
                        Text("Si haces el cambio, la carta entra al deck con estas copias.")
                    }
                }

                Section {
                    Toggle(isOn: $entry.isAlternative.animation()) {
                        Label("Opción o sustitución", systemImage: "arrow.triangle.swap")
                    }
                    if entry.isAlternative {
                        SubstituteTargetPicker(candidates: mainEntries, selection: replacesBinding)
                    }
                    TextField("Nota", text: $entry.note, prompt: Text("Por qué la considerarías"), axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    Text(entry.isAlternative
                         ? "Las opciones no cuentan en el total. Si eliges a quién sustituye, puedes hacer el cambio con un toque; la carta que sale queda en opciones por si te arrepientes."
                         : "Las opciones no cuentan en el total del deck; aparecen en su propia sección.")
                }

                Section {
                    Button("Quitar del deck", role: .destructive) {
                        SafeDeletion.delete(entry, in: context, after: dismiss)
                    }
                }
            }
            .navigationTitle("Carta del deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { try? context.save(); dismiss() }
                }
            }
            .onChange(of: entry.quantity) { _, value in
                if entry.ownedQuantity > value { entry.ownedQuantity = value }
            }
            .tint(color)
        }
        .sheetSize()
    }
}

/// Elegir el color de un deck.
struct DeckColorSheet: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(deck.accentGradient)
                        .frame(height: 90)
                        .overlay(alignment: .leading) {
                            Text(deck.name)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(deck.accentForeground)
                                .padding(.horizontal, 20)
                        }
                        .animation(Motion.gentle, value: deck.colorHex)
                    DeckColorPicker(colorHex: $deck.colorHex, gameColor: deck.game.color)
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle("Color del deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { try? context.save(); dismiss() }
                }
            }
        }
        .sheetSize(shortOnPhone: true)
    }
}

/// Paleta de colores: hasta 3, en el orden en que los tocas. La primera opción regresa al color del juego.
struct DeckColorPicker: View {
    @Binding var colorHex: String
    var gameColor: Color

    private var selected: [String] { DeckColors.hexes(colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 14)], spacing: 14) {
                swatch(color: gameColor, selected: selected.isEmpty, label: "Color del juego", symbol: "gamecontroller.fill") { colorHex = "" }
                ForEach(DeckPalette.colors, id: \.hex) { item in
                    let order = selected.firstIndex(of: item.hex).map { $0 + 1 }
                    swatch(color: Color(hex: item.hex) ?? .gray, selected: order != nil, label: item.name, order: order) {
                        colorHex = DeckColors.toggle(item.hex, in: colorHex)
                    }
                }
            }
            Text(selected.isEmpty ? "Toca hasta 3 colores para los decks de varios colores."
                 : "\(selected.count) de \(DeckColors.maxColors) colores. Toca uno elegido para quitarlo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func swatch(color: Color, selected: Bool, label: String, symbol: String? = nil, order: Int? = nil, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.snappy) { action() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            ZStack {
                Circle().fill(color.gradient)
                if let symbol {
                    Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(color.readableForeground)
                }
                if selected {
                    Circle().strokeBorder(Color.primary, lineWidth: 3).padding(-5)
                }
                if let order {
                    Text("\(order)")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(color.readableForeground)
                }
            }
            .frame(width: 40, height: 40)
            .padding(5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(order.map { "\(label), color \($0)" } ?? label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "⇄ Sustituye a Luffy · +$20 MXN": a quién reemplaza y cuánto cambia el costo.
/// En la versión completa también muestra el precio por unidad de las dos cartas.
struct SubstitutionSummary: View {
    let option: DeckEntry
    let target: DeckEntry
    var compact = false
    @Environment(AppModel.self) private var model

    private var difference: Double? {
        DeckSubstitution.costDifference(option: option, target: target) { amount, currency in
            model.converted(amount, from: currency)
        }
    }

    private var differenceText: some View {
        Group {
            if let difference {
                Text(difference > 0.005 ? "+\(MoneyFormatter.string(difference, currency: model.displayCurrency))"
                     : difference < -0.005 ? "−\(MoneyFormatter.string(-difference, currency: model.displayCurrency))"
                     : "mismo costo")
                    .fontWeight(.semibold)
                    .foregroundStyle(difference > 0.005 ? Theme.negative : (difference < -0.005 ? Theme.positive : .secondary))
                    .lineLimit(1)
            }
        }
    }

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                Text("Sustituye a \(target.name)").lineLimit(1)
                differenceText
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                line("Sale", entry: target, symbol: "arrow.up.right.circle", tint: Theme.negative)
                line("Entra", entry: option, symbol: "arrow.down.left.circle", tint: Theme.positive)
                HStack {
                    Text("Diferencia en el deck").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    differenceText.font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func line(_ title: String, entry: DeckEntry, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            CardThumbnail(url: entry.imageURL, width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title): \(entry.name)").font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    UnitPriceText(unit: entry.unitPrice, currency: entry.currency)
                    Text("× \(entry.quantity)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Precio por unidad en tu moneda: "$120.00 MXN c/u".
struct UnitPriceText: View {
    let unit: Double?
    let currency: String
    @Environment(AppModel.self) private var model

    var body: some View {
        if let unit {
            let shown = model.converted(unit, from: currency).map { ($0, model.displayCurrency) } ?? (unit, currency)
            HStack(spacing: 3) {
                MoneyText(amount: shown.0, currency: shown.1, font: .caption.weight(.semibold), tagSize: .small)
                Text("c/u").font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Text("Sin precio").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// Fila del formulario para elegir a qué carta del deck sustituye; abre una lista con imágenes.
struct SubstituteTargetPicker: View {
    let candidates: [DeckEntry]
    @Binding var selection: PersistentIdentifier?

    private var selected: DeckEntry? { candidates.first { $0.persistentModelID == selection } }

    var body: some View {
        NavigationLink {
            SubstituteTargetList(candidates: candidates, selection: $selection)
        } label: {
            HStack(spacing: 10) {
                Label("Sustituye a", systemImage: "arrow.left.arrow.right")
                Spacer()
                if let selected {
                    CardThumbnail(url: selected.imageURL, width: 26)
                    Text(selected.name).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Ninguna").foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("substitute-picker")
    }
}

struct SubstituteTargetList: View {
    let candidates: [DeckEntry]
    @Binding var selection: PersistentIdentifier?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [DeckEntry] {
        let needle = query.trimmed.lowercased()
        let sorted = candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return needle.isEmpty ? sorted : sorted.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        List {
            Button {
                selection = nil
                dismiss()
            } label: {
                HStack {
                    Label("Ninguna, solo es una opción", systemImage: "circle.dashed")
                    Spacer()
                    if selection == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .foregroundStyle(.primary)
            ForEach(filtered) { entry in
                Button {
                    selection = entry.persistentModelID
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        CardThumbnail(url: entry.imageURL, width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name).font(.body.weight(.semibold)).lineLimit(2)
                            Text(entry.setLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            UnitPriceText(unit: entry.unitPrice, currency: entry.currency)
                        }
                        Spacer()
                        Text("×\(entry.quantity)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        if selection == entry.persistentModelID {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .searchable(text: $query, prompt: "Buscar en el deck")
        .navigationTitle("Sustituye a")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Cuántas copias de la carta lleva el deck: "×4".
struct CopiesBadge: View {
    let count: Int
    var color: Color
    var large = false

    var body: some View {
        Text("×\(count)")
            .font(.system(large ? .subheadline : .caption, design: .rounded).weight(.heavy))
            .monospacedDigit()
            .contentTransition(.numericText())
            .padding(.horizontal, large ? 8 : 6)
            .padding(.vertical, large ? 3 : 2)
            .background(color, in: Capsule())
            .foregroundStyle(color.readableForeground)
            .overlay(Capsule().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .animation(Motion.snappy, value: count)
            .accessibilityLabel("\(count) \(count == 1 ? "copia" : "copias") en el deck")
    }
}

/// Etiqueta para distinguir impresiones especiales por su nombre: "Arte alterno", "Paralela", "Manga"…
enum PrintingStyle {
    static func label(for name: String) -> String? {
        let lower = name.lowercased()
        let rules: [(String, String)] = [
            ("manga", "Manga"),
            ("alternate art", "Arte alterno"),
            ("alt art", "Arte alterno"),
            ("parallel", "Paralela"),
            ("wanted poster", "Wanted"),
            ("(sp)", "SP"),
            ("pirate foil", "Pirate foil"),
            ("(gold)", "Dorada"),
            ("box topper", "Box topper"),
            ("full art", "Full art"),
            ("treasure", "Treasure"),
        ]
        return rules.first { lower.contains($0.0) }?.1
    }
}

struct PrintingStyleChip: View {
    let name: String

    var body: some View {
        if let label = PrintingStyle.label(for: name) {
            Text(label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Elegir otra impresión para una carta del deck (por ejemplo, el arte alterno).
/// Si hay varias copias, se puede cambiar solo una para separar artes distintos.
struct PrintingChoiceList: View {
    @Bindable var entry: DeckEntry
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var printings: [CardDetail] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pending: CardDetail?

    var body: some View {
        List {
            if isLoading {
                HStack { ProgressView(); Text("Buscando impresiones…").foregroundStyle(.secondary) }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.negative)
            } else if printings.count <= 1 {
                Text("Esta carta solo tiene una impresión.").foregroundStyle(.secondary)
            }
            ForEach(printings, id: \.summary.id) { printing in
                Button {
                    choose(printing)
                } label: {
                    HStack(spacing: 12) {
                        CardThumbnail(url: printing.summary.imageURL ?? printing.summary.thumbnailURL, width: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(printing.summary.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                PrintingStyleChip(name: printing.summary.name)
                            }
                            Text(printing.summary.setLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            let quote = printing.cheapestQuote()
                            UnitPriceText(unit: quote?.reference, currency: quote?.currency ?? "USD")
                        }
                        Spacer()
                        if printing.summary.id == entry.cardID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .disabled(printing.summary.id == entry.cardID)
                .accessibilityIdentifier("printing-option")
            }
        }
        .navigationTitle("Impresión")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Cambiar cuántas copias?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let pending {
                Button("Solo 1 copia (separar)") { apply(pending, onlyOne: true) }
                Button("Las \(entry.quantity) copias") { apply(pending, onlyOne: false) }
            }
        } message: {
            Text("Con \"Solo 1 copia\" el deck tendrá las dos impresiones por separado, por ejemplo una normal y una de arte alterno.")
        }
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let provider = model.provider(for: entry.game)
            let current = try await provider.detail(providerID: entry.providerID)
            let all = try await provider.printings(of: current)
            printings = all.isEmpty ? [current] : all.sorted {
                ($0.summary.id == entry.cardID ? 0 : 1, $0.summary.setName) < ($1.summary.id == entry.cardID ? 0 : 1, $1.summary.setName)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func choose(_ printing: CardDetail) {
        if entry.quantity > 1 { pending = printing } else { apply(printing, onlyOne: false) }
    }

    private func apply(_ printing: CardDetail, onlyOne: Bool) {
        let quote = printing.cheapestQuote() ?? PriceQuote(source: .tcgplayer, variant: "Normal", currency: "USD", market: nil, low: nil, mid: nil, high: nil)
        if onlyOne, let deck = entry.deck {
            entry.quantity -= 1
            entry.ownedQuantity = min(entry.ownedQuantity, entry.quantity)
            if let existing = deck.entryList.first(where: { $0.cardID == printing.summary.id && $0.isAlternative == entry.isAlternative }) {
                existing.quantity += 1
            } else {
                let split = DeckEntry(card: printing.summary, quantity: 1, quote: quote)
                split.isAlternative = entry.isAlternative
                context.insert(split)
                split.deck = deck
            }
            model.showToast("Separaste 1 copia: \(printing.summary.name)")
        } else {
            entry.apply(summary: printing.summary, quote: quote)
            model.showToast("Cambiaste a \(printing.summary.name)")
        }
        try? context.save()
        pending = nil
        dismiss()
    }
}
