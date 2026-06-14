import Foundation

final class RePKGService {
    private var currentProcess: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    var onOutput: ((String) -> Void)?
    var onComplete: ((Int32) -> Void)?

    var isRunning: Bool { currentProcess?.isRunning ?? false }

    func findExecutable() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["REPKG_PATH"] {
            let url = PathResolver.resolve(envPath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        let resourceURL = Bundle.main.resourceURL
        let execDirURL = Bundle.main.executableURL?.deletingLastPathComponent()

        let candidates: [URL?] = [
            resourceURL?.appendingPathComponent("RePKG"),
            execDirURL?.appendingPathComponent("RePKG"),
            execDirURL?.appendingPathComponent("RePKG.exe"),
            PathResolver.resolve("resources/osx-arm64/RePKG"),
        ]

        for candidate in candidates {
            guard let url = candidate else { continue }
            let resolved = url.standardizedFileURL
            if FileManager.default.fileExists(atPath: resolved.path) { return resolved }
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["RePKG"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        } catch {}

        return nil
    }

    // resolvePath → PathResolver.resolve in PathResolver.swift

    func run(arguments: [String]) throws {
        guard !isRunning else { return }
        guard let executable = findExecutable() else {
            throw RePKGError.executableNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = executable.deletingLastPathComponent()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        outputPipe = outPipe
        errorPipe = errPipe

        setupReadabilityHandler(for: outPipe, handler: onOutput)
        setupReadabilityHandler(for: errPipe, handler: onOutput)

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.cleanupPipes()
                self?.currentProcess = nil
                self?.onComplete?(proc.terminationStatus)
            }
        }

        currentProcess = process
        try process.run()
    }

    func runAndWait(arguments: [String]) async throws -> String {
        guard let executable = findExecutable() else {
            throw RePKGError.executableNotFound
        }

        let output = OutputCollector()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = executable.deletingLastPathComponent()

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    output.append(text)
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    output.append(text)
                }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                try? outPipe.fileHandleForReading.close()
                try? errPipe.fileHandleForReading.close()

                let text = output.value
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: RePKGError.exitCode(proc.terminationStatus, text))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        guard let process = currentProcess, process.isRunning else { return }
        process.terminate()
        cleanupPipes()
        currentProcess = nil
    }

    // MARK: - Private

    private func setupReadabilityHandler(for pipe: Pipe, handler: ((String) -> Void)?) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8), self != nil else { return }
            DispatchQueue.main.async {
                handler?(text)
            }
        }
    }

    private func cleanupPipes() {
        if let pipe = outputPipe {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
        }
        if let pipe = errorPipe {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
        }
    }

    // MARK: - Static

    static func buildArguments(
        inputPath: String,
        outputDir: String? = nil,
        ignoreExtensions: String? = nil,
        onlyExtensions: String? = nil,
        debugInfo: Bool = false,
        convertTEX: Bool = false,
        noTEXConvert: Bool = false,
        singleDir: Bool = false,
        recursive: Bool = true,
        copyProject: Bool = false,
        useName: Bool = false,
        overwrite: Bool = false
    ) -> [String] {
        var args = ["extract"]

        if let out = outputDir { args += ["-o", out] }
        if let ignore = ignoreExtensions, !ignore.isEmpty { args += ["-i", ignore] }
        if let only = onlyExtensions, !only.isEmpty { args += ["-e", only] }
        if debugInfo { args.append("-d") }
        if convertTEX { args.append("-t") }
        if noTEXConvert { args.append("--no-tex-convert") }
        if singleDir { args.append("-s") }
        if recursive { args.append("-r") }
        if copyProject { args.append("-c") }
        if useName { args.append("-n") }
        if overwrite { args.append("--overwrite") }

        args.append(inputPath)
        return args
    }
}

final class OutputCollector: @unchecked Sendable {
    private var _value = ""
    private let lock = NSLock()

    var value: String {
        lock.withLock { _value }
    }

    func append(_ text: String) {
        lock.withLock { _value += text }
    }
}

enum RePKGError: LocalizedError {
    case executableNotFound
    case exitCode(Int32, String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "RePKG executable not found. Set REPKG_PATH environment variable or ensure RePKG is in PATH."
        case .exitCode(let code, let output):
            let preview = output.split(separator: "\n").suffix(3).joined(separator: "\n")
            return "RePKG exited with code \(code).\n\(preview)"
        }
    }
}
