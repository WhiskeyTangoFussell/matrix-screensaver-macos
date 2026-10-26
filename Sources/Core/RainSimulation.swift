import Foundation

/// One falling stream of glyphs within a column.
///
/// `head` is the fractional row of the leading glyph and grows downward.
/// The characters always stay in the grid; the stream only decides which
/// cells are lit. Stepped mode lights whole rows `litHead - length + 1 ... litHead`;
/// gliding mode uses the fractional `head` so the light moves continuously.
struct RainStream {
    var head: Double
    var length: Int
    /// The lowest row that has received a fresh glyph. Stepped mode writes the
    /// row the head enters; gliding mode writes one row ahead so the cell the
    /// head is fading into already shows its new character.
    var litHead: Int
    /// Multiplier on the base fall speed.
    var speed: Double
    /// Random per-stream value hosts can use for variety (e.g. color choice).
    var variant: UInt16

    var tail: Double { head - Double(length) }
}

/// A vertical lane of the grid. Holds zero or more streams, newest last.
struct RainColumn {
    var streams: [RainStream] = []
    var cooldown: Double = 0
}

/// The terminal-style grid simulation: a glyph per cell, plus streams that
/// fall through the columns and decide which cells are lit.
///
/// It has no knowledge of fonts or drawing; glyphs are plain indices into
/// whatever glyph table the renderer owns.
final class RainSimulation {
    let columns: Int
    let rows: Int
    let glyphCount: Int
    var settings: MatrixSettings

    private(set) var cells: [UInt16]
    private(set) var lanes: [RainColumn]
    private var rng: SplitMix64

    init(columns: Int, rows: Int, glyphCount: Int, settings: MatrixSettings, seed: UInt64) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        self.glyphCount = max(glyphCount, 1)
        self.settings = settings
        rng = SplitMix64(seed: seed)
        // Placeholders first: Swift requires every property set before the
        // RNG-using helpers below can be called on `self`.
        cells = []
        lanes = []

        cells = (0..<(self.columns * self.rows)).map { _ in randomGlyph() }
        // Stagger the first wave so the screen fills in like cmatrix does.
        let stagger = max(settings.meanSpawnInterval, 1.5)
        lanes = (0..<self.columns).map { _ in
            RainColumn(cooldown: Double.random(in: 0...stagger, using: &rng))
        }
    }

    func glyph(column: Int, row: Int) -> Int {
        Int(cells[row * columns + column])
    }

    /// Advances the simulation by `dt` seconds.
    func step(_ dt: Double) {
        let distance = settings.rowsPerSecond * dt
        for c in lanes.indices {
            advance(column: c, by: distance, dt: dt)
        }
        mutate(dt: dt)
    }

    /// Fast-forwards until the rain reaches a steady state, so hosts start
    /// with a full screen instead of an empty one filling from the top.
    /// Long enough for the first (staggered) wave's slowest possible stream to
    /// fall all the way through, tail included.
    func prewarm() {
        let stagger = max(settings.meanSpawnInterval, 1.5)
        let longestTrail = Double(rows) * settings.meanTrailFraction * settings.lengthFactorRange.upperBound
        let seconds = min(stagger + (Double(rows) + longestTrail) / settings.rowsPerSecond, 120)
        let dt = MatrixScene.frameInterval
        for _ in 0..<Int(seconds / dt) { step(dt) }
    }

    // MARK: - Private

    private func advance(column c: Int, by distance: Double, dt: Double) {
        var lane = lanes[c]

        let gliding = settings.glidingMotion
        for i in lane.streams.indices {
            lane.streams[i].head += distance * lane.streams[i].speed
            let reached = Int(lane.streams[i].head.rounded(.down)) + (gliding ? 1 : 0)
            let previous = lane.streams[i].litHead
            if reached > previous {
                for row in (previous + 1)...reached where row < rows {
                    cells[row * columns + c] = randomGlyph()
                }
                lane.streams[i].litHead = reached
            }
        }
        lane.streams.removeAll { $0.tail >= Double(rows) }

        let topIsClear = lane.streams.last.map { $0.tail >= 1 } ?? true
        if topIsClear { lane.cooldown -= dt }
        if lane.cooldown <= 0 && topIsClear {
            var speed = Double.random(in: settings.speedFactorRange, using: &rng)
            if let ahead = lane.streams.last { speed = min(speed, maxFollowSpeed(behind: ahead)) }
            lane.streams.append(RainStream(
                // Gliding heads start one row up so the first cell fades in.
                head: gliding ? -1 : 0,
                length: randomLength(),
                litHead: -1,
                speed: speed,
                variant: .random(in: .min ... .max, using: &rng)
            ))
            lane.cooldown = randomExponential(mean: settings.meanSpawnInterval)
        }

        lanes[c] = lane
    }

    /// The fastest a new stream can go without reaching the tail of `ahead`
    /// before that tail leaves the screen. Faster followers are fine as long as
    /// the gap can't close in time. Assumes the new head starts at row 0;
    /// gliding heads start at −1, which only adds margin.
    private func maxFollowSpeed(behind ahead: RainStream) -> Double {
        let remaining = Double(rows) - ahead.tail     // rows until the tail exits
        guard remaining > 0 else { return .infinity }
        let gap = ahead.tail - 1                      // rows between new head and that tail
        return ahead.speed * (1 + gap / remaining)
    }

    private func mutate(dt: Double) {
        let expected = Double(cells.count) * settings.mutationsPerCellPerSecond * dt
        var count = Int(expected)
        if Double.random(in: 0..<1, using: &rng) < expected - Double(count) { count += 1 }
        for _ in 0..<count {
            cells[Int.random(in: 0..<cells.count, using: &rng)] = randomGlyph()
        }
    }

    private func randomGlyph() -> UInt16 {
        UInt16(Int.random(in: 0..<glyphCount, using: &rng))
    }

    private func randomLength() -> Int {
        let mean = Double(rows) * settings.meanTrailFraction
        return max(3, Int(mean * Double.random(in: settings.lengthFactorRange, using: &rng)))
    }

    private func randomExponential(mean: Double) -> Double {
        -mean * log(1 - Double.random(in: 0..<1, using: &rng))
    }
}

/// Small, fast, seedable generator so snapshots are reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
