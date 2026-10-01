import Foundation
import Testing
@testable import PumlCore

@Suite struct TextFormatTests {
    @Test func roundTripsUTF8WithLF() throws {
        let data = Data("@startuml\nА -> Б\n@enduml\n".utf8)
        let decoded = try TextFormat.decode(data)
        #expect(decoded.format == .standard)
        #expect(decoded.replacedBytes == 0)
        #expect(try decoded.format.encode(decoded.text) == data)
    }

    @Test func keepsCRLFOnSaveButShowsLFInTheEditor() throws {
        let data = Data("@startuml\r\nA -> B\r\n@enduml\r\n".utf8)
        let decoded = try TextFormat.decode(data)
        #expect(decoded.text == "@startuml\nA -> B\n@enduml\n")
        #expect(decoded.format.lineBreak == .crlf)
        // A line typed in the editor gets the file's line break too.
        #expect(try decoded.format.encode(decoded.text + "B -> A\n") == Data("@startuml\r\nA -> B\r\n@enduml\r\nB -> A\r\n".utf8))
    }

    @Test func keepsTheLineBreakMostLinesUse() throws {
        let decoded = try TextFormat.decode(Data("@startuml\r\nA -> B\nB -> A\n@enduml\n".utf8))
        #expect(decoded.format.lineBreak == .lf)
        #expect(decoded.text == "@startuml\nA -> B\nB -> A\n@enduml\n")
    }

    @Test func keepsWindows1251() throws {
        let data = try #require("@startuml\nАлиса -> Боб : привет\n@enduml\n".data(using: .windowsCP1251))
        let decoded = try TextFormat.decode(data)
        #expect(decoded.text.contains("Алиса"))
        #expect(decoded.format.encoding == .windowsCP1251)
        #expect(try decoded.format.encode(decoded.text) == data)
        #expect(decoded.format.description == "Windows-1251 · LF")
    }

    /// Accented letters stand alone between ASCII ones; Cyrillic letters come in words.
    @Test func tellsLatin1FromWindows1251() throws {
        let data = try #require("@startuml\nRené -> Zoë : Grüße, ça va?\n@enduml\n".data(using: .windowsCP1252))
        let decoded = try TextFormat.decode(data)
        #expect(decoded.format.encoding == .windowsCP1252)
        #expect(decoded.text.contains("René -> Zoë : Grüße, ça va?"))
        #expect(try decoded.format.encode(decoded.text) == data)
    }

    @Test func readsUTF16WithAndWithoutByteOrderMark() throws {
        let text = "@startuml\nАлиса -> Bob\n@enduml\n"
        let littleEndian = Data([0xFF, 0xFE]) + (text.data(using: .utf16LittleEndian) ?? Data())
        let marked = try TextFormat.decode(littleEndian)
        #expect(marked.text == text)
        #expect(marked.format == TextFormat(encoding: .utf16LittleEndian, hasByteOrderMark: true))
        #expect(try marked.format.encode(marked.text) == littleEndian)

        let bigEndian = try #require(text.data(using: .utf16BigEndian))
        let unmarked = try TextFormat.decode(bigEndian)
        #expect(unmarked.text == text)
        #expect(unmarked.format.encoding == .utf16BigEndian)
        #expect(try unmarked.format.encode(unmarked.text) == bigEndian)
    }

    /// One broken byte in a UTF-8 file is shown as "�" instead of turning the file into Windows-1251.
    @Test func readsUTF8WithABrokenByte() throws {
        let data = Data("@startuml\nАлиса -> Боб\n".utf8) + Data([0x98]) + Data("\n@enduml\n".utf8)
        let decoded = try TextFormat.decode(data)
        #expect(decoded.format.encoding == .utf8)
        #expect(decoded.replacedBytes == 1)
        #expect(decoded.text.contains("Алиса -> Боб\n\u{FFFD}\n"))
    }

    /// 0x98 has no character in Windows-1251: it becomes "�" instead of failing the whole file.
    @Test func readsWindows1251WithAnUndefinedByte() throws {
        let data = (try #require("Алиса -> Боб : привет ".data(using: .windowsCP1251))) + Data([0x98])
        let decoded = try TextFormat.decode(data)
        #expect(decoded.format.encoding == .windowsCP1251)
        #expect(decoded.replacedBytes == 1)
        #expect(decoded.text == "Алиса -> Боб : привет \u{FFFD}")
    }

    @Test func refusesBinaryFiles() {
        #expect(throws: CocoaError.self) { try TextFormat.decode(Data([0x00, 0x00, 0x13, 0x37, 0x00, 0x00, 0x00, 0x01])) }
    }

    @Test func reopensWithAChosenEncoding() throws {
        let data = try #require("Алиса".data(using: .windowsCP1251))
        #expect(try TextFormat.decode(data, as: TextFormat.koi8R).format.encoding == TextFormat.koi8R)
        #expect(try TextFormat.decode(data, as: .windowsCP1251).text == "Алиса")
    }

    @Test func refusesToDropCharactersTheEncodingCannotStore() throws {
        let format = TextFormat(encoding: .windowsCP1251)
        #expect(!format.canStore("emoji 👋"))
        #expect(throws: CocoaError.self) { try format.encode("emoji 👋") }
    }

    @Test func keepsTheByteOrderMark() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("@startuml\n@enduml\n".utf8)
        let decoded = try TextFormat.decode(data)
        #expect(!decoded.text.hasPrefix("\u{FEFF}"))
        #expect(decoded.format.hasByteOrderMark)
        #expect(try decoded.format.encode(decoded.text) == data)
    }
}
