#!/usr/bin/env bash
# Typecheck one or more D source files against the GID bindings, without
# linking or building the rest of the project.
#
# The GTK4 port cannot be built incrementally: gtk-d and GID define
# incompatible D types for the same underlying C objects, so the project does
# not compile again until every module has been converted. This lets a module
# be checked on its own as soon as its own dependencies are converted, instead
# of waiting for the whole sweep to finish.
#
# Usage:
#   ./contrib/gid-typecheck.sh source/gx/gtk/color.d [more.d ...]
#
# Override the bindings location with GID_PACKAGES if it is not in ~/.dub.

set -uo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <file.d> [more.d ...]" >&2
    exit 2
fi

# Locate the GID package tree (newest version wins).
if [ -z "${GID_PACKAGES:-}" ]; then
    GID_PACKAGES="$(ls -d "$HOME"/.dub/packages/gid/*/gid/packages 2>/dev/null | sort -V | tail -1)"
fi
if [ -z "$GID_PACKAGES" ] || [ ! -d "$GID_PACKAGES" ]; then
    echo "error: GID bindings not found. Run a dub build once to fetch them," >&2
    echo "       or set GID_PACKAGES to the directory holding glib2/, gtk4/, ..." >&2
    exit 1
fi

INC=( "-Isource" )
for pkg in glib2 gio2 gtk4 gdk4 gsk4 graphene1 vte3 cairo1 pango1 \
           pangocairo1 gdkpixbuf2 harfbuzz0 freetype2 secret1 gmodule2 xlib2; do
    [ -d "$GID_PACKAGES/$pkg" ] && INC+=( "-I$GID_PACKAGES/$pkg" )
done

DC="${DC:-ldc2}"
"$DC" -c -o- --d-version=StdLoggerDisableTrace "${INC[@]}" "$@"
rc=$?

if [ $rc -eq 0 ]; then
    echo "TYPECHECK OK: $*"
else
    echo "TYPECHECK FAILED: $*"
fi
exit $rc
