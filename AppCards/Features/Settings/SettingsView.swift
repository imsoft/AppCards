import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var isRefreshingAll = false
    @State private var refreshMessage: String?
    @State private var isReloadingCatalog = false
    @State private var catalogMessage: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                SyncSettingsSection()
                Section("Moneda") {
                    Picker("Mostrar precios en", selection: $model.displayCurrency) {
                        ForEach(CurrencyConverter.supported, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    Toggle("Mostrar precio estimado en tienda", isOn: $model.showStorePrice)
                    if model.showStorePrice {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Margen de tienda")
                                Spacer()
                                Text("+\(Int(model.storeMarkupPercent))%")
                                    .font(.headline).monospacedDigit()
                                    .foregroundStyle(.tint)
                                    .animatedNumber(model.storeMarkupPercent)
                            }
                            Slider(value: $model.storeMarkupPercent, in: StoreMarkup.range, step: 5)
                            HStack(spacing: 8) {
                                ForEach([15.0, 20.0, 25.0, 30.0], id: \.self) { preset in
                                    Button("\(Int(preset))%") { model.storeMarkupPercent = preset }
                                        .buttonStyle(.bordered)
                                        .tint(model.storeMarkupPercent == preset ? .accentColor : .gray)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        LabeledContent("Ejemplo: carta de $100.00 MXN") {
                            MoneyText(amount: StoreMarkup.storePrice(100, percent: model.storeMarkupPercent), currency: "MXN", font: .subheadline.weight(.semibold), tagSize: .small)
                        }
                    }
                } header: {
                    Text("Precio en tienda")
                } footer: {
                    Text("Las tiendas suelen cobrar 20–25% arriba del precio de mercado. La app te muestra ese precio estimado junto al de mercado, en el detalle de cada carta y en lo que te falta de cada deck.")
                }

                Section {
                    if let rates = model.rates {
                        if let mxn = rates.rates["MXN"] {
                            LabeledContent("1 USD", value: MoneyFormatter.string(mxn, currency: "MXN"))
                        }
                        if let eur = rates.rates["EUR"] {
                            LabeledContent("1 USD", value: MoneyFormatter.string(eur, currency: "EUR"))
                        }
                        LabeledContent("Fecha", value: rates.date)
                    } else {
                        Text("Sin tipo de cambio descargado.").foregroundStyle(.secondary)
                    }
                    if let error = model.ratesError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        Task { await model.refreshRates() }
                    } label: {
                        HStack {
                            Text("Actualizar tipo de cambio")
                            if model.isRefreshingRates { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isRefreshingRates)

                    Toggle("Usar tipo de cambio manual (USD → MXN)", isOn: $model.useManualRate)
                    if model.useManualRate {
                        LabeledContent("1 USD en MXN") {
                            TextField("18.00", value: $model.manualUSDMXN, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Tipo de cambio")
                } footer: {
                    Text("Fuente: Frankfurter (Banco Central Europeo). El manual te sirve para usar el tipo de cambio de tu tarjeta o de la tienda donde compras.")
                }

                Section {
                    Button {
                        Task { await refreshAll() }
                    } label: {
                        HStack {
                            Text("Actualizar colección y deseos ahora")
                            if isRefreshingAll { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isRefreshingAll)
                    if let last = model.lastRefreshAt {
                        Text("Última actualización: \(last.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let refreshMessage {
                        Text(refreshMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Permitir notificaciones de precios") {
                        Task { _ = await PriceRefreshService.requestNotificationPermission() }
                    }
                } header: {
                    Text("Seguimiento de precios")
                } footer: {
                    Text("Al abrir la app y una vez al día en segundo plano se actualizan los precios de tu colección y deseos, se guarda el historial y se anota el valor de la colección.")
                }

                Section {
                    Button {
                        Task { await reloadCatalog() }
                    } label: {
                        HStack {
                            Text("Volver a descargar catálogo de One Piece")
                            if isReloadingCatalog { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isReloadingCatalog)
                    if let catalogMessage {
                        Text(catalogMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Datos")
                } footer: {
                    Text("Magic: Scryfall (TCGplayer USD y Cardmarket EUR). Pokémon: TCGdex (TCGplayer y Cardmarket). One Piece: TCGplayer vía tcgcsv.com. Todos actualizan precios una vez al día.")
                }
            }
            .navigationTitle("Ajustes")
        }
    }

    private func refreshAll() async {
        isRefreshingAll = true
        defer { isRefreshingAll = false }
        let report = await PriceRefreshService(model: model, context: context).runDaily(force: true)
        refreshMessage = "\(report.collectionUpdated) de colección, \(report.wishlistUpdated) de deseos, \(report.failures) errores."
    }

    private func reloadCatalog() async {
        isReloadingCatalog = true
        defer { isReloadingCatalog = false }
        do {
            let catalog = try await model.onePiece.loadCatalog(force: true)
            catalogMessage = "\(catalog.entries.count) cartas descargadas."
        } catch {
            catalogMessage = error.localizedDescription
        }
    }
}
