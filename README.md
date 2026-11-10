# ZavahTweaks

A small standalone addon with UI tweaks that Blizzard's UI doesn't offer on its own.

## Features

- **Tooltip health bar**: health bar and percentage on unit tooltips, with adjustable bar height and text size.
- **Target of target**: shows who the hovered unit is targeting, right in the tooltip.
- **Chat bubbles**: custom font size and outline for chat bubbles.
- **World map zoomed on player**: the world map always opens on your zone, fully zoomed in and centered on your character, and follows you while it's open (drag the map to stop, double-click it to follow again). Entering a new zone with the map open switches to its map. Based on [Persistent World Map](https://www.curseforge.com/wow/addons/persistent-world-map) by LudiusMaximus (MIT License).

Every feature can be toggled on or off on its own.

## Requirements

None. When **EllesmereUI** is installed, ZavahTweaks picks up its class colors and font, and skips its own target-of-target line if EllesmereUI's "Show Unit Target" is on.

## Installation

1. Download this repository (green **Code** button → **Download ZIP**) or clone it.
2. Put the folder in `World of Warcraft/<game version>/Interface/AddOns/` and make sure it's named exactly `ZavahTweaks`.
3. Restart the game or `/reload`.

## Settings

Open the settings with `/zt` (or `/zavahtweaks`), or go to **Options → AddOns → ZavahTweaks**.

Settings are saved in `ZavahTweaksDB`.

## Adding a module

1. Create a file in `Modules/` that calls `ns.RegisterModule{ key, name, defaults, options, OnLoad, Refresh }` (see the spec at the top of `Core.lua`).
2. Add it to `ZavahTweaks.toc` under `# Modules`.

The options panel builds itself from the registered modules.
