import Foundation

/// How a file stores its text. The editor always works with "\n"; saving restores the file's own
/// encoding and line breaks, so opening and saving does not rewrite a file.
public struct TextFormat: Equatable, Sendable, CustomStringConvertible {
    public enum LineBreak: String, Sendable {
        case lf = "\n"
        case crlf = "\r\n"
    }

    public var encoding: String.Encoding
    public var lineBreak: LineBreak
    /// Whether the file starts with a byte order mark: some Windows tools write one in UTF-8,
    /// and UTF-16 files carry one to tell their byte order.
    public var hasByteOrderMark: Bool

    public static let standard = TextFormat(encoding: .utf8)

    public static let koi8R = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue))
    )

    /// The encodings File › Reopen with Encoding and Convert to Encoding offer.
    public static let encodings: [String.Encoding] = [
        .utf8, .utf16LittleEndian, .utf16BigEndian, .windowsCP1251, koi8R, .windowsCP1252, .isoLatin1, .macOSRoman,
    ]

    /// UTF-16 gets a byte order mark unless told otherwise: without one other programs guess its byte order.
    public init(encoding: String.Encoding, lineBreak: LineBreak = .lf, hasByteOrderMark: Bool? = nil) {
        self.encoding = encoding
        self.lineBreak = lineBreak
        self.hasByteOrderMark = hasByteOrderMark ?? (encoding == .utf16LittleEndian || encoding == .utf16BigEndian)
    }

    public static func name(of encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .windowsCP1251: "Windows-1251"
        case .windowsCP1252: "Windows-1252"
        case .isoLatin1: "ISO Latin 1"
        case .macOSRoman: "Mac OS Roman"
        case koi8R: "KOI8-R"
        default: String.localizedName(of: encoding)
        }
    }

    public var description: String {
        let byteOrderMark = hasByteOrderMark && encoding == .utf8 ? " with BOM" : ""
        return "\(Self.name(of: encoding))\(byteOrderMark) · \(lineBreak == .crlf ? "CRLF" : "LF")"
    }

    /// Whether saving `text` in this format keeps every character.
    public func canStore(_ text: String) -> Bool {
        text.canBeConverted(to: encoding)
    }

    /// Fails rather than dropping characters the file's encoding cannot hold.
    public func encode(_ text: String) throws -> Data {
        // Text pasted from elsewhere may bring its own "\r\n".
        var text = text.replacingOccurrences(of: "\r\n", with: "\n")
        if lineBreak == .crlf { text = text.replacingOccurrences(of: "\n", with: "\r\n") }
        guard let body = text.data(using: encoding, allowLossyConversion: false) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding, userInfo: [
                NSLocalizedDescriptionKey: "The text has characters that \(Self.name(of: encoding)) cannot store.",
            ])
        }
        let mark = hasByteOrderMark ? Self.byteOrderMarks.first { $0.encoding == encoding }?.bytes ?? [] : []
        return Data(mark) + body
    }

    // MARK: Reading

    /// Text read from a file.
    public struct Decoded: Sendable {
        public var text: String
        public var format: TextFormat
        /// Bytes that `format.encoding` could not read and that became "�"; saving writes "�".
        public var replacedBytes: Int
    }

    /// Reads a file, working out its encoding: a byte order mark; UTF-16 without one (text in
    /// UTF-16 is full of zero bytes); UTF-8, also with a few broken bytes; otherwise a single-byte
    /// encoding: Windows-1251 when the bytes above 127 come in runs, as Cyrillic words do, and
    /// Windows-1252 (Latin 1) when they stand alone, as accented letters do. Lines keep the
    /// line break most of them use.
    public static func decode(_ data: Data) throws -> Decoded {
        let bytes = [UInt8](data)
        if let mark = byteOrderMarks.first(where: { bytes.starts(with: $0.bytes) }) {
            return try decode(bytes, as: mark.encoding, skipping: mark.bytes.count)
        }
        if bytes.contains(0) {
            guard let encoding = utf16ByteOrder(of: bytes) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The file is not text."])
            }
            return try decode(bytes, as: encoding, skipping: 0)
        }
        let utf8 = UTF8Check(bytes[...])
        if utf8.invalidBytes < max(1, utf8.multibyteCharacters) {
            return try decode(bytes, as: .utf8, skipping: 0)
        }
        return try decode(bytes, as: looksCyrillic(bytes) ? .windowsCP1251 : .windowsCP1252, skipping: 0)
    }

    /// Reads a file as `encoding`, for File › Reopen with Encoding.
    public static func decode(_ data: Data, as encoding: String.Encoding) throws -> Decoded {
        let bytes = [UInt8](data)
        let mark = byteOrderMarks.first { $0.encoding == encoding && bytes.starts(with: $0.bytes) }
        return try decode(bytes, as: encoding, skipping: mark?.bytes.count ?? 0)
    }

    private static let byteOrderMarks: [(encoding: String.Encoding, bytes: [UInt8])] = [
        (.utf8, [0xEF, 0xBB, 0xBF]),
        (.utf16LittleEndian, [0xFF, 0xFE]),
        (.utf16BigEndian, [0xFE, 0xFF]),
    ]

    private static func decode(_ bytes: [UInt8], as encoding: String.Encoding, skipping byteOrderMark: Int) throws -> Decoded {
        let body = bytes[byteOrderMark...]
        let text: String
        var replaced = 0
        switch encoding {
        case .utf8:
            replaced = UTF8Check(body).invalidBytes
            text = String(decoding: body, as: UTF8.self)
        case .utf16LittleEndian, .utf16BigEndian:
            guard let decoded = String(bytes: body, encoding: encoding) else {
                throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [
                    NSLocalizedDescriptionKey: "The file is not in \(name(of: encoding)).",
                ])
            }
            text = decoded
        default:
            (text, replaced) = decodeSingleByte(body, encoding)
        }
        let (normalized, lineBreak) = normalizingLineBreaks(text)
        let format = TextFormat(encoding: encoding, lineBreak: lineBreak, hasByteOrderMark: byteOrderMark > 0)
        return Decoded(text: normalized, format: format, replacedBytes: replaced)
    }

    /// Byte by byte through a table, so a byte the encoding leaves undefined (0x98 in
    /// Windows-1251) becomes "�" instead of failing the whole file.
    private static func decodeSingleByte(_ bytes: ArraySlice<UInt8>, _ encoding: String.Encoding) -> (String, replaced: Int) {
        var table = [UInt16](repeating: 0xFFFD, count: 256)
        for byte in 0...255 {
            if let character = String(bytes: [UInt8(byte)], encoding: encoding)?.utf16, character.count == 1 {
                table[byte] = character[character.startIndex]
            }
        }
        var replaced = 0
        let units = bytes.map { byte in
            let unit = table[Int(byte)]
            if unit == 0xFFFD { replaced += 1 }
            return unit
        }
        return (String(decoding: units, as: UTF16.self), replaced)
    }

    /// UTF-16 without a byte order mark: ASCII characters leave a zero in every other byte.
    private static func utf16ByteOrder(of bytes: [UInt8]) -> String.Encoding? {
        let sample = bytes.prefix(4096)
        var zerosAtEven = 0
        var zerosAtOdd = 0
        for (offset, byte) in sample.enumerated() where byte == 0 {
            if offset.isMultiple(of: 2) { zerosAtEven += 1 } else { zerosAtOdd += 1 }
        }
        let pairs = sample.count / 2
        if zerosAtOdd * 4 > pairs, zerosAtEven * 4 < zerosAtOdd { return .utf16LittleEndian }
        if zerosAtEven * 4 > pairs, zerosAtOdd * 4 < zerosAtEven { return .utf16BigEndian }
        return nil
    }

    /// Cyrillic letters are all above 127 in single-byte encodings and come in words, while
    /// Latin text has an accented letter here and there.
    private static func looksCyrillic(_ bytes: [UInt8]) -> Bool {
        var high = 0
        var inRuns = 0
        for index in bytes.indices where bytes[index] >= 0x80 {
            high += 1
            if (index > 0 && bytes[index - 1] >= 0x80) || (index + 1 < bytes.count && bytes[index + 1] >= 0x80) {
                inRuns += 1
            }
        }
        return inRuns * 2 > high
    }

    /// "\r\n" becomes "\n"; the format keeps the line break most lines use.
    private static func normalizingLineBreaks(_ text: String) -> (String, LineBreak) {
        var crlf = 0
        var lf = 0
        var afterCR = false
        for unit in text.utf16 {
            if unit == 0x0A {
                if afterCR { crlf += 1 } else { lf += 1 }
            }
            afterCR = unit == 0x0D
        }
        let normalized = crlf > 0 ? text.replacingOccurrences(of: "\r\n", with: "\n") : text
        return (normalized, crlf > lf ? .crlf : .lf)
    }
}

/// Counts valid multi-byte UTF-8 characters and bytes that belong to none.
struct UTF8Check {
    private(set) var multibyteCharacters = 0
    private(set) var invalidBytes = 0

    init(_ bytes: ArraySlice<UInt8>) {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let lead = bytes[index]
            if lead < 0x80 {
                index += 1
                continue
            }
            // Allowed range of the second byte, which rules out overlong forms and surrogates.
            let length: Int
            var second: ClosedRange<UInt8> = 0x80...0xBF
            switch lead {
            case 0xC2...0xDF: length = 2
            case 0xE0: length = 3; second = 0xA0...0xBF
            case 0xE1...0xEC, 0xEE...0xEF: length = 3
            case 0xED: length = 3; second = 0x80...0x9F
            case 0xF0: length = 4; second = 0x90...0xBF
            case 0xF1...0xF3: length = 4
            case 0xF4: length = 4; second = 0x80...0x8F
            default: length = 0
            }
            var valid = length > 0 && index + length <= bytes.endIndex && second.contains(bytes[index + 1])
            if valid, length > 2 {
                valid = bytes[(index + 2)..<(index + length)].allSatisfy { (0x80...0xBF).contains($0) }
            }
            if valid {
                multibyteCharacters += 1
                index += length
            } else {
                invalidBytes += 1
                index += 1
            }
        }
    }
}
