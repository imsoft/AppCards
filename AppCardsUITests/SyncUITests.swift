import XCTest

/// Sincronización real entre dos dispositivos contra un Supabase local.
/// Se corre por pasos en dos simuladores distintos con SYNC_EMAIL / SYNC_PASSWORD en el entorno.
final class SyncUITests: XCTestCase {
    private var email: String { ProcessInfo.processInfo.environment["SYNC_EMAIL"] ?? "" }
    private var password: String { ProcessInfo.processInfo.environment["SYNC_PASSWORD"] ?? "" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(email.isEmpty, "Sin SYNC_EMAIL: prueba de sincronización omitida")
    }

    /// Paso 1 (iPhone): inicia sesión, agrega una carta a la colección y crea un deck.
    func test1_DeviceAWritesData() throws {
        let app = launch(tab: "settings")
        signIn(app)

        relaunch(app, tab: "search")
        let search = openSearch(app)
        search.tap()
        search.typeText("sol ring")
        let add = app.buttons["Agregar una a la colección"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()
        sleep(2)

        relaunch(app, tab: "decks")
        app.buttons["Nuevo deck"].firstMatch.tap()
        let name = app.textFields["Nombre"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Deck del iPhone")
        app.buttons["Crear"].tap()
        sleep(6) // debounce de 3 s + subida
        relaunch(app, tab: "settings")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sincronizado'")).firstMatch.waitForExistence(timeout: 20), "No se ve Sincronizado en la tarjeta de cuenta")
        shot(app, "A-sincronizado")
    }

    /// Paso 2 (iPad): inicia sesión con la misma cuenta y debe ver lo del iPhone; luego crea su propio deck.
    func test2_DeviceBReadsAndWrites() throws {
        let app = launch(tab: "settings")
        signIn(app)
        sleep(4)

        relaunch(app, tab: "collection")
        XCTAssertTrue(app.buttons["collection-tile"].firstMatch.waitForExistence(timeout: 20), "La carta del iPhone no llegó")
        shot(app, "B-coleccion")

        relaunch(app, tab: "decks")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Deck del iPhone'")).firstMatch.waitForExistence(timeout: 20), "El deck del iPhone no llegó")
        app.buttons["Nuevo deck"].firstMatch.tap()
        let name = app.textFields["Nombre"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Deck del iPad")
        app.buttons["Crear"].tap()
        sleep(6)
        shot(app, "B-decks")
    }

    /// Paso 3 (iPhone otra vez): debe ver el deck creado en el iPad.
    func test3_DeviceASeesDeviceB() throws {
        let app = launch(tab: "decks")
        sleep(4)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Deck del iPad'")).firstMatch.waitForExistence(timeout: 20), "El deck del iPad no llegó al iPhone")
        shot(app, "A-decks")
    }

    /// Crear cuenta con nombre: debe quedar en la cuenta y verse en Ajustes.
    func test0_SignUpStoresName() throws {
        let app = launch(tab: "settings")
        let unique = "nombre\(Int(Date().timeIntervalSince1970))@test.dev"
        app.buttons["Crear cuenta"].firstMatch.tap()
        let name = app.textFields["Tu nombre"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Brandon García")
        let field = app.textFields["Correo"]
        field.tap()
        field.typeText(unique)
        let secure = app.secureTextFields["Contraseña"]
        secure.tap()
        dismissStrongPasswordSuggestion(app)
        secure.tap()
        secure.typeText(password)
        app.buttons["auth-submit"].tap()
        XCTAssertTrue(app.staticTexts["Brandon García"].waitForExistence(timeout: 20), "El nombre no aparece en la tarjeta de cuenta")
        shot(app, "nombre-en-ajustes")
        relaunch(app, tab: "settings")
        XCTAssertTrue(app.staticTexts["Brandon García"].waitForExistence(timeout: 10), "El nombre no persiste al reabrir")
    }

    /// Olvidé mi contraseña: correo → enlace abre Vault → contraseña nueva → ya se puede entrar con ella.
    func test4_PasswordRecovery() throws {
        let env = ProcessInfo.processInfo.environment
        guard let api = env["SYNC_API"], let key = env["SYNC_ANON"], let mail = env["SYNC_MAILPIT"] else {
            throw XCTSkip("Sin Supabase local")
        }
        let user = "recupera\(Int(Date().timeIntervalSince1970))@test.dev"
        XCTAssertEqual(try http("POST", "\(api)/auth/v1/signup", key: key, body: ["email": user, "password": "vieja123"]).status, 200)

        let app = XCUIApplication()
        app.launchArguments = ["-tab", "settings"]
        app.launch()
        let field = app.textFields["Correo"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(user)
        app.buttons["auth-forgot"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Te mandamos un correo'")).firstMatch.waitForExistence(timeout: 15))

        // Busca el correo en el buzón de prueba y sigue el enlace hasta la URL que abre la app.
        var link: String?
        for _ in 0..<20 where link == nil {
            sleep(1)
            let list = try http("GET", "\(mail)/api/v1/search?query=to:\(user)", key: nil, body: nil)
            if let id = ((list.json?["messages"] as? [[String: Any]])?.first?["ID"] as? String) {
                let message = try http("GET", "\(mail)/api/v1/message/\(id)", key: nil, body: nil)
                let text = (message.json?["Text"] as? String) ?? ""
                link = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()<>\""))).first { $0.contains("/auth/v1/verify") }
            }
        }
        let verify = try XCTUnwrap(link, "No llegó el correo de recuperación")
        let location = try XCTUnwrap(try http("GET", verify, key: nil, body: nil, followRedirects: false).location)
        XCTAssertTrue(location.hasPrefix("imsoft-vault://auth-callback"), "El enlace no regresa a la app: \(location)")
        app.open(URL(string: location)!)

        let first = app.secureTextFields["Contraseña nueva"]
        XCTAssertTrue(first.waitForExistence(timeout: 15), "No apareció la pantalla de contraseña nueva")
        shot(app, "recuperar-contrasena")
        first.tap(); first.typeText("nueva456")
        let second = app.secureTextFields["Repite la contraseña"]
        second.tap(); second.typeText("nueva456")
        app.buttons["new-password-save"].tap()
        XCTAssertTrue(app.buttons["Ajustes"].waitForExistence(timeout: 15), "No quedó con la sesión iniciada")

        let login = try http("POST", "\(api)/auth/v1/token?grant_type=password", key: key, body: ["email": user, "password": "nueva456"])
        XCTAssertEqual(login.status, 200, "La contraseña nueva no funciona")
    }

    private struct HTTPResult { let status: Int; let json: [String: Any]?; let location: String? }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }

    private func http(_ method: String, _ url: String, key: String?, body: [String: String]?, followRedirects: Bool = true) throws -> HTTPResult {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        if let key { request.setValue(key, forHTTPHeaderField: "apikey") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let session = followRedirects ? URLSession.shared : URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        var result: HTTPResult?
        let done = expectation(description: url)
        session.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            result = HTTPResult(status: http?.statusCode ?? 0, json: json, location: http?.value(forHTTPHeaderField: "Location"))
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return try XCTUnwrap(result)
    }

    // MARK: Ayudas

    /// iOS ofrece "¿Usar contraseña segura?" al crear cuenta; la prueba la cierra para escribir la suya.
    private func dismissStrongPasswordSuggestion(_ app: XCUIApplication) {
        guard app.buttons["Rellenar contraseña segura"].waitForExistence(timeout: 3)
                || app.buttons["Use Strong Password"].exists else { return }
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Cerrar', 'Close', 'Ahora no', 'Not Now', 'Elegir mi propia contraseña', 'Choose My Own Password'}")).firstMatch
        if close.exists { close.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.62)).tap() }
        sleep(1)
    }

    /// Con el candado, al abrir sin sesión aparece la pantalla de entrar.
    private func signIn(_ app: XCUIApplication) {
        let field = app.textFields["Correo"]
        guard field.waitForExistence(timeout: 8) else { return } // ya tenía sesión
        field.tap()
        field.typeText(email)
        let secure = app.secureTextFields["Contraseña"]
        secure.tap()
        secure.typeText(password)
        app.buttons["auth-submit"].tap()
        XCTAssertTrue(app.buttons["Ajustes"].waitForExistence(timeout: 20), "No se pudo iniciar sesión")
    }

    private func launch(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", tab]
        app.launch()
        return app
    }

    private func relaunch(_ app: XCUIApplication, tab: String) {
        app.terminate()
        app.launchArguments = ["-tab", tab]
        app.launch()
    }

    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) { return field }
        let button = app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] 'Search' OR label ==[c] 'Buscar'")).firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
