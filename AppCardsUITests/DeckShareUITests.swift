import XCTest

/// Compartir la imagen del deck: completo y solo lo que falta.
final class DeckShareUITests: XCTestCase {
    func testShareDeckImages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "decks"]
        app.launch()

        app.buttons["Importar lista"].firstMatch.tap()
        let name = app.textFields["Nombre del deck"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Luffy compartir")
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("1xOP01-003\n4xOP01-016\n4xOP01-025\n2xOP01-013\n4xOP02-058\n3xOP01-006")
        app.buttons["Revisar lista"].tap()
        let create = app.buttons["Crear deck"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: create)
        waitForExpectations(timeout: 120)
        create.tap()

        let deck = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Luffy compartir'")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        deck.tap()

        // Una carta a opciones, para que salga en su propia sección.
        let nami = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nami'")).firstMatch
        XCTAssertTrue(nami.waitForExistence(timeout: 10))
        nami.swipeLeft()
        let toOptions = app.buttons.matching(NSPredicate(format: "identifier == 'swipe-A opciones' OR label == 'A opciones'")).firstMatch
        XCTAssertTrue(toOptions.waitForExistence(timeout: 3))
        toOptions.tap()
        sleep(1)

        // Marcar todo y luego quitar algunas para que haya faltantes.
        app.buttons["deck-menu"].tap()
        app.buttons["Marcar todo como que lo tengo"].tap()
        sleep(1)
        app.buttons["deck-menu"].tap()
        // Las opciones no se marcan con "Marcar todo", así que todavía hay faltantes.
        XCTAssertTrue(app.buttons["Lo que me falta"].isEnabled)
        app.buttons["Deck completo"].tap()
        let preview = app.images["share-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 60), "No se generó la imagen")
        sleep(1)
        shot(app, "1-deck-completo")

        XCTAssertTrue(app.buttons["share-button"].exists)

        // Tocar una carta de la vista previa la abre en el visor.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.3)).tap()
        let viewer = app.descendants(matching: .any).matching(identifier: "card-viewer-card").firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), "Tocar la carta no abrió el visor")
        sleep(1)
        shot(app, "1a-visor")
        app.buttons["Cerrar"].firstMatch.tap()
        sleep(1)

        // Zoom: doble toque acerca, pellizcar también.
        preview.doubleTap()
        sleep(1)
        shot(app, "1b-zoom")
        preview.doubleTap()
        preview.pinch(withScale: 2.5, velocity: 2)
        sleep(1)
        shot(app, "1c-pellizco")
        app.buttons["Cerrar"].tap()
        sleep(1)

        app.buttons["deck-menu"].tap()
        app.buttons["Reiniciar conteo"].tap()
        sleep(1)
        app.buttons["deck-menu"].tap()
        app.buttons["Lo que me falta"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 60))
        sleep(1)
        shot(app, "2-lo-que-falta")

        app.buttons["share-button"].tap()
        sleep(3)
        shot(app, "3-hoja-compartir")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
