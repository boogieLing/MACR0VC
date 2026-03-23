import Foundation

struct AppEnvironment {
    let repoRoot: URL
    let engineRoot: URL
    let engineRunnerURL: URL
    let bridgeScriptURL: URL

    var weightsDirectory: URL {
        engineRoot.appendingPathComponent("assets/weights", isDirectory: true)
    }

    var indicesDirectory: URL {
        engineRoot.appendingPathComponent("assets/indices", isDirectory: true)
    }

    var defaultBatchOutputDirectory: URL {
        engineRoot.appendingPathComponent("opt", isDirectory: true)
    }

    var preferredPythonExecutable: String {
        let python3 = engineRoot.appendingPathComponent(".venv/bin/python3").path
        if FileManager.default.isExecutableFile(atPath: python3) {
            return python3
        }

        let python = engineRoot.appendingPathComponent(".venv/bin/python").path
        if FileManager.default.isExecutableFile(atPath: python) {
            return python
        }

        return "/usr/bin/python3"
    }

    static func detect(
        fileManager: FileManager = .default,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        bundleURL: URL = Bundle.main.bundleURL
    ) throws -> AppEnvironment {
        let cwd = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        let bundleRoot = bundleURL.standardizedFileURL

        var candidates: [URL] = []
        candidates.append(cwd)
        candidates.append(cwd.deletingLastPathComponent())

        var cursor = bundleRoot
        for _ in 0..<6 {
            candidates.append(cursor)
            cursor.deleteLastPathComponent()
        }

        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.path).inserted }

        for candidate in unique {
            let repo = normalizedRepoRoot(from: candidate)
            let engineRoot = repo.appendingPathComponent("engine", isDirectory: true)
            let runner = engineRoot.appendingPathComponent("run-engine.sh")
            let bridge = engineRoot.appendingPathComponent("gradio_bridge.py")
            let macClient = repo.appendingPathComponent("mac-client", isDirectory: true)
            if fileManager.fileExists(atPath: runner.path),
               fileManager.fileExists(atPath: bridge.path),
               fileManager.fileExists(atPath: macClient.path) {
                return AppEnvironment(
                    repoRoot: repo,
                    engineRoot: engineRoot,
                    engineRunnerURL: runner,
                    bridgeScriptURL: bridge
                )
            }
        }

        throw AppEnvironmentError.repoRootNotFound
    }

    static func fallback() -> AppEnvironment {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let repo = normalizedRepoRoot(from: cwd)
        let engineRoot = repo.appendingPathComponent("engine", isDirectory: true)
        return AppEnvironment(
            repoRoot: repo,
            engineRoot: engineRoot,
            engineRunnerURL: engineRoot.appendingPathComponent("run-engine.sh"),
            bridgeScriptURL: engineRoot.appendingPathComponent("gradio_bridge.py")
        )
    }

    private static func normalizedRepoRoot(from candidate: URL) -> URL {
        if candidate.lastPathComponent == "mac-client" || candidate.lastPathComponent == "engine" {
            return candidate.deletingLastPathComponent()
        }
        return candidate
    }
}

enum AppEnvironmentError: LocalizedError {
    case repoRootNotFound

    var errorDescription: String? {
        switch self {
        case .repoRootNotFound:
            return L10n.tr("environment.repo_root_not_found")
        }
    }
}
