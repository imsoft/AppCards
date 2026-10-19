import XCTest

/// Capturas de las columnas izquierdas en iPad (vertical y horizontal).
final class IPadColumnsUITests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Solo iPad")
    }

    func testColumns() throws {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for tab in ["collection", "decks", "wishlist"] {
                let app = XCUIApplication()
                app.launchArguments = ["-uiTestsSkipAuth", "-tab", tab]
                app.launch()
                sleep(3)
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "\(orientation == .portrait ? "v" : "h")-\(tab)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
