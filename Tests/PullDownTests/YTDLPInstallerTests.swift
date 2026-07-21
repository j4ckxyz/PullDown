import Foundation
import Testing
@testable import PullDown

struct YTDLPInstallerTests {
    @Test func extractsNamedChecksumFromOfficialFormat() {
        let contents = """
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  yt-dlp
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb *yt-dlp_macos
        """
        #expect(YTDLPInstaller.checksum(for: "yt-dlp_macos", in: contents) == String(repeating: "b", count: 64))
    }

    @Test func computesKnownSHA256Digest() {
        let digest = YTDLPInstaller.sha256Hex(of: Data("hello".utf8))
        #expect(digest == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
