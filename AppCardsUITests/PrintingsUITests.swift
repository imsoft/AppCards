import XCTest

/// Arte normal y arte alterno de la misma carta deben quedar separados en el deck.
final class PrintingsUITests: XCTestCase {
    func testNormalAndAlternateArtStaySeparate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()

        app.buttons["One Piece"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        field.typeText("OP02-058")
        let parallel = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Buggy' AND label CONTAINS 'Alternate Art'")).firstMatch
        XCTAssertTrue(parallel.waitForExistence(timeout: 180), "No apareció el Buggy de arte alterno")
        sleep(2)
        let normal = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Buggy' AND NOT (label CONTAINS 'Alternate Art')")).firstMatch

        add(app, tile: normal, newDeck: "Buggy test")
        add(app, tile: parallel, newDeck: nil)

        app.terminate()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "decks"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Buggy test'")).firstMatch.tap()
        sleep(2)
        let rows = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Buggy'"))
        XCTAssertGreaterThanOrEqual(rows.count, 2, "El arte normal y el paralelo se juntaron en una sola carta")
        XCTAssertTrue(app.staticTexts["Arte alterno"].firstMatch.exists, "Falta la etiqueta de arte alterno")
        shot(app, "1-dos-artes")

        // Separar: subir la normal a ×2 y pasar 1 copia a otra impresión.
        app.staticTexts.matching(NSPredicate(format: "label == 'Buggy'")).firstMatch.tap()
        let quiero = app.steppers.firstMatch
        XCTAssertTrue(quiero.waitForExistence(timeout: 5))
        quiero.buttons.element(boundBy: 1).tap()
        app.buttons["change-printing"].tap()
        let other = app.buttons.matching(NSPredicate(format: "identifier == 'printing-option' AND isEnabled == true")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 30), "No cargaron las impresiones")
        other.tap()
        let onlyOne = app.buttons["Solo 1 copia (separar)"]
        XCTAssertTrue(onlyOne.waitForExistence(timeout: 5), "No preguntó cuántas copias cambiar")
        onlyOne.tap()
        sleep(1)
        if app.buttons["Listo"].exists { app.buttons["Listo"].tap() }
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
        shot(app, "2-separada")
    }

    private func add(_ app: XCUIApplication, tile: XCUIElement, newDeck: String?) {
        tile.press(forDuration: 1.2)
        app.buttons["Agregar a deck"].tap()
        if let newDeck {
            let name = app.textFields["Nombre del deck nuevo"]
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            name.tap(); name.typeText(newDeck)
        }
        let add = app.buttons["Agregar"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: add)
        waitForExpectations(timeout: 30)
        add.tap()
        sleep(2)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
