# Installs the Wrench Works mod into BeamNG as an unpacked mod (a junction, so edits here are live)
# and copies the garage sounds and the garage music out of your own Street Legal Racing: Redline install.
param(
  [string]$SlrrPath = 'L:\SteamLibrary\steamapps\common\Street Legal Racing Redline',
  [string]$BeamUserPath = "$env:LOCALAPPDATA\BeamNG\BeamNG.drive\current"
)
$ErrorActionPreference = 'Stop'
$mod = Join-Path (Split-Path $PSScriptRoot -Parent) 'mod'

# sounds are not shipped with the mod; they come from the copy of SLRR you own
$soundDir = Join-Path $mod 'art\sound\slrr_garage'
New-Item -ItemType Directory -Force -Path $soundDir | Out-Null
$sounds = 'entergarage.wav','leavegarage.wav','wrench.wav','screw.wav','dragdrop.WAV','money.wav','warn.wav','flip.wav','mnuback.wav','mnuselect.wav','mnumove.wav','trash.wav','ok.wav','spray.wav','repair.wav'
foreach ($s in $sounds) {
  $src = Join-Path $SlrrPath "frontend\sounds\$s"
  if (Test-Path $src) { Copy-Item $src (Join-Path $soundDir $s.ToLower()) -Force } else { Write-Warning "missing SLRR sound: $s" }
}

# the garage's background music, likewise from your own copy (see add_music.ps1)
try { & (Join-Path $PSScriptRoot 'add_music.ps1') -SlrrPath $SlrrPath -BeamUserPath $BeamUserPath } catch { Write-Warning "garage music not installed: $_" }

$target = Join-Path $BeamUserPath 'mods\unpacked\slrr_garage'
if (Test-Path $target) {
  $item = Get-Item $target -Force
  if ($item.LinkType -ne 'Junction') { throw "$target exists and is not a junction - move it away first." }
} else {
  New-Item -ItemType Junction -Path $target -Target $mod | Out-Null
}
"Installed: $target -> $mod"
