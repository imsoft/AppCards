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
    /// Si es sustituto: nombre de la carta del deck a la que reemplazaría.
    var replaces: String? = nil
    let image: UIImage?
    /// Para abrir la carta en el visor al tocarla en la vista previa.
    var summary: CardSummary? = nil

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

/// Dónde quedó cada carta dentro de la imagen (en puntos), para saber cuál se tocó.
final class ShareCardFrames {
    var frames: [String: CGRect] = [:]
}

/// La imagen generada y las cartas con su lugar en ella.
struct DeckShareResult {
    let image: UIImage
    let cards: [(card: DeckShareCard, frame: CGRect)]

    /// La carta que hay en ese punto de la imagen (en puntos, no píxeles).
    func card(at point: CGPoint) -> DeckShareCard? {
        cards.first { $0.frame.contains(point) }?.card
    }
}

/// Arma la imagen del deck: baja las imágenes de las cartas y las dibuja en una sola foto.
@MainActor
enum DeckShareRenderer {
    /// Ancho de la imagen en puntos.
    static let width: CGFloat = 540

    static func cards(for deck: Deck, kind: DeckShareKind) -> [(entry: DeckEntry, copies: Int)] {
        pick(deck.mainEntries, kind: kind)
    }

    /// Opciones y sustituciones: van en su propia sección de la imagen.
    static func options(for deck: Deck, kind: DeckShareKind) -> [(entry: DeckEntry, copies: Int)] {
        pick(deck.alternativeEntries, kind: kind)
    }

    private static func pick(_ entries: [DeckEntry], kind: DeckShareKind) -> [(entry: DeckEntry, copies: Int)] {
        entries
            .map { ($0, kind == .full ? $0.quantity : $0.missingQuantity) }
            .filter { $0.1 > 0 }
            .sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
    }

    static func render(deck: Deck, kind: DeckShareKind) async -> DeckShareResult? {
        let picked = cards(for: deck, kind: kind)
        let pickedOptions = options(for: deck, kind: kind)
        let entries = deck.entryList
        let requests = (picked + pickedOptions).map { (id: $0.entry.syncID.isEmpty ? UUID().uuidString : $0.entry.syncID,
                                     name: $0.entry.name, copies: $0.copies,
                                     code: DeckShareCard.code(game: $0.entry.game, setName: $0.entry.setName, number: $0.entry.number),
                                     replaces: DeckSubstitution.target(of: $0.entry, in: entries)?.name,
                                     summary: $0.entry.summary,
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
        let collector = ShareCardFrames()
        let shareCards = requests.enumerated().map { index, request in
            DeckShareCard(id: request.id, name: request.name, copies: request.copies, code: request.code,
                          replaces: request.replaces, image: images[index], summary: request.summary)
        }

        let view = DeckShareView(
            deckName: deck.name,
            game: deck.game,
            colors: deck.accentColors,
            foreground: deck.accentForeground,
            kind: kind,
            cards: Array(shareCards.prefix(picked.count)),
            options: Array(shareCards.dropFirst(picked.count)),
            totalCopies: picked.reduce(0) { $0 + $1.copies },
            optionCopies: pickedOptions.reduce(0) { $0 + $1.copies },
            frameCollector: collector
        )
        let renderer = ImageRenderer(content: view.frame(width: width))
        // Escala 3 (1620 px): se ve nítida al hacer zoom en la vista previa.
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return DeckShareResult(image: image, cards: shareCards.compactMap { card in
            collector.frames[card.id].map { (card, $0) }
        })
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
    var options: [DeckShareCard] = []
    let totalCopies: Int
    var optionCopies: Int = 0
    var frameCollector: ShareCardFrames? = nil

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: cards.count + options.count > 20 ? 5 : 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if cards.isEmpty {
                Text(kind == .missing ? "¡Ya tengo todas las cartas del deck!" : "El deck no tiene cartas todavía")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, options.isEmpty ? 40 : 16)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        tile(card)
                    }
                }
            }
            if !options.isEmpty {
                optionsSection
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
        .coordinateSpace(.named(Self.space))
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
            HStack(spacing: 6) {
                Text("\(totalCopies) \(totalCopies == 1 ? "carta" : "cartas")\(kind == .missing ? " por conseguir" : "")")
                    .font(.headline)
                if optionCopies > 0 {
                    Text("+ \(optionCopies) \(optionCopies == 1 ? "opcional" : "opcionales")")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.8)
                }
            }
        }
        .foregroundStyle(foreground)
        .padding(18)
        .background(DeckColors.gradient(colors), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Opciones y sustituciones, separadas del deck con un título y un marco punteado.
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.swap")
                Text("OPCIONES Y SUSTITUCIONES")
                    .tracking(1)
                    .fixedSize()
                Text("\(optionCopies)")
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.15), in: Capsule())
                Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white.opacity(0.85))

            Text("No cuentan en el deck: cartas que podría incluir o cambiar.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(options) { card in
                    tile(card)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .padding(.top, 6)
    }

    static let space = "deck-share"

    private func tile(_ card: DeckShareCard) -> some View {
        tileContent(card)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { frame in
                frameCollector?.frames[card.id] = frame
            }
    }

    private func tileContent(_ card: DeckShareCard) -> some View {
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

                // Copias grandes y con los colores del deck, para que se lean de lejos.
                Text("×\(card.copies)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(DeckColors.gradient(colors), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.55), radius: 4, y: 2)
                    .offset(x: 6, y: 6)
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
                if let replaces = card.replaces {
                    Label("por \(replaces)", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Vista previa con selector (deck completo / lo que falta) y botón de compartir.
struct DeckShareSheet: View {
    let deck: Deck
    @State var kind: DeckShareKind
    @Environment(\.dismiss) private var dismiss
    @State private var result: DeckShareResult?
    @State private var isRendering = true
    @State private var viewerCard: CardSummary?

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("Qué compartir", selection: $kind) {
                    ForEach(DeckShareKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("share-kind")
                .padding(.horizontal, Theme.screenPadding)

                if let result, !isRendering {
                    ZoomableImage(image: result.image) { point in
                        if let card = result.card(at: point)?.summary { viewerCard = card }
                    }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("Vista previa de la imagen")
                    .accessibilityIdentifier("share-preview")
                    Label("Toca una carta para verla · pellizca para hacer zoom", systemImage: "hand.tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Preparando imagen…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .navigationTitle("Compartir deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let result, !isRendering {
                        let picture = Image(uiImage: result.image)
                        ShareLink(item: picture, preview: SharePreview("\(deck.name) · \(kind.title)", image: picture)) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("share-button")
                    }
                }
            }
            .task(id: kind) {
                isRendering = true
                result = await DeckShareRenderer.render(deck: deck, kind: kind)
                isRendering = false
            }
            .cardViewer(for: $viewerCard)
        }
        .sheetSize()
    }
}

/// Imagen con zoom: pellizcar para acercar y moverse; doble toque acerca ahí o regresa al tamaño completo.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var maxZoom: CGFloat = 5
    /// Toque sencillo: el punto en coordenadas de la imagen (puntos).
    var onTap: ((CGPoint) -> Void)? = nil

    /// Recalcula el ajuste cada vez que cambia su tamaño (al aparecer o al girar).
    final class LayoutScrollView: UIScrollView {
        var onLayout: ((UIScrollView) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
    }

    func makeUIView(context: Context) -> LayoutScrollView {
        let scroll = LayoutScrollView()
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.layout(in: $0) }
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = maxZoom
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        // El toque sencillo espera a que no sea doble, para no abrir la carta al hacer zoom.
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)
        context.coordinator.onTap = onTap
        return scroll
    }

    func updateUIView(_ scroll: LayoutScrollView, context: Context) {
        context.coordinator.onTap = onTap
        guard let imageView = context.coordinator.imageView else { return }
        if imageView.image !== image {
            imageView.image = image
            scroll.setZoomScale(1, animated: false)
            context.coordinator.reset()
            scroll.setNeedsLayout()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onTap: ((CGPoint) -> Void)?
        private var lastBounds: CGSize = .zero

        func reset() { lastBounds = .zero }

        /// Ajusta la imagen al espacio disponible (a escala 1) y la centra.
        func layout(in scroll: UIScrollView) {
            guard let imageView, let image = imageView.image, scroll.bounds.size != .zero else { return }
            if scroll.bounds.size != lastBounds {
                lastBounds = scroll.bounds.size
                let zoom = scroll.zoomScale
                scroll.zoomScale = 1
                let fit = min(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
                imageView.frame = CGRect(x: 0, y: 0, width: image.size.width * fit, height: image.size.height * fit)
                scroll.contentSize = imageView.frame.size
                scroll.zoomScale = zoom
            }
            center(in: scroll)
        }

        private func center(in scroll: UIScrollView) {
            guard let imageView else { return }
            let x = max((scroll.bounds.width - imageView.frame.width) / 2, 0)
            let y = max((scroll.bounds.height - imageView.frame.height) / 2, 0)
            scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { center(in: scrollView) }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let imageView, let image = imageView.image, imageView.bounds.width > 0 else { return }
            let location = gesture.location(in: imageView)
            guard imageView.bounds.contains(location) else { return }
            let point = CGPoint(x: location.x / imageView.bounds.width * image.size.width,
                                y: location.y / imageView.bounds.height * image.size.height)
            onTap?(point)
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView, let imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 3
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}
