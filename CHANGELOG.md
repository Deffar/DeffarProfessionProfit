# Changelog

## 0.45.0
- **Engineering and Tailoring catalogs.** Untick **Known recipes** to list the recipes you have not learned: 198 Engineering, 380 Tailoring. Each shows its source (trainer, vendor, quest, drop), bind type and materials. Vendors are named per side and can be pinned on the map with Ctrl-click (Mount Hyjal and the Skyborn zone included).
- Cooking recipes that cannot be had yet say so: Winter Veil (Egg Nog, Gingerbread Cookie), summer fish (Hot Smoked Bass), Ahn'Qiraj (Dirge's Kickin' Chimaerok Chops).
- **Hotfix alert.** A recipe whose materials or yield changed since the last time is said in chat: `DPP: Skywall Souffle changed: Small Egg 2 -> 1`.
- **Enchanting:**
  - Items with a random suffix are no longer listed twice, once without the suffix.
  - The Level dropdown lists every range in the scan, not only ranges with a paying item.
  - The list is built in the background, so opening the tab does not lag. It changes only when you press **Refresh**: browsing or searching the auction house does not rebuild it.
  - An item whose data was still loading is asked for again every 5 seconds, and the list fills in by itself.
  - Quality and Level are saved between sessions.
  - An item that loses money is never shown; one whose price turns it into a loss leaves at once.
  - An item the `[A]` search marked as gone comes back on its next price (the mark lasts a day).
  - New: `/dpp why <name or id>` says why an item is or is not in the list.
- **Hovers.** The recipe tooltip has no "Makes 1x [item]"; **Requires** lists the materials while **Shift** is held, with an empty line above the click hints. Create All's value line says `Sells:` (`AH:` with Shift). The Luck window's tooltips are shorter, with the materials used on Shift.
- **Vendor "+":** stays visible and greyed out while it buys.
- **`[A]` lists:** when no unit is at or under the limit, the quantity box is set to 0.
- **Boxes:** a click selects all the text; the search boxes have a small **x** to clear them; Min margin goes up to 999%.
- **Create All:** counts only what is in your bags, and no longer lists Blacksmithing recipes in the Engineering window. The 100-craft default is gone (as many as the budget allows).
- Removed: `/dpp crafts`, `/dpp crafttime`, the footer Luck button (the title-bar [L] stays).
- The GitHub release zip now includes the icon and this changelog.

## 0.44.0
- **A new toolbar.** The controls under the tabs are grouped in rows with a caption: **View**, **Value** and **Shopping** on recipe tabs, **View** and **Filters** on the Enchanting tab. They are laid out by their own width, so nothing overlaps. The shopping settings stay in view.
- Renamed: Odds is now **Confidence**, Margin is **Min margin**. The empty Budget box says "all gold".
- **Enchanting:** a **Level** column (the item's level) left of the AH price; the Quality and Level dropdowns are narrower.
- **Short hovers** on every toolbar control and every control of the luck window: a title, then short labelled lines, coloured by meaning. The unlearned recipe's `Binds on Equip` is an earthy green and `Binds on Pickup` an earthy red, and the bind type is remembered, so the line is there at once.
- **Vendor "+":**
  - It is at the bottom right of the merchant window.
  - It buys the materials of every recipe in step, so one material cannot take all the bag room.
  - The recipe you hold the least meat for is bought first, in full.
  - Its tooltip is grouped per dish: `Craft: [dish] xN`, `Buy: [supply] xY` for each supply, `Cost:`, a rule between dishes, then the Total.
  - The rules are as wide as the tooltip. The tooltip says when a stack size or the bag space cannot be read.
- **Create All "+"** (Cooking window): the same layout as the vendor tooltip. Below the crafts you can start it lists the dishes your meat could make, with a red `Missing:` line for each supply you lack.

## 0.43.12
- **Enchanting tab:**
  - The "Apply filters" box is gone: Min return, Min profit, Min odds and Max age always apply, and items that lose money are never listed.
  - New **Quality** and **Level** dropdowns. Level lists the item level ranges of the disenchant table; with a quality picked each range shows the icons of what it disenchants into (hover to name them).
  - A price last seen more than a day ago, or with no age on record, is never used. Items gone from the auction house no longer come back after a reload. Max age is now 0 or 1.
  - Random-suffix items show their suffix again ("... of the Bear") instead of a number.
  - The full scan time is kept for all characters and keeps counting down while you are logged out.
- **Cooking:** the Rank button is at the right end of the checkbox row, and the "Master Chef ..." line is gone: the button's tooltip says it. "Known recipes" moved to the Budget row.
- The Disenchant checkbox is only on tabs that make gear (Tailoring, Engineering), not Cooking.
- The empty space under the tabs is closed on every tab.
- Chat messages from the addon start with `DPP`.

## 0.43.11
- Hovering an unlearned recipe now shows everything in the tooltip: `(175) not learned.` (the skill green when yours reaches it, red when not), `Source: Kendor Kabonka (Vendor)` for your faction (or `HORDE ONLY` / `ALLIANCE ONLY` in red), and `Binds on Pickup` / `Binds on Equip`.
- A plain click on an unlearned recipe no longer prints in chat. Ctrl-click still pins the vendor on the map.
- Vendors are now known for every vendor-sold Cooking recipe, per faction.

## 0.43.9
- **Known recipes** box (Cooking): untick it to list every obtainable Cooking recipe, learned or not. Unlearned ones are in an earthy red.
- Click an unlearned recipe to see in chat where it comes from: `[Item] (175) not learned. Source: Kendor Kabonka (Vendor)`. The skill is green when yours reaches it and red when not. Vendors are named for your faction; a recipe only the other faction sells says `HORDE ONLY` / `ALLIANCE ONLY`.
- Ctrl-click a recipe sold by a vendor to pin the vendor on the map and open the map there. Ctrl-click again removes the pin.
- Luck window: an item ticked as sold at the auction house shows Spent, Gained, Profit and Per hr at auction prices, and an **Auction House** row under the totals adds those items together. The main row is now **Vendor** and leaves the ticked items out completely.
- Shorter hover tooltips on recipes (name, Profit cell, [A] button), with the click functions as one short line each.
- The Whole craft tooltip says `Avg return per craft (+40% extra)`, and the Green/Orange/Red lines show their percentages.
- Create All "+" tooltip: vendor price per craft, hold Shift for the auction house price after the cut; lists what your materials allow when a requirement is missing.

## 0.41.4
- With the materials but a missing requirement (a campfire, an Iron Oven), the "+" tooltip lists the items and counts you could make, then what is missing.

## 0.41.3
- The Create All "+" button is no longer greyed out when the best craft you can make loses money.
- Its tooltip shows what a vendor pays for a craft; hold Shift for the auction house price after the cut. Both ignore the panel's sell mode.

## 0.41.0
- Enchanting tab: tooltips in the shared look, a Profit tooltip with the disenchant sums, and Shift-click detail with the highest price to pay.

## 0.40.1
- Leaving the auction house page while a search is loading no longer removes the item from the Enchanting list.

## 0.40.0
- Added a minimap button: left-click opens the window, right-click the luck window, drag to move it. `/dpp minimap on|off` shows or hides it.

## 0.39.1
- Listed under the Professions category in the in-game addon list.
- Added the addon icon.

## 0.39.0
- First release of Deffar Profession Profit (`/dpp`).
- Gold per hour for every learned recipe (Cooking, Engineering, Tailoring) from Auctionator and vendor prices.
- Enchanting disenchant ranking, luck tracker, and AH sales tab.
- Vendor + button to buy materials and Create All + button on the profession window.
- Auctionator shopping lists with price limits.
