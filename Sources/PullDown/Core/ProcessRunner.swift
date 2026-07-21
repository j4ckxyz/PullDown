@preconcurrency import Foundation

protocol ProcessRunning: Sendable {
    func events(for command: CommandSpec) async throws -> AsyncThrowingStream<ProcessEvent, Error>
    func capture(executable: URL, arguments: [String]) async throws -> String
    func cancel() async
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
            continuation.yield(.standardError(text))
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            let exitCode = terminatedProcess.terminationStatus
            let processID = terminatedProcess.processIdentifier
            Task {
                await self?.finish(processID: processID, exitCode: exitCode, continuation: continuation)
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
        var output = ""
        let stream = try events(for: CommandSpec(executable: executable, arguments: arguments))
        for try await event in stream {
            switch event {
            case let .standardOutput(text), let .standardError(text):
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
        continuation: AsyncThrowingStream<ProcessEvent, Error>.Continuation
    ) {
        if activeProcessID == processID {
            activeProcess = nil
            activeProcessID = nil
        }

        if exitCode == 0 {
            continuation.finish()
        } else {
            continuation.finish(throwing: ProcessExecutionError(exitCode: exitCode, message: "yt-dlp stopped with exit status \(exitCode)."))
        }
    }
}
