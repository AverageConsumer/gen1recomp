# Build a Windows win64 Gen1Recomp zip with native TLS (gen1tls.dll).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 [-Version 0.1.77]
#
# Produces:
#   dist\win\gen1recomp-<version>-windows.zip
#     gen1recomp.exe   fused LÖVE + game.love
#     gen1tls.dll      Native AOT TLS dialer (Schannel via SslStream)
#
# Requires: .NET 8 SDK (for Native AOT), Git Bash, and tools/winbuild on PATH
# for pack_love.sh under Git Bash on Windows.

param(
  [string]$Version = "0.1.77"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root "main.lua"))) {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
  throw "Version must be X.Y.Z (got '$Version')"
}

$Cache = Join-Path $Root ".bazinga\cache"
$Work = Join-Path $Root ".bazinga\work"
$OutDir = Join-Path $Work "gen1recomp-win64"
$DistDir = Join-Path $Root "dist\win"
$NativeOut = Join-Path $Root "dist\native\win-x64"
$LoveZip = Join-Path $Cache "love-11.5-win64.zip"
$LoveUrl = "https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip"
$Bash = "C:\Program Files\Git\bin\bash.exe"

New-Item -ItemType Directory -Force -Path $Cache, $Work, $DistDir, $NativeOut | Out-Null

# Put zip/python shims first so pack_love.sh works in Git Bash on Windows.
$env:PATH = "$(Join-Path $Root 'tools\winbuild');$env:PATH"

Write-Host "==> building gen1tls.dll (Native AOT)"
dotnet publish (Join-Path $Root "native\tls_dial\Gen1Tls.csproj") `
  -c Release -r win-x64 -o $NativeOut
if ($LASTEXITCODE -ne 0) { throw "gen1tls publish failed" }
$TlsDll = Join-Path $NativeOut "gen1tls.dll"
if (-not (Test-Path $TlsDll)) { throw "gen1tls.dll missing after publish" }

if (-not (Test-Path $LoveZip) -or (Get-Item $LoveZip).Length -lt 1MB) {
  Write-Host "==> downloading love-11.5-win64.zip"
  Invoke-WebRequest -Uri $LoveUrl -OutFile $LoveZip -UseBasicParsing
}

Write-Host "==> packing game.love (engine $Version)"
if (-not (Test-Path $Bash)) { throw "Git Bash not found at $Bash" }
$RootPosix = ($Root -replace '\\', '/') -replace '^([A-Za-z]):', '/$1'
& $Bash -lc "cd '$RootPosix' && PATH=`"`$PWD/tools/winbuild:`$PATH`" scripts/pack_love.sh --output .bazinga/work/game.love --listing .bazinga/work/love-listing.txt --version $Version"
if ($LASTEXITCODE -ne 0) { throw "pack_love failed" }

Write-Host "==> fusing gen1recomp.exe"
$Extract = Join-Path $Work "love-win64"
Remove-Item -Recurse -Force $Extract, $OutDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Extract, $OutDir | Out-Null
Expand-Archive -Path $LoveZip -DestinationPath $Extract -Force
$LoveDir = Get-ChildItem $Extract -Directory | Select-Object -First 1
Copy-Item (Join-Path $LoveDir.FullName "*.dll") $OutDir
Copy-Item (Join-Path $LoveDir.FullName "license.txt") $OutDir -ErrorAction SilentlyContinue
Copy-Item $TlsDll $OutDir

$out = [IO.File]::Create((Join-Path $OutDir "gen1recomp.exe"))
try {
  $a = [IO.File]::OpenRead((Join-Path $LoveDir.FullName "love.exe"))
  try { $a.CopyTo($out) } finally { $a.Dispose() }
  $b = [IO.File]::OpenRead((Join-Path $Work "game.love"))
  try { $b.CopyTo($out) } finally { $b.Dispose() }
} finally { $out.Dispose() }

@"
Gen1Recomp Windows (engine $Version) — native TLS

gen1tls.dll sits next to gen1recomp.exe and exposes a non-blocking TLS
client (Windows Schannel via .NET SslStream, Native AOT). Mods can load it
through LuaJIT FFI, or call love.system.tls* on Android.

Keep gen1tls.dll beside the executable when you redistribute the zip.
"@ | Set-Content (Join-Path $OutDir "README-TLS.txt") -Encoding UTF8

$ZipOut = Join-Path $DistDir "gen1recomp-$Version-windows.zip"
Remove-Item $ZipOut -ErrorAction SilentlyContinue
Compress-Archive -Path $OutDir -DestinationPath $ZipOut -Force

Write-Host "==> built $ZipOut"
Get-Item $ZipOut | ForEach-Object { "    {0:N1} MB" -f ($_.Length / 1MB) }
Get-ChildItem $OutDir | ForEach-Object { "    $($_.Name)" }
