import Foundation
import XCTest
import AveoCore

final class CsvLogTests: XCTestCase {
    func testExactHeaderEscapedEventUnknownFieldsAndTimestamp() {
        XCTAssertEqual(CsvLog.header, "hora,evento,ralenti_alto,rpm,ralenti_deseado_rpm,iac_pasos,mariposa_relativa_pct,velocidad_kmh,mariposa_pct,refrigerante_c,voltaje_bateria_v")
        let date = sampleDate()
        let row = CsvLog.row(at: date, event: "SE ACELERÓ, dijo \"sí\"", highIdle: true,
                             values: ["rpm": 1470, "ralenti_deseado_rpm": 825])
        XCTAssertEqual(row, "10:59:03.120,\"SE ACELERÓ, dijo \"\"sí\"\"\",1,1470.0,825.0,,,,,,")
        XCTAssertEqual(CsvLog.row(at: date, event: "", highIdle: false, values: [:]),
                       "10:59:03.120,,0,,,,,,,,")
    }

    func testRowsReachDiskBeforeClosingAndDoNotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = sampleDate()
        let log = try CsvLog(directory: directory, at: date)
        defer { try? log.close() }
        XCTAssertEqual(log.url.lastPathComponent, "aveo_2026-10-22_10-59-03.csv")
        XCTAssertEqual(try String(contentsOf: log.url, encoding: .utf8), CsvLog.header + "\n")
        try log.append(at: date, event: "SE COMPUSO", highIdle: false, values: ["rpm": 850])
        XCTAssertEqual(log.rowCount, 1)
        let contents = try String(contentsOf: log.url, encoding: .utf8)
        XCTAssertEqual(contents, CsvLog.header + "\n10:59:03.120,SE COMPUSO,0,850.0,,,,,,,\n")
        XCTAssertThrowsError(try CsvLog(directory: directory, at: date))
        XCTAssertEqual(try String(contentsOf: log.url, encoding: .utf8), contents)
        try log.close()
        XCTAssertThrowsError(try log.append(highIdle: false, values: [:]))
        XCTAssertEqual(log.rowCount, 1)
    }

    private func sampleDate() -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10,
                                                  minute: 59, second: 3, nanosecond: 120_000_000))!
    }
}
