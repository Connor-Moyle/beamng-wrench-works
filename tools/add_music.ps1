# Puts music where the Wrench Works garage radio finds it.
# Converts anything ffmpeg can read (mp3, m4a, wav, flac, ...) to .ogg in your BeamNG user folder,
# under settings\slrr_garage\music. No music comes with the mod; this is how you bring your own.
#
#   .\add_music.ps1 -Source "D:\Music\Garage"     a folder, or one or more files
#   .\add_music.ps1 -Slrr                          the garage music of your own copy of
#                                                  Street Legal Racing: Redline (found through Steam,
#                                                  or say where it is with -SlrrPath)
#   -Clean    keep the sound as it is, in stereo. Without it the tracks are made mono, which the
#             game needs to place the sound at the radio, and given the narrow tone of a small speaker.
#
# Needs ffmpeg on the PATH:  winget install Gyan.FFmpeg
param(
  [string[]]$Source,
  [switch]$Slrr,
  [string]$SlrrPath,
  [switch]$Clean,
  [string]$BeamUserPath = "$env:LOCALAPPDATA\BeamNG\BeamNG.drive\current"
)
$ErrorActionPreference = 'Stop'

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) { throw 'ffmpeg was not found. Install it (winget install Gyan.FFmpeg), open a new terminal and run this again.' }

if ($Slrr -or $SlrrPath) {
  if (-not $SlrrPath) {
    # every Steam library on this PC
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $libraries = @($steam)
    $vdf = if ($steam) { Join-Path $steam 'steamapps\libraryfolders.vdf' }
    if ($vdf -and (Test-Path $vdf)) {
      $libraries += Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $SlrrPath = $libraries | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'steamapps\common\Street Legal Racing Redline' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $SlrrPath) { throw 'Street Legal Racing: Redline was not found in your Steam libraries. Say where it is with -SlrrPath.' }
  }
  $Source = @($Source) + (Join-Path $SlrrPath 'music\Garage_Shop') | Where-Object { $_ }
}
if (-not $Source) { throw 'Nothing to add. Give -Source <folder or files>, or -Slrr.' }

$files = foreach ($s in $Source) {
  if (-not (Test-Path $s)) { Write-Warning "not found: $s"; continue }
  $item = Get-Item $s
  if ($item.PSIsContainer) { Get-ChildItem $item.FullName -File | Where-Object { $_.Extension -match '^\.(mp3|m4a|aac|ogg|opus|wav|flac|wma)$' } } else { $item }
}
if (-not $files) { throw 'No music files found there.' }

$target = Join-Path $BeamUserPath 'settings\slrr_garage\music'
New-Item -ItemType Directory -Force -Path $target | Out-Null

# a small speaker: no deep bass, no sparkle, evened out a little, and one channel
$radio = 'highpass=f=200,lowpass=f=5500,acompressor=threshold=-18dB:ratio=3:attack=10:release=200,volume=1.4'
$done = 0
foreach ($f in $files) {
  $out = Join-Path $target ($f.BaseName.ToLower() + '.ogg')
  $opts = if ($Clean) { @() } else { @('-ac', '1', '-af', $radio) }
  & $ffmpeg.Source -loglevel error -y -i $f.FullName -vn @opts -c:a libvorbis -q:a 5 $out
  if ($LASTEXITCODE -eq 0) { $done++ } else { Write-Warning "could not convert $($f.Name)" }
}
"$done track(s) in $target"
