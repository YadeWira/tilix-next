/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.shortcuts;

import std.algorithm;
import std.experimental.logger;
import std.path;

import gio.settings : GSettings = Settings;

import gtk.builder : Builder;
import gtk.shortcuts_group : ShortcutsGroup;
import gtk.shortcuts_section : ShortcutsSection;
import gtk.shortcuts_shortcut : ShortcutsShortcut;
import gtk.shortcuts_window : ShortcutsWindow;

import gx.gtk.actions;
import gx.i18n.l10n;

import gx.tilix.constants;
import gx.tilix.preferences;

public:

ShortcutsWindow getShortcutWindow() {
    // Force registration of these GTypes before parsing the resource below.
    // On some systems (see gnunn1/tilix#2178) nothing has instantiated them
    // yet by this point, and GtkBuilder fails with "Invalid object type
    // 'GtkShortcutsWindow'" because it can't resolve a type it has never seen.
    cast(void) ShortcutsWindow._getGType();
    cast(void) ShortcutsSection._getGType();
    cast(void) ShortcutsGroup._getGType();
    cast(void) ShortcutsShortcut._getGType();

    Builder builder = new Builder();
    builder.setTranslationDomain(TILIX_DOMAIN);
    if (!builder.addFromResource(SHORTCUT_UI_RESOURCE)) {
        error("Could not load shortcuts from " ~ SHORTCUT_UI_RESOURCE);
        return null;
    }
    GSettings gsShortcuts = new GSettings(SETTINGS_KEY_BINDINGS_ID);
    string[] keys = gsShortcuts.listKeys();
    foreach(key; keys) {
        ShortcutsShortcut ss = cast(ShortcutsShortcut) builder.getObject(key);
        if (ss !is null) {
            string accelName = gsShortcuts.getString(key);
            if (accelName == SHORTCUT_DISABLED) accelName.length = 0;
            ss.setProperty("accelerator", accelName);
        } else {
            trace("Could not find shortcut for " ~ key);
        }
    }

    // Add Profile shortcuts to window
    ShortcutsGroup sgProfile = cast(ShortcutsGroup) builder.getObject("profile");
    if (sgProfile !is null) {
        string[] uuids = prfMgr.getProfileUUIDs();
        foreach (uuid; uuids) {
            GSettings gsProfile = prfMgr.getProfileSettings(uuid);
            if (gsProfile !is null) {
                string accelName = gsProfile.getString(SETTINGS_PROFILE_SHORTCUT_KEY);
                if (accelName == SHORTCUT_DISABLED) accelName.length = 0;
                trace("Create ShortcutShortcut");
                // Built through GID's fluent builder, which is its binding for
                // g_object_new_with_properties(). Do NOT use new ObjectWrap(GType) here:
                // it takes ownership, and for a floating GInitiallyUnowned (which every
                // GtkWidget is) GID sinks the float *and* drops the taken reference, so
                // the widget is finalised inside the constructor. The builder wraps with
                // No.Take and gets the refcount right. It also yields a properly typed
                // ShortcutsShortcut: unlike gtk-d's ObjectG, GID's ObjectWrap has no
                // opCast, so downcasting a bare ObjectWrap would always give null.
                ShortcutsShortcut ss = ShortcutsShortcut.builder()
                    .title(gsProfile.getString(SETTINGS_PROFILE_VISIBLE_NAME_KEY))
                    .accelerator(accelName)
                    .build();
                if (ss !is null) {
                    sgProfile.addShortcut(ss);
                } else {
                    trace("Profile ShortcutShortcut is null");
                }
            }
        }
    } else {
        trace("Didn't find profile ShortcutGroup");
    }

    return cast(ShortcutsWindow) builder.getObject("shortcuts-tilix");
}