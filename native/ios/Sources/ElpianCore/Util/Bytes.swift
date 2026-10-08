import Foundation

/**
 * UTF-8 and base64 helpers with exactly the TypeScript core's behaviour
 * (util/bytes.ts): lone surrogates encode as U+FFFD, malformed UTF-8 decodes
 * to U+FFFD (`allowMalformed`), base64 decoding accepts the URL-safe
 * alphabet and tolerates whitespace and padding.
 */
public enum Bytes {
    public static func utf8Encode(_ text: String) -> [UInt8] {
        // Swift strings are always well-formed, so this is the plain encoding.
        Array(text.utf8)
    }

    /** Decode UTF-8, replacing malformed sequences with U+FFFD. */
    public static func utf8Decode(_ bytes: [UInt8]) -> String {
        var out = String.UnicodeScalarView()
        var i = 0
        let n = bytes.count
        func push(_ cp: UInt32) { out.append(Unicode.Scalar(cp) ?? "\u{FFFD}") }
        while i < n {
            let b = bytes[i]
            if b < 0x80 {
                push(UInt32(b))
                i += 1
                continue
            }
            var need = 0
            var cp: UInt32 = 0
            var minimum: UInt32 = 0
            if b >= 0xC2 && b <= 0xDF {
                need = 1; cp = UInt32(b & 0x1F); minimum = 0x80
            } else if b >= 0xE0 && b <= 0xEF {
                need = 2; cp = UInt32(b & 0x0F); minimum = 0x800
            } else if b >= 0xF0 && b <= 0xF4 {
                need = 3; cp = UInt32(b & 0x07); minimum = 0x10000
            } else {
                push(0xFFFD)
                i += 1
                continue
            }
            var j = 1
            while j <= need {
                if i + j >= n { break }
                let c = bytes[i + j]
                if (c & 0xC0) != 0x80 { break }
                cp = (cp << 6) | UInt32(c & 0x3F)
                j += 1
            }
            if j <= need || cp < minimum || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
                push(0xFFFD)
                i += max(1, j)
                continue
            }
            push(cp)
            i += need + 1
        }
        return String(out)
    }

    private static let B64: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let B64_INDEX: [UInt8: Int] = {
        var m: [UInt8: Int] = [:]
        for (i, c) in B64.enumerated() { m[c] = i }
        m[UInt8(ascii: "-")] = 62
        m[UInt8(ascii: "_")] = 63
        return m
    }()

    public static func base64Encode(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity((bytes.count + 2) / 3 * 4)
        var i = 0
        while i + 2 < bytes.count {
            let v = (Int(bytes[i]) << 16) | (Int(bytes[i + 1]) << 8) | Int(bytes[i + 2])
            out += [B64[v >> 18], B64[(v >> 12) & 63], B64[(v >> 6) & 63], B64[v & 63]]
            i += 3
        }
        let rest = bytes.count - i
        if rest == 1 {
            let v = Int(bytes[i]) << 16
            out += [B64[v >> 18], B64[(v >> 12) & 63], 61, 61]
        } else if rest == 2 {
            let v = (Int(bytes[i]) << 16) | (Int(bytes[i + 1]) << 8)
            out += [B64[v >> 18], B64[(v >> 12) & 63], B64[(v >> 6) & 63], 61]
        }
        return String(decoding: out, as: UTF8.self)
    }

    public struct InvalidBase64: Error, CustomStringConvertible {
        public let character: String
        public var description: String { "invalid base64 character \"\(character)\"" }
    }

    /** Decode standard or URL-safe base64 (whitespace and padding tolerated). */
    public static func base64Decode(_ text: String) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(text.utf8.count * 3 / 4)
        var acc = 0
        var bits = 0
        for scalar in text.unicodeScalars {
            if scalar == "=" || scalar.properties.isWhitespace { continue }
            guard scalar.isASCII, let v = B64_INDEX[UInt8(scalar.value)] else {
                throw InvalidBase64(character: String(scalar))
            }
            acc = ((acc << 6) | v) & 0xFFFFFF
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((acc >> bits) & 0xFF))
            }
        }
        return out
    }
}
