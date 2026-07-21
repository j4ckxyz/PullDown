@preconcurrency import Foundation

protocol ProcessRunning: Sendable {
    func events(for command: CommandSpec) async throws -> AsyncThrowingStream<ProcessEvent, Error>
    func capture(executable: URL, arguments: [String]) async throws -> String
    func cancel() async
}

/// Thread-safe rolling buffer used to remember the tail of a process's
/// standard-error output so a failure can report the real reason.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private let limit: Int

    init(limit: Int = 16_000) {
        self.limit = limit
    }

    func append(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        text += chunk
        if text.count > limit {
            text = String(text.suffix(limit))
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

actor ProcessRunner: ProcessRunning {
    private var activeProcess: Process?
    private var activeProcessID: Int32?

    func events(for command: CommandSpec) throws -> AsyncThrowingStream<ProcessEvent, Error> {
        guard activeProcess == nil else {
            throw PullDownError.downloadAlreadyRunning
        }

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = Self.childEnvironment()

        let stderrBuffer = OutputBuffer()

        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: ProcessEvent.self,
            bufferingPolicy: .bufferingNewest(500)
        )

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            let text = String(decoding: data, as: UTF8.self)
            continuation.yield(.standardOutput(text))
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            let text = String(decoding: data, as: UTF8.self)
            stderrBuffer.append(text)
            continuation.yield(.standardError(text))
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            let exitCode = terminatedProcess.terminationStatus
            let processID = terminatedProcess.processIdentifier
            let stderr = stderrBuffer.snapshot()
            Task {
                await self?.finish(processID: processID, exitCode: exitCode, stderr: stderr, continuation: continuation)
            }
        }

        do {
            try process.run()
            activeProcess = process
            activeProcessID = process.processIdentifier
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            continuation.finish(throwing: error)
            throw error
        }

        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.cancel() }
        }
        return stream
    }

    func capture(executable: URL, arguments: [String]) async throws -> String {
        // Only standard output is returned. Mixing standard error into the
        // result corrupts structured output such as the playlist JSON dump,
        // and any real failure is reported through the thrown error instead.
        var output = ""
        let stream = try events(for: CommandSpec(executable: executable, arguments: arguments))
        for try await event in stream {
            if case let .standardOutput(text) = event {
                output += text
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        guard let activeProcess, activeProcess.isRunning else { return }
        activeProcess.terminate()
    }

    private func finish(
        processID: Int32,
        exitCode: Int32,
        stderr: String,
        continuation: AsyncThrowingStream<ProcessEvent, Error>.Continuation
    ) {
        if activeProcessID == processID {
            activeProcess = nil
            activeProcessID = nil
        }

        if exitCode == 0 {
            continuation.finish()
        } else {
            let message = YTDLPErrorFormatter.describe(exitCode: exitCode, stderr: stderr)
            continuation.finish(throwing: ProcessExecutionError(exitCode: exitCode, message: message))
        }
    }

    /// A GUI app launched from Finder inherits a bare environment, so yt-dlp
    /// and any helper it shells out to can behave differently than in a
    /// terminal. Augment PATH with the common tool locations to keep the two
    /// consistent across machines.
    static func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let additions = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existing = environment["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        var ordered: [String] = []
        var seen = Set<String>()
        for path in existing + additions where seen.insert(path).inserted {
            ordered.append(path)
        }
        environment["PATH"] = ordered.joined(separator: ":")
        return environment
    }
}
