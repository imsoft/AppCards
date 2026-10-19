import XCTest

/// Recorre la app en iPad horizontal y guarda capturas de cada pantalla.
final class IPadLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Solo iPad")
    }

    func testLandscapeTour() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "search"]
        app.launch()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("sol ring\n")
        let add = app.buttons["Agregar una a la colección"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()
        sleep(3)
        shot(app, "1-buscar")

        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sol Ring'")).firstMatch.tap()
        sleep(4)
        shot(app, "2-perfil-carta")

        relaunch(app, tab: "collection")
        let tile = app.buttons["collection-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        shot(app, "3-coleccion-vacia-derecha")
        tile.tap()
        sleep(3)
        shot(app, "4-coleccion-con-ficha")

        relaunch(app, tab: "decks")
        let newDeck = app.buttons["Nuevo deck"].firstMatch
        XCTAssertTrue(newDeck.waitForExistence(timeout: 10))
        newDeck.tap()
        let name = app.textFields["Nombre"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Prueba iPad")
        app.buttons["Crear"].tap()
        sleep(2)
        let deck = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Prueba iPad'")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        deck.tap()
        sleep(2)
        shot(app, "5-decks-con-detalle")

        relaunch(app, tab: "wishlist")
        sleep(2)
        shot(app, "6-deseos")

        relaunch(app, tab: "settings")
        sleep(2)
        shot(app, "7-ajustes")

        XCUIDevice.shared.orientation = .portrait
        relaunch(app, tab: "collection")
        sleep(3)
        shot(app, "8-coleccion-vertical")
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
