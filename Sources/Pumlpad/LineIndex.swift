import Foundation
import PumlCore

/// Where each line of a text starts, so that line arithmetic is a binary search instead of a
/// scan of the text. The editor builds it once per edit and shares it with the caret, the
/// error marker and the line-number ruler. Lines end where NSString ends them: "\n", "\r\n",
/// "\r", U+0085, U+2028 and U+2029.
struct LineIndex {
    /// UTF-16 offsets of the line starts; text ending with a line break has an empty last line.
    private var starts: [Int] = [0]
    let length: Int

    init(_ string: NSString) {
        length = string.length
        var buffer = [unichar](repeating: 0, count: 4096)
        var offset = 0
        var afterCR = false
        while offset < length {
            let count = min(buffer.count, length - offset)
            string.getCharacters(&buffer, range: NSRange(location: offset, length: count))
            for index in 0..<count {
                let unit = buffer[index]
                switch unit {
                case 0x0A:
                    // "\r\n" is one line break: the line starts after the "\n", not between the two.
                    if afterCR { starts[starts.count - 1] = offset + index + 1 } else { starts.append(offset + index + 1) }
                case 0x0D, 0x85, 0x2028, 0x2029:
                    starts.append(offset + index + 1)
                default:
                    break
                }
                afterCR = unit == 0x0D
            }
            offset += count
        }
    }

    var lineCount: Int {
        starts.count
    }

    /// The line holding the character at `location`; the end of the text belongs to the last line.
    func line(at location: Int) -> Line {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= location { low = middle } else { high = middle - 1 }
        }
        return Line(index: low)
    }

    /// Characters of `line` with its line break, or `nil` past the last line.
    func range(of line: Line) -> NSRange? {
        guard starts.indices.contains(line.index) else { return nil }
        let start = starts[line.index]
        let end = line.index + 1 < starts.count ? starts[line.index + 1] : length
        return NSRange(location: start, length: end - start)
    }
}
