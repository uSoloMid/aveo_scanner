# Aveo Scanner — Especificación técnica (Fase 2 + núcleo de Fase 3)

Documento de contrato para quien implemente. El README explica el *qué* y el *por qué*; este documento fija el *cómo*. Si algo aquí contradice al README, **manda este documento**. Si algo no está definido, elige lo más simple y déjalo anotado en `docs/DECISIONS.md`.

---

## 0. Reglas generales

- Dart 3 / Flutter estable (3.47). Solo Android.
- **Dependencias permitidas** (ya están en `pubspec.yaml`, no agregar otras sin aprobación):
  `flutter_riverpod`, `sqflite`, `path`, `path_provider`, `permission_handler`, `wakelock_plus`; dev: `sqflite_common_ffi`, `flutter_test`, `flutter_lints`.
- Bluetooth clásico: **platform channel propio en Kotlin** (sección 9). Nada de paquetes de Bluetooth.
- Estado: Riverpod 3 **sin generación de código** (`Provider`, `NotifierProvider`, `StreamProvider`, `FutureProvider`).
- Modelos inmutables (`final` en todo, `const` constructores, `copyWith` cuando haga falta). Nada de `dynamic` salvo al leer JSON.
- Textos de la UI **en español**. Identificadores y comentarios de código en inglés.
- Archivos de 200–400 líneas, máximo 800. Funciones de menos de ~50 líneas.
- Sin `print`. Usar `dart:developer` `log()` o el `TrafficLog` (sección 4.4).
- `flutter analyze` sin issues y `flutter test` en verde al terminar **cada lote**.
- Todo el código de `lib/core` y `lib/obd` es Dart puro (sin `package:flutter`), para que se pruebe con `flutter test` sin dispositivo.

---

## 1. Estructura

```
lib/
├── main.dart
├── app.dart                         # MaterialApp, tema, navegación
├── core/
│   ├── transport/
│   │   ├── transport.dart
│   │   ├── bt_classic_transport.dart
│   │   ├── bt_classic_channel.dart  # wrapper del MethodChannel/EventChannel
│   │   └── mock_transport.dart
│   ├── elm327/
│   │   ├── elm327.dart
│   │   ├── elm_response.dart        # modelos de respuesta / errores
│   │   ├── response_parser.dart
│   │   └── traffic_log.dart
│   └── safety/
│       └── command_guard.dart
├── obd/
│   ├── pid.dart
│   ├── standard_pids.dart
│   ├── supported_pids.dart
│   ├── dtc.dart
│   ├── dtc_descriptions_es.dart
│   ├── vehicle_info.dart            # VIN, CALID, CVN (modo 09)
│   └── obd_service.dart             # API de alto nivel sobre Elm327
├── data/
│   ├── database.dart
│   ├── session_repository.dart
│   └── backup_repository.dart
└── ui/
    ├── providers.dart
    ├── theme.dart
    ├── connect_screen.dart
    ├── dashboard_screen.dart
    ├── dtc_screen.dart
    ├── backup_screen.dart
    ├── terminal_screen.dart
    └── widgets/ (gauge_tile.dart, confirm_dialogs.dart, …)
android/app/src/main/kotlin/mx/solomid/aveo_scanner/
├── MainActivity.kt
└── BtClassicPlugin.kt
test/  (espejo de lib/: core/, obd/, data/, ui/)
```

`ble_transport.dart` y `profile_loader.dart` **no** entran en esta fase.

---

## 2. `CommandGuard` — seguridad (crítico)

`lib/core/safety/command_guard.dart`. Es la **única** puerta hacia el adaptador. `Elm327` lo llama en cada envío; ningún otro código escribe al `Transport`.

```dart
enum GuardVerdict { allowed, needsConfirmation, blocked }

final class GuardResult {
  final GuardVerdict verdict;
  final String normalized;   // comando limpio: sin espacios, mayúsculas
  final String reason;       // explicación en español (para UI y log)
}

abstract final class CommandGuard {
  static GuardResult check(String raw);
}
```

### Normalización
1. Si `raw` contiene **cualquier** carácter de control (`\r`, `\n`, `\t`, código < 0x20 o 0x7F) → `blocked` ("caracteres de control no permitidos"). Esto evita meter dos comandos en uno.
2. Quitar espacios (solo `' '`), pasar a mayúsculas.
3. Vacío → `blocked`.
4. Largo máximo 32 → si no, `blocked`.

### Comandos AT (empiezan con `AT`)
- Solo `[A-Z0-9]` después de `AT`; si no → `blocked`.
- Bloqueados (prefijo, tras `AT`): `MA`, `MR`, `MT` (monitores de bus), `PP` (parámetros programables), `BRD`, `BRT` (cambio de baudios). Esa es la lista exacta; `ATWS` y el resto están permitidos.
- Cualquier otro AT → `allowed`.

### Comandos OBD (todo lo demás)
- Solo dígitos hex `[0-9A-F]`; si no → `blocked` (esto bloquea comandos `ST...` de STN y basura).
- Largo par y ≥ 2; si no → `blocked`.
- Servicio = primeros 2 caracteres:
  - `allowed`: `01 02 03 07 09 0A 22 13`
  - `needsConfirmation`: `04 14 AE`
  - todo lo demás → `blocked` (incluye `10 11 27 2E 3B 31 34 35 36 37` y cualquiera no listado).

### Confirmación
```dart
final class Confirmation {
  final String command;  // comando normalizado que el usuario aprobó
  const Confirmation._(this.command);
  factory Confirmation.userApproved(String command);  // normaliza igual que check()
}
```
`Elm327.send(cmd, {Confirmation? confirmation})`:
- `blocked` → lanza `CommandBlockedException(result)` sin tocar el transporte.
- `needsConfirmation` sin `confirmation` o con `confirmation.command != normalized` → lanza `ConfirmationRequiredException(result)`.
- Cada intento (permitido o no) queda en `TrafficLog`.

### Pruebas obligatorias (`test/core/safety/command_guard_test.dart`)
Tabla con al menos: `010C`, `01 0c`, `0100`, `03`, `07`, `0A`, `0902`, `22 11A1`, `134000`, `ATZ`, `atsp6`, `ATSH7E0`, `ATRV` → allowed. `04`, `14FF00`, `AE01` → needsConfirmation. `10 03`, `1101`, `2701`, `2E1234`, `3B01`, `3101`, `34`, `36`, `37`, `FF`, `ATMA`, `AT MA`, `ATMR01`, `ATMT01`, `ATPPS`, `ATPP0CSV`, `ATBRD45`, `ATBRT`, `""`, `"   "`, `"010C\r04"`, `"010C\n"`, `"ST DI"`, `"01G0"`, `"010"` (impar), `"0"`, cadena de 33 caracteres → blocked. Y pruebas de `Elm327` que verifiquen que `blocked` y `needsConfirmation` sin confirmación **nunca** llegan al `Transport` (con un transporte espía).

---

## 3. Transporte

```dart
abstract interface class Transport {
  Future<void> connect();
  Future<void> disconnect();
  bool get isConnected;
  Future<void> write(List<int> bytes);
  Stream<List<int>> get incoming;   // broadcast
  Stream<TransportState> get state; // disconnected, connecting, connected, error
}
```
`readUntilPrompt` **no** va en el transporte: lo implementa `Elm327` acumulando `incoming` hasta ver `>`.

### `MockTransport` (`mock_transport.dart`)
Simula un ELM327 v1.5 conectado a un Aveo por **CAN 11 bit 500k** (protocolo 6), con `ATE0 ATL0 ATS0 ATH1` aplicados según lo que reciba (por defecto ATZ deja eco encendido, espacios encendidos, encabezados apagados — respetar el estado: si no se mandó `ATS0`, responder con espacios; si no se mandó `ATE0`, repetir el comando).
- Latencia aleatoria 30–80 ms (inyectable para tests: `Duration Function()?` o `Random` con semilla).
- Responde terminando en `\r\r>`.
- `ATZ` → `ELM327 v1.5`; `ATI` → `ELM327 v1.5`; `ATRV` → `12.4V` (13.9V si el motor "está encendido"); `ATDPN` → `A6`; otros AT → `OK`; AT desconocido → `?`.
- Primer comando OBD tras `ATSP0`: antepone `SEARCHING...\r`.
- PIDs soportados (`0100`, `0120`, `0140`): exactamente los de la tabla de la sección 6 más `00 20 40` encadenados.
- Valores que cambian suavemente con el tiempo (RPM 750–3000 ondulando, velocidad 0–80, refrigerante sube de 40 a 90 °C y se queda, voltaje 14.1 V, etc.).
- PID no soportado → `NO DATA`.
- DTC: confirmados `P0133`, `P0300`; pendientes `P0171`; permanentes `P0133`. `04` los borra (confirmados y pendientes; permanentes **no**).
- Freeze frame `0202` → DTC `P0300`; `02xx00` devuelve valores fijos del momento de la falla.
- `0902` → VIN `KL1TD5DE5CB000000` (respuesta multi-trama ISO-TP), `0904` → CALID `12345678ABCDEF` multi-trama, `0906` → CVN 4 bytes.
- `22000D` y `2211A1` responden (`7E8056211A101FF` → 511 s, con tiempo creciente); otros `22xxxx` → `7F2231`.
- Modo debug: `MockTransport(kwp: true)` responde en formato ISO 14230 (protocolo 5, `ATDPN` → `A5`) con encabezado de 3 bytes + checksum, para probar el parser.
- Comando bloqueado nunca debería llegarle; si le llega, responde `?` y registra un `assert`.

---

## 4. ELM327

### 4.1 `Elm327` (`elm327.dart`)
```dart
class Elm327 {
  Elm327(Transport transport, {TrafficLog? log, Clock? clock});
  Future<ElmResponse> send(String cmd, {Duration timeout = const Duration(seconds: 2), Confirmation? confirmation});
  Future<ElmInfo> initialize();  // secuencia de inicio
  Future<void> close();
}
```
- **Cola**: una sola petición en vuelo. Las demás esperan en orden FIFO. Implementar con una cadena de `Future` o un `Completer` por petición; nada de `while(busy) sleep`.
- Escribe `normalized + '\r'` en ASCII.
- Acumula bytes hasta encontrar `>`; el texto antes de `>` es la respuesta cruda.
- Timeout → `ElmTimeoutException`. Tras un timeout, descartar cualquier dato tardío hasta el siguiente `>` antes de mandar el siguiente comando.
- Respuesta `7F xx 78` (respuesta pendiente) → seguir esperando hasta otro `>` con timeout extendido (5 s), máximo 3 veces.
- Límite de ritmo: mínimo 50 ms entre el fin de una respuesta y el siguiente envío (≈ 10 req/s máximo absoluto).

### 4.2 Secuencia `initialize()`
`ATZ` (timeout 3 s, luego esperar 1 s) → `ATE0` → `ATL0` → `ATS0` → `ATH1` → `ATAT1` → `ATSP0` → `ATI` → `0100` (timeout 6 s, tolera `SEARCHING...`) → `ATDPN` → `ATRV`.
Devuelve `ElmInfo { version, protocolCode, protocolName, voltage, supportedPids }`.
Si `0100` da `UNABLE TO CONNECT` → `ElmInitException` con mensaje en español ("¿Está el contacto encendido?").
Nombre de protocolo a partir de `ATDPN` (quitar `A` inicial): 1 J1850 PWM, 2 J1850 VPW, 3 ISO 9141-2, 4 ISO 14230 (5 baud), 5 ISO 14230 (rápido), 6 CAN 11b 500k, 7 CAN 29b 500k, 8 CAN 11b 250k, 9 CAN 29b 250k.

### 4.3 `ResponseParser` (`response_parser.dart`)
Entrada: texto crudo + `ProtocolFamily { can11, can29, kwp, unknown }`. Salida: `ElmResponse`.
- Limpia: `\r`, `\n`, espacios, `SEARCHING...`, `BUS INIT: ...OK` / `BUS INIT...`, eco (línea igual al comando enviado), líneas vacías.
- Errores reconocidos → `ElmResponse.error(ElmError.x)`: `NO DATA`, `?`, `UNABLE TO CONNECT`, `CAN ERROR`, `BUS ERROR`, `BUS BUSY`, `FB ERROR`, `DATA ERROR`, `STOPPED`, `BUFFER FULL`, `ERR\d+`, `LV RESET`.
- Respuestas AT → `ElmResponse.text(String)`.
- Respuestas OBD → `ElmResponse.messages(List<EcuMessage>)`, con `EcuMessage { String ecu; List<int> data; }` donde `data` empieza en el byte de servicio (p. ej. `41 0C 1A F8`).
  - **CAN 11 bit con encabezados**: 3 hex de encabezado + PCI ISO-TP. Trama única `0N` → N bytes. Primera trama `1L LL` + consecutivas `2N`: reensamblar por ECU, en orden del índice de secuencia, recortar al largo declarado.
  - **CAN 29 bit**: igual con 8 hex de encabezado (ECU = últimos 2 bytes).
  - **KWP / ISO 9141 con encabezados**: cada línea = 3 bytes de encabezado (`format target source`) + datos + 1 byte checksum. ECU = byte `source`. Validar checksum (suma mod 256); si falla, descartar la línea y anotar en log.
  - Sin encabezados (por si `ATH1` falla): una línea = datos tal cual, ECU = `'?'`.
- Respuesta negativa `7F SS NN` → `EcuMessage` normal; `ElmResponse.isNegative` y `negativeCode` para que el llamador decida.
- Pruebas con todos los ejemplos del README (`7E804410C1AF8` → RPM 1726, `7E8056211A101FF` → 511), un VIN multi-trama real, una respuesta de 2 ECUs a la vez y respuestas KWP.

### 4.4 `TrafficLog`
Búfer circular (500 entradas) de `TrafficEntry { DateTime at; Direction dir (tx/rx/guard); String text; }` con `Stream` de cambios. Lo usa la pantalla Terminal.

---

## 5. Servicio OBD de alto nivel (`obd_service.dart`)

```dart
class ObdService {
  ObdService(Elm327 elm);
  Future<ElmInfo> connectAndInit();
  Future<Map<int, PidValue>> readPids(List<int> pids);     // modo 01, de uno en uno (clones fallan con multi-PID)
  Future<SupportedPids> readSupportedPids();               // 0100, 0120, 0140, 0160 encadenados según bit 0x20/0x40/…
  Future<List<Dtc>> readDtcs(DtcKind kind);                // 03 / 07 / 0A
  Future<FreezeFrame> readFreezeFrame();                   // 0202 + PIDs soportados en 02 (0200)
  Future<VehicleInfo> readVehicleInfo();                   // 0902, 0904, 0906
  Future<void> clearDtcs(Confirmation confirmation);       // 04 — ver sección 7
}
```
El Elm327 por debajo determina `ProtocolFamily` desde `ATDPN` y lo pasa al parser.

---

## 6. PIDs (`pid.dart`, `standard_pids.dart`, `supported_pids.dart`)

```dart
final class PidDef {
  final int pid; final String nameEs; final String unit;
  final int bytes; final double Function(List<int> d) decode;
  final double min, max;  // para medidores
}
final class PidValue { final int pid; final double value; final DateTime at; }
```
Tabla v1 (exactamente la del README): `04 05 06 07 0B 0C 0D 0E 0F 10 11 1F 2F 42`. Agregar además `01` (estado de monitores: solo decodificar MIL encendido y número de DTC) y `33` (presión barométrica, `A` kPa).
`SupportedPids` decodifica las máscaras de 32 bits (bit más significativo = PID base+1). Pruebas con máscara real ejemplo `BE3EB811` → 01,03,04,05,06,07,0B,0C,0D,0E,0F,11,13,14,15,1C,20.
Consumo: `fuelLph(maf) = maf*3600/(14.7*740)`, `kmPerL(speed, lph)` con `lph < 0.05 → null`.

---

## 7. DTC (`dtc.dart`, `dtc_descriptions_es.dart`)

- `Dtc { String code; DtcKind kind; String? descriptionEs; String ecu; }`, `DtcKind { confirmed, pending, permanent }`.
- Decodificación de 2 bytes según tabla del README. `00 00` = relleno, se ignora.
- CAN: después del byte de servicio (`43`/`47`/`4A`) viene el **conteo**; luego pares. KWP/ISO 9141: sin conteo, 3 pares por mensaje, varios mensajes.
- Descripciones: códigos genéricos SAE J2012 **P0xxx** más comunes (mínimo 150: P0010–P0050, P0100–P0175, P0200–P0310 incl. P0300–P0304, P0325–P0345, P0400–P0460, P0500–P0510, P0560–P0565, P0600–P0606, P0700–P0705, P1xxx no). Solo códigos genéricos cuya descripción conozcas con certeza; si dudas, no lo pongas (la UI dice "Sin descripción, búscalo como código genérico"). Formato: `const Map<String, String> dtcDescriptionsEs`.

### Borrado (`04`) — flujo obligatorio
`ObdService.clearDtcs` y la UI deben, en este orden:
1. Leer RPM (`010C`). Si RPM > 0 → rechazar: "Apaga el motor (deja solo el contacto) antes de borrar códigos."
2. **Respaldo automático** en DB (`backup_repository`): DTC 03/07/0A, freeze frame, VIN si se tiene, fecha. Si el respaldo falla → **no borrar**.
3. Diálogo 1: explica consecuencias (monitores de emisiones, verificación).
4. Diálogo 2: el usuario escribe `BORRAR`. Solo entonces se crea `Confirmation.userApproved('04')`.
5. Enviar `04`. Respuesta esperada `44`. Volver a leer `03` y mostrar resultado.

---

## 8. Datos (`lib/data`)

SQLite con `sqflite` (en tests: `sqflite_common_ffi` con `databaseFactoryFfi` en memoria). Archivo `aveo_scanner.db`, versión 1, migraciones en `onUpgrade` por número.

```sql
CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, ended_at INTEGER, transport TEXT NOT NULL, protocol TEXT, vin TEXT);
CREATE TABLE readings (session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, at INTEGER NOT NULL, pid INTEGER NOT NULL, value REAL NOT NULL);
CREATE INDEX idx_readings_session ON readings(session_id, at);
CREATE TABLE backups (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INTEGER NOT NULL, kind TEXT NOT NULL, -- 'initial' | 'pre_clear'
                      payload TEXT NOT NULL);  -- JSON
```
- Tiempos en milisegundos epoch UTC.
- `SessionRepository`: `start`, `end`, `addReadings(List<PidValue>)` en transacción/batch; la UI agrupa y escribe cada ~1 s (no una escritura por lectura).
- `BackupRepository`: `save(kind, Map payload)`, `list()`, `get(id)`, `exportJson(id)` → escribe el JSON en `getExternalStorageDirectory()/backups/aveo_backup_<fecha>.json` y devuelve la ruta.
- **Respaldo inicial** (pantalla Respaldo): `ATI`, `ATDPN`, `ATRV`, VIN, CALID, CVN, PIDs soportados (todas las máscaras), DTC 03/07/0A, freeze frame, una lectura de cada PID soportado de la tabla. Todo crudo **y** decodificado.

---

## 9. Bluetooth clásico (Kotlin + Dart)

### Kotlin `BtClassicPlugin.kt` (registrado en `MainActivity.configureFlutterEngine`)
- `MethodChannel("mx.solomid.aveo_scanner/bt_classic")`:
  - `isEnabled` → Boolean
  - `bondedDevices` → `List<Map>{name, address}` (solo emparejados; no hacemos escaneo/descubrimiento)
  - `connect({address})` → en un hilo de fondo: `adapter.cancelDiscovery()`, intentar `createRfcommSocketToServiceRecord(SPP)`, si falla `createInsecureRfcommSocketToServiceRecord(SPP)`, si falla el fallback por reflexión `createRfcommSocket(1)` (clones). Error → `result.error("CONNECT_FAILED", msg, null)` en el hilo principal.
  - `write({bytes: Uint8List})`
  - `disconnect`
- `EventChannel("mx.solomid.aveo_scanner/bt_classic/data")`: hilo lector que manda `ByteArray` leídos; al perder conexión manda `endOfStream`/error y limpia el socket.
- UUID SPP `00001101-0000-1000-8000-00805F9B34FB`.
- Todas las respuestas al `Result` y eventos del `EventSink` **en el hilo principal** (`Handler(Looper.getMainLooper())`).
- Sin `SecurityException` sin manejar: si falta `BLUETOOTH_CONNECT`, devolver `result.error("NO_PERMISSION", …)`.

### Manifiesto
Los permisos exactos del README en `android/app/src/main/AndroidManifest.xml`, más `<uses-feature android:name="android.hardware.bluetooth" android:required="true"/>`. `android:label="Aveo Scanner"`. Orientación libre (la tablet puede ir horizontal).

### Dart
- `BtClassicChannel` envuelve los canales (inyectable para pruebas).
- `BtClassicTransport(address)` implementa `Transport`.
- Antes de listar dispositivos: pedir `Permission.bluetoothConnect` con `permission_handler`; si se niega, la UI explica y ofrece abrir ajustes.

---

## 10. UI

- Tema oscuro, alto contraste, números grandes (uso en el carro). Material 3, color semilla ámbar/naranja. Tipografía del sistema.
- `wakelock_plus`: pantalla encendida mientras haya conexión.
- Navegación: `NavigationRail` en horizontal / `NavigationBar` en vertical. Pestañas: **Conectar, Tablero, Fallas, Respaldo, Terminal**. Las 4 últimas deshabilitadas sin conexión.

### Conectar
Lista de dispositivos emparejados + opción fija **"Simulador (sin carro)"**. Al conectar: progreso por paso de la secuencia de inicio; al terminar muestra versión, protocolo, voltaje. Errores en español con qué hacer.

### Tablero
- 4 tarjetas grandes: RPM, velocidad, temperatura del refrigerante, voltaje (`0142`; si no se soporta, `ATRV`).
- Rejilla con el resto de PIDs de la tabla **que el carro soporte** (los no soportados no se muestran).
- Sondeo round-robin: los 4 principales en cada vuelta, el resto uno por vuelta. Respeta el ritmo de `Elm327`.
- Consumo instantáneo (L/h y km/L) si hay MAF.
- Botón Grabar sesión (inicia/termina `session`).
- Refrigerante > 105 °C o voltaje < 12.0 V con motor encendido → tarjeta en rojo.

### Fallas
Botones Leer (03, 07, 0A en secciones separadas), Freeze frame, Borrar (flujo sección 7). Cada DTC: código grande, descripción, tipo.

### Respaldo
Botón "Hacer respaldo inicial" con progreso, lista de respaldos guardados, ver detalle (JSON legible) y Exportar (muestra la ruta resultante).

### Terminal
Lista en vivo del `TrafficLog` (tx/rx/guard con colores) + campo para escribir un comando. **Pasa por `CommandGuard` como todo**; si es `needsConfirmation` la terminal lo rechaza ("usa la pantalla Fallas"). Sirve para llenar "Hallazgos de mi Aveo".

### Pruebas de UI
Widget tests con `MockTransport` (latencia 0): conectar al simulador → ver RPM en el tablero; leer fallas → ver `P0133`; flujo de borrado completo (incluye rechazo si RPM > 0 y que sin escribir `BORRAR` no se manda `04`).

---

## 11. Entregables por lote

| Lote | Contenido | Criterio de aceptación |
|---|---|---|
| **A — Núcleo** | Secciones 2–7 (`lib/core`, `lib/obd`) + pruebas | `flutter test` verde, `flutter analyze` limpio, cobertura ≥ 80 % en `lib/core` y `lib/obd` |
| **B — Bluetooth Android** | Sección 9 (Kotlin, manifiesto, `bt_classic_*`) | `flutter build apk --debug` compila; pruebas Dart del transporte con canal falso |
| **C — Datos + UI** | Secciones 8 y 10, `main.dart`, `app.dart` | Todo lo anterior + widget tests; la app corre en la tablet con el simulador |

Al terminar cada lote: lista de archivos, decisiones tomadas (en `docs/DECISIONS.md`) y lo que quedó pendiente. **No hacer commits**: el revisor revisa y hace commit.
