#!/usr/bin/env sh
# tilix-copy: send stdin to the local clipboard through a Tilix "ClipboardPrompt"
# trigger, without relying on OSC 52 (which VTE deliberately does not support,
# see https://github.com/gnunn1/tilix/issues/2198).
#
# Unlike OSC 52, this never writes to the clipboard silently: it only prints a
# plain, visible marker line; Tilix must have a trigger configured to react to
# it, and even then the user has to click "Copy" on the InfoBar that appears.
#
# Usage:
#   printf '%s' "some text" | tilix-copy
#   tilix-copy < file.txt
#
# In vim, yank to the local clipboard over SSH with e.g.:
#   vnoremap <leader>y :w !tilix-copy<CR><CR>
#
# Setup (one time, in Tilix Preferences -> Profile -> Triggers):
#   Regex:      TILIX-CLIP:([A-Za-z0-9+/=]+)
#   Action:     ClipboardPrompt
#   Parameter:  $1

set -eu

encoded=$(base64 | tr -d '\n')
printf 'TILIX-CLIP:%s\n' "$encoded" > /dev/tty
