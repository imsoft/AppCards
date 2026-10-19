import XCTest

/// Capturas de búsquedas donde antes faltaban imágenes.
final class ImagesUITests: XCTestCase {
    func testMissingImagesNowLoad() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-uiTestsResetData", "-tab", "search"]
        app.launch()
        search(app, game: "Pokémon", text: "pikachu", wait: "Pikachu")
        // Bajar a promos sin imagen en TCGdex.
        for _ in 0..<6 { app.swipeUp(); usleep(300_000) }
        sleep(5)
        shot(app, "1-pokemon")

        search(app, game: "One Piece", text: "OP16-036", wait: "Bon")
        sleep(5)
        shot(app, "2-op-oficial")
        search(app, game: "One Piece", text: "EB05-045", wait: "Monday")
        sleep(5)
        shot(app, "3-op-sin-imagen")
    }

    private func search(_ app: XCUIApplication, game: String, text: String, wait: String) {
        app.buttons[game].firstMatch.tap()
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", wait)).firstMatch.waitForExistence(timeout: 180))
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
