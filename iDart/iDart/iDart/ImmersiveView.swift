import SwiftUI
import RealityKit

struct ImmersiveView: View {

    var body: some View {
        RealityView { content in

            let anchor = AnchorEntity(.head)
            content.add(anchor)

            // 🎯 Dartboard
            let board = ModelEntity(
                mesh: .generateCylinder(height: 0.02, radius: 0.25),
                materials: [SimpleMaterial(color: .white, isMetallic: false)]
            )
            board.position = [0, 0, -2.0]
            board.components.set(
                PhysicsBodyComponent(
                    massProperties: .default,
                    material: .default,
                    mode: .static
                )
            )
            anchor.addChild(board)

            // 🟥 Dart
            let dart = ModelEntity(
                mesh: .generateCylinder(height: 0.15, radius: 0.01),
                materials: [SimpleMaterial(color: .red, isMetallic: true)]
            )
            dart.position = [0, 0, -0.4]

            var body = PhysicsBodyComponent(
                massProperties: .default,
                material: .default,
                mode: .dynamic
            )
            body.linearDamping = 0.1
            body.angularDamping = 5.0
            dart.components.set(body)

            anchor.addChild(dart)

            // 🚀 Testwurf
            let direction = normalize(SIMD3<Float>(0, 0, -2) - dart.position)
            dart.applyLinearImpulse(direction * 3.0, relativeTo: nil)
        }
    }
}
