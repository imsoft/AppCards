import SwiftUI
import SwiftData
import Charts

struct PricePointValue: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Gráfica de línea con puntos ya convertidos a la moneda de la app.
struct PriceHistoryChart: View {
    let points: [PricePointValue]
    let currency: String
    var compact = false

    private var sampled: [PricePointValue] { PriceTracking.downsample(points, limit: 120) }
    private var change: Double? { PriceTracking.change(from: points.first?.value, to: points.last?.value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !compact, let last = points.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(MoneyFormatter.string(last.value, currency: currency))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    if let change {
                        Text(String(format: "%+.1f%%", change * 100))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(change < 0 ? .green : (change > 0 ? .red : .secondary))
                    }
                    Spacer()
                    Text("\(points.count) días").font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart(sampled) { point in
                LineMark(x: .value("Fecha", point.date), y: .value("Precio", point.value))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Fecha", point.date), y: .value("Precio", point.value))
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(compact ? .hidden : .automatic)
            .chartYAxis(compact ? .hidden : .automatic)
            .frame(height: compact ? 44 : 160)
        }
    }
}

/// Historial de una carta: lee los puntos guardados y los convierte a la moneda elegida.
struct CardPriceHistorySection: View {
    let cardID: String
    let quoteID: String?

    @Environment(AppModel.self) private var model
    @Query private var points: [PricePoint]

    init(cardID: String, quoteID: String?) {
        self.cardID = cardID
        self.quoteID = quoteID
        _points = Query(filter: #Predicate<PricePoint> { $0.cardID == cardID }, sort: \PricePoint.date)
    }

    private var values: [PricePointValue] {
        let chosen = quoteID.flatMap { id in points.contains { $0.quoteID == id } ? id : nil } ?? points.first?.quoteID
        return points
            .filter { $0.quoteID == chosen }
            .compactMap { point in
                guard let value = model.converted(point.price, from: point.currency) else { return nil }
                return PricePointValue(date: point.date, value: value)
            }
    }

    var body: some View {
        SectionCard(title: "Historial", systemImage: "chart.line.uptrend.xyaxis", tint: .purple) {
            if values.count >= 2 {
                PriceHistoryChart(points: values, currency: model.displayCurrency)
            } else {
                Text("Se guarda un precio por día cada vez que abres la carta, la tienes en colección o en deseos. Vuelve mañana para ver la gráfica.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
