import SwiftUI
import UIKit
import RealityKit
import RealityKitContent

// MARK: - Eigener State für Dart
struct DartStateComponent: Component {
    var wasHeld: Bool = false
    var wasThrown: Bool = false
}

// MARK: - Track velocity while manipulating (for throw-on-release)
struct VelocityTrackingComponent: Component {
    var lastPosition: SIMD3<Float>?
    var linearVelocity: SIMD3<Float> = .zero
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
        manipulation.releaseBehavior = .stay   // ⬅️ CRITICAL: prevents snap-back on release
        manipulation.dynamics.scalingBehavior = .none
        dart.components.set(manipulation)

        dart.components.set(DartStateComponent())
        dart.components.set(VelocityTrackingComponent())
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
    
    // MARK: - Floor (prevents falling into the void)
    func createFloor() -> Entity {
        let floor = Entity()
        let size: Float = 10.0

        let shape = ShapeResource.generateBox(
            width: size,
            height: 0.02,
            depth: size
        )

        floor.components.set(
            CollisionComponent(shapes: [shape])
        )

        floor.components.set(
            PhysicsBodyComponent(
                shapes: [shape],
                mass: 1.0,
                material: PhysicsMaterialResource.generate(
                    friction: 0.9,
                    restitution: 0.0
                ),
                mode: .static
            )
        )

        floor.position = SIMD3(0, 0.0, 0)
        return floor
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

        let manipulation = ManipulationComponent()
        ball.components.set(manipulation)

        ball.components.set(VelocityTrackingComponent())
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
            content.add(createFloor())

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
            
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                let dt = max(Float(event.deltaTime), 0.001)

                for entity in event.scene.performQuery(EntityQuery(where: .has(VelocityTrackingComponent.self))) {
                    guard let model = entity as? ModelEntity else { continue }

                    // Only track while the user is manipulating the entity (so "release" velocity makes sense)
                    guard model.components[ManipulationComponent.self] != nil else {
                        // Reset the last position when not being held to avoid stale spikes
                        if var vt = model.components[VelocityTrackingComponent.self] {
                            vt.lastPosition = nil
                            vt.linearVelocity = .zero
                            model.components.set(vt)
                        }
                        continue
                    }

                    let pos = model.position(relativeTo: nil)

                    if var vt = model.components[VelocityTrackingComponent.self] {
                        if let last = vt.lastPosition {
                            vt.linearVelocity = (pos - last) / dt
                        }
                        vt.lastPosition = pos
                        model.components.set(vt)
                    }
                }
            }
            
            _ = content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                guard
                    let model = event.entity as? ModelEntity,
                    model.name == "Dart"
                else { return }

                // Read tracked release velocity (still valid in WillEnd)
                let velocity =
                    model.components[VelocityTrackingComponent.self]?.linearVelocity ?? .zero

                let speed = length(velocity)
                let throwThreshold: Float = 0.25

                // 🟢 Drop (no throw) → let gravity place the dart
                if speed < throwThreshold {
                    // Remove manipulation control
                    model.components.remove(ManipulationComponent.self)
                    model.components.remove(InputTargetComponent.self)

                    if var body = model.components[PhysicsBodyComponent.self] {
                        body.mode = .dynamic
                        body.linearDamping = 0.8
                        body.angularDamping = 8.0
                        model.components.set(body)
                    }

                    // Ensure no residual throw velocity
                    var motion = PhysicsMotionComponent()
                    motion.linearVelocity = .zero
                    motion.angularVelocity = .zero
                    model.components.set(motion)

                    // Cleanup
                    model.components.remove(VelocityTrackingComponent.self)
                    return
                }

                // 🚫 Hand-off from manipulation to physics
                model.components.remove(ManipulationComponent.self)
                model.components.remove(InputTargetComponent.self)

                if var body = model.components[PhysicsBodyComponent.self] {
                    body.mode = .dynamic
                    body.linearDamping = 0.05
                    body.angularDamping = 6.0
                    model.components.set(body)
                }

                // 🎯 Force direction toward dartboard
                if let dartboard = model.scene?.findEntity(named: "Dartboard") {
                    let from = model.position(relativeTo: nil)
                    let to = dartboard.position(relativeTo: nil)
                    let direction = normalize(to - from)

                    let strength = max(speed, 0.6)

                    var motion = PhysicsMotionComponent()
                    motion.linearVelocity = direction * strength * 1.5
                    model.components.set(motion)
                }

                // Cleanup
                model.components.remove(VelocityTrackingComponent.self)
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
    }
}

#Preview {
    ImmersiveView()
        .environment(AppModel())
}
