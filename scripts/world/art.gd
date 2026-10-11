class_name Art
extends RefCounted
## Cursing Gnomes — sprite art manager.
##
## All artwork is ported from the HTML build (v0930.59), extracted to
## res://assets/art/ (see assets/art/manifest.json). Textures load lazily
## and are cached here so 96 unit sprites don't all decode at boot.
##
## Sprite identity is a faithful port of the HTML's appearanceKey54() +
## chibiArchetype(): race_archetype_gender+variant, deterministic per unit.


const UNIT_DIR := "res://assets/art/units/"
const BUILDING_DIR := "res://assets/art/buildings/"
const WALL_DIR := "res://assets/art/walls/"
const TREE_DIR := "res://assets/art/trees/"
const JOBTAG_DIR := "res://assets/art/jobtags/"
const FURNITURE_DIR := "res://assets/art/furniture/"
const PORTRAIT_DIR := "res://assets/art/portraits/"
const FX_DIR := "res://assets/art/fx/"
const ICON_DIR := "res://assets/art/icons/"
const NODES_DIR := "res://assets/art/nodes/"
const ANIMAL_DIR := "res://assets/art/animals/"
const GODS_DIR := "res://assets/gods/"
const VEHICLE_DIR := "res://assets/art/vehicles/"
const BOAT_DIR := "res://assets/art/boats/"
const TOOL_DIR := "res://assets/art/tools/"

static var _cache: Dictionary = {}


## Job -> chibi archetype. Port of the HTML's chibiArchetype().
static func archetype_for_job(job: String) -> String:
	var j: String = job.to_lower()
	if "ruler" in j:
		return "mage"
	for w: String in ["mage", "caster", "warlock", "shaman", "doctor",
			"medic", "priest", "druid", "alchemist"]:
		if w in j:
			return "mage"
	for w2: String in ["archer", "ranger", "musketeer", "sniper", "hunter",
			"scout"]:
		if w2 in j:
			return "ranger"
	for w3: String in ["knight", "axeman", "axe", "clubber", "berserker",
			"soldier", "warrior", "guard", "general", "chieftain",
			"commander", "mayor", "paladin", "brute", "raider", "cannoneer"]:
		if w3 in j:
			return "warrior"
	return "worker"


## Unit -> sprite key, e.g. "gnome_worker_m0". Port of appearanceKey54().
static func appearance_key(faction: String, job: String, unit_id: int,
		gender: String) -> String:
	# FIX 2026-10-02: factions are plural ("humans") but sprite files use
	# singular ("human"). Map correctly instead of defaulting to gnome.
	# NOTE: naive s-stripping breaks "elves" -> "elve", so use explicit map.
	var r: String = faction.to_lower()
	var singular := {
		"humans": "human", "ogres": "ogre", "elves": "elf",
		"gnomes": "gnome", "undead": "undead",
		"human": "human", "ogre": "ogre", "elf": "elf",
		"gnome": "gnome",
	}
	r = singular.get(r, "gnome")
	# Undead use their own unique unit types, not the generic archetypes.
	# (Jeremy 2026-10-03: "Undead never had mage they had their own uniques")
	if r == "undead":
		var ujob: String = job.to_lower()
		# Map generic jobs to skeleton (HTML: generic undead jobs render as skeletons)
		var undead_types := ["skeleton", "zombie", "ghoul", "wraith",
			"necromancer", "plaguebearer", "bone_golem", "lich"]
		var utype: String = "skeleton"  # default for generic jobs
		for t: String in undead_types:
			if t in ujob or ujob in t:
				utype = t
				break
		var uh: int = absi(hash("%d|%s|%s" % [unit_id, r, ujob]))
		return "%s_%s_%d" % [r, utype, uh % 2]
	var arch: String = archetype_for_job(job)
	var g: String = "f" if gender == "f" else "m"
	var h: int = absi(hash("%d|%s|%s|%s" % [unit_id, r, job, gender]))
	return "%s_%s_%s%d" % [r, arch, g, h % 2]


static func _tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path) as Texture2D
	_cache[path] = t
	return t


## Chibi sprite for a unit, or null if the key has no art.
static func unit_texture(faction: String, job: String, unit_id: int,
		gender: String) -> Texture2D:
	return _tex(UNIT_DIR + appearance_key(faction, job, unit_id, gender)
		+ ".png")


## Boat hull texture for a boat job ("fishing_boat" / "war_ship"), or null
## for non-boat jobs. Port of the HTML's boatSprite() (BOAT.img registry) —
## AI-generated pixel-art hulls extracted from fix79's BOAT_SPRITE_SRC.
static func boat_texture(job: String) -> Texture2D:
	var j: String = job.to_lower()
	if j != "fishing_boat" and j != "war_ship":
		return null
	return _tex(BOAT_DIR + j + ".png")


## Faction accent colors — port of the HTML's RACES[race].accent. Used for
## the faction pennant fluttering from boat masts.
const FACTION_ACCENTS := {
	"gnome": Color("#8e24aa"), "ogre": Color("#388e3c"),
	"elf": Color("#2e7d32"), "human": Color("#0288d1"),
	"undead": Color("#37474f"),
}

static func faction_accent(faction: String) -> Color:
	var r: String = faction.to_lower()
	# NOTE: naive s-stripping breaks "elves" -> "elve", so use explicit map.
	var singular := {
		"humans": "human", "ogres": "ogre", "elves": "elf",
		"gnomes": "gnome", "undead": "undead",
		"human": "human", "ogre": "ogre", "elf": "elf",
		"gnome": "gnome",
	}
	return FACTION_ACCENTS.get(singular.get(r, "gnome"), Color(1, 1, 1))


## Furniture sprite for an extracted art key (e.g. "furn_bed_human"),
## or null when the kind has no art (procedural fallback).
## Jeremy 2026-10-07: the "fire" key (fire_lg_0) lives in the fx dir, not
## furniture — fall back there so hearths/campfires render their flame art.
static func furniture_texture(art_key: String) -> Texture2D:
	if art_key == "":
		return null
	var t: Texture2D = _tex(FURNITURE_DIR + art_key + ".png")
	if t != null:
		return t
	return _tex(FX_DIR + art_key + ".png")


## Portrait texture for a pfp key (e.g. "portrait_gnome_3"), or null.
## Portraits are stored as .webp; falls back to .png.
static func portrait_texture(pfp_key: String) -> Texture2D:
	if pfp_key == "":
		return null
	var t: Texture2D = _tex(PORTRAIT_DIR + pfp_key + ".webp")
	if t != null:
		return t
	return _tex(PORTRAIT_DIR + pfp_key + ".png")


## Job -> jobtag icon index. Port of the HTML's _jobIconMap54, extended for
## the Godot job roster (woodcutter/miner/farmer share the worker hard-hat).
const JOB_TAGS := {
	"worker": 0, "woodcutter": 0, "miner": 0, "farmer": 0,
	"roadbuilder": 1,
	"archer": 2, "ranger": 2,
	"mage": 4,
	"soldier": 5,
	"builder": 6,
	"doctor": 7,
	"firefighter": 8,
	"cannoneer": 9,
	"guard": 11,
	# HTML verbatim: war_ship isn't in _jobIconMap54 but IS in COMBAT_JOBS,
	# so jobIconFor54() falls back to the combat shield icon (idx 10).
	# fishing_boat has no tag in the HTML (no entry, not combat) — handled
	# by UnitNode's boat branch, not here.
	"war_ship": 10,
}


static func job_tag(job: String) -> Texture2D:
	var idx: int = int(JOB_TAGS.get(job, 0))
	return _tex(JOBTAG_DIR + "jobtag%d.png" % idx)


## Building type -> real art file, or "" when the HTML has no art for it
## (those buildings keep their programmer-art silhouettes).
const BUILDING_ART := {
	"town_hall": "bld_townhall.png",
	# Launch-readiness 2026-10-06: 'townhall' is a real placed btype (alias
	# def in buildings.gd) but had no art entry — it fell to the generic
	# box. Same sprite as town_hall.
	"townhall": "bld_townhall.png",
	"hall": "bld_hall.png",
	"house": "bld_house.png",
	"guard_tower": "bld_tower.png",
	"barracks": "bld_barracks.png",
	"flesh_farm": "bld_flesh_farm.png",
	"horse_stable": "bld_stable.png",
	"knights_castle": "bld_castle.png",
	"courthouse": "bld_civic.png",
	# Wake routine 2026-10-04: the six civic offices drew programmer-art
	# silhouettes (clinic/_clinic, tome_library/_tome_library, the gov_*
	# types fell through to the generic box+roof), but fix79's
	# BLD_SPRITE_FOR maps them ALL to bld_civic — the same real pixel art
	# courthouse already uses. The sprite path runs BEFORE the drawn
	# branches in the HTML, so the drawn arms stay as missing-art
	# fallback only (same as the tent/smithy ports).
	"gov_office": "bld_civic.png",
	"gov_treasury": "bld_civic.png",
	"gov_war_office": "bld_civic.png",
	"gov_justice": "bld_civic.png",
	"tome_library": "bld_civic.png",
	"clinic": "bld_civic.png",
	"jail": "bld_jail.png",
	"gate": "gatehouse.png",
	"wall": "wall_strip.png",
	"barn": "bld_barn.png",
	"coop": "bld_coop.png",
	# Graphics-hourly 2026-10-04: stockpiles + storage drew a generic
	# house-box silhouette, but fix79's BLD_SPRITE_FOR maps all six to
	# bld_shop (with bld_shop_undead for the undead race) and the art
	# was already extracted — the port just never mapped it.
	"storage": "bld_shop.png",
	"stock_gold": "bld_shop.png",
	"stock_wood": "bld_shop.png",
	"stock_food": "bld_shop.png",
	"stock_oil": "bld_shop.png",
	"stock_seeds": "bld_shop.png",
	# Wake routine 2026-10-04: windmill drew the programmer-art box + blades,
	# but fix79's BLD_SPRITE_FOR maps windmill to bld_windmill (real pixel
	# art shipped in AGRI62_BLD_B64) — extracted to assets and mapped here.
	# The blade-spin logic stays as the missing-art fallback path.
	"windmill": "bld_windmill.png",
	# Wake routine 2026-10-04: farmhouse fell through to the generic
	# box+roof arm, but fix79's BLD_SPRITE_FOR maps farmhouse to
	# bld_farmhouse (real pixel art shipped in AGRI62_BLD_B64) —
	# extracted to assets and mapped here.
	"farmhouse": "bld_farmhouse.png",
	# Graphics-hourly 2026-10-04: fence fell through to the generic
	# box+roof arm, but fix79 ships bld_fence62 (fences draw it as artKey
	# in the HTML's agri system) — extracted to assets and mapped here.
	# bld_crop_field and bld_cow62 are also extracted and staged for when
	# the crop_field/cattle_pen sim types get ported from the HTML.
	"fence": "bld_fence62.png",
	# Wake routine 2026-10-04: the necropolis (undead town center, the
	# HTML's bldHouseUndead68 bld_necropolis for undead hall/townhall)
	# fell through to the generic box+roof arm — the pixel art was
	# already extracted to assets but the port never mapped it.
	"necropolis": "bld_necropolis.png",
	# Wake routine 2026-10-04: the three camps and the weaponsmith drew
	# programmer-art silhouettes, but fix79's BLD_SPRITE_FOR maps them to
	# real pixel art (bld_tent_field / bld_tent_camp / bld_tent_medic /
	# bld_smithy) — the sprite path runs BEFORE the vector branches in
	# the HTML, so the drawn tent/medic/smith arms only ever render as
	# fallback when the sprite fails to load. Extracted and mapped here.
	"field_camp": "bld_tent_field.png",
	"camp": "bld_tent_camp.png",
	"equip_camp": "bld_tent_camp.png",
	"medic_camp": "bld_tent_medic.png",
	"weaponsmith": "bld_smithy.png",
	# Jeremy 2026-10-04: tool/shop petition chain — the blacksmith shares
	# the smithy sprite.
	"blacksmith": "bld_smithy.png",
	# Graphics-hourly 2026-10-04: fix79's BLD_SPRITE_FOR maps trade_outpost
	# to bld_shop (it fell through to the generic box+roof arm); undead
	# variant handled in BUILDING_ART_FACTION below (bldHouseUndead68).
	"trade_outpost": "bld_shop.png",
	# Wake routine 2026-10-04: fix79's bldMageSpireSprite64() maps
	# mage_spire to per-race art (bld_mage_spire_{elf,gnome,human,ogre}),
	# falling back to bld_tower when the race has no key (undead). The
	# per-race sprites are extracted to assets; the tower fallback is
	# mapped here as the base so undead spires match the HTML.
	"mage_spire": "bld_tower.png",
	# Jeremy 2026-10-04: fire station had procedural art — now proper
	# isometric pixel art. shooting_range art existed but was never mapped.
	"fire_station": "bld_fire_station.png",
	"shooting_range": "bld_archery_range.png",
	# Jeremy 2026-10-04: resource camps — gatherers haul here instead of
	# town hall (HTML parity; work.gd noted "Godot has no camp type").
	"resource_camp": "bld_resource_camp.png",
	# Jeremy 2026-10-05: lumber camps (Rise of Nations style) — AI-generated
	# isometric pixel art in the resource_camp style (cabin, sawbuck, log
	# stacks, chopping stump, log cart); transparency keyed in-tree.
	"lumber_camp": "bld_lumber_camp.png",
	# Jeremy 2026-10-05: oil pumps — AI-generated pumpjack art, same style;
	# transparency keyed in-tree.
	"oil_pump": "bld_oil_pump.png",
	# Wake routine 2026-10-04: fix79's bldGuardHouseSprite61() maps
	# guard_house to per-race art (bld_guard_house_{elf,gnome,human,ogre}).
	# Its fallback key 'bld_guard_house' has NO art in the HTML (TEX.img
	# miss), so the undead keep the drawn _guard_house arm — the port's
	# null path — hence no base BUILDING_ART entry here.
	# Wake routine 2026-10-05 (launch-readiness graphics pass): the last
	# drawn-silhouette building types that fix79's BLD_SPRITE_FOR maps to
	# real pixel art (extracted verbatim from fix79/index.html, including
	# the well/seedshop patch assignments). The drawn arms below stay as
	# missing-art fallback only; undead variants keep routing through
	# BUILDING_ART_FACTION above (inn/hotel -> bld_tavern_undead,
	# bathhouse -> bld_office_undead, war_hut/cannon_foundry/
	# vehicle_depot/armory -> bld_barracks_undead).
	"inn": "bld_inn.png",
	"hotel": "bld_shop.png",
	"bathhouse": "bld_civic.png",
	"war_hut": "bld_barracks.png",
	"cannon_foundry": "bld_barracks.png",
	"vehicle_depot": "bld_barracks.png",
	"armory": "bld_barracks.png",
	"aa_tower": "bld_tower.png",
	"nuke_silo": "bld_tower.png",
	"anti_nuke": "bld_anti_nuke.png",
	# Building-art fix 2026-10-06: 'air_defense' is the legacy alias of
	# aa_tower (artillery.gd treats btype == "aa_tower" or "air_defense"
	# identically, and fix79 draws it in the exact same drawBuilding
	# branch). It fell through to the generic box+roof arm; it now takes
	# the same bld_tower sprite as aa_tower (fix79 BLD_SPRITE_FOR verbatim).
	"air_defense": "bld_tower.png",
	"well": "bld_shop.png",
	"seedshop": "bld_shop.png",
	# Launch-readiness 2026-10-06: the ten SimFoodPerks perk eateries fell
	# back to the drawn _eatery arm; the port ships genuine per-race
	# C61/C70 pixel-art restaurant sprites (one per race, giant rooftop
	# product statue baked in), so each perk eatery gets its race's art.
	"greasy_spoon": "eat_cheese_shop.png",
	"salad_bar": "eat_cheese_shop.png",
	"ogre_sausage_shop": "eat_turkey_shop.png",
	"meat_tornado": "eat_turkey_shop.png",
	"moonberry_lounge": "eat_acorn_shop.png",
	"dewdrop_diner": "eat_acorn_shop.png",
	"bastard_drivethru": "eat_taco_shop.png",
	"fungus_hut": "eat_taco_shop.png",
	"crypt_kitchen": "eat_soul_cafe.png",
	"grave_snacks": "eat_soul_cafe.png",
}


## Faction-specific art variants: btype -> {faction -> file}.
const BUILDING_ART_FACTION := {
	"guild_hall": {
		"humans": "bld_guild_hall_human.png",
		"ogres": "bld_guild_hall_ogre.png",
		"elves": "bld_guild_hall_elf.png",
		"gnomes": "bld_guild_hall_gnome.png",
		"undead": "bld_guild_undead.png",
	},
	# Graphics-hourly 2026-10-04: fix79's bldHouseUndead68() swaps
	# bld_shop -> bld_shop_undead for the undead race (storage,
	# trade_outpost, z_shop, and all five stock_* types). Wake 14:19 pass:
	# the same clause also covers plain 'shop' — mapped below (bld_shop.png
	# has no undead-living fallback need; living shops keep the drawn
	# _shop arm).
	# 2026-10-04 later pass: fix79's bldStoreSprite57 renders storage as the
	# faction's storefront sprite (bld_general_store_{race}, bld_shop as
	# fallback) — the undead override stays bld_shop_undead because
	# bldHouseUndead68 runs AFTER bldStoreSprite57 in the draw path.
	"storage": {
		"gnomes": "bld_general_store_gnome.png",
		"ogres": "bld_general_store_ogre.png",
		"elves": "bld_general_store_elf.png",
		"humans": "bld_general_store_human.png",
		"undead": "bld_shop_undead.png",
	},
	# Jeremy 2026-10-04: tool/shop petition chain — the general store uses
	# the faction storefront sprites (undead keep bld_shop_undead).
	"general_store": {
		"gnomes": "bld_general_store_gnome.png",
		"ogres": "bld_general_store_ogre.png",
		"elves": "bld_general_store_elf.png",
		"humans": "bld_general_store_human.png",
		"undead": "bld_shop_undead.png",
	},
	# Graphics-hourly 2026-10-04: bldHouseUndead68 verbatim — undead
	# trade_outpost shops use bld_shop_undead.
	"shop": {"undead": "bld_shop_undead.png"},
	"trade_outpost": {"undead": "bld_shop_undead.png"},
	"stock_gold": {"undead": "bld_shop_undead.png"},
	"stock_wood": {"undead": "bld_shop_undead.png"},
	"stock_food": {"undead": "bld_shop_undead.png"},
	"stock_oil": {"undead": "bld_shop_undead.png"},
	"stock_seeds": {"undead": "bld_shop_undead.png"},
	# Wake routine 2026-10-04: fix79's bldHouseUndead68() reroutes the
	# civic offices to bld_office_undead for the undead race
	# (gov_office, gov_treasury, gov_war_office, gov_justice,
	# tome_library, clinic) — art already extracted to assets.
	"gov_office": {"undead": "bld_office_undead.png"},
	"gov_treasury": {"undead": "bld_office_undead.png"},
	"gov_war_office": {"undead": "bld_office_undead.png"},
	"gov_justice": {"undead": "bld_office_undead.png"},
	"tome_library": {"undead": "bld_office_undead.png"},
	"clinic": {"undead": "bld_office_undead.png"},
	# Wake routine 2026-10-04: the SAME bldHouseUndead68 clause also
	# reroutes undead bathhouse -> bld_office_undead (verbatim) — parked
	# from the 13:05 pass because the drawn _bathhouse arm is shared with
	# hotel/inn. Per-type mapping is safe: hotel/inn route to
	# bld_tavern_undead instead (mapped separately below) and are NOT
	# included here; living races keep the drawn _bathhouse arm (the HTML
	# has no bld_bathhouse sprite for them). The drawn arm stays as
	# missing-art fallback only.
	"bathhouse": {"undead": "bld_office_undead.png"},
	# Wake routine 2026-10-04: fix79's bldHouseUndead68() routes undead
	# tavern/inn/hotel -> bld_tavern_undead (verbatim, the same C70 clause
	# as the shops and civic offices). The port has no 'tavern' btype, so
	# hotel + inn take the mapping here. Art already extracted to assets.
	# Living races keep the drawn _bathhouse arm (hotel/inn share that
	# HTML branch; the HTML has no living tavern sprite).
	"hotel": {"undead": "bld_tavern_undead.png"},
	"inn": {"undead": "bld_tavern_undead.png"},
	# Graphics-hourly 2026-10-04: fix79's bldHouseUndead68() routes undead
	# house/z_house -> bld_house_undead (verbatim). The port has no z_house
	# sim type, so only "house" takes the mapping; living races keep
	# bld_house.png (base art). Size unchanged (30.0); no HTML size
	# evidence for a distinct undead footprint, so none invented.
	"house": {"undead": "bld_house_undead.png"},
	# Graphics-hourly 2026-10-04: fix79's bldHouseUndead68() routes the
	# whole undead military family (barracks, war_hut, cannon_foundry,
	# z_garrison, z_factory, vehicle_depot, armory) -> bld_barracks_undead
	# (verbatim). The port has no z_garrison/z_factory sim types, so only
	# the five real ones take the mapping. Living races are untouched:
	# barracks keeps bld_barracks.png; war_hut/cannon_foundry/armory/
	# vehicle_depot keep their drawn programmer-art arms (the HTML has no
	# source sprites for them either). The drawn arms stay as missing-art
	# fallback only. Sizes unchanged (no HTML evidence for distinct
	# undead footprints).
	"barracks": {"undead": "bld_barracks_undead.png"},
	"war_hut": {"undead": "bld_barracks_undead.png"},
	"cannon_foundry": {"undead": "bld_barracks_undead.png"},
	"armory": {"undead": "bld_barracks_undead.png"},
	"vehicle_depot": {"undead": "bld_barracks_undead.png"},
	# Graphics-hourly 2026-10-04: fix79's C61 faction eatery art (Jeremy
	# 2026-09-28: true 2:1 isometric pixel-art restaurants, one per race,
	# giant rooftop product statue baked into the art, verified genuine
	# alpha) — the HTML restaurant branch draws EATERY_IMG[this.race]
	# (taco/turkey/acorn/cheese/soul-cafe per race). soul_cafe keeps the
	# C61 Soul Cafe eatery art for every race (C70); it is undead-locked
	# in the sim, but the mapping is total so no faction ever falls back
	# to the generic box+roof arm.
	"restaurant": {
		"gnomes": "eat_taco_shop.png",
		"ogres": "eat_turkey_shop.png",
		"elves": "eat_acorn_shop.png",
		"humans": "eat_cheese_shop.png",
		"undead": "eat_soul_cafe.png",
	},
	"soul_cafe": {
		"gnomes": "eat_soul_cafe.png",
		"ogres": "eat_soul_cafe.png",
		"elves": "eat_soul_cafe.png",
		"humans": "eat_soul_cafe.png",
		"undead": "eat_soul_cafe.png",
	},
	# Wake routine 2026-10-04: fix79's bldMageSpireSprite64() routes
	# mage_spire to the per-race pixel art (bld_mage_spire_{race}).
	# Undead has no per-race key in the HTML, so it keeps the
	# bld_tower fallback from BUILDING_ART above (verbatim).
	"mage_spire": {
		"humans": "bld_mage_spire_human.png",
		"ogres": "bld_mage_spire_ogre.png",
		"elves": "bld_mage_spire_elf.png",
		"gnomes": "bld_mage_spire_gnome.png",
	},
	# Wake routine 2026-10-04: fix79's bldGuardHouseSprite61() routes
	# guard_house to the per-race pixel art (bld_guard_house_{race}).
	# The HTML's fallback key 'bld_guard_house' has no art, so the
	# undead keep the drawn _guard_house arm (no base entry, null path).
	"guard_house": {
		"humans": "bld_guard_house_human.png",
		"ogres": "bld_guard_house_ogre.png",
		"elves": "bld_guard_house_elf.png",
		"gnomes": "bld_guard_house_gnome.png",
	},
}


static func building_texture(btype: String) -> Texture2D:
	if btype == "wall" or btype == "gate":
		return _tex(WALL_DIR + String(BUILDING_ART[btype]))
	if BUILDING_ART.has(btype):
		return _tex(BUILDING_DIR + String(BUILDING_ART[btype]))
	return null


## Faction-aware variant: picks faction-specific art when the type has it,
## otherwise falls back to building_texture().
static func building_texture_for(btype: String, faction: String) -> Texture2D:
	if BUILDING_ART_FACTION.has(btype):
		var variants: Dictionary = BUILDING_ART_FACTION[btype]
		var f: String = String(variants.get(faction, ""))
		if f != "":
			return _tex(BUILDING_DIR + f)
	return building_texture(btype)


## Tree prop texture (oak/pine alternate deterministically by position).
static func tree_texture(pos: Vector2) -> Texture2D:
	var pick: int = absi(hash("%d,%d" % [int(pos.x), int(pos.y)])) % 2
	return _tex(TREE_DIR + ("oak_tree.png" if pick == 0 else "pine_tree.png"))


## Resource node icon by key ("wood"|"oil"|"gold"), or null if missing.
## Used by MapProp so resource nodes show the real pixel-art icons
## (log / oil drop / gold coin) instead of the old flat diamonds.
static func resource_icon(kind: String) -> Texture2D:
	return _tex(ICON_DIR + "icon_" + kind + ".png")


## Resource node deposit sprite by key ("wood"|"oil"|"gold"), or null if
## missing. Jeremy 2026-10-04: map nodes show rich mineable deposit sprites
## (gold veins sparkling, oil pool glossy, stacked log pile) instead of the
## plain HUD icons — proper finished art, no placeholder.
static func resource_node_texture(kind: String) -> Texture2D:
	return _tex(NODES_DIR + "deposit_" + kind + ".png")


## Milestone 7: animal texture by key (e.g. "moose", "lizard").
static func animal_texture(key: String) -> Texture2D:
	return _tex(ANIMAL_DIR + key + ".png")


## Jeremy 2026-10-04: hand-tool sprite ("axe"|"pickaxe"|"hammer") for the
## work-animation tool overlay. Returns null if the art is missing (the
## node hides the overlay rather than crashing).
static func tool_texture(kind: String) -> Texture2D:
	return _tex(TOOL_DIR + "tool_" + kind + ".png")


## Milestone 7: vehicle texture by key (e.g. "veh_fire_truck").
static func vehicle_texture(key: String) -> Texture2D:
	return _tex(VEHICLE_DIR + key + ".png")


## Seven Monasteries (Jeremy 2026-10-04): pixel-art sprite per benevolent god.
static func monastery_texture(god_id: String) -> Texture2D:
	return _tex(GODS_DIR + "monastery_" + god_id + ".png")


## Seven Dark Crystals (Jeremy 2026-10-04): pixel-art sprite per rogue god.
static func crystal_texture(god_id: String) -> Texture2D:
	return _tex(GODS_DIR + "crystal_" + god_id + ".png")
