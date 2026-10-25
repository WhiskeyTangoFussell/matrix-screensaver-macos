# Builds the screen saver with plain swiftc — no Xcode project required
# (Command Line Tools are enough). See README.md for details.

PRODUCT     := MatrixScreenSaver
MIN_MACOS   := 15.0
ARCHS       := arm64 x86_64
BUILD       := build
SAVER       := $(BUILD)/$(PRODUCT).saver
INSTALL_DIR := $(HOME)/Library/Screen Savers

CORE_SOURCES  := $(wildcard Sources/Core/*.swift)
SAVER_SOURCES := $(CORE_SOURCES) $(wildcard Sources/ScreenSaver/*.swift)
SWIFTFLAGS    := -swift-version 6 -O -whole-module-optimization -module-name $(PRODUCT)
HOST_TARGET   := $(shell uname -m)-apple-macos$(MIN_MACOS)
THUMBNAILS    := Resources/thumbnail.png Resources/thumbnail@2x.png

.PHONY: all build install uninstall run fullscreen snapshot thumbnails render-baseline render-check clean

all: build

build: $(SAVER)

# Universal (arm64 + x86_64) loadable bundle, ad-hoc signed.
$(SAVER): $(SAVER_SOURCES) Resources/Info.plist $(THUMBNAILS)
	@rm -rf "$@"
	@mkdir -p "$@/Contents/MacOS" "$@/Contents/Resources" "$(BUILD)/obj"
	@for arch in $(ARCHS); do \
		echo "swiftc [$$arch]"; \
		swiftc $(SWIFTFLAGS) -target $$arch-apple-macos$(MIN_MACOS) \
			-emit-executable -Xlinker -bundle -framework ScreenSaver \
			-o "$(BUILD)/obj/$(PRODUCT)-$$arch" $(SAVER_SOURCES) || exit 1; \
	done
	@lipo -create $(foreach a,$(ARCHS),"$(BUILD)/obj/$(PRODUCT)-$(a)") -output "$@/Contents/MacOS/$(PRODUCT)"
	@cp Resources/Info.plist "$@/Contents/Info.plist"
	@cp $(THUMBNAILS) "$@/Contents/Resources/"
	@codesign --force --sign - "$@"
	@echo "Built $@"

install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(PRODUCT).saver"
	@cp -R "$(SAVER)" "$(INSTALL_DIR)/"
	@# Force the screen saver host to reload the new binary.
	@killall legacyScreenSaver 2>/dev/null || true
	@killall "System Settings" 2>/dev/null || true
	@echo "Installed to $(INSTALL_DIR)/$(PRODUCT).saver"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(PRODUCT).saver"
	@echo "Removed $(INSTALL_DIR)/$(PRODUCT).saver"

# Windowed preview app hosting the same view (⌘, opens Options).
$(BUILD)/MatrixPreview: $(SAVER_SOURCES) Tools/PreviewApp/main.swift
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -target $(HOST_TARGET) -framework ScreenSaver -o $@ $^

# Both preview targets take ARGS, e.g. ARGS="--color rainbowSpectrum".
run: $(BUILD)/MatrixPreview
	./$(BUILD)/MatrixPreview $(ARGS)

# Full-screen preview that behaves like the real screen saver (any input exits).
fullscreen: $(BUILD)/MatrixPreview
	./$(BUILD)/MatrixPreview --fullscreen $(ARGS)

# Off-screen render to PNG: make snapshot ARGS="out.png 1440 900 cyan katakana"
$(BUILD)/snapshot: $(CORE_SOURCES) Tools/Snapshot/main.swift
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -target $(HOST_TARGET) -o $@ $^

snapshot: $(BUILD)/snapshot
	./$(BUILD)/snapshot $(or $(ARGS),$(BUILD)/snapshot.png)

# Regenerates the System Settings picker thumbnails (90×58 and 180×116, the
# sizes Apple's own savers use) from a real render of the default settings.
thumbnails: $(BUILD)/snapshot
	./$(BUILD)/snapshot $(BUILD)/thumbnail-source.png 630 406 tokyoNight classic 40
	sips -z 116 180 $(BUILD)/thumbnail-source.png --out Resources/thumbnail@2x.png
	sips -z 58 90 $(BUILD)/thumbnail-source.png --out Resources/thumbnail.png

# Refactor safety net: record render hashes, change code, then check they match.
$(BUILD)/render-check: $(CORE_SOURCES) Tools/RenderCheck/main.swift
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -target $(HOST_TARGET) -o $@ $^

render-baseline: $(BUILD)/render-check
	./$(BUILD)/render-check > $(BUILD)/render-baseline.txt
	@echo "Baseline saved to $(BUILD)/render-baseline.txt"

render-check: $(BUILD)/render-check
	@./$(BUILD)/render-check > $(BUILD)/render-latest.txt
	@diff $(BUILD)/render-baseline.txt $(BUILD)/render-latest.txt && echo "Renders identical to baseline."

clean:
	rm -rf $(BUILD)
