import XCTest

final class PricesAndDeckFilterUITests: XCTestCase {
    /// En Pokémon, los precios aparecen en los resultados aunque TCGdex no los mande en la lista.
    func testPokemonSearchShowsPrices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "search"]
        app.launch()
        app.buttons["Pokémon"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        field.typeText("charizard")
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Charizard'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "No hubo resultados")
        let priced = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Charizard' AND label CONTAINS '$'")).firstMatch
        XCTAssertTrue(priced.waitForExistence(timeout: 30), "Las cartas de Pokémon siguen sin precio")
        sleep(3)
        shot(app, "1-pokemon-precios")
    }

    /// La lista de decks se filtra por juego y por nombre.
    func testFilterDecks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "decks"]
        app.launch()
        newDeck(app, name: "Elfos verdes", game: "Magic")
        newDeck(app, name: "Pikachu rápido", game: "Pokémon")
        newDeck(app, name: "Luffy rojo", game: "One Piece")

        let elfos = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Elfos verdes'")).firstMatch
        let pikachu = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pikachu rápido'")).firstMatch
        let luffy = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Luffy rojo'")).firstMatch
        XCTAssertTrue(luffy.waitForExistence(timeout: 5))

        app.buttons["Pokémon"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(pikachu.exists)
        XCTAssertFalse(elfos.exists, "El filtro de juego no quitó el deck de Magic")
        XCTAssertFalse(luffy.exists)
        shot(app, "2-decks-pokemon")

        app.buttons["Todo"].firstMatch.tap()
        sleep(1)
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("luffy")
        sleep(1)
        XCTAssertTrue(luffy.exists)
        XCTAssertFalse(elfos.exists, "La búsqueda no filtró por nombre")
        shot(app, "3-decks-busqueda")
    }

    private func newDeck(_ app: XCUIApplication, name: String, game: String) {
        app.buttons["Nuevo deck"].firstMatch.tap()
        let field = app.textFields["Nombre"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name)
        app.buttons.matching(NSPredicate(format: "label == %@", game)).element(boundBy: app.buttons.matching(NSPredicate(format: "label == %@", game)).count - 1).tap()
        app.buttons["Crear"].tap()
        sleep(1)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
