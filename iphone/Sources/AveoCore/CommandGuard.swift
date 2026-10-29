import Foundation

public enum CommandGuard {
    /// Reject control characters and chained commands before touching the adapter.
    /// Whitespace normalization is limited to ASCII spaces inside hex requests.
    public static func isAllowed(_ cmd: String) -> Bool {
        let command = cmd.uppercased()
        let adapterCommands: Set<String> = [
            "ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0", "ATRV", "ATDPN"
        ]
        if adapterCommands.contains(command) { return true }
        guard command.unicodeScalars.allSatisfy({
            "0123456789ABCDEF ".unicodeScalars.contains($0)
        }) else { return false }
        let hex = command.replacingOccurrences(of: " ", with: "")
        return hex.count >= 2 && hex.count.isMultiple(of: 2)
            && ["01", "09", "22"].contains(where: { hex.hasPrefix($0) })
    }
}
