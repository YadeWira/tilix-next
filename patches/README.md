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

### Also note

VTE **0.76.0 specifically has no sixel code at all** — upstream deleted the
sixel sources for that release (present in 0.69.90–0.75.0, gone in 0.75.92 and
0.76.0, restored in 0.77.0). Debian/Ubuntu ship 0.76.0, so on those systems
`vte_terminal_set_enable_sixel()` exists but is a no-op stub. Building against
0.77.0 or newer is required before this patch is even relevant.

`sixel` is also a meson option defaulting to `false`, so distro builds have it
off regardless.

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
