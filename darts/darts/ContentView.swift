//
//  ContentView.swift
//  darts
//
//  Created by Sebastian Buresch on 21.11.25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {

    @State private var enlarge = false

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                _ = scene.findEntity(named: "SegmentModel")
                if let segment = scene.findEntity(named: "SegmentModel"),
                   let meshEntity = segment.findEntity(named: "Körper1"),
                   let model = meshEntity.components[ModelComponent.self] {

                    do {
                        let convex = try await ShapeResource.generateConvex(from: model.mesh)
                        segment.components.set(
                            CollisionComponent(
                                shapes: [convex],
                                isStatic: true
                            )
                        )
                    } catch {
                        print("Collision generation failed: \(error)")
                    }
                }

                content.add(scene)
                    
            }
        } update: { content in
            // Update the RealityKit content when SwiftUI state changes
            if let scene = content.entities.first {
                let uniformScale: Float = enlarge ? 1.4 : 1.0
                scene.transform.scale = [uniformScale, uniformScale, uniformScale]
            }
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { _ in
            enlarge.toggle()
        })
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                VStack (spacing: 12) {
                    Button {
                        enlarge.toggle()
                    } label: {
                        Text(enlarge ? "Reduce RealityView Content" : "Enlarge RealityView Content")
                    }
                    .animation(.none, value: 0)
                    .fontWeight(.semibold)

                    ToggleImmersiveSpaceButton()
                }
            }
        }
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environment(AppModel())
}
