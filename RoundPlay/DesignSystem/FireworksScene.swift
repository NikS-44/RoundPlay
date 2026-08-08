import SpriteKit
import UIKit

/// A short, transparent fireworks show that launches from the top of the screen and
/// bursts into gravity-affected, glowing spark particles. Self-cleans after the show.
final class FireworksScene: SKScene {

    private var hasLaunched = false

    private static let palette: [SKColor] = [
        SKColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1), // gold
        SKColor(red: 1.00, green: 0.42, blue: 0.46, alpha: 1), // coral
        SKColor(red: 0.40, green: 0.85, blue: 0.95, alpha: 1), // sky
        SKColor(red: 0.55, green: 0.95, blue: 0.60, alpha: 1), // mint
        SKColor(red: 0.80, green: 0.60, blue: 1.00, alpha: 1), // violet
        SKColor(red: 1.00, green: 0.65, blue: 0.30, alpha: 1), // tangerine
        SKColor(red: 1.00, green: 0.55, blue: 0.85, alpha: 1)  // pink
    ]

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        view.allowsTransparency = true
        view.backgroundColor = .clear
        view.isOpaque = false
        physicsWorld.gravity = CGVector(dx: 0, dy: -2.5)
        attemptLaunch()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        attemptLaunch()
    }

    /// Launch once we actually have a real size (didMove can fire before sizing).
    private func attemptLaunch() {
        guard !hasLaunched, size.width > 1, size.height > 1 else { return }
        hasLaunched = true
        launchShow()
    }

    private func launchShow() {
        let count = 3
        for i in 0..<count {
            let delay = Double(i) * 0.34
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in self?.launchRocket() }
            ]))
        }
    }

    private func launchRocket() {
        let startX = CGFloat.random(in: size.width * 0.18 ... size.width * 0.82)
        let start = CGPoint(x: startX, y: size.height + 12)
        let burstPoint = CGPoint(
            x: startX + CGFloat.random(in: -36...36),
            y: CGFloat.random(in: size.height * 0.56 ... size.height * 0.82)
        )
        let color = Self.palette.randomElement() ?? .white

        let rocket = SKShapeNode(circleOfRadius: 2.5)
        rocket.fillColor = color
        rocket.strokeColor = .clear
        rocket.glowWidth = 4
        rocket.position = start
        rocket.zPosition = 1
        addChild(rocket)

        // A faint trail as it climbs in.
        let trail = SKEmitterNode()
        trail.particleTexture = Self.sparkTexture
        trail.particleBirthRate = 220
        trail.particleLifetime = 0.35
        trail.particleColor = color
        trail.particleColorBlendFactor = 1
        trail.particleBlendMode = .add
        trail.particleAlpha = 0.7
        trail.particleAlphaSpeed = -2.0
        trail.particleScale = 0.16
        trail.particleScaleSpeed = -0.3
        trail.particleSpeed = 8
        trail.emissionAngle = .pi / 2
        trail.emissionAngleRange = .pi * 2
        rocket.addChild(trail)

        let travel = SKAction.move(to: burstPoint, duration: 0.55)
        travel.timingMode = .easeOut
        rocket.run(.sequence([
            travel,
            .run { [weak self] in
                trail.particleBirthRate = 0
                self?.burst(at: burstPoint, color: color)
            },
            .removeFromParent()
        ]))
    }

    private func burst(at point: CGPoint, color: SKColor) {
        let emitter = SKEmitterNode()
        emitter.position = point
        emitter.zPosition = 2
        emitter.particleTexture = Self.sparkTexture
        emitter.numParticlesToEmit = 90
        emitter.particleBirthRate = 6000
        emitter.particleLifetime = 1.5
        emitter.particleLifetimeRange = 0.6
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = 240
        emitter.particleSpeedRange = 100
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -0.7
        emitter.particleScale = 0.34
        emitter.particleScaleRange = 0.18
        emitter.particleScaleSpeed = -0.12
        emitter.yAcceleration = -200
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBlendMode = .add
        addChild(emitter)
        emitter.run(.sequence([
            .wait(forDuration: 2.2),
            .removeFromParent()
        ]))

        // A quick central flash for punch.
        let flash = SKShapeNode(circleOfRadius: 7)
        flash.position = point
        flash.fillColor = .white
        flash.strokeColor = .clear
        flash.glowWidth = 8
        flash.blendMode = .add
        flash.zPosition = 3
        addChild(flash)
        flash.run(.sequence([
            .group([
                .scale(to: 2.4, duration: 0.22),
                .fadeOut(withDuration: 0.22)
            ]),
            .removeFromParent()
        ]))
    }

    /// Soft radial dot used (tinted, additive) for every spark.
    static let sparkTexture: SKTexture = {
        let dimension: CGFloat = 18
        let size = CGSize(width: dimension, height: dimension)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: dimension / 2, y: dimension / 2)
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            cg.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: dimension / 2,
                options: []
            )
        }
        return SKTexture(image: image)
    }()
}
