/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.gtk.util;

import std.conv;
import std.experimental.logger;
import std.format;
import std.process;
import std.string;

import gdk.display : Display;
import gdk.rgba : RGBA;

import gio.file : File;
import gio.list_model : ListModel;
import gio.settings : GSettings = Settings;

import glib.error : GException = ErrorWrap;
import glib.main_context : MainContext;

import gobject.global : typeName;
import gobject.types : GType, GTypeEnum;
import gobject.value : Value;

import gtk.box : Box;
import gtk.combo_box : ComboBox;
import gtk.cell_renderer_text : CellRendererText;
import gtk.entry : Entry;
import gtk.list_store : ListStore;
import gtk.paned : Paned;
import gtk.settings : Settings;
import gtk.style_context : StyleContext;
import gtk.tree_iter : TreeIter;
import gtk.tree_model : TreeModel;
import gtk.tree_path : TreePath;
import gtk.tree_store : TreeStore;
import gtk.tree_view : TreeView;
import gtk.tree_view_column : TreeViewColumn;
import gtk.types : Orientation, StateFlags;
import gtk.widget : Widget;
import gtk.window : Window;

/**
 * Parse filename and return FileIF object
 */
public File parseName(string parseName) {
    return File.parseName(parseName);
}



/**
 * Directly process events for up to a specified period
 */
void processEvents(uint millis) {
    import std.datetime.stopwatch : StopWatch, AutoStart;

    // GTK4 removed gtk_main_iteration(); drive the GLib main context directly.
    auto context = MainContext.default_();
    StopWatch sw = StopWatch(AutoStart.yes);
    scope (exit) {
        sw.stop();
    }
    while (context.pending() && sw.peek.total!"msecs" < millis) {
        context.iteration(false);
    }
}

/**
 * Activates a window using the X11 APIs when available
 */
void activateWindow(Window window) {
    if (window.isActive()) return;

    // GTK4 dropped presentWithTime() and there is no GID binding for the X11
    // backend, so the old _NET_ACTIVE_WINDOW dance in gx.gtk.x11 is gone. The
    // compositor decides whether the request is honoured.
    window.present();
}

/**
 * Returns true if running under Wayland, right now
 * it just uses a simple environment variable check to detect it.
 */
bool isWayland(Window window) {
    // GdkWindow is gone in GTK4 and GID has no gdkx11/gdkwayland bindings, so
    // the backend is identified by the display's GObject type name instead of
    // by type-checking against GdkX11Window.
    Display display = window is null ? Display.getDefault() : window.getDisplay();
    if (display !is null) {
        string name = typeName(display._gType);
        if (name.length > 0) {
            return name.indexOf("Wayland") >= 0;
        }
    }
    return environment.get("XDG_SESSION_TYPE", "x11") == "wayland"
        && environment.get("GDK_BACKEND") != "x11";
}

/**
 * Return the name of the GTK Theme
 */
string getGtkTheme() {
    Value value = new Value("");
    Settings.getDefault.getProperty("gtk-theme-name", value);
    return value.getString();
}

/**
 * Convenience method for creating a box and adding children
 */
Box createBox(Orientation orientation, int spacing,  Widget[] children) {
    Box result = new Box(orientation, spacing);
    foreach(child; children) {
        result.append(child);
    }
    return result;
}

/**
 * Finds the index position of a child in a container.
 */
int getChildIndex(Widget parent, Widget child) {
    if (parent is null || child is null) return -1;
    int i = 0;
    for (Widget c = parent.getFirstChild(); c !is null; c = c.getNextSibling()) {
        if (c._cPtr == child._cPtr) return i;
        i++;
    }
    return -1;
}

/**
 * Walks up the parent chain until it finds the parent of the
 * requested type.
 */
T findParent(T) (Widget widget) {
    while ((widget !is null)) {
        widget = widget.getParent();
        T result = cast(T) widget;
        if (result !is null) return result;
    }
    return null;
}

/**
 * Template for finding all children of a specific type
 */
T[] getChildren(T) (Widget widget, bool recursive) {
    T[] result;

    if (widget is null) return result;

    // GTK4 dropped GtkContainer and GtkBin: children hang off the widget
    // itself, so the single-child and multi-child cases are now the same walk.
    for (Widget child = widget.getFirstChild(); child !is null; child = child.getNextSibling()) {
        T match = cast(T) child;
        if (match !is null) result ~= match;
        if (recursive) {
            result ~= getChildren!(T)(child, recursive);
        }
    }
    return result;
}

/**
 * Gets the background color from style context. Works around
 * spurious VTE State messages on GTK 3.19 or later. See the
 * blog entry here: https://blogs.gnome.org/mclasen/2015/11/20/a-gtk-update/
 */
void getStyleBackgroundColor(StyleContext context, StateFlags flags, out RGBA color) {
    // gtk_style_context_get_background_color() was removed: GTK4 has no single
    // background colour for a style context, it is painted from the CSS
    // background shorthand. Callers must read a named colour instead.
    context.save();
    context.setState(flags);
    if (!context.lookupColor("theme_bg_color", color)) {
        color = RGBA(0.0f, 0.0f, 0.0f, 0.0f);
    }
    context.restore();
}

/**
 * Gets the color from style context. Works around
 * spurious VTE State messages on GTK 3.19 or later. See the
 * blog entry here: https://blogs.gnome.org/mclasen/2015/11/20/a-gtk-update/
 */
void getStyleColor(StyleContext context, StateFlags flags, out RGBA color) {
    context.save();
    context.setState(flags);
    context.getColor(color);
    context.restore();
}

/**
 * Sets all margins of a widget to the same value
 */
void setAllMargins(Widget widget, int margin) {
    setMargins(widget, margin, margin, margin, margin);
}

/**
 * Sets margins of a widget to the passed values
 */
void setMargins(Widget widget, int left, int top, int right, int bottom) {
    widget.setMarginStart(left);
    widget.setMarginTop(top);
    widget.setMarginEnd(right);
    widget.setMarginBottom(bottom);
}

/**
 * Defined here since not defined in GtkD
 */
enum MouseButton : uint {
    PRIMARY = 1,
    MIDDLE = 2,
    SECONDARY = 3
}

/**
 * Not declared in GtkD
 */
enum long GDK_CURRENT_TIME = 0;

/**
 * Compares two RGBA and returns if they are equal, supports null references
 */
bool equal(RGBA r1, RGBA r2) {
    // RGBA is a value type in GID, so there are no null references to guard.
    return r1.equal(r2);
}

bool equal(Widget w1, Widget w2) {
    if (w1 is null && w2 is null)
        return true;
    if ((w1 is null && w2 !is null) || (w1 !is null && w2 is null))
        return false;
    return w1._cPtr == w2._cPtr;
}

/**
 * Appends multiple values to a row in a list store
 */
TreeIter appendValues(TreeStore ts, TreeIter parentIter, string[] values) {
    TreeIter iter;
    ts.append(iter, parentIter);
    for (int i = 0; i < values.length; i++) {
        ts.setValue(iter, i, new Value(values[i]));
    }
    return iter;
}

/**
 * Appends multiple values to a row in a list store
 */
TreeIter appendValues(ListStore ls, string[] values) {
    TreeIter iter;
    ls.append(iter);
    for (int i = 0; i < values.length; i++) {
        ls.setValue(iter, i, new Value(values[i]));
    }
    return iter;
}

/**
 * Creates a combobox that holds a set of name/value pairs
 * where the name is displayed.
 */
ComboBox createNameValueCombo(const string[string] keyValues) {

    ListStore ls = ListStore.new_([GTypeEnum.String, GTypeEnum.String]);

    foreach (key, value; keyValues) {
        appendValues(ls, [value, key]);
    }

    ComboBox cb = ComboBox.newWithModel(ls);
    cb.setFocusOnClick(false);
    cb.setIdColumn(1);
    CellRendererText cell = new CellRendererText();
    cell.setAlignment(0, 0);
    cb.packStart(cell, false);
    cb.addAttribute(cell, "text", 0);

    return cb;
}

/**
 * Creates a combobox that holds a set of name/value pairs
 * where the name is displayed.
 */
ComboBox createNameValueCombo(const string[] names, const string[] values) {
    assert(names.length == values.length);

    ListStore ls = ListStore.new_([GTypeEnum.String, GTypeEnum.String]);

    for (int i = 0; i < names.length; i++) {
        appendValues(ls, [names[i], values[i]]);
    }

    ComboBox cb = ComboBox.newWithModel(ls);
    cb.setFocusOnClick(false);
    cb.setIdColumn(1);
    CellRendererText cell = new CellRendererText();
    cell.setAlignment(0, 0);
    cb.packStart(cell, false);
    cb.addAttribute(cell, "text", 0);

    return cb;
}

template TComboBox(T) {

    ComboBox createComboBox(const string[] names, T[] values) {
        assert(names.length == values.length);
        trace(typeof(values).stringof);

        GType valueType = GType.STRING;
        if (is(typeof(values) == int[])) valueType = GType.INT;
        else if (is(typeof(values) == uint[])) valueType = GType.INT;
        else if (is(typeof(values) == long[])) valueType = GType.INT64;
        else if (is(typeof(values) == ulong[])) valueType = GType.INT64;
        else if (is(typeof(values) == double[])) valueType = GType.DOUBLE;

        trace(valueType);

        ListStore ls = new ListStore([GType.STRING, valueType]);

        for (int row; row < values.length; row++) {
            TreeIter iter = ls.createIter();
            ls.setValue(iter, 0, names[row]);
            ls.setValue(iter, 1, values[row]);
        }

        ComboBox cb = ComboBox.newWithModel(ls);
        cb.setFocusOnClick(false);
        cb.setIdColumn(1);
        CellRendererText cell = new CellRendererText();
        cell.setAlignment(0, 0);
        cb.packStart(cell, false);
        cb.addAttribute(cell, "text", 0);
        return cb;
    }
}

/**
 * Selects the specified row in a Treeview
 */
void selectRow(TreeView tv, int row, TreeViewColumn column = null) {
    TreeModel model = tv.getModel();
    TreeIter iter;
    model.iterNthChild(iter, null, row);
    if (iter !is null) {
        tv.setCursor(model.getPath(iter), column, false);
    } else {
        tracef("No TreeIter found for row %d", row);
    }
}

/**
 * An implementation of a range that allows using foreach with a TreeModel and TreeIter
 */
struct TreeIterRange {

private:
    TreeModel model;
    TreeIter iter;
    bool _empty;

public:
    this(TreeModel model) {
        this.model = model;
        _empty = !model.getIterFirst(iter);
    }

    this(TreeModel model, TreeIter parent) {
        this.model = model;
        _empty = !model.iterChildren(iter, parent);
        if (_empty) trace("TreeIter has no children");
    }

    @property bool empty() {
        return _empty;
    }

    @property auto front() {
        return iter;
    }

    void popFront() {
        _empty = !model.iterNext(iter);
    }

    /**
     * Based on the example here https://www.sociomantic.com/blog/2010/06/opapply-recipe/#.Vm8mW7grKEI
     */
    int opApply(int delegate(ref TreeIter iter) dg) {
        int result = 0;
        //bool hasNext = model.getIterFirst(iter);
        bool hasNext = !_empty;
        while (hasNext) {
            result = dg(iter);
            if (result) {
                break;
            }
            hasNext = model.iterNext(iter);
        }
        return result;
    }
}
