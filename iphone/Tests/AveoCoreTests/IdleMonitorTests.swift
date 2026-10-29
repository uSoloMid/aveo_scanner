import XCTest
import AveoCore

final class IdleMonitorTests: XCTestCase {
    func testDartReferenceSequence() {
        var monitor = IdleMonitor()
        XCTAssertNil(monitor.update(rpm: 1470, desired: 825, speed: 0, throttle: 11))
        XCTAssertEqual(monitor.update(rpm: 1470, desired: 825, speed: 0, throttle: 11), .becameHigh(1470, 825))
        XCTAssertTrue(monitor.isHigh)
        XCTAssertNil(monitor.update(rpm: 1100, desired: 825, speed: 0, throttle: 11))
        XCTAssertEqual(monitor.update(rpm: 850, desired: 825, speed: 0, throttle: 11), .becameNormal(850))
        XCTAssertFalse(monitor.isHigh)
        XCTAssertNil(monitor.update(rpm: 2000, desired: 825, speed: 40, throttle: 11))
        XCTAssertNil(monitor.update(rpm: 2000, desired: 825, speed: 40, throttle: 11))
    }

    func testStrictThresholdsConsecutiveEntryAndHysteresis() {
        var monitor = IdleMonitor()
        XCTAssertNil(monitor.update(rpm: 1125, desired: 825)) // Exactly 300: no entry.
        XCTAssertNil(monitor.update(rpm: 1125, desired: 825))
        XCTAssertNil(monitor.update(rpm: 1470, desired: 825))
        XCTAssertNil(monitor.update(rpm: 1000, desired: 825)) // Resets the streak.
        XCTAssertNil(monitor.update(rpm: 1470, desired: 825))
        XCTAssertEqual(monitor.update(rpm: 1470, desired: 825), .becameHigh(1470, 825))
        XCTAssertNil(monitor.update(rpm: 975, desired: 825)) // Exactly 150: stays high.
        XCTAssertEqual(monitor.update(rpm: 974, desired: 825), .becameNormal(974))
    }

    func testMovementAndThrottlePreventEntryAndEndHighIdle() {
        for (speed, throttle) in [(2.0, 11.0), (0.0, 14.0)] {
            var monitor = IdleMonitor()
            XCTAssertNil(monitor.update(rpm: 1470, desired: 825, speed: speed, throttle: throttle))
            XCTAssertNil(monitor.update(rpm: 1470, desired: 825, speed: speed, throttle: throttle))
            XCTAssertFalse(monitor.isHigh)
            XCTAssertNil(monitor.update(rpm: 1470, desired: 825, speed: 1.9, throttle: 13.9))
            XCTAssertEqual(monitor.update(rpm: 1470, desired: 825, speed: 1.9, throttle: 13.9), .becameHigh(1470, 825))
            XCTAssertEqual(monitor.update(rpm: 1470, desired: 825, speed: speed, throttle: throttle), .endedByDriving)
            XCTAssertFalse(monitor.isHigh)
        }
    }

    func testMissingOrStoppedEngineMatchesReferenceNoChange() {
        var monitor = IdleMonitor()
        XCTAssertNil(monitor.update(rpm: nil, desired: 825))
        XCTAssertNil(monitor.update(rpm: 1470, desired: nil))
        XCTAssertNil(monitor.update(rpm: 0, desired: 825))
        XCTAssertNil(monitor.update(rpm: 1470, desired: 0))
        XCTAssertNil(monitor.update(rpm: 1470, desired: 825))
        XCTAssertNil(monitor.update(rpm: nil, desired: 825)) // Reference preserves streak.
        XCTAssertEqual(monitor.update(rpm: 1470, desired: 825), .becameHigh(1470, 825))
        XCTAssertNil(monitor.update(rpm: 0, desired: 825))
        XCTAssertTrue(monitor.isHigh)
    }
}
