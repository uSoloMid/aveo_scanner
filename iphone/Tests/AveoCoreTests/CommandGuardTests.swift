import XCTest
import AveoCore

final class CommandGuardTests: XCTestCase {
    func testAllowsOnlyReadCommandsAndListedAdapterSetup() {
        for command in ["010C", "221192", "ATRV", "ATZ", "ATE0", "ATL0", "ATS0",
                        "ATH0", "ATSP0", "ATDPN", "0902", "01 0C", "010c"] {
            XCTAssertTrue(CommandGuard.isAllowed(command), command)
        }
        for command in ["04", "2E1192", "ATMA", "14FF00", "3B01", "2F01", "3101", "2701",
                        "", "010", "010Z", "010C\r04", "010C\nATMA", "010C;04", "ATRV\r", "ATSP1"] {
            XCTAssertFalse(CommandGuard.isAllowed(command), command)
        }
    }
}
