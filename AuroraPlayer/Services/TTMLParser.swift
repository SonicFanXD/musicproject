import Foundation

/// Parser for Apple Music timed-text lyrics.
struct TTMLParser {
    private static let namespace = "http://www.w3.org/ns/ttml"

    static func parse(_ text: String) -> SynchronizedLyrics? {
        guard text.range(of: "<tt", options: .caseInsensitive) != nil else { return nil }
        let delegate = ParserDelegate()
        guard let data = text.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), delegate.namespaceFound, !delegate.lines.isEmpty else {
            return nil
        }

        let lines = delegate.lines.map { entry in
            LyricLine(time: entry.begin, text: entry.text)
        }
        let words = delegate.words.map {
            LyricWord(time: $0.begin, text: $0.text, duration: $0.end.map { max(0, $0 - $0.begin) })
        }
        return SynchronizedLyrics(lines: lines, words: words, isWordByWord: !words.isEmpty)
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        struct Line {
            let begin: TimeInterval
            let end: TimeInterval?
            let text: String
        }

        struct Word {
            let begin: TimeInterval
            let end: TimeInterval?
            let text: String
        }

        var lines: [Line] = []
        var words: [Word] = []
        private var currentLine: (begin: TimeInterval, end: TimeInterval?, text: String)?
        private var currentWord: (begin: TimeInterval, end: TimeInterval?, text: String)?
        var namespaceFound = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if namespaceURI == TTMLParser.namespace {
                namespaceFound = true
            }
            let name = localName(elementName, qualifiedName: qName)
            guard namespaceFound || name == "tt" else { return }

            if name == "p" {
                currentLine = (timestamp(attributeDict["begin"]) ?? 0, timestamp(attributeDict["end"]), "")
            } else if name == "span", currentLine != nil {
                let begin = timestamp(attributeDict["begin"]) ?? currentLine?.begin ?? 0
                currentWord = (begin, timestamp(attributeDict["end"]), "")
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if currentWord != nil {
                currentWord?.text += string
            }
            if currentLine != nil {
                currentLine?.text += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(elementName, qualifiedName: qName)
            if name == "span", let word = currentWord {
                let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    words.append(Word(begin: word.begin, end: word.end, text: text))
                }
                currentWord = nil
            } else if name == "p", let line = currentLine {
                let text = line.text.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    lines.append(Line(begin: line.begin, end: line.end, text: text))
                }
                currentLine = nil
            }
        }

        private func localName(_ name: String, qualifiedName: String?) -> String {
            let value = qualifiedName ?? name
            return value.split(separator: ":").last.map(String.init) ?? value
        }

        private func timestamp(_ value: String?) -> TimeInterval? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            if value.hasSuffix("ms"), let milliseconds = Double(value.dropLast(2)) {
                return milliseconds / 1000
            }
            if value.hasSuffix("s"), let seconds = Double(value.dropLast()) {
                return seconds
            }
            let parts = value.split(separator: ":")
            if parts.count == 3,
               let hours = Double(parts[0]),
               let minutes = Double(parts[1]),
               let seconds = Double(parts[2]) {
                return hours * 3600 + minutes * 60 + seconds
            }
            if parts.count == 2,
               let minutes = Double(parts[0]),
               let seconds = Double(parts[1]) {
                return minutes * 60 + seconds
            }
            return nil
        }
    }
}
