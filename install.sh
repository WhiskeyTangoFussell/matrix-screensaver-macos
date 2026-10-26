#!/bin/bash
# Builds and installs the Matrix screen saver for the current user.
#
#   curl -fsSL https://raw.githubusercontent.com/WhiskeyTangoFussell/matrix-screensaver-macos/main/install.sh | bash
#
# Remove it again with `... | bash -s -- --uninstall`. Set MATRIX_REF to a tag
# or branch to install that instead of the latest release.
#
# The saver is compiled on this Mac, so it isn't quarantined and Gatekeeper
# doesn't block it even though it has no Developer ID signature.
set -euo pipefail

REPO="WhiskeyTangoFussell/matrix-screensaver-macos"
SAVER="MatrixScreenSaver.saver"
DEST="$HOME/Library/Screen Savers"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "this screen saver is for macOS only."
(( $(sw_vers -productVersion | cut -d. -f1) >= 15 )) || fail "macOS 15 Sequoia or later is required."

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -rf "$DEST/$SAVER"
    killall legacyScreenSaver 2>/dev/null || true
    echo "Removed $DEST/$SAVER"
    exit 0
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Building needs Apple's Command Line Tools. Opening the installer…"
    xcode-select --install 2>/dev/null || true
    fail "finish installing the Command Line Tools, then run this command again."
fi

ref="${MATRIX_REF:-}"
if [[ -z "$ref" ]]; then
    ref=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1) || true
    ref="${ref:-main}"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Downloading $REPO ($ref)…"
curl -fsSL "https://github.com/$REPO/archive/$ref.tar.gz" | tar -xz -C "$work" --strip-components 1

echo "Building (about a minute)…"
make -C "$work" install

echo
echo "Done. Open System Settings → Screen Saver and choose \"Matrix\"."
