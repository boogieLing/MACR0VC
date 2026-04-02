import SwiftUI
import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        appState?.prepareForTermination()
    }
}

@main
struct SwiftRVCMacClientApp: App {
    @AppStorage("app.language") private var appLanguageRawValue = AppLanguage.system.rawValue
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycleDelegate
    @StateObject private var appState: AppState

    init() {
        let environment = (try? AppEnvironment.detect()) ?? .fallback()
        _appState = StateObject(wrappedValue: AppState(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1260, minHeight: 760)
                .onAppear {
                    lifecycleDelegate.appState = appState
                }
                .task {
                    await appState.performInitialBootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            Form {
                Picker(L10n.tr("settings.language.title"), selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }

                Text(L10n.tr("app.settings.deferred"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 360)
        }
    }
}
