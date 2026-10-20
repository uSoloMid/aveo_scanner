package mx.solomid.aveo_scanner

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

class BtClassicPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()
    private val lock = Any()
    private var context: android.content.Context? = null
    private var socket: BluetoothSocket? = null
    private var sink: EventChannel.EventSink? = null
    @Volatile private var readerActive = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(binding.binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        closeSocket()
        synchronized(lock) { sink = null }
        executor.shutdownNow()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "isEnabled" && call.method != "bondedDevices" &&
            !hasConnectPermission()) {
            replyError(result, "NO_PERMISSION", "Falta el permiso Bluetooth para conectar.")
            return
        }
        try {
            when (call.method) {
                "isEnabled" -> result.success(adapter()?.isEnabled ?: false)
                "bondedDevices" -> {
                    val devices = adapter()?.bondedDevices.orEmpty().map {
                        mapOf("name" to it.name, "address" to it.address)
                    }
                    result.success(devices)
                }
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "Falta la dirección Bluetooth.", null)
                    } else {
                        executor.execute { connect(address, result) }
                    }
                }
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) result.error("INVALID_ARGUMENT", "Faltan los bytes.", null)
                    else executor.execute { write(bytes, result) }
                }
                "disconnect" -> executor.execute {
                    closeSocket()
                    replySuccess(result, null)
                }
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) {
            replyError(result, "NO_PERMISSION", error.message ?: "Falta el permiso Bluetooth.")
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        synchronized(lock) { sink = events }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) { sink = null }
    }

    private fun connect(address: String, result: MethodChannel.Result) {
        try {
            val adapter = adapter() ?: throw IOException("Bluetooth no está disponible.")
            if (!hasConnectPermission()) {
                replyError(result, "NO_PERMISSION", "Falta el permiso Bluetooth para conectar.")
                return
            }
            adapter.cancelDiscovery()
            closeSocket()
            val device = adapter.getRemoteDevice(address)
            val connected = trySocket { device.createRfcommSocketToServiceRecord(SPP_UUID) }
                ?: trySocket { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) }
                ?: trySocket {
                    device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                        .invoke(device, 1) as BluetoothSocket
                }
                ?: throw IOException("No fue posible abrir el socket SPP.")
            synchronized(lock) { socket = connected }
            readerActive = true
            replySuccess(result, null)
            startReader(connected)
        } catch (error: SecurityException) {
            replyError(result, "NO_PERMISSION", error.message ?: "Falta el permiso Bluetooth.")
        } catch (error: Exception) {
            closeSocket()
            replyError(result, "CONNECT_FAILED", error.message ?: "No se pudo conectar.")
        }
    }

    private fun trySocket(create: () -> BluetoothSocket): BluetoothSocket? {
        val candidate = try { create() } catch (_: Exception) { return null }
        try {
            candidate.connect()
            return candidate
        } catch (_: Exception) {
            try { candidate.close() } catch (_: IOException) { }
            return null
        }
    }

    private fun write(bytes: ByteArray, result: MethodChannel.Result) {
        try {
            val active = synchronized(lock) { socket } ?: throw IOException("No hay conexión Bluetooth.")
            active.outputStream.write(bytes)
            active.outputStream.flush()
            replySuccess(result, null)
        } catch (error: SecurityException) {
            replyError(result, "NO_PERMISSION", error.message ?: "Falta el permiso Bluetooth.")
        } catch (error: Exception) {
            replyError(result, "WRITE_FAILED", error.message ?: "Falló el envío Bluetooth.")
        }
    }

    private fun startReader(active: BluetoothSocket) {
        executor.execute {
            val buffer = ByteArray(1024)
            try {
                while (readerActive && active === synchronized(lock) { socket }) {
                    val count = active.inputStream.read(buffer)
                    if (count < 0) throw IOException("La conexión Bluetooth se cerró.")
                    val chunk = buffer.copyOf(count)
                    main.post { synchronized(lock) { sink }?.success(chunk) }
                }
            } catch (error: Exception) {
                // closeSocket() clears `socket` before closing, so an intentional
                // disconnect is not reported as a lost connection. No endOfStream:
                // the stream must stay usable for the next connect().
                val unexpected = synchronized(lock) { socket === active }
                if (unexpected) {
                    main.post {
                        synchronized(lock) { sink }?.error("CONNECTION_LOST", error.message ?: "Se perdió la conexión Bluetooth.", null)
                    }
                }
            } finally {
                if (active === synchronized(lock) { socket }) closeSocket()
            }
        }
    }

    private fun closeSocket() {
        readerActive = false
        val active = synchronized(lock) { val old = socket; socket = null; old }
        if (active != null) {
            try { active.inputStream.close() } catch (_: Exception) { }
            try { active.outputStream.close() } catch (_: Exception) { }
            try { active.close() } catch (_: Exception) { }
        }
    }

    private fun adapter(): BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

    private fun hasConnectPermission(): Boolean {
        val appContext = context ?: return false
        return android.os.Build.VERSION.SDK_INT < 31 || ContextCompat.checkSelfPermission(
            appContext, Manifest.permission.BLUETOOTH_CONNECT
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun replySuccess(result: MethodChannel.Result, value: Any?) = main.post { result.success(value) }
    private fun replyError(result: MethodChannel.Result, code: String, message: String) =
        main.post { result.error(code, message, null) }

    companion object {
        private const val METHOD_CHANNEL = "mx.solomid.aveo_scanner/bt_classic"
        private const val EVENT_CHANNEL = "mx.solomid.aveo_scanner/bt_classic/data"
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
