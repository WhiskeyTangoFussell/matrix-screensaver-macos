# CLAUDE.md

README.md is the source of truth for this project: features, options, architecture,
conventions and changelog. Read it first, and update it (especially the options table
and Changelog) with every change.

Quick facts:
- Build with `make build` (swiftc + Command Line Tools; there is no Xcode project).
- Verify visuals with `make snapshot ARGS="out.png 1440 900 tokyoNight classic 8"` and view the PNG.
- Before any refactor run `make render-baseline`; afterwards `make render-check` must report identical renders.
- README has step-by-step recipes for adding an option or a color theme.
- Clean-room code: never copy from cmatrix.
- Never rename persisted raw values (MatrixColor, GlyphStyle, MatrixSettings.Key).
- Keep the build warning-free in Swift 6 language mode.
