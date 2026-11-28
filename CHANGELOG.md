# Changelog

## 0.48.1
- **The Auction House row in the luck window shows what you really sold for.** For a recipe ticked "sold at the AH", Gained is the money your AH sales brought in (after the 5% cut and the deposits), Spent is the materials of the units sold, and Profit and Per hr follow from those. A change in today's price no longer moves them. Crafts not sold through the AH are not counted, and a recipe with nothing recorded as sold shows "-". Before this the row valued every craft you had ever made at today's price.

## 0.48.0
- **Five more profession tabs: Leatherworking, Alchemy, Blacksmithing, First Aid and Mining.** Each lists the recipes you have learned with their cost, value and profit per hour, like Cooking, Engineering and Tailoring (`/dpp leatherworking`, `/dpp alchemy`, `/dpp blacksmithing`, `/dpp firstaid`, `/dpp mining`). Open each profession window once so its recipes are saved.
- **Tab order:** Cooking first, then your two main professions in the order the game lists them, then First Aid.
- **Known recipes for every profession.** Untick the box to see the recipes you have not learned: Leatherworking (473), Alchemy (163), Blacksmithing (401), First Aid (26) and Mining (14) now have it too. **Blueprints** (the crafting stations: Anvil, Master Forge, Tanning Rack, Fermenter, campfires and more) are listed for every profession.
- **Where a recipe comes from.** The tooltip of a recipe you have not learned reads: name, how it binds, skill, source, and a new **Zone** line. **Ctrl-click** pins it on the map:
  - a vendor or a quest giver (Cooking, Engineering and Tailoring quest recipes included);
  - for a recipe that drops from a creature, the middle of where that creature stands;
  - for a recipe a trainer teaches, the nearest trainer of that profession.
  A ring closes in on the pin when the map opens. A creature inside an instance has no spot on the map: the zone is shown and the click says so.
- **Golden "?" button beside the X.** Shows how to get your next profession rank for the tab you are on: your skill against what the rank needs (green once you have it), the player level it needs, the nearest trainer, the book's vendor and auction price, or the quest giver, and where. Click it to pin the place. It covers Cooking, Engineering, Tailoring, Leatherworking, Alchemy, Blacksmithing, First Aid, Mining and Enchanting.
- **Cooking Effect dropdown.** Pick a buff (Stamina, Strength, Agility, Intellect, Spirit, Spell damage, Healing, Mana regen, Health regen, Fishing, Other buff, No buff) to list only the foods that give it. A **Stat** column shows the number; Shift-click another heading to sort inside each stat value, so equal stats show the cheapest-to-make or best-earning one first.
- **The Rank button** moved to the tab row (Cooking tab only), and the search box is narrower and lines up with the rows below.
- **`[A]` price limits follow today's price.** After you search an item the limit is worked out again from the prices the auction house just showed, still inside your margin and odds. When nothing is cheap enough the message says which price it could not meet instead of "0c".
- **Fixed:** a saved Profit per hour sort was reset to Profit when you logged in.

## 0.47.0
- **Nearest vendor for a material.** Hover a material's icon or name in a recipe's details: for a material a vendor sells (spices, milk, thread, stout skin and more) the tooltip names the nearest vendor with the distance, plus how many more there are. **Ctrl-click** the icon or the name to pin that vendor on the map. Vendors are filtered to your faction. The data holds 150 vendors for 69 materials, with every capital city covered (Stormwind, Ironforge, Darnassus, Orgrimmar, Undercity, Thunder Bluff).
- **Shift-click a material** to search for it in Auctionator or TSM. Hovering a material's icon shows the item itself.
- **Vendor "+", hold Shift:** reads **Buy materials (AH)** and buys for the crafts that earn money at the auction house. It still buys for the meat in your bags, one recipe per shared meat (the one that earns most from it), as many as your bags and gold allow.
- **Create All "+" asks which recipe when recipes compete.**
  - When two or more recipes that earn money share a material you hold, the "+" opens a list instead of picking one for you. A recipe that shares nothing is crafted first.
  - One click on a row starts the craft. Hovering a row gives it a gold border and dims the others; the row that earns most has a green border.
  - The prices shown are vendor prices; hold **Shift** for auction house prices. The columns line up on every row.
  - If a craft does not start, click "+" again and it crafts your choice.
- **`[A]` and `[T]` start fresh every time.** What is already in your bags is no longer taken off: a list is sized by the margin, the confidence and the budget alone (holding 100 Murloc Eyes does not turn it into "buy X more"). What you buy after the click still counts, so the quantity box goes back to 0 once you have bought what the list asked for.
- **Smoother buying with `[A]`:** the quantity goes back to 0 as soon as you have bought your amount, and your budget now keeps gold back for the vendor materials, so you are not left unable to afford the spices.

## 0.46.0
- **TradeSkillMaster (TSM) support.** Prices come from TSM or Auctionator. With both loaded TSM is used first and Auctionator is the backup for an item TSM has no price for; a small **Prices: TSM / Auctionator** button in the footer (only shown with both) switches which is first. `/dpp prices auto|auctionator|tsm`, `/dpp tsmsource <TSM price source>` (default `DBMinBuyout`).
- **The row button reads `T` while TSM is first, `A` when Auctionator is first.**
  - `T` types one search into TSM's Browse box for every material of the recipe, with each price limit and quantity (`Clam Meat/exact/57c/x175;Murloc Fin/exact/5s/x350`); TSM then opens the buy dialog already set to that quantity.
  - It brings TSM's window up first if the game's auction window is showing, and `A` switches back to the game's window before making its list.
  - With TSM only it is greyed out until TSM's auction window is open.
- With TSM only: the disenchant value of gear results uses TSM's Destroy value, the Enchanting tab says it needs Auctionator and points to TSM's Disenchant search, and TSM prices show no age. `/dpp tsmfind` shows what `T` can see of TSM's windows.
- **`[A]` lists:**
  - The scarcest material decides how many of the others to buy (2 Murloc Eye + 1 Tender Crab Meat: 108 eyes means 54 crab meat, not hundreds); the quantity box is lowered again if Auctionator resets it. `/dpp depth` says what the last list read.
  - Chat lines are shorter and name items as links; "cut from 100000 crafts" is now "(budget)".
- Prices and hovers say "AH price" instead of "Auctionator price".

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
