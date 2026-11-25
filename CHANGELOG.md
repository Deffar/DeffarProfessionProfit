# Changelog

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
