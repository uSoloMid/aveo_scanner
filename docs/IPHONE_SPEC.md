# Aveo Ralentí (iPhone) — especificación

App mínima para iPhone que vigila el ralentí del Aveo por Bluetooth LE y avisa
cuando cambia, para no tener que estar mirando la tablet. Vive en `iphone/` como
paquete SwiftPM que compila e instala [xtool](https://github.com/xtool-org/xtool)
desde Windows (WSL). No reemplaza a la app Flutter.

## Restricciones

- Swift 6, SwiftUI, iOS 17+. Sin dependencias externas.
- Solo lectura. Lista blanca de comandos (rechazar todo lo demás antes de enviarlo):
  `ATZ ATE0 ATL0 ATS0 ATH0 ATSP0 ATRV ATDPN` y cualquier comando que empiece con
  `01`, `09` o `22`. Nunca `04`, `14`, `2E`, `2F`, `3B`, `31`, `27`, etc.
- Archivos en UTF-8. Textos de la UI en español de México.
- El ELM327 contesta texto ASCII terminado en `>`; un comando a la vez.

## Estructura

```
iphone/
  Package.swift          # productos: AveoRalenti (app), AveoCore (lógica pura)
  xtool.yml              # bundleID mx.solomid.AveoRalenti, infoPath: Info.plist
  Info.plist
  Sources/AveoCore/      # SIN CoreBluetooth/UIKit: debe compilar y probarse en Linux
    CommandGuard.swift
    ElmParser.swift
    IdleMonitor.swift
    CsvLog.swift
  Sources/AveoRalenti/   # app iOS
    AveoRalentiApp.swift
    BleElm.swift
    Poller.swift
    ContentView.swift
    Alerts.swift
  Tests/AveoCoreTests/   # XCTest, corre con `swift test` en Linux
```

`Info.plist` debe incluir: `NSBluetoothAlwaysUsageDescription`,
`UIBackgroundModes` = [`bluetooth-central`, `audio`], `UIFileSharingEnabled` = true,
`LSSupportsOpeningDocumentsInPlace` = true.

## AveoCore

**CommandGuard.isAllowed(_ cmd: String) -> Bool**: aplica la lista blanca.

**ElmParser**: recibe el texto crudo de una respuesta y devuelve bytes.
- Quitar espacios, `\r`, `\n`, `>`, líneas `SEARCHING...` y `BUS INIT: ...`.
- `NO DATA`, `?`, `ERROR`, `UNABLE TO CONNECT`, `STOPPED` o `7F22..` → `nil`.
- Buscar el prefijo esperado (`410C`, `4145`, `410D`, `4111`, `4105`, `621192`,
  `621172`) y devolver los bytes que siguen.
- Decodificación:
  - RPM `010C` = (A·256+B)/4
  - Ralentí deseado `221192` = A·12.5
  - IAC `221172` = A (pasos)
  - Mariposa relativa `0145` = A·100/255
  - Velocidad `010D` = A
  - Mariposa `0111` = A·100/255
  - Refrigerante `0105` = A−40
  - Batería `ATRV`: el número antes de `V`
- Ejemplos reales del carro para pruebas:
  - `62 11 92 41` → 812.5
  - `62 11 72 25` → 37
  - `41 0C 0D 3C` → 847
  - `BUS INIT: ...ERROR` → nil

**IdleMonitor** (misma regla que `HighIdleDetector` en `lib/obd/idle_recorder.dart`):
- Entra a "alto" cuando RPM − deseado > 300 durante 2 lecturas seguidas, con
  velocidad < 2 y mariposa < 14 %.
- Sale cuando la diferencia baja de 150, o cuando el carro se mueve o se acelera.
- `update(...) -> Event?`, con `Event` igual a `.becameHigh(rpm, desired)`,
  `.becameNormal(rpm)` o `.endedByDriving`.

**CsvLog**:
- Encabezado: `hora,evento,ralenti_alto,rpm,ralenti_deseado_rpm,iac_pasos,mariposa_relativa_pct,velocidad_kmh,mariposa_pct,refrigerante_c,voltaje_bateria_v`.
- Hora en formato `HH:mm:ss.SSS`; vacío si el valor no se conoce.
- Escapar el campo evento si trae coma o comillas.
- Archivo `aveo_YYYY-MM-DD_HH-mm-ss.csv` en Documents; flush en cada fila.

## App iOS

**BleElm** (CoreBluetooth):
- Buscar periféricos. Mostrar todos los que tengan nombre y ordenar primero los
  que contengan `OBD`, `ELM`, `V-LINK`, `IOS-Vlink` o `Vgate`.
- Al conectar, descubrir todos los servicios. Usar la primera característica con
  `notify` para leer y la primera con `write` o `writeWithoutResponse` para
  escribir. Los UUID comunes son `FFF0` (`FFF1` notify / `FFF2` write) y `FFE0`
  (`FFE1` ambos), pero no hay que fijarlos.
- `send(_ cmd: String) async throws -> String`:
  - Pasar por CommandGuard y escribir `cmd + "\r"`.
  - Juntar notificaciones hasta ver `>`.
  - Timeout de 4 s (8 s para `0100`); serializar con un actor.
- Guardar el UUID del último periférico y reconectar solo.

**Poller**:
- Inicialización: `ATZ` (esperar 1 s), `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATSP0`,
  `0100`. Si la respuesta no contiene `4100`, reintentar `0100` hasta 2 veces
  (K-Line del Aveo).
- Ciclo:
  - En cada vuelta: `010C`, `221192`, `221172`, `0145`.
  - Además, uno de `010D`, `0111`, `0105`, `ATRV` por turnos.
- Cada vuelta actualiza el estado, alimenta IdleMonitor y escribe una fila CSV.
- Si nada responde en una vuelta, esperar 1 s. Si se pierde la conexión,
  reconectar.

**Alerts**:
- Al cambiar el estado: notificación local (pedir permiso al iniciar), sonido
  del sistema y vibración.
  - "Ralentí alto: N rpm (pide M)"
  - "Ralentí normal: N rpm" ← el aviso más importante
- Botón "Probar alerta".

**ContentView** (una sola pantalla, letras grandes, legible a 1 m):
- Estado de conexión y botón Conectar / lista de dispositivos.
- Indicador grande: ROJO "RALENTÍ ALTO" / VERDE "Normal" / gris "Sin datos".
- RPM real, Pide la computadora, Diferencia, IAC (pasos), Mariposa relativa %.
  - Si la mariposa relativa es > 1 %, mostrar aviso "la computadora cree que
    estás acelerando".
- Botones de marca: "SE ACELERÓ", "SE COMPUSO" (se escriben en la columna
  evento de la siguiente fila).
- Interruptor "Mantener pantalla encendida" (`isIdleTimerDisabled`).
- Grabar / Detener, número de filas y `ShareLink` del CSV actual o el último.

## Pruebas (AveoCoreTests)

- CommandGuard:
  - Acepta `010C`, `221192`, `ATRV`.
  - Rechaza `04`, `2E1192`, `ATMA`, `14FF00`, `3B01`.
- ElmParser: los ejemplos reales de arriba más `NO DATA` y `7F2231` → nil.
- IdleMonitor: la misma secuencia que `test/obd/idle_recorder_test.dart`
  (1470, 1470 → alto; 1100 → nada; 850 → normal; 2000 a 40 km/h → nada).
- CsvLog: el encabezado exacto y una fila con evento con coma.

## Fuera de alcance

Fallas (DTC), borrado, base de datos, terminal libre, escáner modo 22.
