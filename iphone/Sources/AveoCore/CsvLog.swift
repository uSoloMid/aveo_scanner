import Foundation

public final class CsvLog {
    public static let header = "hora,evento,ralenti_alto,rpm,ralenti_deseado_rpm,iac_pasos,mariposa_relativa_pct,velocidad_kmh,mariposa_pct,refrigerante_c,voltaje_bateria_v"
    public static let valueKeys = [
        "rpm", "ralenti_deseado_rpm", "iac_pasos", "mariposa_relativa_pct",
        "velocidad_kmh", "mariposa_pct", "refrigerante_c", "voltaje_bateria_v"
    ]

    public let url: URL
    public private(set) var rowCount = 0
    private var handle: FileHandle?

    public init(directory: URL? = nil, at date: Date = Date()) throws {
        let folder = try directory ?? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = Self.formatter("yyyy-MM-dd_HH-mm-ss")
        url = folder.appendingPathComponent("aveo_\(formatter.string(from: date)).csv")
        // Never truncate a previous recording started within the same second.
        if FileManager.default.fileExists(atPath: url.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        try Data((Self.header + "\n").utf8).write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
        try handle?.synchronize()
    }

    public static func row(
        at date: Date, event: String, highIdle: Bool, values: [String: Double]
    ) -> String {
        let fields = [formatter("HH:mm:ss.SSS").string(from: date), escape(event), highIdle ? "1" : "0"]
        let numbers = valueKeys.map { key -> String in
            guard let value = values[key], value.isFinite else { return "" }
            return String(value)
        }
        return (fields + numbers).joined(separator: ",")
    }

    public func append(
        at date: Date = Date(), event: String = "", highIdle: Bool, values: [String: Double]
    ) throws {
        guard let handle else { throw CocoaError(.fileWriteUnknown) }
        let line = Self.row(at: date, event: event, highIdle: highIdle, values: values) + "\n"
        try handle.write(contentsOf: Data(line.utf8))
        try handle.synchronize()
        rowCount += 1
    }

    public func close() throws {
        guard let handle else { return }
        try handle.synchronize()
        try handle.close()
        self.handle = nil
    }

    deinit { try? handle?.close() }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
}
