import XCTest
import AveoCore

final class ElmParserTests: XCTestCase {
    func testRealAveoResponses() {
        XCTAssertEqual(ElmParser.bytes("62 11 92 41", expectedPrefix: "621192"), [0x41])
        XCTAssertEqual(ElmParser.value("62 11 92 41", command: "221192"), 812.5)
        XCTAssertEqual(ElmParser.value("62 11 72 25", command: "221172"), 37)
        XCTAssertEqual(ElmParser.value("41 0C 0D 3C", command: "010C"), 847)
        XCTAssertEqual(ElmParser.value("83F111621172258F\r\r>", command: "221172"), 37)
        XCTAssertEqual(ElmParser.value("83F11162119241CB\r\r>", command: "221192"), 812.5)
    }

    func testEchoSearchingBusInitAndAllDecoders() {
        XCTAssertEqual(ElmParser.value("010C\rSEARCHING...\r41 0C 0D 3C\r>", command: "010C"), 847)
        XCTAssertEqual(ElmParser.value("BUS INIT: ...\r41 0D 28\r>", command: "010D"), 40)
        XCTAssertEqual(ElmParser.value("BUS INIT: ...41 0D 28>", command: "010D"), 40)
        XCTAssertEqual(ElmParser.value("41 45 FF>", command: "0145"), 100)
        XCTAssertEqual(ElmParser.value("41 11 FF>", command: "0111"), 100)
        XCTAssertEqual(ElmParser.value("41 05 7B>", command: "0105"), 83)
        XCTAssertEqual(ElmParser.value("41 05 00>", command: "0105"), -40)
        XCTAssertEqual(ElmParser.value("ATRV\r12.6V\r>", command: "ATRV"), 12.6)
        XCTAssertEqual(ElmParser.value(" 14.2 V\r>", command: "ATRV"), 14.2)
    }

    func testErrorsMissingAndTruncatedPayloadsAreUnknown() {
        for response in ["BUS INIT: ...ERROR", "NO DATA", "?", "ERROR", "UNABLE TO CONNECT",
                         "STOPPED", "7F2231", "7F 22 31", "", "410C", "410C0D", "410CGG", "4145FF"] {
            XCTAssertNil(ElmParser.value(response, command: "010C"), response)
        }
        XCTAssertNil(ElmParser.value("NO DATA", command: "221192"))
        XCTAssertNil(ElmParser.value("7F2231", command: "221192"))
        XCTAssertNil(ElmParser.value("ATRV\rERROR>", command: "ATRV"))
        XCTAssertNil(ElmParser.value("V>", command: "ATRV"))
        XCTAssertNil(ElmParser.value("410C0D3C", command: "unknown"))
    }
}
