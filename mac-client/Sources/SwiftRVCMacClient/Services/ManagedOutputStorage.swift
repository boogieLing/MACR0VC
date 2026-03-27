import Foundation

struct ManagedTaskOutputReservation {
    let taskID: UUID
    let taskDirectoryURL: URL
    let primaryOutputDirectoryURL: URL
    let secondaryOutputDirectoryURL: URL?
}

struct ManagedOutputStorage {
    private let environment: AppEnvironment
    private let fileManager: FileManager

    /// Creates a repo-scoped storage helper for managed task outputs.
    init(environment: AppEnvironment, fileManager: FileManager = .default) {
        self.environment = environment
        self.fileManager = fileManager
    }

    /// Ensures the shared storage tree exists before any task reserves output space.
    func prepareBaseDirectories() throws {
        try ensureDirectory(environment.unifiedStorageRootDirectory)
        try ensureDirectory(environment.defaultSingleOutputDirectory)
        try ensureDirectory(environment.defaultBatchOutputDirectory)
        try ensureDirectory(environment.defaultUVROutputDirectory)
        try ensureDirectory(environment.defaultONNXExportDirectory)
    }

    /// Reserves a unique managed directory for one single-file conversion task.
    func reserveSingleOutput(for inputFileURL: URL) throws -> ManagedTaskOutputReservation {
        let taskID = UUID()
        let taskDirectoryURL = try makeTaskDirectory(
            family: "single",
            slug: inputFileURL.deletingPathExtension().lastPathComponent,
            taskID: taskID
        )
        return ManagedTaskOutputReservation(
            taskID: taskID,
            taskDirectoryURL: taskDirectoryURL,
            primaryOutputDirectoryURL: taskDirectoryURL,
            secondaryOutputDirectoryURL: nil
        )
    }

    /// Reserves a unique managed directory for one batch conversion task.
    func reserveBatchOutput() throws -> ManagedTaskOutputReservation {
        let taskID = UUID()
        let taskDirectoryURL = try makeTaskDirectory(
            family: "batch",
            slug: "batch",
            taskID: taskID
        )
        return ManagedTaskOutputReservation(
            taskID: taskID,
            taskDirectoryURL: taskDirectoryURL,
            primaryOutputDirectoryURL: taskDirectoryURL,
            secondaryOutputDirectoryURL: nil
        )
    }

    /// Reserves paired vocals and instrumentals directories for one UVR task.
    func reserveUVROutputs(inputLabel: String?) throws -> ManagedTaskOutputReservation {
        let taskID = UUID()
        let taskDirectoryURL = try makeTaskDirectory(
            family: "uvr",
            slug: inputLabel ?? "uvr",
            taskID: taskID
        )
        let vocalDirectoryURL = taskDirectoryURL.appendingPathComponent("vocals", isDirectory: true)
        let instrumentalDirectoryURL = taskDirectoryURL.appendingPathComponent("instrumentals", isDirectory: true)
        try ensureDirectory(vocalDirectoryURL)
        try ensureDirectory(instrumentalDirectoryURL)
        return ManagedTaskOutputReservation(
            taskID: taskID,
            taskDirectoryURL: taskDirectoryURL,
            primaryOutputDirectoryURL: vocalDirectoryURL,
            secondaryOutputDirectoryURL: instrumentalDirectoryURL
        )
    }

    private func makeTaskDirectory(family: String, slug: String, taskID: UUID) throws -> URL {
        try prepareBaseDirectories()
        let directoryURL = environment.unifiedStorageRootDirectory
            .appendingPathComponent("tasks", isDirectory: true)
            .appendingPathComponent(family, isDirectory: true)
            .appendingPathComponent(directoryName(for: slug, taskID: taskID), isDirectory: true)
        try ensureDirectory(directoryURL)
        return directoryURL
    }

    private func directoryName(for slug: String, taskID: UUID) -> String {
        let timestamp = Self.directoryTimestampFormatter.string(from: Date())
        let compactID = String(taskID.uuidString.prefix(8))
        return "\(timestamp)-\(sanitizedSlug(slug))-\(compactID)"
    }

    private func sanitizedSlug(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let mapped = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let compact = String(mapped)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compact.isEmpty ? "task" : compact.lowercased()
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private static let directoryTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
