import SwiftUI
import FirebaseCore

@main
struct FriendsApp: App {
    init() {
        FirebaseApp.configure()
        // デフォルトのログレベルを設定 (.debug)
        AppLogger.setLevel(.debug)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
