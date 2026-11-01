import Foundation

/// Hex helpers for the test vectors ("6E 41 6C 40", upper case, space separated).
public enum Hex {
    public static func bytes(_ text: String) -> [UInt8]? {
        let digits = Array(text.filter { !$0.isWhitespace })
        guard digits.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(digits.count / 2)
        var i = 0
        while i < digits.count {
            guard let byte = UInt8(String(digits[i...i + 1]), radix: 16) else { return nil }
            out.append(byte)
            i += 2
        }
        return out
    }

    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
