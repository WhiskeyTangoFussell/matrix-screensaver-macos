import AppKit

/// Builds and runs the "Options…" sheet shown from System Settings.
///
/// The UI is constructed in code (no nib) and edits a working copy of the
/// settings; a live preview reflects every change before it is saved.
@MainActor
final class ConfigureSheetController: NSObject {
    let window: NSWindow

    private var settings: MatrixSettings
    private let onSave: (MatrixSettings) -> Void
    private let onCancel: () -> Void

    private let preview: MatrixPreviewView
    private let fontPopup = NSPopUpButton()
    private let glyphPopup = NSPopUpButton()
    private let colorPopup = NSPopUpButton()
    private let fontSizeSlider = LabeledSlider(range: MatrixSettings.fontSizeRange, format: "%.0f pt")
    private let speedSlider = LabeledSlider(range: MatrixSettings.levelRange)
    private let speedSpreadSlider = LabeledSlider(range: MatrixSettings.spreadRange, step: 25, format: "+%.0f%%")
    private let densitySlider = LabeledSlider(range: MatrixSettings.levelRange, step: 0.5, format: "%.1f")
    private let trailSlider = LabeledSlider(range: MatrixSettings.levelRange)
    private let lengthVarianceSlider = LabeledSlider(range: MatrixSettings.varianceRange, step: 10, format: "±%.0f%%")
    private let mutationSlider = LabeledSlider(range: MatrixSettings.mutationRange)
    private let glideCheckbox = NSButton(checkboxWithTitle: "Gliding motion", target: nil, action: nil)
    private let brightHeadsCheckbox = NSButton(checkboxWithTitle: "Bright white heads", target: nil, action: nil)
    private let fadeCheckbox = NSButton(checkboxWithTitle: "Fade trails", target: nil, action: nil)
    private let glowCheckbox = NSButton(checkboxWithTitle: "Glow", target: nil, action: nil)
    private let blendCheckbox = NSButton(checkboxWithTitle: "Blend colors along streams", target: nil, action: nil)

    private var fontNames: [String] = []

    init(settings: MatrixSettings,
         onSave: @escaping (MatrixSettings) -> Void,
         onCancel: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        preview = MatrixPreviewView(settings: settings, fontScale: 0.75)
        // Sized to fit its layout in buildInterface().
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        super.init()
        window.title = "Matrix Options"
        buildInterface()
        populate()
    }

    // MARK: - Layout

    private func buildInterface() {
        populateMenus()

        let effects = NSStackView(views: [glideCheckbox, brightHeadsCheckbox, fadeCheckbox, glowCheckbox, blendCheckbox])
        effects.orientation = .vertical
        effects.alignment = .leading
        effects.spacing = 6

        let grid = NSGridView(views: [
            [label("Font:"), fontPopup],
            [label("Size:"), fontSizeSlider],
            [label("Characters:"), glyphPopup],
            [label("Color:"), colorPopup],
            [label("Speed:"), speedSlider],
            [label("Speed variance:"), speedSpreadSlider],
            [label("Density:"), densitySlider],
            [label("Trail length:"), trailSlider],
            [label("Length variance:"), lengthVarianceSlider],
            [label("Glyph changes:"), mutationSlider],
            [label("Effects:"), effects],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        let effectsRow = grid.row(at: grid.numberOfRows - 1)
        effectsRow.yPlacement = .top
        effectsRow.rowAlignment = .none
        grid.column(at: 1).width = 260

        for control in [fontPopup, glyphPopup, colorPopup] {
            control.target = self
            control.action = #selector(controlChanged)
        }
        for slider in [fontSizeSlider, speedSlider, speedSpreadSlider, densitySlider, trailSlider, lengthVarianceSlider, mutationSlider] {
            slider.onChange = { [weak self] in self?.controlChanged() }
        }
        for checkbox in [glideCheckbox, brightHeadsCheckbox, fadeCheckbox, glowCheckbox, blendCheckbox] {
            checkbox.target = self
            checkbox.action = #selector(controlChanged)
        }

        let defaultsButton = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let okButton = NSButton(title: "OK", target: self, action: #selector(save))
        okButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [defaultsButton, spacer, cancelButton, okButton])

        preview.translatesAutoresizingMaskIntoConstraints = false
        let body = NSStackView(views: [grid, preview])
        body.alignment = .top
        body.spacing = 20

        let root = NSStackView(views: [body, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: body.widthAnchor),
            preview.widthAnchor.constraint(equalToConstant: 260),
            preview.heightAnchor.constraint(equalTo: grid.heightAnchor),
        ])
        window.contentView = content
        // System Settings sizes the sheet itself; never let it squeeze the
        // controls below the size they need.
        window.setContentSize(content.fittingSize)
        window.contentMinSize = content.fittingSize
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func populateMenus() {
        let named = NSFontManager.shared.availableFonts
            .filter { !$0.hasPrefix(".") }
            .compactMap { name in NSFont(name: name, size: 12) }
            .filter(Self.hasMonospacedText)
            .map { ($0.fontName, $0.displayName ?? $0.fontName) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }

        fontNames = [MatrixSettings.systemMonospacedFontName] + named.map(\.0)
        fontPopup.removeAllItems()
        fontPopup.addItem(withTitle: "System Monospaced (SF Mono)")
        for (_, display) in named { fontPopup.addItem(withTitle: display) }
        if !fontNames.contains(settings.fontName) {
            fontNames.append(settings.fontName)
            fontPopup.addItem(withTitle: settings.fontName)
        }

        glyphPopup.removeAllItems()
        glyphPopup.addItems(withTitles: GlyphStyle.allCases.map(\.displayName))

        colorPopup.removeAllItems()
        for color in MatrixColor.allCases {
            colorPopup.addItem(withTitle: color.displayName)
            colorPopup.lastItem?.image = Self.swatch(for: color)
        }
    }

    private func populate() {
        fontPopup.selectItem(at: fontNames.firstIndex(of: settings.fontName) ?? 0)
        glyphPopup.selectItem(at: GlyphStyle.allCases.firstIndex(of: settings.glyphStyle) ?? 0)
        colorPopup.selectItem(at: MatrixColor.allCases.firstIndex(of: settings.color) ?? 0)
        fontSizeSlider.value = settings.fontSize
        speedSlider.value = settings.speed
        speedSpreadSlider.value = settings.speedSpread
        densitySlider.value = settings.density
        trailSlider.value = settings.trailLength
        lengthVarianceSlider.value = settings.lengthVariance
        mutationSlider.value = settings.mutationRate
        glideCheckbox.state = settings.glidingMotion ? .on : .off
        brightHeadsCheckbox.state = settings.brightHeads ? .on : .off
        fadeCheckbox.state = settings.fadeTrails ? .on : .off
        glowCheckbox.state = settings.glow ? .on : .off
        blendCheckbox.state = settings.blendColors ? .on : .off
        updateBlendAvailability()
        preview.apply(settings)
    }

    // MARK: - Actions

    @objc private func controlChanged() {
        settings.fontName = fontNames[max(fontPopup.indexOfSelectedItem, 0)]
        settings.glyphStyle = GlyphStyle.allCases[max(glyphPopup.indexOfSelectedItem, 0)]
        settings.color = MatrixColor.allCases[max(colorPopup.indexOfSelectedItem, 0)]
        settings.fontSize = fontSizeSlider.value
        settings.speed = speedSlider.value
        settings.speedSpread = speedSpreadSlider.value
        settings.density = densitySlider.value
        settings.trailLength = trailSlider.value
        settings.lengthVariance = lengthVarianceSlider.value
        settings.mutationRate = mutationSlider.value
        settings.glidingMotion = glideCheckbox.state == .on
        settings.brightHeads = brightHeadsCheckbox.state == .on
        settings.fadeTrails = fadeCheckbox.state == .on
        settings.glow = glowCheckbox.state == .on
        settings.blendColors = blendCheckbox.state == .on
        updateBlendAvailability()
        preview.apply(settings)
    }

    /// Blending only means something for multi-color families.
    private func updateBlendAvailability() {
        blendCheckbox.isEnabled = if case .families = settings.color.scheme { true } else { false }
    }

    @objc private func restoreDefaults() {
        settings = MatrixSettings()
        populate()
    }

    @objc private func save() {
        onSave(settings)
        dismiss()
    }

    @objc private func cancel() {
        onCancel()
        dismiss()
    }

    private func dismiss() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }

    /// True when letters and digits share one advance width. Broader than
    /// `isFixedPitch`, which rejects fonts like Nerd Font "NF" builds whose
    /// icon glyphs are double-width even though their text is monospaced.
    private static func hasMonospacedText(_ font: NSFont) -> Bool {
        if font.isFixedPitch { return true }
        let ctFont = font as CTFont
        var units = Array("iMW0.".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &units, &glyphs, units.count) else { return false }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyphs, &advances, glyphs.count)
        return advances.allSatisfy { abs($0.width - advances[0].width) < 0.01 }
    }

    // MARK: - Swatches

    private static func swatch(for color: MatrixColor) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 12), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            let stops: [RGB] = switch color.scheme {
            case .solid(let rgb): [rgb, rgb]
            case .rainbow: (0...6).map { RGB.hue(CGFloat($0) / 6) }
            case .families(let families): families.map { $0[1] }
            }
            let nsColors = stops.map { NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) }
            NSGradient(colors: nsColors)?.draw(in: path, angle: 0)
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
    }
}

/// A slider with a trailing value readout.
@MainActor
private final class LabeledSlider: NSStackView {
    var onChange: (() -> Void)?
    private let slider: NSSlider
    private let readout = NSTextField(labelWithString: "")
    private let format: String

    var value: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = newValue; updateReadout() }
    }

    init(range: ClosedRange<Double>, step: Double = 1, format: String = "%.0f") {
        self.format = format
        slider = NSSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        super.init(frame: .zero)
        slider.allowsTickMarkValuesOnly = true
        slider.numberOfTickMarks = Int((range.upperBound - range.lowerBound) / step) + 1
        slider.tickMarkPosition = .below
        slider.target = self
        slider.action = #selector(sliderMoved)
        readout.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        readout.alignment = .right
        // NSSlider has no intrinsic width, so without a required minimum any
        // host-driven resize (System Settings does this) collapses it to zero,
        // leaving an immovable knob next to the value.
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        slider.setContentCompressionResistancePriority(.required, for: .horizontal)
        readout.widthAnchor.constraint(equalToConstant: 56).isActive = true
        setViews([slider, readout], in: .leading)
        distribution = .fill
        spacing = 8
        updateReadout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func sliderMoved() {
        updateReadout()
        onChange?()
    }

    private func updateReadout() {
        readout.stringValue = String(format: format, slider.doubleValue)
    }
}
