import Foundation

enum TaskHistoryKind: String, Codable, CaseIterable {
    case single
    case batch
    case realtime
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
    let speakerID: Int?
    let errorMessage: String?
}
