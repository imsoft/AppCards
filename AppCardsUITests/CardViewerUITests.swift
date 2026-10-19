import XCTest

final class CardViewerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTappingCardImageOpensViewer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "search"]
        app.launch()

        let search = openSearch(app)
        search.tap()
        search.typeText("sol ring")

        let firstCard = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sol Ring'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "No aparecieron resultados")
        firstCard.tap()

        let image = app.descendants(matching: .any).matching(identifier: "card-hero-image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 15), "No apareció la imagen del perfil")
        sleep(4) // que la imagen termine de cargar, como en el iPhone con caché
        attach(app, "perfil")
        image.tap()

        let close = app.buttons["Cerrar"]
        let opened = close.waitForExistence(timeout: 5)
        attach(app, "despues-de-tocar")
        XCTAssertTrue(opened, "Tocar la imagen no abrió el visor")

        let viewerCard = app.descendants(matching: .any).matching(identifier: "card-viewer-card").firstMatch
        XCTAssertTrue(viewerCard.exists)
        let start = viewerCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)); start.press(forDuration: 0.1, thenDragTo: viewerCard.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)))
        close.tap()
        sleep(1)
        attach(app, "despues-de-cerrar")
        XCTAssertTrue(image.waitForExistence(timeout: 5), "Cerrar no regresó al perfil")
    }

    /// Mismo flujo pero llegando al perfil desde el escáner (en simulador usa el campo manual).
    func testTappingCardImageFromScannerOpensViewer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "search"]
        app.launch()

        let scan = app.buttons["Escanear"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()
        allowSystemAlertIfShown()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No apareció el campo manual del escáner")
        field.tap()
        field.typeText("Sol Ring")
        app.buttons["Leer"].tap()

        let link = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Toca para ver'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20), "No apareció el resultado del escáner")
        attach(app, "resultado-escaner")
        link.tap()
        sleep(2)
        attach(app, "despues-de-tocar-resultado")

        let image = app.descendants(matching: .any).matching(identifier: "card-hero-image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 15), "No apareció el perfil desde el escáner")
        sleep(4)
        attach(app, "perfil-desde-escaner")
        image.tap()

        let opened = app.buttons["Cerrar"].waitForExistence(timeout: 5)
        attach(app, "despues-de-tocar-desde-escaner")
        XCTAssertTrue(opened, "Desde el escáner, tocar la imagen no abrió el visor")
    }

    /// Colección → carta → tocar la imagen abre el visor (el caso que reportó Brandon).
    func testTappingCardImageInCollectionOpensViewer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "search"]
        app.launch()

        let search = openSearch(app)
        search.tap()
        search.typeText("sol ring")

        let add = app.buttons["Agregar una a la colección"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "No apareció el botón + en los resultados")
        add.tap()
        sleep(2)
        attach(app, "despues-de-agregar")

        // Con el teclado abierto la barra de pestañas se oculta: reabrimos directo en Colección.
        app.terminate()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "collection"]
        app.launch()
        let tile = app.buttons["collection-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "La carta no aparece en Colección")
        attach(app, "coleccion")
        tile.tap()

        let image = app.buttons["card-image-button"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10), "No hay imagen tocable en la ficha de colección")
        sleep(3)
        attach(app, "ficha-coleccion")
        image.tap()

        let close = app.buttons["Cerrar"]
        let opened = close.waitForExistence(timeout: 5)
        attach(app, "visor-desde-coleccion")
        XCTAssertTrue(opened, "Desde Colección, tocar la imagen no abrió el visor")
        close.tap()
        XCTAssertTrue(image.waitForExistence(timeout: 5), "Cerrar no regresó a la ficha de colección")
    }

    /// En iPad vertical la búsqueda es un botón con lupa en la barra; en iPhone es un campo visible.
    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) { return field }
        let button = app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar' OR identifier ==[c] 'magnifyingglass'")).firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No apareció la búsqueda")
        return field
    }

    /// Acepta el aviso de permiso de cámara si aparece (instalación limpia).
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Permitir", "OK", "Aceptar"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) { button.tap(); return }
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
