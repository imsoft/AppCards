# Vault (App Cards)

App nativa de iOS y iPadOS (SwiftUI + SwiftData, iOS 18+) para consultar cartas y precios de **Magic**, **Pokémon** y **One Piece**, armar decks y ver cuánto costaría comprarlos en MXN, USD o EUR.

## Correr

```bash
brew install xcodegen   # si no lo tienes
xcodegen generate
open AppCards.xcodeproj
```

Tests: `xcodebuild test -project AppCards.xcodeproj -scheme AppCards -destination 'platform=iOS Simulator,name=iPhone 17'`

El `.xcodeproj` se genera desde `project.yml` y no se versiona.

## Fuentes de datos (gratis, sin API key)

| Juego | Cartas e imágenes | Precios |
|---|---|---|
| Magic | Scryfall `api.scryfall.com` | USD (TCGplayer) y EUR (Cardmarket), vienen en la misma respuesta |
| Pokémon | TCGdex `api.tcgdex.net/v2/en` | TCGplayer (USD) y Cardmarket (EUR) en `pricing` |
| One Piece | tcgcsv.com (volcado diario de TCGplayer, categoría 68) | TCGplayer (USD) por variante |

One Piece no tiene API de búsqueda, así que la primera búsqueda descarga el catálogo completo (~7,600 cartas, 87 sets) y lo guarda 24 h en Caches.

Tipo de cambio: Frankfurter (`api.frankfurter.dev`), con opción de tipo de cambio manual USD→MXN en Ajustes.

## Look and feel

Nativa iOS, tema según el sistema, acento azul `#2F5BEA`. Cuadrícula de cartas con insignias (×N que tienes, corazón si está en deseos), cifras grandes con cambio del día, precio en tu moneda grande con el original pequeño, y colores semánticos: verde bajó / ya la tienes, rojo subió / te falta, ámbar precio con más de 7 días.

## Funciones

- **Buscar** por nombre o número, con filtros por set, color/tipo de energía, tipo de carta, costo, rareza, solo paralelas (One Piece) y orden por precio. Con filtros se puede explorar un set sin escribir nada.
- **Colección** con +1 rápido (swipe en resultados o botón en el detalle), precio de mercado y precio local pagado.
- **Decks** con "qué me falta" descontando la colección, impresión más barata por defecto, e **importar listas de One Piece** pegando texto (`4xOP01-003`, `4 OP01-003`, `4 Luffy (OP01-003)` o solo nombre).

- **Historial de precios** por carta (un punto por día cada vez que se consulta), **lista de deseos** con precio objetivo y notificación local al alcanzarlo o al bajar 5%, y **valor de la colección en el tiempo**. Se actualiza al abrir la app y una vez al día con `BGAppRefreshTask` (`com.imsoft.appcards.refresh`).

- **Escáner con cámara** (botón de cámara en Buscar y Colección): Vision lee el texto de la carta. One Piece por número (`OP01-003`), Pokémon por nombre y `N/Total`, Magic por nombre y código de set (`BLB • EN`). En simulador, sin cámara, hay un campo de texto para probar el flujo.

## iCloud

El proyecto ya trae el entitlement de CloudKit (`iCloud.com.imsoft.appcards`). Para que sincronice entre iPhone y iPad:

1. Pon tu `DEVELOPMENT_TEAM` en `project.yml` y vuelve a correr `xcodegen generate`.
2. En Xcode, Signing & Capabilities → iCloud → crea el contenedor con ese identificador.
3. Prueba en dispositivos reales con la misma cuenta de iCloud.

Si el entitlement no está firmado (por ejemplo en simulador sin team), la app cae a base de datos local sin fallar.

## Estructura

- `AppCards/Models` — `CardSummary`, `CardDetail`, `PriceQuote`, modelos SwiftData `Deck`/`DeckEntry` y `DeckMath`.
- `AppCards/Services` — `CardProvider` y una implementación por juego, `OnePieceCatalog`, `CurrencyConverter`.
- `AppCards/Features` — Buscar, detalle de carta, colección, decks y ajustes.
- `AppCardsTests` — decodificación con respuestas reales de cada API, búsqueda del catálogo, conversión y totales.
