import XCTest

/// Oprime cada botón del menú del deck en las tres vistas y revisa que la app no se cierre.
final class DeckActionsUITests: XCTestCase {
    func testEveryDeckActionInEveryView() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        field.typeText("llanowar elves")
        let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Llanowar Elves'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        for index in 0..<2 {
            tiles.element(boundBy: index).press(forDuration: 1.2)
            app.buttons["Agregar a deck"].tap()
            let name = app.textFields["Nombre del deck nuevo"]
            if name.waitForExistence(timeout: 4) { name.tap(); name.typeText("Elfos") }
            let add = app.buttons["Agregar"]
            expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: add)
            waitForExpectations(timeout: 20)
            add.tap()
            sleep(2)
        }
        // Una a la colección para que "Rellenar desde mi colección" tenga algo.
        app.buttons.matching(NSPredicate(format: "label == %@", "Agregar una a la colección")).firstMatch.tap()
        sleep(1)

        app.terminate()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "decks"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Elfos'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["deck-menu"].waitForExistence(timeout: 10))

        for mode in ["Lista", "Cuadrícula", "Por estado"] {
            app.buttons[mode].tap()
            for action in ["Marcar todo como que lo tengo", "Reiniciar conteo", "Rellenar desde mi colección",
                           "Marcar todo como que lo tengo", "Reiniciar conteo"] {
                app.buttons["deck-menu"].tap()
                let button = app.buttons[action]
                XCTAssertTrue(button.waitForExistence(timeout: 5), "No está \(action)")
                if button.isEnabled { button.tap() } else { app.tap() }
                sleep(1)
                XCTAssertEqual(app.state, .runningForeground, "La app se cerró con \(action) en \(mode)")
            }
            // Subir y bajar lo que tienes con los botones de la fila (solo en lista y por estado).
            let plus = app.buttons["Tengo una más"].firstMatch
            if plus.exists && plus.isHittable { plus.tap(); sleep(1) }
            XCTAssertEqual(app.state, .runningForeground, "La app se cerró al sumar en \(mode)")
        }

        // Colores: dos colores.
        app.buttons["deck-menu"].tap()
        app.buttons["Color del deck"].tap()
        XCTAssertTrue(app.buttons["Verde"].waitForExistence(timeout: 5))
        app.buttons["Verde"].tap()
        app.buttons["Azul"].tap()
        shot(app, "1-dos-colores")
        app.buttons["Listo"].tap()
        sleep(1)

        // Abrir una carta, moverla a opciones desde la hoja, y regresar.
        app.buttons["Lista"].tap()
        app.staticTexts["Llanowar Elves"].firstMatch.tap()
        let optionToggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'Opción'")).firstMatch
        XCTAssertTrue(optionToggle.waitForExistence(timeout: 5))
        optionToggle.switches.firstMatch.exists ? optionToggle.switches.firstMatch.tap() : optionToggle.tap()
        app.buttons["Listo"].tap()
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)

        // Eliminar el deck desde su menú.
        app.buttons["deck-menu"].tap()
        app.buttons["Eliminar deck"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Eliminar deck'")).element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.sheets.buttons["Eliminar deck"].exists ? app.sheets.buttons["Eliminar deck"].tap() : confirm.tap()
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "La app se cerró al eliminar el deck")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Elfos'")).firstMatch.exists, "El deck no se eliminó")
        shot(app, "2-deck-eliminado")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
