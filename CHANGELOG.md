# Changelog

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
