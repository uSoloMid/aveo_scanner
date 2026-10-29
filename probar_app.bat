@echo off
rem Revisa, prueba e instala la app en la tablet conectada por USB.
rem El resultado completo queda en resultado_flutter.txt para que Claude lo lea.
cd /d "%~dp0"
set LOG=resultado_flutter.txt
echo Fecha: %date% %time% > %LOG%

echo [1/5] Descargando paquetes...
echo ===== flutter pub get ===== >> %LOG%
call flutter pub get >> %LOG% 2>&1

echo [2/5] Revisando el codigo...
echo ===== flutter analyze ===== >> %LOG%
call flutter analyze >> %LOG% 2>&1

echo [3/5] Corriendo pruebas...
echo ===== flutter test ===== >> %LOG%
call flutter test >> %LOG% 2>&1

echo [4/5] Buscando la tablet...
echo ===== flutter devices ===== >> %LOG%
call flutter devices >> %LOG% 2>&1

echo [5/5] Compilando e instalando en la tablet (tarda unos minutos)...
echo ===== flutter build apk --release ===== >> %LOG%
call flutter build apk --release >> %LOG% 2>&1
echo ===== flutter install --release ===== >> %LOG%
call flutter install --release >> %LOG% 2>&1

echo ===== FIN ===== >> %LOG%
echo.
echo Listo. Avisale a Claude: ya puede leer resultado_flutter.txt
pause
