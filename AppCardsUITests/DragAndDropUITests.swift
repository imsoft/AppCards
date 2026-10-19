import XCTest

/// Arrastrar cartas entre "Cartas" y "Opciones y sustituciones", hojas completas y contador de cartas.
final class DragAndDropUITests: XCTestCase {
    func testDragCardToOptionsAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        field.typeText("counterspell")
        let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Counterspell'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20))
        sleep(2)

        tiles.element(boundBy: 0).press(forDuration: 1.2)
        app.buttons["Agregar a deck"].tap()
        let name = app.textFields["Nombre del deck nuevo"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        shot(app, "1-hoja-agregar")
        name.tap(); name.typeText("Azul")
        tapWhenEnabled(app.buttons["Agregar"])
        sleep(2)

        app.terminate()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "decks"]
        app.launch()
        let deck = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Azul'")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1"].exists || app.otherElements["1 carta en el deck"].exists || app.staticTexts.matching(NSPredicate(format: "label == '1'")).count > 0,
                      "Falta el contador de cartas en la tarjeta del deck")
        shot(app, "2-decks-contador")
        deck.tap()
        sleep(2)

        // Arrastrar la carta del deck al área de opciones.
        let row = app.staticTexts["Counterspell"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // Que la zona de opciones quede a la vista, no detrás del menú de abajo.
        app.swipeUp(); sleep(1)
        let dropZone = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Arrastra aquí'")).firstMatch
        XCTAssertTrue(dropZone.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0, thenDragTo: dropZone, withVelocity: .slow, thenHoldForDuration: 0.8)
        let toOptions = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'a opciones'")).firstMatch
        XCTAssertTrue(toOptions.waitForExistence(timeout: 5), "Soltar en opciones no movió la carta")
        sleep(2)
        shot(app, "3-en-opciones")

        // Y de regreso al deck: se suelta sobre el texto "Agrega cartas…" de la sección vacía de cartas.
        app.swipeUp(); sleep(1)
        let moved = app.staticTexts["Counterspell"].firstMatch
        let empty = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Agrega cartas'")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        moved.press(forDuration: 1.0, thenDragTo: empty, withVelocity: .slow, thenHoldForDuration: 0.8)
        let toDeck = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'al deck'")).firstMatch
        XCTAssertTrue(toDeck.waitForExistence(timeout: 5), "Soltar en cartas no regresó la carta al deck")
        sleep(2)

        // La hoja de la carta abre completa.
        app.staticTexts["Counterspell"].firstMatch.tap()
        let done = app.buttons["Listo"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Quitar del deck"].isHittable, "La hoja de la carta no abrió completa")
        shot(app, "4-hoja-carta")
    }

    private func tapWhenEnabled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        waitForExpectations(timeout: 20)
        element.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
