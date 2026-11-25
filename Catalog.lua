-- Deffar Profession Profit: every Cooking recipe of WoW Forever that can be obtained, for the "Known recipes" box (unticked lists the
-- ones the character has not learned too). GENERATED from the Wowhead Forever database (wowhead.com/forever, read 2026-11-25): the
-- recipe spell, the item it makes, its materials and the skill it is learned at, and who gives the recipe. A recipe is only listed when
-- Wowhead names how to get it: a trainer, a recipe item with a source (vendor, quest, drop), or it is one every cook starts with (checked
-- against the characters' own learned recipes). Recipes with no source there (and the ones that make no item) are left out, not guessed at.
-- kind = Trainer, Vendor, Quest or Drop; by = the name of the vendor, quest or creature (the vendor first: a recipe that can be bought is
-- listed as bought), nil when Wowhead names none; skill = the skill it is learned at; item = the recipe item; vend = { A = , H = } the
-- vendor (an F.CATALOG_NPCS id) the Alliance and the Horde buy it from, when read.
local addonName, F = ...
F.CATALOG = F.CATALOG or {}
F.CATALOG.cooking = {
    [2538] = { name = "Charred Wolf Meat", out = 2679, qMin = 1, qMax = 1, skill = 45, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 2672 } } } },
    [2539] = { name = "Spiced Wolf Meat", out = 2680, qMin = 1, qMax = 1, skill = 10, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 2672 } }, { qty = 1, ids = { 2678 } } } },
    [2540] = { name = "Roasted Boar Meat", out = 2681, qMin = 1, qMax = 1, skill = 45, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 769 } } } },
    [2541] = { name = "Coyote Steak", out = 2684, qMin = 1, qMax = 1, skill = 50, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 2673 } } } },
    [2542] = { name = "Goretusk Liver Pie", out = 724, qMin = 1, qMax = 1, skill = 50, kind = "Vendor", by = "Kendor Kabonka", item = 2697, vend = { A = 340 }, r = { { qty = 1, ids = { 723 } }, { qty = 1, ids = { 2678 } } } },
    [2543] = { name = "Westfall Stew", out = 733, qMin = 1, qMax = 1, skill = 75, kind = "Vendor", by = "Kendor Kabonka", item = 728, vend = { A = 340 }, r = { { qty = 1, ids = { 729 } }, { qty = 1, ids = { 730 } }, { qty = 1, ids = { 731 } } } },
    [2544] = { name = "Crab Cake", out = 2683, qMin = 1, qMax = 1, skill = 75, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 2674 } }, { qty = 1, ids = { 2678 } } } },
    [2545] = { name = "Cooked Crab Claw", out = 2682, qMin = 1, qMax = 1, skill = 85, kind = "Vendor", by = "Kendor Kabonka", item = 2698, vend = { A = 340 }, r = { { qty = 1, ids = { 2675 } }, { qty = 1, ids = { 2678 } } } },
    [2546] = { name = "Dry Pork Ribs", out = 2687, qMin = 1, qMax = 1, skill = 80, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 2677 } }, { qty = 1, ids = { 2678 } } } },
    [2547] = { name = "Redridge Goulash", out = 1082, qMin = 1, qMax = 1, skill = 100, kind = "Vendor", by = "Kendor Kabonka", item = 2699, vend = { A = 340 }, r = { { qty = 1, ids = { 1081 } }, { qty = 1, ids = { 1080 } } } },
    [2548] = { name = "Succulent Pork Ribs", out = 2685, qMin = 1, qMax = 1, skill = 110, kind = "Vendor", by = "Kendor Kabonka", item = 2700, vend = { A = 340 }, r = { { qty = 2, ids = { 2677 } }, { qty = 1, ids = { 2692 } } } },
    [2549] = { name = "Seasoned Wolf Kabob", out = 1017, qMin = 3, qMax = 3, skill = 100, kind = "Vendor", by = "Kendor Kabonka", item = 2701, vend = { A = 340 }, r = { { qty = 2, ids = { 1015 } }, { qty = 1, ids = { 2678 } } } },
    [2795] = { name = "Beer Basted Boar Ribs", out = 2888, qMin = 1, qMax = 1, skill = 25, kind = "Vendor", by = "Kendor Kabonka", item = 2889, vend = { A = 340 }, r = { { qty = 1, ids = { 2886 } }, { qty = 1, ids = { 2894 } } } },
    [3370] = { name = "Crocolisk Steak", out = 3662, qMin = 1, qMax = 1, skill = 80, kind = "Vendor", by = "Kendor Kabonka", item = 3678, vend = { A = 340 }, r = { { qty = 1, ids = { 2924 } }, { qty = 1, ids = { 2678 } } } },
    [3371] = { name = "Blood Sausage", out = 3220, qMin = 2, qMax = 2, skill = 60, kind = "Vendor", by = "Kendor Kabonka", item = 3679, vend = { A = 340 }, r = { { qty = 1, ids = { 3173 } }, { qty = 1, ids = { 3172 } }, { qty = 1, ids = { 3174 } } } },
    [3372] = { name = "Murloc Fin Soup", out = 3663, qMin = 1, qMax = 1, skill = 90, kind = "Vendor", by = "Kendor Kabonka", item = 3680, vend = { A = 340 }, r = { { qty = 2, ids = { 1468 } }, { qty = 1, ids = { 2692 } } } },
    [3373] = { name = "Crocolisk Gumbo", out = 3664, qMin = 1, qMax = 1, skill = 120, kind = "Vendor", by = "Kendor Kabonka", item = 3681, vend = { A = 340 }, r = { { qty = 1, ids = { 3667 } }, { qty = 1, ids = { 2692 } } } },
    [3376] = { name = "Curiously Tasty Omelet", out = 3665, qMin = 1, qMax = 1, skill = 130, kind = "Vendor", by = "Kendor Kabonka", item = 3682, vend = { A = 340, H = 1148 }, r = { { qty = 1, ids = { 3685 } }, { qty = 1, ids = { 2692 } } } },
    [3377] = { name = "Gooey Spider Cake", out = 3666, qMin = 1, qMax = 1, skill = 110, kind = "Vendor", by = "Kendor Kabonka", item = 3683, vend = { A = 340 }, r = { { qty = 2, ids = { 2251 } }, { qty = 1, ids = { 2692 } } } },
    [3397] = { name = "Big Bear Steak", out = 3726, qMin = 1, qMax = 1, skill = 110, kind = "Vendor", by = "Ulthaan", item = 3734, vend = { A = 3960, H = 12246 }, r = { { qty = 1, ids = { 3730 } }, { qty = 1, ids = { 2692 } } } },
    [3398] = { name = "Hot Lion Chops", out = 3727, qMin = 1, qMax = 1, skill = 125, kind = "Vendor", by = "Zargh", item = 3735, vend = { A = 12245, H = 3489 }, r = { { qty = 1, ids = { 3731 } }, { qty = 1, ids = { 2692 } } } },
    [3399] = { name = "Tasty Lion Steak", out = 3728, qMin = 1, qMax = 1, skill = 150, kind = "Quest", by = "Costly Menace", item = 3736, r = { { qty = 2, ids = { 3731 } }, { qty = 1, ids = { 3713 } } } },
    [3400] = { name = "Soothing Turtle Bisque", out = 3729, qMin = 1, qMax = 1, skill = 175, kind = "Quest", by = "Soothing Turtle Bisque", item = 3737, r = { { qty = 1, ids = { 3712 } }, { qty = 1, ids = { 3713 } } } },
    [4094] = { name = "Barbecued Buzzard Wing", out = 4457, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Narj Deepslice", item = 4609, vend = { A = 2814, H = 12246 }, r = { { qty = 1, ids = { 3404 } }, { qty = 1, ids = { 2692 } } } },
    [6412] = { name = "Kaldorei Spider Kabob", out = 5472, qMin = 1, qMax = 1, skill = 10, kind = "Quest", by = "Recipe of the Kaldorei", item = 5482, r = { { qty = 1, ids = { 5465 } } } },
    [6413] = { name = "Scorpid Surprise", out = 5473, qMin = 1, qMax = 1, skill = 20, kind = "Vendor", by = "Grimtak", item = 5483, vend = { H = 3881 }, r = { { qty = 1, ids = { 5466 } } } },
    [6414] = { name = "Roasted Kodo Meat", out = 5474, qMin = 2, qMax = 2, skill = 35, kind = "Vendor", by = "Wunna Darkmane", item = 5484, vend = { H = 3081 }, r = { { qty = 1, ids = { 5467 } }, { qty = 1, ids = { 2678 } } } },
    [6415] = { name = "Fillet of Frenzy", out = 5476, qMin = 2, qMax = 2, skill = 50, kind = "Vendor", by = "Laird", item = 5485, vend = { A = 4200 }, r = { { qty = 1, ids = { 5468 } }, { qty = 1, ids = { 2678 } } } },
    [6416] = { name = "Strider Stew", out = 5477, qMin = 2, qMax = 2, skill = 50, kind = "Vendor", by = "Tari'qa", item = 5486, vend = { H = 3482 }, r = { { qty = 1, ids = { 5469 } }, { qty = 1, ids = { 4536 } } } },
    [6417] = { name = "Dig Rat Stew", out = 5478, qMin = 2, qMax = 2, skill = 90, kind = "Quest", by = "Dig Rat Stew", item = 5487, r = { { qty = 1, ids = { 5051 } } } },
    [6418] = { name = "Crispy Lizard Tail", out = 5479, qMin = 2, qMax = 2, skill = 100, kind = "Vendor", by = "Tari'qa", item = 5488, vend = { H = 3482 }, r = { { qty = 1, ids = { 5470 } }, { qty = 1, ids = { 2692 } } } },
    [6419] = { name = "Lean Venison", out = 5480, qMin = 2, qMax = 2, skill = 110, kind = "Vendor", by = "Ulthaan", item = 5489, vend = { A = 3960, H = 12245 }, r = { { qty = 1, ids = { 5471 } }, { qty = 4, ids = { 2678 } } } },
    [6499] = { name = "Boiled Clams", out = 5525, qMin = 1, qMax = 1, skill = 50, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 5503 } }, { qty = 1, ids = { 159 } } } },
    [6500] = { name = "Goblin Deviled Clams", out = 5527, qMin = 1, qMax = 1, skill = 125, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 5504 } }, { qty = 1, ids = { 2692 } } } },
    [6501] = { name = "Clam Chowder", out = 5526, qMin = 1, qMax = 1, skill = 90, kind = "Vendor", by = "Kriggon Talsone", item = 5528, vend = { A = 4305 }, r = { { qty = 1, ids = { 5503 } }, { qty = 1, ids = { 1179 } }, { qty = 1, ids = { 2678 } } } },
    [7213] = { name = "Giant Clam Scorcho", out = 6038, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Kelsey Yance", item = 6039, vend = { A = 2664, H = 2664 }, r = { { qty = 1, ids = { 4655 } }, { qty = 1, ids = { 2692 } } } },
    [7751] = { name = "Brilliant Smallfish", out = 6290, qMin = 1, qMax = 1, skill = 1, kind = "Vendor", by = "Tharynn Bouden", item = 6325, vend = { A = 66, H = 3029 }, r = { { qty = 1, ids = { 6291 } } } },
    [7752] = { name = "Slitherskin Mackerel", out = 787, qMin = 1, qMax = 1, skill = 1, kind = "Vendor", by = "Martine Tramblay", item = 6326, vend = { A = 4305, H = 3550 }, r = { { qty = 1, ids = { 6303 } } } },
    [7753] = { name = "Longjaw Mud Snapper", out = 4592, qMin = 1, qMax = 1, skill = 50, kind = "Vendor", by = "Tharynn Bouden", item = 6328, vend = { A = 66, H = 3027 }, r = { { qty = 1, ids = { 6289 } } } },
    [7754] = { name = "Loch Frenzy Delight", out = 6316, qMin = 1, qMax = 1, skill = 50, kind = "Vendor", by = "Khara Deepwater", item = 6329, vend = { A = 1684 }, r = { { qty = 1, ids = { 6317 } }, { qty = 1, ids = { 2678 } } } },
    [7755] = { name = "Bristle Whisker Catfish", out = 4593, qMin = 1, qMax = 1, skill = 100, kind = "Vendor", by = "Lindea Rabonne", item = 6330, vend = { A = 2383, H = 2397 }, r = { { qty = 1, ids = { 6308 } } } },
    [7827] = { name = "Rainbow Fin Albacore", out = 5095, qMin = 1, qMax = 1, skill = 50, kind = "Vendor", by = "Stuart Fleming", item = 6368, vend = { A = 3178, H = 3333 }, r = { { qty = 1, ids = { 6361 } } } },
    [7828] = { name = "Rockscale Cod", out = 4594, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Lindea Rabonne", item = 6369, vend = { A = 2383, H = 2664 }, r = { { qty = 1, ids = { 6362 } } } },
    [8238] = { name = "Savory Deviate Delight", out = 6657, qMin = 1, qMax = 1, skill = 85, kind = "Drop", by = "Lost Barrens Kodo", item = 6661, r = { { qty = 1, ids = { 6522 } }, { qty = 1, ids = { 2678 } } } },
    [8604] = { name = "Herb Baked Egg", out = 6888, qMin = 1, qMax = 1, skill = 1, kind = "Trainer", by = "Cooking trainer", r = { { qty = 1, ids = { 6889 } }, { qty = 1, ids = { 2678 } } } },
    [8607] = { name = "Smoked Bear Meat", out = 6890, qMin = 1, qMax = 1, skill = 40, kind = "Vendor", by = "Drac Roughcut", item = 6892, vend = { A = 1465, H = 3556 }, r = { { qty = 1, ids = { 3173 } } } },
    [9513] = { name = "Thistle Tea", out = 7676, qMin = 1, qMax = 1, skill = 60, kind = "Vendor", by = "Smudge Thunderwood", item = 18160, vend = { A = 6779, H = 6779 }, r = { { qty = 1, ids = { 2452 } }, { qty = 1, ids = { 159 } } } },
    [15853] = { name = "Lean Wolf Steak", out = 12209, qMin = 1, qMax = 1, skill = 125, kind = "Vendor", by = "Super-Seller 680", item = 12227, vend = { A = 12246, H = 12246 }, r = { { qty = 1, ids = { 1015 } }, { qty = 1, ids = { 2678 } } } },
    [15855] = { name = "Roast Raptor", out = 12210, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Corporal Bluth", item = 12228, vend = { A = 734, H = 1148 }, r = { { qty = 1, ids = { 12184 } }, { qty = 1, ids = { 2692 } } } },
    [15856] = { name = "Hot Wolf Ribs", out = 13851, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Vivianna", item = 12229, vend = { A = 7947, H = 8145 }, r = { { qty = 1, ids = { 12203 } }, { qty = 1, ids = { 2692 } } } },
    [15861] = { name = "Jungle Stew", out = 12212, qMin = 2, qMax = 2, skill = 175, kind = "Vendor", by = "Corporal Bluth", item = 12231, vend = { A = 734, H = 1148 }, r = { { qty = 1, ids = { 12202 } }, { qty = 1, ids = { 159 } }, { qty = 2, ids = { 4536 } } } },
    [15863] = { name = "Carrion Surprise", out = 12213, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Banalash", item = 12232, vend = { A = 12245, H = 989 }, r = { { qty = 1, ids = { 12037 } }, { qty = 1, ids = { 2692 } } } },
    [15865] = { name = "Mystery Stew", out = 12214, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Helenia Olden", item = 12233, vend = { A = 4897, H = 12246 }, r = { { qty = 1, ids = { 12037 } }, { qty = 1, ids = { 2596 } } } },
    [15906] = { name = "Dragonbreath Chili", out = 12217, qMin = 1, qMax = 1, skill = 200, kind = "Vendor", by = "Searing Hatchling", item = 12239, vend = { A = 4897, H = 4879 }, r = { { qty = 1, ids = { 12037 } }, { qty = 1, ids = { 4402 } }, { qty = 1, ids = { 2692 } } } },
    [15910] = { name = "Heavy Kodo Stew", out = 12215, qMin = 2, qMax = 2, skill = 200, kind = "Vendor", by = "Janet Hommers", item = 12240, vend = { A = 8150, H = 9636 }, r = { { qty = 2, ids = { 12204 } }, { qty = 1, ids = { 3713 } }, { qty = 1, ids = { 159 } } } },
    [15915] = { name = "Spiced Chili Crab", out = 12216, qMin = 1, qMax = 1, skill = 225, kind = "Vendor", by = "Banalash", item = 16111, vend = { A = 4305, H = 989 }, r = { { qty = 1, ids = { 12206 } }, { qty = 2, ids = { 2692 } } } },
    [15933] = { name = "Monster Omelet", out = 12218, qMin = 1, qMax = 1, skill = 225, kind = "Vendor", by = "Malygen", item = 16110, vend = { A = 2803, H = 2806 }, r = { { qty = 1, ids = { 12207 } }, { qty = 2, ids = { 3713 } } } },
    [15935] = { name = "Crispy Bat Wing", out = 12224, qMin = 1, qMax = 1, skill = 1, kind = "Vendor", by = "Abigail Shiel", item = 12226, vend = { H = 2118 }, r = { { qty = 1, ids = { 12223 } }, { qty = 1, ids = { 2678 } } } },
    [18238] = { name = "Spotted Yellowtail", out = 6887, qMin = 1, qMax = 1, skill = 225, kind = "Vendor", by = "Gikkix", item = 13939, vend = { A = 8137, H = 8137 }, r = { { qty = 1, ids = { 4603 } } } },
    [18239] = { name = "Cooked Glossy Mightfish", out = 13927, qMin = 1, qMax = 1, skill = 225, kind = "Vendor", by = "Kelsey Yance", item = 13940, vend = { A = 2664, H = 2664 }, r = { { qty = 1, ids = { 13754 } }, { qty = 1, ids = { 3713 } } } },
    [18240] = { name = "Grilled Squid", out = 13928, qMin = 1, qMax = 1, skill = 240, kind = "Vendor", by = "Gikkix", item = 13942, vend = { A = 8137, H = 8137 }, r = { { qty = 1, ids = { 13755 } }, { qty = 1, ids = { 3713 } } } },
    [18241] = { name = "Filet of Redgill", out = 13930, qMin = 1, qMax = 1, skill = 225, kind = "Vendor", by = "Kelsey Yance", item = 13941, vend = { A = 2664, H = 2664 }, r = { { qty = 1, ids = { 13758 } } } },
    [18242] = { name = "Hot Smoked Bass", out = 13929, qMin = 1, qMax = 1, skill = 240, kind = "Vendor", by = "Kelsey Yance", item = 13943, vend = { A = 2664, H = 2664 }, r = { { qty = 1, ids = { 13756 } }, { qty = 2, ids = { 2692 } } } },
    [18243] = { name = "Nightfin Soup", out = 13931, qMin = 1, qMax = 1, skill = 250, kind = "Vendor", by = "Gikkix", item = 13945, vend = { A = 8137, H = 8137 }, r = { { qty = 1, ids = { 13759 } }, { qty = 1, ids = { 159 } } } },
    [18244] = { name = "Poached Sunscale Salmon", out = 13932, qMin = 1, qMax = 1, skill = 250, kind = "Vendor", by = "Gikkix", item = 13946, vend = { A = 8137, H = 8137 }, r = { { qty = 1, ids = { 13760 } } } },
    [18245] = { name = "Lobster Stew", out = 13933, qMin = 1, qMax = 1, skill = 275, kind = "Vendor", by = "Vivianna", item = 13947, vend = { A = 7947, H = 8145 }, r = { { qty = 1, ids = { 13888 } }, { qty = 1, ids = { 159 } } } },
    [18246] = { name = "Mightfish Steak", out = 13934, qMin = 1, qMax = 1, skill = 275, kind = "Vendor", by = "Vivianna", item = 13948, vend = { A = 7947, H = 8145 }, r = { { qty = 1, ids = { 13893 } }, { qty = 1, ids = { 2692 } }, { qty = 1, ids = { 3713 } } } },
    [18247] = { name = "Baked Salmon", out = 13935, qMin = 1, qMax = 1, skill = 275, kind = "Vendor", by = "Vivianna", item = 13949, vend = { A = 7947, H = 8145 }, r = { { qty = 1, ids = { 13889 } }, { qty = 1, ids = { 3713 } } } },
    [20626] = { name = "Undermine Clam Chowder", out = 16766, qMin = 2, qMax = 2, skill = 225, kind = "Vendor", by = "Jabbey", item = 16767, vend = { A = 8139, H = 8139 }, r = { { qty = 2, ids = { 7974 } }, { qty = 1, ids = { 2692 } }, { qty = 1, ids = { 1179 } } } },
    [20916] = { name = "Mithril Headed Trout", out = 8364, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", by = "Lindea Rabonne", item = 17062, vend = { A = 2383, H = 2664 }, r = { { qty = 1, ids = { 8365 } } } },
    [21143] = { name = "Gingerbread Cookie", out = 17197, qMin = 1, qMax = 1, skill = 1, kind = "Vendor", by = "Penney Copperpinch", item = 17200, vend = { A = 13433, H = 13420 }, r = { { qty = 1, ids = { 6889 } }, { qty = 1, ids = { 17194 } } } },
    [21144] = { name = "Egg Nog", out = 17198, qMin = 1, qMax = 1, skill = 35, kind = "Vendor", by = "Penney Copperpinch", item = 17201, vend = { A = 13433, H = 13420 }, r = { { qty = 1, ids = { 6889 } }, { qty = 1, ids = { 1179 } }, { qty = 1, ids = { 17196 } }, { qty = 1, ids = { 17194 } } } },
    [21175] = { name = "Spider Sausage", out = 17222, qMin = 1, qMax = 1, skill = 200, kind = "Trainer", by = "Cooking trainer", r = { { qty = 2, ids = { 12205 } } } },
    [22480] = { name = "Tender Wolf Steak", out = 18045, qMin = 1, qMax = 1, skill = 225, kind = "Vendor", item = 18046, vend = { A = 4782, H = 7733 }, r = { { qty = 1, ids = { 12208 } }, { qty = 1, ids = { 3713 } } } },
    [22761] = { name = "Runn Tum Tuber Surprise", out = 18254, qMin = 1, qMax = 1, skill = 275, kind = "Drop", by = "Pusillin", item = 18267, r = { { qty = 1, ids = { 18255 } }, { qty = 1, ids = { 3713 } } } },
    [24418] = { name = "Heavy Crocolisk Stew", out = 20074, qMin = 1, qMax = 1, skill = 150, kind = "Vendor", by = "Ogg'marr", item = 20075, vend = { H = 4879 }, r = { { qty = 2, ids = { 3667 } }, { qty = 1, ids = { 3713 } } } },
    [25659] = { name = "Dirge's Kickin' Chimaerok Chops", out = 21023, qMin = 5, qMax = 5, skill = 300, kind = "Quest", by = "Dirge's Kickin' Chimaerok Chops", item = 21025, r = { { qty = 1, ids = { 2692 } }, { qty = 1, ids = { 9061 } }, { qty = 1, ids = { 8150 } }, { qty = 1, ids = { 21024 } } } },
    [25704] = { name = "Smoked Sagefish", out = 21072, qMin = 1, qMax = 1, skill = 80, kind = "Vendor", item = 21099, vend = { A = 2381, H = 2397 }, r = { { qty = 1, ids = { 21071 } }, { qty = 1, ids = { 2678 } } } },
    [25954] = { name = "Sagefish Delight", out = 21217, qMin = 1, qMax = 1, skill = 175, kind = "Vendor", item = 21219, vend = { A = 2381, H = 2397 }, r = { { qty = 1, ids = { 21153 } }, { qty = 1, ids = { 2692 } } } },
    [1249957] = { name = "Peace Tea", out = 249865, qMin = 1, qMax = 1, skill = 25, kind = "Drop", by = "Frostmane Seer", item = 249879, r = { { qty = 1, ids = { 159 } }, { qty = 2, ids = { 2447 } } } },
    [1249958] = { name = "Royal Tea", out = 249866, qMin = 1, qMax = 1, skill = 100, kind = "Drop", by = "Windshear Geomancer", item = 249880, r = { { qty = 1, ids = { 1179 } }, { qty = 2, ids = { 785 } } } },
    [1249959] = { name = "Root Tea", out = 249867, qMin = 1, qMax = 1, skill = 125, kind = "Drop", by = "Torn Fin Oracle", item = 249881, r = { { qty = 1, ids = { 1205 } }, { qty = 2, ids = { 3357 } } } },
    [1249960] = { name = "Triage Tea", out = 249868, qMin = 1, qMax = 1, skill = 180, kind = "Drop", by = "Woodpaw Mystic", item = 249882, r = { { qty = 1, ids = { 1708 } }, { qty = 2, ids = { 3818 } } } },
    [1249961] = { name = "Sunny Tea", out = 249869, qMin = 1, qMax = 1, skill = 200, kind = "Drop", by = "Marsh Oracle", item = 249883, r = { { qty = 1, ids = { 1645 } }, { qty = 2, ids = { 8838 } } } },
    [1249962] = { name = "Sage's Tea", out = 249870, qMin = 1, qMax = 1, skill = 250, kind = "Drop", by = "Deadwind Ogre Mage", item = 249884, r = { { qty = 1, ids = { 8766 } }, { qty = 2, ids = { 13465 } } } },
    [1249963] = { name = "Venomous Smoothie", out = 249871, qMin = 1, qMax = 1, skill = 25, kind = "Vendor", item = 249885, vend = { A = 256731, H = 248198 }, r = { { qty = 1, ids = { 159 } }, { qty = 1, ids = { 2678 } }, { qty = 1, ids = { 1475 } } } },
    [1249964] = { name = "Slimy Smoothie", out = 249872, qMin = 1, qMax = 1, skill = 100, kind = "Vendor", item = 249886, vend = { A = 256731, H = 248198 }, r = { { qty = 1, ids = { 1179 } }, { qty = 2, ids = { 2678 } }, { qty = 1, ids = { 3174 } } } },
    [1249965] = { name = "Mrrggl Smrrthle", out = 249873, qMin = 1, qMax = 1, skill = 125, kind = "Vendor", item = 249887, vend = { A = 256731, H = 248198 }, r = { { qty = 1, ids = { 1205 } }, { qty = 2, ids = { 2692 } }, { qty = 1, ids = { 1468 } } } },
    [1249966] = { name = "Calcified Smoothie", out = 249874, qMin = 1, qMax = 1, skill = 180, kind = "Vendor", item = 249888, vend = { A = 256731, H = 248198 }, r = { { qty = 1, ids = { 1708 } }, { qty = 3, ids = { 2692 } }, { qty = 1, ids = { 5637 } } } },
    [1249967] = { name = "Spicy Smoothie", out = 249875, qMin = 1, qMax = 1, skill = 200, kind = "Vendor", item = 249889, vend = { A = 256731, H = 248198 }, r = { { qty = 1, ids = { 1645 } }, { qty = 3, ids = { 3713 } }, { qty = 1, ids = { 4402 } } } },
    [1249968] = { name = "Wicked Smoothie", out = 249876, qMin = 1, qMax = 1, skill = 250, kind = "Vendor", item = 249890, vend = { A = 256731, H = 248198 }, r = { { qty = 1, ids = { 8766 } }, { qty = 4, ids = { 3713 } }, { qty = 1, ids = { 8146 } } } },
    [1250142] = { name = "Savory Stag Sliders", out = 250065, qMin = 1, qMax = 1, skill = 225, kind = "Vendor", by = "Qia", item = 250173, vend = { A = 11189, H = 11189 }, r = { { qty = 2, ids = { 5471 } }, { qty = 3, ids = { 2692 } } } },
    [1250144] = { name = "Bat Hachee", out = 250067, qMin = 1, qMax = 1, skill = 275, kind = "Drop", by = "Monstrous Plaguebat", item = 250175, r = { { qty = 3, ids = { 12223 } }, { qty = 2, ids = { 3713 } } } },
    [1250145] = { name = "Savory Turtle Stew", out = 250068, qMin = 1, qMax = 1, skill = 275, kind = "Drop", by = "Child of Tortolla", item = 250176, r = { { qty = 3, ids = { 3712 } }, { qty = 3, ids = { 3713 } } } },
    [1250146] = { name = "Flank au Poivre", out = 250069, qMin = 1, qMax = 1, skill = 275, kind = "Drop", by = "Ghostfang Alpha", item = 250177, r = { { qty = 3, ids = { 12203 } }, { qty = 3, ids = { 3713 } } } },
    [1250147] = { name = "Bear Bruscitti", out = 250070, qMin = 1, qMax = 1, skill = 275, kind = "Drop", by = "Rabid Shardtooth", item = 250178, r = { { qty = 3, ids = { 3730 } }, { qty = 3, ids = { 3713 } } } },
    [1250148] = { name = "Steaming Stag Steak", out = 250071, qMin = 1, qMax = 1, skill = 275, kind = "Quest", item = 250179, r = { { qty = 3, ids = { 5471 } }, { qty = 4, ids = { 3713 } } } },
    [1250149] = { name = "Swiftstrike Steak", out = 250072, qMin = 1, qMax = 1, skill = 275, kind = "Drop", by = "Frostsaber Pride Watcher", item = 250180, r = { { qty = 3, ids = { 12202 } }, { qty = 2, ids = { 3713 } } } },
    [1250150] = { name = "Raging Raptor Ribs", out = 250073, qMin = 1, qMax = 1, skill = 180, kind = "Drop", by = "Venomhide Ravasaur", item = 250181, r = { { qty = 2, ids = { 12184 } }, { qty = 3, ids = { 2692 } } } },
    [1250151] = { name = "Bear Brisket", out = 250074, qMin = 1, qMax = 1, skill = 175, kind = "Drop", by = "Ashenvale Bear", item = 250182, r = { { qty = 2, ids = { 3730 } }, { qty = 3, ids = { 2692 } } } },
    [1250152] = { name = "Prehistoric Pulled Raptor", out = 250075, qMin = 1, qMax = 1, skill = 275, kind = "Drop", item = 250183, r = { { qty = 3, ids = { 12184 } }, { qty = 4, ids = { 3713 } } } },
    [1250153] = { name = "Raptor Rouladen", out = 250076, qMin = 1, qMax = 1, skill = 225, kind = "Drop", by = "Bloodfen Lashtail", item = 250184, r = { { qty = 2, ids = { 12184 } }, { qty = 4, ids = { 2692 } } } },
    [1250154] = { name = "Twice-Spiced Raptor Slice", out = 250077, qMin = 1, qMax = 1, skill = 75, kind = "Quest", by = "Changing Tastes", item = 250185, r = { { qty = 1, ids = { 12184 } }, { qty = 2, ids = { 2678 } } } },
    [1250155] = { name = "Giant Scrambled Eggs", out = 250078, qMin = 1, qMax = 1, skill = 175, kind = "Drop", by = "Lost One Cook", item = 250186, r = { { qty = 2, ids = { 12207 } }, { qty = 4, ids = { 2692 } } } },
    [1250156] = { name = "Tasty Raptor Bites", out = 250079, qMin = 1, qMax = 1, skill = 25, kind = "Drop", item = 250187, r = { { qty = 1, ids = { 3685 } }, { qty = 4, ids = { 2678 } } } },
    [1250157] = { name = "Breakfast Omelette", out = 250080, qMin = 1, qMax = 1, skill = 75, kind = "Drop", by = "Dire Condor", item = 250188, r = { { qty = 1, ids = { 6889 } }, { qty = 4, ids = { 2678 } } } },
    [1250158] = { name = "Clam Linguine", out = 250081, qMin = 1, qMax = 1, skill = 275, kind = "Drop", by = "Spitelash Enchantress", item = 250189, r = { { qty = 3, ids = { 7974 } }, { qty = 4, ids = { 3713 } } } },
    [1252566] = { name = "Savory Whimsyfin Delight", out = 251525, qMin = 1, qMax = 1, skill = 85, kind = "Drop", item = 251526, r = { { qty = 1, ids = { 251524 } }, { qty = 1, ids = { 2678 } } } },
    [1262978] = { name = "Cookie's Feast", out = 279957, qMin = 1, qMax = 1, skill = 140, kind = "Drop", by = "Cookie", item = 273102, r = { { qty = 2, ids = { 12037 } }, { qty = 1, ids = { 12204 } }, { qty = 1, ids = { 3713 } } } },
    [1270633] = { name = "Skywall Souffle", out = 263509, qMin = 1, qMax = 1, skill = 25, kind = "Quest", by = "Restocking the Larders", item = 263511, r = { { qty = 2, ids = { 6889 } }, { qty = 1, ids = { 10284 } } } },
    [1270635] = { name = "Pincer Bites", out = 263512, qMin = 1, qMax = 1, skill = 35, kind = "Quest", by = "Crab Season", item = 263513, r = { { qty = 1, ids = { 2675 } }, { qty = 1, ids = { 10284 } } } },
    [1294014] = { name = "Sweetpaw Jam", out = 267341, qMin = 1, qMax = 1, skill = 275, kind = "Vendor", by = "Dala Fairmaw", item = 274415, vend = {  }, r = { { qty = 3, ids = { 249796 } }, { qty = 1, ids = { 3713 } } } },
    [1295805] = { name = "Briny Seafood Stew", out = 274971, qMin = 1, qMax = 1, skill = 200, kind = "Vendor", by = "Fimbo Greasemitz", item = 274972, vend = { A = 259962, H = 259962 }, r = { { qty = 2, ids = { 730 } }, { qty = 1, ids = { 12206 } }, { qty = 1, ids = { 2692 } } } },
    [1295834] = { name = "Plain Ol' Paletusk", out = 274976, qMin = 1, qMax = 1, skill = 185, kind = "Vendor", item = 274977, vend = { A = 259860, H = 256728 }, r = { { qty = 2, ids = { 769 } }, { qty = 1, ids = { 2678 } } } },
    [1319313] = { name = "Plated Armorfish", out = 286152, qMin = 1, qMax = 1, skill = 225, kind = "Drop", by = "Recipe: Raw Plated Armorfish", item = 286153, r = { { qty = 1, ids = { 13890 } }, { qty = 1, ids = { 3713 } } } },
}

-- The vendors the recipes name, with where they stand: the game's map ID (uiMapID) and the position on it, 0-100, from the Wowhead
-- Forever NPC pages (a vendor not read yet has only its name, and no pin).
F.CATALOG_NPCS = {
    [66] = { name = "Tharynn Bouden", map = 1429, x = 41.8, y = 67.0 },
    [340] = { name = "Kendor Kabonka", map = 1453, x = 77.2, y = 52.4 },
    [734] = { name = "Corporal Bluth", map = 1434, x = 38.0, y = 3.0 },
    [989] = { name = "Banalash", map = 1435, x = 44.4, y = 57.0 },
    [1148] = { name = "Nerrist", map = 1434, x = 32.6, y = 29.2 },
    [1465] = { name = "Drac Roughcut", map = 1432, x = 35.4, y = 48.8 },
    [1684] = { name = "Khara Deepwater", map = 1432, x = 39.4, y = 39.2 },
    [2118] = { name = "Abigail Shiel", map = 1420, x = 61.0, y = 52.4 },
    [2381] = { name = "Micha Yance", map = 1424, x = 49.0, y = 55.0 },
    [2383] = { name = "Lindea Rabonne", map = 1424, x = 50.0, y = 62.4 },
    [2397] = { name = "Derak Nightfall", map = 1424, x = 63.0, y = 19.4 },
    [2664] = { name = "Kelsey Yance", map = 1434, x = 28.2, y = 74.4 },
    [2803] = { name = "Malygen", map = 1448, x = 62.2, y = 25.4 },
    [2806] = { name = "Bale", map = 1448, x = 34.8, y = 53.2 },
    [2814] = { name = "Narj Deepslice", map = 1417, x = 45.4, y = 47.4 },
    [3027] = { name = "Naal Mistrunner", map = 1456, x = 50.2, y = 51.6 },
    [3029] = { name = "Sewa Mistrunner", map = 1456, x = 55.2, y = 48.0 },
    [3081] = { name = "Wunna Darkmane", map = 1412, x = 45.4, y = 61.8 },
    [3178] = { name = "Stuart Fleming", map = 1437, x = 8.0, y = 58.2 },
    [3333] = { name = "Shankys", map = 1454, x = 69.4, y = 29.0 },
    [3482] = { name = "Tari'qa", map = 1413, x = 51.6, y = 30.0 },
    [3489] = { name = "Zargh", map = 1413, x = 52.4, y = 29.8 },
    [3550] = { name = "Martine Tramblay", map = 1420, x = 65.8, y = 59.4 },
    [3556] = { name = "Andrew Hilbert", map = 1421, x = 43.0, y = 40.4 },
    [3881] = { name = "Grimtak", map = 1411, x = 51.2, y = 42.4 },
    [3960] = { name = "Ulthaan", map = 1440, x = 50.0, y = 66.4 },
    [4200] = { name = "Laird", map = 1439, x = 36.8, y = 44.2 },
    [4305] = { name = "Kriggon Talsone", map = 1436, x = 36.2, y = 90.0 },
    [4782] = { name = "Truk Wildbeard", map = 1425, x = 14.4, y = 42.4 },
    [4879] = { name = "Ogg'marr", map = 1445, x = 36.6, y = 31.0 },
    [4897] = { name = "Helenia Olden", map = 1445, x = 66.4, y = 51.4 },
    [6779] = { name = "Smudge Thunderwood", map = 1416, x = 86.0, y = 79.4 },
    [7733] = { name = "Innkeeper Fizzgrimble", map = 1446, x = 52.4, y = 27.8 },
    [7947] = { name = "Vivianna", map = 1444, x = 31.2, y = 43.4 },
    [8137] = { name = "Gikkix", map = 1446, x = 66.6, y = 22.0 },
    [8139] = { name = "Jabbey", map = 1446, x = 67.0, y = 22.0 },
    [8145] = { name = "Sheendra Tallgrass", map = 1444, x = 74.4, y = 42.8 },
    [8150] = { name = "Janet Hommers", map = 1443, x = 66.2, y = 6.6 },
    [9636] = { name = "Kireena", map = 1443, x = 51.0, y = 53.4 },
    [11189] = { name = "Qia", map = 1452, x = 61.2, y = 37.2 },
    [12245] = { name = "Vendor-Tron 1000", map = 1443, x = 60.2, y = 38.2 },
    [12246] = { name = "Super-Seller 680", map = 1443, x = 40.4, y = 79.2 },
    [13420] = { name = "Penney Copperpinch", map = 1454, x = 52.8, y = 66.6 },
    [13433] = { name = "Wulmort Jinglepocket", map = 1455, x = 33.4, y = 65.4 },
    [248198] = { name = "Aza'bek", map = 1413, x = 49.6, y = 29.4 },
    [256728] = { name = "Na'zok", map = 2548, x = 70.4, y = 28.0 },
    [256731] = { name = "Kalsey Sanden", map = 1433, x = 10.8, y = 72.4 },
    [259860] = { name = "Martha Wellsworth", map = 2548, x = 64.2, y = 84.0 },
    [259962] = { name = "Fimbo Greasemitz", map = 2548, x = 79.0, y = 54.2 },
}

F.Catalog = {}

-- Whether a profession has a catalog (the "Known recipes" box only shows for those).
function F.Catalog.Has(prof) return F.CATALOG ~= nil and F.CATALOG[prof] ~= nil end

-- The vendor of a recipe for this character's side: its id and its entry in F.CATALOG_NPCS ({ name, map, x, y }); nil when the recipe names
-- none for that side (the other side's vendor is not yours to go to). A character whose side cannot be read gets any of the two.
function F.Catalog.Vendor(recipe)
    local ids = type(recipe) == "table" and recipe.vend or nil
    if type(ids) ~= "table" then return nil end
    local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    local id
    if faction == "Horde" then id = ids.H
    elseif faction == "Alliance" then id = ids.A
    else id = ids.A or ids.H end
    if not id then return nil end
    return id, F.CATALOG_NPCS[id]
end

-- The vendor of a recipe for the OTHER side (an Alliance character looking at a Horde-only recipe), when this side has none: its entry and the
-- name of that side ("Horde").
function F.Catalog.OtherVendor(recipe)
    local ids = type(recipe) == "table" and recipe.vend or nil
    local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    if type(ids) ~= "table" or (faction ~= "Horde" and faction ~= "Alliance") then return nil end
    local id = faction == "Horde" and ids.A or ids.H
    local npc = id and F.CATALOG_NPCS[id]
    if not npc then return nil end
    return npc, faction == "Horde" and "Alliance" or "Horde"
end

-- Who gives a recipe: the name, the kind and, for a vendor only the OTHER side's sells, that side ("Horde"). A recipe nobody of this side can
-- buy must say so loudly wherever it is shown (the name tooltip, the list row).
function F.Catalog.Giver(recipe)
    local kind = type(recipe) == "table" and F.String(recipe.kind) and recipe.kind or nil
    if not kind then return nil, nil, nil end
    local name = recipe.by
    if kind == "Vendor" and type(recipe.vend) == "table" then
        local _, npc = F.Catalog.Vendor(recipe)
        if npc then
            name = npc.name
        else
            local other, side = F.Catalog.OtherVendor(recipe)
            if other then return other.name, kind, side end
            name = nil
        end
    end
    return F.String(name) and name or nil, kind, nil
end

-- The side ("Horde") when only that side's vendor sells the recipe and this character is on the other; nil otherwise.
function F.Catalog.OnlySide(recipe)
    local _, _, side = F.Catalog.Giver(recipe)
    return side
end

-- How the recipe item binds, as the words a tooltip uses: "Binds on Pickup" / "Binds on Equip" / "Binds on Use"; nil when it does not bind, the
-- recipe has no item (a trainer's) or the item data has not arrived yet (it is asked for, and the window redraws when it does).
function F.Catalog.Bind(recipe)
    if type(recipe) ~= "table" or not F.Integer(recipe.item, 1, 2147483647) then return nil end
    local bind = F.ItemMeta(recipe.item).bind
    if bind == 1 then return "Binds on Pickup" end
    if bind == 2 then return "Binds on Equip" end
    if bind == 3 then return "Binds on Use" end
    return nil
end

-- The colour code of the skill a recipe needs: green when the character's skill in that profession reaches it, red when it does not, sand
-- when the skill cannot be read.
function F.Catalog.SkillColor(recipe, prof)
    local S = F.Style
    local def = F.PROFESSIONS[prof or F.Tab()]
    local have = def and F.SkillRank(def.line) or nil
    if have == nil or not F.Integer(recipe.skill, 1, 9999) then return S.SAND end
    return have >= recipe.skill and S.GREEN or S.RED
end

-- The two coloured pieces of an unlearned recipe's name tooltip:
--   Status: "(175) not learned."  (the skill green when the character's reaches it, red when not; "not learned." in the earthy red)
--   Source: "Source: Kendor Kabonka (Vendor) HORDE ONLY"  (the name in sand, the kind in grey, the side in red when only the other side sells it)
function F.Catalog.Status(recipe, prof)
    local S = F.Style
    local skill = ""
    if F.Integer(recipe.skill, 1, 9999) then skill = S.Paint(F.Catalog.SkillColor(recipe, prof), "(" .. recipe.skill .. ")") .. " " end
    return skill .. S.Paint(S.RUSTCODE, "not learned.")
end

function F.Catalog.SourceLine(recipe)
    local S = F.Style
    local name, kind, only = F.Catalog.Giver(recipe)
    if not kind then return nil end
    local text = S.Paint(S.GREYTEXT, "Source:") .. " "
    if name then text = text .. S.Paint(S.SAND, name) .. " " .. S.Paint(S.GREYTEXT, "(" .. kind .. ")")
    else text = text .. S.Paint(S.SAND, kind) end
    if only then text = text .. " " .. S.Paint(S.RED, only:upper() .. " ONLY") end
    return text
end

-- A click on an unlearned recipe. A plain click says nothing (the tooltip has what the recipe is and where it comes from); with `pin`
-- (Ctrl-click) and a vendor for this side that has a position, the vendor is pinned on the map (Waypoint.lua) and the world map opened on its
-- zone, and a second Ctrl-click takes the pin away. Only the pin says anything in the chat.
function F.Catalog.Click(recipe, prof, pin)
    if not pin then return end
    local _, npc = F.Catalog.Vendor(recipe)
    if not (npc and npc.map and npc.x and npc.y) then
        local other, side = F.Catalog.OtherVendor(recipe)
        if other and not npc then
            F.Print("Only " .. (side == "Alliance" and "an " or "a ") .. side .. " vendor sells it (" .. other.name .. "): nothing to pin for you.")
        else
            F.Print("No vendor position to pin for " .. (F.String(recipe.name) and recipe.name or "this recipe") .. ".")
        end
        return
    end
    local S = F.Style
    local place = (F.Waypoint.MapName(npc.map) or "the map") .. string.format(" (%.1f, %.1f)", npc.x, npc.y)
    local result, why = F.Waypoint.Toggle(npc)
    if result == "set" then F.Print("Map pin: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ". Ctrl-click again to remove it.")
    elseif result == "cleared" then F.Print("Map pin removed.")
    elseif why == "map" then F.Print("This map takes no pin: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ".")
    else F.Print("This client has no map pin call: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ".") end
end
