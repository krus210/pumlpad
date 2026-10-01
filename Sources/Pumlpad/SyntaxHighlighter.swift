import AppKit

/// Colours PlantUML source with regular expressions.
///
/// Colours are temporary attributes of the layout manager: they are not saved, do not enter undo,
/// and changing them does not re-layout text. After an edit only the edited lines are recoloured;
/// block comments `/' … '/` span lines, so an edit that changes where one starts or ends
/// recolours everything.
@MainActor
final class SyntaxHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let color: NSColor
    }

    /// Rules that never cross a line break. Later rules win: comments and strings override the rest.
    private let lineRules: [Rule]
    private let blockComment = SyntaxHighlighter.regex(#"/'[\s\S]*?'/"#)
    private let commentColor = NSColor.secondaryLabelColor
    /// Block comments found by the last recolouring.
    private var blockComments: [NSRange] = []

    init() {
        let statements = (Keywords.types + Keywords.keywords.filter { !$0.hasPrefix("@") })
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")

        func rule(_ pattern: String, _ color: NSColor, _ options: NSRegularExpression.Options = []) -> Rule {
            Rule(regex: Self.regex(pattern, options), color: color)
        }

        lineRules = [
            // Statement keywords at the start of a line: participant, class, alt, note, skinparam…
            rule(#"^[ \t]*(?:\#(statements))\b"#, .systemPink, [.anchorsMatchLines, .caseInsensitive]),
            rule(#"\bas\b"#, .systemPink),
            // Arrows with a head on the right (->, -->, ..>, -[#red]->, --*), on the left (<-, <|--),
            // or plain lines of two or more (--, ..); a single "-" or "=" in text is not an arrow.
            rule(#"(?<![\w"])(?:(?:<\|?|<<|[o*+x#])?[-.=~]+(?:\[[^\]\n]*\])?(?:(?:up|down|left|right|u|d|l|r)[-.=~]*)?(?:\|?>>?|[o*+x#])|(?:<\|?|<<)[-.=~]+(?:\[[^\]\n]*\])?[-.=~]*|[-.=~]{2,})(?![\w"])"#, .systemTeal),
            // Procedure and macro calls: Person(…), Rel(…), $myProc(…)
            rule(#"\$?\b[A-Za-z_][A-Za-z0-9_]*(?=\()"#, .systemBlue),
            rule(#"\$[A-Za-z_][A-Za-z0-9_]*"#, .systemBlue),
            rule(#"<<[^>\n]+>>"#, .systemIndigo),
            rule(#"#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{3}|[A-Za-z]+)\b"#, .systemBrown),
            rule(#"^[ \t]*![A-Za-z_]+"#, .systemOrange, .anchorsMatchLines),
            rule(#""[^"\n]*""#, .systemRed),
            rule(#"^[ \t]*@(?:start|end)[a-z]+\b.*$"#, .systemPurple, [.anchorsMatchLines, .caseInsensitive]),
            rule(#"^[ \t]*'.*$"#, .secondaryLabelColor, .anchorsMatchLines),
        ]
    }

    /// Recolours the lines of `edited`, the edit's range in the new text with `delta` its change
    /// in length, or the whole text when `edited` is `nil` or the edit moved a comment boundary.
    func highlight(_ layoutManager: NSLayoutManager, text: NSString, edited: NSRange?, delta: Int) {
        let whole = NSRange(location: 0, length: text.length)
        let string = text as String
        let comments = text.range(of: "/'", options: .literal).location == NSNotFound
            ? [] : blockComment.matches(in: string, range: whole).map(\.range)
        var range = whole
        if let edited, comments == Self.moved(blockComments, by: edited, delta: delta) {
            let location = min(edited.location, text.length)
            range = text.lineRange(for: NSRange(location: location, length: min(edited.length, text.length - location)))
        }
        blockComments = comments

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        for rule in lineRules {
            rule.regex.enumerateMatches(in: string, range: range) { match, _, _ in
                guard let match, match.range.length > 0 else { return }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: rule.color, forCharacterRange: match.range)
            }
        }
        for comment in comments {
            let overlap = NSIntersectionRange(comment, range)
            guard overlap.length > 0 else { continue }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: commentColor, forCharacterRange: overlap)
        }
    }

    /// Where `comments` end up after an edit that leaves their delimiters alone: those before
    /// it stay, those after it shift, one around it grows or shrinks. A comment whose delimiter
    /// the edit touches gets an impossible range, so the lists differ.
    private static func moved(_ comments: [NSRange], by edited: NSRange, delta: Int) -> [NSRange] {
        // Where the replaced text ended before the edit.
        let oldEnd = NSMaxRange(edited) - delta
        return comments.map { comment in
            if NSMaxRange(comment) <= edited.location { return comment }
            if comment.location >= oldEnd { return NSRange(location: comment.location + delta, length: comment.length) }
            if comment.location + 2 <= edited.location, oldEnd <= NSMaxRange(comment) - 2 {
                return NSRange(location: comment.location, length: comment.length + delta)
            }
            return NSRange(location: NSNotFound, length: 0)
        }
    }

    /// Patterns are literals in this file; a typo should fail loudly during development.
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }
}
