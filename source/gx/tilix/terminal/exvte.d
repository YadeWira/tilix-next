/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.terminal.exvte;

import core.sys.posix.unistd;

import std.experimental.logger;

// Same as every GID module: re-exports gulong, which is in this module's own
// public API through the signal-connection return values.
public import gid.basictypes;

import gid.gid;

import gobject.c.types : GClosure, GValue;
import gobject.dclosure : DClosure, DGClosure;
import gobject.global : signalLookup;
import gobject.value : getVal;

import vte.terminal : Terminal;
import vte.c.types : VteTerminal;

import gx.tilix.terminal.util;

enum TerminalScreen {
    NORMAL = 0,
    ALTERNATE = 1
};

/**
 * Extends default GID VTE widget to support various patches
 * which provide additional features when available.
 */
class ExtendedVTE : Terminal {

private:
    bool ignoreFirstNotification = true;

public:

    /**
	 * Sets our main struct and passes it to the parent class.
	 */
    this(void* ptr, Flag!"Take" take) nothrow {
        super(ptr, take);
    }

    /**
	 * Creates a new terminal widget.
	 *
	 * Return: a new #VteTerminal object
	 */
    this() nothrow {
        super();
    }

    debug(Destructors) {
        ~this() {
            import std.stdio: writeln;
            writeln("******** VTE Destructor");
        }
    }

	/**
	 * Emitted when a process running in the terminal wants to
	 * send a notification to the desktop environment.
	 *
	 * This signal only exists on a patched VTE; on a stock one the
	 * connection is skipped and 0 is returned, as before.
	 *
	 * Params:
	 *     summary = The summary
	 *     bod = Extra optional text
	 */
	gulong connectNotificationReceived(T)(T callback, Flag!"After" after = No.After) nothrow
	if (isCallable!T
		&& is(ReturnType!T == void)
	&& (Parameters!T.length < 1 || (ParameterStorageClassTuple!T[0] == ParameterStorageClass.none && is(Parameters!T[0] == string)))
	&& (Parameters!T.length < 2 || (ParameterStorageClassTuple!T[1] == ParameterStorageClass.none && is(Parameters!T[1] == string)))
	&& (Parameters!T.length < 3 || (ParameterStorageClassTuple!T[2] == ParameterStorageClass.none && is(Parameters!T[2] : Terminal)))
	&& Parameters!T.length < 4)
	{
		extern(C) void _cmarshal(GClosure* _closure, GValue* _returnValue, uint _nParams, const(GValue)* _paramVals, void* _invocHint, void* _marshalData) nothrow
		{
			assert(_nParams == 3, "Unexpected number of signal parameters");
			auto _dClosure = cast(DGClosure!T*)_closure;
			Tuple!(Parameters!T) _paramTuple;

			static if (Parameters!T.length > 0)
				_paramTuple[0] = getVal!(Parameters!T[0])(&_paramVals[1]);

			static if (Parameters!T.length > 1)
				_paramTuple[1] = getVal!(Parameters!T[1])(&_paramVals[2]);

			static if (Parameters!T.length > 2)
				_paramTuple[2] = getVal!(Parameters!T[2])(&_paramVals[0]);

			try
			{
				_dClosure.cb(_paramTuple[]);
			}
			catch (Exception e)
			{
				gidInvokeCallbackExceptionHandler(e, "gx.tilix.terminal.exvte.ExtendedVTE.notificationReceived");
			}
		}

		if (signalLookup("notification-received", _getGType()) == 0)
			return 0;

		auto closure = new DClosure(callback, &_cmarshal);
		return connectSignalClosure("notification-received", closure, after);
	}

	/**
	 * Emitted by a patched VTE when the terminal switches between the
	 * normal and the alternate screen. Returns 0 on a stock VTE.
	 */
	gulong connectTerminalScreenChanged(T)(T callback, Flag!"After" after = No.After) nothrow
	if (isCallable!T
		&& is(ReturnType!T == void)
	&& (Parameters!T.length < 1 || (ParameterStorageClassTuple!T[0] == ParameterStorageClass.none && is(Parameters!T[0] == int)))
	&& (Parameters!T.length < 2 || (ParameterStorageClassTuple!T[1] == ParameterStorageClass.none && is(Parameters!T[1] : Terminal)))
	&& Parameters!T.length < 3)
	{
		extern(C) void _cmarshal(GClosure* _closure, GValue* _returnValue, uint _nParams, const(GValue)* _paramVals, void* _invocHint, void* _marshalData) nothrow
		{
			assert(_nParams == 2, "Unexpected number of signal parameters");
			auto _dClosure = cast(DGClosure!T*)_closure;
			Tuple!(Parameters!T) _paramTuple;

			static if (Parameters!T.length > 0)
				_paramTuple[0] = getVal!(Parameters!T[0])(&_paramVals[1]);

			static if (Parameters!T.length > 1)
				_paramTuple[1] = getVal!(Parameters!T[1])(&_paramVals[0]);

			try
			{
				_dClosure.cb(_paramTuple[]);
			}
			catch (Exception e)
			{
				gidInvokeCallbackExceptionHandler(e, "gx.tilix.terminal.exvte.ExtendedVTE.terminalScreenChanged");
			}
		}

		if (signalLookup("terminal-screen-changed", _getGType()) == 0)
			return 0;

		auto closure = new DClosure(callback, &_cmarshal);
		return connectSignalClosure("terminal-screen-changed", closure, after);
	}

    public bool getDisableBGDraw() {
		return vte_terminal_get_disable_bg_draw(cast(VteTerminal*)this._cPtr) != 0;
    }

    public void setDisableBGDraw(bool isDisabled) {
		vte_terminal_set_disable_bg_draw(cast(VteTerminal*)this._cPtr, isDisabled);
    }

    /*
     * getColorBackgroundForDraw() used to be hand-linked here because gtk-d's
     * VTE binding predated it. GID's vte3 binds it, so the inherited
     * Terminal.getColorBackgroundForDraw(out RGBA) is used instead and the
     * COMPILE_VTE_BACKGROUND_COLOR workaround is gone. Note the signature
     * differs: GID's gdk.rgba.RGBA is a struct and the colour is an out
     * parameter, not a pre-allocated object that gets filled in.
     */

    /**
     * Returns the child pid running in the terminal or -1
     * if no child pid is running. May also return the VTE gpid
     * as well which also indicates no child process.
     */
    pid_t getChildPid() {
		if (isFlatpak()) {
            warning("getChildPid should not be called from a Flatpak environment.");
			return -1;
		} else {
			if (getPty() is null)
            	return false;
        	return tcgetpgrp(getPty().getFd());
		}
    }
}

private:

import gid.loader : gidLink, gidResolveLibs;

/*
 * Same library name GID's vte3 binding resolves against, so a patched
 * libvte-2.91-gtk4 is picked up from wherever that one was found.
 */
immutable LIBS = ["vte-2.91-gtk4_0"];

__gshared extern(C) nothrow {
	int function(VteTerminal* terminal) c_vte_terminal_get_disable_bg_draw;
	void function(VteTerminal* terminal, int isAudible) c_vte_terminal_set_disable_bg_draw;
}

alias vte_terminal_get_disable_bg_draw = c_vte_terminal_get_disable_bg_draw;
alias vte_terminal_set_disable_bg_draw = c_vte_terminal_set_disable_bg_draw;

shared static this() {
	auto libs = gidResolveLibs(LIBS);

	/*
	 * gidLink() points an unresolved symbol at a stub that throws and records
	 * the name in gid.loader.gidUnresolvedSymbols, which is what
	 * gx.gtk.vte.checkVTEFeature() reads to decide whether the patched
	 * background-draw API is available.
	 */
	gidLink(cast(void**)&vte_terminal_get_disable_bg_draw, "vte_terminal_get_disable_bg_draw", libs);
	gidLink(cast(void**)&vte_terminal_set_disable_bg_draw, "vte_terminal_set_disable_bg_draw", libs);
}
