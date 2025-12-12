import SwiftUI

struct ContentView: View {

    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 20) {
            Text("Apple Darts 🎯")
                .font(.largeTitle)
                .bold()

            Text("Starte das Dartspiel im Immersive Space")
                .foregroundStyle(.secondary)

            ToggleImmersiveSpaceButton()
        }
        .padding(40)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
