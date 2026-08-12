#!/usr/bin/env bash
# After first boot of a compatible Linux ARM handheld (or when PortMaster is installed), reinsert the
# SD card and run this to install gen1recomp-sbc + Red/Blue ROMs into Roms/PORTS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGE="$ROOT/.bazinga/work/linux-arm-sbc-install"
DECPREP="${DECPREP:-$ROOT/../decprep}"
ZIP="$ROOT/dist/linux-arm-sbc/gen1recomp-sbc-portmaster.zip"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Find a mounted handheld userdata volume with a ROMs or Apps directory.
find_roms_root() {
  local v candidate
  for v in /Volumes/*; do
    [ -d "$v" ] || continue
    # Prefer a volume that already has Roms/ or Apps/
    if [ -d "$v/Roms" ] || [ -d "$v/roms" ] || [ -d "$v/PORTS" ] || [ -d "$v/ports" ] || [ -d "$v/Apps" ]; then
      echo "$v"
      return 0
    fi
  done
  # Fallback: common removable-volume labels
  for v in /Volumes/SDCARD /Volumes/sdcard /Volumes/NO\ NAME /Volumes/ROMS; do
    if [ -d "$v" ]; then
      echo "$v"
      return 0
    fi
  done
  return 1
}

say "looking for handheld SD volume"
ROMS_ROOT="$(find_roms_root)" || fail "no SD volume mounted. boot the handheld once, power it off, reinsert the SD, then rerun."

say "using: $ROMS_ROOT"
# Resolve the device PortMaster ports directory
if [ -d "$ROMS_ROOT/Roms/PORTS" ]; then
  PORTS="$ROMS_ROOT/Roms/PORTS"
elif [ -d "$ROMS_ROOT/roms/PORTS" ]; then
  PORTS="$ROMS_ROOT/roms/PORTS"
elif [ -d "$ROMS_ROOT/Roms/ports" ]; then
  PORTS="$ROMS_ROOT/Roms/ports"
elif [ -d "$ROMS_ROOT/PORTS" ]; then
  PORTS="$ROMS_ROOT/PORTS"
else
  mkdir -p "$ROMS_ROOT/Roms/PORTS"
  PORTS="$ROMS_ROOT/Roms/PORTS"
fi
say "PORTS: $PORTS"

# Refresh staged payload
mkdir -p "$STAGE/PORTS"
if [ -f "$ZIP" ]; then
  rm -rf "$STAGE/PORTS/gen1recomp-sbc.sh" "$STAGE/PORTS/gen1recomp-sbc" "$STAGE/PORTS/port.json" \
    "$STAGE/PORTS/gameinfo.xml" "$STAGE/PORTS/README.md"
  unzip -q -o "$ZIP" -d "$STAGE/PORTS"
else
  fail "missing $ZIP — run ./build-linux-arm-sbc.sh first"
fi

# Ensure ROMs are in lovegame (Choose ROM scans this folder on minimal images)
[ -f "$DECPREP/Pokemon - Red Version.gb" ] || fail "missing Red ROM in $DECPREP"
[ -f "$DECPREP/Pokemon - Blue Version.gb" ] || fail "missing Blue ROM in $DECPREP"
cp -f "$DECPREP/Pokemon - Red Version.gb" "$STAGE/PORTS/gen1recomp-sbc/lovegame/"
cp -f "$DECPREP/Pokemon - Blue Version.gb" "$STAGE/PORTS/gen1recomp-sbc/lovegame/"

say "copying gen1recomp port"
rm -rf "$PORTS/gen1recomp-sbc" "$PORTS/gen1recomp-sbc.sh"
cp -R "$STAGE/PORTS/gen1recomp-sbc" "$PORTS/"
cp -f "$STAGE/PORTS/gen1recomp-sbc.sh" "$PORTS/"
cp -f "$STAGE/PORTS/port.json" "$PORTS/"
cp -f "$STAGE/PORTS/README.md" "$PORTS/"
chmod +x "$PORTS/gen1recomp-sbc.sh" "$PORTS/gen1recomp-sbc/bin/love.aarch64"

# Also drop carts in the stock GB folder for the emulator library
GB_DIR=""
for candidate in "$ROMS_ROOT/Roms/GB" "$ROMS_ROOT/roms/GB" "$ROMS_ROOT/Roms/gb"; do
  if [ -d "$candidate" ]; then GB_DIR="$candidate"; break; fi
done
if [ -n "$GB_DIR" ]; then
  say "copying .gb into $GB_DIR"
  cp -f "$DECPREP/Pokemon - Red Version.gb" "$GB_DIR/"
  cp -f "$DECPREP/Pokemon - Blue Version.gb" "$GB_DIR/"
fi

sync
say "installed:"
ls -lh "$PORTS/gen1recomp-sbc.sh"
ls -lh "$PORTS/gen1recomp-sbc/lovegame/"*.gb
say "eject the SD, insert it in the handheld, open Ports → gen1recomp-sbc, Choose ROM."
