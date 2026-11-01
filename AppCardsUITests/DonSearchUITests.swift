import XCTest

/// Las cartas DON!! de One Piece se encuentran buscando "DON".
final class DonSearchUITests: XCTestCase {
    func testSearchDonCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "search"]
        app.launch()
        app.buttons["One Piece"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch.tap()
        }
        field.tap()
        field.typeText("DON")
        let don = app.buttons.matching(NSPredicate(format: "label CONTAINS 'DON!!'")).firstMatch
        XCTAssertTrue(don.waitForExistence(timeout: 180), "No aparecieron cartas DON!!")
        sleep(4)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "1-don"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
