#if os(iOS)
import SwiftUI

@main
@MainActor
struct AveoRalentiApp: App {
    @StateObject private var ble: BleElm
    @StateObject private var poller: Poller
    @StateObject private var alerts: Alerts

    init() {
        let ble = BleElm()
        let alerts = Alerts()
        _ble = StateObject(wrappedValue: ble)
        _alerts = StateObject(wrappedValue: alerts)
        _poller = StateObject(wrappedValue: Poller(ble: ble, alerts: alerts))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(ble: ble, poller: poller, alerts: alerts)
                .task { await alerts.requestPermission() }
        }
    }
}
#endif
