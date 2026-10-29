# 🚗 Aveo Scanner

App propia de diagnóstico OBD2 para mi **Chevrolet Aveo 2012 (1.6L, estándar, versión México)**, hecha en **Flutter**, corriendo en una **tablet Android** con un adaptador **ELM327 Bluetooth**.

> Objetivo: leer todo lo que el carro pueda decir (motor, fallas, datos de fábrica, y después ABS y más), con un dashboard propio y sin riesgo de dañar la computadora del carro.

---

## 📋 Índice

1. [Estado del proyecto](#-estado-del-proyecto)
2. [Hardware](#-hardware)
3. [Instalación del entorno (Windows)](#-instalación-del-entorno-windows)
4. [Crear el proyecto](#-crear-el-proyecto)
5. [Arquitectura](#-arquitectura)
6. [Reglas de seguridad (NO NEGOCIABLES)](#-reglas-de-seguridad-no-negociables)
7. [Cómo hablar con el ELM327](#-cómo-hablar-con-el-elm327)
8. [PIDs estándar para la v1](#-pids-estándar-para-la-v1)
9. [Códigos de falla (DTC)](#-códigos-de-falla-dtc)
10. [Perfil del Aveo (OBDb)](#-perfil-del-aveo-obdb)
11. [Fases del proyecto](#-fases-del-proyecto)
12. [Hallazgos de mi Aveo](#-hallazgos-de-mi-aveo)
13. [Referencias](#-referencias)

---

## 📍 Estado del proyecto

- [x] Escáner comprado (ELM327 mini, Bluetooth clásico, Mercado Libre)
- [x] Escáner validado con Car Scanner (2026-10-20)
- [x] Entorno Flutter instalado
- [x] Proyecto creado (app de diagnóstico funcional con simulador; falta probarla en el carro)
- [ ] Fase 2: "Hola carro" (RPM, velocidad, temperatura)
- [x] Modo 22 de GM confirmado en el carro con terminal (ralentí deseado e IAC)
- [ ] Pestaña **Diagnóstico** (grabadora CSV + escáner modo 22) probada en el carro

---

## 🔌 Hardware

| Pieza | Detalle |
|---|---|
| Carro | Chevrolet Aveo 2012, 1.6L, transmisión estándar, México |
| Generación | T250 (base Daewoo, primo del Gentra/Lacetti) |
| Adaptador | ELM327 mini, **Bluetooth clásico (SPP)**, clon chino |
| Dispositivo | Tablet Android |
| Conector | OBD2 de 16 pines, bajo el volante |

**Protocolo:** pendiente de confirmar con Car Scanner. Puede ser:
- **CAN 11 bit 500 kbps** (protocolo `6`) — lo que reportan las pruebas de un Aveo 2009 en OBDb.
- **ISO 14230 KWP2000 / K-Line** (protocolo `5`) — lo que usa el ejemplo de AveoForum para el ABS.

Es posible que el **motor** vaya por CAN y el **ABS** por K-Line. Lo confirmamos en la Fase 1.

### Cuidados con el adaptador
- Conectarlo con el carro en **contacto o encendido**.
- **No dejarlo conectado** con el carro apagado varios días (drena batería).
- Si algo se comporta raro (tablero parpadeando, el carro hace cosas extrañas): desconectar y ya.
- Nada de estar picándole a la app manejando. Que solo muestre datos.

---

## 💻 Instalación del entorno (Windows)

### 1. Git para Windows
Descargar de https://git-scm.com/download/win e instalar con opciones por defecto.

### 2. Flutter (desde VS Code, la forma fácil)
1. En VS Code → Extensiones → instalar **Flutter** (instala también **Dart**).
2. `Ctrl + Shift + P` → escribir **Flutter: New Project**.
3. Si no encuentra el SDK, VS Code ofrece **Download SDK**. Elegir una carpeta **sin espacios ni acentos**, por ejemplo `C:\dev\flutter`.
4. Aceptar cuando pregunte si agrega Flutter al `PATH`.
5. Cerrar y abrir VS Code.

### 3. Android Studio (solo para el SDK de Android)
1. Descargar de https://developer.android.com/studio e instalar.
2. Abrirlo una vez y dejar que descargue el **Android SDK**.
3. En **SDK Manager → SDK Tools**, marcar **Android SDK Command-line Tools** e instalar.
4. Ya no hace falta abrirlo más; programamos en VS Code.

### 4. Verificar
En una terminal (PowerShell o la de VS Code):
```powershell
flutter doctor
flutter doctor --android-licenses   # aceptar todo con "y"
```
`flutter doctor` debe mostrar palomita en **Flutter** y **Android toolchain**. Lo de Visual Studio / Chrome no importa para este proyecto.

### 5. Preparar la tablet
1. **Ajustes → Acerca de la tablet → Información de software** → tocar **Número de compilación** 7 veces → se activa el modo desarrollador.
2. **Ajustes → Opciones de desarrollador** → activar **Depuración por USB**.
3. Conectar la tablet por USB a la compu y aceptar el mensaje "¿Permitir depuración USB?".
4. Verificar:
   ```powershell
   flutter devices
   ```
   Debe aparecer la tablet.

> Si no aparece: instalar el driver USB del fabricante (Samsung, Lenovo, etc.) o probar otro cable (algunos solo cargan).

---

## 🏗️ Crear el proyecto

```powershell
cd C:\ruta\a\mis\proyectos
flutter create --org mx.solomid --platforms android aveo_scanner
cd aveo_scanner
code .
```

Probar que corre en la tablet:
```powershell
flutter run
```
Debe aparecer la app de ejemplo (el contador). Con eso el entorno queda listo.

---

## 🧱 Arquitectura

```
aveo_scanner/
├── assets/
│   └── profiles/
│       ├── generic_obd2.json        # PIDs estándar modo 01
│       └── chevrolet_aveo.json      # Copia de OBDb (CC BY-SA 4.0)
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── transport/
│   │   │   ├── transport.dart            # Interfaz: connect, write, readUntilPrompt, disconnect
│   │   │   ├── bt_classic_transport.dart # Bluetooth clásico (mi escáner actual)
│   │   │   ├── ble_transport.dart        # BLE (futuro: iPhone / ESP32)
│   │   │   └── mock_transport.dart       # Simulador: responde como un Aveo falso
│   │   ├── elm327/
│   │   │   ├── elm327.dart               # Cola de comandos, init, timeouts
│   │   │   └── response_parser.dart      # Limpia ">", "SEARCHING...", espacios, etc.
│   │   └── safety/
│   │       └── command_guard.dart        # LISTA BLANCA. Todo comando pasa por aquí.
│   ├── obd/
│   │   ├── pid.dart                      # Modelo de una señal
│   │   ├── standard_pids.dart            # Fórmulas modo 01
│   │   ├── dtc.dart                      # Lectura/decodificación de códigos
│   │   ├── dtc_descriptions_es.dart      # Descripciones en español
│   │   └── profile_loader.dart           # Lee el JSON formato OBDb
│   ├── data/
│   │   └── database.dart                 # SQLite: sesiones, lecturas, respaldos
│   └── ui/
│       ├── connect_screen.dart
│       ├── dashboard_screen.dart
│       ├── dtc_screen.dart
│       └── backup_screen.dart
└── README.md
```

### Ideas clave
- **Transporte separado del protocolo.** El ELM327 no sabe si va por Bluetooth clásico, BLE o simulador. Así después cambiamos a iPhone/ESP32 sin tocar el resto.
- **`MockTransport` desde el día 1.** Permite programar el dashboard en la compu sin estar en el carro. Responde a `010C`, `010D`, etc. con valores falsos que cambian.
- **Todo comando pasa por `CommandGuard`.** No hay otra forma de mandarle algo al escáner.
- **Perfiles en JSON.** Agregar otro carro = agregar otro archivo.

### Paquetes (a confirmar en pub.dev al iniciar la Fase 2)
| Para qué | Opción |
|---|---|
| Bluetooth clásico (SPP) | Revisar en pub.dev un paquete mantenido para SPP. Si no hay uno confiable, escribimos un **platform channel en Kotlin** (~100 líneas, usa `BluetoothSocket` con el UUID SPP `00001101-0000-1000-8000-00805F9B34FB`). |
| BLE (futuro) | `flutter_blue_plus` |
| Permisos | `permission_handler` |
| Base de datos | `sqflite` o `drift` |
| Gráficas / medidores | Revisar `fl_chart` y `syncfusion_flutter_gauges` |
| Estado | `riverpod` (o `provider` si queremos algo más simple) |

### Permisos Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<!-- Android 11 o menor -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

---

## 🛡️ Reglas de seguridad (NO NEGOCIABLES)

La computadora del carro entiende "servicios". **Leer no rompe nada; escribir sí puede.** La app solo deja pasar servicios de lectura.

### ✅ Permitidos (lista blanca)
| Servicio | Qué hace |
|---|---|
| `01` | Datos en vivo |
| `02` | Freeze frame (foto al momento de la falla) |
| `03` | Leer códigos de falla confirmados |
| `07` | Leer códigos pendientes |
| `09` | Info del vehículo (VIN, calibración, CVN) |
| `0A` | Leer códigos permanentes |
| `22` | Leer datos de fábrica (GM / OBDb) |
| `13` | Leer fallas por K-Line (ABS, SAE J2190) |
| `AT...` | Comandos del propio ELM327 (no llegan al carro) |

### ⚠️ Permitidos con confirmación
| Servicio | Qué hace | Por qué cuidado |
|---|---|---|
| `04` | Borrar códigos (motor) | Resetea monitores de emisiones → **no pasas verificación** hasta manejar varios días. |
| `14` | Borrar códigos (K-Line / ABS) | Igual que arriba. |
| `AE` | Activar actuadores (GM) | **Solo con el carro detenido.** Fase 5, si acaso. |

### ⛔ Bloqueados SIEMPRE
| Servicio | Qué hace |
|---|---|
| `10` | Cambiar sesión de diagnóstico |
| `11` | Reiniciar la computadora |
| `27` | Acceso de seguridad (desbloquear) |
| `2E`, `3B` | Escribir datos |
| `31` | Ejecutar rutinas internas |
| `34`–`37` | Reprogramar (flashear) la computadora |
| Cualquier otro | Bloqueado por defecto |

### Comandos AT bloqueados
- `ATMA` (monitor de todo el bus): solo en una pantalla especial de "espía", nunca automático.
- `ATPP...` / `ATPPS` (parámetros programables): pueden dejar el adaptador mal configurado.

### Implementación (idea)
```dart
class CommandGuard {
  static const _allowed = {'01', '02', '03', '07', '09', '0A', '22', '13'};
  static const _needsConfirm = {'04', '14', 'AE'};

  static GuardResult check(String cmd) {
    final c = cmd.replaceAll(' ', '').toUpperCase();
    if (c.startsWith('AT')) {
      if (c.startsWith('ATMA') || c.startsWith('ATPP')) return GuardResult.blocked;
      return GuardResult.allowed;
    }
    if (c.length < 2) return GuardResult.blocked;
    final service = c.substring(0, 2);
    if (_allowed.contains(service)) return GuardResult.allowed;
    if (_needsConfirm.contains(service)) return GuardResult.needsConfirmation;
    return GuardResult.blocked;
  }
}
```

---

## 🗣️ Cómo hablar con el ELM327

El ELM327 es como una terminal de texto: le mandas un comando terminado en `\r` y responde texto que termina con el prompt `>`.

### Secuencia de inicio
```
ATZ      → reset (responde "ELM327 v1.5" o similar). Esperar ~1 s.
ATE0     → sin eco (que no repita lo que le mandamos)
ATL0     → sin saltos de línea extra
ATS0     → sin espacios en la respuesta (más fácil de parsear)
ATH1     → mostrar encabezados (saber qué módulo responde: 7E8, etc.)
ATAT1    → timing adaptativo
ATSP0    → protocolo automático (ya confirmado, fijar con ATSP6 o ATSP5)
0100     → primer comando real: PIDs soportados 01–20
ATDPN    → qué protocolo encontró (número)
ATRV     → voltaje de la batería (lo mide el propio adaptador)
```

### Reglas de oro
- **Un comando a la vez.** Esperar el `>` antes de mandar el siguiente (cola de comandos).
- **Timeouts:** ~1–2 s normal, hasta 5 s para el primer `0100` (el `SEARCHING...` tarda).
- **Respuestas a ignorar/limpiar:** `SEARCHING...`, `BUS INIT: ...OK`, ecos, `\r`, espacios.
- **Errores típicos:**
  - `NO DATA` → el carro no respondió ese PID (no lo soporta o no aplica).
  - `?` → comando que el ELM no entiende.
  - `UNABLE TO CONNECT` → contacto apagado o protocolo equivocado.
  - `CAN ERROR` / `BUS ERROR` → problema de comunicación; reintentar o reiniciar con `ATZ`.
  - `7F xx 31` → respuesta negativa: ese PID/servicio no existe en este módulo.
  - `7F xx 78` → "espérame, estoy procesando"; seguir esperando.
- **Clones baratos:** pueden ser lentos o cortar respuestas largas. No pedir más de ~5–10 lecturas por segundo en total.

### Ejemplo con encabezados (`ATH1`, `ATS0`)
```
>010C
7E804410C1AF8
 │  │ │ │ └──┴─ A=0x1A, B=0xF8
 │  │ │ └ PID 0C (RPM)
 │  │ └ 0x41 = respuesta positiva al modo 01
 │  └ largo
 └ quién responde (7E8 = motor)

RPM = (0x1A * 256 + 0xF8) / 4 = 1726 rpm
```

---

## 📊 PIDs estándar para la v1

| PID | Qué es | Fórmula | Unidad |
|---|---|---|---|
| `0104` | Carga del motor | `A × 100 / 255` | % |
| `0105` | Temp. refrigerante | `A − 40` | °C |
| `0106` | Trim combustible corto | `(A − 128) × 100 / 128` | % |
| `0107` | Trim combustible largo | `(A − 128) × 100 / 128` | % |
| `010B` | Presión del múltiple (MAP) | `A` | kPa |
| `010C` | RPM | `(A × 256 + B) / 4` | rpm |
| `010D` | Velocidad | `A` | km/h |
| `010E` | Avance de encendido | `A / 2 − 64` | ° |
| `010F` | Temp. aire de admisión | `A − 40` | °C |
| `0110` | Flujo de aire (MAF) | `(A × 256 + B) / 100` | g/s |
| `0111` | Posición del acelerador | `A × 100 / 255` | % |
| `011F` | Tiempo desde arranque | `A × 256 + B` | s |
| `012F` | Nivel de combustible | `A × 100 / 255` | % |
| `0142` | Voltaje del módulo | `(A × 256 + B) / 1000` | V |

### PIDs soportados
`0100`, `0120`, `0140`... devuelven 4 bytes = 32 bits. Cada bit en 1 = ese PID existe. Así la app sabe qué preguntar y qué no.

### Consumo de gasolina (desde el MAF)
```
Litros/hora = MAF(g/s) × 3600 / (14.7 × 740)
km/L        = velocidad(km/h) / Litros/hora
```
(14.7 = relación aire/combustible estequiométrica; 740 g/L ≈ densidad de la gasolina.) Es una aproximación; después la calibramos con llenadas reales de tanque.

---

## 🚨 Códigos de falla (DTC)

### Leer
- `03` → confirmados (los que prenden el check engine)
- `07` → pendientes (aún no confirmados, pero el carro ya sospecha)
- `0A` → permanentes (no se borran con `04`; se quitan solos cuando el carro verifica que ya se arregló)

### Decodificar
Cada código son 2 bytes. Los 2 primeros bits dicen la letra:

| Bits | Letra | Sistema |
|---|---|---|
| `00` | P | Motor / transmisión |
| `01` | C | Chasis (ABS, etc.) |
| `10` | B | Carrocería |
| `11` | U | Red / comunicación |

Ejemplo: bytes `01 33` → `P0133` (sensor de oxígeno con respuesta lenta).

### Respaldo antes de borrar
Antes de cualquier `04`, la app guarda automáticamente: códigos, freeze frame (`02`) y fecha. Así nunca se pierde la evidencia de qué falló.

---

## 🧬 Perfil del Aveo (OBDb)

Fuente: https://github.com/OBDb/Chevrolet-Aveo — archivo `signalsets/v3/default.json` (licencia **CC BY-SA 4.0**; dar crédito y compartir cambios con la misma licencia).

### Qué trae
| Módulo | Pide → responde | Contenido |
|---|---|---|
| Motor | `7E0` → `7E8` | ~100 señales modo `22` |
| Transmisión automática | `7E2` → `7EA` | No aplica (mi Aveo es estándar) |
| Presión de llantas | `241` / `DA40` | Probablemente no aplica a T250 |

### ⚠️ Advertencias
- El archivo mezcla **todas las generaciones** (2002–2024). Muchas señales son del Sonic/T300 o del Aveo nuevo: turbo, persianas de parrilla, enfriador de aire, vida de aceite, módulo 14V. **Mi Aveo no tiene eso.**
- Solo 2 señales modo `22` están probadas con un Aveo real (2009): `22000D` (velocidad) y `2211A1` (tiempo desde arranque).
- No trae ABS, bolsas de aire ni carrocería.

### Las que más me interesan (a verificar)
| Comando | Señal |
|---|---|
| `221200`–`221204` | Fallas de encendido: total e historial por cilindro |
| `221205`–`221208` | Fallas de encendido actuales por cilindro |
| `221193`–`221196` | Ancho de pulso de inyector, cilindros 1–4 |
| `2211A6` | Retardo por cascabeleo |
| `221192` | RPM de ralentí deseadas |
| `221172` | Posición válvula IAC |
| `2213AF` | Comando del ventilador |
| `22135F` | Causa del check engine |
| `220042` | Voltaje del módulo |
| `2211A1` | Tiempo desde arranque ✅ probado |

### Formato de una señal (simplificado)
```json
{
  "hdr": "7E0",
  "rax": "7E8",
  "cmd": { "22": "11A1" },
  "freq": 1,
  "signals": [
    {
      "id": "AVEO_RUNTM",
      "name": "Time since engine start",
      "fmt": { "len": 16, "unit": "seconds" }
    }
  ]
}
```
- `hdr` → encabezado a usar (`ATSH7E0`)
- `rax` → de quién esperamos respuesta (`7E8`)
- `cmd` → servicio + PID
- `freq` → cada cuántos segundos leerla
- `fmt` → cómo convertir los bytes (`len` en bits, y opcionalmente `bix` posición, `mul`, `div`, `add`, `min`, `max`)

Prueba real del repo: respuesta `7E8056211A101FF` → `0x01FF` = **511 segundos**.

### Descubrimiento de PIDs
Función de la app que:
1. Manda cada comando del perfil y guarda cuáles responde mi Aveo.
2. Opcional: barrido de rangos `22xxxx` para encontrar PIDs no documentados.
3. Genera el **perfil verificado del Aveo 2012 México**.

Solo modo `22` = solo lectura = seguro. Ir despacio (no saturar el bus).

### ABS por K-Line (de AveoForum)
```
ATZ
ATL1
ATSP5           → ISO 14230 KWP, fast init
ATH1
ATSH8628F1      → encabezado para el módulo 28 (ABS)
ATSTFF          → timeout máximo
134000          → Modo $13: leer fallas grupo chasis
```
- El ABS no siempre responde a la primera; a veces hay que reinicializar.
- `14xxxx` borra (pedir confirmación).
- Referencias: hoja de datos del ELM327 y SAE J2190.

---

## 🗺️ Fases del proyecto

### Fase 0 — Preparación
- [ ] Instalar Git, Flutter, Android Studio (SDK)
- [ ] `flutter doctor` en verde (Flutter + Android)
- [ ] Modo desarrollador y depuración USB en la tablet
- [ ] `flutter create` y correr la app de ejemplo en la tablet

### Fase 1 — Validación con Car Scanner (~30 min)
- [ ] Instalar **Car Scanner** en la tablet
- [ ] Emparejar el ELM327 (PIN `1234` o `0000`)
- [ ] Anotar protocolo detectado
- [ ] Anotar PIDs soportados
- [ ] Anotar códigos de falla actuales (**no borrar**)
- [ ] Si no funciona → devolución inmediata

### Fase 2 — "Hola carro"
- [ ] `Transport` + `BtClassicTransport` + `MockTransport`
- [ ] `Elm327` con cola de comandos y secuencia de inicio
- [ ] `CommandGuard` (lista blanca) con pruebas unitarias
- [ ] Pantalla de conexión (listar dispositivos emparejados)
- [ ] Mostrar RPM, velocidad, temperatura y voltaje en vivo

### Fase 3 — Lo útil
- [ ] Leer códigos `03`, `07`, `0A` con descripción en español
- [ ] Freeze frame `02`
- [ ] Borrar códigos `04` con confirmación + respaldo automático
- [ ] **Respaldo inicial**: VIN (`0902`), calibración (`0904`), CVN (`0906`), PIDs soportados, valores base
- [ ] Dashboard completo con PIDs estándar
- [ ] Guardar sesiones en SQLite

### Fase 4 — Lo chido
- [ ] Cargar perfil OBDb del Aveo
- [ ] Descubrimiento de PIDs modo `22`
- [ ] Fallas de encendido e inyectores por cilindro
- [ ] Consumo de gasolina instantáneo y por viaje
- [ ] Historial de viajes con GPS
- [ ] Alertas: temperatura alta, voltaje bajo, trims fuera de rango

### Fase 5 — Avanzado
- [ ] ABS por K-Line
- [ ] Cable Y + modo monitor para espiar el escáner del mecánico
- [ ] Escáner propio con ESP32 (BLE + CAN/K-Line)
- [ ] Contribuir el perfil verificado a OBDb
- [ ] Versión iPhone (BLE)

---

## 🔍 Hallazgos de mi Aveo

> Llenar conforme vayamos probando.

| Dato | Valor |
|---|---|
| Versión del ELM327 (`ATI`) | ELM327 v2.1 (clon) |
| Protocolo (`ATDPN`) | **ISO 14230-4 KWP, fast init (10.4 kbaud)** — K-Line, no CAN |
| Voltaje en reposo (`ATRV`) | 12.1–12.5 V (bajo; batería por revisar) |
| Voltaje con motor encendido | 14.6–14.7 V |
| VIN (`0902`) | `3G1TA5AF8CLXXXXXX` (enmascarado) |
| Calibración (`0904`) | 47060302 |
| PIDs soportados `0100` | |
| PIDs soportados `0120` | |
| PIDs soportados `0140` | |
| Códigos de falla actuales | Ninguno. MIL apagada, todos los monitores completos |
| Computadora (ECU) | Delphi MR-140 / HV-240 (motor F16D3), responde en `F1 ← 11` |
| Inicio de K-Line | El primer comando suele dar `BUS INIT: ERROR`; al segundo intento responde |
| Módulos que responden | |

### PIDs modo 22 verificados
| Comando | ¿Responde? | Valor de ejemplo | Notas |
|---|---|---|---|
| `221192` | ✅ | `62 11 92 41` → 812 rpm (caliente) · `42` → 825 rpm (frío) | Ralentí deseado = A × 12.5. Escala confirmada: pidió 812, real 847 |
| `221172` | ✅ | `62 11 72 25` → 37 (caliente) · `2F` → 47 (frío, 1472 rpm) · `3D` → 61 (llave ON, motor apagado) | Posición IAC en pasos |
| `22000D` | | | |
| `2211A1` | | | |
| `221200` | | | |

### Caso: ralentí alto en frío (oct 2026)
- En frío se queda en 1400–1650 rpm con avance ~33° (normal en ralentí: 3–4°), mariposa 10.98 % (cerrada) y sin códigos.
- La computadora pide ~825 rpm mientras el motor va a ~1470 → entra aire que la ECU no controla.
- En caliente todo normal (812 pedido / 847 real, IAC 37). Volante, pedal y A/C no lo disparan.
- Siguiente: registrar con la pestaña **Diagnóstico** para ver si la IAC baja mientras las RPM siguen altas.

---

## 📚 Referencias

- **OBDb — Chevrolet Aveo:** https://github.com/OBDb/Chevrolet-Aveo
- **OBDb (base de datos completa):** https://obdb.community
- **AveoForum — ABS con ELM327:** https://www.aveoforum.com/forum/f94/retrieving-error-codes-ecu-10457/
- **ELM327 (hoja de datos):** buscar "ELM327 datasheet" en el sitio de ELM Electronics
- **PIDs OBD2 estándar:** https://en.wikipedia.org/wiki/OBD-II_PIDs
- **Flutter:** https://docs.flutter.dev
- **Normas:** SAE J1979 (OBD2), ISO 15765 (CAN), ISO 14230 (KWP2000), SAE J2190 (modos 13/14)
- **Comunidad rusa del Aveo T250:** drive2.ru (buscar en ruso, p. ej. "Авео Т250 ELM327")

---

## 📄 Licencia

El código de este proyecto está bajo licencia **MIT** (ver [LICENSE](LICENSE)).

Excepción: los perfiles copiados de OBDb (`assets/profiles/chevrolet_aveo.json` y derivados) conservan su licencia original **CC BY-SA 4.0**.

> ⚠️ Uso bajo tu propio riesgo. Esta app solo debe leer datos; aun así, conectar cualquier dispositivo al puerto OBD2 de un carro es responsabilidad de quien lo hace.
