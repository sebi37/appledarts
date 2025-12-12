//
//  DartThrowView.swift
//  darts
//
//  Created by Sebastian Buresch on 12.12.25.
//

import SwiftUI
import RealityKit

struct DartThrowView: View {
    @State private var dartEntity: ModelEntity?
    var body: some View {
        RealityView { content in
            
            let anchor = AnchorEntity(.head)
            content.add(anchor)
            
            // Zylinder = Dart-Ersatz
            let mesh = MeshResource.generateCylinder(
                height: 0.15,
                radius: 0.01
            )
            
            let material = SimpleMaterial(
                color: .red,
                roughness: 0.3,
                isMetallic: true
            )
            
            let dart = ModelEntity(
                mesh: mesh,
                materials: [material]
            )
            
            Task { @MainActor in
                self.dartEntity = dart
            }
            
            // Position vor dem Nutzer
            dart.position = [0, 1.4, -0.5]
            dart.look(at: [0, 1.4, -2.0], from: dart.position, relativeTo: nil)
            
            // Physik
            var body = PhysicsBodyComponent(
                massProperties: .default,
                material: .default,
                mode: .dynamic
            )
            body.linearDamping = 0.1
            body.angularDamping = 5.0
            dart.components.set(body)
            
            dart.components.set(
                CollisionComponent(
                    shapes: [
                        ShapeResource.generateCapsule(
                            height: 0.15,
                            radius: 0.01
                        )
                    ]
                )
            )
            
            anchor.addChild(dart)
        }
        .gesture(
            TapGesture().onEnded {
                if let dart = dartEntity {
                    throwDart(dart: dart)
                }
            }
        )
    }
}

func throwDart(dart: ModelEntity) {
    let targetPosition = SIMD3<Float>(0, 1.4, -2.0)
    let direction = normalize(targetPosition - dart.position)
    let impulseStrength: Float = 2.5
    dart.applyLinearImpulse(direction * impulseStrength, relativeTo: nil)
}

