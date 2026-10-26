import XCTest

/// Deslizar tarjetas de deck y cartas del deck para ver opciones.
final class SwipeOptionsUITests: XCTestCase {
    func testSwipeDeckAndCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "decks"]
        app.launch()

        app.buttons["Importar lista"].firstMatch.tap()
        let name = app.textFields["Nombre del deck"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Deslizar")
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("1xOP01-003\n4xOP01-016\n2xOP01-013")
        app.buttons["Revisar lista"].tap()
        let create = app.buttons["Crear deck"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: create)
        waitForExpectations(timeout: 120)
        create.tap()

        // Tarjeta de deck: deslizar a la izquierda muestra Color, Compartir y Eliminar.
        let deck = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Deslizar'")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        deck.swipeLeft()
        let share = swipeButton(app, "Compartir")
        XCTAssertTrue(share.waitForExistence(timeout: 3), "No aparecieron las opciones del deck")
        XCTAssertTrue(swipeButton(app, "Eliminar").exists)
        sleep(1)
        shot(app, "1-deck-opciones")
        share.tap()
        XCTAssertTrue(app.images["share-preview"].waitForExistence(timeout: 60), "Compartir no abrió la imagen")
        app.buttons["Cerrar"].tap()
        sleep(1)

        // Con las opciones cerradas, tocar abre el deck.
        deck.tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nami'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // Carta: izquierda = mover / quitar; derecha = tengo todas.
        row.swipeLeft()
        let toOptions = swipeButton(app, "A opciones")
        XCTAssertTrue(toOptions.waitForExistence(timeout: 3), "No aparecieron las opciones de la carta")
        sleep(1)
        shot(app, "2-carta-izquierda")
        toOptions.tap()
        sleep(1)

        let sanji = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sanji'")).firstMatch
        sanji.swipeRight()
        let ownAll = swipeButton(app, "Tengo todas")
        XCTAssertTrue(ownAll.waitForExistence(timeout: 3), "No apareció 'Tengo todas'")
        sleep(1)
        shot(app, "3-carta-derecha")
        ownAll.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["2 de 3 cartas"].firstMatch.exists, "Tengo todas no marcó las copias")

        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Monkey'")).firstMatch.swipeLeft()
        let remove = swipeButton(app, "Quitar")
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        sleep(2)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ver Monkey'")).firstMatch.exists, "Quitar no quitó la carta")
        shot(app, "4-final")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func swipeButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "swipe-\(title)", title)).firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
