import SwiftUI

/// Imagen de carta que abre el visor 3D a pantalla completa. Úsala en cualquier lugar donde se muestre una carta.
struct CardImageButton: View {
    let url: URL?
    let title: String
    var color: Color = .vaultBlue
    var width: CGFloat = 60
    var fallback: ArtworkFallback? = nil

    @State private var showViewer = false

    var body: some View {
        Button {
            DiagnosticsLog.event("card image tapped title=\(title)")
            showViewer = true
        } label: {
            CardThumbnail(url: url, width: width, fallback: fallback)
                .shadow(color: color.opacity(0.35), radius: width > 60 ? 8 : 3, y: 3)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: width > 60 ? 11 : 8, weight: .bold))
                        .padding(width > 60 ? 6 : 4)
                        .background(.regularMaterial, in: Circle())
                        .foregroundStyle(.primary)
                        .padding(4)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Ver \(title) en pantalla completa")
        .accessibilityIdentifier("card-image-button")
        .fullScreenCover(isPresented: $showViewer) {
            CardViewer(url: ImageQuality.best(url, size: .full), title: title, color: color, fallback: fallback) {
                showViewer = false
            }
        }
    }
}

extension View {
    /// Presenta el visor 3D para la carta que se asigne a `card`.
    func cardViewer(for card: Binding<CardSummary?>) -> some View {
        fullScreenCover(item: card) { summary in
            CardViewer(url: ImageQuality.best(summary.imageURL ?? summary.thumbnailURL, size: .full), title: summary.name, color: summary.game.color, fallback: ArtworkFallback(summary)) {
                card.wrappedValue = nil
            }
        }
    }
}
