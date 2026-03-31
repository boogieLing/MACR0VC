import Foundation

@MainActor
final class EngineController: ObservableObject {
    private struct HealthPayload: Decodable {
        let status: String
        let apiVersion: String?
        let backendVersion: String?
        let sessionId: String?
        let sessionStartedAt: String?
    }

    private struct HealthyEndpoint {
        let port: Int
        let payload: HealthPayload
    }

    private static let requiredAPIVersion = "phase1-api-2026-03-29"

    @Published private(set) var state: EngineState = .idle
    @Published private(set) var port: Int?
    @Published private(set) var processIdentifier: Int32?
    @Published private(set) var lastError: String?
    @Published private(set) var recentLog: String = ""
    @Published private(set) var backendVersion: String?
    @Published private(set) var backendSessionID: String?
    @Published private(set) var backendSessionStartedAt: String?

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

    var backendVersionLabel: String {
        backendVersion ?? "Unknown"
    }

    // start TODO: 补充方法注释。
    func start() async {
        guard state != .starting, state != .ready else { return }

        lastError = nil
        readyOnce = false
        recentLog = ""
        backendVersion = nil
        backendSessionID = nil
        backendSessionStartedAt = nil
        state = .starting

        let candidatePort: Int
        if let availablePort = PortScanner.firstAvailablePort(in: 7865...7875) {
            candidatePort = availablePort
        } else if let endpoint = await bestHealthyEndpoint(in: 7865...7875) {
            applyHealthyEndpoint(endpoint, connectedMessage: "Connected to existing engine")
            return
        } else {
            state = .failed
            lastError = "No compatible backend found in 7865...7875."
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
                    self.backendVersion = nil
                    self.backendSessionID = nil
                    self.backendSessionStartedAt = nil
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

    // refreshConnection TODO: 补充方法注释。
    func refreshConnection() async {
        lastError = nil
        state = .starting
        if let endpoint = await bestHealthyEndpoint(in: 7865...7875) {
            applyHealthyEndpoint(endpoint, connectedMessage: "Refreshed backend connection")
            return
        }

        if let currentPort = port, await waitUntilReady(port: currentPort) {
            state = .ready
            return
        }

        state = .failed
        lastError = "No compatible backend is reachable. Start or restart the engine."
    }

    // restart TODO: 补充方法注释。
    func restart() async {
        stop()
        try? await Task.sleep(for: .milliseconds(500))
        await start()
    }

    // stop TODO: 补充方法注释。
    func stop() {
        guard let process else {
            state = .idle
            processIdentifier = nil
            backendVersion = nil
            backendSessionID = nil
            backendSessionStartedAt = nil
            return
        }
        state = .stopping
        process.terminate()
    }

    // attach TODO: 补充方法注释。
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

    // waitUntilReady TODO: 补充方法注释。
    private func waitUntilReady(port: Int) async -> Bool {
        for _ in 0..<60 {
            if let endpoint = await healthyEndpoint(port: port) {
                applyHealthyEndpoint(endpoint)
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    // bestHealthyEndpoint TODO: 补充方法注释。
    private func bestHealthyEndpoint(in range: ClosedRange<Int>) async -> HealthyEndpoint? {
        var best: HealthyEndpoint?
        for port in range {
            guard let endpoint = await healthyEndpoint(port: port) else { continue }
            if let currentBest = best {
                let left = endpoint.payload.sessionStartedAt ?? ""
                let right = currentBest.payload.sessionStartedAt ?? ""
                if left > right {
                    best = endpoint
                }
            } else {
                best = endpoint
            }
        }
        return best
    }

    // healthyEndpoint TODO: 补充方法注释。
    private func healthyEndpoint(port: Int) async -> HealthyEndpoint? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(httpResponse.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(HealthPayload.self, from: data)
            guard payload.status == "ok", payload.apiVersion == Self.requiredAPIVersion else { return nil }
            return HealthyEndpoint(port: port, payload: payload)
        } catch {
            return nil
        }
    }

    // applyHealthyEndpoint TODO: 补充方法注释。
    private func applyHealthyEndpoint(_ endpoint: HealthyEndpoint, connectedMessage: String? = nil) {
        port = endpoint.port
        processIdentifier = process?.processIdentifier
        backendVersion = endpoint.payload.backendVersion
        backendSessionID = endpoint.payload.sessionId
        backendSessionStartedAt = endpoint.payload.sessionStartedAt
        readyOnce = true
        state = .ready
        if let connectedMessage {
            recentLog = "\(connectedMessage) on port \(endpoint.port) (\(endpoint.payload.backendVersion ?? "unknown"))."
        }
    }

#if DEBUG
    /// 为单元测试直接注入引擎就绪态，避免依赖真实后端启动流程。
    func forceReadyForTesting(port: Int? = 7865) {
        self.port = port
        processIdentifier = nil
        lastError = nil
        readyOnce = true
        state = .ready
    }
#endif
}
