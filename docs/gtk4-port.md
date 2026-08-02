# GTK4 port

Work in progress on the `gtk4-port` branch. `master` stays on GTK3 and remains
the usable version until this lands.

## Why it is not incremental

gtk-d has no GTK4 support, so the port is really two changes stacked:

1. **Bindings:** gtk-d → [GID](https://code.dlang.org/packages/gid) (GObject
   introspection D bindings). GID 0.9.13 provides `gtk4`, `gdk4`, `gsk4`,
   `vte3` (VTE for GTK4), `adw1` and `secret1`, among 54 subpackages.
2. **Toolkit semantics:** GTK3 → GTK4, which removes or redesigns a lot of what
   this codebase currently uses.

The first of those cannot be done module by module in a compiling state: gtk-d
and GID declare *different, incompatible D types* for the same underlying C
objects, so a widget cannot be handed across a gtk-d/GID boundary. The tree
therefore does not build again until the sweep is finished.

To keep that from being a blind rewrite, `contrib/gid-typecheck.sh` typechecks
individual files against GID without linking. Working bottom-up (leaves first),
each module can be verified as it is converted.

Verified on this machine: a dub project depending on `gid:gtk4` and `gid:vte3`
0.9.13 builds, links and runs with ldc2, and `connectClicked`,
`EventControllerKey` and `vte.terminal.Terminal` typecheck as expected.

## Scope, as measured

33,897 lines of D across `source/`.

Imports to rewrite (GID uses `snake_case` module names, e.g. `gtk.AboutDialog`
becomes `gtk.about_dialog`):

| Prefix    | Imports |
| --------- | ------- |
| `gtk.*`   | 393     |
| `gio.*`   | 106     |
| `glib.*`  | 97      |
| `gdk.*`   | 68      |
| `gobject.*` | 36    |
| `gtkc.*` (raw C) | 27 |
| `vte.*`   | 16      |
| `cairo.*` | 11      |
| `gdkpixbuf.*` | 6   |
| `pango.*` | 4       |

Signal connections: **194** `addOn*` calls, which become `connectX` in GID.

### The parts that are not a rename

These need actual redesign, not translation — 202 sites in total:

| What | Sites | Files | Notes |
| ---- | ----- | ----- | ----- |
| GTK3 event handlers | 39 | 11 | `addOnButtonPress`/`KeyPress`/`Draw`/… all gone; become `EventController*` / `Gesture*` |
| `GdkWindow` / `getWindow()` | 37 | 6 | GdkWindow does not exist in GTK4 |
| `showAll()` | 36 | 13 | Removed; widgets are visible by default |
| Clipboard atoms | 27 | 3 | No `GdkAtom`; `GdkClipboard` objects from the display instead |
| Drag and drop | 22 | 3 | Completely redesigned |
| `EventBox` | 19 | 4 | Widget removed; ordinary widgets take events |
| `Alignment` | 12 | 3 | Removed; use halign/valign/margins |
| cairo draw handlers | 6 | 3 | GTK4 renders through GSK snapshots |
| direct X11 | 4 | 2 | X11-only paths need a Wayland-safe story |

### Free wins

`source/secret/` and `source/secretc/` are 10 files and **6,179 lines** of
hand-written libsecret bindings — 18% of the codebase. GID ships `secret1`, so
that whole tree gets deleted rather than ported.

## Phases

1. **gtk-d → GID, still GTK3.** Mechanical but large. Upstream PR
   gnunn1/tilix#2282 did exactly this against GID 0.9.7 and is worth reading for
   patterns, but applying its +7825/−10280 diff directly would conflict badly
   with this fork's own changes, so it is a reference only.
2. **GTK3 → GTK4 semantics.** The table above, plus CSD/HeaderBar changes.
3. **VTE for GTK4** (`gid:vte3`), and re-doing the sixel drawing patch against
   GSK — `patches/vte-draw-sixel-images.patch` is cairo-based and therefore
   GTK3-only. See `patches/README.md`.

## Local prerequisites still missing

* `libgtk-4-dev` — the GTK4 runtime is present here, but not the headers, so
  VTE cannot yet be built with `-Dgtk4=true`.
* A VTE built for GTK4 (`libvte-2.91-gtk4`), which no distro package provides
  here either.
