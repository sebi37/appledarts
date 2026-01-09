import SwiftUI
import UIKit
import RealityKit
import RealityKitContent

// MARK: - Points for rings
struct RingPointsComponent: Component {
    var points: Int
}

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

    @AppStorage("Highscore") private var highscore: Int = 0

    @State private var darts: [ModelEntity] = []
    @State private var resetFlag = false

    // Game state (2 players, 3 rounds, 3 darts per turn)
    @State private var playerScores: [Int] = [0, 0]
    @State private var currentPlayer: Int = 0
    @State private var currentRound: Int = 1
    @State private var dartsThisTurn: Int = 0
    @State private var gameOver: Bool = false
    @State private var winnerText: String = ""

    // HUD state
    @State private var lastHitText: String = ""
    @State private var showBullseyeAnimation: Bool = false
    @State private var showWinnerAnimation: Bool = false
    @State private var winnerPulse: Bool = false

    // MARK: - Dart
    func createDart() -> ModelEntity {
        // Root = shaft (this entity gets physics + manipulation)
        let shaftLength: Float = 0.16
        let shaftRadius: Float = 0.004

        let shaftMaterial = SimpleMaterial(color: .darkGray, isMetallic: true)
        let dart = ModelEntity(
            mesh: .generateCylinder(height: shaftLength, radius: shaftRadius),
            materials: [shaftMaterial]
        )

        dart.name = "Dart"

        // Collision approximates the full dart length (shaft + tip)
        dart.components.set(
            CollisionComponent(
                shapes: [.generateCapsule(height: shaftLength + 0.05, radius: 0.01)]
            )
        )

        // Cylinder/cone are oriented along local +Y by default.
        // Rotate so the dart points toward world -Z (toward your board).
        dart.orientation = simd_quatf(
            angle: -.pi / 2,
            axis: SIMD3<Float>(1, 0, 0)
        )

        // Physics + interaction
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

        // ---------------------------
        // Visual-only parts (children)
        // ---------------------------

        // 1) Barrel rings (grip) near the front
        let ringMaterial = SimpleMaterial(color: .gray, isMetallic: true)
        let ringCount = 3
        let ringThickness: Float = 0.004
        let ringRadius: Float = shaftRadius * 1.55
        let ringStartY: Float = (shaftLength * 0.20)
        let ringSpacing: Float = 0.010

        for i in 0..<ringCount {
            let ring = ModelEntity(
                mesh: .generateCylinder(height: ringThickness, radius: ringRadius),
                materials: [ringMaterial]
            )
            ring.position = SIMD3<Float>(0, ringStartY + Float(i) * ringSpacing, 0)
            dart.addChild(ring)
        }

        // 2) Metal tip (cone) at the front (local +Y)
        let tipHeight: Float = 0.035
        let tipRadius: Float = 0.0048
        let tip = ModelEntity(
            mesh: .generateCone(height: tipHeight, radius: tipRadius),
            materials: [SimpleMaterial(color: .lightGray, isMetallic: true)]
        )
        // Place along the shaft axis (local +Y)
        tip.position = SIMD3<Float>(0, (shaftLength / 2) + (tipHeight / 2) - 0.001, 0)
        dart.addChild(tip)

        // 3) Tail cap (small cylinder) at the back (local -Y)
        let tail = ModelEntity(
            mesh: .generateCylinder(height: 0.010, radius: shaftRadius * 1.25),
            materials: [SimpleMaterial(color: .black, isMetallic: false)]
        )
        tail.position = SIMD3<Float>(0, -(shaftLength / 2) + 0.005, 0)
        dart.addChild(tail)

        // 4) Flights (4 fins) at the back (local -Y)
        // Make fins like thin planes: thickness along Y, width in X, height in Z.
        let finWidth: Float = 0.040
        let finHeight: Float = 0.028
        let finThickness: Float = 0.0018
        let finMaterial = SimpleMaterial(color: .cyan, isMetallic: false)

        let finY: Float = -(shaftLength / 2) + 0.018
        let finSize = SIMD3<Float>(finWidth, finThickness, finHeight)

        for i in 0..<4 {
            let fin = ModelEntity(mesh: .generateBox(size: finSize), materials: [finMaterial])
            fin.position = SIMD3<Float>(0, finY, 0)
            // Rotate around the shaft axis (local Y) to create a cross (0°, 90°, 45°, 135°)
            let angle = Float(i) * (.pi / 2)
            fin.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
            dart.addChild(fin)
        }

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

        floor.name = "Floor" // Added name to identify

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

            // Physics Body statisch
            ring.components.set(
                PhysicsBodyComponent(
                    massProperties: .default,
                    material: .default,
                    mode: .static
                )
            )

            ring.components.set(RingPointsComponent(points: ringPoints[i]))
            ring.name = "Ring_\(i)"
            container.addChild(ring)
        }

        return container
    }

    // MARK: - View
    var body: some View {
        RealityView { content, attachments in
            content.add(createTable())
            content.add(createFloor())

            // 🎯 Target (Dartboard) in the world
            let target = createTargetMarker()
            target.name = "Target"
            content.add(target)

            // 🎯 Drei Darts
            for i in 0..<3 {
                let dart = createDart()
                dart.position = SIMD3(-0.1 + Float(i) * 0.1, 0.85, -0.6)
                darts.append(dart)
                content.add(dart)
            }

            // ✅ Scoreboard as a 3D attachment next to the dartboard
            if let hud = attachments.entity(for: "hud") {
                hud.name = "ScoreHUD"
                hud.position = SIMD3<Float>(0.38, 1.22, -1.05)
                hud.components.set(BillboardComponent())
                content.add(hud)
            }

            // 🎉 Bullseye animation as a 3D attachment above the dartboard
            if let bullseye = attachments.entity(for: "bullseye") {
                bullseye.name = "BullseyeFX"
                // Place it slightly above the board center
                bullseye.position = SIMD3<Float>(0.0, 1.45, -1.18)
                bullseye.components.set(BillboardComponent())
                content.add(bullseye)
            }

            // 🏆 Winner animation as a 3D attachment above the dartboard
            if let winnerFx = attachments.entity(for: "winner") {
                winnerFx.name = "WinnerFX"
                winnerFx.position = SIMD3<Float>(0.0, 1.62, -1.18)
                winnerFx.components.set(BillboardComponent())
                content.add(winnerFx)
            }

            // --- Collision Listener ---
            _ = content.subscribe(to: CollisionEvents.Began.self) { event in
                if gameOver { return }

                guard
                    let dart = event.entityA as? ModelEntity ?? event.entityB as? ModelEntity,
                    dart.name == "Dart"
                else { return }

                var state = dart.components[DartStateComponent.self] ?? DartStateComponent()
                if state.isStuck { return }

                let hitRing = (event.entityA as? ModelEntity)?.name.starts(with: "Ring_") == true
                    ? event.entityA as? ModelEntity
                    : (event.entityB as? ModelEntity)?.name.starts(with: "Ring_") == true
                        ? event.entityB as? ModelEntity
                        : nil
                let hitFloor = event.entityA.name == "Floor" || event.entityB.name == "Floor"
                let hitTable = event.entityA.name == "Table" || event.entityB.name == "Table"

                if let ring = hitRing {
                    // Dart auf Scheibe kleben lassen
                    dart.components.remove(PhysicsMotionComponent.self)
                    if var body = dart.components[PhysicsBodyComponent.self] {
                        body.mode = .kinematic
                        dart.components.set(body)
                    }
                    dart.components.remove(CollisionComponent.self)

                    state.isStuck = true
                    dart.components.set(state)

                    let points = ring.components[RingPointsComponent.self]?.points ?? 0
                    Task { @MainActor in
                        // Add points to current player
                        playerScores[currentPlayer] += points
                        lastHitText = points > 0 ? "+\(points)" : ""

                        // 🎉 Bullseye animation for 50 points
                        if points == 50 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                                showBullseyeAnimation = true
                            }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showBullseyeAnimation = false
                                }
                            }
                        }

                        // A dart is "used" once it sticks
                        dartsThisTurn += 1

                        // Turn ends after 3 darts
                        if dartsThisTurn >= 3 {
                            dartsThisTurn = 0

                            if currentPlayer == 0 {
                                currentPlayer = 1
                            } else {
                                currentPlayer = 0
                                currentRound += 1
                            }

                            // Clear board + respawn darts for next player/round
                            resetFlag = true

                            // Game ends after player 2 finishes round 3
                            if currentRound > 3 {
                                gameOver = true

                                if playerScores[0] > playerScores[1] {
                                    winnerText = "Spieler 1 gewinnt!"
                                } else if playerScores[1] > playerScores[0] {
                                    winnerText = "Spieler 2 gewinnt!"
                                } else {
                                    winnerText = "Unentschieden!"
                                }

                                // 🏆 Winner celebration (once)
                                if !showWinnerAnimation {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                        showWinnerAnimation = true
                                    }
                                    winnerPulse = false
                                    withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) {
                                        winnerPulse = true
                                    }

                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                                        withAnimation(.easeOut(duration: 0.35)) {
                                            showWinnerAnimation = false
                                        }
                                        winnerPulse = false
                                    }
                                }

                                // Persist best score achieved
                                let bestThisGame = max(playerScores[0], playerScores[1])
                                if bestThisGame > highscore {
                                    highscore = bestThisGame
                                }
                            }
                        }
                    }
                    print("Treffer \(ring.name), Punkte: \(ring.components[RingPointsComponent.self]?.points ?? 0)")
                } else if hitFloor || hitTable {
                    // Dart als stuck markieren
                    dart.components.remove(PhysicsMotionComponent.self)
                    if var body = dart.components[PhysicsBodyComponent.self] {
                        body.mode = .kinematic
                        dart.components.set(body)
                    }
                    dart.components.remove(CollisionComponent.self)

                    state.isStuck = true
                    dart.components.set(state)

                    Task { @MainActor in
                        lastHitText = "" // oder "0"
                        dartsThisTurn += 1
                        if dartsThisTurn >= 3 {
                            dartsThisTurn = 0
                            if currentPlayer == 0 {
                                currentPlayer = 1
                            } else {
                                currentPlayer = 0
                                currentRound += 1
                            }
                            resetFlag = true
                            if currentRound > 3 {
                                gameOver = true
                                if playerScores[0] > playerScores[1] {
                                    winnerText = "Spieler 1 gewinnt!"
                                } else if playerScores[1] > playerScores[0] {
                                    winnerText = "Spieler 2 gewinnt!"
                                } else {
                                    winnerText = "Unentschieden!"
                                }
                                if !showWinnerAnimation {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                        showWinnerAnimation = true
                                    }
                                    winnerPulse = false
                                    withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) {
                                        winnerPulse = true
                                    }
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                                        withAnimation(.easeOut(duration: 0.35)) {
                                            showWinnerAnimation = false
                                        }
                                        winnerPulse = false
                                    }
                                }
                                let bestThisGame = max(playerScores[0], playerScores[1])
                                if bestThisGame > highscore {
                                    highscore = bestThisGame
                                }
                            }
                        }
                    }
                    print("Pfeil verfehlt, Punkte: 0")
                    resetFlag = false
                    return
                }

                resetFlag = false
            }

            // --- Throw / Drop ---
            _ = content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                if gameOver { return }

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

        } update: { content, attachments in
            // --- Reset check ---
            if resetFlag {

                // 1) Alle Darts im Scene-Graph finden und entfernen (robust, auch wenn sie nicht im Array sind)
                func collectDarts(from entity: Entity, into list: inout [Entity]) {
                    if entity.name == "Dart" { list.append(entity) }
                    for child in entity.children {
                        collectDarts(from: child, into: &list)
                    }
                }

                var dartsToRemove: [Entity] = []
                for root in content.entities {
                    collectDarts(from: root, into: &dartsToRemove)
                }

                for e in dartsToRemove {
                    e.removeFromParent()
                }

                // 2) State-Array leeren und neue Darts erzeugen
                darts.removeAll()

                for i in 0..<3 {
                    let dart = createDart()
                    dart.position = SIMD3(-0.1 + Float(i) * 0.1, 0.85, -0.6)
                    darts.append(dart)
                    content.add(dart)
                }

                resetFlag = false
            }

            // Keep HUD parked next to the dartboard
            if let hud = content.entities.first(where: { $0.name == "ScoreHUD" }) {
                hud.position = SIMD3<Float>(0.38, 1.22, -1.05)
            }

            // Keep Bullseye FX parked above the dartboard
            if let fx = content.entities.first(where: { $0.name == "BullseyeFX" }) {
                fx.position = SIMD3<Float>(0.0, 1.45, -1.18)
            }

            // Keep Winner FX parked above the dartboard
            if let fx = content.entities.first(where: { $0.name == "WinnerFX" }) {
                fx.position = SIMD3<Float>(0.0, 1.62, -1.18)
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
        } attachments: {
            Attachment(id: "hud") {
                ZStack {
                    VStack(alignment: .leading, spacing: 12) {

                        Text("Runde \(min(currentRound, 3))/3")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        if gameOver {
                            Text(winnerText)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .bold()
                        } else {
                            Text("Spieler \(currentPlayer + 1) ist dran")
                                .font(.system(size: 23, weight: .semibold, design: .rounded))
                        }

                        Text("\(playerScores[currentPlayer])")
                            .font(.system(size: 90, weight: .heavy, design: .rounded))

                        HStack(spacing: 10) {
                            Text("P1: \(playerScores[0])")
                                .bold(!gameOver && currentPlayer == 0)
                            Text("P2: \(playerScores[1])")
                                .bold(!gameOver && currentPlayer == 1)
                        }
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Darts übrig: \(3 - dartsThisTurn)")
                            .font(.system(size: 20, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)

                        if !lastHitText.isEmpty {
                            Text(lastHitText)
                                .font(.title3)
                        }

                        Text("Highscore: \(highscore)")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Button("Neues Spiel") {
                            // Reset game state + clear darts/board
                            gameOver = false
                            winnerText = ""
                            playerScores = [0, 0]
                            currentPlayer = 0
                            currentRound = 1
                            dartsThisTurn = 0
                            lastHitText = ""
                            showBullseyeAnimation = false
                            showWinnerAnimation = false
                            winnerPulse = false
                            resetFlag = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.vertical, 6)

                        Button("Highscore zurücksetzen") {
                            highscore = 0
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.vertical, 6)
                    }
                    .padding(38)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
            }
            Attachment(id: "bullseye") {
                if showBullseyeAnimation {
                    Text("🎯 BULLSEYE!")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(.yellow)
                        .shadow(radius: 12)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Attachment(id: "winner") {
                if showWinnerAnimation {
                    WinnerCelebrationView(winnerText: winnerText, pulsing: winnerPulse)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}


// MARK: - Winner Celebration (Trophy + Confetti)
struct WinnerCelebrationView: View {
    let winnerText: String
    let pulsing: Bool

    @State private var confettiGo = false

    // Simple deterministic "random" offsets by index
    private func xOffset(_ i: Int) -> CGFloat {
        let v = (i * 37) % 120
        return CGFloat(v) - 60
    }

    private func rot(_ i: Int) -> Double {
        Double(((i * 53) % 60) - 30)
    }

    var body: some View {
        ZStack {
            // Confetti burst
            ForEach(0..<28, id: \.self) { i in
                Text(["🎉", "✨", "🎊" ][i % 3])
                    .font(.system(size: 28))
                    .offset(x: xOffset(i), y: confettiGo ? 140 : -40)
                    .rotationEffect(.degrees(confettiGo ? rot(i) * 4 : rot(i)))
                    .opacity(confettiGo ? 0.0 : 1.0)
                    .animation(
                        .easeOut(duration: 1.6)
                            .delay(Double(i) * 0.015),
                        value: confettiGo
                    )
            }

            // Trophy + text
            VStack(spacing: 10) {
                Text("🏆")
                    .font(.system(size: 78))

                Text(winnerText)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("GG Future-Taylor?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .opacity(0.9)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 14)
            .scaleEffect(pulsing ? 1.06 : 0.96)
            .rotationEffect(.degrees(pulsing ? 2.0 : -2.0))
            .animation(.easeInOut(duration: 0.22), value: pulsing)
        }
        .onAppear {
            confettiGo = false
            // trigger burst next runloop so transitions are visible
            DispatchQueue.main.async {
                confettiGo = true
            }
        }
    }
}

#Preview {
    ImmersiveView()
        .environment(AppModel())
}

