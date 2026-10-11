class_name SimBuildings
extends RefCounted
## Cursing Gnomes — building logic (Milestone 3: jobs & buildings).
##
## The building TYPE registry (costs, build time, function) plus construction
## and service-building behaviors. Placement validity + ghost preview live in
## world/building_placement.gd; this file is pure sim.
##
## Design ported from the HTML build (not its code):
##   - Blueprints: placing deducts resources up front, builders raise
##     progress 0 -> 100, then the building goes live ("complete").
##   - Clinic: auto-spawns 1 doctor (10 s retry, essential-service bypass).
##   - Fire station: auto-spawns 2 firefighters (10 s retry, bypass).
##   - Guild hall: auto-spawns 1 guild master (10 s retry, town-capped).
##   - Guard house: auto-spawns 2 guards (10 s retry, town-capped).
##   - Guard tower / AA tower: budgeted auto-fire (Milestone 4 implements
##     firing; here we track the "armed" state only).
##
## Faction uniques (knights_castle=humans, mage_spire=gnomes, war_hut=ogres,
## flesh_farm=undead) are blocked for other factions ("wrong_faction").
## "hall" is an alias of "town_hall" (the HTML's name for the town center).
##
## BUILDING RECORD SCHEMA (extends GameState's base schema):
##   id, type, faction, town_id, position, alive,
##   complete: bool, progress: float (0..1), hp: float, max_hp: float
##
## Pure logic — no rendering, no input, no audio.


## type -> {name, costs {res: amt}, build_time (sec of 1-builder work),
##           hp, desc, size (footprint radius px for placement)}.

## Jeremy 2026-10-05: lumber-camp coverage radius (Rise of Nations style).
## Woodcutters work trees inside a completed camp's radius and haul wood
## back to it.
const LUMBER_CAMP_RADIUS := 450.0

const BUILDINGS := {
	"town_hall":   {"name": "Town Hall",    "costs": {"wood": 150, "oil": 100},
		"build_time": 60.0, "hp": 1200.0, "size": 46.0,
		"desc": "Town center. Founding building; drop-off for all hauling."},
	"house":       {"name": "House",        "costs": {"wood": 60, "oil": 20},
		"build_time": 25.0, "hp": 400.0, "size": 30.0,
		"desc": "Cottage. Houses workers; keeps morale up."},
	"farm":        {"name": "Farm",         "costs": {"wood": 40},
		"build_time": 20.0, "hp": 250.0, "size": 34.0,
		"desc": "Grows food. Farmers work here."},
	"sawmill":     {"name": "Sawmill",      "costs": {"wood": 80, "oil": 30},
		"build_time": 30.0, "hp": 500.0, "size": 32.0,
		"desc": "Processes timber. Boosts nearby woodcutters."},
	"quarry":      {"name": "Quarry",       "costs": {"wood": 50, "oil": 40},
		"build_time": 30.0, "hp": 500.0, "size": 32.0,
		"desc": "Stone pit. Miners work here."},
	"mine":        {"name": "Gold Mine",    "costs": {"wood": 100, "oil": 80},
		"build_time": 45.0, "hp": 600.0, "size": 32.0,
		"desc": "Digs gold. Miners work here."},
	"clinic":      {"name": "Clinic",       "costs": {"wood": 90, "oil": 60, "gold": 40},
		"build_time": 40.0, "hp": 550.0, "size": 32.0,
		"desc": "Heals the sick. Auto-staffs 1 doctor."},
	"fire_station": {"name": "Fire Station","costs": {"wood": 90, "oil": 60, "gold": 40},
		"build_time": 40.0, "hp": 550.0, "size": 34.0,
		"desc": "Fights fires. Auto-staffs 2 firefighters."},
	# Jeremy 2026-10-04: resource camps — gatherers haul here instead of
	# trekking to town hall (HTML parity).
	"resource_camp": {"name": "Resource Camp", "costs": {"wood": 60},
		"build_time": 25.0, "hp": 400.0, "size": 30.0,
		"desc": "Wilderness dropoff. Gatherers haul resources here."},
	# Jeremy 2026-10-05: oil pumps — oil comes from pumps placed in
	# industrial zones (no more oil piles). Passive generation, 4 per town.
	"oil_pump": {"name": "Oil Pump", "costs": {"wood": 100, "gold": 50},
		"build_time": 40.0, "hp": 500.0, "size": 30.0,
		"desc": "Pumpjack. Generates oil inside an industrial zone."},
	# Jeremy 2026-10-05: lumber camps (Rise of Nations style) — a camp
	# covers a radius of trees; woodcutters work trees inside the radius
	# and haul the wood back to the camp (faction inventory on dropoff).
	"lumber_camp": {"name": "Lumber Camp", "costs": {"wood": 80},
		"build_time": 30.0, "hp": 500.0, "size": 34.0,
		"desc": "Covers nearby trees. Woodcutters fell them and haul wood here."},
	"guard_tower": {"name": "Guard Tower",  "costs": {"wood": 70, "oil": 70},
		"build_time": 35.0, "hp": 650.0, "size": 26.0,
		"desc": "Armed watchtower. Fires on hostiles."},
	"shop":        {"name": "Shop",         "costs": {"wood": 70, "gold": 30},
		"build_time": 30.0, "hp": 400.0, "size": 30.0,
		"desc": "Trading post. Generates gold inside a commercial zone."},
	# Jeremy 2026-10-04: tool/shop petition chain — the general store and
	# blacksmith sell tools (pickaxe/axe/hammer/fishing rod/hoe) to workers.
	"general_store": {"name": "General Store", "costs": {"wood": 90, "gold": 40},
		"build_time": 35.0, "hp": 550.0, "size": 32.0,
		"desc": "Sells tools to workers: pickaxes, axes, hammers, fishing rods, hoes."},
	"blacksmith":  {"name": "Blacksmith",   "costs": {"wood": 100, "gold": 50},
		"build_time": 40.0, "hp": 600.0, "size": 32.0,
		"desc": "Forge and tool shop. Workers buy tools here."},
	# Jeremy 2026-10-10: vehicle dealership (P3 of the roads/vehicles order).
	# Citizens spend their OWN coins on fantasy-era personal vehicles
	# (wagon/cart/carriage — never modern cars). District-developed in
	# commercial zones like the other shops; parking lot out front.
	"wagon_dealership": {"name": "Wagon Dealership", "costs": {"wood": 110, "gold": 60},
		"build_time": 40.0, "hp": 550.0, "size": 36.0,
		"desc": "Sells wagons, carts and carriages to citizens. Parking lot out front."},
	"seedshop":    {"name": "Seed Shop",    "costs": {"wood": 60, "gold": 40},
		"build_time": 25.0, "hp": 400.0, "size": 30.0,
		"desc": "Sells seeds to farmers. Stock: 25, cap 200, 5 gold each."},
	"barracks":    {"name": "Barracks",     "costs": {"wood": 120, "oil": 100, "gold": 60},
		"build_time": 50.0, "hp": 800.0, "size": 40.0,
		"desc": "Trains soldiers, archers, guards."},
	"fishing_dock": {"name": "Fishing Dock", "costs": {"wood": 70, "oil": 30},
		"build_time": 30.0, "hp": 450.0, "size": 30.0, "near_water": true,
		"desc": "Must be built near water. Fishers work here."},
	"wall":        {"name": "Wall Segment", "costs": {"oil": 25},
		"build_time": 12.0, "hp": 900.0, "size": 18.0,
		"desc": "Defensive wall. Chain segments into lines."},
	# --- Bridge (HTML bridge_drag tool / "bridge" segment). Drag across
	# water: cost per 30px segment from the HTML COSTS.bridge_drag entry.
	"bridge":      {"name": "Bridge Segment", "costs": {"wood": 10, "gold": 2},
		"build_time": 8.0, "hp": 550.0, "size": 40.0,
		"desc": "Drag across water. Units walk the deck instead of swimming."},
	# --- Milestone 3b: HTML building ports (costs scaled from the HTML
	# COSTS table where present; invented to match Godot's economy where
	# the HTML had none). Only gold/wood/food/seeds/oil are used.
	"aa_tower":    {"name": "AA Tower",      "costs": {"wood": 60, "oil": 50, "gold": 30},
		"build_time": 40.0, "hp": 700.0, "size": 26.0,
		"desc": "Anti-air tower. Shoots down flying threats."},
	"bathhouse":   {"name": "Bathhouse",     "costs": {"wood": 90, "oil": 40, "gold": 30},
		"build_time": 35.0, "hp": 500.0, "size": 32.0,
		"desc": "Public baths. Serves the hygiene urge; uses water."},
	"courthouse":  {"name": "Courthouse",    "costs": {"wood": 140, "oil": 100, "gold": 80},
		"build_time": 55.0, "hp": 900.0, "size": 40.0,
		"desc": "Seat of law and leadership. Lifts town morale."},
	# --- Government district (HTML GOV_OFFICE_TYPES). Auto-laid north of the
	# hall by lay_government_district() — never offered in the build menu
	# (see is_player_buildable). Costs/HP/sizes from the HTML COSTS, hpMap,
	# sizeMap tables; oil scaled like the other 3b ports.
	"gov_office":  {"name": "Government Office", "costs": {"wood": 60, "oil": 40, "gold": 80},
		"build_time": 45.0, "hp": 500.0, "size": 56.0,
		"desc": "Civic. District office; advisors work the cubicles inside. Auto-placed, not buildable."},
	"gov_treasury": {"name": "Treasury Office",  "costs": {"wood": 55, "oil": 35, "gold": 90},
		"build_time": 45.0, "hp": 520.0, "size": 58.0,
		"desc": "Civic. Treasury office; the economy advisor works here. Auto-placed, not buildable."},
	"gov_war_office": {"name": "War Office",     "costs": {"wood": 70, "oil": 45, "gold": 100},
		"build_time": 45.0, "hp": 540.0, "size": 58.0,
		"desc": "Civic. War office; the war advisor works here. Auto-placed, not buildable."},
	"gov_justice": {"name": "Justice Office",    "costs": {"wood": 60, "oil": 40, "gold": 85},
		"build_time": 45.0, "hp": 500.0, "size": 56.0,
		"desc": "Civic. Justice office; the civic advisor works here. Auto-placed, not buildable."},
	"farmhouse":   {"name": "Farmhouse",     "costs": {"wood": 80, "oil": 30, "gold": 20},
		"build_time": 30.0, "hp": 450.0, "size": 34.0,
		"desc": "Upgraded farm. Farmers gather food 50% faster here."},
	"flesh_farm":  {"name": "Flesh Farm",    "costs": {"wood": 60, "oil": 40, "gold": 20},
		"build_time": 30.0, "hp": 450.0, "size": 34.0,
		"desc": "UNDEAD unique. Grows food from... corpses."},
	"guard_house": {"name": "Guard House",   "costs": {"wood": 70, "oil": 30},
		"build_time": 25.0, "hp": 500.0, "size": 30.0,
		"desc": "Guard barracks. Smaller than a tower; auto-staffs 2 guards."},
	# Jeremy 2026-10-04: the justice system needs real cells. Holds
	# prisoners in pretrial detention and serving sentences.
	"jail":        {"name": "Jail",          "costs": {"wood": 100, "oil": 60, "gold": 40},
		"build_time": 40.0, "hp": 700.0, "size": 34.0,
		"desc": "Stone cells with iron bars. Holds prisoners awaiting trial and serving sentences."},
	"guild_hall":  {"name": "Guild Hall",    "costs": {"wood": 120, "oil": 80, "gold": 60},
		"build_time": 50.0, "hp": 800.0, "size": 40.0,
		"desc": "Guild master office. Auto-staffs 1 guild master who hires workers."},
	# The HTML calls the town center "hall"; Godot's canonical type is
	# "town_hall". This alias keeps HTML save/type references working.
	"hall":        {"name": "Town Hall",    "costs": {"wood": 150, "oil": 100},
		"build_time": 60.0, "hp": 1200.0, "size": 46.0,
		"desc": "Town center. Founding building; drop-off for all hauling."},
	"horse_stable": {"name": "Horse Stable", "costs": {"wood": 110, "oil": 70, "gold": 50},
		"build_time": 45.0, "hp": 550.0, "size": 36.0,
		"desc": "Stables horses. Boosts transport and unit speed."},
	"knights_castle": {"name": "Knight's Castle", "costs": {"wood": 150, "oil": 120, "gold": 100},
		"build_time": 70.0, "hp": 1500.0, "size": 52.0,
		"desc": "HUMAN unique. Military headquarters of the realm."},
	"mage_spire":  {"name": "Mage Spire",    "costs": {"wood": 160, "oil": 120, "gold": 110},
		"build_time": 70.0, "hp": 1400.0, "size": 48.0,
		"desc": "GNOME unique. Tower of magic research."},
	"repair_shop": {"name": "Repair Shop",   "costs": {"wood": 80, "oil": 50, "gold": 30},
		"build_time": 35.0, "hp": 550.0, "size": 32.0,
		"desc": "Workshop. Buildings repaired nearby are fixed 50% faster."},
	"storage":     {"name": "Storage",       "costs": {"wood": 70, "oil": 30},
		"build_time": 25.0, "hp": 500.0, "size": 34.0,
		"desc": "Generic storage. Extra room for hauling drop-offs."},
	"trade_outpost": {"name": "Trade Outpost", "costs": {},
		"build_time": 0.0, "hp": 600.0, "size": 36.0,
		"desc": "Diplomatic trade post. Marks a faction's end of a trade \
route; raised automatically when a route opens. Not player-buildable."},
	"stock_gold":  {"name": "Gold Vault",    "costs": {"wood": 60, "oil": 30, "gold": 30},
		"build_time": 20.0, "hp": 400.0, "size": 30.0,
		"desc": "Resource-specific storage. Secures gold."},
	"stock_wood":  {"name": "Lumber Yard",   "costs": {"wood": 90, "oil": 20},
		"build_time": 20.0, "hp": 400.0, "size": 30.0,
		"desc": "Resource-specific storage. Stockpiles wood."},
	"stock_food":  {"name": "Granary",       "costs": {"wood": 60, "oil": 20},
		"build_time": 20.0, "hp": 400.0, "size": 30.0,
		"desc": "Resource-specific storage. Preserves food."},
	"stock_oil":   {"name": "Oil Depot",     "costs": {"wood": 60, "oil": 30},
		"build_time": 20.0, "hp": 400.0, "size": 30.0,
		"desc": "Resource-specific storage. Holds oil."},
	"stock_seeds": {"name": "Seed Silo",     "costs": {"wood": 55, "oil": 15},
		"build_time": 20.0, "hp": 400.0, "size": 30.0,
		"desc": "Resource-specific storage. Keeps seeds."},
	"war_hut":     {"name": "War Hut",       "costs": {"wood": 140, "oil": 100, "gold": 90},
		"build_time": 60.0, "hp": 1200.0, "size": 48.0,
		"desc": "OGRE unique. War hut; heart of the horde's military."},
	"well":        {"name": "Well",          "costs": {"wood": 30},
		"build_time": 15.0, "hp": 300.0, "size": 20.0,
		"desc": "Town water source."},
	# --- Farm animals (HTML Stage-8 s8StockFarmAnimals). Barn -> cow+pig,
	# coop -> chicken+chicken, second barn -> goat+sheep. Animals yield
	# food daily into the faction stock.
	"barn":        {"name": "Barn",          "costs": {"wood": 100, "oil": 40},
		"build_time": 35.0, "hp": 500.0, "size": 38.0,
		"desc": "Houses livestock. Cows and pigs move in; yields food daily."},
	"coop":        {"name": "Chicken Coop",  "costs": {"wood": 50, "oil": 20},
		"build_time": 20.0, "hp": 350.0, "size": 28.0,
		"desc": "Houses chickens. Yields food daily."},
	"windmill":    {"name": "Windmill",      "costs": {"wood": 90, "oil": 40, "gold": 20},
		"build_time": 40.0, "hp": 600.0, "size": 36.0,
		"desc": "Catches the wind. Boosts nearby production."},
	# --- Milestone 3c: more HTML ports (COSTS table values scaled to the
	# Godot economy like the 3b ports). Zones: restaurants/hotels/inns want
	# commercial/residential; camps, foundries, depots want military.
	"restaurant":  {"name": "Restaurant",    "costs": {"wood": 70, "oil": 45, "gold": 30},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "Tavern/eatery. Named per race (Cheese Shop, Soul Café...); serves eat + social urges."},
	"hotel":       {"name": "Hotel",         "costs": {"wood": 90, "oil": 60, "gold": 35},
		"build_time": 40.0, "hp": 550.0, "size": 34.0,
		"desc": "Hotel. Serves sleep and social urges; gold income from guests."},
	"inn":         {"name": "Inn",           "costs": {"wood": 95, "oil": 70, "gold": 45},
		"build_time": 40.0, "hp": 550.0, "size": 34.0,
		"desc": "Inn. Serves every need; rooms for travelers."},
	"weaponsmith": {"name": "Weapon Shop",   "costs": {"wood": 85, "oil": 60, "gold": 40},
		"build_time": 40.0, "hp": 600.0, "size": 32.0,
		"desc": "Smithy. Paid weapon upgrades; they visibly change avatars."},
	"townhall":    {"name": "Town Hall",    "costs": {"wood": 150, "oil": 100},
		"build_time": 60.0, "hp": 1200.0, "size": 46.0,
		"desc": "Town center. Founding building; drop-off for all hauling. ('townhall' alias)"},
	"camp":        {"name": "Resource Camp", "costs": {"wood": 60, "oil": 30, "gold": 20},
		"build_time": 25.0, "hp": 350.0, "size": 30.0,
		"desc": "Field camp. Harvest drop-off far from town."},
	"cannon_foundry": {"name": "Cannon Foundry", "costs": {"wood": 160, "oil": 130, "gold": 110},
		"build_time": 65.0, "hp": 900.0, "size": 40.0,
		"desc": "Military. Builds cannons for the war effort."},
	"field_camp":  {"name": "Field Camp",    "costs": {"wood": 45, "oil": 30},
		"build_time": 20.0, "hp": 300.0, "size": 30.0,
		"desc": "Military. Forward camp; musters soldiers in the field."},
	"medic_camp":  {"name": "Medic Camp",    "costs": {"wood": 55, "oil": 40, "gold": 20},
		"build_time": 25.0, "hp": 350.0, "size": 30.0,
		"desc": "Military. Heals soldiers in the field."},
	"equip_camp":  {"name": "Equipment Camp", "costs": {"wood": 50, "oil": 35, "gold": 20},
		"build_time": 25.0, "hp": 350.0, "size": 30.0,
		"desc": "Military. Repairs and re-equips troops in the field."},
	"armory":      {"name": "Armory",        "costs": {"wood": 90, "oil": 60, "gold": 50},
		"build_time": 40.0, "hp": 700.0, "size": 34.0,
		"desc": "Military. Stores weapons for the garrison."},
	"shooting_range": {"name": "Shooting Range", "costs": {"wood": 90, "oil": 70, "gold": 40},
		"build_time": 40.0, "hp": 400.0, "size": 36.0,
		"desc": "Military. Trains archers and musketeers."},
	"vehicle_depot": {"name": "Vehicle Depot", "costs": {"wood": 100, "oil": 80, "gold": 60},
		"build_time": 45.0, "hp": 600.0, "size": 36.0,
		"desc": "Military. Stores wagons and siege engines."},
	"nuke_silo":   {"name": "Nuke Silo",      "costs": {"wood": 170, "oil": 150, "gold": 180},
		"build_time": 90.0, "hp": 1200.0, "size": 44.0,
		"desc": "Military. Endgame deterrent."},
	# --- Faction uniques, race-locked via FACTION_UNIQUE below.
	"tome_library": {"name": "Tome Library",  "costs": {"wood": 155, "oil": 125, "gold": 100},
		"build_time": 65.0, "hp": 1300.0, "size": 48.0,
		"desc": "ELF unique. Library of deep magic research."},
	"necropolis":  {"name": "Necropolis",    "costs": {"wood": 170, "oil": 150, "gold": 150},
		"build_time": 80.0, "hp": 1600.0, "size": 56.0,
		"desc": "UNDEAD unique. Military necropolis; raises the dead roster."},
	"soul_cafe":   {"name": "Soul Café",     "costs": {"wood": 70, "oil": 50, "gold": 60},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "UNDEAD unique eatery. The dead dine on essence, not meals."},
	# --- Perk restaurants (SimFoodPerks): signature dishes grant timed
	# gameplay buffs, not just hunger. Jeremy 2026-10-04.
	"greasy_spoon": {"name": "Greasy Spoon", "costs": {"wood": 80, "oil": 50, "gold": 35},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "HUMAN perk eatery. Heart Attack Platter: work faster, waddle slower."},
	"salad_bar": {"name": "Salad Bar", "costs": {"wood": 75, "oil": 45, "gold": 40},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "HUMAN perk eatery. Kale Smoothie: light step, smug mood."},
	"ogre_sausage_shop": {"name": "Ogre Sausage", "costs": {"wood": 85, "oil": 55, "gold": 40},
		"build_time": 35.0, "hp": 500.0, "size": 34.0,
		"desc": "OGRE perk eatery. Ogre Sausage Link: hit harder. Sometimes regrets."},
	"meat_tornado": {"name": "Meat Tornado", "costs": {"wood": 90, "oil": 60, "gold": 45},
		"build_time": 40.0, "hp": 500.0, "size": 34.0,
		"desc": "OGRE perk eatery. Mystery Meat Skewer: tougher hide, slow mend."},
	"moonberry_lounge": {"name": "Moonberry Lounge", "costs": {"wood": 80, "oil": 55, "gold": 50},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "ELF perk eatery. Moonberry Tart: blissful mood, easy chatter."},
	"dewdrop_diner": {"name": "Dewdrop Diner", "costs": {"wood": 75, "oil": 50, "gold": 45},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "ELF perk eatery. Morning Dew Tea: rested and quick at work."},
	"bastard_drivethru": {"name": "Taco Bastard Drive-Thru", "costs": {"wood": 85, "oil": 55, "gold": 40},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "GNOME perk eatery. Bastard Burrito: blazing fast. Gut roulette."},
	"fungus_hut": {"name": "Fungus Hut", "costs": {"wood": 70, "oil": 45, "gold": 35},
		"build_time": 30.0, "hp": 400.0, "size": 30.0,
		"desc": "GNOME perk eatery. Glowcap Stew: happy trip, shoddy work."},
	"crypt_kitchen": {"name": "Crypt Kitchen", "costs": {"wood": 80, "oil": 55, "gold": 50},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "UNDEAD perk eatery. Essence Soup: tireless labor."},
	"grave_snacks": {"name": "Grave Snacks", "costs": {"wood": 75, "oil": 50, "gold": 40},
		"build_time": 35.0, "hp": 450.0, "size": 32.0,
		"desc": "UNDEAD perk eatery. Finger Sandwiches: savage strength. They're fingers."},
	# --- Misc placeables (HTML PLAYER_BUILDABLES: garden, fence, pier).
	"garden":      {"name": "Garden Plot",   "costs": {"wood": 15},
		"build_time": 10.0, "hp": 150.0, "size": 24.0,
		"desc": "Decor. Garden plot; lifts nearby morale."},
	"fence":       {"name": "Fence",         "costs": {"wood": 2},
		"build_time": 5.0, "hp": 250.0, "size": 12.0,
		"desc": "Cheap wooden fence segment. Boundary marker, not a fortification."},
	"pier":        {"name": "Pier",          "costs": {"wood": 40, "oil": 20},
		"build_time": 25.0, "hp": 350.0, "size": 28.0, "near_water": true,
		"desc": "Wooden pier reaching over the water's edge."},
}

## Buildings whose completion auto-staffs service units.
const SERVICE_BUILDINGS := {
	"clinic": "doctor",
	"fire_station": "firefighter",
	"guild_hall": "guild_master",
	"guard_house": "guard",
	# Jeremy 2026-10-04: every courthouse gets its judge for live trials.
	"courthouse": "judge",
}


## Faction-locked building types: btype -> faction id. Any other faction
## placing one is blocked with last_block_reason = "wrong_faction".
const FACTION_UNIQUE := {
	"knights_castle": "humans",
	"mage_spire": "gnomes",
	"war_hut": "ogres",
	"flesh_farm": "undead",
	"tome_library": "elves",
	"necropolis": "undead",
	"soul_cafe": "undead",
}


## HARD BUILDING CAP (HTML C65): 180 buildings total. Enforced in
## place_blueprint; halls/town halls are exempt (town centers).
const BUILDING_CAP := 180
const CAP_EXEMPT := ["hall", "town_hall", "townhall"]


## --- Government district (HTML ensureGovernmentDistrict) ------------------
## Four civic office types, auto-laid as a district north of each faction's
## hall — never offered in the build menu (is_player_buildable). District
## records carry is_gov = true (HTML b.isGov: damped collision shove, and
## zone growth never builds over a hall/townhall/isGov building).
const GOV_OFFICE_TYPES := ["gov_office", "gov_treasury", "gov_war_office",
	"gov_justice"]

## Grid cell in px the district layout is measured in (HTML ZONE_CELL).
const GOV_DISTRICT_CELL := 96.0

## District layout: townhall spot is (0,-2) in the HTML, but Godot's
## "town_hall" IS the founding hall, so the port lays only the four offices
## around the existing hall.
const GOV_DISTRICT_SPOTS := [
	{"type": "gov_office", "ox": -2, "oy": -3},
	{"type": "gov_treasury", "ox": 2, "oy": -3},
	{"type": "gov_war_office", "ox": -2, "oy": -4},
	{"type": "gov_justice", "ox": 2, "oy": -4},
]

## Advisor staff spawned once per faction with the district (HTML
## ensureGovernmentDistrict roles). Actual spawning is the spawner's job;
## this is the data contract. Advisors are non-workers (is_advisor) who
## work INSIDE the district offices at claimed desks.
const GOV_ADVISOR_ROLES := [
	{"job": "advisor_economy", "name": "Treasury Advisor"},
	{"job": "advisor_war", "name": "War Advisor"},
	{"job": "advisor_civic", "name": "Civic Advisor"},
	{"job": "clerk", "name": "Draft Clerk"},
]

## Periodic government decisions (HTML GOV_DECISIONS): every ~45 s each
## active faction resolves one at random — the player gets a popup, the AI
## auto-resolves (55% approve). Effects live in other systems (draft =
## spawner, tax/rations = resources/population, trade = diplomacy); this is
## the data contract for the HUD panel.
const GOV_DECISIONS := [
	{"id": "draft", "title": "Emergency Draft",
		"body": "Conscript villagers into the army?"},
	{"id": "tax", "title": "Raise War Tax",
		"body": "Collect extra gold from industry?"},
	{"id": "peace", "title": "Seek Trade",
		"body": "Open trade with a neutral faction?"},
	{"id": "artillery", "title": "Crew the Guns",
		"body": "Draft citizens onto parked artillery?"},
	{"id": "rations", "title": "Ration Food",
		"body": "Distribute food from storage to civilians?"},
]


## --- Naval (HTML fishing_dock trains fishing_boat + war_ship) ---------------
## Boats are UNITS, not buildings: no crew aboard, the hull is the unit
## (HTML isBoat). Trained at a completed fishing_dock, launched into water
## next to the dock — never on land — and exempt from the town cap (naval
## units, not town citizens).
const BOAT_JOBS := ["fishing_boat", "war_ship"]

## Boat training spec (HTML COSTS + TRAIN_TIME + Unit init multipliers).
## fish_period/fish_per_haul: the fishing_boat drifts to the nearest lake
## with fish and hauls this much food per period (HTML: 2.5 s, up to 10).
const BOAT_SPECS := {
	"fishing_boat": {"train_cost": {"gold": 60, "wood": 50}, "train_time": 4.5,
		"hp_mul": 0.9, "dmg_mul": 0.3, "range": 60.0, "attack_rate": 1.2,
		"speed_mul": 1.35, "fish_period": 2.5, "fish_per_haul": 10},
	"war_ship": {"train_cost": {"gold": 150, "wood": 110}, "train_time": 7.0,
		"hp_mul": 2.6, "dmg_mul": 2.2, "range": 220.0, "attack_rate": 1.6,
		"speed_mul": 1.1, "splash_radius": 60.0, "splash_mul": 0.5},
}

## Boat launch: trained hulls spawn in water found by a ring search around
## the dock (HTML: 24 angles, distance 50..280 in 38px steps). The spawner
## owns the water lookup; these are the search bounds.
const BOAT_LAUNCH_MIN := 50.0
const BOAT_LAUNCH_MAX := 280.0
const BOAT_LAUNCH_STEP := 38.0


## --- Bridge tool (HTML bridge_drag) ------------------------------------------
## The build-mode id is "bridge_drag"; placed records are type "bridge".
## Cost per segment, deck walk radius, and placement margins are verbatim
## from the HTML canPlaceBridge / Bridge deck constants.
const BRIDGE_SEG_SPACING := 30.0   # drag distance between segments
const BRIDGE_WATER_MARGIN := 80.0  # must be within 80px of water
const BRIDGE_DECK_RADIUS := 34.0   # completed deck walk radius (bridgeAt)
const BRIDGE_MAP_MARGIN := 70.0    # placement kept 70px off map edges
const BRIDGE_STACK_DIST := 26.0    # no second segment within 26px
const BRIDGE_OVERLAP_PAD := 24.0   # vs other buildings: size*0.7 + 24


## Build-menu category tabs, ported from the HTML BUILD_TABS (zones, roads,
## homes, services, military). The HUD builds one tab row from these and
## filters SimBuildings.BUILDINGS by build_category().
const BUILD_TABS := [
	["zones", "Zones"],
	["roads", "Roads"],
	["homes", "Homes"],
	["services", "Services"],
	["military", "Military"],
]

## Types the HTML buildCat() routes to the Homes tab.
const HOME_TYPES := ["house", "storage", "inn", "hotel"]

## Types the HTML buildCat() routes to the Military tab (extended with the
## undead necropolis and the other military support buildings).
const MILITARY_TYPES := [
	"barracks", "cannon_foundry", "aa_tower", "guard_tower", "guard_house",
	"nuke_silo", "field_camp", "medic_camp", "equip_camp",
	"knights_castle", "war_hut", "mage_spire", "tome_library", "necropolis",
	"armory", "shooting_range", "vehicle_depot",
]


## Which build-menu tab a type belongs to (HTML buildCat() logic).
## The bridge drag tool, pier, and fishing dock sit in the Roads tab next to
## the other waterfront/line tools (HTML buildCat routes them to 'roads').
static func build_category(btype: String) -> String:
	if btype == "trade_outpost":
		return ""  # diplomatic infrastructure: auto-raised by trade
	               # routes, never in the player build menu
	if btype.begins_with("zone"):
		return "zones"
	if btype in HOME_TYPES:
		return "homes"
	if btype in MILITARY_TYPES:
		return "military"
	if btype in ["bridge", "bridge_drag", "pier", "fishing_dock"]:
		return "roads"
	return "services"


## Per-race restaurant names (HTML eateryName): the same "restaurant" type
## wears a different sign per faction.
const EATERY_NAMES := {
	"humans": "Cheese Shop",
	"ogres": "Ogre Fried Turkey",
	"elves": "Gilded Acorn",
	"gnomes": "Taco Bastard",
	"undead": "Soul Café",
}

## Per-race signature dishes (HTML eateryDish).
const EATERY_DISHES := {
	"humans": {"id": "cheese_wheel", "name": "Cheese Wheel", "buy": 18, "sell": 8},
	"ogres": {"id": "fried_turkey", "name": "Whole Fried Turkey", "buy": 30, "sell": 12},
	"elves": {"id": "honeycake", "name": "Honeycake", "buy": 16, "sell": 7},
	"gnomes": {"id": "taco", "name": "Gnome Taco", "buy": 14, "sell": 6},
	"undead": {"id": "soul_brew", "name": "Soul Brew", "buy": 20, "sell": 8},
}


## Display name for a restaurant of a faction (race-specific sign).
static func eatery_name(faction: String) -> String:
	return String(EATERY_NAMES.get(faction, "Tavern"))


## Signature dish dict for a faction's eatery, or {}.
static func eatery_dish(faction: String) -> Dictionary:
	return (EATERY_DISHES.get(faction, {}) as Dictionary).duplicate()


## Instance display name: restaurants show the faction eatery name
## (HTML bldName); everything else uses building_name().
static func display_name(btype: String, faction: String = "") -> String:
	if btype == "restaurant":
		return eatery_name(faction)
	return building_name(btype)


## True when a type never counts against the building cap (town centers).
static func is_cap_exempt(btype: String) -> bool:
	return btype in CAP_EXEMPT


## True for the four civic office types (government district buildings).
static func is_gov_building(btype: String) -> bool:
	return btype in GOV_OFFICE_TYPES


## True when the build menu may offer the type. Gov offices are never
## player-buildable (HTML: they are auto-laid by ensureGovernmentDistrict).
static func is_player_buildable(btype: String) -> bool:
	return is_building(btype) and not is_gov_building(btype)


## Spec dict for a boat job ({} for non-boats). See BOAT_SPECS.
static func boat_spec(job: String) -> Dictionary:
	return (BOAT_SPECS.get(job, {}) as Dictionary).duplicate()


## Unit jobs a completed building can train (HTML Building.trainOptions).
static func train_options(btype: String) -> Array:
	if btype == "fishing_dock":
		return BOAT_JOBS.duplicate()
	return []


## The completed bridge deck under a point, or {} (HTML bridgeAt:
## "walk here, don't swim" — units on a deck stay dry).
static func bridge_at(buildings: Array, pos: Vector2) -> Dictionary:
	for b: Dictionary in buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("type", "")) != "bridge":
			continue
		if pos.distance_to(b.get("position", Vector2.ZERO)) < BRIDGE_DECK_RADIUS:
			return b
	return {}


## A random government decision (HTML tickGovernment). Pass a seeded RNG
## for deterministic tests.
static func pick_gov_decision(rng: RandomNumberGenerator) -> Dictionary:
	var d: Dictionary = GOV_DECISIONS[rng.randi_range(0, GOV_DECISIONS.size() - 1)]
	return d.duplicate()


## World positions for the district offices around a hall (does not place).
## Returns Array of {type, position}.
static func gov_district_spot_positions(hall_position: Vector2) -> Array:
	var out: Array = []
	for s: Dictionary in GOV_DISTRICT_SPOTS:
		out.append({
			"type": String(s["type"]),
			"position": hall_position + Vector2(
				float(s["ox"]) * GOV_DISTRICT_CELL,
				float(s["oy"]) * GOV_DISTRICT_CELL),
		})
	return out


## Lays a faction's government district around its hall (HTML
## ensureGovernmentDistrict): the four offices go down FREE and COMPLETE,
## tagged is_gov = true. A spot is skipped when a same-type building of the
## race is already within 40px, or ANY building within 70px. Idempotent per
## hall record: sets hall["gov_laid"] and no-ops when already laid.
## Returns the placed records.
## WIRING: the world update should call this once per faction when its
## first hall completes (the HTML runs it every 120 frames per race).
func lay_government_district(faction: String, hall: Dictionary,
		town_id: int) -> Array:
	var placed: Array = []
	if hall.is_empty() or bool(hall.get("gov_laid", false)):
		return placed
	hall["gov_laid"] = true
	var hp: Vector2 = hall.get("position", Vector2.ZERO)
	for s: Dictionary in gov_district_spot_positions(hp):
		var stype: String = String(s["type"])
		var spos: Vector2 = s["position"]
		var blocked := false
		for b: Dictionary in _gs.buildings:
			if not b.get("alive", false):
				continue
			var d: float = spos.distance_to(b.get("position", Vector2.ZERO))
			if String(b.get("type", "")) == stype \
					and String(b.get("faction", "")) == faction and d < 40.0:
				blocked = true
				break
			if d < 70.0:
				blocked = true
				break
		if blocked:
			continue
		var d2: Dictionary = BUILDINGS[stype]
		placed.append(_gs.add_building({
			"type": stype,
			"faction": faction,
			"town_id": town_id,
			"position": spos,
			"alive": true,
			"complete": true,
			"progress": 1.0,
			"hp": float(d2.get("hp", 400.0)),
			"max_hp": float(d2.get("hp", 400.0)),
			"is_gov": true,
		}))
	return placed


## Number of alive, cap-counted buildings (HTML C65 counts every alive
## building except halls/town halls).
static func count_capped(buildings: Array) -> int:
	var n := 0
	for b: Dictionary in buildings:
		if not b.get("alive", false):
			continue
		if is_cap_exempt(String(b.get("type", ""))):
			continue
		n += 1
	return n


## Unit ids visibly assigned to a construction site: units whose work state
## is to_build/building and whose work_building points at this building.
## Sim-side of the builder-crew visuals (the renderer draws them).
static func crew_of(units: Array, building_id: int) -> Array:
	var out: Array = []
	for u: Dictionary in units:
		if not u.get("alive", false):
			continue
		if int(u.get("work_building", -1)) != building_id:
			continue
		if String(u.get("work_state", "")) in ["to_build", "building"]:
			out.append(int(u.get("id", 0)))
	return out


## Building types farmers can work for food (infinite sources).
const FOOD_BUILDINGS := ["farm", "farmhouse", "fishing_dock", "flesh_farm"]

## Gather-rate multiplier when a farmer works a farmhouse (upgraded farm).
const FARMHOUSE_BONUS := 1.5

## Repair-rate multiplier when the repaired building is within range of a
## completed repair shop of the same faction.
const REPAIR_SHOP_BONUS := 1.5
const REPAIR_SHOP_RANGE := 400.0


var _gs: GameState


func _init(game_state: GameState) -> void:
	_gs = game_state


## True if the type id is a known building.
static func is_building(btype: String) -> bool:
	return BUILDINGS.has(btype)


## True when the faction may place a building type (faction uniques are
## locked to their faction; everything else is open to all 5 factions).
static func faction_may_build(btype: String, faction: String) -> bool:
	return not FACTION_UNIQUE.has(btype) \
		or String(FACTION_UNIQUE[btype]) == faction


## Staffing target for a service job ("doctor" | "firefighter" |
## "guild_master" | "guard"). Single source of truth — HUD reads this too.
static func service_want(job: String) -> int:
	match job:
		"firefighter":
			return Config.FIREFIGHTERS_PER_STATION
		"guard":
			return Config.GUARDS_PER_HOUSE
		"guild_master":
			return Config.GUILDMASTERS_PER_HALL
		"judge":
			return 1  # one judge per courthouse (Jeremy 2026-10-04)
		_:
			return Config.DOCTORS_PER_CLINIC


## Display name for a building type.
static func building_name(btype: String) -> String:
	var d: Dictionary = BUILDINGS.get(btype, {})
	return String(d.get("name", btype))


## Cost dict {resource -> amount} for a building type ({} if unknown).
static func cost_of(btype: String) -> Dictionary:
	var d: Dictionary = BUILDINGS.get(btype, {})
	return (d.get("costs", {}) as Dictionary).duplicate()


## True when the type must be placed near water (fishing dock).
## Enforced by the placement ghost (world/building_placement.gd); the pure
## sim has no map handle, so place_blueprint() does NOT check this.
static func requires_water(btype: String) -> bool:
	var d: Dictionary = BUILDINGS.get(btype, {})
	return bool(d.get("near_water", false))


## Footprint radius in px, used by placement overlap checks.
static func footprint(btype: String) -> float:
	var d: Dictionary = BUILDINGS.get(btype, {})
	return float(d.get("size", 30.0))


## Places a blueprint: deducts resources (atomic — fails if unaffordable),
## creates an incomplete building record, emits building_placed.
## Returns the record, or {} when blocked ("unknown_type" | "unaffordable" |
## "wrong_faction" recorded in last_block_reason).
var last_block_reason: String = ""


func place_blueprint(btype: String, faction: String, town_id: int,
		position: Vector2) -> Dictionary:
	last_block_reason = ""
	if not is_building(btype):
		last_block_reason = "unknown_type"
		return {}
	if FACTION_UNIQUE.has(btype) \
			and faction != String(FACTION_UNIQUE[btype]):
		last_block_reason = "wrong_faction"
		return {}
	# C65: hard cap 180 (halls exempt).
	if not is_cap_exempt(btype) \
			and count_capped(_gs.buildings) >= BUILDING_CAP:
		last_block_reason = "building_cap"
		return {}
	if not _gs.resources.spend(faction, _cost_for(btype, faction)):
		last_block_reason = "unaffordable"
		return {}
	var d: Dictionary = BUILDINGS[btype]
	var b: Dictionary = _gs.add_building({
		"type": btype,
		"faction": faction,
		"town_id": town_id,
		"position": position,
		"alive": true,
		"complete": false,
		"progress": 0.0,
		"hp": float(d.get("hp", 400.0)),
		"max_hp": float(d.get("hp", 400.0)),
	})
	return b


## Policy-adjusted build cost (HTML buildCost parity): the player's
## government makes construction cheaper or pricier.
func _cost_for(btype: String, faction: String) -> Dictionary:
	var cost: Dictionary = (cost_of(btype) as Dictionary).duplicate()
	if faction == _gs.player_faction and _gs.get("court_sys") != null \
			and _gs.court_sys.get("policies") != null:
		var m: float = _gs.court_sys.policies.build_cost_mult()
		for r: String in cost.keys():
			cost[r] = maxf(1.0, roundf(float(cost[r]) * m))
	return cost


## Breathing room (px) between building edges for AI auto-layout.
## Player placement stays at the bare no-overlap rule; the AI's town layout
## uses this gap so buildings read as separate structures instead of a jam.
## Jeremy 2026-10-06: districts must space buildings out more per block —
## airy blocks with room between buildings, not dense packing.
const PLACEMENT_GAP := 96.0


## True when a building's footprint would sit on water (HTML's
## footprintInWater guard): the center plus the four cardinal points at
## footprint radius are probed against the baked terrain grid. Bridges are
## exempt — they exist to cross water. Everything else (houses, barns,
## walls, docks...) must stay dry.
static func footprint_in_water(map_data: Dictionary, btype: String,
		position: Vector2) -> bool:
	if map_data.is_empty() or not map_data.has("terrain") \
			or btype == "bridge":
		return false
	if MapGen.nearest_water_tile(map_data, position, 0) != Vector2i(-1, -1):
		return true
	var r: float = footprint(btype)
	for off: Vector2 in [Vector2(r, 0), Vector2(-r, 0),
			Vector2(0, r), Vector2(0, -r)]:
		if MapGen.nearest_water_tile(map_data, position + off, 0) \
				!= Vector2i(-1, -1):
			return true
	return false


## True when a blueprint can legally go at position: no overlap with other
## buildings' footprints (walls excepted — they chain), and inside the map.
## Resource affordability is checked separately by place_blueprint().
## When faction is given, the HTML canPlaceBuilding rule applies: foreign
## builds are blocked on another faction's claimed territory (walls exempt).
## gap adds extra breathing room beyond the bare footprint check (used by
## AI auto-layout; player placement uses 0).
## map_data (optional): when provided, the footprint must not touch water
## (Jeremy 2026-10-10: barns were building in lakes).
static func can_place_at(buildings: Array, btype: String,
		position: Vector2, map_rect: Rect2, faction: String = "",
		gap: float = 0.0, post_claimants: Array = [],
		map_data: Dictionary = {}) -> bool:
	if not map_rect.has_point(position):
		return false
	if footprint_in_water(map_data, btype, position):
		return false
	# Perf R31: fused single pass. The old code ran claim_owner_at (a full
	# building scan for the territory check) and then the footprint loop (a
	# second full scan). Both are side-effect-free booleans over the same
	# array, so fusing them is behavior-identical.
	# HTML canPlaceBridge has no territory check — bridges may cross any water.
	# Jeremy 2026-10-06: Command Posts — held monasteries/crystals also
	# claim land (post_claimants from SimCommandPosts.claimants_of()).
	var check_territory: bool = faction != "" and btype != "wall" \
		and btype != "bridge"
	var r: float = footprint(btype)
	var best := ""
	var best_d := SimTerritory.TERRITORY_R
	for b: Dictionary in buildings:
		if not b.get("alive", false):
			continue
		# Walls and bridges chain: segments may touch/overlap their own kind
		# (bridge decks are 78px long on 30px spacing by design).
		var bt: String = String(b.get("type", ""))
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		if check_territory and b.get("complete", false) \
				and bt in SimTerritory.CLAIM_TYPES:
			var d: float = position.distance_to(bp)
			if d < best_d:
				best_d = d
				best = String(b.get("faction", ""))
		if btype == "wall" and bt == "wall":
			continue
		if btype == "bridge" and bt == "bridge":
			continue
		var br: float = footprint(bt)
		if position.distance_to(bp) < r + br + gap:
			return false
	# Command-post claims (monasteries/crystals held by a faction).
	if check_territory:
		for c in post_claimants:
			var cd := c as Dictionary
			if cd.is_empty():
				continue
			var cf: String = String(cd.get("faction", ""))
			if cf == "" or cf == faction:
				continue
			var cr: float = float(cd.get("radius", SimTerritory.TERRITORY_R))
			if position.distance_to(
					cd.get("position", Vector2.ZERO)) < cr:
				return false
	if check_territory and best != "" and best != faction:
		return false
	return true


## Advances construction. Each builder working on the blueprint contributes
## builder_power (1.0 = one builder) of progress per second against
## build_time. Returns true on the tick the building completes.
func tick_construction(building: Dictionary, builder_power: float,
		delta: float) -> bool:
	if building.get("complete", false) or not building.get("alive", false):
		return false
	var d: Dictionary = BUILDINGS.get(String(building.get("type", "")), {})
	var build_time: float = maxf(1.0, float(d.get("build_time", 30.0)))
	var progress: float = float(building.get("progress", 0.0))
	# Policies: government build-speed multiplier (HTML buildSpeed).
	var speed_mult := 1.0
	if _gs.get("court_sys") != null \
			and _gs.court_sys.get("policies") != null:
		speed_mult = _gs.court_sys.policies.build_speed_mult()
	progress += (builder_power * delta * speed_mult) / build_time
	if progress >= 1.0:
		building["progress"] = 1.0
		building["complete"] = true
		# Military zone: walls, towers, and barracks finish tougher.
		if _gs.zoning != null and String(building.get("type", "")) \
				in ["wall", "guard_tower", "barracks"]:
			var bp: Vector2 = building.get("position", Vector2.ZERO)
			if _gs.zoning.defense_mult_at(bp, String(building.get("faction", ""))) > 1.0:
				building["max_hp"] = float(building["max_hp"]) \
					* SimZoning.WALL_HP_BONUS
		building["hp"] = building["max_hp"]
		_gs.bus.building_placed.emit(building)  # completion fanfare hook
		# Jeremy 2026-10-08: HTML celebrate parity (fix79:
		# u.buildTarget === this -> u._celebrateT = 2.4) — the crew that
		# raised it hops with joy. The world sync edge-triggers the
		# CELEBRATE one-shot from the flag and consumes it.
		var _bid: int = int(building.get("id", -1))
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			if int(u.get("work_building", -1)) != _bid:
				continue
			if String(u.get("work_state", "")) in ["to_build", "building"]:
				u["_celebrate_t"] = 2.4
		# Jeremy 2026-10-07 (wake rapid lane): feed the Gazette news
		# desk's BUILDING BOOM trivia bucket — one tally per
		# completion (wired live 2026-10-07; the bucket is not dormant). Walls excluded: drag-place chains finish dozens
		# at once and would keep the bucket permanently tripped.
		# Reported straight to the news desk, not bus.gazette_story,
		# so the rumor mill doesn't mint a whisper for every farm —
		# the aggregated BOOM story still reaches the bus, Chronicle,
		# and mill through court.publish_story.
		_report_completion_trivia(building)
		# Jeremy 2026-10-07 (wake audio lane): a finished building finally
		# makes a sound — the "build" SFX at the site.
		_gs.bus.sfx_spatial.emit("build",
			building.get("position", Vector2.ZERO), Vector2.ZERO)
		return true
	building["progress"] = progress
	return false


## One building-completion tally for the news desk's BUILDING BOOM
## trivia bucket (called from tick_construction's completion branch).
## Null-safe: bare-sim tests and worlds without a court skip silently;
## no new persisted state, so old saves are unaffected.
func _report_completion_trivia(building: Dictionary) -> void:
	var btype := String(building.get("type", ""))
	if btype == "" or btype == "wall":
		return
	var court = _gs.get("court_sys")
	if court == null:
		return
	var desk = court.get("news_desk")
	if desk == null or not desk.has_method("report"):
		return
	var disp := String(building.get("name", ""))
	if disp == "":
		disp = btype.replace("_", " ")
	desk.report("Finished a " + disp,
		"The builders finished a %s." % disp)


## Per-tick service-building behavior. Clinics/fire stations auto-staff
## their service units with a retry throttle (mirrors the HTML 10 s rule).
## Call once per building per tick from the world update.
func tick_service(building: Dictionary, delta: float) -> void:
	if not building.get("complete", false) or not building.get("alive", false):
		return
	var btype: String = String(building.get("type", ""))
	if not SERVICE_BUILDINGS.has(btype):
		return
	var job: String = String(SERVICE_BUILDINGS[btype])
	var faction: String = String(building.get("faction", ""))
	# Retry throttle, stored on the record (survives save/load as a number).
	var now: float = Time.get_ticks_msec() / 1000.0
	var next_try: float = float(building.get("_staff_next_try", 0.0))
	if now < next_try:
		return
	building["_staff_next_try"] = now + Config.AUTOSPAWN_RETRY_SECONDS
	var want: int = service_want(job)
	var have: int = _gs.population.count_job(faction, job)
	if have >= want:
		return
	var town_id: int = int(building.get("town_id", -1))
	var pos: Vector2 = building.get("position", Vector2.ZERO) + Vector2(24, 16)
	# Fill to the staffing target in one pass (HTML spawned both at once);
	# the spawner still enforces every cap per unit, so this can't overshoot.
	for i: int in range(want - have):
		var made: Dictionary = _gs.spawner.spawn_unit(
			faction, job, town_id, pos + Vector2(i * 18.0, 0.0))
		if made.is_empty():
			break


## Heals units near a completed clinic. Returns number healed.
func tick_clinic_heal(building: Dictionary, heal_per_sec: float,
		delta: float) -> int:
	if String(building.get("type", "")) != "clinic":
		return 0
	if not building.get("complete", false) or not building.get("alive", false):
		return 0
	var healed: int = 0
	var bp: Vector2 = building.get("position", Vector2.ZERO)
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != String(building.get("faction", "")):
			continue
		var hp: float = float(u.get("hp", 100.0))
		var max_hp: float = float(u.get("max_hp", 100.0))
		if hp >= max_hp:
			continue
		var up: Vector2 = u.get("position", Vector2.ZERO)
		if up.distance_to(bp) > 220.0:
			continue
		u["hp"] = minf(max_hp, hp + heal_per_sec * delta)
		healed += 1
	return healed
