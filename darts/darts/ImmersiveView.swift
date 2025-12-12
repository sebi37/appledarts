import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {

    func createDartboard() -> Entity {
        let dartboard = Entity()

        let rings: [(radius: Float, color: UIColor)] = [
            (0.5, .black),
            (0.45, .white),
            (0.4, .red),
            (0.35, .green),
            (0.3, .yellow)
        ]

        let height: Float = 0.02
        let zOffsetStep: Float = -0.002

        for (index, ring) in rings.enumerated() {
            let cylinder = ModelEntity(
                mesh: MeshResource.generateCylinder(height: height, radius: ring.radius),
                materials: [SimpleMaterial(color: ring.color, isMetallic: false)]
            )

            cylinder.position = SIMD3(0, Float(index) * zOffsetStep, 0)

            // Approximation der Kollision mit Box
            let collision = CollisionComponent(
                shapes: [ShapeResource.generateBox(size: [ring.radius*2, height, ring.radius*2])]
            )
            cylinder.components.set(collision)
            
            cylinder.components.set(InputTargetComponent())

            dartboard.addChild(cylinder)
        }

        dartboard.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        var manipulation = ManipulationComponent()
        manipulation.releaseBehavior = .stay
        manipulation.dynamics.scalingBehavior = .none
        dartboard.components.set(manipulation)

        return dartboard
    }


    var body: some View {
        RealityView { content in
//            let dartboard = createDartboard()
//            dartboard.position = SIMD3(x: 0, y: 1.2, z: -1.0)
//            content.add(dartboard)
            
            if let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle),
               let dartboard = scene.findEntity(named: "Dartboard") {
                dartboard.generateCollisionShapes(recursive: true)
                dartboard.components.set(InputTargetComponent())
                
                var manipulation = ManipulationComponent()
                manipulation.releaseBehavior = .stay
                manipulation.dynamics.scalingBehavior = .none
                dartboard.components.set(manipulation)
                
                content.add(dartboard)
            }
        }
    }
}

#Preview {
    ImmersiveView()
        .environment(AppModel())
}

