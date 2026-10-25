// A tiny host for the screen saver view, so the effect and the options sheet
// can be exercised without installing anything.
//
//   make run         windowed: ⌘, opens Options, ⌘F toggles full screen, ⌘Q quits
//   make fullscreen  like the real screen saver: borderless over the whole main
//                    display, cursor hidden; any key, click or mouse move exits
//
// `--color <name>` (e.g. ARGS="--color rainbowSpectrum") overrides the saved
// color for this run only.

import AppKit

/// Borderless windows refuse key status by default, which would swallow the
/// key presses that should dismiss the full-screen preview.
final class SaverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    private let fullScreen: Bool
    private let colorOverride: MatrixColor?
    private var window: NSWindow!
    private var saverView: MatrixScreenSaverView!
    private var eventMonitor: Any?

    init(fullScreen: Bool, colorOverride: MatrixColor?) {
        self.fullScreen = fullScreen
        self.colorOverride = colorOverride
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if fullScreen {
            showFullScreen()
        } else {
            showWindowed()
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Windowed

    private func showWindowed() {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Matrix Screen Saver — Preview"
        window.collectionBehavior = .fullScreenPrimary
        attachSaverView(frame: frame)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.mainMenu = makeMenu()
    }

    @objc private func showOptions(_ sender: Any?) {
        guard window.attachedSheet == nil, let sheet = saverView.configureSheet else { return }
        window.beginSheet(sheet)
    }

    private func makeMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Options…", action: #selector(showOptions), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen), keyEquivalent: "f")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }

    // MARK: - Full screen (screen saver simulation)

    private func showFullScreen() {
        guard let screen = NSScreen.main else { return showWindowed() }
        window = SaverWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        window.setFrame(screen.frame, display: true)
        attachSaverView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.makeKeyAndOrderFront(nil)
        NSCursor.hide()

        // Ignore input briefly so the keystroke or click that launched us
        // doesn't immediately dismiss the preview.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismissOnUserActivity()
        }
    }

    private func dismissOnUserActivity() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            // Tiny mouse jitter shouldn't count, matching the real screen saver's tolerance.
            if event.type == .mouseMoved && abs(event.deltaX) + abs(event.deltaY) < 3 { return event }
            NSCursor.unhide()
            NSApp.terminate(nil)
            return nil
        }
    }

    // MARK: - Shared

    private func attachSaverView(frame: NSRect) {
        saverView = MatrixScreenSaverView(frame: frame, isPreview: false)
        saverView.autoresizingMask = [.width, .height]
        window.contentView = saverView
        if let colorOverride {
            var settings = SettingsStore.load()
            settings.color = colorOverride
            saverView.apply(settings)
        }
        saverView.startAnimation()
    }
}

let app = NSApplication.shared
let arguments = CommandLine.arguments
let colorOverride = arguments.firstIndex(of: "--color").flatMap { index -> MatrixColor? in
    guard index + 1 < arguments.count else { return nil }
    guard let color = MatrixColor(rawValue: arguments[index + 1]) else {
        print("unknown color; choose from: \(MatrixColor.allCases.map(\.rawValue).joined(separator: ", "))")
        exit(1)
    }
    return color
}
let delegate = PreviewAppDelegate(fullScreen: arguments.contains("--fullscreen"), colorOverride: colorOverride)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
