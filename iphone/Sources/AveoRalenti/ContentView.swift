#if os(iOS)
import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
    @ObservedObject var ble: BleElm
    @ObservedObject var poller: Poller
    @ObservedObject var alerts: Alerts
    @State private var showingDevices = false
    @State private var keepAwake = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var rpmSize: CGFloat = 64

    private var valid: Bool { ble.isReady && poller.hasData && poller.isRecording }
    private var stateText: String { !valid ? "Sin datos" : poller.isHigh ? "RALENTÍ ALTO" : "Normal" }
    private var stateColor: Color {
        // Darker state inks keep the smaller RPM label legible in daylight.
        if !valid {
            return colorScheme == .dark
                ? Color(red: 0.80, green: 0.84, blue: 0.88)
                : Color(red: 0.29, green: 0.33, blue: 0.39)
        }
        if poller.isHigh {
            return colorScheme == .dark
                ? Color(red: 0.99, green: 0.65, blue: 0.65)
                : Color(red: 0.73, green: 0.11, blue: 0.11)
        }
        return colorScheme == .dark
            ? Color(red: 0.53, green: 0.94, blue: 0.67)
            : Color(red: 0.09, green: 0.40, blue: 0.20)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    connection
                    indicator
                    readings
                    if let relative = poller.values["mariposa_relativa_pct"], relative > 1,
                       ble.isReady && poller.isRecording {
                        Label("la computadora cree que estás acelerando", systemImage: "exclamationmark.triangle.fill")
                            .font(.title3.weight(.semibold))
                    }
                    recording
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Mantener pantalla encendida", isOn: $keepAwake)
                        Button("Probar alerta") { alerts.test() }
                            .frame(minHeight: 44)
                    }
                    if let message = poller.message { Text(message).font(.body) }
                    if let message = alerts.message { Text(message).font(.body) }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Aveo Ralentí")
            .sheet(isPresented: $showingDevices, onDismiss: { ble.stopScan() }) { devicePicker }
            .onChange(of: keepAwake) { _, _ in updateIdleTimer() }
            .onChange(of: scenePhase) { _, phase in
                updateIdleTimer()
                if phase == .active { ble.reconnect() }
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onAppear { updateIdleTimer() }
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ble.status, systemImage: ble.isReady ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .font(.headline)
            Button(ble.isReady ? "Dispositivos" : "Conectar") {
                ble.scan()
                showingDevices = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var indicator: some View {
        VStack(spacing: 12) {
            Image(systemName: !valid ? "minus.circle.fill" : poller.isHigh ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(stateText)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(valid ? number(poller.values["rpm"]) : "—")
                .font(.system(size: rpmSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("RPM real").font(.title3)
        }
        .foregroundStyle(stateColor)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(stateColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stateText). RPM real: \(valid ? number(poller.values["rpm"]) : "sin datos")")
    }

    private var readings: some View {
        VStack(spacing: 16) {
            metric("Pide la computadora", value: number(poller.values["ralenti_deseado_rpm"]), unit: "rpm")
            Divider()
            metric("Diferencia", value: difference, unit: "rpm")
            Divider()
            metric("IAC", value: number(poller.values["iac_pasos"]), unit: "pasos")
            Divider()
            metric("Mariposa relativa", value: number(poller.values["mariposa_relativa_pct"], decimals: 1), unit: "%")
        }
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).font(.title3)
                Spacer(minLength: 8)
                Text("\(value) \(unit)").font(.title2.bold()).monospacedDigit().fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3)
                Text("\(value) \(unit)").font(.title2.bold()).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(poller.isStopping ? "Deteniendo…" : poller.isRecording ? "Detener" : "Grabar") {
                if poller.isRecording { poller.stop() } else { poller.start() }
            }
            .font(.title2.bold())
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: 44)
            .disabled(poller.isStopping)
            Text("\(poller.rowCount) filas grabadas").font(.headline).monospacedDigit()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { markerButtons }
                VStack(alignment: .leading, spacing: 12) { markerButtons }
            }
            .disabled(!poller.isRecording)
            if let url = poller.csvURL {
                ShareLink(item: url) { Label("Compartir CSV", systemImage: "square.and.arrow.up") }
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            if !poller.isRecording {
                Text("Conecta el adaptador y toca Grabar para vigilar el ralentí.").font(.body)
            }
        }
    }

    @ViewBuilder private var markerButtons: some View {
        Button("SE ACELERÓ") { poller.mark("SE ACELERÓ") }
            .buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
        Button("SE COMPUSO") { poller.mark("SE COMPUSO") }
            .buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
    }

    private var devicePicker: some View {
        NavigationStack {
            List {
                Section {
                    Text(ble.status)
                    if ble.isScanning { ProgressView("Buscando dispositivos con nombre…") }
                    if ble.devices.isEmpty {
                        Text("Enciende tu adaptador Bluetooth LE y acércalo al iPhone.")
                    }
                }
                Section("Dispositivos") {
                    ForEach(ble.devices) { device in
                        Button {
                            ble.connect(device.id)
                            showingDevices = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).font(.headline)
                                if device.preferred { Text("Posible adaptador OBD").font(.subheadline) }
                            }
                            .padding(.vertical, 8)
                            .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
            }
            .navigationTitle("Conectar")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { showingDevices = false }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Buscar de nuevo") { ble.scan() }
                }
            }
        }
    }

    private var difference: String {
        guard let rpm = poller.values["rpm"], let desired = poller.values["ralenti_deseado_rpm"] else { return "—" }
        return number(rpm - desired)
    }

    private func number(_ value: Double?, decimals: Int = 0) -> String {
        guard let value, ble.isReady else { return "—" }
        return value.formatted(.number.locale(Locale(identifier: "es_MX")).precision(.fractionLength(decimals)))
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && scenePhase == .active
    }
}
#endif
