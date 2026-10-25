import CoreGraphics

/// Owns a renderer + simulation pair and keeps them consistent as the
/// settings or the drawing surface change. Every host (screen saver view,
/// live preview, snapshot tool) drives the effect through this one type.
final class MatrixScene {
    /// How often hosts advance and redraw. Motion is time-based (`advance(by:)`),
    /// so this only affects smoothness, not speed.
    static let frameInterval: Double = 1.0 / 30

    private(set) var settings: MatrixSettings
    private let fontScale: CGFloat
    private let seed: UInt64?
    private var renderer: MatrixRenderer
    private var simulation: RainSimulation?
    private var elapsed: Double = 0

    /// - Parameters:
    ///   - fontScale: shrinks glyphs for small surfaces like the System Settings thumbnail.
    ///   - seed: fixed seed for reproducible output; `nil` for a random one.
    init(settings: MatrixSettings, fontScale: CGFloat = 1, seed: UInt64? = nil) {
        self.settings = settings
        self.fontScale = fontScale
        self.seed = seed
        renderer = MatrixRenderer(settings: settings, scale: fontScale)
    }

    func apply(_ newSettings: MatrixSettings) {
        guard newSettings != settings else { return }
        let needsNewGrid = newSettings.fontName != settings.fontName
            || newSettings.fontSize != settings.fontSize
            || newSettings.glyphStyle != settings.glyphStyle
            || newSettings.glidingMotion != settings.glidingMotion
        settings = newSettings
        renderer = MatrixRenderer(settings: newSettings, scale: fontScale)
        if needsNewGrid {
            simulation = nil
        } else {
            simulation?.settings = newSettings
        }
    }

    func advance(by dt: Double) {
        elapsed += dt
        simulation?.step(dt)
    }

    func draw(in context: CGContext, size: CGSize) {
        let simulation = simulation(for: size)
        renderer.draw(simulation, in: context, size: size, time: elapsed)
    }

    /// Returns the simulation for `size`, rebuilding it if the grid changed.
    @discardableResult
    func simulation(for size: CGSize) -> RainSimulation {
        let grid = renderer.gridSize(for: size)
        if let simulation, simulation.columns == grid.columns, simulation.rows == grid.rows,
           simulation.glyphCount == renderer.atlas.entries.count {
            return simulation
        }
        let fresh = RainSimulation(
            columns: grid.columns,
            rows: grid.rows,
            glyphCount: renderer.atlas.entries.count,
            settings: settings,
            seed: seed ?? UInt64.random(in: .min ... .max)
        )
        simulation = fresh
        return fresh
    }
}
