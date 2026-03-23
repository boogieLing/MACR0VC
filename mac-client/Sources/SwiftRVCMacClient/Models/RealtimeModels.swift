import Foundation

enum RealtimeMonitorMode: String, CaseIterable, Codable, Identifiable {
    case inputMonitor = "im"
    case outputConverted = "vc"

    var id: String { rawValue }
}

enum SampleRateMode: String, CaseIterable, Codable, Identifiable {
    case model = "sr_model"
    case device = "sr_device"

    var id: String { rawValue }
}

struct RealtimeDeviceSnapshot: Codable {
    let hostapis: [String]
    let selectedHostapi: String
    let inputDevices: [String]
    let outputDevices: [String]
    let selectedInputDevice: String
    let selectedOutputDevice: String
    let sampleRate: Int?
    let channels: Int?
}

struct RealtimeStatus: Codable {
    let running: Bool
    let function: String
    let sampleRate: Int
    let channels: Int
    let delayTimeMs: Int
    let inferTimeMs: Int
    let selectedHostapi: String
    let selectedInputDevice: String
    let selectedOutputDevice: String
    let modelName: String
    let indexPath: String
    let lastError: String?
}

struct RealtimeStatusEnvelope: Codable {
    let devices: RealtimeDeviceSnapshot
    let status: RealtimeStatus
}

struct RealtimeStartRequest: Codable {
    let modelName: String
    let indexPath: String?
    let transpose: Double
    let formant: Double
    let indexRate: Double
    let rmsMixRate: Double
    let f0Method: F0Method
    let threshold: Int
    let sampleLength: Double
    let fadeLength: Double
    let extraInferenceTime: Double
    let cpuProcesses: Int
    let inputNoiseReduction: Bool
    let outputNoiseReduction: Bool
    let usePhaseVocoder: Bool
    let sampleRateMode: SampleRateMode
    let hostapi: String?
    let inputDevice: String?
    let outputDevice: String?
    let wasapiExclusive: Bool
    let function: RealtimeMonitorMode

    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }
        if inputDevice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw ValidationError.missingRealtimeInputDevice
        }
        if outputDevice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw ValidationError.missingRealtimeOutputDevice
        }
    }
}

struct RealtimeConfigureRequest: Codable {
    let modelName: String?
    let indexPath: String?
    let transpose: Double?
    let formant: Double?
    let indexRate: Double?
    let rmsMixRate: Double?
    let f0Method: F0Method?
    let threshold: Int?
    let sampleLength: Double?
    let fadeLength: Double?
    let extraInferenceTime: Double?
    let cpuProcesses: Int?
    let inputNoiseReduction: Bool?
    let outputNoiseReduction: Bool?
    let usePhaseVocoder: Bool?
    let sampleRateMode: SampleRateMode?
    let hostapi: String?
    let inputDevice: String?
    let outputDevice: String?
    let wasapiExclusive: Bool?
    let function: RealtimeMonitorMode?
}
