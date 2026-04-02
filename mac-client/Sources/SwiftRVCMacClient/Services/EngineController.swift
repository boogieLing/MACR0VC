import Darwin
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

    private static let requiredAPIVersion = "phase1-api-2026-04-02-150837"

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
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
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

        if let endpoint = await bestHealthyEndpoint(in: 7865...7875) {
            applyHealthyEndpoint(endpoint, connectedMessage: "Connected to existing engine")
            return
        }

        let candidatePort: Int
        if let availablePort = PortScanner.firstAvailablePort(in: 7865...7875) {
            candidatePort = availablePort
        } else {
            state = .failed
            lastError = "No compatible backend found in 7865...7875."
            return
        }

        port = candidatePort
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        stdoutPipe = stdout
        stderrPipe = stderr
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
                self.detachPipes()
                self.process = nil
                self.processIdentifier = nil
                if self.state == .stopping {
                    self.port = nil
                    self.backendVersion = nil
                    self.backendSessionID = nil
                    self.backendSessionStartedAt = nil
                    self.readyOnce = false
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

    /// 在应用加载前清掉旧连接快照，避免把失效端口和会话残留带进新一轮自举。
    func prepareForLaunchCleanup() {
        detachPipes()
        process = nil
        resetConnectionState()
        recentLog = ""
        state = .idle
    }

    /// 在应用退出时尽力释放实时与运行时资源，并回收当前拥有的引擎进程。
    func prepareForTermination() {
        bestEffortStopRealtime()
        bestEffortReleaseRuntimeMemory()
        stopAndWait()
        resetConnectionState()
        recentLog = ""
        state = .idle
    }

    // stop TODO: 补充方法注释。
    func stop() {
        guard let process else {
            detachPipes()
            state = .idle
            resetConnectionState()
            return
        }
        state = .stopping
        detachPipes()
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

    /// 停止 pipe 回调，避免旧 stdout / stderr 在重启和退出过程中继续写入 UI 日志。
    private func detachPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
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

    /// 清空连接态和后端元数据，防止 UI 继续持有已失效的端口与会话信息。
    private func resetConnectionState() {
        port = nil
        processIdentifier = nil
        backendVersion = nil
        backendSessionID = nil
        backendSessionStartedAt = nil
        lastError = nil
        readyOnce = false
    }

    /// 同步等待当前受控引擎退出；若超时则强制杀进程，避免端口继续占用。
    private func stopAndWait(timeout: TimeInterval = 2.0) {
        guard let process else {
            detachPipes()
            return
        }
        state = .stopping
        detachPipes()
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                let forcedDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < forcedDeadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                }
            }
        }
        self.process = nil
        self.processIdentifier = nil
    }

    /// 退出时先尽力停止 realtime，避免后续 runtime release 因冲突状态被拒绝。
    private func bestEffortStopRealtime() {
        _ = runBridgeMaintenance(command: "realtime-stop")
    }

    /// 退出时释放模型与缓存，降低下次启动残留状态带来的系统错误概率。
    private func bestEffortReleaseRuntimeMemory() {
        _ = runBridgeMaintenance(command: "release-runtime-memory")
    }

    /// 用同步 bridge 调用执行退出期维护任务，避免终止阶段再依赖异步状态机。
    private func runBridgeMaintenance(command: String, timeout: TimeInterval = 2.0) -> Bool {
        guard let port else { return false }
        guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else { return false }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = environment.engineRoot

        let pythonPath = environment.preferredPythonExecutable
        if FileManager.default.isExecutableFile(atPath: pythonPath) {
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [environment.bridgeScriptURL.path, "--base-url", baseURL.absoluteString, command]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", environment.bridgeScriptURL.path, "--base-url", baseURL.absoluteString, command]
        }

        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if process.isRunning {
            process.terminate()
            return false
        }

        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus == 0 {
            return true
        }

        if let errorText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !errorText.isEmpty {
            recentLog = errorText
        }
        return false
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
