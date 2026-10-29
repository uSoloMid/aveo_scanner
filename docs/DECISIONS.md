# Decisiones de implementación — Lote A

- El reloj y la espera de `Elm327` son inyectables para pruebas deterministas; el reloj real y `Future.delayed` son los valores predeterminados.
- La familia de protocolo inicia como CAN 11 bit y se actualiza durante `initialize()` a partir de `ATDPN`.
- Los datos del modo 09 se exponen como texto concatenado en `VehicleInfo`; no se agrega lógica de persistencia porque pertenece al lote de datos.
- El borrado del servicio recibe confirmación y verifica RPM; el respaldo previo requiere la capa de base de datos, fuera del alcance/archivos permitidos de este lote.
- Se implementaron descripciones españolas para códigos P0 comunes conocidos. No se inventaron textos para códigos restantes del mínimo tabular del spec.

## Lote B

- Bluetooth clásico usa un plugin Flutter propio con un executor de fondo para conexión, lectura y escritura; los callbacks de Flutter se despachan al hilo principal.
- El canal Dart es una interfaz inyectable; `BtClassicTransport` traduce errores de plataforma a `TransportException` y expone estado y bytes como streams broadcast.
- Se expone `requestBluetoothConnectPermission()` con resultados explícitos (`granted`, `denied`, `permanentlyDenied`, `restricted`) para que la UI decida cómo explicar o abrir ajustes.

- ObdService recibe un callback opcional savePreClearBackup porque la persistencia esta fuera de los archivos permitidos. clearDtcs exige ese callback y aborta antes de enviar 04 si falta o falla; recibe DTC, freeze frame, VIN y fecha.
- La lectura de freeze frame consulta la mascara 0200 y solo pide valores de PIDs indicados como soportados.
- El parser acepta encabezados CAN 11 bit de tres digitos aunque la linea hex completa tenga longitud impar, y distingue respuestas sin encabezado por el byte de servicio.

## Lote C

- La pantalla principal construye únicamente la pestaña seleccionada; así el sondeo del tablero se cancela al salir y se inicia de nuevo al volver. El bloqueo de pantalla sigue el ciclo de vida de la conexión.
- La confirmación de borrado guarda primero una captura pre-clear desde UI; tras las dos confirmaciones, `ObdService.clearDtcs` vuelve a comprobar RPM y ejecuta su callback de respaldo obligatorio antes de transmitir `04`. Esto genera dos capturas si el usuario confirma. El API comprometido no ofrece una operación pública para preparar y reutilizar esa captura.
- `ObdService.clearDtcs` devuelve `void` aunque relee la sección 03 internamente. Para mostrar los códigos resultantes, la UI hace una segunda lectura 03; el API no permite recuperar el resultado de la primera lectura posterior al borrado.
- Si el adaptador no anuncia o no entrega el PID `0142`, el tablero muestra el voltaje obtenido durante `ATRV` al inicializar la conexión.
- Las pruebas de datos usan `sqflite_common_ffi` con base en memoria. No se ejecutó Flutter por la restricción del entorno; quedan por revisar analyze y test.

## Lote D — Diagnóstico de ralentí

- Nueva pestaña **Diagnóstico**: `IdleRecorder` (lib/obd) lee en ciclo los canales rápidos (RPM, ralentí deseado `221192`, IAC `221172`, mariposa, velocidad) y dos lentos por vuelta (round-robin). Cada vuelta produce una fila CSV con el último valor conocido de todos los canales.
- Los PIDs de modo 22 no verificados en el carro (de OBDb) se prueban una vez al iniciar y se descartan si la ECU no responde.
- `HighIdleDetector` marca `ralenti_alto=1` y agrega eventos `AUTO:` cuando RPM − deseado > 300 durante 2 vueltas con el carro detenido y la mariposa < 14 %; sale cuando la diferencia baja de 150.
- CSV en `Android/data/mx.solomid.aveo_scanner/files/registros/` (visible por USB desde la PC). Se hace `flush` en cada fila. No se agregó `share_plus` para respetar la lista de dependencias del SPEC; si se aprueba, se puede agregar un botón Compartir.
- `Mode22Scanner` recorre 256 identificadores `22xxxx` (solo lectura, servicio permitido por `CommandGuard`) y guarda las respuestas en `modo22_*.csv`.
- `Elm327.initialize` reintenta `0100` hasta 2 veces cuando la respuesta no contiene `4100` (K-Line del Aveo: el primer intento da `BUS INIT: ERROR`).
- No se pudo ejecutar `flutter analyze`/`flutter test` en el entorno de desarrollo; pendiente correrlos en Windows.
- La grabadora también registra lo que usaba Car Scanner: O2 1 y 2 (`0114`/`0115`, A/200 V), estado de combustible (`0103`: 1 = lazo abierto por frío, 2 = lazo cerrado, 4 = abierto por carga) y voltaje de batería con `ATRV`. Lentos por vuelta: 3.
- Se aprobó `share_plus` (2026-10-22) para mandar los registros desde la tablet. Los CSV se guardan primero en `Descargas/AveoScanner` (público, Android 11+ sin permisos); si no se puede escribir ahí, en la carpeta privada de la app.
- 2026-10-22: hallazgo clave. Con la mariposa en 10.98 % (cruda), la mariposa **relativa** (`0145`, también `220045`) marcó 0 % el día bueno (20-oct) y 4.3–4.7 % los días con ralentí alto. La ECU cree que el acelerador está ~4 % abierto y no entra a control de ralentí (IAC retenida en 48–55, avance 33°). La grabadora registra ahora `0145` como canal rápido; el ralentí deseado y la mariposa cruda pasan a lentos; los extras GM opcionales ya no se graban por defecto, salvo `221170` y `221176` (significado por confirmar).
