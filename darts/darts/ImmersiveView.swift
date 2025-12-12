import SwiftUI
import UIKit
import RealityKit
import RealityKitContent

// MARK: - Eigener State für Dart
struct DartStateComponent: Component {
    var wasHeld: Bool = false
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
        manipulation.releaseBehavior = .stay
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
            // 🎯 Referenz auf Dartboard
            let dartboard = content.entities.first { $0.name == "Dartboard" }

            // 🏹 Loslassen erkennen → Wurf
            for entity in content.entities {
                guard entity.name == "Dart",
                      var state = entity.components[DartStateComponent.self]
                else { continue }

                let isCurrentlyHeld =
                    entity.components[ManipulationComponent.self] != nil

                // 👉 Übergang: gehalten → losgelassen
                if state.wasHeld && !isCurrentlyHeld,
                   let board = dartboard {

                    entity.components.remove(ManipulationComponent.self)
                    entity.components.remove(PhysicsMotionComponent.self)

                    // Richtung vom Dart zur Scheibe
                    let direction = normalize(board.position - entity.position)

                    // Physik auf dynamisch umstellen
                    var body = PhysicsBodyComponent(
                        massProperties: .default,
                        material: .default,
                        mode: .dynamic
                    )
                    body.linearDamping = 0.1
                    body.angularDamping = 10.0
                    entity.components.set(body)

                    // Fluggeschwindigkeit setzen
                    entity.components.set(
                        PhysicsMotionComponent(
                            linearVelocity: direction * 4.0
                        )
                    )
                }

                state.wasHeld = isCurrentlyHeld
                entity.components.set(state)
            }
        }
    }
}

#Preview {
    ImmersiveView()
        .environment(AppModel())
}
