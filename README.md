# Matrix Screen Saver for macOS

A native macOS screen saver that recreates the look and behavior of the classic
terminal program **cmatrix**, written in modern Swift with AppKit, Core Text and
the ScreenSaver framework.

This is a **clean-room implementation**. No cmatrix source code was used or
ported. cmatrix's *observable behavior* (falling columns of random characters,
bright leading glyphs, characters that flicker in place, async column speeds)
served as the spec, and everything was designed fresh for macOS.

---

## Contents

- [Features](#features)
- [Install](#install)
- [Requirements](#requirements)
- [Build from source](#build-from-source)
- [Options reference](#options-reference)
- [Project layout](#project-layout)
- [Architecture](#architecture)
- [How the rain works](#how-the-rain-works)
- [Rendering pipeline](#rendering-pipeline)
- [macOS screen saver quirks handled](#macos-screen-saver-quirks-handled)
- [Development workflow](#development-workflow)
- [Conventions](#conventions)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [Changelog](#changelog)
- [License](#license)

---

## Features

- 100% Swift (Swift 6 language mode, strict concurrency), no Objective-C, no nibs.
- Universal binary (Apple silicon + Intel), ad-hoc signed.
- Builds with **Command Line Tools only**. No Xcode project is needed; a `Makefile` drives `swiftc`.
- Options sheet with a **live animated preview**.
- **21 color modes**: Tokyo Night (Neon), Rainbow Spectrum (Pastel), Rainbow
  Spectrum (Vivid), Thinkpad, Midnight and Blackout, all multi-color and blendable along streams, plus 15 solid
  colors and an animated Rainbow.
- **8 character sets**: Classic (cmatrix's ASCII, default), Hexadecimal, Binary,
  Unicode (letters from nine writing systems), Katakana, Katakana (Combined) with
  Latin letters and symbols, Katakana (Enhanced) with normal and mirrored glyphs,
  and Katakana (Film) with mirrored glyphs like the movie.
- Any installed monospaced font (default CaskaydiaCove NF Bold), 8–48 pt.
- Adjustable speed and speed variance, density, trail length and length variance,
  and glyph-change rate.
- **Gliding motion**: the light moves smoothly over fixed characters (or the classic
  stepped cmatrix look).
- Toggles for bright white heads, fading trails, glow, and blending colors along streams.
- **Starts full**: the rain is fast-forwarded to a steady state before the first
  frame, so the screen is already filled when the saver starts.
- Fast: about 2–7 ms for a full Retina frame on Apple silicon, glow included.
- Multi-display aware: saving options updates every running instance.

## Install

Needs macOS 15 Sequoia or later and Apple's Command Line Tools (the installer
offers to install them). Both methods build the saver on your Mac, so Gatekeeper
doesn't block it even though it isn't Developer ID signed.

**One-line installer**

```sh
curl -fsSL https://raw.githubusercontent.com/WhiskeyTangoFussell/matrix-screensaver-macos/main/install.sh | bash
```

It downloads the latest release, runs `make install` and cleans up. Run it again
to update. To remove it:

```sh
curl -fsSL https://raw.githubusercontent.com/WhiskeyTangoFussell/matrix-screensaver-macos/main/install.sh | bash -s -- --uninstall
```

To install the current development version instead of the latest release, end
the command with `| MATRIX_REF=main bash`.

**Homebrew**

```sh
brew tap whiskeytangofussell/tap
brew trust --formula whiskeytangofussell/tap/matrix-screensaver
brew install whiskeytangofussell/tap/matrix-screensaver
cp -R "$(brew --prefix matrix-screensaver)/MatrixScreenSaver.saver" ~/Library/Screen\ Savers/
```

Homebrew only loads formulae from third-party taps you've trusted, hence the
second line. Homebrew can't write to `~/Library`, so the last line activates the
saver (brew prints it after installing). Run it again after `brew upgrade`.

Then open **System Settings → Screen Saver**, choose **Matrix**, and click
**Options…** to customize it.

## Requirements

| | |
|---|---|
| Runs on | macOS 15 Sequoia or later. |
| Builds with | Swift 6 toolchain. Xcode **or** just the Command Line Tools (`xcode-select --install`). |

The deployment target is set by `MIN_MACOS` in the `Makefile` and
`LSMinimumSystemVersion` in `Resources/Info.plist`. Keep the two in sync.

## Build from source

```sh
git clone https://github.com/WhiskeyTangoFussell/matrix-screensaver-macos.git
cd matrix-screensaver-macos

make build      # → build/MatrixScreenSaver.saver (universal, ad-hoc signed)
make install    # copies to ~/Library/Screen Savers and restarts the saver host
make uninstall  # removes it again

make run        # windowed preview app: ⌘, Options · ⌘F full screen · ⌘Q quit
make fullscreen # screen-saver-style preview: borderless, cursor hidden; any key/click/mouse move exits
make fullscreen ARGS="--color rainbowSpectrum"   # override the color for one run (also works with run)
make snapshot ARGS="out.png 1440 900 cyan katakana 6"   # headless PNG render
make thumbnails # regenerate the System Settings picker thumbnails in Resources/
make render-baseline && make render-check   # prove a refactor changed no pixels (see Development workflow)
make clean
```

> `make install` runs `killall legacyScreenSaver` and quits System Settings.
> Without that, macOS keeps the previously loaded binary in memory and you'd see stale code.

Snapshot arguments: `out.png [width] [height] [color] [glyphStyle] [seconds]`.
Color and style use the persisted raw values (`matrixGreen`, `rainbow`, `katakana`, …).
Running `build/snapshot` with no arguments lists them.

## Options reference

| Option | Range / values | Default | Effect |
|---|---|---|---|
| Font | System Monospaced (SF Mono) + every installed font whose letters/digits are fixed-width (includes Nerd Font "NF" builds that macOS doesn't flag as fixed-pitch) | CaskaydiaCove NF Bold (`CaskaydiaCoveNF-Bold`) | Falls back to SF Mono if the font isn't installed. Pick weight by choosing the face (Bold, SemiBold…). Characters the font lacks (e.g. katakana) come from a system fallback font automatically. |
| Size | 8–48 pt | 16 | Glyph size. The System Settings thumbnail scales this down to fit. |
| Characters | Classic · Hexadecimal · Binary · Unicode · Katakana · Katakana (Combined) · Katakana (Enhanced) · Katakana (Film) | Classic | **Classic** (`classic`) is cmatrix's printable ASCII (`!`…`~`). **Hexadecimal** (`hex`) is `0–9 A–F`; **Binary** (`binary`) is `0 1`. **Unicode** (`unicode`) mixes ~600 standalone letters from Latin (accented), Greek, Cyrillic, Hebrew, Arabic, Armenian, Georgian and Runic with katakana and digits; combining marks are excluded by Unicode category. **Katakana** (`katakana`) uses half-width forms U+FF66–FF9D plus digits. **Combined** (`mixed`) adds Latin capitals and symbols. **Enhanced** (`katakanaEnhanced`) adds a left-right mirrored copy of every katakana, so both orientations rain together. **Film** (`katakanaFilm`) is mirrored katakana with normal digits and the symbols `:."=*+-<>\|¦`, like the movie. |
| Color | **Tokyo Night (Neon)**, **Rainbow Spectrum (Pastel)**, **Rainbow Spectrum (Vivid)**, **Thinkpad**, **Midnight**, **Blackout**, Matrix Green, Emerald, Lime, Mint, Cyan, Ice Blue, Azure, Violet, Magenta, Pink, Red, Orange, Amber, Gold, White, **Rainbow** | Tokyo Night (Neon) | Tokyo Night uses 9 neon colors: pink `#FF9ED8 #FF4FAE #C2187A`, purple `#CDA8FF #A25CFF #6C2BD9`, blue `#8CD5FF #4D8DFF #2A52D6` (light/medium/dark). Rainbow Spectrum (Pastel) uses 8 hue families at 0°, 30°, 55°, 120°, 185°, 220°, 270° and 315° (red → magenta), softened toward pastel: light = 60% white, medium = 40% white, dark = 25% white at 75% brightness. Rainbow Spectrum (Vivid) uses the same 8 hues at full saturation: light = 20% white, medium = pure hue, dark = 70% brightness. Thinkpad uses 12 colors: pink-red `#FFA8B6 #FF7088 #E04862`, dark red `#D8262E #AA1520 #7A0C14`, grey `#C8C8C8 #A6A6A6 #868686`, white `#FFFFFF #F0F0F0 #DCDCDC`. Midnight uses 12 barely visible colors: grey `#3A3A3A #2C2C2C #1F1F1F`, blue `#1C2A4A #142038 #0D1628`, indigo `#22205A #191744 #100F2E`, violet `#2E1C4A #221438 #170D28`, with dim `#4A4A5E` heads instead of white so nothing stands out. Blackout uses 9 colors just above the black background: black `#1A1A1A #141414 #0E0E0E`, charcoal `#262626 #1F1F1F #181818`, dark grey `#333333 #2A2A2A #212121`, with the same dim `#4A4A5E` heads. Rainbow sweeps hues across the columns and slowly cycles. |
| Speed | 1–10 | 4 | Head speed = `3 × (40/3)^((speed−1)/9)` rows/sec, an exponential curve: 1 → 3, 4 ≈ 7, 7 ≈ 17, 10 → 40. |
| Speed variance | +0–300% (steps of 25) | +150% | The base Speed is the **floor**: each stream falls at base × a random factor in `1…(1 + v)`, so +150% → 1×–2.5× (≈7–18 rows/s at default speed), like cmatrix `-a`. 0% gives every stream the base speed. |
| Density | 1–10 (steps of 0.5) | 4.5 | Mean wait before a column launches its next stream, measured from when the previous stream clears the top: `8 s × (0.15/8)^((d−1)/9)`, i.e. 8 s down to 0.15 s. |
| Trail length | 1–10 | 5 | Baseline trail = `0.08 + 0.6 × (t−1)/9` of screen height (at least 3 glyphs). |
| Length variance | ±0–100% (steps of 10) | ±50% | Each stream's length is the baseline × a random factor in `1 ± v` (the low end is floored at 0.15). |
| Glyph changes | 0–10 | 3 | Each cell re-rolls its character `0.05 × value` times per second (the cmatrix "flicker"). |
| Gliding motion | on/off | on | Characters stay fixed in the grid while the light glides over them: the white head crossfades smoothly from cell to cell and the trail fades continuously. Off gives the classic cmatrix look, where the lit band steps a whole row at a time. Speed is identical either way. |
| Bright white heads | on/off | on | Leading glyph drawn pure white (cmatrix `-b`), or the theme's dim head color for Midnight and Blackout. |
| Fade trails | on/off | on | Tail dims toward black over 10 steps. Off gives cmatrix's flat, hard-edged look. |
| Blend colors along streams | on/off | on | Multi-color themes only (Tokyo Night, both Rainbow Spectrums, Thinkpad, Midnight and Blackout). On: each stream sweeps the theme's whole spectrum (e.g. pink → purple → blue) from head to tail, light shades near the head and dark toward the tail, starting at a random point and direction. Off: each stream uses one of the theme's colors. |
| Glow | on/off | on | Subtle halo behind each head, tinted with its stream's color: a pre-rendered radial-gradient sprite at 1.6× the cell size. |

Settings live in the ScreenSaver defaults domain `com.fussell.MatrixScreenSaver`.
On recent macOS that's inside the legacyScreenSaver sandbox container:
`~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/`.
The `make run` preview app reads and writes a separate, non-sandboxed copy.

**Adding an option:**
1. `MatrixSettings`: add the property with its default (plus a range constant if
   it's numeric), a `Key`, and the matching load and save lines.
2. If it needs a physical mapping (rows/s, seconds, …), add a computed property
   in the "Derived simulation values" extension and document the formula here.
3. `ConfigureSheetController`: declare the control, add it to the grid in
   `buildInterface`, and wire it in `populate` and `controlChanged`. Keep all
   three in the same order as the on-screen rows. Sliders use `LabeledSlider`,
   which handles the System Settings sizing pitfall.
4. If changing it must reset the rain (anything that changes the grid or what
   cells mean), add it to `needsNewGrid` in `MatrixScene.apply`.
5. Add a row to the table above and a Changelog entry.

**Adding a color theme:** add a case to `MatrixColor` (new raw value; never rename
existing ones), give it a `displayName`, and return its `scheme`: `.solid(RGB)`
for one color, or `.families([[light, medium, dark], …])` for a multi-color theme.
That gets blending, per-stream colors, the menu swatch and glow automatically
(see `tokyoNightNeon`, `pastelRainbow`, `vividRainbow`, `thinkpadColors`, `midnightColors` and `blackoutColors`). Then document it in the Color row above.

**Adding a character set:** add a case to `GlyphStyle` with a `displayName` and its
`characters`. List any characters that should also appear flipped left-to-right in
`mirroredCharacters`. The menu follows the case order.

## Project layout

```
matrix-screensaver-macos/
├── README.md                  ← project reference
├── CLAUDE.md                  ← short pointer for AI-assisted sessions
├── LICENSE                    ← GPL-3.0
├── Makefile                   ← build / install / run / snapshot
├── install.sh                 ← one-line installer (curl … | bash)
├── Resources/
│   ├── Info.plist             ← bundle id, version, NSPrincipalClass
│   └── thumbnail(@2x).png     ← picker image in System Settings (90×58 / 180×116)
├── Sources/
│   ├── Core/                  ← platform-neutral effect (no ScreenSaver dependency)
│   │   ├── MatrixSettings.swift   options, slider→physics mapping, persistence
│   │   ├── Palette.swift          RGB helper, ColorScheme, MatrixColor palette (21 entries)
│   │   ├── GlyphStyle.swift       character sets
│   │   ├── RainSimulation.swift   grid + streams simulation, seedable RNG
│   │   ├── GlyphAtlas.swift       chars → Core Text glyphs, font fallback, mirroring, cell metrics
│   │   ├── MatrixRenderer.swift   batched drawing into any CGContext
│   │   └── MatrixScene.swift      glue: keeps renderer + simulation in sync
│   └── ScreenSaver/           ← macOS screen saver integration
│       ├── MatrixScreenSaverView.swift     ScreenSaverView subclass + SettingsStore
│       ├── ConfigureSheetController.swift  Options sheet (built in code)
│       └── MatrixPreviewView.swift         self-animating view for the sheet preview
└── Tools/
    ├── PreviewApp/main.swift  ← windowed / full-screen dev host (`make run`, `make fullscreen`)
    ├── Snapshot/main.swift    ← headless PNG renderer (`make snapshot`, `make thumbnails`)
    └── RenderCheck/main.swift ← render-hash regression check (`make render-check`)
```

`build/` is generated output and is git-ignored.

## Architecture

```
 ScreenSaverView / MatrixPreviewView / snapshot tool      (hosts)
                     │  advance(by: dt), draw(in: ctx, size:)
                     ▼
                MatrixScene  ── apply(settings) ──┐
                 │        │                       │ rebuilds on change
                 ▼        ▼                       │
       RainSimulation   MatrixRenderer ◄──────────┘
       (cells, streams)   └─ GlyphAtlas (fonts, glyphs, metrics)
```

- **Core never imports ScreenSaver.** That's what lets the snapshot tool and
  the preview view reuse it unchanged.
- **The simulation knows nothing about fonts.** Cells store glyph *indices*.
  The renderer maps them through `GlyphAtlas`.
- **`MatrixScene` owns consistency.** If the font, size, character set or motion
  mode changes, or the surface resizes, it rebuilds (and prewarms) the simulation
  grid. Other changes (color, speed, …) apply live without resetting the rain.
- **Time is explicit.** Hosts pass a real `dt` (clamped to 0.1 s), so
  animation speed doesn't depend on frame rate. Every host runs at
  `MatrixScene.frameInterval` (30 fps); change it in that one place.

## How the rain works

The screen is a terminal-like grid of `columns × rows` cells. Every cell always
holds a glyph. *Streams* decide which cells are visible.

1. Each column holds zero or more **streams** (newest last). A stream has a
   fractional `head` row, a `length`, and `litHead`, the lowest row it has reached.
2. Each step, a head moves by `rowsPerSecond × stream.speed × dt`. Every *new*
   row it enters gets a freshly randomized glyph, so text appears to be
   "typed" as it falls, like cmatrix.
3. A column's **spawn cooldown** only counts down while its top row is clear.
   When it reaches zero, a new stream starts at the top (row 0, or −1 in
   gliding mode) and the cooldown is re-rolled from an exponential distribution
   whose mean depends on Density. This produces the irregular dark gaps of the original.
4. Each stream gets its **own speed** (Speed variance). A new stream may be
   faster than the one ahead of it in the same column, but only fast enough that
   it can't reach that stream's tail before the tail leaves the screen
   (`maxFollowSpeed`), so streams never overlap.
5. Streams are removed once their tail passes the bottom.
6. **Mutation:** each step, about `cells × rate × dt` random cells get a new glyph.
7. **Prewarm:** a new simulation starts with staggered column cooldowns, then
   `RainSimulation.prewarm()` fast-forwards it until the slowest first-wave stream
   could have fallen all the way through, tail included (capped at 120 simulated
   seconds). Every host therefore opens on a full, steady-state screen.

**Gliding motion (default).** Characters never move; they live in the grid
exactly as in stepped mode. Only the light glides. With fractional head `h` in
row `⌊h⌋` and progress `p = h − ⌊h⌋`:
- trail cells take their brightness from the continuous distance `h − row`, so
  the fade slides smoothly instead of jumping a row at a time;
- the white head is a crossfade, drawn at opacity `1 − p` in row `⌊h⌋` and at `p`
  in row `⌊h⌋ + 1`. Its center of mass is exactly `h`, which is also where the glow
  halo is drawn;
- the simulation writes each fresh character one row *ahead* of the head, so the
  cell being faded into already shows its new character;
- streams start at `h = −1`, so the first cell fades in rather than popping on.

The RNG is a seedable `SplitMix64`, which makes snapshot renders reproducible (seed 42).

## Rendering pipeline

`MatrixRenderer.draw` per frame:

1. Fill the background black.
2. **Glow pass** (if enabled): for every on-screen head, blit that color's
   pre-rendered halo sprite. This happens before any glyphs, so halos never cover text.
3. **Glyph pass:** for each stream, walk its visible rows top to bottom and
   group consecutive glyphs that share a brightness level (0–9 trail, 10 head),
   color bin and font into a *run*. Each run is one `setFillColor` plus one
   `CTFontDrawGlyphs` call. In gliding mode the head is then drawn separately as
   two single-glyph draws at partial opacity (the crossfade), using `setAlpha`.

Color selection (`ColorScheme` → the renderer's `Coloring`): `.solid` uses one
color, `.rainbow` picks from 24 hue bins by column and time, and `.families`
(hue families ordered light → medium → dark, e.g. Tokyo Night) works in one of two ways:
- **spectrum** (Blend on): 24 bins sampled bilinearly across the family grid
  (`[[RGB]].sample(hue:shade:)`). Each cell's bin comes from its position along the
  stream, offset and direction come from the stream's random `variant`, and the
  sweep bounces back at the ends. The shade goes from light near the head to dark
  near the tail, with a gentler brightness fade (35%→100%).
- **perStream** (Blend off): `variant` picks one of the theme's flat colors.

The color table (`palette[colorBin][level]`) is precomputed when settings change.
Trail shades scale from 15% to 100% brightness with a slight white tint near the
head. The head is always pure white.

**Why per-stream runs.** Core Graphics draws each `CTFontDrawGlyphs` call through
an intermediate bitmap covering the call's whole glyph bounding box. Batching
glyphs by color across the whole screen makes every call screen-sized (tens of
milliseconds per frame); per-stream runs keep each call to a thin strip, about
2–5 ms per frame. Glow uses pre-rendered sprites because `CGContext.setShadow`
blurs every glyph individually and is far too slow.

**Font fallback and mirroring:** `GlyphAtlas` resolves each character in the chosen
font, falling back to `CTFontCreateForString`. Fallback fonts get their own slot,
so batching still works. Fallback glyphs wider than 1.25× the primary font's `0`
are skipped (they would widen every column), as are characters only `LastResort`
can draw. Mirrored characters use a horizontally flipped copy of their font, with
`Entry.xOffset` keeping them centered, so mirroring costs nothing per frame. Cell
width is the widest glyph × 1.5, which keeps the open spacing between cmatrix
columns. Glyphs are centered in their cells.

**Edge fit:** the grid holds only whole cells (`floor` in both directions), and
the leftover space is split evenly as left/right and top/bottom margins, so no
glyph is ever clipped at a screen edge. For example, at the default 16 pt
CaskaydiaCove (15×19 pt cells), 1720×1118 gives 114×58 cells with 5 pt / 8 pt margins.

Coordinates use the default bottom-left origin for both the `NSView` and
bitmap contexts. Row 0 is the top row of the centered grid.

## macOS screen saver quirks handled

- **No Xcode project:** the bundle is a Mach-O `MH_BUNDLE` linked with
  `swiftc -emit-executable -Xlinker -bundle`, one per arch, combined with `lipo`.
- **Stable principal class:** `@objc(MatrixScreenSaverView)` keeps the
  Objective-C name module-independent, matching `NSPrincipalClass` in Info.plist.
- **Lingering host process (macOS 14+):** `legacyScreenSaver` often never calls
  `stopAnimation()` and keeps running in the background after you dismiss the
  saver. The view listens for the `com.apple.screensaver.willstop` distributed
  notification, stops animating, and (for full-screen, non-preview instances
  inside `legacyScreenSaver` only) exits the host after 1 s. The preview app and
  the System Settings thumbnail are never terminated.
- **Thumbnail scaling:** in preview mode, font size is scaled by
  `thumbnailWidth / screenWidth` (minimum 0.25×) so the tiny thumbnail looks
  like a miniature of the real thing.
- **Stale binaries:** macOS caches loaded savers, so `make install` restarts
  `legacyScreenSaver` and System Settings.
- **Picker thumbnail:** System Settings shows `Contents/Resources/thumbnail.png`
  and `thumbnail@2x.png` (90×58 / 180×116, the same as Apple's own savers) in the
  saver list. `make thumbnails` regenerates them from a render.
- **Options sheet sizing:** System Settings resizes the sheet itself, and `NSSlider`
  has no intrinsic width, so each slider has a required ≥180 pt width and the sheet
  has `contentMinSize` = its fitted size. Otherwise sliders collapse to 0 pt wide.
- **Sheet dismissal:** the sheet ends through `sheetParent.endSheet`, which is
  what System Settings expects, and falls back to `close()` in other hosts.

## Development workflow

This README is the project's reference: update it (especially the options table
and Changelog) with every change.

1. For a refactor or cleanup, run `make render-baseline` **before** editing.
2. Edit the sources.
3. `make run` for a live window (⌘, opens Options) and `make fullscreen` to see
   it as the screen saver renders it. Add `ARGS="--color rainbowSpectrum"` to
   preview any theme.
4. `make snapshot ARGS="..."` checks visuals headlessly. It's deterministic (seed 42)
   and prints the steady-state frame time; keep frames well under 33 ms.
5. For refactors, `make render-check` must report identical renders. It hashes
   12 settings combinations (gliding/stepped, every effect toggle, all three color
   scheme kinds, fallback fonts, mirrored glyphs, Unicode) at three points in time.
   A diff means something visible changed. Hashes are only comparable on the same
   machine and OS.
6. `make install` and test in System Settings: the thumbnail, the Options sheet
   (drag the sliders), and multiple displays if available.

Compiler settings: Swift 6 language mode, `-O -whole-module-optimization`.
Keep the build **warning-free**.

## Conventions

- Don't copy code from cmatrix or other Matrix projects. Keep it clean-room.
- Core stays free of `ScreenSaver` imports. AppKit is allowed only where Core
  Text needs `NSFont` (font lookup).
- Persisted raw values (`MatrixColor`, `GlyphStyle` cases and the
  `MatrixSettings.Key` strings) must never be renamed. Add new cases instead.
  Display names and menu order can change freely.
- Intensity-style sliders use the friendly 1–10 scale; variance-style sliders use
  percentages. Either way, put the physical mapping in a computed property in
  `MatrixSettings` and document the formula above.
- Never batch glyphs across the whole screen, and never use `CGContext.setShadow`
  for glow (see *Rendering pipeline* for why). Use per-stream runs and sprites.
- Comments explain *why*, not *what*. Match the existing density.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Old version still shows after install | `make install` restarts the hosts. If it persists, log out and back in. |
| "Matrix" missing from System Settings | Check that `~/Library/Screen Savers/MatrixScreenSaver.saver` exists. Run `codesign -v` on it. |
| macOS says it can't open the saver | A prebuilt copy downloaded from elsewhere is quarantined. Install with one of the methods above instead, or run `xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/MatrixScreenSaver.saver`. |
| Options don't stick | Check the sandboxed prefs path in [Options reference](#options-reference). |
| High CPU after dismissing | Should be handled by the willstop exit. Check with `pgrep legacyScreenSaver`. |

## Roadmap

- [ ] Metal renderer for very small fonts on 6K/8K displays.
- [ ] "Message" mode that spells a custom phrase through the rain.
- [ ] Per-display color or style.
- [ ] Optional 60 fps (change `MatrixScene.frameInterval`; frames cost ~2–7 ms,
  so it's affordable but roughly doubles CPU use).
- [ ] Unit tests for `RainSimulation` (needs XCTest / swift-testing from a full Xcode install).
- [ ] Developer ID signed and notarized release build.

## Changelog

### Unreleased

- The 1.2.0 grey, blue and violet theme is renamed **Midnight** (saved as
  `midnight`) and gains a fourth color, deep indigo, between its blue and violet.
- New **Blackout** theme: near-black and dark grey shades just above the
  background, with the same dimmed heads. Saved 1.2.0 Blackout choices now get
  this theme; pick Midnight to get the old colors back.

### 1.2.0 — 2026-10-26

- **Thinkpad** color theme: pink-red, dark red, grey and white.
- **Midnight** color theme (released as "Blackout"): barely visible dark grey, blue and violet, with dimmed heads.

### 1.1.0 — 2026-10-26

- **Rainbow Spectrum (Vivid)** color theme.
- **Unicode**, **Katakana (Enhanced)** and **Katakana (Film)** character sets,
  including mirrored katakana.
- Character menu reordered (Classic, Hexadecimal, Binary, Unicode, then the
  katakana sets); "Katakana + Latin" is now "Katakana (Combined)". Saved choices
  carry over.
- The saver starts with a full screen instead of filling from the top.
- One-line installer (`install.sh`) and Homebrew formula.
- Licensed under GPL-3.0.

### 1.0.0 — 2026-10-25

- First release: cmatrix-style rain with gliding or stepped motion, 18 color
  modes (including Tokyo Night and Rainbow Spectrum (Pastel)), 5 character sets,
  any monospaced font, adjustable speed, density, trails and glyph changes, glow,
  Options sheet with live preview, and multi-display support.

## License

GPL-3.0. See [LICENSE](LICENSE). Copyright © 2026 WhiskeyTangoFussell.
