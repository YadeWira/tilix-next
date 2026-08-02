/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.terminal.advpaste;

import std.experimental.logger;
import std.format;
import std.string;
import std.typecons : No;

import gdk.types : KEY_Return, ModifierType;

import gio.settings : GSettings = Settings;
import gio.types : SettingsBindFlags;

import gtk.box : Box;
import gtk.check_button : CheckButton;
import gtk.dialog : Dialog;
import gtk.event_controller_key : EventControllerKey;
import gtk.label : Label;
import gtk.spin_button : SpinButton;
import gtk.text_buffer : TextBuffer;
import gtk.text_iter : TextIter;
import gtk.text_tag_table : TextTagTable;
import gtk.text_view : TextView;
import gtk.scrolled_window : ScrolledWindow;
import gtk.types : Align, Orientation, PolicyType, PropagationPhase, ResponseType;
import gtk.window : Window;

import gx.i18n.l10n;

import gx.tilix.preferences;

string[3] getUnsafePasteMessage() {
    string[3] result = [_("This command is asking for Administrative access to your computer"),
                        _("Copying commands from the internet can be dangerous. "),
                        _("Be sure you understand what each part of this command does.")];

    return result;
}

/**
 * A dialog that is shown to support advance paste. It allows the user
 * to review and edit the content as well as performing various transformations
 * before pasting.
 */
class AdvancedPasteDialog: Dialog {

private:

    GSettings gsSettings;

    TextBuffer buffer;
    CheckButton cbTabsToSpaces;
    SpinButton sbTabWidth;

    CheckButton cbConvertCRLF;

    void createUI(string text, bool unsafe) {
        with (getContentArea()) {
            setMarginStart(18);
            setMarginEnd(18);
            setMarginTop(18);
            setMarginBottom(18);
        }

        Box b = new Box(Orientation.Vertical, 6);
        if (unsafe) {
            string[3] msg = getUnsafePasteMessage();
            Label lblUnsafe = new Label("<span weight='bold' size='large'>" ~ msg[0] ~ "</span>\n" ~ msg[1] ~ "\n" ~ msg[2]);
            lblUnsafe.setUseMarkup(true);
            lblUnsafe.setWrap(true);
            b.append(lblUnsafe);
            // GTK4 removed the style context class API, the class goes on the widget itself now.
            getWidgetForResponse(ResponseType.Apply).addCssClass("destructive-action");
        }

        buffer = new TextBuffer(new TextTagTable());
        buffer.setText(text);
        TextView view = TextView.newWithBuffer(buffer);
        // GTK4 has no key-press-event signal, key handling is an event controller. The GTK3
        // handler ran ahead of the TextView's own default handler, so use the capture phase
        // to keep Ctrl+Return from being swallowed as a newline.
        EventControllerKey kc = new EventControllerKey();
        kc.setPropagationPhase(PropagationPhase.Capture);
        kc.connectKeyPressed(delegate(uint keyval, uint keycode, ModifierType state) {
            if (keyval == KEY_Return && (state & ModifierType.ControlMask)) {
                response(ResponseType.Apply);
                return true;
            }
            return false;
        });
        view.addController(kc);
        ScrolledWindow sw = new ScrolledWindow();
        sw.setChild(view);
        // GTK4 replaced GtkScrolledWindow's shadow-type with the boolean has-frame.
        sw.setHasFrame(true);
        sw.setPolicy(PolicyType.Automatic, PolicyType.Automatic);
        sw.setHexpand(true);
        sw.setVexpand(true);
        sw.setSizeRequest(400, 140);

        b.append(sw);

        Label lblTransform = new Label(format("<b>%s</b>", _("Transform")));
        lblTransform.setUseMarkup(true);
        lblTransform.setHalign(Align.Start);
        lblTransform.setMarginTop(6);
        b.append(lblTransform);

        //Tabs to Spaces
        Box bTabs = new Box(Orientation.Horizontal, 6);
        cbTabsToSpaces = CheckButton.newWithMnemonic(_("Convert spaces to tabs"));
        gsSettings.bind(SETTINGS_ADVANCED_PASTE_REPLACE_TABS_KEY, cbTabsToSpaces, "active", SettingsBindFlags.Default);
        bTabs.append(cbTabsToSpaces);

        sbTabWidth = SpinButton.newWithRange(0, 32, 1);
        gsSettings.bind(SETTINGS_ADVANCED_PASTE_SPACE_COUNT_KEY, sbTabWidth.getAdjustment(), "value", SettingsBindFlags.Default);
        gsSettings.bind(SETTINGS_ADVANCED_PASTE_REPLACE_TABS_KEY, sbTabWidth, "sensitive", SettingsBindFlags.Default);
        bTabs.append(sbTabWidth);

        b.append(bTabs);

        cbConvertCRLF = CheckButton.newWithMnemonic(_("Convert CRLF and CR to LF"));
        gsSettings.bind(SETTINGS_ADVANCED_PASTE_REPLACE_CRLF_KEY, cbConvertCRLF, "active", SettingsBindFlags.Default);
        b.append(cbConvertCRLF);

        getContentArea().append(b);
    }

    string transform() {
        // GID has no argument-less TextBuffer.getText(); gtk-d's built the bounds and
        // called get_slice with hidden characters included, so do that here.
        TextIter start, end;
        buffer.getBounds(start, end);
        string text = buffer.getSlice(start, end, true);
        if (gsSettings.getBoolean(SETTINGS_ADVANCED_PASTE_REPLACE_TABS_KEY)) {
            text = text.detab(gsSettings.getInt(SETTINGS_ADVANCED_PASTE_SPACE_COUNT_KEY));
        }
        if (gsSettings.getBoolean(SETTINGS_ADVANCED_PASTE_REPLACE_CRLF_KEY)) {
            text = text.replace("\r\n", "\n");
            text = text.replace("\r", "\n");

        }
        return text;
    }

public:
    this(Window parent, string text, bool unsafe) {
        // GID does not bind the variadic gtk_dialog_new_with_buttons, and use-header-bar is
        // construct-only, so the instance has to come from the GID builder to keep the header
        // bar. Everything the old constructor arguments carried is set explicitly below.
        super(cast(void*) Dialog.builder().useHeaderBar(1).createGObject(Dialog._getGType), No.Take);
        setTitle(_("Advanced Paste"));
        setModal(true);
        addButton(_("Paste"), ResponseType.Apply);
        addButton(_("Cancel"), ResponseType.Cancel);
        setTransientFor(parent);
        setDefaultResponse(ResponseType.Apply);
        gsSettings = new GSettings(SETTINGS_ID);
        createUI(text, unsafe);
    }

    @property string text() {
        return transform();
    }
}
