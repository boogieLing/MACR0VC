import Foundation

enum F0Method: String, CaseIterable, Codable, Identifiable {
    case pm
    case dio
    case harvest
    case crepe
    case rmvpe
    case fcpe

    var id: String { rawValue }

    /// Returns the display label shown in UI pickers and status cards.
    var displayName: String {
        rawValue.uppercased()
    }

    /// Returns the short sentence used in compact UI surfaces.
    var shortDescription: String {
        switch self {
        case .pm:
            return "Fastest classic option for quick tests."
        case .dio:
            return "Light classic option with simple balance."
        case .harvest:
            return "Stronger on low notes and noisy vocals."
        case .crepe:
            return "Most detailed, but also the heaviest."
        case .rmvpe:
            return "Recommended default for most vocals."
        case .fcpe:
            return "Light neural option with smoother tracking."
        }
    }

    /// Returns the longer picker subtitle for users choosing an F0 strategy.
    var pickerDescription: String {
        switch self {
        case .pm:
            return "Fastest. Best for quick clean-speech checks."
        case .dio:
            return "Light classic fallback. Lower load than RMVPE."
        case .harvest:
            return "Safer on singing, low notes, and noisy takes."
        case .crepe:
            return "Most pitch detail, but the highest compute cost."
        case .rmvpe:
            return "Best all-rounder. Start here first."
        case .fcpe:
            return "Light neural balance between classic and CREPE."
        }
    }
}

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    case wav
    case flac
    case mp3
    case m4a

    var id: String { rawValue }
}

struct ModelCatalog: Codable {
    let models: [ModelOption]
    let indexPaths: [String]
}

struct ModelSelectionResult: Codable {
    let modelName: String
    let modelInfoSummary: String
    let modelInfoError: String?
    let indexPaths: [String]
    let speakerCount: Int
}

struct ModelUnloadResult: Codable {
    let modelName: String
    let modelInfoSummary: String
    let indexPaths: [String]
    let speakerCount: Int
    let unloaded: Bool
}

struct MemoryReleaseResult: Codable {
    let released: Bool
    let message: String
}

struct SingleInferenceRequest: Encodable {
    let modelName: String
    let inputFileURL: URL
    let outputDirectoryURL: URL
    let speakerID: Int
    let transpose: Double
    let f0Method: F0Method
    let indexPath: String?
    let customIndexURL: URL?
    let indexRate: Double
    let filterRadius: Double
    let resampleSR: Double
    let rmsMixRate: Double
    let protect: Double
    let f0FileURL: URL?

    /// Returns the index path that should be sent to the backend, preferring an explicit override.
    var resolvedIndexPath: String? {
        if let customIndexURL {
            return customIndexURL.path
        }
        return indexPath
    }

    /// Validates local file inputs before serialization.
    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }
        if !FileManager.default.fileExists(atPath: inputFileURL.path) {
            throw ValidationError.missingInputFile
        }
        try Self.validateOptionalFileURL(customIndexURL, error: .missingCustomIndexFile)
        try Self.validateOptionalFileURL(f0FileURL, error: .missingF0CurveFile)
    }

    /// Encodes the request using the resolved index path so backend payloads stay compatible.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(inputFileURL, forKey: .inputFileURL)
        try container.encode(outputDirectoryURL, forKey: .outputDirectoryURL)
        try container.encode(speakerID, forKey: .speakerID)
        try container.encode(transpose, forKey: .transpose)
        try container.encode(f0Method, forKey: .f0Method)
        try container.encode(resolvedIndexPath, forKey: .indexPath)
        try container.encode(indexRate, forKey: .indexRate)
        try container.encode(filterRadius, forKey: .filterRadius)
        try container.encode(resampleSR, forKey: .resampleSR)
        try container.encode(rmsMixRate, forKey: .rmsMixRate)
        try container.encode(protect, forKey: .protect)
        try container.encode(f0FileURL, forKey: .f0FileURL)
    }

    private enum CodingKeys: String, CodingKey {
        case modelName
        case inputFileURL
        case outputDirectoryURL
        case speakerID = "speakerId"
        case transpose
        case f0Method
        case indexPath
        case indexRate
        case filterRadius
        case resampleSR
        case rmsMixRate
        case protect
        case f0FileURL
    }

    /// Reuses the same existence gate for optional path-based overrides.
    private static func validateOptionalFileURL(_ url: URL?, error: ValidationError) throws {
        guard let url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            throw error
        }
    }
}

struct SingleInferenceResult: Codable {
    let message: String
    let outputAudioURL: URL?
    let outputDirectoryURL: URL?
}

enum TextAudioGenderID: String, CaseIterable, Codable, Identifiable {
    case female
    case male

    var id: String { rawValue }

    /// 文本生成先锁定性别基线，再继续细化语气。
    var displayName: String {
        switch self {
        case .female:
            return "Female"
        case .male:
            return "Male"
        }
    }

    /// 用简短说明告诉用户当前性别基线对源声线的影响。
    var shortDescription: String {
        switch self {
        case .female:
            return "Higher-formant source baseline for feminine target voices."
        case .male:
            return "Lower-formant source baseline for masculine target voices."
        }
    }

    /// 自定义语气文本优先建立在当前性别基线上，减少偏离目标模型的概率。
    var customTonePlaceholder: String {
        switch self {
        case .female:
            return "Example: soft idol, gentle narration, airy whisper"
        case .male:
            return "Example: calm lead, warm narration, deep serious"
        }
    }

    var defaultTonePreset: TextAudioTonePresetID {
        switch self {
        case .female:
            return .femaleNatural
        case .male:
            return .maleWarmSolid
        }
    }
}

enum TextAudioToneMode: String, CaseIterable, Codable, Identifiable {
    case preset
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .preset:
            return "Preset"
        case .custom:
            return "Custom"
        }
    }

    var shortDescription: String {
        switch self {
        case .preset:
            return "Use a tuned tone preset that already biases toward the target voice."
        case .custom:
            return "Enter a free-form tone hint, then keep the RVC match preset strict."
        }
    }
}

enum TextAudioMatchProfileID: String, CaseIterable, Codable, Identifiable {
    case identityLock
    case balancedMatch
    case expressiveMatch
    case customToneLock

    var id: String { rawValue }

    /// 这些预设不是泛化风格，而是直接控制目标音色贴合策略。
    var displayName: String {
        switch self {
        case .identityLock:
            return "RVC Voice Priority"
        case .balancedMatch:
            return "Balanced Match"
        case .expressiveMatch:
            return "Expressive Match"
        case .customToneLock:
            return "Custom Tone Lock"
        }
    }

    var shortDescription: String {
        switch self {
        case .identityLock:
            return "Default. Push the conversion hardest toward the selected RVC model timbre."
        case .balancedMatch:
            return "Safer default when you still want a stable target timbre."
        case .expressiveMatch:
            return "Keep more speaking motion while staying inside the target identity."
        case .customToneLock:
            return "Use custom tone text, but keep the timbre lock stricter than the tone freedom."
        }
    }
}

enum TextAudioTonePresetID: String, CaseIterable, Codable, Identifiable {
    case femaleSadYouth = "female_sad_youth"
    case femaleGentle = "female_gentle"
    case femaleElegantMature = "female_elegant_mature"
    case femaleBrightCheerful = "female_bright_cheerful"
    case femaleNatural = "female_natural"
    case femaleHeartbroken = "female_heartbroken"
    case maleWarmSolid = "male_warm_solid"
    case maleClearLead = "male_clear_lead"
    case maleDeepAnchor = "male_deep_anchor"
    case maleCalmNarration = "male_calm_narration"

    var id: String { rawValue }

    var gender: TextAudioGenderID {
        switch self {
        case .femaleSadYouth, .femaleGentle, .femaleElegantMature, .femaleBrightCheerful, .femaleNatural, .femaleHeartbroken:
            return .female
        case .maleWarmSolid, .maleClearLead, .maleDeepAnchor, .maleCalmNarration:
            return .male
        }
    }

    /// 预设名称直接使用英文，保持 IN 二级菜单语言统一。
    var displayName: String {
        switch self {
        case .femaleSadYouth:
            return "Sad Youth"
        case .femaleGentle:
            return "Gentle"
        case .femaleElegantMature:
            return "Elegant Mature"
        case .femaleBrightCheerful:
            return "Bright Cheerful"
        case .femaleNatural:
            return "Natural"
        case .femaleHeartbroken:
            return "Heartbroken"
        case .maleWarmSolid:
            return "Warm Solid"
        case .maleClearLead:
            return "Clear Lead"
        case .maleDeepAnchor:
            return "Deep Anchor"
        case .maleCalmNarration:
            return "Calm Narration"
        }
    }

    var shortDescription: String {
        switch self {
        case .femaleSadYouth:
            return "Youthful sadness with a lighter center and cleaner emotional phrasing."
        case .femaleGentle:
            return "Soft, warm, and mild. Good for calm lines without pushing too much color."
        case .femaleElegantMature:
            return "Steadier mature female tone with more control and less sweetness."
        case .femaleBrightCheerful:
            return "Lively, open, and sunny. Best for energetic lines and clear positivity."
        case .femaleNatural:
            return "Balanced everyday female baseline for most lines and first-pass testing."
        case .femaleHeartbroken:
            return "Heavier grief with slower breath and a more fragile emotional tail."
        case .maleWarmSolid:
            return "Warm, centered source for most male RVC voices."
        case .maleClearLead:
            return "Cleaner front presence for youthful or brighter male models."
        case .maleDeepAnchor:
            return "Low, dense source for deeper target voices."
        case .maleCalmNarration:
            return "Steady speech contour for calm male narration."
        }
    }

    /// 后端用这个 id 解析到具体 ChatTTS preset，不再直接暴露旧的 bright / airy / warm / deep 心智。
    var backendPresetID: String {
        rawValue
    }

    /// 每个 tone preset 都绑定一组基础参数，再叠加匹配策略。
    var baseParameterBundle: TextAudioParameterBundle {
        switch self {
        case .femaleSadYouth:
            return .init(transpose: 13, speechRate: .medium, f0Method: .crepe, indexRate: 0.89, filterRadius: 3, resampleSR: 0, rmsMixRate: 0.92, protect: 0.12)
        case .femaleGentle:
            return .init(transpose: 13, speechRate: .medium, f0Method: .crepe, indexRate: 0.87, filterRadius: 3, resampleSR: 0, rmsMixRate: 0.94, protect: 0.16)
        case .femaleElegantMature:
            return .init(transpose: 12, speechRate: .medium, f0Method: .crepe, indexRate: 0.88, filterRadius: 3, resampleSR: 0, rmsMixRate: 0.91, protect: 0.12)
        case .femaleBrightCheerful:
            return .init(transpose: 15, speechRate: .fast, f0Method: .crepe, indexRate: 0.93, filterRadius: 2, resampleSR: 0, rmsMixRate: 0.85, protect: 0.06)
        case .femaleNatural:
            return .init(transpose: 12, speechRate: .medium, f0Method: .crepe, indexRate: 0.86, filterRadius: 3, resampleSR: 0, rmsMixRate: 0.92, protect: 0.14)
        case .femaleHeartbroken:
            return .init(transpose: 12, speechRate: .slow, f0Method: .crepe, indexRate: 0.86, filterRadius: 4, resampleSR: 0, rmsMixRate: 0.94, protect: 0.18)
        case .maleWarmSolid:
            return .init(transpose: 2, speechRate: .medium, f0Method: .crepe, indexRate: 0.86, filterRadius: 3, resampleSR: 0, rmsMixRate: 0.94, protect: 0.18)
        case .maleClearLead:
            return .init(transpose: 4, speechRate: .fast, f0Method: .crepe, indexRate: 0.84, filterRadius: 3, resampleSR: 0, rmsMixRate: 0.92, protect: 0.16)
        case .maleDeepAnchor:
            return .init(transpose: -2, speechRate: .slow, f0Method: .crepe, indexRate: 0.82, filterRadius: 5, resampleSR: 0, rmsMixRate: 0.98, protect: 0.22)
        case .maleCalmNarration:
            return .init(transpose: 0, speechRate: .medium, f0Method: .crepe, indexRate: 0.80, filterRadius: 5, resampleSR: 0, rmsMixRate: 0.97, protect: 0.20)
        }
    }

    // presets TODO: 补充方法注释。
    static func presets(for gender: TextAudioGenderID) -> [TextAudioTonePresetID] {
        allCases.filter { $0.gender == gender }
    }
}

enum TextAudioSpeechRateID: String, CaseIterable, Codable, Identifiable {
    case slow
    case medium
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slow:
            return "Slow"
        case .medium:
            return "Mid"
        case .fast:
            return "Fast"
        }
    }

    var promptToken: String {
        switch self {
        case .slow:
            return "[speed_2]"
        case .medium:
            return "[speed_4]"
        case .fast:
            return "[speed_8]"
        }
    }
}

enum TargetVoiceGenderHint: String, Codable {
    case female
    case male
    case unknown

    /// 基于当前仓库已有模型名和元信息做保守推断，只在明显命中时才收紧自动升调。
    static func infer(modelName: String?, infoSummary: String?) -> TargetVoiceGenderHint {
        let combinedText = [modelName ?? "", infoSummary ?? ""]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !combinedText.isEmpty else { return .unknown }

        let explicitFemaleMarkers = [
            "gender: female", "gender=female", "sex: female", "female voice",
            "female", "女声", "女生", "女性", "女"
        ]
        if explicitFemaleMarkers.contains(where: { combinedText.contains($0) }) {
            return .female
        }

        let explicitMaleMarkers = [
            "gender: male", "gender=male", "sex: male", "male voice",
            "male", "男声", "男生", "男性", "男"
        ]
        if explicitMaleMarkers.contains(where: { combinedText.contains($0) }) {
            return .male
        }

        let knownFemaleModelMarkers = [
            "taffy", "atri", "doro", "乃琳", "嘉然", "东雪莲", "伊蕾娜",
            "友利奈绪", "小兰", "由比滨结衣", "米浴", "雪之下雪乃", "诗歌剧"
        ]
        if knownFemaleModelMarkers.contains(where: { combinedText.contains($0.lowercased()) }) {
            return .female
        }

        let knownMaleModelMarkers = ["丁真", "炭治郎"]
        if knownMaleModelMarkers.contains(where: { combinedText.contains($0.lowercased()) }) {
            return .male
        }

        return .unknown
    }
}

struct TextAudioParameterBundle: Codable, Equatable {
    var transpose: Double
    var speechRate: TextAudioSpeechRateID
    var f0Method: F0Method
    var indexRate: Double
    var filterRadius: Double
    var resampleSR: Double
    var rmsMixRate: Double
    var protect: Double

    /// 性别护栏优先保证“听起来还是这个性别的人声”，再谈风格化。
    func normalized(
        for sourceGender: TextAudioGenderID,
        targetGenderHint: TargetVoiceGenderHint = .unknown
    ) -> TextAudioParameterBundle {
        if sourceGender == .female, targetGenderHint == .female {
            return TextAudioParameterBundle(
                transpose: min(transpose, 0),
                speechRate: speechRate,
                f0Method: f0Method,
                indexRate: min(max(indexRate, 0.86), 0.94),
                filterRadius: min(max(filterRadius, 2), 4),
                resampleSR: resampleSR,
                rmsMixRate: min(max(rmsMixRate, 0.88), 0.95),
                protect: min(max(protect, 0.10), 0.20)
            )
        }

        switch sourceGender {
        case .female:
            return TextAudioParameterBundle(
                transpose: max(transpose, 12),
                speechRate: speechRate,
                f0Method: f0Method,
                indexRate: min(max(indexRate, 0.86), 0.94),
                filterRadius: min(max(filterRadius, 2), 4),
                resampleSR: resampleSR,
                rmsMixRate: min(max(rmsMixRate, 0.88), 0.95),
                protect: min(max(protect, 0.10), 0.20)
            )
        case .male:
            return TextAudioParameterBundle(
                transpose: min(transpose, 6),
                speechRate: speechRate,
                f0Method: f0Method,
                indexRate: min(max(indexRate, 0.78), 0.92),
                filterRadius: max(filterRadius, 3),
                resampleSR: resampleSR,
                rmsMixRate: min(max(rmsMixRate, 0.88), 0.98),
                protect: min(max(protect, 0.10), 0.24)
            )
        }
    }

    /// 匹配策略负责把 tone preset 的基础参数向“更像模型音色”这件事进一步压实。
    func applying(matchProfile: TextAudioMatchProfileID) -> TextAudioParameterBundle {
        switch matchProfile {
        case .identityLock:
            return TextAudioParameterBundle(
                transpose: transpose,
                speechRate: speechRate,
                f0Method: f0Method,
                indexRate: max(indexRate, 0.92),
                filterRadius: min(max(filterRadius, 3), 5),
                resampleSR: resampleSR,
                rmsMixRate: min(rmsMixRate, 0.88),
                protect: min(protect, 0.08)
            )
        case .balancedMatch:
            return TextAudioParameterBundle(
                transpose: transpose,
                speechRate: speechRate,
                f0Method: f0Method,
                indexRate: max(indexRate, 0.86),
                filterRadius: max(filterRadius, 3),
                resampleSR: resampleSR,
                rmsMixRate: min(rmsMixRate, 0.92),
                protect: min(max(protect, 0.14), 0.18)
            )
        case .expressiveMatch:
            return TextAudioParameterBundle(
                transpose: transpose,
                speechRate: speechRate,
                f0Method: f0Method,
                indexRate: max(indexRate, 0.82),
                filterRadius: max(filterRadius, 5),
                resampleSR: resampleSR,
                rmsMixRate: min(rmsMixRate, 0.96),
                protect: min(max(protect, 0.18), 0.22)
            )
        case .customToneLock:
            return TextAudioParameterBundle(
                transpose: transpose,
                speechRate: speechRate,
                f0Method: f0Method,
                indexRate: max(indexRate, 0.84),
                filterRadius: max(filterRadius, 3),
                resampleSR: resampleSR,
                rmsMixRate: min(rmsMixRate, 0.90),
                protect: min(max(protect, 0.12), 0.18)
            )
        }
    }
}

struct TextAudioRequest: Encodable {
    let modelName: String
    let text: String
    let outputDirectoryURL: URL
    let gender: TextAudioGenderID
    let toneMode: TextAudioToneMode
    let tonePreset: TextAudioTonePresetID?
    let customToneText: String
    let matchProfile: TextAudioMatchProfileID
    let speakerID: Int
    let transpose: Double
    let speechRate: TextAudioSpeechRateID
    let f0Method: F0Method
    let indexPath: String?
    let customIndexURL: URL?
    let indexRate: Double
    let filterRadius: Double
    let resampleSR: Double
    let rmsMixRate: Double
    let protect: Double

    /// 返回应发送到后端的索引路径，优先使用外部覆盖值。
    var resolvedIndexPath: String? {
        if let customIndexURL {
            return customIndexURL.path
        }
        return indexPath
    }

    /// 在发起文本转音频任务前校验模型与文本输入。
    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BridgeError.invocationFailed("Enter some text before generating audio.")
        }
        if toneMode == .custom && customToneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BridgeError.invocationFailed("Enter a custom tone hint before using custom tone mode.")
        }
        try Self.validateOptionalFileURL(customIndexURL, error: .missingCustomIndexFile)
    }

    /// 以与单文件换声一致的键名编码文本任务请求。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(text, forKey: .text)
        try container.encode(outputDirectoryURL, forKey: .outputDirectoryURL)
        try container.encode(gender, forKey: .gender)
        try container.encode(toneMode, forKey: .toneMode)
        try container.encode(tonePreset, forKey: .tonePreset)
        try container.encode(customToneText, forKey: .customToneText)
        try container.encode(matchProfile, forKey: .matchProfile)
        try container.encode(speakerID, forKey: .speakerID)
        try container.encode(transpose, forKey: .transpose)
        try container.encode(speechRate, forKey: .speechRate)
        try container.encode(f0Method, forKey: .f0Method)
        try container.encode(resolvedIndexPath, forKey: .indexPath)
        try container.encode(indexRate, forKey: .indexRate)
        try container.encode(filterRadius, forKey: .filterRadius)
        try container.encode(resampleSR, forKey: .resampleSR)
        try container.encode(rmsMixRate, forKey: .rmsMixRate)
        try container.encode(protect, forKey: .protect)
    }

    private enum CodingKeys: String, CodingKey {
        case modelName
        case text
        case outputDirectoryURL
        case gender
        case toneMode
        case tonePreset
        case customToneText
        case matchProfile
        case speakerID = "speakerId"
        case transpose
        case speechRate
        case f0Method
        case indexPath
        case indexRate
        case filterRadius
        case resampleSR
        case rmsMixRate
        case protect
    }

    /// 复用可选路径存在性校验。
    private static func validateOptionalFileURL(_ url: URL?, error: ValidationError) throws {
        guard let url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            throw error
        }
    }
}

struct TextAudioResult: Codable {
    let message: String
    let sourceAudioURL: URL?
    let outputAudioURL: URL?
    let outputDirectoryURL: URL?
}

enum TextAudioStage: String, Codable {
    case idle
    case preparing
    case loadingChatTTS
    case generatingSpeech
    case convertingVoice
    case finalizing
    case completed
    case failed

    /// 统一提供队列面板使用的短标题。
    var displayTitle: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparing:
            return "Prepare"
        case .loadingChatTTS:
            return "Load TTS"
        case .generatingSpeech:
            return "Generate"
        case .convertingVoice:
            return "Convert"
        case .finalizing:
            return "Finalize"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
    }
}

struct TextAudioProgressSnapshot: Codable {
    let active: Bool
    let stage: TextAudioStage
    let title: String
    let detail: String
    let completedSteps: Int
    let totalSteps: Int
    let modelName: String?
    let stageElapsedSeconds: Double?
    let totalElapsedSeconds: Double?
    let stageDurations: [String: Double]?
}

struct BatchInferenceRequest: Encodable {
    let modelName: String
    let inputDirectoryURL: URL?
    let inputFileURLs: [URL]
    let outputDirectoryURL: URL
    let format: OutputFormat
    let speakerID: Int
    let transpose: Double
    let f0Method: F0Method
    let indexPath: String?
    let customIndexURL: URL?
    let indexRate: Double
    let filterRadius: Double
    let resampleSR: Double
    let rmsMixRate: Double
    let protect: Double

    /// Returns the index path that should be sent to the backend, preferring an explicit override.
    var resolvedIndexPath: String? {
        if let customIndexURL {
            return customIndexURL.path
        }
        return indexPath
    }

    /// Validates local file inputs before serialization.
    func validate() throws {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingModel
        }

        let hasDirectory = inputDirectoryURL != nil
        let hasFiles = !inputFileURLs.isEmpty
        if hasDirectory == hasFiles {
            throw ValidationError.invalidBatchInputMode
        }

        if hasDirectory, let directory = inputDirectoryURL,
           !FileManager.default.fileExists(atPath: directory.path) {
            throw ValidationError.missingInputDirectory
        }

        if hasFiles, inputFileURLs.contains(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            throw ValidationError.missingInputFile
        }

        try Self.validateOptionalFileURL(customIndexURL, error: .missingCustomIndexFile)
    }

    /// Encodes the batch request using the resolved index path so backend payloads stay compatible.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(inputDirectoryURL, forKey: .inputDirectoryURL)
        try container.encode(inputFileURLs, forKey: .inputFileURLs)
        try container.encode(outputDirectoryURL, forKey: .outputDirectoryURL)
        try container.encode(format, forKey: .format)
        try container.encode(speakerID, forKey: .speakerID)
        try container.encode(transpose, forKey: .transpose)
        try container.encode(f0Method, forKey: .f0Method)
        try container.encode(resolvedIndexPath, forKey: .indexPath)
        try container.encode(indexRate, forKey: .indexRate)
        try container.encode(filterRadius, forKey: .filterRadius)
        try container.encode(resampleSR, forKey: .resampleSR)
        try container.encode(rmsMixRate, forKey: .rmsMixRate)
        try container.encode(protect, forKey: .protect)
    }

    private enum CodingKeys: String, CodingKey {
        case modelName
        case inputDirectoryURL
        case inputFileURLs
        case outputDirectoryURL
        case format
        case speakerID = "speakerId"
        case transpose
        case f0Method
        case indexPath
        case indexRate
        case filterRadius
        case resampleSR
        case rmsMixRate
        case protect
    }

    /// Reuses the same existence gate for optional path-based overrides.
    private static func validateOptionalFileURL(_ url: URL?, error: ValidationError) throws {
        guard let url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            throw error
        }
    }
}

struct BatchInferenceResult: Codable {
    let message: String
    let outputDirectoryURL: URL?
    let outputFileURLs: [URL]
}

enum ValidationError: LocalizedError {
    case missingModel
    case missingInputFile
    case missingInputDirectory
    case invalidBatchInputMode
    case invalidUVRInputMode
    case missingRealtimeInputDevice
    case missingRealtimeOutputDevice
    case missingCustomIndexFile
    case missingF0CurveFile

    /// Maps validation failures to user-facing copy while keeping the existing localization behavior.
    var errorDescription: String? {
        switch self {
        case .missingModel:
            return L10n.tr("validation.missing_model")
        case .missingInputFile:
            return L10n.tr("validation.missing_input_file")
        case .missingInputDirectory:
            return L10n.tr("validation.missing_input_directory")
        case .invalidBatchInputMode:
            return L10n.tr("validation.invalid_batch_input_mode")
        case .invalidUVRInputMode:
            return "Choose either an input folder or explicit audio files for UVR."
        case .missingRealtimeInputDevice:
            return L10n.tr("validation.missing_realtime_input_device")
        case .missingRealtimeOutputDevice:
            return L10n.tr("validation.missing_realtime_output_device")
        case .missingCustomIndexFile:
            return "Custom index file does not exist."
        case .missingF0CurveFile:
            return "F0 curve file does not exist."
        }
    }
}
