#!/usr/bin/env bash
# The Mods menu, end to end in the running game (tester: connor-80). Needs a running game with Wrench Works and the other mods installed (a career is not needed).
#   bash tools/qa/mods_walkthrough.sh                        native resolution
#   bash tools/qa/mods_walkthrough.sh --res 1920x1080,3440x1440   also each of these (set from Lua: windowed or fullscreen; the screen must be at least that big)
# 1. Data level: for every mod and tab one value is changed, read back from its store and restored; every Quick setup preset is applied and the current preset checked; the search works.
# 2. Screens: every mod page and tab, the search page and Quick setup are opened as a screen (route menu.slrrMods, extensions.ui_router.navigate), and screenshotted as
#    mods_<mod>_<tab>.jpg (mods_find.jpg, mods_quick.jpg; _<W>x<H> added for a resolution other than the native one). The pause menu cards show the same components; the tab
#    and the cards in the ESC menu itself are looked at by hand (core_gamestate and keys cannot open it from outside).
# Output: the lines of the check, the screenshot folder ($QA_SHOT_DIR, default ./mods_shots), exit code 1 if a data check failed.
QA_LIB="${QA_LIB:-/c/Dev/SLRR BeamNG Graph/tools/qa_game/lib.sh}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES=""
while [ $# -gt 0 ]; do case "$1" in --res) RES="$2"; shift 2;; *) shift;; esac; done
# shellcheck disable=SC1090
source "$QA_LIB"
PROBES="$HERE"                      # (the probes of this folder: mods_data.lua)
OUT="${QA_SHOT_DIR:-./mods_shots}"; mkdir -p "$OUT"

# The display is changed only with --res; its original resolution and window mode are read first, written to a file and always put back at the end (also when the script fails or
# is stopped). By hand: bash tools/qa/mods_restore_display.sh   (or the line it prints).
ORIG_FILE="$OUT/original_display.txt"
restore_display() {
  [ -n "$RES" ] || return 0
  local res mode
  res="$(cut -d'|' -f1 "$ORIG_FILE" 2>/dev/null)"; mode="$(cut -d'|' -f2 "$ORIG_FILE" 2>/dev/null)"
  [ -n "$res" ] || return 0
  R "settings.setValue('GraphicDisplayResolutions', '$res') if '$mode' ~= '' then settings.setValue('GraphicDisplayModes', '$mode') end if core_settings_graphic and core_settings_graphic.applyGraphicsState then core_settings_graphic.applyGraphicsState() end return 1" > /dev/null
  echo "display restored to: $res $mode"
}
if [ -n "$RES" ]; then
  R "return tostring(settings.getValue('GraphicDisplayResolutions')) .. '|' .. tostring(settings.getValue('GraphicDisplayModes'))" | tr -d '' | head -1 > "$ORIG_FILE"
  echo "original display: $(cat "$ORIG_FILE")  (saved in $ORIG_FILE; to restore by hand: bash tools/qa/mods_restore_display.sh \"$ORIG_FILE\")"
  trap restore_display EXIT INT TERM
fi

echo "== data level"
check "mods menu: data check" mods_data.lua

shotpage() {   # shotpage <name> <lua params>
  local name="$1" params="$2" out
  out="$(R "local r = extensions.ui_router.navigate('menu.slrrMods', $params) return dumps(r)" | tr -d '\r' | head -c 300)"
  case "$out" in *success*false*|*error*|*fail*) rec "open $name" FAIL "$out"; return;; esac
  nap 2.5
  # the MCP screenshot does not include the pause menu or the router screens drawn by the UI: the whole desktop is copied instead (the game window must be in front)
  powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size); $bmp.Save('$(cygpath -w "$OUT/$name.jpg")',[System.Drawing.Imaging.ImageFormat]::Jpeg)" > /dev/null 2>&1
  rec "screen $name" INFO "$OUT/$name.jpg ($out)"
}

walk() {       # walk <suffix>
  local suf="$1" mod tab
  R "local o = {} for _, m in ipairs(slrr_settings.mods()) do for _, t in ipairs(m.tabs) do o[#o + 1] = m.mod .. '|' .. t.id end end return table.concat(o, '\n')" | tr -d '\r' | while IFS='|' read -r mod tab; do
    [ -n "$mod" ] && [ -n "$tab" ] && shotpage "mods_${mod}_${tab}${suf}" "{page='mod', mod='$mod', tab='$tab'}"
  done
  shotpage "mods_find${suf}" "{page='find'}"
  shotpage "mods_quick${suf}" "{page='quick'}"
}

echo "== screens (native)"
walk ""
for r in $(echo "$RES" | tr ',' ' '); do
  w="${r%x*}"; h="${r#*x}"
  echo "== screens ($r)"
  R "settings.setValue('GraphicDisplayResolutions', '$w $h') if core_settings_graphic and core_settings_graphic.applyGraphicsState then core_settings_graphic.applyGraphicsState() end return 1" > /dev/null
  nap 5
  walk "_${r}"
done
R "pcall(extensions.ui_router.navigate, 'play') return 1" > /dev/null

fails="$(grep -c "	FAIL	" "$RESULTS" 2>/dev/null || true)"
echo "== done: $fails failed; screenshots in $OUT; results in $RESULTS"
[ "${fails:-0}" -eq 0 ]
