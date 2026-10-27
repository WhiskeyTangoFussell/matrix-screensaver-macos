import AppKit

/// A self-animating view used for the live preview inside the options sheet.
final class MatrixPreviewView: NSView {
    private let scene: MatrixScene
    private var timer: Timer?
    private var lastTick: CFTimeInterval?

    init(settings: MatrixSettings, fontScale: CGFloat) {
        scene = MatrixScene(settings: settings, fontScale: fontScale)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ settings: MatrixSettings) {
        let rateChanged = settings.frameRate != scene.settings.frameRate
        scene.apply(settings)
        if rateChanged { restartTimer() }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: scene.settings.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        scene.advance(by: min(now - (lastTick ?? now), 0.1))
        lastTick = now
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        scene.draw(in: context, size: bounds.size)
    }
}
