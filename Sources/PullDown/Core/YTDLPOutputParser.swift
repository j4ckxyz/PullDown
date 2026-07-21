import Foundation

struct ParsedYTDLPOutput: Equatable, Sendable {
    var progress: Double?
    var speed: String?
    var eta: String?
    var outputPath: String?
    var isPostProcessing = false
}

enum YTDLPOutputParser {
    static func parse(_ line: String) -> ParsedYTDLPOutput? {
        var result = ParsedYTDLPOutput()

        if let percent = firstCapture(in: line, pattern: #"([0-9]+(?:\.[0-9]+)?)%"#).flatMap(Double.init) {
            result.progress = min(max(percent / 100, 0), 1)
        }
        result.speed = firstCapture(in: line, pattern: #"\bat\s+([^\s]+)"#)
        result.eta = firstCapture(in: line, pattern: #"\bETA\s+([^\s]+)"#)

        if let quoted = firstCapture(in: line, pattern: #"(?:Destination:|Merging formats into)\s+\"([^\"]+)\""#) {
            result.outputPath = quoted
        } else if let unquoted = firstCapture(in: line, pattern: #"Destination:\s+(.+)$"#) {
            result.outputPath = unquoted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        result.isPostProcessing = line.contains("[Merger]")
            || line.contains("[ExtractAudio]")
            || line.contains("[Metadata]")
            || line.contains("[EmbedSubtitle]")
            || line.contains("[ThumbnailsConvertor]")

        guard
            result.progress != nil
                || result.speed != nil
                || result.eta != nil
                || result.outputPath != nil
                || result.isPostProcessing
        else { return nil }
        return result
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
