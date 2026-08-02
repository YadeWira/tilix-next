/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.gtk.threads;

import std.experimental.logger;

import glib.global : idleAdd, timeoutAdd;
import glib.types : PRIORITY_DEFAULT, PRIORITY_DEFAULT_IDLE, SourceFunc;

/**
 * Schedules a delegate to be run on the main loop once it is idle. The
 * delegate returns whether it wants to be run again, exactly like a
 * GSourceFunc.
 *
 * GTK4 removed the gdk_threads_* family along with the GDK lock, so this now
 * calls GLib directly. GID passes D delegates through to g_idle_add itself,
 * which is why none of the DelegatePointer/GC.addRoot marshalling that the
 * gtk-d version needed is here any more.
 */
void threadsAddIdleDelegate(SourceFunc theDelegate) {
    idleAdd(PRIORITY_DEFAULT_IDLE, () {
        try {
            return theDelegate();
        } catch (Exception e) {
            warningf("Unexpected exception in idle callback: %s", e.msg);
            return false;
        }
    });
}

/**
 * Schedules a delegate to be run on the main loop every interval milliseconds
 * until it returns false. Returns the source id so the caller can cancel it.
 */
uint threadsAddTimeoutDelegate(uint interval, SourceFunc theDelegate) {
    return timeoutAdd(PRIORITY_DEFAULT, interval, () {
        try {
            return theDelegate();
        } catch (Exception e) {
            warningf("Unexpected exception in timeout callback: %s", e.msg);
            return false;
        }
    });
}
