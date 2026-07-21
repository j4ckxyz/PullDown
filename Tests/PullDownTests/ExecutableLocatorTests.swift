import Foundation
import Testing
@testable import PullDown

private struct StubExecutableChecker: ExecutableChecking {
    let executablePaths: Set<String>

    func isExecutable(at url: URL) -> Bool {
        executablePaths.contains(url.path)
    }
}

struct ExecutableLocatorTests {
    @Test func findsExecutableFromFinderIndependentHomebrewPath() {
        let expected = "/opt/homebrew/bin/yt-dlp"
        let locator = ExecutableLocator(
            homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true),
            environmentPath: "/usr/bin:/bin",
            managedBinDirectory: URL(fileURLWithPath: "/Users/test/Library/Application Support/PullDown/bin", isDirectory: true),
            checker: StubExecutableChecker(executablePaths: [expected])
        )

        #expect(locator.locate(named: "yt-dlp")?.path == expected)
    }

    @Test func removesDuplicateSearchDirectories() {
        let locator = ExecutableLocator(
            homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true),
            environmentPath: "/opt/homebrew/bin:/opt/homebrew/bin:/usr/local/bin",
            managedBinDirectory: URL(fileURLWithPath: "/managed", isDirectory: true),
            checker: StubExecutableChecker(executablePaths: [])
        )
        let paths = locator.candidateDirectories().map(\.path)
        #expect(paths.count == Set(paths).count)
    }
}
