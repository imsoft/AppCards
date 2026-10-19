import SwiftUI

/// Fila estándar para listas editables: miniatura, nombre, set, estado y contenido a la derecha.
struct ItemRow<Trailing: View, Status: View>: View {
    let imageURL: URL?
    let name: String
    let subtitle: String
    /// Si se da, la miniatura abre el visor 3D (no usar dentro de un NavigationLink).
    var viewerColor: Color? = nil
    @ViewBuilder var status: () -> Status
    @ViewBuilder var trailing: () -> Trailing

    init(imageURL: URL?, name: String, subtitle: String, viewerColor: Color? = nil,
         @ViewBuilder status: @escaping () -> Status = { EmptyView() },
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.imageURL = imageURL
        self.name = name
        self.subtitle = subtitle
        self.viewerColor = viewerColor
        self.status = status
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let viewerColor {
                CardImageButton(url: imageURL, title: name, color: viewerColor, width: 44)
            } else {
                CardThumbnail(url: imageURL, width: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(2)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                status()
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 4)
    }
}

/// Resumen de pestaña: una cifra grande y hasta dos datos secundarios, siempre en GradientCard.
struct SummaryCard: View {
    let title: String
    let amount: Double
    let currency: String
    var previous: Double? = nil
    var footnote: String? = nil
    var colors: [Color] = [.vaultBlue, .vaultBlueDark]
    var foreground: Color = .white
    var pills: [(text: String, symbol: String)] = []

    var body: some View {
        GradientCard(colors: colors, foreground: foreground) {
            VStack(alignment: .leading, spacing: 14) {
                BigAmountView(title: title, amount: amount, currency: currency, previous: previous, footnote: footnote, onGradient: true)
                if !pills.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                            Label(pill.text, systemImage: pill.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(foreground.opacity(0.22), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}
