# Linux ARM SBC Handhelds (PortMaster)

Download `gen1recomp-*-sbc-portmaster.zip` from the [Gen1Recomp releases](https://github.com/bryanthaboi/gen1recomp/releases). This build targets 64-bit Linux ARM handhelds with PortMaster, including compatible H700 devices.

## Install

1. Unzip the release. It contains `gen1recomp-sbc.sh` and a `gen1recomp-sbc/` folder.
2. Copy both as siblings into your device's PortMaster ports directory, commonly `Roms/Ports (PORTS)/` or `Roms/PORTS/`.
3. Install PortMaster for your firmware and refresh the Ports list.
4. Copy your legally owned canonical US Red or Blue `.gb` file into `gen1recomp-sbc/lovegame/`.
5. Launch **gen1recomp-sbc** from Ports and choose the ROM.

The pack includes `portable.txt`, so saves and ROM-derived cache remain beside the game on the SD card. The build never ships ROM-derived bytes.

Canonical US cart SHA-1 values:

- Red: `ea9bcae617fdf159b045185467ae58b2e4a48b9a`
- Blue: `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2`

## Controls

| Input | Action |
| --- | --- |
| D-pad | Move cursor |
| A | Click / confirm |
| L1 / R1 | Switch tabs |
| Start / Select | Play or choose ROM |

In-game controls use the normal PortMaster/SDL mapping and can be rebound in **OPTIONS → CONTROLS**.

## Runtime and suspend

The package bundles PortMaster's LÖVE 11.5 aarch64 runtime. The launcher sources `control.txt`, calls `get_controls`, applies an optional CFW override, invokes `pm_platform_helper`, and calls `pm_finish` on exit. Paths are relative to the launcher, allowing different firmware mount points.

Suspend/resume uses the existing LÖVE focus/visibility lifecycle: input is reset on focus loss and the game resumes when the window becomes visible again. Exact power-button behavior remains firmware-dependent; hardware validation has been performed on the TrimUI Brick, not every SBC or H700 device.

## Building

Release workflows build this automatically. Standalone builds resolve the latest published Gen1Recomp release by default:

```sh
./build-linux-arm-sbc.sh --version 0.1.75
```

For development, package a local checkout explicitly:

```sh
GEN1RECOMP_SOURCE_DIR="$PWD" ./build-linux-arm-sbc.sh --version 0.1.0
# or: ./build-linux-arm-sbc.sh --source "$PWD" --version 0.1.0
```

The generated `port.json` records the source release tag. `install-linux-arm-sbc.sh` is a macOS helper for copying a built pack to a mounted SD card.

PortMaster device support and runtime integration are maintained in the [PortMaster](https://github.com/PortsMaster/PortMaster-New) ecosystem.
