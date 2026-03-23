import Foundation

@MainActor
final class EngineController: ObservableObject {
    @Published private(set) var state: EngineState = .idle
    @Published private(set) var port: Int?
    @Published private(set) var processIdentifier: Int32?
    @Published private(set) var lastError: String?
    @Published private(set) var recentLog: String = ""

    private let environment: AppEnvironment
    private var process: Process?
    private var readyOnce = false

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var baseURL: URL? {
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    func start() async {
        guard state != .starting, state != .ready else { return }

        lastError = nil
        readyOnce = false
        recentLog = ""
        state = .starting

        let candidatePort: Int
        if let availablePort = PortScanner.firstAvailablePort(in: 7865...7875) {
            candidatePort = availablePort
        } else if let existingPort = await firstHealthyPort(in: 7865...7875) {
            port = existingPort
            processIdentifier = nil
            readyOnce = true
            state = .ready
            recentLog = "Connected to existing engine on port \(existingPort)."
            return
        } else {
            state = .failed
            lastError = L10n.tr("engine.no_port")
            return
        }

        port = candidatePort
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = environment.engineRoot
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            environment.engineRunnerURL.path,
            "--port", "\(candidatePort)",
            "--noautoopen",
            "--nocheck",
        ]

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        attach(pipe: stdout)
        attach(pipe: stderr)

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process = nil
                self.processIdentifier = nil
                if self.state == .stopping {
                    self.state = .idle
                    return
                }

                if !self.readyOnce {
                    self.state = .failed
                    self.lastError = L10n.tr(
                        "engine.exit_before_ready",
                        terminatedProcess.terminationStatus
                    )
                } else if self.state != .failed {
                    self.state = .idle
                }
            }
        }

        do {
            try process.run()
            self.process = process
            self.processIdentifier = process.processIdentifier
        } catch {
            state = .failed
            lastError = error.localizedDescription
            return
        }

        let becameReady = await waitUntilReady(port: candidatePort)
        guard becameReady else {
            state = .failed
            lastError = recentLog.isEmpty ? L10n.tr("engine.timeout") : recentLog
            stop()
            return
        }

        readyOnce = true
        state = .ready
    }

    func restart() async {
        stop()
        try? await Task.sleep(for: .milliseconds(500))
        await start()
    }

    func stop() {
        guard let process else {
            state = .idle
            processIdentifier = nil
            return
        }
        state = .stopping
        process.terminate()
    }

    private func attach(pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if self.recentLog.isEmpty {
                    self.recentLog = trimmed
                } else {
                    self.recentLog = [self.recentLog, trimmed].joined(separator: "\n")
                }

                let lines = self.recentLog.split(separator: "\n", omittingEmptySubsequences: false)
                if lines.count > 14 {
                    self.recentLog = lines.suffix(14).joined(separator: "\n")
                }
            }
        }
    }

    private func waitUntilReady(port: Int) async -> Bool {
        for _ in 0..<60 {
            if await isReady(port: port) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    private func firstHealthyPort(in range: ClosedRange<Int>) async -> Int? {
        for port in range {
            if await isReady(port: port) {
                return port
            }
        }
        return nil
    }

    private func isReady(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
}
