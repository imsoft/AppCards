import SwiftUI
import UIKit

/// Qué cartas van en la imagen para compartir.
enum DeckShareKind: String, CaseIterable, Identifiable {
    case full, missing
    var id: String { rawValue }
    var title: String { self == .full ? "Deck completo" : "Lo que me falta" }
}

/// Una carta ya lista para dibujar (con su imagen descargada).
struct DeckShareCard: Identifiable {
    let id: String
    let name: String
    let copies: Int
    /// Expansión y número, por ejemplo "OP15-001" o "TRK #1704".
    let code: String
    let image: UIImage?

    static func code(game: Game, setName: String, number: String) -> String {
        if game == .onePiece { return number }
        // "Star Trek (TRK)" → "TRK"; si no hay código entre paréntesis, el nombre del set.
        let set: String
        if let open = setName.lastIndex(of: "("), let close = setName.lastIndex(of: ")"), open < close {
            set = String(setName[setName.index(after: open)..<close])
        } else {
            set = setName
        }
        return [set, number.isEmpty ? "" : "#\(number)"].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Arma la imagen del deck: baja las imágenes de las cartas y las dibuja en una sola foto.
@MainActor
enum DeckShareRenderer {
    /// Ancho de la imagen en puntos; con escala 2 sale de 1080 px, el ancho de Instagram.
    static let width: CGFloat = 540

    static func cards(for deck: Deck, kind: DeckShareKind) -> [(entry: DeckEntry, copies: Int)] {
        deck.mainEntries
            .map { ($0, kind == .full ? $0.quantity : $0.missingQuantity) }
            .filter { $0.1 > 0 }
            .sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
    }

    static func render(deck: Deck, kind: DeckShareKind) async -> UIImage? {
        let picked = cards(for: deck, kind: kind)
        let requests = picked.map { (id: $0.entry.syncID.isEmpty ? UUID().uuidString : $0.entry.syncID,
                                     name: $0.entry.name, copies: $0.copies,
                                     code: DeckShareCard.code(game: $0.entry.game, setName: $0.entry.setName, number: $0.entry.number),
                                     url: $0.entry.imageURL, fallback: $0.entry.artworkFallback) }

        let images = await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    if let url = request.url, let image = await ImagePipeline.shared.image(for: url) { return (index, image) }
                    if let alternate = await ArtworkFallbackResolver.shared.url(for: request.fallback) {
                        return (index, await ImagePipeline.shared.image(for: alternate))
                    }
                    return (index, nil)
                }
            }
            var result = [Int: UIImage]()
            for await (index, image) in group { result[index] = image }
            return result
        }
        let shareCards = requests.enumerated().map { index, request in
            DeckShareCard(id: request.id, name: request.name, copies: request.copies, code: request.code, image: images[index])
        }

        let view = DeckShareView(
            deckName: deck.name,
            game: deck.game,
            colors: deck.accentColors,
            foreground: deck.accentForeground,
            kind: kind,
            cards: shareCards,
            totalCopies: picked.reduce(0) { $0 + $1.copies }
        )
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// El diseño de la imagen: encabezado con los colores del deck y cuadrícula de cartas.
struct DeckShareView: View {
    let deckName: String
    let game: Game
    let colors: [Color]
    let foreground: Color
    let kind: DeckShareKind
    let cards: [DeckShareCard]
    let totalCopies: Int

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: cards.count > 20 ? 5 : 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if cards.isEmpty {
                Text("¡Ya tengo todas las cartas!")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        tile(card)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                Text("Hecho con Vault")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(white: 0.09), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(game.title, systemImage: game.systemImage)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(foreground.opacity(0.18), in: Capsule())
                Spacer()
                Text(kind.title.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1)
            }
            Text(deckName)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text("\(totalCopies) \(totalCopies == 1 ? "carta" : "cartas")\(kind == .missing ? " por conseguir" : "")")
                .font(.headline)
        }
        .foregroundStyle(foreground)
        .padding(18)
        .background(DeckColors.gradient(colors), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func tile(_ card: DeckShareCard) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = card.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color(white: 0.22)
                            Text(card.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.716, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if card.copies > 1 {
                    Text("×\(card.copies)")
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .padding(4)
                }
            }
            VStack(spacing: 1) {
                Text(card.code)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(card.name)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}

/// Vista previa con selector (deck completo / lo que falta) y botón de compartir.
struct DeckShareSheet: View {
    let deck: Deck
    @State var kind: DeckShareKind
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isRendering = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Qué compartir", selection: $kind) {
                        ForEach(DeckShareKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("share-kind")

                    if let image, !isRendering {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                            .accessibilityIdentifier("share-preview")
                    } else {
                        ProgressView("Preparando imagen…")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle("Compartir deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let image, !isRendering {
                        let picture = Image(uiImage: image)
                        ShareLink(item: picture, preview: SharePreview("\(deck.name) · \(kind.title)", image: picture)) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("share-button")
                    }
                }
            }
            .task(id: kind) {
                isRendering = true
                image = await DeckShareRenderer.render(deck: deck, kind: kind)
                isRendering = false
            }
        }
        .sheetSize()
    }
}
