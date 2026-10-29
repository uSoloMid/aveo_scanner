#if os(iOS)
import Foundation
import Combine
import AveoCore

@MainActor
final class Poller: ObservableObject {
    @Published private(set) var values: [String: Double] = [:]
    @Published private(set) var isRecording = false
    @Published private(set) var isStopping = false
    @Published private(set) var isHigh = false
    @Published private(set) var hasData = false
    @Published private(set) var rowCount = 0
    @Published private(set) var csvURL: URL?
    @Published private(set) var message: String?

    private let ble: BleElm
    private let alerts: Alerts
    private var monitor = IdleMonitor()
    private var log: CsvLog?
    private var task: Task<Void, Never>?
    private var markers: [String] = []
    private var slowIndex = 0
    private let fast = ["010C", "221192", "221172", "0145"]
    private let slow = ["010D", "0111", "0105", "ATRV"]
    private let keys = [
        "010C": "rpm", "221192": "ralenti_deseado_rpm", "221172": "iac_pasos",
        "0145": "mariposa_relativa_pct", "010D": "velocidad_kmh", "0111": "mariposa_pct",
        "0105": "refrigerante_c", "ATRV": "voltaje_bateria_v"
    ]

    init(ble: BleElm, alerts: Alerts) {
        self.ble = ble
        self.alerts = alerts
        if let name = UserDefaults.standard.string(forKey: "AveoRalenti.lastCSV"),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = documents.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { csvURL = url }
        }
    }

    func start() {
        guard !isRecording, task == nil else { return }
        do {
            let recording = try CsvLog()
            log = recording
            csvURL = recording.url
            UserDefaults.standard.set(recording.url.lastPathComponent, forKey: "AveoRalenti.lastCSV")
            rowCount = 0
            markers = []
            slowIndex = 0
            clearReadings()
            message = nil
            isRecording = true
            task = Task { [weak self] in await self?.run() }
        } catch {
            message = "No se pudo crear el CSV: \(error.localizedDescription)"
        }
    }

    func stop() {
        isStopping = task != nil
        isRecording = false
        task?.cancel()
        // run() releases the task only after the in-flight request unwinds.
        closeLog()
        hasData = false
    }

    func mark(_ label: String) {
        guard isRecording else { return }
        markers.append(label)
    }

    private func clearReadings() {
        values = [:]
        monitor = IdleMonitor()
        isHigh = false
        hasData = false
    }

    private func closeLog() {
        do { try log?.close() }
        catch { message = "No se pudo cerrar el CSV: \(error.localizedDescription)" }
        log = nil
    }

    private func initializeAdapter() async throws {
        _ = try await ble.send("ATZ")
        try await Task.sleep(for: .seconds(1))
        for command in ["ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"] {
            _ = try await ble.send(command)
        }
        for attempt in 0..<3 {
            let reply = try await ble.send("0100")
            let compact = reply.uppercased().filter { !$0.isWhitespace }
            if compact.contains("4100") { return }
            if attempt < 2 { try await Task.sleep(for: .seconds(1)) }
        }
        throw InitializationError.noECU
    }

    private func run() async {
        defer {
            isRecording = false
            isStopping = false
            hasData = false
            closeLog()
            task = nil
        }
        var initializedSession: UUID?
        while isRecording, !Task.isCancelled {
            guard ble.isReady, let session = ble.connectionID else {
                clearReadings()
                initializedSession = nil
                ble.reconnect()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                continue
            }
            do {
                if initializedSession != session {
                    clearReadings()
                    message = "Preparando la conexión con la computadora del Aveo…"
                    try await initializeAdapter()
                    try Task.checkCancellation()
                    guard ble.connectionID == session else { continue }
                    initializedSession = session
                    message = nil
                }
                let replies = try await cycle(session: session)
                if replies == 0 {
                    message = "Sin respuesta de la computadora. Revisa que el encendido esté abierto."
                    try await Task.sleep(for: .seconds(1))
                } else { message = nil }
            } catch is CancellationError {
                break
            } catch {
                if !isRecording { break }
                message = error.localizedDescription
                hasData = false
                initializedSession = nil
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    private func cycle(session: UUID) async throws -> Int {
        let commands = fast + [slow[slowIndex % slow.count]]
        slowIndex = (slowIndex + 1) % slow.count
        var next = values
        var replies = 0
        for command in commands {
            try Task.checkCancellation()
            guard ble.connectionID == session else { return 0 }
            do {
                let raw = try await ble.send(command)
                if let value = ElmParser.value(raw, command: command), let key = keys[command] {
                    next[key] = value
                    replies += 1
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                if !ble.isReady { throw error }
                // NO DATA and unsupported PIDs keep the last known value.
            }
        }
        try Task.checkCancellation()
        guard ble.connectionID == session, isRecording else { return 0 }
        values = next
        let event = monitor.update(
            rpm: next["rpm"], desired: next["ralenti_deseado_rpm"],
            speed: next["velocidad_kmh"], throttle: next["mariposa_pct"]
        )
        isHigh = monitor.isHigh
        hasData = replies > 0 && (next["rpm"] ?? 0) > 0 && (next["ralenti_deseado_rpm"] ?? 0) > 0
        if let event { alerts.announce(event) }
        let events = (event.map { [$0.description] } ?? []) + markers
        do {
            try log?.append(event: events.joined(separator: " | "), highIdle: isHigh, values: next)
            markers.removeAll()
            rowCount = log?.rowCount ?? rowCount
        } catch {
            message = "Se detuvo la grabación porque no se pudo escribir el CSV: \(error.localizedDescription)"
            isRecording = false
            throw error
        }
        return replies
    }

    private enum InitializationError: LocalizedError {
        case noECU
        var errorDescription: String? {
            "La computadora no respondió después de tres intentos. Revisa el encendido; se volverá a intentar."
        }
    }
}
#endif
