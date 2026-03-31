import Foundation

enum TaskHistoryKind: String, Codable, CaseIterable {
    case single
    case batch
    case text
    case realtime
    case uvr
}

enum TaskHistoryStatus: String, Codable, CaseIterable {
    case success
    case failure
    case info
}

struct TaskHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: TaskHistoryKind
    let status: TaskHistoryStatus
    let title: String
    let summary: String
    let modelName: String?
    let inputLabel: String?
    let inputPath: String?
    let outputLabel: String?
    let outputPath: String?
    let indexPath: String?
    let f0Method: String?
    let parameterSummary: String?
    let timingSummary: String?
    let speakerID: Int?
    let errorMessage: String?
    let taskDirectoryPath: String?
    let outputArtifacts: [TaskHistoryArtifact]
    let sourceTaskID: UUID?

    init(
        id: UUID,
        timestamp: Date,
        kind: TaskHistoryKind,
        status: TaskHistoryStatus,
        title: String,
        summary: String,
        modelName: String?,
        inputLabel: String?,
        inputPath: String?,
        outputLabel: String?,
        outputPath: String?,
        indexPath: String?,
        f0Method: String?,
        parameterSummary: String?,
        timingSummary: String?,
        speakerID: Int?,
        errorMessage: String?,
        taskDirectoryPath: String?,
        outputArtifacts: [TaskHistoryArtifact] = [],
        sourceTaskID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.status = status
        self.title = title
        self.summary = summary
        self.modelName = modelName
        self.inputLabel = inputLabel
        self.inputPath = inputPath
        self.outputLabel = outputLabel
        self.outputPath = outputPath
        self.indexPath = indexPath
        self.f0Method = f0Method
        self.parameterSummary = parameterSummary
        self.timingSummary = timingSummary
        self.speakerID = speakerID
        self.errorMessage = errorMessage
        self.taskDirectoryPath = taskDirectoryPath
        self.outputArtifacts = outputArtifacts
        self.sourceTaskID = sourceTaskID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        kind = try container.decode(TaskHistoryKind.self, forKey: .kind)
        status = try container.decode(TaskHistoryStatus.self, forKey: .status)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        inputLabel = try container.decodeIfPresent(String.self, forKey: .inputLabel)
        inputPath = try container.decodeIfPresent(String.self, forKey: .inputPath)
        outputLabel = try container.decodeIfPresent(String.self, forKey: .outputLabel)
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
        indexPath = try container.decodeIfPresent(String.self, forKey: .indexPath)
        f0Method = try container.decodeIfPresent(String.self, forKey: .f0Method)
        parameterSummary = try container.decodeIfPresent(String.self, forKey: .parameterSummary)
        timingSummary = try container.decodeIfPresent(String.self, forKey: .timingSummary)
        speakerID = try container.decodeIfPresent(Int.self, forKey: .speakerID)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        taskDirectoryPath = try container.decodeIfPresent(String.self, forKey: .taskDirectoryPath)
        outputArtifacts = try container.decodeIfPresent([TaskHistoryArtifact].self, forKey: .outputArtifacts) ?? []
        sourceTaskID = try container.decodeIfPresent(UUID.self, forKey: .sourceTaskID)
    }
}

struct TaskHistoryArtifact: Identifiable, Codable, Equatable {
    let id: UUID
    let role: TaskHistoryArtifactRole
    let label: String
    let path: String
}

enum TaskHistoryArtifactRole: String, Codable, CaseIterable {
    case singleOutput
    case batchOutput
    case textOutput
    case textSource
    case uvrVocal
    case uvrInstrumental
    case mixedOutput
}
