# Builds slrr_garage.zip (without the SLRR sounds, which are not ours to hand out).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$mod = Join-Path $root 'mod'
$zip = Join-Path $root 'slrr_garage.zip'
$stage = Join-Path $env:TEMP ("slrr_garage_pkg_" + [guid]::NewGuid().ToString('N'))
Copy-Item $mod $stage -Recurse
Get-ChildItem (Join-Path $stage 'art\sound\slrr_garage') -Filter *.wav -ErrorAction SilentlyContinue | Remove-Item -Force
if (Test-Path $zip) { Remove-Item $zip -Force }
# tar writes forward-slash paths; Compress-Archive on Windows PowerShell does not, and the game needs them
& (Join-Path $env:SystemRoot 'System32/tar.exe') -a -c -f $zip -C $stage (Get-ChildItem $stage -Name)
if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
Remove-Item $stage -Recurse -Force
"Built $zip"
