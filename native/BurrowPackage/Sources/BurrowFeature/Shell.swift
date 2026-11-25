import Foundation

/// Runs command-line tools as child processes of Burrow, so they inherit
/// Burrow's own privacy access (Full Disk Access is granted to Burrow.app).
/// Every run gets an explicit PATH and `/dev/null` as stdin unless input is
/// given: `mo clean` without a TTY is non-interactive, which is what Burrow wants.
public enum Shell {
    public struct Result: Sendable {
        public var code: Int32
        public var stdout: String
        public var stderr: String
        public var timedOut = false
        public var ok: Bool { code == 0 && !timedOut }
        /// The last lines of output, for error messages.
        public var tail: String {
            let text = Fmt.stripANSI(stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.split(separator: "\n").suffix(2).joined(separator: " ")
        }
    }

    static let path = [
        "/opt/homebrew/bin", "/usr/local/bin", "\(Paths.home)/.cargo/bin", "\(Paths.home)/.local/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ].joined(separator: ":")

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        return env
    }

    /// Runs `executable args…` and collects its output. `onLine` sees stdout line by line as it arrives.
    public static func run(
        _ executable: String, _ args: [String], input: String? = nil, timeout: TimeInterval = 120,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> Result {
        await withCheckedContinuation { (cont: CheckedContinuation<Result, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = environment
            process.currentDirectoryURL = URL(fileURLWithPath: Paths.home)
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            let inPipe: Pipe? = input == nil ? nil : Pipe()
            process.standardInput = inPipe ?? FileHandle.nullDevice

            let collector = Collector(onLine: onLine)
            let group = DispatchGroup()
            group.enter()
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; group.leave() } else { collector.out(d) }
            }
            group.enter()
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; group.leave() } else { collector.err(d) }
            }
            group.enter()
            process.terminationHandler = { _ in group.leave() }
            do {
                try process.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: Result(code: 127, stdout: "", stderr: error.localizedDescription))
                return
            }
            if let inPipe, let input {
                DispatchQueue.global().async {
                    try? inPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                    try? inPipe.fileHandleForWriting.close()
                }
            }
            let timer = DispatchWorkItem { [weak process] in
                guard let process, process.isRunning else { return }
                collector.timedOut = true
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            group.notify(queue: .global()) {
                timer.cancel()
                cont.resume(returning: collector.result(code: process.terminationStatus))
            }
        }
    }

    /// `bash -c` with Burrow's PATH. Quote arguments with `Shell.quote`.
    public static func sh(_ command: String, input: String? = nil, timeout: TimeInterval = 120,
                          onLine: (@Sendable (String) -> Void)? = nil) async -> Result {
        await run("/bin/bash", ["-c", command], input: input, timeout: timeout, onLine: onLine)
    }

    /// One of the bundled scan scripts (Scripts/), run from Burrow's support folder.
    public static func script(_ name: String, _ args: [String] = [], input: String? = nil, timeout: TimeInterval = 300) async -> Result {
        await run("/bin/bash", [Paths.scripts.appendingPathComponent("\(name).sh").path] + args, input: input, timeout: timeout)
    }

    /// Single-quotes a value for bash.
    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Gathers a child's output from the pipe handlers (which run on their own queues).
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data(), errData = Data(), lineBuffer = Data()
    private let onLine: (@Sendable (String) -> Void)?
    var timedOut = false

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func out(_ d: Data) {
        lock.lock()
        outData.append(d)
        var lines: [String] = []
        if onLine != nil {
            lineBuffer.append(d)
            while let i = lineBuffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                lines.append(String(decoding: lineBuffer[lineBuffer.startIndex..<i], as: UTF8.self))
                lineBuffer.removeSubrange(lineBuffer.startIndex...i)
            }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func err(_ d: Data) { lock.lock(); errData.append(d); lock.unlock() }

    func result(code: Int32) -> Shell.Result {
        lock.lock(); defer { lock.unlock() }
        return Shell.Result(code: code, stdout: String(decoding: outData, as: UTF8.self),
                            stderr: String(decoding: errData, as: UTF8.self), timedOut: timedOut)
    }
}
