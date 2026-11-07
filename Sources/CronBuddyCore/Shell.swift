import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public struct CronBuddyError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Shell {
    /// POSIX single-quote escaping, safe for sh, bash and zsh.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a short-lived tool to completion. Meant for commands with small output.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String] = [], input: String? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let inPipe = input.map { _ in Pipe() }
        process.standardInput = inPipe ?? FileHandle.nullDevice

        try process.run()
        if let inPipe, let input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
