class_name SimFoodPerks
extends RefCounted

## Cursing Gnomes — restaurant perk/dish system.
##
## Each race has specialty restaurants (beyond their default eatery) whose
## signature dishes grant temporary gameplay perks when eaten — not just
## hunger restoration. Perks are timed buffs stored on the unit dict as
## plain data (JSON-safe for save/load):
##
##   unit["food_perks"] = [
##     {"id": "bastard_rush", "expires": 12345.6, "source": "Bastard Burrito"},
##   ]
##
## Expiry is lazy: get_modifier() and active_perks() prune expired entries
## when queried, so there's no per-frame tick over all units. Modifiers
## queried: "speed", "work", "strength". Side effects (food poisoning etc.)
## are applied as separate perks with their own behavior.
##
## Duration is in game_time seconds (Config.DAY_LENGTH_SECONDS = 1 day).

## Perk definitions: id -> {name, desc, duration_days, effects}.
## Effects keys: speed_mult, work_mult, str_mult, mood_boost (instant),
##   energy_boost (instant), max_hp_mult, heal_per_sec, poison_dps.
const PERK_DEFS := {
	# --- Human ---
	"greasy_grind": {
		"name": "Greasy Grind",
		"desc": "Heart Attack Platter: work 30% faster, move 15% slower.",
		"duration_days": 1.0,
		"effects": {"work_mult": 1.3, "speed_mult": 0.85},
	},
	"rabbit_food_rush": {
		"name": "Rabbit Food Rush",
		"desc": "Kale Smoothie: move 15% faster, feel smug.",
		"duration_days": 1.0,
		"effects": {"speed_mult": 1.15, "mood_boost": 10.0},
	},
	# --- Ogre ---
	"sausage_strength": {
		"name": "Sausage Strength",
		"desc": "Ogre Sausage Link: hit 40% harder.",
		"duration_days": 1.0,
		"effects": {"str_mult": 1.4},
	},
	"meat_sweats": {
		"name": "Meat Sweats",
		"desc": "Mystery Meat Skewer: +20% max HP, slow heal.",
		"duration_days": 1.0,
		"effects": {"max_hp_mult": 1.2, "heal_per_sec": 0.5},
	},
	# --- Elf ---
	"moonberry_bliss": {
		"name": "Moonberry Bliss",
		"desc": "Moonberry Tart: +30 mood, chats flow easier.",
		"duration_days": 1.0,
		"effects": {"mood_boost": 30.0, "work_mult": 1.1},
	},
	"dew_awakened": {
		"name": "Dew Awakened",
		"desc": "Morning Dew Tea: fully rested, work 20% faster.",
		"duration_days": 1.0,
		"effects": {"energy_boost": 40.0, "work_mult": 1.2},
	},
	# --- Gnome ---
	"bastard_rush": {
		"name": "Bastard Rush",
		"desc": "Bastard Burrito: move 35% faster. Hold on tight.",
		"duration_days": 1.0,
		"effects": {"speed_mult": 1.35},
	},
	"glowcap_trip": {
		"name": "Glowcap Trip",
		"desc": "Glowcap Stew: +20 mood, work 10% slower (whoa, colors).",
		"duration_days": 1.0,
		"effects": {"mood_boost": 20.0, "work_mult": 0.9},
	},
	# --- Undead ---
	"essence_surcharge": {
		"name": "Essence Surcharge",
		"desc": "Essence Soup: work 25% faster, never tire.",
		"duration_days": 1.0,
		"effects": {"work_mult": 1.25, "energy_boost": 30.0},
	},
	"finger_food_frenzy": {
		"name": "Finger Food Frenzy",
		"desc": "Finger Sandwiches: hit 30% harder. (They're fingers.)",
		"duration_days": 1.0,
		"effects": {"str_mult": 1.3},
	},
	# --- Side effects (negative) ---
	"food_poisoning": {
		"name": "Food Poisoning",
		"desc": "Something was off about that meal. Stomach churns.",
		"duration_days": 0.5,
		"effects": {"poison_dps": 2.0, "speed_mult": 0.9},
	},
	"horrified": {
		"name": "Horrified",
		"desc": "Those were REAL fingers. -20 mood.",
		"duration_days": 0.5,
		"effects": {"mood_boost": -20.0},
	},
}

## Dish served per perk-restaurant building type.
## btype -> {dish_id, dish_name, perk_id, poison_chance, horror_for_living}
const PERK_DISHES := {
	# Humans
	"greasy_spoon": {
		"dish_id": "heart_attack_platter", "dish_name": "Heart Attack Platter",
		"perk_id": "greasy_grind", "poison_chance": 0.0,
	},
	"salad_bar": {
		"dish_id": "kale_smoothie", "dish_name": "Kale Smoothie",
		"perk_id": "rabbit_food_rush", "poison_chance": 0.0,
	},
	# Ogres
	"ogre_sausage_shop": {
		"dish_id": "ogre_sausage_link", "dish_name": "Ogre Sausage Link",
		"perk_id": "sausage_strength", "poison_chance": 0.25,
	},
	"meat_tornado": {
		"dish_id": "mystery_skewer", "dish_name": "Mystery Meat Skewer",
		"perk_id": "meat_sweats", "poison_chance": 0.15,
	},
	# Elves
	"moonberry_lounge": {
		"dish_id": "moonberry_tart", "dish_name": "Moonberry Tart",
		"perk_id": "moonberry_bliss", "poison_chance": 0.0,
	},
	"dewdrop_diner": {
		"dish_id": "dew_tea", "dish_name": "Morning Dew Tea",
		"perk_id": "dew_awakened", "poison_chance": 0.0,
	},
	# Gnomes
	"bastard_drivethru": {
		"dish_id": "bastard_burrito", "dish_name": "Bastard Burrito",
		"perk_id": "bastard_rush", "poison_chance": 0.30,
	},
	"fungus_hut": {
		"dish_id": "glowcap_stew", "dish_name": "Glowcap Stew",
		"perk_id": "glowcap_trip", "poison_chance": 0.10,
	},
	# Undead
	"crypt_kitchen": {
		"dish_id": "essence_soup", "dish_name": "Essence Soup",
		"perk_id": "essence_surcharge", "poison_chance": 0.0,
	},
	"grave_snacks": {
		"dish_id": "finger_sandwiches", "dish_name": "Finger Sandwiches",
		"perk_id": "finger_food_frenzy", "poison_chance": 0.0,
		"horror_for_living": true,
	},
}

## All perk-restaurant building types (for urge building lists).
const PERK_RESTAURANT_TYPES: Array[String] = [
	"greasy_spoon", "salad_bar",
	"ogre_sausage_shop", "meat_tornado",
	"moonberry_lounge", "dewdrop_diner",
	"bastard_drivethru", "fungus_hut",
	"crypt_kitchen", "grave_snacks",
]


## True when this building type serves a perk dish.
static func is_perk_restaurant(btype: String) -> bool:
	return PERK_DISHES.has(btype)


## Dish info dict for a perk-restaurant type, or {}.
static func dish_for(btype: String) -> Dictionary:
	return (PERK_DISHES.get(btype, {}) as Dictionary).duplicate()


## Apply a restaurant's dish perks to a unit. Called when hunger is
## satisfied inside a perk restaurant. game_time is GameState.game_time.
## Uses the unit's own RNG via randf() — callers in sim context are fine.
static func apply_dish(unit: Dictionary, btype: String, game_time: float) -> void:
	var dish: Dictionary = PERK_DISHES.get(btype, {})
	if dish.is_empty():
		return
	var day_len: float = Config.DAY_LENGTH_SECONDS
	var perk_id: String = String(dish.get("perk_id", ""))
	if perk_id != "" and PERK_DEFS.has(perk_id):
		_apply_perk(unit, perk_id, String(dish.get("dish_name", "")), game_time, day_len)
	# Food poisoning gamble.
	var pchance: float = float(dish.get("poison_chance", 0.0))
	if pchance > 0.0 and randf() < pchance:
		_apply_perk(unit, "food_poisoning", String(dish.get("dish_name", "")), game_time, day_len)
	# Finger sandwiches horrify the living.
	if bool(dish.get("horror_for_living", false)) \
			and String(unit.get("faction", "")) != "undead":
		_apply_perk(unit, "horrified", String(dish.get("dish_name", "")), game_time, day_len)


## Add (or refresh) a perk on the unit. Instant effects (mood_boost,
## energy_boost) apply immediately; multipliers persist until expiry.
static func _apply_perk(unit: Dictionary, perk_id: String, source: String,
		game_time: float, day_len: float) -> void:
	var def: Dictionary = PERK_DEFS.get(perk_id, {})
	if def.is_empty():
		return
	var duration: float = float(def.get("duration_days", 1.0)) * day_len
	var perks: Array = unit.get("food_perks", [])
	# Refresh existing instead of stacking duplicates.
	for p in perks:
		if p is Dictionary and String(p.get("id", "")) == perk_id:
			p["expires"] = game_time + duration
			p["source"] = source
			_apply_instant(unit, def)
			unit["food_perks"] = perks
			return
	perks.append({
		"id": perk_id,
		"expires": game_time + duration,
		"source": source,
	})
	unit["food_perks"] = perks
	_apply_instant(unit, def)


## Instant one-shot effects (mood/energy) apply on eat, not over time.
static func _apply_instant(unit: Dictionary, def: Dictionary) -> void:
	var fx: Dictionary = def.get("effects", {})
	if fx.has("mood_boost"):
		var urges: Dictionary = unit.get("urges", {})
		urges["mood"] = clampf(float(urges.get("mood", 60.0)) + float(fx["mood_boost"]), 0.0, 100.0)
		unit["urges"] = urges
	if fx.has("energy_boost"):
		var urges2: Dictionary = unit.get("urges", {})
		urges2["energy"] = clampf(float(urges2.get("energy", 60.0)) + float(fx["energy_boost"]), 0.0, 100.0)
		unit["urges"] = urges2


## Prune expired perks. Returns the live perk array (may be empty).
## Called lazily by getters — no per-frame tick needed.
static func prune(unit: Dictionary, game_time: float) -> Array:
	if not unit.has("food_perks"):
		return []
	var perks: Array = unit.get("food_perks", [])
	var live: Array = []
	for p in perks:
		if p is Dictionary and float(p.get("expires", 0.0)) > game_time:
			live.append(p)
	if live.is_empty():
		unit.erase("food_perks")
	else:
		unit["food_perks"] = live
	return live


## Combined multiplier for "speed" | "work" | "strength".
## Multiplicative stacking across active perks.
static func get_modifier(unit: Dictionary, mod: String, game_time: float) -> float:
	# Perf R36: units with no perks skip the match + prune + empty loop.
	# Bit-identical: prune() is a no-op returning [] when the key is
	# absent, so the old path also returned 1.0 with zero side effects.
	if not unit.has("food_perks"):
		return 1.0
	var key := ""
	match mod:
		"speed":
			key = "speed_mult"
		"work":
			key = "work_mult"
		"strength":
			key = "str_mult"
		_:
			return 1.0
	var mult := 1.0
	for p in prune(unit, game_time):
		var def: Dictionary = PERK_DEFS.get(String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		if fx.has(key):
			mult *= float(fx[key])
	return mult


## Max-HP multiplier (for temp HP buffs like Meat Sweats).
static func get_max_hp_mult(unit: Dictionary, game_time: float) -> float:
	# Perf R36: no-perk early-out (bit-identical — see get_modifier).
	if not unit.has("food_perks"):
		return 1.0
	var mult := 1.0
	for p in prune(unit, game_time):
		var def: Dictionary = PERK_DEFS.get(String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		if fx.has("max_hp_mult"):
			mult *= float(fx["max_hp_mult"])
	return mult


## Per-second heal from active perks (Meat Sweats).
static func get_heal_per_sec(unit: Dictionary, game_time: float) -> float:
	# Perf R36: no-perk early-out (bit-identical — see get_modifier).
	if not unit.has("food_perks"):
		return 0.0
	var hps := 0.0
	for p in prune(unit, game_time):
		var def: Dictionary = PERK_DEFS.get(String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		hps += float(fx.get("heal_per_sec", 0.0))
	return hps


## Per-second damage from active perks (Food Poisoning).
static func get_poison_dps(unit: Dictionary, game_time: float) -> float:
	# Perf R36: no-perk early-out (bit-identical — see get_modifier).
	if not unit.has("food_perks"):
		return 0.0
	var dps := 0.0
	for p in prune(unit, game_time):
		var def: Dictionary = PERK_DEFS.get(String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		dps += float(fx.get("poison_dps", 0.0))
	return dps


## Active perk display infos for UI: [{name, desc, secs_left}].
static func active_perks(unit: Dictionary, game_time: float) -> Array:
	var out: Array = []
	for p in prune(unit, game_time):
		var def: Dictionary = PERK_DEFS.get(String(p.get("id", "")), {})
		if def.is_empty():
			continue
		out.append({
			"name": String(def.get("name", "")),
			"desc": String(def.get("desc", "")),
			"source": String(p.get("source", "")),
			"secs_left": maxf(0.0, float(p.get("expires", 0.0)) - game_time),
		})
	return out


## Human-readable time-left string (no emoji; plain text).
static func format_time_left(secs: float) -> String:
	if secs >= 3600.0:
		return "%.1fh left" % (secs / 3600.0)
	if secs >= 60.0:
		return "%dm left" % int(secs / 60.0)
	return "%ds left" % int(secs)
