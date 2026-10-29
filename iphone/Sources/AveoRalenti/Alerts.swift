#if os(iOS)
import Foundation
import Combine
import UserNotifications
import AudioToolbox
import AVFAudio
import AveoCore

@MainActor
final class Alerts: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var message: String?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                message = "Activa las notificaciones en Configuración para recibir avisos con la app en segundo plano."
            }
        } catch {
            message = "No se pudo pedir permiso para las notificaciones: \(error.localizedDescription)"
        }
    }

    func announce(_ event: IdleMonitor.Event) {
        switch event {
        case let .becameHigh(rpm, desired):
            deliver("Ralentí alto: \(Int(rpm.rounded())) rpm (pide \(Int(desired.rounded())))", normal: false)
        case let .becameNormal(rpm):
            deliver("Ralentí normal: \(Int(rpm.rounded())) rpm", normal: true)
        case .endedByDriving:
            deliver("Fin de ralentí alto: el carro se movió o aceleró", normal: false)
        }
    }

    func test() { deliver("Prueba de alerta: Aveo Ralentí está listo", normal: true) }

    private func deliver(_ title: String, normal: Bool) {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audio.setActive(true)
        } catch {
            message = "No se pudo preparar el sonido: \(error.localizedDescription)"
        }
        AudioServicesPlaySystemSound(normal ? 1007 : 1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task { [weak self] in
            do { try await self?.center.add(request) }
            catch { self?.message = "No se pudo mostrar el aviso: \(error.localizedDescription)" }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The system sound above already plays in the foreground.
        completionHandler([.banner, .list])
    }
}
#endif
