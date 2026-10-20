import SwiftUI

struct FilterSheet: View {
    let game: Game
    @Binding var filters: SearchFilters

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var options: FilterOptions?
    @State private var errorMessage: String?
    @State private var draft: SearchFilters = .none
    @State private var priceMinText = ""
    @State private var priceMaxText = ""
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            Form {
                if let options {
                    content(options)
                } else if let errorMessage {
                    ContentUnavailableView("No se pudieron cargar los filtros", systemImage: "line.3.horizontal.decrease.circle", description: Text(errorMessage))
                } else {
                    ProgressView("Cargando filtros…").frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Filtros · \(game.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Limpiar") {
                        draft = .none
                        priceMinText = ""
                        priceMaxText = ""
                    }
                    .disabled(draft == .none)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") { apply() }
                        .fontWeight(.semibold)
                }
            }
            .tint(game.color)
            .task { await load() }
            .onAppear {
                // Al volver de un selector (Set, Rareza…) `onAppear` se dispara otra vez: no hay que borrar lo elegido.
                guard !didStart else { return }
                didStart = true
                draft = filters
                priceMinText = filters.priceMinUSD.flatMap(displayPrice) ?? ""
                priceMaxText = filters.priceMaxUSD.flatMap(displayPrice) ?? ""
            }
        }
    }

    // MARK: Secciones

    @ViewBuilder
    private func content(_ options: FilterOptions) -> some View {
        Section {
            Picker("Mostrar", selection: $draft.ownership) {
                ForEach(OwnershipFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Ordenar por", selection: $draft.sort) {
                ForEach(options.sorts) { Text($0.title).tag($0) }
            }
        } header: {
            header("Mostrar y ordenar", "arrow.up.arrow.down")
        } footer: {
            if let note = options.priceSortNote { Text(note) }
        }

        if options.supportsCardText || options.supportsSubtype {
            Section {
                if options.supportsCardText {
                    LabeledContent(game == .pokemon ? "Ilustrador" : "Texto") {
                        TextField(game == .pokemon ? "Ilustrador" : "Texto", text: $draft.cardText, prompt: Text(options.cardTextPlaceholder))
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("filter-text")
                    }
                }
                if options.supportsSubtype {
                    LabeledContent("Subtipo") {
                        TextField("Subtipo", text: $draft.subtype, prompt: Text(options.subtypePlaceholder))
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("filter-subtype")
                    }
                }
            } header: {
                header(game == .pokemon ? "Ilustrador" : "Texto y subtipo", "text.magnifyingglass")
            } footer: {
                if game == .magic { Text("El texto busca en la habilidad de la carta, en inglés.") }
                if game == .onePiece { Text("El texto busca en el efecto de la carta, en inglés.") }
            }
        }

        Section {
            if !options.sets.isEmpty {
                NavigationLink {
                    SetPickerView(sets: options.sets, selection: $draft.cardSet)
                } label: {
                    LabeledContent("Set", value: draft.cardSet?.title ?? "Todos")
                }
            }
            if !options.formats.isEmpty {
                optionPicker("Formato", options: options.formats, selection: $draft.format)
            }
            if !options.rarities.isEmpty {
                optionPicker("Rareza", options: options.rarities, selection: $draft.rarity)
            }
            if options.supportsParallel {
                Toggle("Solo paralelas / alt-art", isOn: $draft.parallelOnly)
            }
        } header: {
            header("Colección y formato", "square.stack.3d.up")
        }

        Section {
            if !options.colors.isEmpty {
                optionPicker(game == .pokemon ? "Tipo de energía" : "Color", options: options.colors, selection: $draft.color)
            }
            if !options.cardTypes.isEmpty {
                optionPicker(game == .pokemon ? "Categoría" : "Tipo de carta", options: options.cardTypes, selection: $draft.cardType)
            }
            if !options.stages.isEmpty {
                optionPicker("Etapa", options: options.stages, selection: $draft.stage)
            }
            if !options.mechanics.isEmpty {
                optionPicker(options.mechanicTitle, options: options.mechanics, selection: $draft.mechanic)
            }
        } header: {
            header("Características", "sparkles")
        }

        if !options.costs.isEmpty || options.powerTitle != nil {
            Section {
                if !options.costs.isEmpty {
                    Picker(game == .magic ? "Valor de maná" : "Costo", selection: $draft.cost) {
                        Text("Cualquiera").tag(Int?.none)
                        ForEach(options.costs, id: \.self) { cost in
                            Text(cost == options.costs.last && game == .magic ? "\(cost)+" : "\(cost)").tag(Optional(cost))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                if let powerTitle = options.powerTitle {
                    Picker(powerTitle, selection: $draft.minPower) {
                        Text("Cualquiera").tag(Int?.none)
                        ForEach(options.powerValues, id: \.self) { Text("\($0)").tag(Optional($0)) }
                    }
                    .pickerStyle(.navigationLink)
                }
            } header: {
                header("Números", "number")
            }
        }

        if options.supportsPriceRange {
            Section {
                HStack {
                    TextField("Mínimo", text: $priceMinText).keyboardType(.decimalPad)
                    Text("a").foregroundStyle(.secondary)
                    TextField("Máximo", text: $priceMaxText).keyboardType(.decimalPad)
                    CurrencyTag(code: model.displayCurrency)
                }
                HStack {
                    ForEach(quickRanges, id: \.label) { range in
                        Button(range.label) {
                            priceMinText = range.min.map { String(format: "%.0f", $0) } ?? ""
                            priceMaxText = range.max.map { String(format: "%.0f", $0) } ?? ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                header("Precio", "tag")
            } footer: {
                Text("Usa el precio de mercado más bajo de cada carta.")
            }
        }
    }

    private func header(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(game.color)
            .textCase(nil)
    }

    private func optionPicker(_ title: String, options: [FilterOption], selection: Binding<FilterOption?>) -> some View {
        Picker(title, selection: selection) {
            Text("Cualquiera").tag(FilterOption?.none)
            ForEach(options) { option in
                Text(option.title).tag(Optional(option))
            }
        }
        .pickerStyle(.navigationLink)
    }

    // MARK: Precio en tu moneda

    private var quickRanges: [(label: String, min: Double?, max: Double?)] {
        let unit = model.displayCurrency == "MXN" ? 20.0 : 1.0
        return [
            ("< \(Int(5 * unit))", nil, 5 * unit),
            ("\(Int(5 * unit))–\(Int(25 * unit))", 5 * unit, 25 * unit),
            ("\(Int(25 * unit))–\(Int(100 * unit))", 25 * unit, 100 * unit),
            ("> \(Int(100 * unit))", 100 * unit, nil),
        ]
    }

    private func displayPrice(_ usd: Double) -> String? {
        model.converter.convert(usd, from: "USD", to: model.displayCurrency).map { String(format: "%.0f", $0) }
    }

    private func toUSD(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value >= 0 else { return nil }
        return model.converter.convert(value, from: model.displayCurrency, to: "USD")
    }

    private func apply() {
        var result = draft
        result.priceMinUSD = toUSD(priceMinText)
        result.priceMaxUSD = toUSD(priceMaxText)
        filters = result
        dismiss()
    }

    private func load() async {
        do {
            options = try await model.filterOptions(for: game)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Filtros activos como chips; tocar la X quita ese filtro.
struct ActiveFilterChips: View {
    @Binding var filters: SearchFilters
    var color: Color
    var onOpen: () -> Void

    var body: some View {
        if !filters.chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters.chips) { chip in
                        Button {
                            withAnimation(Motion.snappy) { filters.remove(chip.key) }
                        } label: {
                            HStack(spacing: 4) {
                                Text(chip.label).lineLimit(1)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(color.opacity(0.14), in: Capsule())
                            .foregroundStyle(color)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Quitar filtro \(chip.label)")
                    }
                    Button("Limpiar todo") { withAnimation(Motion.snappy) { filters = .none } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 6)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct SetPickerView: View {
    let sets: [FilterOption]
    @Binding var selection: FilterOption?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [FilterOption] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty ? sets : sets.filter { $0.title.lowercased().contains(needle) || $0.id.lowercased().contains(needle) }
    }

    var body: some View {
        List {
            Button {
                selection = nil
                dismiss()
            } label: {
                HStack {
                    Text("Todos los sets")
                    Spacer()
                    if selection == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .foregroundStyle(.primary)
            ForEach(filtered) { set in
                Button {
                    selection = set
                    dismiss()
                } label: {
                    HStack {
                        Text(set.title)
                        Spacer()
                        if selection == set { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .searchable(text: $query, prompt: "Buscar set")
        .navigationTitle("Set")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Botón de filtros con contador, para ponerlo junto al selector de juego.
struct FilterButton: View {
    let count: Int
    var color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.body.weight(.semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, count > 0 ? 11 : 9)
            .padding(.vertical, 8)
            .background(count > 0 ? color : Color(.secondarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(count > 0 ? color.readableForeground : color)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(count > 0 ? "Filtros, \(count) activos" : "Filtros")
        .accessibilityIdentifier("filter-button")
        .animation(Motion.snappy, value: count)
    }
}
