#if os(iOS)
import Foundation
@preconcurrency import CoreBluetooth
import Combine
import AveoCore

private enum ElmError: LocalizedError {
    case forbidden, disconnected, timeout, unavailable

    var errorDescription: String? {
        switch self {
        case .forbidden: return "Comando rechazado: solo se permite lectura."
        case .disconnected: return "Se perdió la conexión con el adaptador."
        case .timeout: return "El adaptador no respondió a tiempo. Reconectando…"
        case .unavailable: return "El dispositivo no ofrece lectura y escritura Bluetooth."
        }
    }
}

/// An actor is reentrant at await points, so explicitly hold a FIFO permit
/// through the entire request/response exchange.
private actor ElmCommandQueue {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func send(_ command: String, through transport: BleElm) async throws -> String {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        return try await transport.exchange(command)
    }
}

@MainActor
final class BleElm: NSObject, ObservableObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct Device: Identifiable {
        let id: UUID
        let name: String
        var preferred: Bool {
            ["OBD", "ELM", "V-LINK", "IOS-VLINK", "VGATE"].contains {
                name.uppercased().contains($0)
            }
        }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var status = "Iniciando Bluetooth…"
    @Published private(set) var isReady = false
    @Published private(set) var isScanning = false
    @Published private(set) var connectionID: UUID?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var reader: CBCharacteristic?
    private var writer: CBCharacteristic?
    private var discovering = 0
    private let queue = ElmCommandQueue()
    private let lastDeviceKey = "AveoRalenti.lastPeripheral"
    private var reconnectTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var response: CheckedContinuation<String, any Error>?
    private var requestID: UUID?
    private var buffer = ""
    private var deferredWrite: Data?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        if !isReady { status = "Buscando dispositivos…" }
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ id: UUID) {
        guard let device = peripherals[id] else { return }
        if peripheral?.identifier == id, device.state == .connected || device.state == .connecting { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        stopScan()
        finish(.failure(ElmError.disconnected))
        if let old = peripheral, old.identifier != id { central.cancelPeripheralConnection(old) }
        clearConnection()
        peripheral = device
        device.delegate = self
        status = "Conectando a \(device.name ?? "adaptador")…"
        central.connect(device)
    }

    func reconnect() {
        guard central.state == .poweredOn, !isReady else { return }
        if let peripheral, peripheral.state == .connecting || peripheral.state == .connected { return }
        if let raw = UserDefaults.standard.string(forKey: lastDeviceKey), let id = UUID(uuidString: raw),
           let saved = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = saved
            connect(id)
        } else {
            scan()
        }
    }

    func send(_ command: String) async throws -> String {
        guard CommandGuard.isAllowed(command) else { throw ElmError.forbidden }
        return try await queue.send(command.uppercased(), through: self)
    }

    fileprivate func exchange(_ command: String) async throws -> String {
        try Task.checkCancellation()
        guard CommandGuard.isAllowed(command) else { throw ElmError.forbidden }
        guard isReady, let peripheral, let writer else { throw ElmError.disconnected }
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requestID = token
                response = continuation
                buffer = ""
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(command == "0100" ? 8 : 4)) }
                    catch { return }
                    self?.abortRequest(token, error: ElmError.timeout)
                }
                let data = Data((command + "\r").utf8)
                if writer.properties.contains(.write) {
                    peripheral.writeValue(data, for: writer, type: .withResponse)
                } else if peripheral.canSendWriteWithoutResponse {
                    peripheral.writeValue(data, for: writer, type: .withoutResponse)
                } else {
                    deferredWrite = data
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.abortRequest(token, error: CancellationError())
            }
        }
    }

    private func abortRequest(_ token: UUID, error: any Error) {
        guard requestID == token else { return }
        finish(.failure(error))
        // Drain late replies by replacing the connection before another command.
        clearConnection()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    private func finish(_ result: Result<String, any Error>) {
        let continuation = response
        response = nil
        requestID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        deferredWrite = nil
        buffer = ""
        continuation?.resume(with: result)
    }

    private func clearConnection() {
        isReady = false
        connectionID = nil
        reader = nil
        writer = nil
        discovering = 0
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.reconnect()
        }
    }

    private func checkReady() {
        guard let peripheral, let reader, reader.isNotifying, writer != nil, !isReady else { return }
        isReady = true
        connectionID = UUID()
        status = "Conectado: \(peripheral.name ?? "adaptador OBD")"
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastDeviceKey)
    }

    private func failConnection(_ message: String) {
        status = message
        finish(.failure(ElmError.disconnected))
        clearConnection()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { reconnect(); return }
        finish(.failure(ElmError.disconnected))
        clearConnection()
        peripheral = nil
        isScanning = false
        reconnectTask?.cancel()
        switch central.state {
        case .unauthorized: status = "Permite Bluetooth en Configuración para conectar el OBD."
        case .poweredOff: status = "Enciende Bluetooth para conectar el OBD."
        case .unsupported: status = "Este dispositivo no admite Bluetooth LE."
        default: status = "Bluetooth no está disponible."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = device.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        peripherals[device.identifier] = device
        devices.removeAll { $0.id == device.identifier }
        devices.append(Device(id: device.identifier, name: name))
        devices.sort {
            if $0.preferred != $1.preferred { return $0.preferred }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        guard device.identifier == peripheral?.identifier else { return }
        status = "Preparando adaptador…"
        device.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: (any Error)?) {
        disconnected(device)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral,
                        error: (any Error)?) {
        disconnected(device)
    }

    private func disconnected(_ device: CBPeripheral) {
        guard device.identifier == peripheral?.identifier else { return }
        finish(.failure(ElmError.disconnected))
        clearConnection()
        status = "Sin conexión. Reconectando…"
        // Also retry a device that has not completed discovery yet.
        peripherals[device.identifier] = device
        UserDefaults.standard.set(device.identifier.uuidString, forKey: lastDeviceKey)
        peripheral = nil
        scheduleReconnect()
    }

    func peripheral(_ device: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard device.identifier == peripheral?.identifier else { return }
        guard error == nil, let services = device.services, !services.isEmpty else {
            failConnection("No se encontraron servicios. Reconectando…"); return
        }
        discovering = services.count
        for service in services { device.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ device: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: (any Error)?) {
        guard device.identifier == peripheral?.identifier else { return }
        discovering -= 1
        if error == nil {
            for characteristic in service.characteristics ?? [] {
                if reader == nil, characteristic.properties.contains(.notify) {
                    reader = characteristic
                    device.setNotifyValue(true, for: characteristic)
                }
                if writer == nil, !characteristic.properties.intersection([.write, .writeWithoutResponse]).isEmpty {
                    writer = characteristic
                }
            }
        }
        if discovering == 0, reader == nil || writer == nil {
            failConnection(ElmError.unavailable.localizedDescription)
        } else { checkReady() }
    }

    func peripheral(_ device: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard device.identifier == peripheral?.identifier, characteristic === reader else { return }
        if error != nil || !characteristic.isNotifying {
            failConnection("No se pudieron activar las lecturas. Reconectando…")
        } else { checkReady() }
    }

    func peripheral(_ device: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard device.identifier == peripheral?.identifier, characteristic === reader, response != nil else { return }
        if let error { failConnection(error.localizedDescription); return }
        guard let data = characteristic.value else { return }
        buffer += String(decoding: data, as: UTF8.self)
        if let prompt = buffer.firstIndex(of: ">") {
            finish(.success(String(buffer[...prompt])))
        }
    }

    func peripheral(_ device: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard device.identifier == peripheral?.identifier, characteristic === writer else { return }
        if let error { failConnection(error.localizedDescription) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse device: CBPeripheral) {
        guard device.identifier == peripheral?.identifier, let writer, let data = deferredWrite else { return }
        deferredWrite = nil
        device.writeValue(data, for: writer, type: .withoutResponse)
    }
}
#endif
