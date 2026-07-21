import Darwin
import Foundation

protocol ExecutableChecking: Sendable {
    func isExecutable(at url: URL) -> Bool
}

struct LocalExecutableChecker: ExecutableChecking {
    func isExecutable(at url: URL) -> Bool {
        access(url.path, X_OK) == 0
    }
}

protocol ExecutableLocating: Sendable {
    func locate(named name: String) -> URL?
}

struct ExecutableLocator: ExecutableLocating, Sendable {
    let homeDirectory: URL
    let environmentPath: String?
    let managedBinDirectory: URL
    let checker: any ExecutableChecking

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        managedBinDirectory: URL? = nil,
        checker: any ExecutableChecking = LocalExecutableChecker()
    ) {
        self.homeDirectory = homeDirectory
        self.environmentPath = environmentPath
        self.managedBinDirectory = managedBinDirectory ?? Self.defaultManagedBinDirectory(home: homeDirectory)
        self.checker = checker
    }

    func locate(named name: String) -> URL? {
        candidateDirectories().lazy
            .map { $0.appending(path: name, directoryHint: .notDirectory) }
            .first(where: checker.isExecutable)
    }

    func candidateDirectories() -> [URL] {
        var paths: [String] = [
            managedBinDirectory.path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/sw/bin",
            "/usr/bin",
            "/bin",
            homeDirectory.appending(path: ".local/bin").path,
            homeDirectory.appending(path: "bin").path,
            homeDirectory.appending(path: ".pyenv/shims").path,
            homeDirectory.appending(path: ".asdf/shims").path,
            homeDirectory.appending(path: ".local/share/mise/shims").path,
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
        ]

        for minorVersion in 10...14 {
            paths.append(homeDirectory.appending(path: "Library/Python/3.\(minorVersion)/bin").path)
        }

        if let environmentPath {
            paths.insert(contentsOf: environmentPath.split(separator: ":").map(String.init), at: 1)
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            let expanded = (path as NSString).expandingTildeInPath
            guard expanded.isEmpty == false, seen.insert(expanded).inserted else { return nil }
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
    }

    static func defaultManagedBinDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: "PullDown/bin", directoryHint: .isDirectory)
    }
}
