import Foundation

/// Turns a raw yt-dlp exit code and captured standard-error stream into a
/// message a human can actually act on, instead of the opaque
/// "yt-dlp stopped with exit status 1".
enum YTDLPErrorFormatter {
    static func describe(exitCode: Int32, stderr: String) -> String {
        let lines = stderr
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }

        // yt-dlp prints the actionable reason on lines that start with ERROR:.
        let errorLines = lines.filter { line in
            line.range(of: #"^(ERROR|error)[:\s]"#, options: .regularExpression) != nil
                || line.localizedCaseInsensitiveContains("ERROR:")
        }

        let chosen = errorLines.isEmpty ? Array(lines.suffix(3)) : Array(errorLines.suffix(2))
        guard chosen.isEmpty == false else {
            return "yt-dlp stopped with exit status \(exitCode)."
        }

        return chosen
            .map { cleaned($0) }
            .joined(separator: "\n")
    }

    private static func cleaned(_ line: String) -> String {
        // Drop the "ERROR: " prefix so the message reads naturally in an alert.
        if let range = line.range(of: #"^ERROR:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            return String(line[range.upperBound...])
        }
        return line
    }
}
