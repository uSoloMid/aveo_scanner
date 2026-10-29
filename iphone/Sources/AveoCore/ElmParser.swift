import Foundation

public enum ElmParser {
    private static func cleaned(_ raw: String) -> String? {
        let upper = raw.uppercased()
        // Check errors before discarding BUS INIT lines: they can contain ERROR.
        let compact = upper.filter { !$0.isWhitespace && $0 != ">" }
        guard !["NODATA", "?", "ERROR", "UNABLETOCONNECT", "STOPPED", "7F22"]
            .contains(where: { compact.contains($0) }) else { return nil }
        return upper.components(separatedBy: .newlines).map { line in
            var text = line.replacingOccurrences(of: "SEARCHING...", with: "")
            if let bus = text.range(of: "BUS INIT:") {
                // Some adapters put the reply on the same line after the ellipsis.
                let suffix = text[bus.upperBound...]
                if let end = suffix.range(of: "...") {
                    text = String(text[..<bus.lowerBound]) + String(suffix[end.upperBound...])
                } else {
                    return ""
                }
            }
            return text.filter { !$0.isWhitespace && $0 != ">" }
        }.joined()
    }

    public static func bytes(_ raw: String, expectedPrefix: String) -> [UInt8]? {
        guard let text = cleaned(raw),
              let range = text.range(of: expectedPrefix.uppercased()) else { return nil }
        let payload = text[range.upperBound...]
        var result: [UInt8] = []
        var index = payload.startIndex
        while index < payload.endIndex {
            let next = payload.index(index, offsetBy: 2, limitedBy: payload.endIndex)
            guard let next, let byte = UInt8(payload[index..<next], radix: 16) else { break }
            result.append(byte)
            index = next
        }
        return result.isEmpty ? nil : result
    }

    public static func value(_ raw: String, command: String) -> Double? {
        let command = command.uppercased().replacingOccurrences(of: " ", with: "")
        if command == "ATRV" {
            guard let text = cleaned(raw), let v = text.lastIndex(of: "V") else { return nil }
            let digits = text[..<v].reversed().prefix { $0.isNumber || $0 == "." }
            return Double(String(digits.reversed())).flatMap { $0.isFinite ? $0 : nil }
        }
        let prefixes = [
            "010C": "410C", "221192": "621192", "221172": "621172",
            "0145": "4145", "010D": "410D", "0111": "4111", "0105": "4105"
        ]
        guard let prefix = prefixes[command],
              let payload = Self.bytes(raw, expectedPrefix: prefix), let first = payload.first else { return nil }
        let a = Double(first)
        switch command {
        case "010C":
            guard payload.count >= 2 else { return nil }
            return (a * 256 + Double(payload[1])) / 4
        case "221192": return a * 12.5
        case "0145", "0111": return a * 100 / 255
        case "0105": return a - 40
        default: return a
        }
    }
}
