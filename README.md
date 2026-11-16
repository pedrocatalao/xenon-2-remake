# Xenon 2 Megablast remake

An exact reimplementation of **Xenon 2 Megablast** (The Bitmap Brothers, 1989) in **Godot 4.7.2**, rebuilt from the disassembly of the DOS executable, with the Amiga graphics and sound as options and an ENHANCED version with high resolution graphics.

> This repository holds **code only**. No graphics, sound, maps or other data of the original game are included: they are extracted from your own copy of the game by the tools in `tools/` (see [Building the game data](#building-the-game-data)).

## Contents

- [Overview](#overview)
- [Status](#status)
- [ORIGINAL and ENHANCED](#original-and-enhanced)
- [Requirements](#requirements)
- [Building the game data](#building-the-game-data)
- [Running](#running)
- [Controls](#controls)
- [Command line options](#command-line-options)
- [Project layout](#project-layout)
- [How it works](#how-it-works)
- [Tools](#tools)
- [Notes](#notes)

## Overview

- **Behaviour** comes only from the disassembled code of `XENON2.EXE` (DOS, VGA, 16 bit real mode). Each routine is read first and then written out as it is, with its code offset in a comment (`code 0x3f1e`, `ds:0x918a`). Nothing is guessed from recordings. What has not been read yet is marked `placeholder` in the scripts, and what was read with a detail still open is marked `unconfirmed`.
- **Data** (sprites, tiles, maps, waves, enemy paths, the shop, the PC speaker driver) comes from the files of the DOS version.
- **Amiga** (two ADF disks): the graphics, the title screen, the level backgrounds and tile masks, and the sound. The Amiga sound player (David Whittaker, Paula) runs on its own memory image, with a Paula emulation, so the music and effects are those of the Amiga game.
- The game logic runs at the DOS game frame (3 × 0x5555 / 1193182 s, about 0.055 s) at 320 × 200, exactly as the original.

## Status

- All five levels with their guardians, the shops, the end of the game and the loop back to level 1.
- Weapons, pod items, dive, protection, bitmap shades, continues, high scores, two players in turn.
- PC or Amiga graphics, PC speaker or Amiga sound, chosen from the title menu (Amiga by default).
- ENHANCED: xBRZ ×4 graphics everywhere, selected pictures redrawn (title logos, the ship and its weapons, the pod capsule and digits), the full Amiga arrangement of the music, and a few comfort changes (see below).

## ORIGINAL and ENHANCED

The opening screen (the title logo, *REMAKE BY VPAPANIK*, and the two versions) chooses between them with up and down; fire or Enter starts. **F12** switches at any moment, in the menus or in play. ENHANCED is the default when the game starts.

| | ORIGINAL 1989 | ENHANCED 2026 |
|---|---|---|
| Picture | 320 × 200, scaled up as one image | every picture drawn at the window's resolution from ×4 graphics |
| Graphics | the original pixels | xBRZ ×4, and selected pictures redrawn by hand |
| Amiga music | the game's arrangement (20 instruments) | the full arrangement of the original release's loading screen (39 instruments, scratches and voices), starting on the beat like the game's |
| Music after losing a life | stops, then starts again from the beginning | goes on where it was |
| Texts of the title screens | at the original's 16 pixel positions | centred to the pixel |
| Continue count | 9 to 0 in about 4.3 s | 9 to 0 in seconds |

The logic is the same in both: the same frames, collisions, boxes and positions, taken from the original pixels. Only the picture, the music and the comfort changes above differ.

## Requirements

- **Godot 4.7.2** (standard build, Compatibility renderer).
- **Python 3.14** with **Pillow** for the tools, and **numpy** for the ENHANCED tools.
- For ENHANCED graphics: the **xBRZ** extension in `tools/xbrz/`, built from `tools/xbrz/src` (GPL 3, xBRZ by Zenju, with the `xbrz_scale_cfg` addition for the scaler settings). On Windows: Visual Studio 2022 build tools, then build the extension next to `tools/xbrz/xbrz.py` (`_xbrz.cp314-win_amd64.pyd`).
- Your own copy of the game:
  - the **DOS version**: `XENON2.EXE`, `GR.DAT`, `SHOP.DAT`, `X2SPR.DAT`, `X2WEAPS.DAT` and the folders `S1` to `S5` (`MAP.CMP`, `MODS.VGA`, `SPRITES.VGA`, `EVENTS.PC`, `EVENTSBG.PC`, `PATHS.BIN`);
  - the **Amiga version**, two ADF disks. Disk 1 must be the TOSEC dump `Xenon II - Megablast (1989)(ImageWorks)(Disk 1 of 2)[cr QTX]`: its game program is stored unpacked and it also carries the loading screen music. Disk 2 is the same in all dumps.

## Building the game data

From the `tools` folder, with `<original PC>` the DOS game folder, `<disk 1>` and `<disk 2>` the ADF files and `<remake>` this folder:

```bash
python x2bitmaps.py "<original PC>" "<remake>/assets"
python x2levels.py "<original PC>" "<remake>/data"
python x2enemies.py "<original PC>" "<remake>/data"
python x2sound.py "<original PC>" "<remake>/data"
python x2shop.py "<original PC>" "<remake>/data"
python x2amiga.py "<disk 1>" "<disk 2>" "<original PC>" "<remake>"
```

For ENHANCED, then:

```bash
python x2xbrz.py "<remake>" "<remake>/assets_hd" 4
python x2enhanced.py "<remake>" "<enhanced>"
python x2nb2.py "<remake>" "<enhanced>"
```

`<enhanced>` is a folder outside the project (for example `../enhanced`) with one picture per object, by category, for viewing and redrawing (see [ENHANCED graphics](#enhanced-graphics)). `x2xbrz.py` rewrites `assets_hd` from the originals, so `x2nb2.py` always runs after it.

Finally import the project once, so that Godot registers the pictures and the script classes:

```bash
godot --headless --path "<remake>" --import
```

## Running

```bash
godot --path "<remake>"
```

On Windows, `start.bat` does the same with the Godot path of the development machine. The `Level N A start.bat`, `Level N B middle.bat` and `Level N C end.bat` files (N 1 to 5) start a level at its beginning, at a checkpoint in the middle, or at the last checkpoint before its guardian, with all weapons, the cheat and 99 lives, for testing. Edit the Godot path in them for your machine.

The window opens at 4 × 320 × 200 as seen on screen (times the Windows display scale), at most what fits, centred.

## Controls

| Key | Action |
|---|---|
| Arrows, keypad 8 2 4 6 (5 is down too) | move |
| Space, joystick buttons | fire |
| Enter, keypad Enter | dive |
| P | pause |
| Esc | back to the title, no high score and no continue |
| F12 | ORIGINAL or ENHANCED |
| F10 | quit |
| K (title menu) | customise keys |
| I | invulnerability, when the cheat is enabled |

## Command line options

Options go after `--`, for example `godot --path . -- --level=3 --enhanced`.

| Option | Effect |
|---|---|
| `--enhanced`, `--original` | start in that version |
| `--title` | show the title sequence also with `--shot` |
| `--level=N` | start at level N |
| `--scroll=N` | start the level at that scroll position, as a restart at a checkpoint |
| `--players=1\|2` | skip the title, 1 or 2 players |
| `--lives=N`, `--credits=N` | lives and credits at the start |
| `--cheat` | the cheat enabled and switched on |
| `--full` | the weapons of Super Nashwan Power kept for good |
| `--nashwan` | Super Nashwan Power from the start |
| `--weapons=0xNN,...` | weapons at the start, by slot type |
| `--item=N` | pod items collected at the start |
| `--dives=N`, `--protection`, `--shades` | dives, protection or bitmap shades at the start |
| `--shop` | a shop at once |
| `--pc-graphics`, `--pc-sound` | PC graphics or the PC speaker from the start |
| `--music` | music on in test runs |
| `--shot=<file> --ticks=N` | run N game frames, save the picture and quit (tests run in ORIGINAL unless `--enhanced`) |
| `--wav=<file>` | with `--shot`, write the sound to a WAV file |
| `--fire`, `--fire-until=N`, `--press=tick:key,...` | scripted input for tests (`up`, `down`, `left`, `right`, `fire`, `enter`) |
| `--z-flash=N`, `--dives=N` | test helpers for single effects |

## Project layout

```
project.godot
scenes/main.tscn
scripts/
  main.gd          the game : main loop, scrolling, ship, weapons, enemies, collisions, HUD, levels
  path_builder.gd  the path interpreter of the enemies
  level2.gd ... level5.gd  the code of each level's guardian and its own objects
  title.gd         title sequence, menus, high scores, continue, the Amiga title, the opening screen
  shop.gd          the shop
  sound.gd         the PC speaker driver, run on its own copy of the driver's memory
  amiga_sound.gd   the Amiga sound player and a Paula emulation
  hd_texture.gd    ENHANCED : a texture with the original size drawing either picture
  hd_mirror.gd     ENHANCED : a ×4 twin for the screens composed in software
tools/             Python tools that read the original game (ignored by Godot through .gdignore)
start.bat, Level N *.bat   launchers for Windows
```

`assets/`, `assets_hd/` and `data/` are produced by the tools and are not in the repository.

## How it works

### Game logic

`main.gd` follows the main loop of `XENON2.EXE` in its order, one game frame at a time. Positions, boxes and timers are integers as in the original, and the random generator is the game's own. Every routine carries the offset of the code it comes from, so it can be checked against the disassembly.

### PC speaker

`sound.gd` runs the original sound driver (extracted by `x2sound.py`) on its own memory, three timer interrupts per game frame, and plays the resulting speaker frequencies.

### Amiga sound

`amiga_sound.gd` ports the 68000 player of the Amiga game routine by routine, on a copy of its memory (`data/amiga_sound.bin`, the player with its tables, tunes and two sample banks). Each vertical blank runs the player and mixes four Paula channels (PAL clock 3546895 Hz, channels 0 and 3 left, 1 and 2 right). The shop has its own effects player (`data/amiga_shop_sound.bin`).

In ENHANCED a second instance plays the full arrangement of the tune (`data/amiga_intro_music.bin`, the loading screen player of the original release, 39 instruments). It skips that tune's first order list entry, the loading screen introduction, so it starts and loops on the beat like the game's. The effects stay with the game's player.

### ENHANCED graphics

`hd_texture.gd` is a texture with the size of the original picture that draws either the original or its ×4 version, so positions, sheet regions, collisions and masks stay in original pixels and no drawing code changes. In ENHANCED the window draws every picture at its own resolution (canvas items stretch mode), in ORIGINAL the 320 × 200 viewport is scaled as one image.

- `x2xbrz.py` turns every picture into xBRZ ×4 (smooth settings: luminance 0.5, tolerance 50, centre 4, dominant 2.5, steep 1.5), padding before scaling (tiles one by one with their edges repeated, Amiga backgrounds wrapped, sprites with a clear border), and writes the masked tile sheets of each level.
- In game, flashes are the xBRZ picture painted in colour 7, and the ship's bullets are scaled with Scale2x twice.
- `x2enhanced.py` writes the `<enhanced>` folder: per object `BMP_<name>.png` (the original frames in a grid) and `xBRZ_<name>.png`, plus `layout.json` with where each frame sits.
- A redrawn picture is saved there as `NB2_<name>.png` (any size, the same layout). `x2nb2.py` scales it to the xBRZ picture, cuts it into frames by `layout.json` and writes them into `assets_hd`, keeping the xBRZ transparency. `x2nb2prep.py` pads an object to a supported aspect ratio for an image model, and `x2nb2check.py` crops the result back and checks every frame against xBRZ (silhouette IoU), keeping the xBRZ frame where the redraw strays.

## Tools

| Script | Produces | Usage |
|---|---|---|
| `x2bitmaps.py` | every picture as PNG (sprites, tiles, maps, the contents of `GR.DAT`) | `python x2bitmaps.py <original PC> <assets>` |
| `x2levels.py` | `S1.json` to `S5.json` : map, waves, wall objects and paths | `python x2levels.py <original PC> <data>` |
| `x2enemies.py` | `enemies.json` : enemy definitions per level and the sine table | `python x2enemies.py <original PC> <data>` |
| `x2sound.py` | `sound.bin` : the PC sound driver as it is | `python x2sound.py <original PC> <data>` |
| `x2shop.py` | `shop.json` : boxes, prices, texts, animation, messages, palette | `python x2shop.py <original PC> <data>` |
| `x2amiga.py` | `amiga_sound.bin`, `amiga_intro_music.bin`, `amiga_shop_sound.bin`, `amiga_title.json`, `amiga_S1.json` to `amiga_S5.json` (tile kinds), and in `assets/amiga` the level backgrounds and the title pictures | `python x2amiga.py <disk 1> <disk 2> <original PC> <remake>` |
| `x2lh1.py` | lh1 decompression, used by `x2enemies.py` | library |
| `x2xbrz.py` | ENHANCED : `assets_hd` in xBRZ ×4 and the masked tile sheets | `python x2xbrz.py <remake> <assets_hd> [4]` |
| `x2enhanced.py` | ENHANCED : the `<enhanced>` folder and `layout.json` | `python x2enhanced.py <remake> <enhanced>` |
| `x2nb2.py` | ENHANCED : every `NB2_` picture into `assets_hd` | `python x2nb2.py <remake> <enhanced>` |
| `x2nb2prep.py`, `x2nb2check.py` | ENHANCED : prepare an object for redrawing and check the result frame by frame | `python x2nb2prep.py <enhanced> <folder/name> <tag> <dir>`, then `python x2nb2check.py <enhanced> <tag> <dir> [min IoU]` |
| `xbrz/` | the xBRZ library for Python (`xbrz.py` and the C++ source in `src`) | library |

## Notes

- Not affiliated with The Bitmap Brothers or Image Works. Xenon 2 Megablast and its graphics, music and data belong to their owners; this repository contains none of them.
- The xBRZ source in `tools/xbrz/src` is GPL 3 (see `tools/xbrz/src/License.txt`).
