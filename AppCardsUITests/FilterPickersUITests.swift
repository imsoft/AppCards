import XCTest

/// Los selectores de filtros (Rareza, Color…) deben quedarse con lo elegido y aplicarse.
final class FilterPickersUITests: XCTestCase {
    func testPickersKeepSelectionAndApply() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()
        app.buttons["Magic"].firstMatch.tap()
        app.buttons["filter-button"].firstMatch.tap()

        let rarity = app.buttons["Rareza"].firstMatch
        XCTAssertTrue(rarity.waitForExistence(timeout: 20), "No cargaron los filtros")
        rarity.tap()
        app.buttons["Mítica"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue((app.buttons["Rareza"].firstMatch.value as? String) == "Mítica", "La rareza elegida se borró al volver")

        let color = app.buttons["Color"].firstMatch
        if !color.isHittable { app.swipeUp() }
        color.tap()
        app.buttons["Verde"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue((app.buttons["Rareza"].firstMatch.value as? String) == "Mítica", "Elegir el color borró la rareza")
        XCTAssertTrue((app.buttons["Color"].firstMatch.value as? String) == "Verde", "El color elegido se borró al volver")
        shot(app, "1-filtros-elegidos")

        app.buttons["Aplicar"].tap()
        XCTAssertTrue(app.buttons["Quitar filtro Mítica"].waitForExistence(timeout: 5), "No se aplicó la rareza")
        XCTAssertTrue(app.buttons["Quitar filtro Verde"].exists, "No se aplicó el color")
        sleep(6)
        shot(app, "2-resultados")

        // Deseos con cantidad: 3 copias de la primera carta.
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Mythic'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "No hubo resultados")
        tile.press(forDuration: 1.2)
        app.buttons["Lista de deseos"].tap()
        let stepper = app.steppers["wishlist-quantity"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 20))
        stepper.buttons.element(boundBy: 1).tap()
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(stepper.value as? String, "3")
        app.buttons["Agregar"].tap()
        sleep(2)

        app.buttons["Deseos"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["3 copias"].firstMatch.waitForExistence(timeout: 5), "La fila no muestra las copias")
        XCTAssertTrue(app.staticTexts["3 cartas"].firstMatch.exists, "El resumen no cuenta las copias")
        shot(app, "3-deseos")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
