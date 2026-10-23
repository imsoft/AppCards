import XCTest

/// Enlazar una opción como sustituto y hacer el cambio.
final class SubstitutionUITests: XCTestCase {
    func testSubstituteAndSwap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        field.typeText("lightning bolt")
        let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Lightning Bolt'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20))
        sleep(2)

        tiles.element(boundBy: 0).press(forDuration: 1.2)
        app.buttons["Agregar a deck"].tap()
        chooseNewDeck(app, named: "Burn")
        tapWhenEnabled(app.buttons["Agregar"])
        sleep(2)

        tiles.element(boundBy: 1).press(forDuration: 1.2)
        app.buttons["Agregar a deck"].tap()
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'opción'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        let replaces = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sustituye a'")).firstMatch
        XCTAssertTrue(replaces.waitForExistence(timeout: 5), "Falta 'Sustituye a' al agregar como opción")
        replaces.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Lightning Bolt'")).firstMatch.tap()
        sleep(1)
        tapWhenEnabled(app.buttons["Agregar"])
        sleep(2)

        app.terminate()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "decks"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Burn'")).firstMatch.tap()
        sleep(2)
        app.swipeUp(); sleep(1)
        let link = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sustituye a'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "La opción no muestra a quién sustituye")
        shot(app, "1-sustitucion")

        // Abrir la opción y hacer el cambio.
        link.tap()
        let swap = app.buttons["do-substitution"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5))

        // En la sustitución también se puede poner cuántas quieres y cuántas tienes.
        let wanted = app.steppers.firstMatch
        let owned = app.steppers["owned-stepper"]
        if !owned.isHittable { app.swipeUp() }
        XCTAssertTrue(owned.waitForExistence(timeout: 5), "La opción no tiene el contador de 'Tengo'")
        for _ in 0..<3 { wanted.buttons.element(boundBy: 1).tap() }
        for _ in 0..<2 { owned.buttons.element(boundBy: 1).tap() }
        XCTAssertEqual(owned.value as? String, "2")
        shot(app, "2-hoja")
        app.swipeDown(velocity: .slow)
        if !swap.isHittable { app.swipeDown() }
        swap.tap()
        sleep(2)
        shot(app, "3-cambiado")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sustituye a'")).firstMatch.exists,
                      "Después del cambio, la carta que salió debe quedar en opciones enlazada a la nueva")
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
