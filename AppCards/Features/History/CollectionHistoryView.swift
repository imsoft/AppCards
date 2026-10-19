import SwiftUI
import SwiftData

struct CollectionHistoryView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \CollectionSnapshot.date) private var snapshots: [CollectionSnapshot]

    private var referenceValues: [PricePointValue] {
        snapshots.compactMap { snap in
            guard let value = model.converted(snap.referenceValue, from: snap.currency) else { return nil }
            return PricePointValue(date: snap.date, value: value)
        }
    }

    var body: some View {
        List {
            Section("Valor de mercado") {
                if referenceValues.count >= 2 {
                    PriceHistoryChart(points: referenceValues, currency: model.displayCurrency)
                } else {
                    Text("Se guarda una foto del valor de tu colección por día. Vuelve mañana para ver la gráfica.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Por día") {
                ForEach(snapshots.reversed()) { snap in
                    HStack {
                        Text(snap.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            PriceLabel(amount: snap.referenceValue, currency: snap.currency, style: .compact)
                            Text("\(snap.cardCount) cartas").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Valor en el tiempo")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Mini gráfica para el encabezado de la colección.
struct CollectionSparkline: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \CollectionSnapshot.date) private var snapshots: [CollectionSnapshot]

    private var values: [PricePointValue] {
        snapshots.compactMap { snap in
            guard let value = model.converted(snap.referenceValue, from: snap.currency) else { return nil }
            return PricePointValue(date: snap.date, value: value)
        }
    }

    var body: some View {
        NavigationLink {
            CollectionHistoryView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Valor en el tiempo").font(.subheadline.weight(.medium))
                    if let change = PriceTracking.change(from: values.first?.value, to: values.last?.value) {
                        Text(String(format: "%+.1f%% desde el %@", change * 100, values.first?.date.formatted(date: .abbreviated, time: .omitted) ?? ""))
                            .font(.caption)
                            .foregroundStyle(change >= 0 ? .green : .red)
                    } else {
                        Text("Se guarda una foto por día").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if values.count >= 2 {
                    PriceHistoryChart(points: values, currency: model.displayCurrency, compact: true)
                        .frame(width: 120)
                }
            }
        }
    }
}
