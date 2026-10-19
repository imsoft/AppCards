import XCTest

/// Capturas para revisar a ojo: precios en la cuadrícula, deck de varios colores y perfil de carta.
final class VisualCheckUITests: XCTestCase {
    func testVisualCheck() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        field.typeText("black lotus\n")
        let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Lotus'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20))
        sleep(4)
        shot(app, "1-precios")

        tiles.element(boundBy: 0).tap()
        sleep(4)
        shot(app, "2-perfil")
        app.swipeUp(); sleep(1)
        shot(app, "3-perfil-desplazado")

        app.terminate()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "decks"]
        app.launch()
        app.buttons["Nuevo deck"].firstMatch.tap()
        let name = app.textFields["Nombre"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Golgari")
        app.buttons["Verde"].tap()
        app.buttons["Grafito"].tap()
        app.buttons["Crear"].tap()
        sleep(2)
        shot(app, "4-deck-colores")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
