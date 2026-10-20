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
