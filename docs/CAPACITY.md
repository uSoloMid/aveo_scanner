# Medición de capacidad y calidad de captura

La capacidad es una propiedad de la combinación vehículo/ECU, protocolo, adaptador,
Bluetooth, teléfono y conjunto de parámetros. No se presenta el máximo observado
como un límite físico garantizado. No se mide la ocupación eléctrica del bus ni se
puede separar con certeza ECU de firmware del adaptador sin instrumental externo.

## Prueba en Diagnóstico

Con el vehículo detenido y el motor encendido, sin otra aplicación conectada al
adaptador, ejecutar **Medir capacidad**. El informe CSV identifica adaptador,
protocolo, transporte, versión y si se está usando el simulador.

1. Escritura local de 200 filas con vaciado por fila, sin consultas OBD.
2. Disponibilidad: doce parámetros, con un reintento de los que no responden.
3. ATI (adaptador sin ECU), 15 segundos.
4. RPM sola, 15 segundos.
5. Grupo de señales disponibles con AT1 y pausas de 250, 100 y 50 ms,
   15 segundos por ajuste.
6. El mismo grupo con AT2 y pausa de 50 ms, 15 segundos.
7. Grupo ampliado de todos los parámetros disponibles con AT1 y AT2, 15 segundos por ajuste.
8. Dos minutos con la configuración mixta más rápida que haya resultado estable.

Duración nominal: unos cinco minutos; los tiempos agotados y la exploración de
soporte pueden extenderla. No se mandan comandos de borrado, actuadores o escritura
ECU. No se superponen comandos ni se reduce el margen entre comandos por debajo de
50 ms. AT1/AT2 cambian únicamente la temporización del adaptador. El ajuste previo
se restaura incluso al cancelar. No se acortan los tiempos de espera sin evidencia.

Cada consulta guarda la respuesta original, coincidencia del servicio/PID,
longitud mínima, errores explícitos, respuestas negativas, espera en cola,
tiempo total, primer byte, envío-a-prompt e interpretación. El primer byte incluye
transporte Bluetooth/firmware: no es una medición directa de latencia ECU.
La tasa efectiva de la etapa incluye el guardado. Las estadísticas por parámetro
agrupan ajustes distintos y así se etiquetan; usar fase/comando para comparar.

Estable significa >=10 intentos, >=98% respuestas válidas, sin aborto. Se corta
una etapa tras tres fallos consecutivos o >10% fallos a partir de diez intentos.
Estos criterios son políticas del programa, no especificaciones GM. No se sigue
acelerando si falla una etapa mixta AT1. Una respuesta válida no demuestra que el
sensor sea exacto ni que la ECU publique una muestra interna nueva cada vez.

**Usar ajuste con margen** añade 50 ms a la pausa validada y aplica el modo AT
correspondiente solo durante la conexión actual. Repetir la prueba en diferentes
condiciones de funcionamiento para comprobar estabilidad. No se aplican los
resultados de ATI o RPM sola como capacidad del grupo completo.

## Grabación normal

Seis señales rápidas por ciclo y hasta tres adicionales vencidas, dando prioridad
a MAP y combustible sobre temperaturas. Las señales lentas con tres fallos se
reintentan cada 30 segundos. La hora de cada lectura permite ver el intervalo real;
los valores retenidos no representan una captura simultánea. Las marcas contienen
la hora del toque, aunque la fila se escriba al terminar el ciclo.

El archivo permanece abierto al cambiar pestañas y orientación. Durante captura,
prueba o exploración se pausan las pantallas que emiten otras consultas. Registros
permite seleccionar, compartir y eliminar varios archivos incluso sin adaptador;
los archivos activos están protegidos. Confirmación antes de eliminar.

La cola de consultas y la cola de escritura están limitadas a 32, el historial de
eventos a 100 y una respuesta sin prompt a 64 KiB. Los errores de disco se muestran
y detienen la grabación. La recuperación intenta reconectar Bluetooth si está
caído y reinicializar el enlace ECU; los huecos no se rellenan con datos inventados.
No se garantiza captura con Android cerrando o suspendiendo el proceso: mantener
la aplicación abierta. La navegación interna sí conserva la sesión.

## Interpretación

- ATI lento/errático: investigar teléfono, Bluetooth y adaptador.
- ATI rápido pero RPM lenta: cuello en la ruta adaptador/protocolo/ECU.
- Un parámetro falla y otros responden: investigar soporte, fórmula y respuesta raw.
- Cola creciente: competencia de consumidores o solicitudes más rápidas que servicio.
- Interpretación o escritura lentas: cuello de procesamiento o almacenamiento local.
- Todas las consultas ECU fallan pero ATRV funciona: adaptador vivo, enlace ECU caído.

Los resultados ayudan a ubicar el tramo; no atribuyen automáticamente una falla a
una pieza del vehículo. Comparar con otro adaptador o escáner es una prueba A/B
necesaria para separar ciertos casos de firmware y ECU.

Referencia técnica: https://www.elmelectronics.com/wp-content/uploads/2017/01/ELM327DS.pdf

## Ficha aportada del adaptador

La referencia comercial aportada es JOYING ELM327 V2.1 Bluetooth, PIN 1234,
serial nominal 38400. Se conserva como referencia, no como identificación
verificada del equipo conectado. ATI y ATDP/ATDPN se registran durante la prueba.
Un firmware puede declarar una versión sin implementar todos sus comandos.

ELM327DSI.pdf aportado, páginas 3, 62 y 65: 38400 se refiere a la interfaz serial
RS232 del chip, no a mediciones por segundo. En 8N1 serían aproximadamente 3840
bytes/s antes de considerar comandos, texto y esperas. El Bluetooth SPP de Android
no expone un ajuste de baud equivalente al cable UART interno del dongle; no se
cambia BRD/PP para intentar acelerarlo.

La página 65 describe cómo las esperas posteriores a la respuesta pueden limitar
el ritmo, y la optimización por número de respuestas esperado. Esta última no se
activa: primero hay que conocer todos los respondedores y validar el protocolo,
pues un conteo menor puede ocasionar retransmisiones y congestión. Las cifras de
4/7/10-12 consultas/s del manual son ejemplos, no capacidades medidas del Aveo.

Ficha: https://elm327mini.com/products/elm327-mini-for-android-head-units/

## Ajustes de estabilidad 1.1.1

La grabación comienza con al menos 100 ms entre comandos. Ante un fallo en una
señal rápida permite un solo reintento por ciclo tras 200 ms; registra el fallo y
si el reintento respondió. Aumenta la pausa 50 ms por ciclo con fallos rápidos,
hasta 500 ms. Tras 20 ciclos rápidos limpios la reduce 25 ms sin bajar del punto
de partida. No se descartan fallos del informe ni se promete ausencia de huecos.

Solo se recupera todo el enlace tras dos ciclos sin ninguna respuesta ECU; ATRV
no cuenta como respuesta del motor. Si IAC u otras señales responden pero RPM no,
se informa lectura parcial y no se reinicia el enlace. Las lecturas lentas se
ordenan por fecha de vencimiento, evitando que MAP/combustible releguen siempre
la temperatura. Voltaje ECU se prueba como opcional y se omite si no responde.
Las respuestas modo 01 deben coincidir con el PID solicitado.

La prueba excluye de cada etapa ECU su preparación: exige tres lecturas RPM
consecutivas correctas, con hasta seis intentos, antes de empezar a cronometrar.
Se guardan también esas consultas de preparación. Compara además ATAT0 con
ATST64 (espera fija de aproximadamente 400 ms) frente a ATAT1/ATAT2 con ATST32.
Una etapa mixta que termina pero no alcanza 98% se repite una vez; las dos
mediciones se conservan por separado, no se ocultan los fallos originales.
La validación sostenida sigue siendo necesaria. Al terminar se restauran tanto
ATST como ATAT y la pausa del programa. El tiempo total puede ser 5-8 minutos o
más según las repeticiones y las esperas. No se puede inferir la salud de una
pieza a partir de NO DATA: es un resultado de comunicación.
