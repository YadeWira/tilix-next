#!/usr/bin/env bash
# Build a VTE with working sixel image rendering, for use with tilix-next.
#
# Distro VTE packages cannot display images: sixel is a build option that
# defaults to off, and even when it is on, upstream never wired the decoded
# images into the drawing code. See ../patches/README.md for the full story.
#
# This clones VTE, applies patches/vte-draw-sixel-images.patch, and installs
# into a private prefix. Nothing outside that prefix is touched; your system
# VTE is left exactly as it is.
#
# Usage:
#   ./contrib/build-vte-sixel.sh [PREFIX]
#
# PREFIX defaults to ~/.local/vte-sixel

set -euo pipefail

PREFIX="${1:-$HOME/.local/vte-sixel}"
# Pinned to the commit the patch was developed and verified against.
VTE_COMMIT="3d55bbdddb87d3341c9e9e87fa6a085192612668"
VTE_REPO="https://gitlab.gnome.org/GNOME/vte.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$SCRIPT_DIR/../patches/vte-draw-sixel-images.patch"
WORKDIR="${TMPDIR:-/tmp}/tilix-vte-sixel-build"

if [ ! -f "$PATCH" ]; then
    echo "error: patch not found at $PATCH" >&2
    exit 1
fi

# --- toolchain -------------------------------------------------------------
# Current VTE master uses C++23 std::out_ptr, which needs GCC 14 or newer.
pick_compiler() {
    for v in 15 14; do
        if command -v "g++-$v" >/dev/null 2>&1; then
            export CC="gcc-$v" CXX="g++-$v"
            return
        fi
    done
    local major
    major="$(g++ -dumpversion 2>/dev/null | cut -d. -f1 || echo 0)"
    if [ "$major" -ge 14 ]; then
        return  # default g++ is new enough
    fi
    echo "error: need GCC 14+ (current VTE master requires C++23 std::out_ptr)." >&2
    echo "       On Debian/Ubuntu: sudo apt install g++-14" >&2
    exit 1
}
pick_compiler

# --- dependencies ----------------------------------------------------------
MISSING=()
for mod in glib-2.0 gio-2.0 gobject-2.0 gtk+-3.0 pango cairo cairo-gobject \
           libpcre2-8 fribidi icu-uc gnutls liblz4 libsystemd; do
    pkg-config --exists "$mod" 2>/dev/null || MISSING+=("$mod")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "error: missing build dependencies (pkg-config modules): ${MISSING[*]}" >&2
    echo "       On Debian/Ubuntu, these usually come from:" >&2
    echo "       sudo apt install libglib2.0-dev libgtk-3-dev libpcre2-dev \\" >&2
    echo "            libfribidi-dev libicu-dev libgnutls28-dev liblz4-dev libsystemd-dev" >&2
    exit 1
fi
command -v meson >/dev/null 2>&1 || { echo "error: meson not found" >&2; exit 1; }
command -v ninja >/dev/null 2>&1 || { echo "error: ninja not found" >&2; exit 1; }

# --- fetch -----------------------------------------------------------------
echo ">>> Fetching VTE into $WORKDIR"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
git init -q "$WORKDIR"
git -C "$WORKDIR" remote add origin "$VTE_REPO"
git -C "$WORKDIR" fetch -q --depth 1 origin "$VTE_COMMIT"
git -C "$WORKDIR" checkout -q FETCH_HEAD

echo ">>> Applying $(basename "$PATCH")"
git -C "$WORKDIR" apply "$PATCH"

# --- build -----------------------------------------------------------------
echo ">>> Configuring (prefix: $PREFIX)"
meson setup "$WORKDIR/_build" "$WORKDIR" \
    --prefix="$PREFIX" \
    --buildtype=release \
    -Dsixel=true \
    -Dgtk3=true -Dgtk4=false \
    -Ddocs=false -Dgir=false -Dvapi=false

echo ">>> Building"
ninja -C "$WORKDIR/_build"

echo ">>> Installing"
ninja -C "$WORKDIR/_build" install

# --- verify ----------------------------------------------------------------
# A successful build is not proof of a useful one: the sixel meson option has
# been renamed/removed across releases, and a VTE without the sixel sources
# still exposes the enable-sixel API as a silent no-op. Check the built library
# for both halves rather than just reporting success.
LIB="$(find "$PREFIX/lib" -name 'libvte-2.91.so.0.*' -print -quit)"
LIBDIR="$(dirname "$LIB")"
VERIFY_FAILED=0

if [ -z "$LIB" ]; then
    echo "error: no libvte-2.91.so.0.* found under $PREFIX/lib" >&2
    exit 1
fi

# Count rather than `grep -q`: under `set -o pipefail`, grep -q exits at the
# first match, the producer takes SIGPIPE, and the pipeline reports failure —
# so a successful match would look like a failed check.

# 1. sixel implementation compiled in (these source paths only appear if it was)
SIXEL_HITS="$(strings "$LIB" 2>/dev/null | grep -c 'src/sixel-context' || true)"
if [ "$SIXEL_HITS" -eq 0 ]; then
    echo "WARNING: built library has no sixel implementation compiled in." >&2
    VERIFY_FAILED=1
fi

# 2. our drawing code present (hidden visibility, so look in the local symtab)
DRAW_HITS="$(nm -C "$LIB" 2>/dev/null | grep -c 'Terminal::draw_images' || true)"
if [ "$DRAW_HITS" -eq 0 ]; then
    echo "WARNING: Terminal::draw_images() not found — the patch did not take effect." >&2
    VERIFY_FAILED=1
fi

if [ "$VERIFY_FAILED" -ne 0 ]; then
    echo "" >&2
    echo "The build completed but will not display images. Please report this" >&2
    echo "along with the VTE version above." >&2
    exit 1
fi

echo ">>> Verified: sixel compiled in and draw_images() present"

# --- done ------------------------------------------------------------------
cat <<EOF

Done. Patched VTE installed to: $PREFIX

Run Tilix against it with:

    LD_LIBRARY_PATH="$LIBDIR" tilix

Then enable images in Preferences -> Profile -> Compatibility ->
"Enable Sixel image support", and try:

    img2sixel some-image.png

Your system VTE was not modified. To undo everything, delete $PREFIX.
EOF
