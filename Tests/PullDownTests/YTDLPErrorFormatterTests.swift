import Foundation
import Testing
@testable import PullDown

struct YTDLPErrorFormatterTests {
    @Test func surfacesTheRealErrorLineInsteadOfTheExitStatus() {
        let stderr = """
        [youtube] 3Up6KwdMeqU: Downloading webpage
        ERROR: [youtube] 3Up6KwdMeqU: Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies for the authentication.
        """

        let message = YTDLPErrorFormatter.describe(exitCode: 1, stderr: stderr)

        #expect(message.contains("Sign in to confirm you're not a bot"))
        #expect(message.hasPrefix("ERROR:") == false)
        #expect(message.contains("exit status") == false)
    }

    @Test func fallsBackToTheLastOutputLinesWhenNoErrorMarkerExists() {
        let stderr = """
        WARNING: something happened
        Requested format is not available
        """

        let message = YTDLPErrorFormatter.describe(exitCode: 1, stderr: stderr)

        #expect(message.contains("Requested format is not available"))
    }

    @Test func fallsBackToExitStatusWhenNothingWasCaptured() {
        let message = YTDLPErrorFormatter.describe(exitCode: 2, stderr: "   \n  \n")

        #expect(message == "yt-dlp stopped with exit status 2.")
    }

    @Test func keepsTheMostRecentErrorLines() {
        let stderr = """
        ERROR: first problem
        ERROR: second problem
        ERROR: final problem
        """

        let message = YTDLPErrorFormatter.describe(exitCode: 1, stderr: stderr)

        #expect(message.contains("final problem"))
        #expect(message.contains("first problem") == false)
    }
}
