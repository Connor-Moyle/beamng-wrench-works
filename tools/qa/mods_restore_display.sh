#!/usr/bin/env bash
# Puts the display resolution and window mode back after tools/qa/mods_walkthrough.sh --res ... (it does this itself at the end; this is for when it was killed).
#   bash tools/qa/mods_restore_display.sh [path to original_display.txt]    (default ./mods_shots/original_display.txt)
# Without the file, the line to run in the game's Lua console is printed instead of guessing.
QA_LIB="${QA_LIB:-/c/Dev/SLRR BeamNG Graph/tools/qa_game/lib.sh}"
FILE="${1:-${QA_SHOT_DIR:-./mods_shots}/original_display.txt}"
# shellcheck disable=SC1090
source "$QA_LIB"
if [ ! -s "$FILE" ]; then echo "no $FILE: set it by hand in Options > Graphics, or in the Lua console: settings.setValue('GraphicDisplayResolutions','<W> <H>') core_settings_graphic.applyGraphicsState()"; exit 1; fi
res="$(cut -d'|' -f1 "$FILE")"; mode="$(cut -d'|' -f2 "$FILE")"
R "settings.setValue('GraphicDisplayResolutions', '$res') if '$mode' ~= '' and '$mode' ~= 'nil' then settings.setValue('GraphicDisplayModes', '$mode') end if core_settings_graphic and core_settings_graphic.applyGraphicsState then core_settings_graphic.applyGraphicsState() end return 1"
echo "display set to: $res $mode"
