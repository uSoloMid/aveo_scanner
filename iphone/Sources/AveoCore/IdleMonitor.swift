import Foundation

public struct IdleMonitor: Sendable {
    public enum Event: Equatable, Sendable {
        case becameHigh(Double, Double)
        case becameNormal(Double)
        case endedByDriving

        public var description: String {
            switch self {
            case let .becameHigh(rpm, desired):
                return "AUTO: ralentí alto (\(Int(rpm.rounded())) rpm, pide \(Int(desired.rounded())))"
            case let .becameNormal(rpm):
                return "AUTO: ralentí normal (\(Int(rpm.rounded())) rpm)"
            case .endedByDriving:
                return "AUTO: fin ralentí alto (se movió o aceleró)"
            }
        }
    }

    public private(set) var isHigh = false
    private var streak = 0

    public init() {}

    public mutating func update(
        rpm: Double?, desired: Double?, speed: Double? = nil, throttle: Double? = nil
    ) -> Event? {
        guard let rpm, let desired, rpm.isFinite, desired.isFinite,
              rpm > 0, desired > 0 else { return nil }
        let idleConditions = (speed ?? 0) < 2 && (throttle ?? 0) < 14
        let delta = rpm - desired
        if !isHigh {
            streak = idleConditions && delta > 300 ? streak + 1 : 0
            if streak >= 2 {
                isHigh = true
                return .becameHigh(rpm, desired)
            }
        } else if !idleConditions || delta < 150 {
            isHigh = false
            streak = 0
            return idleConditions ? .becameNormal(rpm) : .endedByDriving
        }
        return nil
    }
}
