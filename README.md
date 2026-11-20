# Hailstone Stow

Stow adds compact bag and bank views to Hailstone. Category cards wrap and resize to fit their contents, with coin and icon controls in a single dock. It uses the Modern interface and works with interfaces that inherit Modern’s window layout.

## Install

In Hailstone’s login screen, open **Add-ons** and paste this repository’s URL. Approve the add-on and enter the world. Use **Open All Bags** (default **Shift+B**) for Stow Bags and **I** for the regular Inventory window. Visit a banker to open Stow Bank. Type `/stow` or choose **Stow Settings** from the plugin menu to change settings even when the replacement windows are disabled.

Stow needs the server to allow its Lua add-on and grant UI, read, actions, and commands. You can disable Stow in **My add-ons** to return to the selected interface’s windows.

## Bags and bank

- Choose **Category cards**, **Combined**, or **By physical bag** independently for Open All Bags and bank from the dock’s options menu. Click a card heading to collapse it. Drag the dock’s title to move Stow. Cards expand away from the dock and scroll when they reach the screen edge.
- Hover a dock icon to see what it does. Use the bag icon to show physical bags, and the magnifier to open search. Click coins to use the game’s coin controls.
- **Shift+B** opens carried bags together, including tradeskill containers. Open a tradeskill container directly to use its Combine window.
- Use the regular Inventory window for equipment, stats, Bandolier, and alternate currency. Trade, quantity, and item confirmation dialogs use Hailstone’s native interaction.
- Use the normal item controls to pick up, place, split, inspect, use, and link items through item inspection. Click a free-slot counter while holding an item to place it in an eligible slot. Stow Bank gives **Personal** and **Shared** their own counters and drop targets. Right-click a counter to show or hide the individual empty slots for that area.
- Find items by name or group. Combine terms such as `type:tradeskill -is:kept`, `bag:"Large Sack"`, `id:1002`, or `is:new`. Other flags include `is:junk`, `is:quest`, `is:lore`, `is:notrade`, and `is:usable`.
- Middle-click or Ctrl+Alt+right-click an item to assign every copy to a group, mark it **Keep**, mark it for sale, or lock its current slot for item jobs. Custom groups can represent outfits, collections, or items you want to keep handy. A display group change leaves the item in its current slot.
- The **Restack** icon fills matching stacks. **Sort items** physically orders items through Hailstone’s native item job. Assign a filter to a physical bag and use **Tidy into filtered bags** to move matching items into its compatible free slots. These jobs support carried bags and personal bank bags. Shared bank supports manual moves.
- Portable tradeskill containers retain their **Combine** actions. Tradeskill storage bags use the game’s tradeskill-item restriction when items are moved or sorted.

## Settings

Choose **Everyday**, **Adventurer**, **Tradeskiller**, **Compact**, or **Per Bag** as a starting point. Adjust item size, columns, sorting, bank color, free-space compression, window locking, and visible categories. Save your display settings as a named preset. You can create, rename, reorder, disable, and delete custom groups per character.

Under **Appearance**, choose **Auto**, **Up**, or **Down** for **Cards grow**. Auto chooses the side with more space based on where you place the dock. With **Combine empty slots** enabled, turn on **Show Empty Slots cards** to add a single counted drop tile before each area’s item groups.

**New Items** compares item quantities against the last **Reset New Items**. On first use, existing carried items are included until you reset. New Items survives reloads and includes quantities added through bank withdrawals. You can give category assignments priority over New Items.

Use **Sort inventory and clear New Items** on the Stow Bags dock to run the native inventory sort and refresh the New Items baseline in one click.

Auto-sell and Tidy after loot are opt-in. Auto-sell uses items you explicitly marked for sale and honors Hailstone’s Keep protection. The vendor must be open. The add-on uses EverQuest’s stock bank capacity and item properties.

## Client compatibility

Stow’s core views and item actions require Hailstone 0.7.1-beta or later. Automatic Quest Items grouping, special bag labels, and pre-drop compatibility checks require a client exposing `questItem`, `bagType`, `bagSize`, and `inventory.CanPlace`. With older clients, you can still assign quest items manually and select real empty slots. The native game rules apply to every placement.

## Build and test

With a Hailstone client checkout beside this repository, run `python tools/package.py` to regenerate the manifest and platform-independent ZIP. To stage elsewhere, pass `--out dist`. With Lua 5.4, run `lua tests/test_model.lua`, `lua tests/test_cards.lua`, and `lua tests/test_dock.lua` from the repository root.

The ImGui host smoke test in `tests/host_smoke.inc` can be included at the end of Hailstone’s `tests/inventory_manager_ui_test.cpp` when building the client’s test suite. It uses a mock server and the real Hailstone UI host.

Stow is an original EverQuest add-on. The published cargBags Nivaya feature set informed its design. [cargBags Nivaya](https://www.curseforge.com/wow/addons/cargbags-nivaya-mop-update)
