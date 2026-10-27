import AppKit
import ScreenSaver

/// The bundle's principal class. The `@objc` name keeps it stable for
/// `NSPrincipalClass` in Info.plist regardless of the Swift module name.
@objc(MatrixScreenSaverView)
final class MatrixScreenSaverView: ScreenSaverView {
    private var scene: MatrixScene
    private var lastTick: CFTimeInterval?
    private var sheetController: ConfigureSheetController?
    /// Observer tokens; the closures capture `self` weakly, so these are
    /// simply retained for the life of the view.
    private var observers: [NSObjectProtocol] = []

    override init?(frame: NSRect, isPreview: Bool) {
        // The System Settings thumbnail is tiny; scale glyphs to match.
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let fontScale = isPreview ? max(frame.width / screenWidth, 0.25) : 1
        scene = MatrixScene(settings: SettingsStore.load(), fontScale: fontScale)
        super.init(frame: frame, isPreview: isPreview)
        finishInit()
    }

    required init?(coder: NSCoder) {
        scene = MatrixScene(settings: SettingsStore.load())
        super.init(coder: coder)
        finishInit()
    }

    private func finishInit() {
        animationTimeInterval = scene.settings.frameInterval
        observeNotifications()
    }

    /// Applies settings to this instance only, without saving them.
    func apply(_ settings: MatrixSettings) {
        scene.apply(settings)
        if animationTimeInterval != settings.frameInterval {
            animationTimeInterval = settings.frameInterval
        }
    }

    // MARK: - Animation

    override func startAnimation() {
        lastTick = nil
        super.startAnimation()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        // Clamp so a stall (sleep, display wake) doesn't teleport the rain.
        let dt = min(now - (lastTick ?? now), 0.1)
        lastTick = now
        scene.advance(by: dt)
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        scene.draw(in: context, size: bounds.size)
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let controller = ConfigureSheetController(settings: scene.settings) { [weak self] settings in
            SettingsStore.save(settings)
            self?.apply(settings)
            self?.sheetController = nil
        } onCancel: { [weak self] in
            self?.sheetController = nil
        }
        sheetController = controller
        return controller.window
    }

    // MARK: - Notifications

    private func observeNotifications() {
        // Another instance (e.g. on a second display) saved new settings.
        observers.append(NotificationCenter.default.addObserver(
            forName: SettingsStore.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(SettingsStore.load()) }
        })

        // Since macOS 14 the legacyScreenSaver host often never calls
        // stopAnimation() and keeps running hidden after the saver is
        // dismissed, burning CPU. Stop on the "willstop" broadcast and, for
        // full-screen instances, end the host process so it can't linger.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopAnimation()
                if !self.isPreview && Self.isHostedByLegacyScreenSaver {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
                }
            }
        })
    }

    private static var isHostedByLegacyScreenSaver: Bool {
        ProcessInfo.processInfo.processName.contains("legacyScreenSaver")
    }
}

/// Reads and writes settings in the screen saver's own defaults domain.
enum SettingsStore {
    static let moduleName = "com.fussell.MatrixScreenSaver"
    static let didChange = Notification.Name("MatrixScreenSaverSettingsDidChange")

    private static var defaults: UserDefaults {
        ScreenSaverDefaults(forModuleWithName: moduleName) ?? .standard
    }

    static func load() -> MatrixSettings {
        MatrixSettings(defaults: defaults)
    }

    static func save(_ settings: MatrixSettings) {
        settings.save(to: defaults)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
