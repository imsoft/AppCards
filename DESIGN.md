# Sistema de diseño de Vault

Reglas que toda pantalla sigue. Si una pantalla nueva necesita algo que no está aquí, primero se agrega la regla.

## Tipos de pantalla

| Tipo | Ejemplos | Contenedor | Fondo | Título |
|---|---|---|---|---|
| **Explorar** (ver muchas cartas) | Buscar, Colección | `ScrollView` + `CardGrid` | `ScreenBackground` del color de contexto | inline |
| **Lista editable** (filas con acciones) | Decks, Deseos, detalle de deck | `List` inset grouped sobre `ScreenBackground` | `ScreenBackground` | inline |
| **Detalle de carta** | detalle de carta | `ScrollView` + `SectionCard` | `ScreenBackground` del juego | inline |
| **Editor / ajustes** | ficha de colección, ficha de deseo, Ajustes, filtros, hojas | `Form` | sistema | inline |

## iPhone y iPad

- iPhone: solo vertical, pestañas abajo.
- iPad: todas las orientaciones. Las pestañas se vuelven barra lateral (`.sidebarAdaptable`).
- Pantallas de **lista editable** y **Colección** usan `AdaptiveSplitView`: en iPad, lista a la izquierda y detalle a la derecha; en iPhone o ventana angosta, navegación normal. Los elementos se enlazan con `ItemLink`, nunca con `NavigationLink(value:)` directo.
- **Detalle de carta** en iPad: carta a la izquierda (400 pt), información a la derecha (máx. 620 pt).
- La cuadrícula ya es adaptable: no se fija número de columnas.

## Decks

- Cada deck puede tener hasta 3 colores (`Deck.accentColors`, en orden); si no, usa el del juego. Se usan en degradado en el encabezado y el contador de cartas.
- Las tarjetas no llevan barras laterales de color. Un deck se distingue por su fondo suave con sus colores, un borde fino en degradado, puntitos de color junto al nombre y el contador de cartas.
- "Eliminar deck" está en el menú ⋯ del deck y siempre pide confirmación.
- Lo que tienes de cada carta se muestra con `OwnershipRing` ("2/4", palomita verde al completar), nunca con textos como "Completa" o "Faltan 2".
- Tres vistas (Lista, Cuadrícula, Por estado) y un menú de orden; ambos se recuerdan.
- "Opciones y sustituciones" es una sección aparte que no cuenta en el total del deck; muestra su propio subtotal.
- Las secciones del deck son tarjetas (`DeckSectionCard`), no una lista del sistema: así arrastrar y soltar funciona igual en iPhone y iPad. Mantener presionada una carta y arrastrarla a otra sección la mueve entre deck y opciones; la sección destino se ilumina con borde punteado y "Suelta aquí".
- Tocar una carta abre `DeckEntryEditSheet` con todas sus acciones. No hay menú de pulsación larga en las cartas del deck: la pulsación larga es para arrastrar.
- Una opción puede enlazarse a la carta del deck que sustituiría (`DeckSubstitution`). Se muestra "⇄ Sustituye a X" con la diferencia de costo (verde si sale más barato, rojo si más caro). "Hacer el cambio" va arriba en la hoja de la carta y también al deslizar; la carta que sale queda en opciones enlazada al revés, para deshacer con el mismo botón.

## Seguridad contra cierres

- Toda pantalla que muestra un dato guardado revisa primero `isGone` y, si se borró (aquí o desde el otro dispositivo), muestra `DeletedPlaceholder`.
- Borrar desde la propia pantalla usa `SafeDeletion.delete`: primero cierra, luego borra.
- Nada de `fatalError` ni `!` en datos que vienen de fuera. Si la base local no abre, se aparta y se crea otra.
- `DeckActionsUITests` oprime cada botón del menú del deck en las tres vistas; si agregas un botón, agrégalo ahí.

## Dinero en la cuadrícula

- Las imágenes de la cuadrícula ocupan siempre el mismo marco de carta (0.716), para que las etiquetas de precio queden a la misma altura.
- `PriceSticker`: precio completo en un renglón y la moneda abajo, nunca partido.
- En filas con varias copias: total de lo que falta en tu moneda y debajo el precio "c/u" en tu moneda.

## Hojas

- Toda hoja usa `.sheetSize()`: en iPad abre completa; en iPhone completa salvo las cortas (`shortOnPhone: true`, como elegir color).

## Filtros

- Los filtros activos se muestran como chips quitables (`ActiveFilterChips`) debajo del selector de juego, con "Limpiar todo".
- La hoja de filtros agrupa en secciones con encabezado del color del juego: Mostrar y ordenar, Texto y subtipo, Colección y formato, Características, Números, Precio.
- Un filtro que la fuente no soporta no se muestra, o se explica en el pie de la sección.
- Los campos de texto en formularios siempre llevan etiqueta visible (`LabeledContent`), no solo el texto de ejemplo.

## Estructura fija de cada pestaña

1. Barra con título inline y acciones a la derecha (máximo dos íconos, o un menú `⋯`).
2. Si filtra por juego: `GameSelector` justo debajo de la barra.
3. Si tiene totales: una `GradientCard` de resumen como primer elemento (Colección, Decks, Deseos, detalle de deck).
4. Contenido.
5. Vacío: `EmptyStateView` con el color de contexto.

## Color de contexto

- Azul Vault: la app, "Todo", dinero propio (MXN).
- Morado Magic, ámbar Pokémon, verde azulado One Piece: solo para identificar juego. Nunca para estados.
- Verde = ya lo tienes / bajó. Rojo = te falta / subió. Gris con reloj = precio viejo. Rosa = deseos.
- Sobre ámbar el texto va oscuro (`Game.onColor`). Sobre los demás, blanco.

## Dinero

- Siempre `MoneyText` (número + etiqueta de moneda) o `PriceLabel` (convertido grande, original pequeño). Nunca `Text` con un string de dinero.
- MXN azul, USD y EUR gris. El código de moneda siempre visible.
- Cifra protagonista de una pantalla: `BigAmountView` dentro de `GradientCard`.
- Precio estimado en tienda: siempre `StorePriceLine`, debajo del precio de mercado, con ícono de tienda. Nunca sustituye al precio de mercado.

## Filas e ítems

- Cuadrícula para explorar: `CardGridTile` (imagen, sticker de precio, insignias ×N y corazón).
- Fila para editar: `ItemRow` (miniatura 44, nombre, línea de set, línea de estado, contenido a la derecha).
- Nombre de carta o deck: tipografía redondeada, semibold. Todo lo demás, tipografía del sistema.
- Acciones secundarias: swipe en filas, menú contextual en cuadrícula. La acción principal siempre tiene un botón visible.
- Toda imagen de carta en un perfil o fila editable es `CardImageButton` (abre el visor 3D, con iconito de expandir). Excepción: dentro de un `NavigationLink`, donde el toque ya navega; ahí el visor va en el menú contextual ("Ver carta completa").

## Espaciado

- Margen horizontal 20. Entre secciones 24. Entre cartas de cuadrícula 18 horizontal y 24 vertical. Radio de tarjeta 18.

## Movimiento

Toda animación tiene un propósito: mostrar que algo llegó, cambió o respondió. Nada se mueve en bucle ni por decorar. Todo respeta "Reducir movimiento".

| Qué | Cuándo | Cómo |
|---|---|---|
| `floatIn` | Tarjeta de resumen y secciones al abrir una pantalla | Sube 18 pt con resorte, secciones escalonadas 0.05 s |
| `staggeredAppear` | Cartas de cuadrícula y tarjetas de deck | Cascada de 0.04 s por elemento, máximo 0.4 s |
| `animatedNumber` | Cualquier cifra o contador que cambia | Transición de dígitos, nunca un salto |
| `PressableStyle` | Todo lo que se toca y navega: cartas, decks, botón + | Se encoge a 96 % mientras se presiona |
| Barras de progreso | Cuando cambia lo que tienes | Resorte |
| Insignias ×N, "Completa", "Tienes" | Al aparecer o cambiar de estado | Escala con fundido |
| Íconos de acción (+, corazón) | Al tocarlos | `symbolEffect(.bounce)` |
| Abanico de estado vacío | Al aparecer | Se abre desde cerrado |
| Visor de carta (`CardViewer`) | Al tocar la imagen del detalle | Crece desde el centro; arrastrar inclina en 3D hasta 28° con brillo holográfico y regresa con rebote; el giroscopio suma ±10° (apagado con Reducir movimiento) |

Duraciones en `Motion`: `snappy` 0.3 s para números, `spring` para entradas y estados, `gentle` 0.35 s para cambios de filtro o juego.
