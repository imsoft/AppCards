import XCTest

/// Recorre las mejoras del deck y guarda capturas.
final class DeckTourUITests: XCTestCase {
    func testDeckImprovementsTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()

        let search = openSearch(app)
        search.tap()
        search.typeText("sol ring")
        let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sol Ring'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20))
        sleep(2)

        // 1) Primera carta al deck nuevo.
        tiles.element(boundBy: 0).press(forDuration: 1.2)
        app.buttons["Agregar a deck"].tap()
        chooseNewDeck(app, named: "Mono Artefactos")
        tapWhenEnabled(app.buttons["Agregar"])
        sleep(2)

        // 2) Segunda carta como opción.
        tiles.element(boundBy: 1).press(forDuration: 1.2)
        app.buttons["Agregar a deck"].tap()
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'opción'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        tapWhenEnabled(app.buttons["Agregar"])
        sleep(2)

        // 3) Una a la colección y desde ahí al deck.
        app.buttons.matching(NSPredicate(format: "label == %@", "Agregar una a la colección")).element(boundBy: 2).tap()
        sleep(2)
        relaunch(app, tab: "collection")
        let tile = app.buttons["collection-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let addToDeck = app.buttons["collection-add-to-deck"]
        XCTAssertTrue(addToDeck.waitForExistence(timeout: 10), "Falta 'Agregar a un deck' en la ficha de colección")
        addToDeck.tap()
        tapWhenEnabled(app.buttons["Agregar"])
        sleep(2)

        // 4) El deck en sus tres vistas.
        relaunch(app, tab: "decks")
        let deck = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mono Artefactos'")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        deck.tap()
        sleep(3)
        shot(app, "1-deck-lista")
        app.buttons["Cuadrícula"].tap(); sleep(2)
        shot(app, "2-deck-cuadricula")
        app.buttons["Por estado"].tap(); sleep(2)
        shot(app, "3-deck-por-estado")
        app.swipeUp(); sleep(1)
        shot(app, "4-deck-opciones")

        // 5) Color del deck.
        app.buttons["deck-menu"].tap()
        app.buttons["Color del deck"].tap()
        let green = app.buttons["Verde"]
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.tap()
        sleep(1)
        shot(app, "5-color")
        app.buttons["Listo"].tap()
        app.buttons["Lista"].tap()
        app.swipeDown(); sleep(2)
        shot(app, "6-deck-verde")
        app.navigationBars.buttons.firstMatch.tap(); sleep(2)
        shot(app, "7-decks")
    }

    /// Si ya hay decks del mismo juego, la hoja los elige por defecto; aquí se cambia a "Nuevo deck".
    private func chooseNewDeck(_ app: XCUIApplication, named deckName: String) {
        let name = app.textFields["Nombre del deck nuevo"]
        if !name.waitForExistence(timeout: 4) {
            let picker = app.buttons["deck-picker"].firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "No está el selector de deck")
            picker.tap()
            // El menú del selector puede exponer sus opciones como botones o como elementos de menú.
            let option = app.menuItems["Nuevo deck"].exists ? app.menuItems["Nuevo deck"]
                : app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Nuevo deck' AND elementType != %d", XCUIElement.ElementType.staticText.rawValue)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5), "No aparece la opción Nuevo deck")
            option.tap()
        }
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(deckName)
    }

    private func tapWhenEnabled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: element)
        waitForExpectations(timeout: 20)
        element.tap()
    }

    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) { return field }
        let button = app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    private func relaunch(_ app: XCUIApplication, tab: String) {
        app.terminate()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", tab]
        app.launch()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
