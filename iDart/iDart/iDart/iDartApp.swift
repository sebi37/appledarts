import SwiftUI

@main
struct dartsApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {

        // Fenster / Menü
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        // 🎯 Immersive Space (Dartspiel)
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
                .environment(appModel)
        }
    }
}
