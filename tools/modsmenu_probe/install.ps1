# Test only: copies the probe mod into BeamNG as an unpacked mod (restart the game, or reload the mods, then open the pause menu in freeroam and in the career).
param([string]$BeamUserPath = "$env:LOCALAPPDATA\BeamNG\BeamNG.drive\current")
$src = Join-Path $PSScriptRoot 'mod'
$dst = Join-Path $BeamUserPath 'mods\unpacked\slrr_menu_probe'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item (Join-Path $src '*') $dst -Recurse -Force
"Installed: $dst  (remove the folder when done)"
