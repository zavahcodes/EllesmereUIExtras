# ZavahTweaks

A small standalone addon with UI tweaks that Blizzard's UI doesn't offer on its own.

## Features

- **Tooltip health bar**: health bar and percentage on unit tooltips, with adjustable bar height and text size.
- **Target of target**: shows who the hovered unit is targeting, right in the tooltip.
- **Chat bubbles**: custom font size and outline for chat bubbles.
- **World map zoomed on player**: the world map always opens on your zone, fully zoomed in and centered on your character, and follows you while it's open (drag the map to stop, double-click it to follow again). Entering a new zone with the map open switches to its map. Based on [Persistent World Map](https://www.curseforge.com/wow/addons/persistent-world-map) by LudiusMaximus (MIT License).

- **Pawn tooltip cache**: fixes the FPS drop while an item tooltip is open with Pawn enabled. On Forever, Pawn re-reads the item's stats through a hidden tooltip on every tooltip refresh; its result is now reused for a few seconds (cleared when Pawn resets or your gear changes). Pawn's code is not modified.
- **EllesmereUI character sheet outline**: adds an outline (or thick outline) to the text EllesmereUI shows beside each item slot of the character sheet (item stats, weapon DPS, enchant).
- **Baganator combat guard**: stops the ADDON_ACTION_BLOCKED error when the bag key is pressed in combat with Baganator; optionally toggles the bags once combat ends.
- **Hide Zygor world map button**: hides the button (and its POI menu) that Zygor Guides adds to the world map border.

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
