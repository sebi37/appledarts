//
//  ImmersiveView.swift
//  darts
//
//  Created by Sebastian Buresch on 21.11.25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)

                // Put skybox here.  See example in World project available at
                // https://developer.apple.com/
            
                // Test: sichtbaren Dart (Zylinder) zur Szene hinzufügen
                do {
                    let radius: Float = 0.01   // 1 cm
                    let height: Float = 0.15   // 15 cm
                    let mesh = MeshResource.generateCylinder(height: height, radius: radius)

                    var material = SimpleMaterial(color: .red, isMetallic: true)
                    material.roughness = .float(0.3)
                    material.metallic = .float(0.6)

                    let dart = ModelEntity(mesh: mesh, materials: [material])

                    // Positioniere den Dart vor der Scheibe (ggf. Z anpassen)
                    dart.position = [0, 1.4, -1.0]
                    dart.orientation = simd_quatf(angle: .pi / 10, axis: [1, 0, 0])

                    // Physik + Dämpfung
                    var body = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .dynamic)
                    body.linearDamping = 0.1
                    body.angularDamping = 5.0
                    dart.components.set(body)

                    // Kollision als Kapsel
                    dart.components.set(
                        CollisionComponent(
                            shapes: [ShapeResource.generateCapsule(height: height, radius: radius)]
                        )
                    )

                    immersiveContentEntity.addChild(dart)
                }
            }
        }
        .overlay(alignment: .bottom) {
            // Overlay with controls/UI for throwing darts
            DartThrowView()
                .padding()
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
