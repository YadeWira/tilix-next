# Patches

Out-of-tree patches that tilix-next depends on for optional features.

## vte-draw-sixel-images.patch

Makes VTE actually **draw** sixel images. Without it, Tilix's "Enable Sixel image
support" preference has no visible effect no matter which VTE you run.

### Why this is needed

VTE's sixel support is only half-implemented upstream:

* `Terminal::insert_image()` (`src/vte.cc`) decodes the sixel payload into a
  `cairo_surface_t`, computes its size in cells, stores it via
  `Ring::append_image()`, and advances the cursor past it.
* `Ring` (`src/ring.cc`) keeps the images in `m_image_priority_map` /
  `m_image_by_top_map`, rewraps them on resize, and deletes them once they are
  overdrawn.
* `vte::image::Image::paint()` (`src/image.cc`) is fully written — scaling,
  clipping, cairo painting, all of it.

...and then **nothing ever calls `paint()`**. Grepping the drawing code for
images returns nothing; no code outside `ring.cc` ever reads those maps back.
So the image is decoded, stored, and the cursor jumps down by the image's
height — which is why you get a correctly-sized blank gap where the picture
should be.

This patch adds `Terminal::draw_images()`, which walks the stored images that
intersect the current viewport and calls the existing `Image::paint()` for each,
and calls it from `Terminal::draw()` right after `draw_rows()`. That's the whole
fix: 43 lines, no new logic, just connecting two halves that were already there.

Verified on VTE 0.85.0 (master) with both `img2sixel` and `chafa -f sixel`, in
Tilix and in VTE's own demo app.

**GTK3 only.** The patch is guarded with `#if WITH_SIXEL && VTE_GTK == 3`
because it paints through `m_draw.cairo()`, and `m_draw` is only a
`DrawingCairo` in GTK3 builds — under GTK4 it is a `DrawingGsk`, which has no
cairo context. A GTK4 build therefore compiles as before, without image
drawing; wiring images up there means writing a second implementation against
GSK (snapshot/texture) rather than cairo.

### Why a development snapshot, and not a stable release

**No stable VTE release contains sixel at all.** Upstream carries the sixel
sources in `master` during development and strips them again immediately before
every release, then restores them afterwards:

| Tag                                        | sixel sources |
| ------------------------------------------ | ------------- |
| 0.77.0, 0.79.0, 0.81.0 (mid-cycle dev tags) | present       |
| 0.81.90, 0.83.90, 0.83.91 (release candidates) | **removed** |
| 0.76.x … 0.84.1 (every stable release)      | **removed**   |
| `master` (0.85.0-dev)                       | present       |

Checked with `git ls-tree -r --name-only <tag> | grep -i sixel`. VTE 0.84.1, the
newest stable at time of writing, has no sixel files, no `sixel` meson option,
no `image.cc`, and no `insert_image()` in `vte.cc` — the entire image subsystem
is absent. On such builds `vte_terminal_set_enable_sixel()` still exists as an
API symbol but is a silent no-op stub, which is what Debian/Ubuntu ship.

So pinning this to a stable release is not an option that exists; it is a
development snapshot or nothing. `contrib/build-vte-sixel.sh` pins one specific
master commit so the result is at least reproducible rather than a moving
target, and the build is installed into a private prefix used only by Tilix via
`LD_LIBRARY_PATH`, so nothing else on the system is exposed to it.

`sixel` is also a meson option defaulting to `false`, so even the snapshots that
do contain the code have it compiled out unless you ask for it.

### Applying

```sh
git clone https://gitlab.gnome.org/GNOME/vte.git
cd vte
git checkout 3d55bbdddb87d3341c9e9e87fa6a085192612668   # or a newer master
git apply /path/to/patches/vte-draw-sixel-images.patch

# GCC 14+ is required by current VTE master (it uses C++23 std::out_ptr)
CC=gcc-14 CXX=g++-14 meson setup _build . \
    --prefix="$HOME/.local/vte-sixel" \
    --buildtype=release \
    -Dsixel=true -Dgtk3=true -Dgtk4=false \
    -Ddocs=false -Dgir=false -Dvapi=false
ninja -C _build
ninja -C _build install
```

Then run Tilix against it and turn on the Sixel preference in
**Preferences → Profile → Compatibility**:

```sh
LD_LIBRARY_PATH="$HOME/.local/vte-sixel/lib/x86_64-linux-gnu" tilix
```

Test with `img2sixel some-image.png`. Note that `fastfetch` is a poor test
vehicle: it has an unrelated upstream bug that makes it stall for ~139s
detecting Tilix's version (fastfetch-cli/fastfetch#1550).
