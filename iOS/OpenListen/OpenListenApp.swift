import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        AudioDownloads.backgroundCompletion = completionHandler
        _ = AudioDownloads.shared.session
    }
}

@main
struct OpenListenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var library: LibraryStore
    @StateObject private var player: AudioPlayer
    @Environment(\.scenePhase) private var phase

    init() {
        let store = LibraryStore()
        _library = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: AudioPlayer(library: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(player)
                .tint(.mint).preferredColorScheme(.dark)
                .task(id: phase) {
                    guard phase == .active else { player.savePosition(); return }
                    while !Task.isCancelled {
                        await library.refresh()
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    }
                }
        }
    }
}
