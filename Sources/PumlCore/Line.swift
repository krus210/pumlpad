/// A line of text. Code counts lines from 0 (`index`); people, editors and PlantUML's error
/// reports count from 1 (`number`). One type for both keeps the two counts apart.
public struct Line: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public init(number: Int) {
        index = number - 1
    }

    public var number: Int {
        index + 1
    }

    public var description: String {
        "line \(number)"
    }

    public static func < (lhs: Line, rhs: Line) -> Bool {
        lhs.index < rhs.index
    }
}
