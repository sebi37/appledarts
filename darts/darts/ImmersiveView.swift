import SwiftUI
import UIKit
import RealityKit
import RealityKitContent

// MARK: - Eigener State für Dart
struct DartStateComponent: Component {
    var wasHeld: Bool = false
    var wasThrown: Bool = false
}

struct ImmersiveView: View {

    // MARK: - Dart
    func createDart() -> ModelEntity {
        let dart = ModelEntity(
            mesh: .generateCylinder(height: 0.15, radius: 0.005),
            materials: [SimpleMaterial(color: UIColor.gray, isMetallic: true)]
        )

        dart.name = "Dart"

        dart.components.set(
            CollisionComponent(
                shapes: [.generateCapsule(height: 0.15, radius: 0.01)]
            )
        )

        dart.components.set(
            PhysicsBodyComponent(
                massProperties: .default,
                material: .default,
                mode: .kinematic
            )
        )

        dart.components.set(InputTargetComponent())

        var manipulation = ManipulationComponent()
        // NOTE: In some visionOS SDK versions, ReleaseBehavior doesn't have `.remove`.
        // We'll handle "throw" explicitly on tap instead of relying on release behavior.
        dart.components.set(manipulation)

        dart.components.set(DartStateComponent())
        return dart
    }

    // MARK: - Tisch
    func createTable() -> ModelEntity {
        let size = SIMD3<Float>(0.6, 0.05, 0.4)

        let table = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: UIColor.brown, isMetallic: false)]
        )

        table.name = "Table"
        table.position = SIMD3(0, 0.8, -0.6)

        table.components.set(
            PhysicsBodyComponent(
                massProperties: .default,
                material: .default,
                mode: .static
            )
        )

        table.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: size)]
            )
        )

        return table
    }
    
    // MARK: - Ball
    func createBall() -> ModelEntity {
        let radius: Float = 0.04

        let ball = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )

        ball.name = "Ball"

        ball.components.set(
            CollisionComponent(
                shapes: [.generateSphere(radius: radius)]
            )
        )

        ball.components.set(
            PhysicsBodyComponent(
                massProperties: .default,
                material: .default,
                mode: .dynamic
            )
        )

        ball.components.set(InputTargetComponent())

        var manipulation = ManipulationComponent()
        ball.components.set(manipulation)

        return ball
    }

    var body: some View {
        RealityView { content in

            // 🎯 Dartboard
            if let scene = try? await Entity(
                named: "Immersive",
                in: realityKitContentBundle
            ),
            let dartboard = scene.findEntity(named: "Dartboard") {

                dartboard.name = "Dartboard"
                dartboard.generateCollisionShapes(recursive: true)

                dartboard.components.set(
                    PhysicsBodyComponent(
                        massProperties: .default,
                        material: .default,
                        mode: .static
                    )
                )

                // ✅ DAS WAR DIE FEHLENDE ÄNDERUNG
                dartboard.components.set(InputTargetComponent())

                var manipulation = ManipulationComponent()
                manipulation.releaseBehavior = .stay
                manipulation.dynamics.scalingBehavior = .none
                dartboard.components.set(manipulation)

                content.add(dartboard)
            }

            // 🪑 Tisch
            let table = createTable()
            content.add(table)

            // ⚽ Ball auf dem Tisch
            let ball = createBall()
            ball.position = SIMD3(0.2, 0.9, -0.6)
            content.add(ball)

            // 🎯 Drei Darts
            for i in 0..<3 {
                let dart = createDart()
                dart.position = SIMD3(
                    -0.1 + Float(i) * 0.1,
                    0.85,
                    -0.6
                )
                content.add(dart)
            }

        } update: { content in
            for entity in content.entities {
                guard entity.name == "Dart",
                      var state = entity.components[DartStateComponent.self]
                else { continue }

                let isCurrentlyHeld = entity.components[ManipulationComponent.self] != nil
                state.wasHeld = isCurrentlyHeld
                entity.components.set(state)
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard value.entity.name == "Dart" || value.entity.name == "Ball" else { return }

                    // Find the dartboard in the same scene (works even if it's not a top-level entity)
                    let board = value.entity.scene?.findEntity(named: "Dartboard")
                    let targetPos = board?.position ?? SIMD3<Float>(0, 0.8, -2.0)

                    guard let dartEntity = value.entity as? ModelEntity else { return }

                    // Hand over control to physics
                    dartEntity.components.remove(ManipulationComponent.self)
                    dartEntity.components.remove(PhysicsMotionComponent.self)

                    var body = PhysicsBodyComponent(
                        massProperties: .default,
                        material: .default,
                        mode: .dynamic
                    )
                    body.linearDamping = 0.05
                    body.angularDamping = 8.0
                    dartEntity.components.set(body)

                    // Throw toward the dartboard
                    let direction = normalize(targetPos - dartEntity.position)
                    var motion = PhysicsMotionComponent()
                    motion.linearVelocity = direction * 4.0
                    dartEntity.components.set(motion)

                    // Mark as thrown (optional; keeps state coherent)
                    if var state = value.entity.components[DartStateComponent.self] {
                        state.wasThrown = true
                        value.entity.components.set(state)
                    }
                }
        )
    }
}

#Preview {
    ImmersiveView()
        .environment(AppModel())
}
