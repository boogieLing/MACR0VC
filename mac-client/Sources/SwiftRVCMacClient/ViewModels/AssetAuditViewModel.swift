import Foundation

@MainActor
final class AssetAuditViewModel: ObservableObject {
    @Published private(set) var report: AssetIntegrityReport?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var errorMessage: String?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient

    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    var items: [AssetIntegrityItem] {
        report?.items ?? []
    }

    func refreshReport() async {
        errorMessage = nil
        isChecking = true
        defer { isChecking = false }

        do {
            let report = try await bridgeClient.fetchAssetIntegrityReport()
            self.report = report
            lastRunSummary = report.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadAssets() async {
        errorMessage = nil
        isDownloading = true
        defer { isDownloading = false }

        do {
            let result = try await bridgeClient.downloadAssets()
            if let report = result.report {
                self.report = report
            }
            lastRunSummary = result.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
