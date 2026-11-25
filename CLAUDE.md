# Aveo Scanner — guía para Claude

App Flutter (Android) de diagnóstico OBD2 para un Chevrolet Aveo 2012 1.6L estándar (México) con un ELM327 Bluetooth clásico. El usuario habla español: responder en español, claro y sin jerga innecesaria. La UI de la app también va en español.

Contexto completo: `README.md` (hardware, reglas, PIDs, hallazgos del carro), `docs/SPEC.md`, `docs/DECISIONS.md` (bitácora de decisiones por lote), `docs/CAPACITY.md`. `iphone/` es otra app (SwiftUI) y no entra en el flujo del APK.

## Reglas de seguridad — NO NEGOCIABLES
- Todo comando al ELM327 pasa por `lib/core/safety/command_guard.dart` (lista blanca). Nunca agregar otra vía para mandar comandos.
- Solo servicios de lectura. `04`/`14`/`AE` requieren confirmación (y respaldo previo antes de `04`). Bloqueados siempre: `10`, `11`, `27`, `2E`, `3B`, `31`, `34`–`37`, `ATMA` automático, `ATPP*`.
- No relajar el guard ni sus pruebas para que algo "funcione". Si una función lo necesita, preguntar primero.

## Cómo trabajamos: desde la tablet, sin PC
El usuario programa desde la tablet con Claude Code en la nube. No hay USB ni `adb`: el APK lo compila GitHub Actions (`.github/workflows/apk.yml`) en cada push y lo publica en Releases.

Flujo para cada cambio:
1. Hacer el cambio. Respetar la arquitectura (transporte ↔ ELM327 ↔ OBD ↔ datos ↔ UI) y probar con `MockTransport` cuando aplique.
2. Correr `flutter analyze --no-fatal-infos` y `flutter test`. Agregar o ajustar pruebas para lo nuevo.
3. Si cambia algo visible para el usuario, subir la versión en `pubspec.yaml` (`1.2.0` → `1.3.0`, etc.). El número de compilación lo pone CI (1000 + número de corrida); no tocar el `+N`.
4. Anotar decisiones no obvias en `docs/DECISIONS.md` y hallazgos del carro en `README.md`.
5. Commit y push. Luego revisar con las herramientas de GitHub (`actions_list` → `list_workflow_runs`) que la corrida "APK para la tablet" terminó bien; si falló, leer el log (`get_job_logs`) y corregir.
6. Darle al usuario el link de instalación y el número de versión que debe ver en la app:
   https://github.com/uSoloMid/aveo_scanner/releases/latest/download/aveo_scanner.apk

Notas:
- Este contenedor no puede compilar el APK (`dl.google.com`, de donde sale el SDK de Android, está bloqueado). Sí puede correr analyze y pruebas.
- Flutter va fijado en **3.47.7** (Dart 3.13.5), el mismo de `.metadata` y del workflow. Si no está instalado: descargar `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz`, descomprimir en `/root/sdk` y usar `/root/sdk/flutter/bin/flutter`.
- La firma usa los secretos `ANDROID_KEYSTORE_BASE64` y `ANDROID_KEYSTORE_PASSWORD`. Sin ellos el workflow compila pero no publica Release. Nunca subir llaves (`*.jks`, `*.keystore`, `key.properties`) al repo.
- Cada sesión nueva de Claude arranca desde `main`: lo que no llegue a `main` no lo verá la siguiente sesión.
