import XCTest

/// Capturas de pantallas clave para revisión visual.
final class ScreensTourUITests: XCTestCase {
    /// Sin sesión, la app solo muestra la pantalla de entrar; crear cuenta pide el nombre.
    func testGateShowsOnlyAuthWhenSignedOut() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "search"]
        app.launch()
        let email = app.textFields["Correo"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "Sin sesión debe verse la pantalla de entrar")
        XCTAssertFalse(app.buttons["Buscar"].exists, "Sin sesión no debe verse el menú de la app")
        XCTAssertFalse(app.buttons["Cerrar"].exists, "El candado no se puede cerrar")
        shot(app, "1-candado-login")

        XCTAssertFalse(app.textFields["Tu nombre"].exists)
        app.buttons["Crear cuenta"].firstMatch.tap()
        let name = app.textFields["Tu nombre"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "Crear cuenta debe pedir el nombre")
        name.tap()
        name.typeText("Brandon García")
        email.tap()
        email.typeText("yo@correo.com")
        sleep(1)
        shot(app, "2-candado-crear-cuenta")
    }

    func testAuthAndFiltersScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsSkipAuth", "-tab", "search"]
        app.launch()
        app.buttons["filter-button"].firstMatch.tap()
        sleep(3)
        shot(app, "4-filtros-arriba")
        app.swipeUp()
        sleep(1)
        shot(app, "5-filtros-abajo")
        let subtype = app.textFields["filter-subtype"]
        XCTAssertTrue(subtype.waitForExistence(timeout: 5), "No hay campo de subtipo")
        subtype.tap()
        subtype.typeText("Elf")
        app.buttons["Aplicar"].tap()
        sleep(5)
        shot(app, "6-resultados-con-chips")
        XCTAssertTrue(app.buttons["Quitar filtro Elf"].waitForExistence(timeout: 5), "No aparece el chip del filtro")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
