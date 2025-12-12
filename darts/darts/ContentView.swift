import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @State private var enlarge = false

    var body: some View {
        RealityView { content in

            // Szene laden
            guard let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle) else {
                print("Immersive scene nicht gefunden")
                return
            }

            // Original-Segment finden
            guard let originalSegment = scene.findEntity(named: "SegmentModel20") else {
                print("SegmentModel20 nicht gefunden")
                content.add(scene)
                return
            }

            // Mesh im Original finden
            guard let meshEntity = originalSegment.findEntity(named: "Körper1"),
                  let modelComp = meshEntity.components[ModelComponent.self] else {
                print("Körper1 oder ModelComponent fehlt")
                content.add(scene)
                return
            }

            // Collision für das Mesh erstellen
            do {
                let convex = try await ShapeResource.generateConvex(from: modelComp.mesh)
                meshEntity.components.set(CollisionComponent(shapes: [convex], isStatic: true))
                print("Collision auf Körper1 gesetzt")
            } catch {
                print("Fehler beim Erstellen der Collision: \(error)")
            }
            content.add(scene)

        } update: { content in
            if let scene = content.entities.first {
                let scale: Float = enlarge ? 1.4 : 1.0
                scene.transform.scale = [scale, scale, scale]
            }
        }
        .gesture(
            TapGesture().targetedToAnyEntity().onEnded { _ in
                enlarge.toggle()
            }
        )
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environment(AppModel())
}
