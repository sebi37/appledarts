import SwiftUI
import UIKit
import RealityKit
import RealityKitContent

// MARK: - Eigener State für Dart
struct DartStateComponent: Component {
    var wasHeld: Bool = false
    var wasThrown: Bool = false
    var isStuck: Bool = false
}

// MARK: - Track velocity while manipulating
struct VelocityTrackingComponent: Component {
    var lastPosition: SIMD3<Float>?
    var linearVelocity: SIMD3<Float> = .zero
}

struct ImmersiveView: View {
    
    @State private var darts: [ModelEntity] = []
    @State private var resetFlag = false

    // MARK: - Dart
    func createDart() -> ModelEntity {
        let dart = ModelEntity(
            mesh: .generateCylinder(height: 0.15, radius: 0.005),
            materials: [SimpleMaterial(color: .gray, isMetallic: true)]
        )

        dart.name = "Dart"

        dart.components.set(
            CollisionComponent(
                shapes: [.generateCapsule(height: 0.15, radius: 0.01)]
            )
        )
        
        dart.orientation = simd_quatf(
            angle: .pi / 2,
            axis: SIMD3<Float>(1, 0, 0)
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
            materials: [SimpleMaterial(color: .brown, isMetallic: false)]
        )

        table.name = "Table"
        table.position = SIMD3(0, 0.8, -0.6)

        table.components.set(
            PhysicsBodyComponent(mode: .static)
        )

        table.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: size)]
            )
        )

        return table
    }

    // MARK: - Floor
    func createFloor() -> Entity {
        let floor = Entity()
        let size: Float = 10.0

        let shape = ShapeResource.generateBox(
            width: size,
            height: 0.02,
            depth: size
        )

        floor.components.set(CollisionComponent(shapes: [shape]))
        floor.components.set(
            PhysicsBodyComponent(
                shapes: [shape],
                mass: 1.0,
                material: .default,
                mode: .static
            )
        )

        floor.position = SIMD3(0, 0.0, 0)
        return floor
    }

    // MARK: - Dartboard mit 5 Ringen
    func createTargetMarker() -> Entity {
        let container = Entity()

        // Ringe: äußerster bis innerster
        let ringRadii: [Float] = [0.25, 0.20, 0.15, 0.10, 0.05]
        let ringColors: [UIColor] = [.red, .white, .blue, .yellow, .green]
        let ringPoints: [Int] = [10, 20, 30, 40, 50] // Punkte für jeden Ring
        let ringHeight: Float = 0.02
        let ringOffset: Float = 0.003 // kleine Z-Verschiebung, um Überschneidungen zu vermeiden

        for i in 0..<ringRadii.count {
            // Mesh erstellen
            let ring = ModelEntity(
                mesh: .generateCylinder(height: ringHeight, radius: ringRadii[i]),
                materials: [SimpleMaterial(color: ringColors[i], isMetallic: false)]
            )

            // Ringe horizontal ausrichten
            ring.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            ring.position = SIMD3(0, 1.2, -1.2 + Float(i) * ringOffset)

            // Collision vom Mesh ableiten (rund statt Box)
            if let convexShape = try? ShapeResource.generateConvex(from: ring.model!.mesh) {
                ring.components.set(CollisionComponent(shapes: [convexShape]))
            }

            // Physics Body statisch setzen
            ring.components.set(
                PhysicsBodyComponent(
                    massProperties: .default,
                    material: .default,
                    mode: .static
                )
            )

            // Punkte als Component speichern
            struct RingPointsComponent: Component {
                var points: Int
            }
            ring.components.set(RingPointsComponent(points: ringPoints[i]))

            ring.name = "Ring_\(i)"
            container.addChild(ring)
        }

        return container
    }


    /// MARK: - View
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            RealityView { content in
                content.add(createTable())
                content.add(createFloor())
                content.add(createTargetMarker())

                for i in 0..<3 {
                    let dart = createDart()
                    dart.position = SIMD3(-0.1 + Float(i) * 0.1, 0.85, -0.6)
                    darts.append(dart)
                    content.add(dart)
                }
                
                // --- Collision Listener ---
                _ = content.subscribe(to: CollisionEvents.Began.self) { event in
                    guard
                        let dart = event.entityA as? ModelEntity ?? event.entityB as? ModelEntity,
                        dart.name == "Dart"
                    else { return }

                    var state = dart.components[DartStateComponent.self] ?? DartStateComponent()
                    if state.isStuck { return }

                    let ring = (event.entityA as? ModelEntity)?.name.starts(with: "Ring_") == true
                        ? event.entityA as! ModelEntity
                        : (event.entityB as? ModelEntity)?.name.starts(with: "Ring_") == true
                            ? event.entityB as! ModelEntity
                            : nil
                    guard let hitRing = ring else { return }

                    // Dart auf Scheibe kleben lassen
                    dart.components.remove(PhysicsMotionComponent.self)
                    if var body = dart.components[PhysicsBodyComponent.self] {
                        body.mode = .kinematic
                        dart.components.set(body)
                    }
                    dart.components.remove(CollisionComponent.self)

                    state.isStuck = true
                    dart.components.set(state)

                    let ringIndex = Int(hitRing.name.split(separator: "_")[1]) ?? 0
                    let points = (5 - ringIndex) * 10
                    print("Treffer Ring \(ringIndex), Punkte: \(points)")
                    
                    resetFlag = false
                }

                
                // --- Throw / Drop ---
                _ = content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                    guard
                        let model = event.entity as? ModelEntity,
                        model.name == "Dart"
                    else { return }

                    let velocity =
                        model.components[VelocityTrackingComponent.self]?.linearVelocity ?? .zero

                    let speed = length(velocity)
                    let throwThreshold: Float = 0.25

                    model.components.remove(ManipulationComponent.self)
                    model.components.remove(InputTargetComponent.self)

                    if var body = model.components[PhysicsBodyComponent.self] {
                        body.mode = .dynamic
                        body.linearDamping = speed < throwThreshold ? 0.8 : 0.05
                        body.angularDamping = speed < throwThreshold ? 8.0 : 6.0
                        model.components.set(body)
                    }

                    var motion = PhysicsMotionComponent()
                    motion.linearVelocity = SIMD3<Float>(0, 2.0, -4.5)
                    model.components.set(motion)
                    model.components.remove(VelocityTrackingComponent.self)
                }
                


            } update: { content in
                // --- Reset check ---
                if resetFlag {
                    // Alle alten Darts löschen
                    for dart in darts {
                        dart.removeFromParent()
                    }
                    darts.removeAll()
                    
                    // neue darts erstellen
                    for i in 0..<3 {
                        let dart = createDart()
                        dart.position = SIMD3(-0.1 + Float(i) * 0.1, 0.85, -0.6)
                        darts.append(dart)
                        content.add(dart)
                    }
                    resetFlag = false

                }

                // --- bestehende Update-Logik ---
                for entity in content.entities {
                    guard entity.name == "Dart",
                          var state = entity.components[DartStateComponent.self]
                    else { continue }
                    
                    state.wasHeld = entity.components[ManipulationComponent.self] != nil
                    content.entities.first { $0.id == entity.id }?
                        .components.set(state)
                }
            }

            // MARK: Reset Button
            
            Button("Reset") {
                resetFlag = true
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.trailing, 20)
            .padding(.top, 20)
            

                    }
                }
            }
    


#Preview {
    ImmersiveView()
        .environment(AppModel())
}
