![Build Status](https://github.com/YadeWira/tilix-next/actions/workflows/build-test.yml/badge.svg)
# Tilix (tilix-next)
A tiling terminal emulator for Linux using GTK+ 3. The Tilix web site for users is available at [https://gnunn1.github.io/tilix-web](https://gnunn1.github.io/tilix-web).

> **tilix-next** is an actively maintained fork of [gnunn1/tilix](https://github.com/gnunn1/tilix), picking up bug fixes and small features from that
> project's open issues and pull requests while it looks for new maintainers.

###### Screenshot
![Screenshot](https://gnunn1.github.io/tilix-web/assets/images/gallery/tilix-screenshot-1.png)

### About

Tilix is a tiling terminal emulator which uses the VTE GTK+ 3 widget with the following features:

* Layout terminals in any fashion by splitting them horizontally or vertically
* Terminals can be re-arranged using drag and drop both within and between windows
* Terminals can be detached into a new window via drag and drop
* Tabs or sidebar list current sessions
* Input can be synchronized between terminals so commands typed in one terminal are replicated to the others
* The grouping of terminals can be saved and loaded from disk
* Terminals support custom titles
* Color schemes are stored in files and custom color schemes can be created by simply creating a new file
* Transparent background
* Background images
* [Quake mode](https://github.com/gnunn1/tilix/wiki/Quake-Mode) support (i.e. drop-down terminal)
* Custom hyperlinks
* Automatic (triggered) profile switches based on hostname and directory
* Supports notifications when processes are completed out of view. Requires the Fedora notification patches for VTE
* Trigger support: match regexes against terminal output to update titles/badges, send text, run commands, show
  notifications, or (tilix-next) prompt to copy matched text to the clipboard — a safe alternative to OSC 52, since
  it requires both a trigger you configured yourself and an explicit click, see [wiki](https://github.com/gnunn1/tilix/wiki/Automatic-(Triggered)-Profile-Switching)
* Experimental badge support (Requires patched VTE, see [wiki](https://github.com/gnunn1/tilix/wiki/Badges))
* (tilix-next) Optional Sixel image protocol support, so programs can draw real images directly in the terminal — see [Images (Sixel)](#images-sixel) for the VTE requirements

The application was written using GTK 3 and an effort was made to conform to GNOME Human Interface Guidelines (HIG). As a result, it does use CSD (i.e. the GTK HeaderBar)
though it can be disabled if necessary. Other than GNOME, only Unity has been tested officially though users have had success with other desktop environments.

### Dependencies

Tilix requires the following libraries to be installed in order to run:
* GTK 3.18 or later (Tilix 1.8.3 or later, earlier versions supported GTK 3.14)
* GTK VTE 0.46 or later
* dconf
* GSettings
* [Nautilus-Python](https://wiki.gnome.org/Projects/NautilusPython) (Required for Nautilus integration)

### Migrating Settings From Terminix

Terminix was recently re-named to Tilix and as a result the settings key changed. To migrate your settings to Tilix, please perform the following steps:

```
dconf dump /com/gexperts/Terminix/ > terminix.dconf
dconf load /com/gexperts/Tilix/ < terminix.dconf
```
This will export your settings from the Terminix key in dconf and re-import them into the Tilix key.

Note that this will work even after you have uninstalled the Terminix schema, since the user customized settings are available even after the schema got removed, and the
default settings are identical between the two and thus do not matter.

Once you have imported the settings and everything is ok you can clear the old Terminix settings with:
```
dconf reset -f /com/gexperts/Terminix/
```
Finally to copy the bookmarks and custom themes just do:

```
mv ~/.config/terminix ~/.config/tilix
```

### Optional Fonts
In some of the screenshots, the `powerline` statusline shell plugin is used. In order to ensure it works well, you may need to install its [fonts](https://github.com/powerline/fonts)
and ensure Tilix is aware of them. They can be installed via `sudo apt install fonts-powerline` on Debian/Ubuntu and `sudo dnf install powerline-fonts` on Fedora/RedHat-based
Linux distributions.
After installing the fonts, select the "Powerline Symbols" font in Tilix via **Preferences -> Default -> Custom Font**. Sessions are updated automatically.

### Images (Sixel)

Tilix can display real images inline via the Sixel protocol (`img2sixel foo.png`, `chafa -f sixel foo.png`, and anything else
that emits sixel). Turn it on per profile under **Preferences → Profile → Compatibility → "Enable Sixel image support"**; it is
off by default, matching VTE's own default.

**This needs a VTE that can actually draw images, which no distro currently ships.** Two separate upstream gaps are in the way:

1. **No stable VTE release contains sixel at all.** Upstream carries the sixel sources in `master` and strips them again right
   before every release, restoring them afterwards — so 0.76.x through 0.84.1 all ship without a single sixel file, without the
   `sixel` meson option, and without `image.cc`. On those builds `vte_terminal_set_enable_sixel()` exists as an API symbol but is
   a silent no-op. (`sixel` is additionally a build option defaulting to `false`, so even the development snapshots that do carry
   the code have it compiled out unless asked for.)
2. Even with `-Dsixel=true`, VTE decodes sixel images and stores them, but **never draws them**: the cursor advances past a
   correctly-sized blank gap where the picture should be. `patches/vte-draw-sixel-images.patch` in this repository fixes that in
   43 lines by calling VTE's own already-written `Image::paint()` from the drawing code.

The Tilix side works as soon as it is given such a VTE; nothing else is needed here.

#### Option 1: build it with the provided script (recommended)

```
./contrib/build-vte-sixel.sh
```

Clones VTE at a pinned commit, applies the patch, and installs to `~/.local/vte-sixel` (pass a different prefix as the first
argument). Your system VTE is not touched. Then:

```
LD_LIBRARY_PATH="$HOME/.local/vte-sixel/lib/x86_64-linux-gnu" tilix
```

#### Option 2: build it by hand

If you would rather drive it yourself, or need to adapt it to a distro other than Debian/Ubuntu, the equivalent manual steps —
dependencies, the GCC 14 requirement, meson flags, and how to verify the result — are written out in
[patches/README.md](patches/README.md).

To make it permanent, set `LD_LIBRARY_PATH` in your `.desktop` launcher or a shell wrapper. To undo everything, delete the prefix
directory; nothing outside it was modified.

#### A word on stability

Since sixel exists only in VTE's development branch, this necessarily builds a development snapshot rather than a release — the
build even prints *"This is an unstable development release!"*. Two things keep that contained: the script pins one specific
commit, so the result is reproducible instead of whatever `master` happens to be today, and the library is installed into a
private prefix that only the Tilix you launch with `LD_LIBRARY_PATH` will load. Your system VTE, and therefore every other
terminal on the machine, is untouched. If Tilix starts behaving oddly after this, suspect the VTE swap first and just drop the
`LD_LIBRARY_PATH` to get back to the distro library.

### Support

If you are having issues with Tilix, feel free to open issues here in github as necessary.

### Localization

The existing translations in this repository were inherited from upstream Tilix, which is localized using the Weblate hosted
[Tilix translations site](https://hosted.weblate.org/projects/tilix/translations). tilix-next does not have its own Weblate project, so new strings
introduced here are not yet covered by that translation effort; PRs adding or updating translations for this fork's own changes are welcome directly
against this repository.

### Building

Tilix is written in [D](https://dlang.org/) and GTK 3 using the gtkd framework. This project uses dub to manage the build process including fetching the dependencies,
thus there is no need to install dependencies manually. The only thing you need to install to build the application is the D tools (compiler and Phobos) along with dub itself.
Note that D supports three [compilers](https://wiki.dlang.org/Compilers) (DMD, GDC and LDC) but Tilix only supports DMD and LDC.

Once you have those installed, compiling the application is a one line command as follows:

```
dub build --build=release
```

The application depends on various resources to function correctly, run `sudo ./install.sh` to build and copy all of the resources to the correct locations. Note this
has only been tested on Arch Linux, use with caution.
Note : `install.sh` will install Tilix to your `/usr` directory. If you are interested in installing Tilix to a custom location, you can specify the `PREFIX` as an
argument to the `install.sh` script (e.g : `./install.sh $HOME/.local` will install Tilix into `$HOME/.local`). However, this requires you to add your `$PREFIX/share`
directory to your `$XDG_DATA_DIRS` environment variable.

Note there is also support for building with the Meson buildsystem, please see the wiki page on [Meson](https://github.com/gnunn1/tilix/wiki/Building-with-Meson)
for more information.

#### Build Dependencies

Tilix depends on the following libraries as defined in dub.json:
* [gtkd](http://gtkd.org/) >= 3.11.0
* gdk-pixbuf-pixdata (Used when building resource file)

### Install Tilix

Tilix is available as [packages](https://gnunn1.github.io/tilix-web/#packages) for a variety of distributions.

#### Uninstall Tilix

This method only applies if you installed Tilix manually using the install instructions. If you installed Tilix from a distribution package then use your package manager
to remove tilix, do not use these instructions.

Download the uninstall.sh script from this repository and then open a terminal (not Tilix!) in the directory where you saved it. First set the executable flag on the script:

```
chmod +x uninstall.sh
```

and then execute it:

```
sudo sh uninstall.sh
```
