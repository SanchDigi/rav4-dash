import Foundation

/// Trouble-code scan result.
struct DTCReport: Equatable {
    var milOn: Bool
    var stored: [String]
    var pending: [String]
    var date: Date
}

/// Turns raw ELM327 text replies into bytes and values.
/// Assumes echo, spaces and headers are off (ATE0, ATS0, ATH0).
enum ELMParser {
    static func hex2(_ value: UInt8) -> String {
        let s = String(value, radix: 16, uppercase: true)
        return value < 16 ? "0" + s : s
    }

    /// Reply lines without the prompt, "SEARCHING..." or blank lines.
    static func lines(_ raw: String) -> [String] {
        raw.replacingOccurrences(of: ">", with: "")
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.uppercased().hasPrefix("SEARCHING") }
    }

    static func isError(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        let markers = ["NO DATA", "UNABLE TO CONNECT", "CAN ERROR", "BUS INIT", "BUS ERROR", "STOPPED", "ERROR", "?"]
        return markers.contains { upper.contains($0) }
    }

    /// Bytes from one line, ignoring a multi-frame prefix like "0:". Nil if it isn't hex.
    static func bytes(fromLine line: String) -> [UInt8]? {
        var s = line.uppercased()
        if let colon = s.firstIndex(of: ":") {
            s = String(s[s.index(after: colon)...])
        }
        s = s.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty, s.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }

    /// Data bytes for a mode 01 reply, one entry per ECU that answered.
    static func allMode01Data(_ raw: String, pid: UInt8) -> [[UInt8]] {
        lines(raw).compactMap { bytes(fromLine: $0) }.compactMap { b in
            guard b.count >= 3, b[0] == 0x41, b[1] == pid else { return nil }
            return Array(b[2...])
        }
    }

    static func mode01Data(_ raw: String, pid: UInt8) -> [UInt8]? {
        allMode01Data(raw, pid: pid).first
    }

    /// Decodes a "PIDs supported" bitmap reply (PID 00, 20, 40...).
    static func supportedPIDs(_ raw: String, base: UInt8) -> Set<UInt8> {
        var set = Set<UInt8>()
        for data in allMode01Data(raw, pid: base) where data.count >= 4 {
            for byteIndex in 0..<4 {
                for bit in 0..<8 where data[byteIndex] & (UInt8(0x80) >> UInt8(bit)) != 0 {
                    set.insert(base &+ UInt8(byteIndex * 8 + bit + 1))
                }
            }
        }
        return set
    }

    /// Trouble codes from a mode 03 (responseByte 0x43) or mode 07 (0x47) reply.
    static func troubleCodes(_ raw: String, responseByte: UInt8) -> [String] {
        // Each message is the bytes from one ECU. CAN multi-frame replies come as "0: ...", "1: ...".
        var messages: [(bytes: [UInt8], multiFrame: Bool)] = []
        for line in lines(raw) {
            if let colon = line.firstIndex(of: ":") {
                let frame = line[..<colon].trimmingCharacters(in: .whitespaces)
                guard let b = bytes(fromLine: line) else { continue }
                if frame == "0" || messages.isEmpty {
                    messages.append((b, true))
                } else {
                    messages[messages.count - 1].bytes += b
                }
            } else if let b = bytes(fromLine: line) {
                messages.append((b, false))
            }
        }

        var codes: [String] = []
        for message in messages {
            guard let first = message.bytes.first, first == responseByte else { continue }
            var payload = Array(message.bytes.dropFirst())
            // On CAN the first byte is the number of codes.
            if message.multiFrame || payload.count % 2 == 1 {
                guard let count = payload.first else { continue }
                payload = Array(payload.dropFirst().prefix(Int(count) * 2))
            }
            var i = 0
            while i + 1 < payload.count {
                let a = payload[i], b = payload[i + 1]
                i += 2
                if a == 0 && b == 0 { continue }
                codes.append(decodeDTC(a, b))
            }
        }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    static func decodeDTC(_ a: UInt8, _ b: UInt8) -> String {
        let letters = ["P", "C", "B", "U"]
        let letter = letters[Int(a >> 6)]
        let second = String((a >> 4) & 0x03)
        let third = String(a & 0x0F, radix: 16, uppercase: true)
        return letter + second + third + hex2(b)
    }
}
