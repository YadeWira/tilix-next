/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.terminal.search;

import std.experimental.logger;
import std.format;

import gdk.types : KEY_Escape, KEY_Return, ModifierType;

import gio.action_group : ActionGroup;
import gio.menu : Menu;
import gio.settings : GSettings = Settings;
import gio.simple_action : SimpleAction;
import gio.simple_action_group : SimpleActionGroup;

import glib.error : GException = ErrorWrap;
import glib.regex: GRegex = Regex;
import glib.variant : GVariant = Variant;

import gtk.box : Box;
import gtk.button : Button;
import gtk.check_button : CheckButton;
import gtk.event_controller_focus : EventControllerFocus;
import gtk.event_controller_key : EventControllerKey;
import gtk.frame : Frame;
import gtk.image : Image;
import gtk.menu_button : MenuButton;
import gtk.popover : Popover;
import gtk.popover_menu : PopoverMenu;
import gtk.revealer : Revealer;
import gtk.root : Root;
import gtk.search_entry : SearchEntry;
import gtk.toggle_button : ToggleButton;
import gtk.types : Align, Orientation;
import gtk.widget : Widget;

import vte.regex: VRegex = Regex;
import vte.terminal : VTE = Terminal;

import gx.gtk.actions;
import gx.gtk.vte;
import gx.i18n.l10n;

import gx.tilix.common;
import gx.tilix.constants;
import gx.tilix.preferences;
import gx.tilix.terminal.actions;

/**
 * Widget that displays the Find UI for a terminal and manages the search actions
 */
class SearchRevealer : Revealer {

private:

    enum ACTION_SEARCH_PREFIX = "search";
    enum ACTION_SEARCH_MATCH_CASE = "match-case";
    enum ACTION_SEARCH_ENTIRE_WORD_ONLY = "entire-word";
    enum ACTION_SEARCH_MATCH_REGEX = "match-regex";
    enum ACTION_SEARCH_WRAP_AROUND = "wrap-around";

    GSettings gsSettings;

    VTE vte;
    ActionGroup terminalActions;
    SimpleActionGroup sagSearch;

    SearchEntry seSearch;

    MenuButton mbOptions;
    bool matchCase;
    bool entireWordOnly;
    bool matchAsRegex;

    /**
     * Creates the find overlay
     */
    void createUI() {
        createActions();

        setHexpand(true);
        setVexpand(false);
        setHalign(Align.Fill);
        setValign(Align.Start);

        Box bSearch = new Box(Orientation.Horizontal, 6);
        bSearch.setHalign(Align.Center);
        bSearch.setMarginStart(4);
        bSearch.setMarginEnd(4);
        bSearch.setMarginTop(4);
        bSearch.setMarginBottom(4);
        bSearch.setHexpand(true);

        Box bEntry = new Box(Orientation.Horizontal, 0);
        bEntry.addCssClass("linked");

        seSearch = new SearchEntry();
        seSearch.setWidthChars(1);
        seSearch.setMaxWidthChars(30);
        // The "tilix-search-entry" padding workaround was only applied when
        // gtk_check_version(3, 20, 0) reported a mismatch, i.e. on GTK older than
        // 3.20; it was already dead on any GTK 3.20+ runtime. It cannot be kept as
        // written: under GTK4 gtk_check_version(3, 20, 0) reports "version too new
        // (major mismatch)", which is also a non-empty string, so the branch would
        // start firing on every run. Dropped so behaviour matches GTK 3.20+.
        seSearch.connectSearchChanged(delegate() {
            setTerminalSearchCriteria();
        });
        // GTK4: key events are delivered through an EventControllerKey instead of
        // GtkWidget::key-release-event. The modifier state is a signal parameter now,
        // there is no GdkEvent to unpack, and the handler cannot stop propagation
        // (key-released has no return value) - the GTK3 code returned false anyway.
        EventControllerKey ecKey = new EventControllerKey();
        ecKey.connectKeyReleased(delegate(uint keyval, uint keycode, ModifierType state) {
            switch (keyval) {
                case KEY_Escape:
                    setRevealChild(false);
                    vte.grabFocus();
                    break;
                case KEY_Return:
                    if (state & ModifierType.ShiftMask) {
                        terminalActions.activateAction(ACTION_FIND_NEXT, null);
                    } else {
                        terminalActions.activateAction(ACTION_FIND_PREVIOUS, null);
                    }
                    break;
                default:
            }
        });
        seSearch.addController(ecKey);
        bEntry.append(seSearch);

        mbOptions = new MenuButton();
        mbOptions.setTooltipText(_("Search Options"));
        mbOptions.setFocusOnClick(false);
        Image iHamburger = Image.newFromIconName("pan-down-symbolic");
        mbOptions.setChild(iHamburger);
        mbOptions.setPopover(createPopover);
        bEntry.append(mbOptions);

        bSearch.append(bEntry);

        Box bButtons = new Box(Orientation.Horizontal, 0);
        bButtons.addCssClass("linked");

        Button btnNext = Button.newFromIconName("go-up-symbolic");
        btnNext.setTooltipText(_("Find next"));
        btnNext.setActionName(getActionDetailedName(ACTION_PREFIX, ACTION_FIND_PREVIOUS));
        btnNext.setCanFocus(false);
        bButtons.append(btnNext);

        Button btnPrevious = Button.newFromIconName("go-down-symbolic");
        btnPrevious.setTooltipText(_("Find previous"));
        btnPrevious.setActionName(getActionDetailedName(ACTION_PREFIX, ACTION_FIND_NEXT));
        btnPrevious.setCanFocus(false);
        bButtons.append(btnPrevious);

        bSearch.append(bButtons);

        Button btnClose = Button.newFromIconName("window-close-symbolic");
        btnClose.setTooltipText(_("Close search box"));
        // GTK4: GtkReliefStyle is gone, gtk_button_set_has_frame(false) is the replacement.
        btnClose.setHasFrame(false);
        btnClose.setFocusOnClick(true);
        btnClose.connectClicked(delegate() {
            setRevealChild(false);
            vte.grabFocus();
        });
        // GTK4: no gtk_box_pack_end. The close button was the last child of a
        // horizontal box anyway, so appending puts it in the same place.
        bSearch.append(btnClose);

        Frame frame = new Frame(null);
        frame.setChild(bSearch);
        // GTK4: GtkFrame has no shadow type any more, framing is done purely with CSS.
        frame.addCssClass("tilix-search-frame");
        setChild(frame);
    }

    void createActions() {
        GSettings gsGeneral = new GSettings(SETTINGS_ID);

        sagSearch = new SimpleActionGroup();

        registerAction(sagSearch, ACTION_SEARCH_PREFIX, ACTION_SEARCH_MATCH_CASE, null, delegate(GVariant value, SimpleAction sa) {
            matchCase = !sa.getState().getBoolean();
            sa.setState(new GVariant(matchCase));
            setTerminalSearchCriteria();
        }, null, gsGeneral.getValue(SETTINGS_SEARCH_DEFAULT_MATCH_CASE));

        registerAction(sagSearch, ACTION_SEARCH_PREFIX, ACTION_SEARCH_ENTIRE_WORD_ONLY, null, delegate(GVariant value, SimpleAction sa) {
            entireWordOnly = !sa.getState().getBoolean();
            sa.setState(new GVariant(entireWordOnly));
            setTerminalSearchCriteria();
        }, null, gsGeneral.getValue(SETTINGS_SEARCH_DEFAULT_MATCH_ENTIRE_WORD));

        registerAction(sagSearch, ACTION_SEARCH_PREFIX, ACTION_SEARCH_MATCH_REGEX, null, delegate(GVariant value, SimpleAction sa) {
            matchAsRegex = !sa.getState().getBoolean();
            sa.setState(new GVariant(matchAsRegex));
            setTerminalSearchCriteria();
        }, null, gsGeneral.getValue(SETTINGS_SEARCH_DEFAULT_MATCH_AS_REGEX));

        registerAction(sagSearch, ACTION_SEARCH_PREFIX, ACTION_SEARCH_WRAP_AROUND, null, delegate(GVariant value, SimpleAction sa) {
            bool newState = !sa.getState().getBoolean();
            sa.setState(new GVariant(newState));
            vte.searchSetWrapAround(newState);
        }, null, gsGeneral.getValue(SETTINGS_SEARCH_DEFAULT_WRAP_AROUND));

        updateActionsState ();
        insertActionGroup(ACTION_SEARCH_PREFIX, sagSearch);
    }

    Popover createPopover() {
        Menu model = new Menu();
        model.append(_("Match case"), getActionDetailedName(ACTION_SEARCH_PREFIX, ACTION_SEARCH_MATCH_CASE));
        model.append(_("Match entire word only"), getActionDetailedName(ACTION_SEARCH_PREFIX, ACTION_SEARCH_ENTIRE_WORD_ONLY));
        model.append(_("Wrap around"), getActionDetailedName(ACTION_SEARCH_PREFIX, ACTION_SEARCH_WRAP_AROUND));
        model.append(_("Match as regular expression"), getActionDetailedName(ACTION_SEARCH_PREFIX, ACTION_SEARCH_MATCH_REGEX));

        // GTK4: popovers have no relative-to widget, they are positioned by the
        // widget they get attached to (the MenuButton below).
        return PopoverMenu.newFromModel(model);
    }

    void updateActionsState()
    {
        auto action = cast(SimpleAction) sagSearch.lookupAction(ACTION_SEARCH_MATCH_REGEX);
        bool alwaysUseRegex = gsSettings.getBoolean(SETTINGS_ALWAYS_USE_REGEX_IN_SEARCH);
        action.setEnabled(!alwaysUseRegex);
        action.setState(new GVariant(alwaysUseRegex));
        matchAsRegex = alwaysUseRegex;
    }

    void setTerminalSearchCriteria() {
        string text = seSearch.getText();
        if (text.length == 0) {
            vte.searchSetRegex(null, 0);
            return;
        }

        if (!matchAsRegex)
            text = GRegex.escapeString(text);
        if (entireWordOnly)
            text = format("\\b%s\\b", text);

        try {
            uint flags = PCRE2Flags.UTF | PCRE2Flags.MULTILINE | PCRE2Flags.NO_UTF_CHECK;
            if (!matchCase) {
                flags |= PCRE2Flags.CASELESS;
            }
            trace("Setting VTE.Regex for pattern %s", text);
            vte.searchSetRegex(VRegex.newForSearch(text, flags), 0);
            seSearch.removeCssClass("error");
        } catch (GException ge) {
            string message = format(_("Search '%s' is not a valid regex\n%s"), text, ge.msg);
            seSearch.addCssClass("error");
            error(message);
            error(ge.msg);
        }
    }

public:

    this(VTE vte, ActionGroup terminalActions) {
        super();

        this.vte = vte;
        this.terminalActions = terminalActions;

        gsSettings = new GSettings(SETTINGS_ID);
        createUI();
        gsSettings.connectChanged(null, delegate(string key) {
            if (key == SETTINGS_ALWAYS_USE_REGEX_IN_SEARCH)
                updateActionsState();
        });

        this.connectDestroy(delegate() {
            this.vte = null;
            this.terminalActions = null;
        });
        // GTK4: GtkWidget::focus-in-event is gone, focus is reported by an
        // EventControllerFocus. The controller only passes itself to the handler,
        // so the widget the signal is about is the entry the controller is on.
        EventControllerFocus ecFocus = new EventControllerFocus();
        ecFocus.connectEnter(delegate() {
            onSearchEntryFocusIn.emit(seSearch);
        });
        // Note: the GTK3 code connected this to focus-in as well, not focus-out,
        // so it is kept on ::enter here to preserve the existing behaviour.
        ecFocus.connectEnter(delegate() {
            onSearchEntryFocusOut.emit(seSearch);
        });
        seSearch.addController(ecFocus);
    }

    void focusSearchEntry() {
        seSearch.grabFocus();
    }

    /**
     * Whether keyboard focus is inside the search entry.
     *
     * GTK3's GtkSearchEntry was a GtkEntry and took focus itself, so asking the
     * widget was enough. In GTK4 it is a plain GtkWidget that is not focusable
     * and wraps an internal GtkText; the root's focus widget is that GtkText,
     * never the SearchEntry, so seSearch.hasFocus() would answer false the whole
     * time the user is typing. Resolve it through the focused descendant instead.
     */
    private bool searchEntryHoldsFocus() {
        Root root = seSearch.getRoot();
        if (root is null) return false;
        Widget focus = root.getFocus();
        if (focus is null) return false;
        return focus is seSearch || focus.isAncestor(seSearch);
    }

    bool hasSearchEntryFocus() {
        return searchEntryHoldsFocus();
    }

    bool isSearchEntryFocus() {
        return searchEntryHoldsFocus();
    }

    GenericEvent!(Widget) onSearchEntryFocusIn;

    GenericEvent!(Widget) onSearchEntryFocusOut;
}
