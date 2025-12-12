//
//  ImmersiveView.swift
//  darts
//
//  Created by Sebastian Buresch on 21.11.25.
//

import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

struct ImmersiveView: View {

    var body: some View {
        RealityView { content in
            // MARK: - Dartboard laden
            if let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle),
               let dartboard = scene.findEntity(named: "Dartboard") {

                // Anchor im Raum (frei)
                
                
                var manipulationComponent = ManipulationComponent()
                manipulationComponent.releaseBehavior = .stay
                manipulationComponent.dynamics.scalingBehavior = .none
                dartboard.components.set(manipulationComponent)
                
                dartboard.position = SIMD3(x: 0, y: 1.2, z: -1.0)
                
                // Dartboard als Kind hinzufügen
                
                content.add(dartboard)
            }
            // MARK: - Dart vor dem Nutzer hinzufügen
            do {
                let radius: Float = 0.01   // 1 cm
                let height: Float = 0.15   // 15 cm
                let mesh = MeshResource.generateCylinder(height: height, radius: radius)

                var material = SimpleMaterial(color: .red, isMetallic: true)
                material.roughness = .float(0.3)
                material.metallic = .float(0.6)

                let dart = ModelEntity(mesh: mesh, materials: [material])

                // Positioniere den Dart ca. 1 Meter vor dem Nutzer auf Schulterhöhe
                dart.position = [0, 1.4, -1.0]
                dart.orientation = simd_quatf(angle: .pi / 10, axis: [1, 0, 0])

                // Physik + Dämpfung
                var body = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .dynamic)
                body.linearDamping = 0.1
                body.angularDamping = 5.0
                body.isAffectedByGravity = false
                dart.components.set(body)

                // Kollision als Kapsel
                dart.components.set(
                    CollisionComponent(
                        shapes: [ShapeResource.generateCapsule(height: height, radius: radius)]
                    )
                )

                // Direkt zur Szene hinzufügen
                content.add(dart)
            }
        }
//        .overlay(alignment: .bottom) {
//            // UI/Controls zum Werfen von Darts
//            DartThrowView()
//                .padding()
//        }
    }
}

#Preview {
    ImmersiveView()
        .environment(AppModel())
}
