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
