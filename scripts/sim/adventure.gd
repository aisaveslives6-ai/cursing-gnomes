class_name SimAdventure
extends RefCounted
## Cursing Gnomes — adventure mode (RuneScape-style hero RPG layer).
##
## Design ported from the HTML build (not its code). The living world keeps
## simulating (towns, factions, disasters); the player instead leads a single
## hero unit: click-to-move, tap-to-attack, quests, dungeons, gear, levels.
##
## Systems:
##   - Hero RPG layer: level, XP, str/agi/vit/intel, mana, gear slots
##     (weapon/armor/trinket), bag, deeds (adventure log), reputation,
##     wanted heat per faction.
##   - Quest board: 6 story quests (bounty / rescue / escort / fetch /
##     clear-dungeon) from named givers, plus a finale quest.
##   - Dungeons: 3 wild sites (Whispering Cave, Sunken Ruins, Gnawer Den)
##     with level-scaled bandit denizens + lootable chests (dungeon-forged
##     gear), and a 4th Stronghold for the finale.
##   - Heroic Strike ability (30 mana, 12 s cooldown, next hit x2.5).
##   - Crime & wanted: killing non-hostiles in front of witnesses marks the
##     hero wanted by that faction (heat decays).
##   - Death: 8 s respawn at the home hall, -10% gold, 50% HP.
##   - WIN: slay the Bandit King (finale quest). LOSE: fall 5 times.
##   - Quest failure loop (no dead ends): a dead captive/pilgrim fails its
##     quest out loud (deed + toast + giver rep hit) and the board re-offers
##     it; the Bandit King dying by any hand still wins the campaign; kill
##     quests always have living targets (fresh crews ride in); fetch items
##     re-stock their chest on accept.
##
## The world owns one SimAdventure (world.adventure). Combat hooks in via
## two duck-typed links (mirroring the SimMind pattern):
##   combat.adventure = adventure   -> hero damage mitigation
##   adventure.combat = combat       -> hero melee damage application
## Pure logic — no rendering, no input, no audio. Dialogue lines are
## 100% offline/scripted (emitted through bus signals for the HUD).


## Gear catalogue: id -> {slot, name, atk/armor/agi/intel/vit/mana/xp_mul,
## cost (0 = dungeon-only), desc}.
const GEAR := {
	"rusty_sword":    {"slot": "weapon",  "name": "Rusty Sword",     "atk": 4,  "cost": 60.0,  "desc": "Better than fists."},
	"iron_sword":     {"slot": "weapon",  "name": "Iron Sword",      "atk": 9,  "cost": 180.0, "desc": "A soldier's blade."},
	"oak_bow":        {"slot": "weapon",  "name": "Oak Bow",         "atk": 7,  "agi": 2, "cost": 150.0, "desc": "For keen eyes."},
	"rune_staff":     {"slot": "weapon",  "name": "Rune Staff",      "atk": 6,  "intel": 4, "cost": 220.0, "desc": "Hums with old words."},
	"war_hammer":     {"slot": "weapon",  "name": "War Hammer",      "atk": 14, "cost": 420.0, "desc": "Doors hate it."},
	"dragonfang":     {"slot": "weapon",  "name": "Dragonfang Blade","atk": 22, "str": 3, "cost": 0.0, "desc": "Dungeon-forged. Warm to the touch."},
	"hide_armor":     {"slot": "armor",   "name": "Hide Armor",      "armor": 6,  "cost": 120.0, "desc": "Smells like adventure."},
	"chainmail":      {"slot": "armor",   "name": "Chainmail",       "armor": 12, "cost": 320.0, "desc": "Rings of \"nope\"."},
	"dragonscale":    {"slot": "armor",   "name": "Dragonscale Mail","armor": 20, "vit": 3, "cost": 0.0, "desc": "Dungeon-forged. Barely dents."},
	"lucky_charm":    {"slot": "trinket", "name": "Lucky Charm",     "xp_mul": 1.15, "cost": 200.0, "desc": "+15% XP. Probably magic."},
	"mana_crystal":   {"slot": "trinket", "name": "Mana Crystal",    "mana": 40, "cost": 260.0, "desc": "+40 max mana."},
	"berserker_totem":{"slot": "trinket", "name": "Berserker Totem", "atk": 6,  "cost": 0.0, "desc": "Dungeon-forged. It growls."},
}

## Hall building types the adventure layer recognizes. "hall" is the HTML's
## name for the town center (buildings.gd alias of "town_hall"); the AI
## director and world already match both.
const HALL_TYPES: Array[String] = ["town_hall", "hall"]

## Quest definitions. obj.kind: kill | clear_dungeon | rescue | escort | fetch | boss.
## giver: role key; intro/accept/done are scripted story dialogue.
const QUEST_DEFS := [
	{"id": "q_bounty1", "type": "bounty", "giver": "commander",
		"title": "Bandits in the Wilds",
		"desc": "Bandits are raiding our trade routes. Drive off 4 of them.",
		"intro": "Our caravans bleed gold on the wild roads. Four bandit scalps, hero — that's the price of safe passage.",
		"accept": "The wilds won't know what hit them.",
		"done": "The roads breathe again. You're worth every coin.",
		"obj": {"kind": "kill", "race": "bandit", "n": 4, "count": 0},
		"reward": {"xp": 250, "gold": 300.0, "gear": "iron_sword"}},
	{"id": "q_bounty2", "type": "bounty", "giver": "commander",
		"title": "The Old Threat",
		"desc": "Monsters lurk beyond our walls. Slay 2 of them.",
		"intro": "Something with too many teeth nests in the wilds. Put it down before it puts US down.",
		"accept": "Big teeth. Bigger sword.",
		"done": "The wilds fear YOUR name now.",
		"obj": {"kind": "kill", "race": "monster", "n": 2, "count": 0},
		"reward": {"xp": 400, "gold": 450.0, "gear": "chainmail"}},
	{"id": "q_rescue1", "type": "rescue", "giver": "mayor",
		"title": "Taken in the Night",
		"desc": "A townsfolk was dragged off by bandits! Find their camp and bring them home alive.",
		"intro": "They took one of ours in the night — dragged off to a bandit camp! Bring them home breathing, I beg you.",
		"accept": "Hold on — I'm coming!",
		"done": "You brought them home. This town won't forget it.",
		"obj": {"kind": "rescue"},
		"reward": {"xp": 350, "gold": 400.0, "gear": "hide_armor"}},
	{"id": "q_escort1", "type": "escort", "giver": "lord",
		"title": "The Pilgrim's Road",
		"desc": "A traveler wishes to reach the old shrine in the wilds. Keep them alive on the journey.",
		"intro": "A pilgrim seeks the old shrine, and the roads are teeth. Walk beside them. Come back with them.",
		"accept": "No harm will touch them while I stand.",
		"done": "The pilgrim kneels at the shrine, safe. The gods mark your kindness.",
		"obj": {"kind": "escort"},
		"reward": {"xp": 300, "gold": 350.0, "gear": "oak_bow"}},
	{"id": "q_fetch1", "type": "fetch", "giver": "mayor",
		"title": "The Stolen Relic",
		"desc": "Bandits took the mayor's heirloom into the wilds. Search a dungeon chest and bring it back.",
		"intro": "My grandmother's heirloom — in a bandit's chest! Search the dungeon caches. I'll pay in more than thanks.",
		"accept": "I'll turn every chest in the wilds inside out.",
		"done": "The heirloom gleams again. (The mayor is crying. Happy tears. Mostly.)",
		"obj": {"kind": "fetch", "item": "Mayor's Heirloom"},
		"reward": {"xp": 300, "gold": 380.0, "gear": "mana_crystal"}},
	{"id": "q_dungeon1", "type": "clear", "giver": "lord",
		"title": "Clear the Whispering Cave",
		"desc": "The lord wants the bandit camp at Whispering Cave destroyed.",
		"intro": "Whispering Cave festers with cutthroats. Burn them out, root and branch, and my coffers open to you.",
		"accept": "Consider it silenced.",
		"done": "Whispering Cave is silent. The lord raises a cup to you.",
		"obj": {"kind": "clear_dungeon", "dg_id": "dg0", "n": 1, "count": 0},
		"reward": {"xp": 500, "gold": 600.0, "gear": "lucky_charm"}},
	{"id": "q_bounty3", "type": "bounty", "giver": "commander",
		"title": "Wizards Gone Wild",
		"desc": "Rogue wizards are turning our livestock into furniture. Put down 4 of them.",
		"intro": "The wizards have gone feral, hero — they turned my prize goat into an ottoman. An OTTOMAN. Four pelts. Make it stop.",
		"accept": "No more furniture. I swear it.",
		"done": "The goats are goats again. Mostly. One's still a footstool, but he's happy.",
		"obj": {"kind": "kill", "race": "monster", "n": 4, "count": 0},
		"reward": {"xp": 650, "gold": 700.0, "gear": "rune_staff"}},
	{"id": "q_dungeon2", "type": "clear", "giver": "lord",
		"title": "Drain the Sunken Ruins",
		"desc": "The lord wants the bandit camp at Sunken Ruins scoured.",
		"intro": "The Sunken Ruins squat in the marsh, fat with stolen grain. Drown their little kingdom, hero.",
		"accept": "Consider them evicted.",
		"done": "The Ruins are quiet. The lord sends his regards and his gold.",
		"obj": {"kind": "clear_dungeon", "dg_id": "dg1", "n": 1, "count": 0},
		"reward": {"xp": 700, "gold": 800.0, "gear": "war_hammer"}},
	{"id": "q_dungeon3", "type": "clear", "giver": "lord",
		"title": "Smoke Out the Gnawer Den",
		"desc": "Burn the bandits out of the Gnawer Den.",
		"intro": "The Gnawer Den reeks of stolen cheese and bad decisions. Smoke them out — every last one.",
		"accept": "I'll bring the matches.",
		"done": "The Den is a chimney now. Lovely draft.",
		"obj": {"kind": "clear_dungeon", "dg_id": "dg2", "n": 1, "count": 0},
		"reward": {"xp": 800, "gold": 900.0, "gear": "dragonscale"}},
	{"id": "q_rescue2", "type": "rescue", "giver": "mayor",
		"title": "Taken Again?! (Seriously?)",
		"desc": "ANOTHER townsfolk was dragged off by bandits. The mayor is furious. And embarrassed.",
		"intro": "They took another one! I JUST got the last one back! The ransom note says 'lol'. Bring them home — and bring me the note-writer's teeth.",
		"accept": "Third time's the charm. For them. Not for me.",
		"done": "Home safe. I've ordered the town a curfew and the bandits a strongly-worded letter.",
		"obj": {"kind": "rescue"},
		"reward": {"xp": 550, "gold": 600.0, "gear": "berserker_totem"}},
	{"id": "q_escort2", "type": "escort", "giver": "lord",
		"title": "The Tax Collector's Road",
		"desc": "The realm's least-loved civil servant must reach the old shrine alive. Nobody else will walk him. That's why it's you.",
		"intro": "Our tax collector seeks the old shrine — to pray, he says. Everyone ELSE prays he doesn't make it. Walk him there breathing. It's the principle.",
		"accept": "Even HE deserves the road.",
		"done": "He made it. The shrine's donation box is heavier and my conscience is clear. Mostly.",
		"obj": {"kind": "escort"},
		"reward": {"xp": 500, "gold": 550.0, "gear": "oak_bow"}},
	{"id": "q_fetch2", "type": "fetch", "giver": "mayor",
		"title": "The Warlord's Lucky Sock",
		"desc": "The mayor's 'warlord' cousin lost his lucky sock in a dungeon. Yes. A sock. Search the dungeon chests.",
		"intro": "My cousin the 'warlord' — conquered three taverns — lost his LUCKY SOCK in a bandit chest. He won't raid without it. Find the sock, hero. Don't ask.",
		"accept": "For the sock. Gods help me, for the sock.",
		"done": "The sock is home. He wept. I pretended not to see.",
		"obj": {"kind": "fetch", "item": "Warlord's Lucky Sock"},
		"reward": {"xp": 500, "gold": 550.0, "gear": "lucky_charm"}},
	{"id": "q_finale", "type": "finale", "giver": "lord",
		"title": "The Bandit King",
		"desc": "The Bandit King gathers the scattered crews at his Stronghold. End him, and end the raids.",
		"intro": "You've broken every crew in the wilds — so they've crowned a KING. He waits in his Stronghold. End this.",
		"accept": "One crown. One grave.",
		"done": "The Bandit King is dead. The wilds are yours, legend.",
		"obj": {"kind": "boss"},
		"reward": {"xp": 1200, "gold": 1500.0, "gear": "dragonfang"}},
]

const DUNGEON_DEFS := [
	{"name": "Whispering Cave", "kind": "cave"},
	{"name": "Sunken Ruins",    "kind": "ruin"},
	{"name": "Gnawer Den",      "kind": "den"},
]
const STRONGHOLD_DEF := {"name": "Bandit King's Stronghold", "kind": "fort"}

const MAX_DEATHS := 5          # 5th fall ends the campaign
const RESPAWN_DELAY := 8.0     # seconds before waking at the hall
const BOARD_REFRESH := 300.0   # quest board refreshes every 5 min
const WANTED_DECAY := 90.0     # heat ticks down every 90 s
const HERO_SPEED := 115.0
const HERO_RANGE := 48.0
const HERO_COOLDOWN := 1.0
const HERO_AGGRO := 420.0
const MAX_BANDITS := 30        # alive bandit-faction units at once

## Faction-unique hero jobs for the character creator (HTML setupCharCreate
## `paths` parity; Godot faction ids). The hero's job defaults to the first
## entry of their faction's list.
const HERO_JOB_PATHS := {
	"humans": ["swordsman", "archer", "knight", "cleric"],
	"ogres": ["clubber", "musketeer", "berserker", "blunderbuss"],
	"gnomes": ["axeman", "mage", "tinker_mech", "saboteur"],
	"elves": ["ranger", "warlock", "treant", "spellweaver"],
	"undead": ["skeleton", "zombie", "ghoul", "necromancer"],
}
## Picker labels (HTML charcreate button labels parity).
const HERO_JOB_NAMES := {
	"swordsman": "Swordsman", "archer": "Archer", "knight": "Knight",
	"cleric": "Cleric", "clubber": "Clubber", "musketeer": "Musketeer",
	"berserker": "Berserker", "blunderbuss": "Blunderbuss",
	"axeman": "Axeman", "mage": "Mage", "tinker_mech": "Tinker Mech",
	"saboteur": "Saboteur", "ranger": "Ranger", "warlock": "Warlock",
	"treant": "Treant", "spellweaver": "Spellweaver",
	"skeleton": "Skeleton", "zombie": "Zombie", "ghoul": "Ghoul",
	"necromancer": "Necromancer",
}
## Hero starting kits — Jeremy 2026-10-03: faction-unique (HTML was
## uniform; he wants each faction to feel different from the start).
## Gear tracked separately in GEAR.
const STARTING_KITS := {
	"humans": {"bread": 3, "ale": 2, "bandage": 2, "iron_sword": 1, "wooden_shield": 1, "pickaxe": 1},
	"ogres": {"meat": 4, "grog": 2, "bandage": 1, "stone_club": 1, "hide_armor": 1, "pickaxe": 1},
	"elves": {"lembas": 3, "wine": 1, "bandage": 2, "elven_bow": 1, "arrows": 20, "poultice": 2},
	"gnomes": {"bread": 2, "ale": 1, "bandage": 2, "wrench": 1, "tinker_kit": 1, "bomb": 2, "pickaxe": 1},
	"undead": {"flesh": 3, "blood_vial": 2, "bandage": 1, "rusty_blade": 1, "bone_charm": 1, "shovel": 1},
}
## Fallback for unknown factions.
const STARTING_INVENTORY := {"bread": 3, "ale": 1, "bandage": 2, "pickaxe": 1, "hatchet": 1}


## Starting kit for a faction (faction-unique per Jeremy 2026-10-03).
static func starting_kit_for(faction: String) -> Dictionary:
	return (STARTING_KITS.get(faction, STARTING_INVENTORY) as Dictionary).duplicate()
## Display names for consumable supplies (HTML shop stock names parity).
const SUPPLY_NAMES := {
	"bread": "Bread", "ale": "Ale", "bandage": "Bandage",
	"pickaxe": "Pickaxe", "hatchet": "Hatchet", "fish": "Fish", "gem": "Gem",
}


## Hero job ids for a faction's character creator (HTML paths table).
## Unknown factions fall back to the human list.
static func hero_jobs_for(faction: String) -> Array[String]:
	var out: Array[String] = []
	for j in HERO_JOB_PATHS.get(faction, HERO_JOB_PATHS["humans"]):
		out.append(String(j))
	return out


## The default hero job for a faction: first in its list (HTML parity).
static func default_hero_job(faction: String) -> String:
	var jobs := hero_jobs_for(faction)
	return jobs[0] if not jobs.is_empty() else "swordsman"


## Primary attribute per job (HTML advOnLevelUp / advHeroAtkBonus parity:
## mage|warlock -> intel, archer|ranger|musketeer -> agi, everything else str).
static func job_primary_attr(job: String) -> String:
	if job == "mage" or job == "warlock":
		return "intel"
	if job == "archer" or job == "ranger" or job == "musketeer":
		return "agi"
	return "str"


var _gs: GameState
## Duck-typed SimCombat (set by the world) for hero damage application.
var combat = null

var active := false
var faction := ""
var hero_id := -1
var hero_name := "Hero"
var hero_job := "swordsman"  # job id from HERO_JOB_PATHS for the hero's faction
var hero_gender := "male"  # "male" | "female" — chosen on the setup screen

var inventory := {}  # consumable supplies: id -> count (HTML playerInventory)

var level := 1
var xp := 0
var attr := {"str": 8, "agi": 8, "vit": 8, "intel": 8}
var attr_pts := 0
var mana := 60.0
var max_mana := 60.0
var base_hp := 180.0

var gear := {"weapon": "", "armor": "", "trinket": ""}
var bag: Array[String] = []

var quests: Array[Dictionary] = []   # quest records (see _new_quest)
var offered: Array[String] = []      # quest def ids on the board
var deeds: Array[String] = []        # adventure log (newest last, cap 60)
var rep := {}                        # key -> {"score": float, "name": String}
var wanted := {}                     # faction -> heat float
var dungeons: Array[Dictionary] = []

var ability_cd := 0.0
var strike_buff_t := 0.0
var respawn_t := 0.0
var deaths := 0
var board_t := 0.0
var want_t := 0.0

var won := false
var lost := false

var _next_quest_num := 1
var _world_size := Vector2(4096, 4096)

## The hero and quest NPCs get the full urge system through this mind, but
## via tick_passive() — urges affect them (debuffs, complaints) without
## ever hijacking player control or quest behavior.
var mind: SimMind


func _init(game_state: GameState) -> void:
	_gs = game_state
	mind = SimMind.new(game_state)


# ------------------------------------------------------------------ lifecycle

## Starts adventure mode: spawns the hero by their faction's hall, seeds
## dungeons + wild beasts, opens the quest board. Returns false when the
## world is too full to place the hero.
func start(p_faction: String, p_hero_name: String, p_hero_job: String,
		world_size: Vector2, p_hero_gender: String = "") -> bool:
	if active:
		return true
	if _gs.units.size() >= 96:
		return false
	faction = p_faction
	hero_name = p_hero_name if p_hero_name != "" else "Hero"
	hero_job = p_hero_job
	hero_gender = p_hero_gender if p_hero_gender != "" else "male"
	_world_size = world_size
	var hall_pos := _home_hall_pos()
	var u := _gs.add_unit({
		"faction": faction,
		"job": hero_job,
		"town_id": -1,  # hero belongs to no town's cap; they're the story
		"position": hall_pos + Vector2(55, 55),
		"alive": true,
		"hp": base_hp,
		"max_hp": base_hp,
		"is_hero": true,
		"hero_job": hero_job,
		"gold": 50.0,  # seed money for the outfitter
		"speed": HERO_SPEED,
		"attack_cd": 0.0,
		"combat_state": "idle",
		"has_move_order": false,
		"move_target": Vector2.ZERO,
		"attack_target": -1,
		"gender": ("m" if p_hero_gender == "male" else "f") \
			if p_hero_gender != "" else ("m" if randi() % 2 == 0 else "f"),
		"name": hero_name,
	})
	hero_id = int(u["id"])
	_gs.bus.unit_spawned.emit(u)
	# Hero starting kit (HTML startAdventureGame parity).
	inventory = STARTING_INVENTORY.duplicate()
	_apply_stats()
	_spawn_dungeons()
	_spawn_beasts()
	_refresh_board()
	_deed("Began adventuring.")
	active = true
	_say(hero_name + " has entered the wilds.")
	return true


func is_hero(u: Dictionary) -> bool:
	return not u.is_empty() and int(u.get("id", -1)) == hero_id


func is_quest_npc(u: Dictionary) -> bool:
	return not u.is_empty() and bool(u.get("_adv_npc", false))


func hero() -> Dictionary:
	return _gs.get_unit(hero_id)


func _home_hall_pos() -> Vector2:
	for b: Dictionary in _gs.buildings:
		# "hall" is the HTML's name for the town center (buildings.gd alias
		# of "town_hall"); ai_director.gd and world.gd already match both.
		# Matching only "town_hall" stranded the hero at map center on
		# "hall"-typed saves and made rescue quests uncompletable.
		if String(b.get("type", "")) in HALL_TYPES \
				and String(b.get("faction", "")) == faction:
			return b.get("position", Vector2.ZERO)
	return _world_size * 0.5


# ------------------------------------------------------------------ master tick

## Called every physics tick by the world. Drives hero upkeep, dungeons,
## quest NPCs, wanted decay, and respawn.
func tick(delta: float) -> void:
	if not active or won or lost:
		return
	var h := hero()
	if h.is_empty():
		return
	# Hero + quest NPCs tick here (not in the world's AI budget) so the
	# hero stays responsive and NPCs tick exactly once per frame.
	tick_hero(h, delta)
	for u: Dictionary in _gs.units:
		if bool(u.get("_adv_npc", false)):
			tick_quest_npc(u, delta)
	if h.get("alive", false):
		mana = minf(max_mana, mana + delta * 6.0)
		ability_cd = maxf(0.0, ability_cd - delta)
		strike_buff_t = maxf(0.0, strike_buff_t - delta)
	_dungeon_tick(h, delta)
	_wanted_tick(delta)
	_respawn_tick(h, delta)
	_beast_upkeep()
	board_t += delta
	if board_t >= BOARD_REFRESH:
		board_t = 0.0
		_refresh_board()


## Hero brain: movement orders, auto-combat, melee attacks. Runs from
## tick() every frame (the world skips standard AI for the hero).
## The hero FEELS urges (hunger, exhaustion...) but the player keeps full
## control -- urges apply debuffs and complaints, never movement overrides.
func tick_hero(u: Dictionary, delta: float) -> void:
	if not active or not u.get("alive", false):
		return
	_tick_hero_urges(u, delta)
	var pos: Vector2 = u.get("position", Vector2.ZERO)
	# Exhausted hero: heavy legs, slow swings. The player decides whether to
	# push through or rest -- the urge never takes the controls.
	var speed := HERO_SPEED * (0.7 if _hero_exhausted(u) else 1.0)
	var cooldown := HERO_COOLDOWN * (1.5 if _hero_exhausted(u) else 1.0)
	# Movement order first.
	if bool(u.get("has_move_order", false)):
		var tgt: Vector2 = u.get("move_target", pos)
		if _walk_to(u, tgt, speed, delta):
			u["has_move_order"] = false
	# Combat.
	u["attack_cd"] = maxf(0.0, float(u.get("attack_cd", 0.0)) - delta)
	var target := _hero_target(u)
	if target.is_empty():
		u["combat_state"] = "idle"
		return
	var tpos: Vector2 = target.get("position", Vector2.ZERO)
	if pos.distance_to(tpos) <= HERO_RANGE:
		u["combat_state"] = "attacking"
		if float(u.get("attack_cd", 0.0)) <= 0.0:
			u["attack_cd"] = cooldown
			var dmg := hero_attack_bonus(12.0)
			var tid: int = int(target.get("id", -1))
			var died := false
			if combat != null:
				died = bool(combat.damage_unit(tid, dmg, faction, hero_id))
			else:
				died = _gs.kill_unit(tid)
			if died:
				_on_hero_kill(target)
	else:
		u["combat_state"] = "chasing"
		u["attack_target"] = int(target.get("id", -1))
		_walk_to(u, tpos, speed, delta)


## True when the hero's energy is critically low (exhaustion debuffs apply).
func _hero_exhausted(u: Dictionary) -> bool:
	return String(u.get("_urge_crit", "")) == "energy"


## Hero urge upkeep (Jeremy 2026-10-04): the full 6-urge system runs for the
## hero through the passive mind tick -- urges decay, hunger auto-eats from
## the faction stores, energy recovers while idle at the 8-in-game-hours bed
## rate. Critical urges complain and debuff, but NEVER take control away:
## no movement overrides, no building entry, no AI hijack.
func _tick_hero_urges(u: Dictionary, delta: float) -> void:
	if mind == null:
		return
	var idle: bool = not bool(u.get("has_move_order", false)) \
		and String(u.get("combat_state", "idle")) == "idle"
	var crit: String = mind.tick_passive(u, delta, idle)
	var last: String = String(u.get("_urge_last_crit", ""))
	u["_urge_crit"] = crit
	# Starving with empty stores: weakened attacks until fed.
	u["_urge_starving"] = crit == "hunger" and not mind.urges.can_eat(u)
	if crit != "" and crit != last:
		match crit:
			# Hunger only stays critical when the stores are empty
			# (auto-eat already failed) -- the hero complains, loudly.
			"hunger":
				_toast("The hero is starving! No food in the stores.")
			"energy":
				_toast("The hero is exhausted... rest or push through.")
			"bladder":
				_toast("The hero really had to go.")
			"hygiene":
				_toast("The hero is filthy.")
	u["_urge_last_crit"] = crit


## Player tap routing helpers (the world resolves the actual taps).
func order_move(world_pos: Vector2) -> void:
	var h := hero()
	if h.is_empty() or not h.get("alive", false):
		return
	h["has_move_order"] = true
	h["move_target"] = world_pos
	h["attack_target"] = -1


func order_attack(unit_id: int) -> void:
	var h := hero()
	if h.is_empty() or not h.get("alive", false):
		return
	h["attack_target"] = unit_id
	h["has_move_order"] = false


## Heroic Strike: next melee hit within 8 s deals x2.5. Returns a message.
func heroic_strike() -> String:
	var h := hero()
	if h.is_empty() or not h.get("alive", false):
		return "The hero is down."
	if ability_cd > 0.0:
		return "Heroic Strike ready in %ds." % int(ceil(ability_cd))
	if mana < 30.0:
		return "Not enough mana (30)."
	mana -= 30.0
	ability_cd = 12.0
	strike_buff_t = 8.0
	_deed("Unleashed Heroic Strike.")
	return "Heroic Strike armed! Next attack deals x2.5 damage."


# ------------------------------------------------------------------ hero stats

## Attack bonus from gear + primary attribute. Strike buff multiplies x2.5.
func hero_attack_bonus(base_dmg: float) -> float:
	var bonus := float(_gear_stat("atk"))
	var s := _attr("str")
	var a := _attr("agi")
	var it := _attr("intel")
	match job_primary_attr(hero_job):
		"intel":
			bonus += float(it - 8) * 2.0
		"agi":
			bonus += float(a - 8) * 1.2
		_:
			bonus += float(s - 8) * 1.5
	var total := base_dmg + bonus
	if strike_buff_t > 0.0:
		total *= 2.5
		strike_buff_t = 0.0
	# Starving with no food in the stores: weakened swings.
	if bool(hero().get("_urge_starving", false)):
		total *= 0.75
	return maxf(1.0, roundf(total))


## Damage mitigation for incoming hits (called from SimCombat.damage_unit
## via the duck-typed adventure hook).
func mitigate_damage(unit_id: int, dmg: float) -> float:
	if unit_id != hero_id:
		return dmg
	var red := float(_gear_stat("armor")) * 0.7 \
		+ float(maxi(0, _attr("vit") - 8)) * 0.8
	return maxf(1.0, roundf(dmg - minf(red, dmg * 0.6)))


func _attr(key: String) -> int:
	return int(attr.get(key, 8)) + _gear_stat(key)


func _gear_stat(stat: String) -> int:
	var n := 0
	for slot in ["weapon", "armor", "trinket"]:
		var gid: String = String(gear.get(slot, ""))
		if gid != "" and GEAR.has(gid):
			n += int((GEAR[gid] as Dictionary).get(stat, 0))
	return n


func _xp_need(lvl: int) -> int:
	return int(round(90.0 * pow(float(maxi(1, lvl)), 1.6)))


func xp_need() -> int:
	return _xp_need(level)


func _apply_stats() -> void:
	var h := hero()
	if h.is_empty():
		return
	var vit := _attr("vit")
	var intel := _attr("intel")
	var new_max := int(round(base_hp + float(maxi(0, vit - 8)) * 14.0 \
		+ float(level - 1) * 18.0))
	var ratio := 1.0
	if float(h.get("max_hp", 0.0)) > 0.0:
		ratio = clampf(float(h.get("hp", 1.0)) / float(h.get("max_hp", 1.0)),
			0.0, 1.0)
	h["max_hp"] = float(new_max)
	h["hp"] = maxf(1.0, float(new_max) * ratio)
	max_mana = float(int(round(60.0 + float(maxi(0, intel - 8)) * 10.0 \
		+ float(_gear_stat("mana")))))
	mana = minf(mana, max_mana)


func gain_xp(n: int) -> void:
	if not active:
		return
	var mult := 1.0
	var trinket: String = String(gear.get("trinket", ""))
	if trinket != "" and GEAR.has(trinket):
		mult = float((GEAR[trinket] as Dictionary).get("xp_mul", 1.0))
	xp += int(round(float(maxi(0, n)) * mult))
	var need := _xp_need(level)
	var guard := 0
	while xp >= need and guard < 50:
		xp -= need
		level += 1
		need = _xp_need(level)
		_on_level_up()
		guard += 1


func _on_level_up() -> void:
	var primary := job_primary_attr(hero_job)
	attr[primary] = int(attr.get(primary, 8)) + 1
	attr["vit"] = int(attr.get("vit", 8)) + 1
	attr_pts += 1
	_apply_stats()
	var h := hero()
	if not h.is_empty():
		h["hp"] = h["max_hp"]  # level-up full heal
	_deed("Reached level %d." % level)
	_gs.bus.adventure_level_up.emit(level)
	_say("Level %d! %s grows stronger." % [level, hero_name])


# ------------------------------------------------------------------ kills & crime

## Called whenever the hero lands a killing blow.
func _on_hero_kill(victim: Dictionary) -> void:
	if victim.is_empty():
		return
	var vfac: String = String(victim.get("faction", ""))
	# XP by victim kind.
	var xp_gain := 10
	if bool(victim.get("_adv_denizen", false)):
		xp_gain = 45 + (int(victim.get("_adv_lvl", 1)) - 1) * 10
		_deed("Defeated %s." % String(victim.get("name", "a bandit")))
	elif vfac == "monster":
		xp_gain = 60
	elif vfac != faction:
		xp_gain = 25
	gain_xp(xp_gain)
	# Quest kill credit.
	for q: Dictionary in quests:
		if String(q.get("state", "")) != "active":
			continue
		var obj: Dictionary = q.get("obj", {})
		if String(obj.get("kind", "")) == "kill" \
				and vfac == String(obj.get("race", "")):
			obj["count"] = int(obj.get("count", 0)) + 1
			if int(obj["count"]) >= int(obj.get("n", 1)):
				complete_quest(String(q["id"]))
			else:
				_toast("%s: %d/%d" % [String(q["title"]),
					int(obj["count"]), int(obj.get("n", 1))])
	# Boss kill wins the campaign.
	if bool(victim.get("_adv_boss", false)):
		for q: Dictionary in quests:
			if String(q.get("def_id", "")) == "q_finale" \
					and String(q.get("state", "")) == "active":
				complete_quest(String(q["id"]))
				_win()
	# Crimes against non-hostiles, witnessed, are remembered.
	if vfac != "bandit" and vfac != "monster" and vfac != faction \
			and _witnessed(victim):
		_crime(victim)


func _witnessed(victim: Dictionary) -> bool:
	var h := hero()
	if h.is_empty():
		return false
	var hp: Vector2 = h.get("position", Vector2.ZERO)
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", -1)) == hero_id:
			continue
		if u.get("faction", "") != victim.get("faction", "") \
				and SimCombat.is_hostile(String(u.get("faction", "")),
					faction):
			continue
		if hp.distance_to(u.get("position", Vector2.ZERO)) < 360.0:
			return true
	return false


func _crime(victim: Dictionary) -> void:
	var vfac: String = String(victim.get("faction", ""))
	wanted[vfac] = 10.0
	bump_rep("npc:%d" % int(victim.get("id", 0)),
		String(victim.get("name", "them")), -20.0,
		"Fell by %s's hand" % hero_name)
	_deed("Crime witnessed: slew %s." % String(victim.get("name", "an innocent")))
	_toast("WITNESSED! The %s will remember %s's face." % [vfac, hero_name])


# ------------------------------------------------------------------ death & respawn

## Called from the world's unit_died bridge (connect bus.unit_died).
func on_unit_died(unit_id: int) -> void:
	if not active or won or lost:
		return
	var u := _gs.get_unit(unit_id)
	if not u.is_empty():
		# Quest NPCs (captive / pilgrim): their death fails the quest out
		# loud — never a silent hang on an "active" quest that can never
		# finish. Freed NPCs (quest done/abandoned) are untagged, so this
		# only fires for live quests.
		if bool(u.get("_adv_npc", false)):
			_fail_quest_for_npc(unit_id, u)
		# The Bandit King dying by ANY hand while the finale is active ends
		# the campaign — the wilds are free even if the hero didn't land
		# the killing blow. (Hero kills go through _on_hero_kill; the
		# active-state check there makes double-firing a no-op.)
		if bool(u.get("_adv_boss", false)):
			_boss_slain_by_other_hand()
		# Kill-quest prey guarantee: if the last living target of an active
		# kill quest dies to anything (disaster, war, beasts), a fresh crew
		# rides in — the quest can never hang for lack of targets.
		_ensure_prey_supply()
	if unit_id != hero_id:
		return
	if respawn_t > 0.0:
		return
	deaths += 1
	respawn_t = RESPAWN_DELAY
	var h := hero()
	var lost_gold := 0.0
	if not h.is_empty():
		lost_gold = floor(float(h.get("gold", 0.0)) * 0.1)
		h["gold"] = float(h.get("gold", 0.0)) - lost_gold
	_deed("Died and returned. Lost %dg." % int(lost_gold))
	_toast("%s has fallen... the world fades..." % hero_name)
	if deaths >= MAX_DEATHS:
		_lose()


## A quest NPC (captive / pilgrim) died while its quest was active: fail
## the quest out loud — deed, toast, giver rep hit — and re-offer the def
## on the board so the player can try again. No silent hang.
func _fail_quest_for_npc(npc_id: int, npc: Dictionary) -> void:
	for q: Dictionary in quests:
		if String(q.get("state", "")) != "active":
			continue
		if int(q.get("npc_id", -1)) != npc_id:
			continue
		var kind := String((q["obj"] as Dictionary).get("kind", ""))
		if kind != "rescue" and kind != "escort":
			continue
		var role := String(q.get("giver_role", ""))
		var gname := String(q.get("giver_name", "the quest giver"))
		var title := String(q.get("title", "quest"))
		var npc_name := String(npc.get("name", "your charge"))
		q["state"] = "done"
		q["failed"] = true
		_free_quest_npc(q)
		_deed("Failed quest: %s — %s died." % [title, npc_name])
		_toast("Quest failed: %s — %s is dead." % [title, npc_name])
		_say("No... I was too late. Forgive me.")
		bump_rep("giver:" + role, gname, -6.0,
			"Failed \"%s\" — %s died" % [title, npc_name])
		_gs.bus.adventure_quest_failed.emit(q)
		_refresh_board()


## The Bandit King died to something other than the hero while the finale
## is active (disaster, rival faction, wild beasts): the campaign is still
## won — the wilds are free. Rewards match the hero-kill path exactly.
func _boss_slain_by_other_hand() -> void:
	for q: Dictionary in quests:
		if String(q.get("def_id", "")) == "q_finale" \
				and String(q.get("state", "")) == "active":
			complete_quest(String(q.get("id")))
			_deed("The Bandit King fell — not by the hero's hand, but the wilds are free regardless.")
			_toast("Word spreads: the Bandit King is dead, slain by another's hand. The campaign is won.")
			_win()
			return


## Kill-quest prey guarantee: every active kill quest must have at least
## one living target of its race somewhere in the world. If the last one
## died, a fresh crew rides in from the wilds.
func _ensure_prey_supply() -> void:
	for q: Dictionary in quests:
		if String(q.get("state", "")) != "active":
			continue
		var obj: Dictionary = q.get("obj", {})
		if String(obj.get("kind", "")) != "kill":
			continue
		var race := String(obj.get("race", ""))
		if race == "":
			continue
		var living := 0
		for u2: Dictionary in _gs.units:
			if u2.get("alive", false) and String(u2.get("faction", "")) == race:
				living += 1
		if living > 0:
			continue
		var spot := _wild_spot(900.0)
		var spawned := 0
		for i in range(3):
			var nu: Dictionary = {}
			if race == "monster":
				nu = _spawn_unit_raw(race, "rogue_wizard",
					spot + Vector2(i * 40.0, 0.0),
					{"_adv_beast": true, "name": "Wild Beast"})
			else:
				nu = _spawn_unit_raw(race, "bandit",
					spot + Vector2(i * 40.0, 0.0),
					{"_adv_denizen": true, "_adv_lvl": 1, "name": "Bandit"})
			if not nu.is_empty():
				spawned += 1
		if spawned == 0:
			# Unit cap: nothing rode in. Stay quiet (no false "more ride in"
			# toast) — the next death tick retries.
			continue
		_toast("More %ss ride in from the wilds..." % race)
		_deed("Fresh %s tracks near %s." % [race, String(q.get("title", "the hunt"))])


func _respawn_tick(h: Dictionary, delta: float) -> void:
	if respawn_t <= 0.0 or h.is_empty():
		return
	if h.get("alive", false):
		respawn_t = 0.0  # revived in the field — no respawn needed
		return
	respawn_t -= delta
	if respawn_t > 0.0:
		return
	var hall := _home_hall_pos()
	h["alive"] = true
	h["hp"] = float(h.get("max_hp", 100.0)) * 0.5
	h["position"] = hall + Vector2(60, 60)
	h["attack_target"] = -1
	h["has_move_order"] = false
	h["combat_state"] = "idle"
	respawn_t = 0.0
	_deed("Woke at the town hall, alive by luck.")
	_toast("%s wakes at the town hall, patched up and poorer." % hero_name)
	_say("Ugh... what hit me? Right. Everything.")


# ------------------------------------------------------------------ quests

func _giver_name(role: String) -> String:
	var fname := faction.capitalize()
	match role:
		"commander":
			return "Commander %s" % fname
		"mayor":
			return "Mayor %s" % fname
		"lord":
			return "Lord %s" % fname
	return role.capitalize()


func _def(def_id: String) -> Dictionary:
	for d: Dictionary in QUEST_DEFS:
		if String(d.get("id", "")) == def_id:
			return d
	return {}


## Rebuilds the offered list: up to 3 unstarted defs; the finale appears
## once all six base quests are done.
func _refresh_board() -> void:
	var active_ids := {}
	var done_ids := {}
	for q: Dictionary in quests:
		if String(q.get("state", "")) == "active":
			active_ids[String(q.get("def_id", ""))] = true
		elif String(q.get("state", "")) == "done" \
				and not bool(q.get("failed", false)):
			done_ids[String(q.get("def_id", ""))] = true
	offered.clear()
	var base_done := 0
	for d: Dictionary in QUEST_DEFS:
		var did: String = String(d.get("id", ""))
		if did == "q_finale":
			continue
		if not active_ids.has(did) and not done_ids.has(did) \
				and offered.size() < 3:
			offered.append(did)
		if done_ids.has(did):
			base_done += 1
	if base_done >= 6 and not active_ids.has("q_finale") \
			and not done_ids.has("q_finale"):
		offered.append("q_finale")


func offered_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for did in offered:
		var d := _def(did)
		if not d.is_empty():
			out.append(d)
	return out


func active_quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q: Dictionary in quests:
		if String(q.get("state", "")) == "active":
			out.append(q)
	return out


func completed_count() -> int:
	var n := 0
	for q: Dictionary in quests:
		if String(q.get("state", "")) == "done" \
				and not bool(q.get("failed", false)):
			n += 1
	return n


func accept_quest(def_id: String) -> bool:
	var d := _def(def_id)
	if d.is_empty() or not offered.has(def_id):
		return false
	for q: Dictionary in quests:
		if String(q.get("def_id", "")) == def_id \
				and String(q.get("state", "")) == "active":
			return false
	var q := {
		"id": "q%d" % _next_quest_num,
		"def_id": def_id,
		"type": String(d.get("type", "")),
		"title": String(d.get("title", "")),
		"desc": String(d.get("desc", "")),
		"intro": String(d.get("intro", "")),
		"accept_line": String(d.get("accept", "")),
		"done_line": String(d.get("done", "")),
		"state": "active",
		"giver_role": String(d.get("giver", "")),
		"giver_name": _giver_name(String(d.get("giver", ""))),
		"obj": (d.get("obj", {}) as Dictionary).duplicate(true),
		"reward": (d.get("reward", {}) as Dictionary).duplicate(true),
		"npc_id": -1,
		"failed": false,
	}
	_next_quest_num += 1
	var kind := String((q["obj"] as Dictionary).get("kind", ""))
	# Spawn-failure guards: a quest whose NPC/boss never materialized (world
	# at the unit cap) could never complete. Roll back loudly — the def stays
	# on the board — instead of handing the player a silent hang.
	var spawn_ok := true
	var boss_dead_already := false
	if kind == "fetch":
		_plant_quest_item(q)
		if bool((q["obj"] as Dictionary).get("plant_failed", false)):
			# Nowhere to hide the quest item: every dungeon chest is cleared,
			# claimed by another quest, or the stronghold's. Loud rollback —
			# the def stays on the board for a later attempt.
			_toast("No dungeon will hold \"%s\" — \"%s\" must wait."
				% [String((q["obj"] as Dictionary).get("item", "the relic")),
					String(q["title"])])
			_deed("Could not start quest \"%s\": no plantable dungeon chest."
				% String(q["title"]))
			return false
	elif kind == "rescue":
		_spawn_captive(q)
		spawn_ok = int(q.get("npc_id", -1)) >= 0
	elif kind == "escort":
		_spawn_traveler(q)
		spawn_ok = int(q.get("npc_id", -1)) >= 0
	elif kind == "boss":
		var had_stronghold := _stronghold_exists()
		_spawn_stronghold()
		if not _boss_alive():
			if had_stronghold:
				# The King fell (disaster, war, beasts) while the finale
				# was abandoned — no one left to slay. Complete it out
				# loud below instead of hanging on an empty stronghold.
				boss_dead_already = true
			else:
				# First spawn failed (unit cap): tear down the boss-less
				# shell so a later accept starts clean, and roll back.
				_remove_stronghold()
				spawn_ok = false
	if not spawn_ok:
		_toast("The wilds are too crowded — \"%s\" must wait." % String(q["title"]))
		_deed("Could not start quest \"%s\": unit cap." % String(q["title"]))
		return false
	quests.append(q)
	offered.erase(def_id)
	bump_rep("giver:" + String(q["giver_role"]), String(q["giver_name"]),
		3.0, "Took on \"%s\"" % String(q["title"]))
	_deed("Accepted quest: %s (from %s)." % [String(q["title"]),
		String(q["giver_name"])])
	_toast("Quest accepted: %s" % String(q["title"]))
	_toast("%s: \"%s\"" % [String(q["giver_name"]), String(q["intro"])])
	_say(String(q["accept_line"]))
	# A kill quest accepted into a world with no living targets would hang
	# on arrival — guarantee prey before the player ever sees the board.
	_ensure_prey_supply()
	if boss_dead_already:
		# The Bandit King died while the finale was abandoned: the quest was
		# just re-taken into an empty stronghold. Word has already spread —
		# complete it out loud (rewards + campaign win) instead of hanging.
		_boss_slain_by_other_hand()
	_gs.bus.adventure_quest_accepted.emit(q)
	return true


func complete_quest(quest_id: String) -> void:
	var q := _quest_by_id(quest_id)
	if q.is_empty() or String(q.get("state", "")) != "active":
		return
	q["state"] = "done"
	var r: Dictionary = q.get("reward", {})
	if float(r.get("xp", 0)) > 0.0:
		gain_xp(int(r["xp"]))
	var h := hero()
	if not h.is_empty() and float(r.get("gold", 0.0)) > 0.0:
		h["gold"] = float(h.get("gold", 0.0)) + float(r["gold"])
	var gear_id := String(r.get("gear", ""))
	if gear_id != "" and GEAR.has(gear_id) and not bag.has(gear_id) \
			and String(gear.get(String((GEAR[gear_id] as Dictionary).get("slot", "")))) != gear_id:
		bag.append(gear_id)
		_toast("Loot: %s! (Gear panel to equip)" % String((GEAR[gear_id] as Dictionary).get("name", gear_id)))
	bump_rep("giver:" + String(q.get("giver_role", "")),
		String(q.get("giver_name", "")), 12.0,
		"Completed \"%s\"" % String(q["title"]))
	_free_quest_npc(q)
	_deed("Completed quest: %s." % String(q["title"]))
	_toast("Quest complete: %s! +%d XP, +%dg" % [String(q["title"]),
		int(r.get("xp", 0)), int(float(r.get("gold", 0.0)))])
	_say(String(q.get("done_line", "Done.")))
	_gs.bus.adventure_quest_completed.emit(q)
	_refresh_board()


func abandon_quest(quest_id: String) -> void:
	var q := _quest_by_id(quest_id)
	if q.is_empty() or String(q.get("state", "")) != "active":
		return
	q["state"] = "done"
	q["failed"] = true
	_free_quest_npc(q)
	_deed("Abandoned quest: %s." % String(q["title"]))
	_toast("Quest abandoned: %s" % String(q["title"]))
	_refresh_board()


func quest_progress(q: Dictionary) -> String:
	var obj: Dictionary = q.get("obj", {})
	match String(obj.get("kind", "")):
		"kill":
			return "%d/%d slain" % [mini(int(obj.get("count", 0)),
				int(obj.get("n", 1))), int(obj.get("n", 1))]
		"clear_dungeon":
			return "%d/%d cleared" % [mini(int(obj.get("count", 0)),
				int(obj.get("n", 1))), int(obj.get("n", 1))]
		"rescue":
			return "escort them home — follow the mark" if _quest_npc_alive(q) \
				else "find the captive"
		"escort":
			return "reach the old shrine"
		"fetch":
			return "find it in a dungeon chest"
		"boss":
			return "slay the Bandit King"
	return ""


func _quest_by_id(quest_id: String) -> Dictionary:
	for q: Dictionary in quests:
		if String(q.get("id", "")) == quest_id:
			return q
	return {}


func _quest_npc(q: Dictionary) -> Dictionary:
	return _gs.get_unit(int(q.get("npc_id", -1)))


func _quest_npc_alive(q: Dictionary) -> bool:
	var npc := _quest_npc(q)
	return not npc.is_empty() and npc.get("alive", false)


func _free_quest_npc(q: Dictionary) -> void:
	var npc := _quest_npc(q)
	if not npc.is_empty():
		npc["_adv_npc"] = false
		npc["_adv_follow"] = false
	q["npc_id"] = -1


# ------------------------------------------------------------------ quest spawns

func _wild_spot(min_hall_dist: float) -> Vector2:
	var towns: Array = _gs.towns.values()
	for _a in range(60):
		var p := Vector2(randf_range(200.0, _world_size.x - 200.0),
			randf_range(200.0, _world_size.y - 200.0))
		var ok := true
		for t: Dictionary in towns:
			if p.distance_to(t.get("position", Vector2.ZERO)) < min_hall_dist:
				ok = false
				break
		if ok:
			return p
	return _world_size * 0.5


func _spawn_unit_raw(p_faction: String, job: String, pos: Vector2,
		extra: Dictionary) -> Dictionary:
	if _gs.units.size() >= 96:
		return {}
	var rec := {
		"faction": p_faction,
		"job": job,
		"town_id": -1,
		"position": pos,
		"alive": true,
		"hp": 100.0,
		"max_hp": 100.0,
		"gender": "m" if randi() % 2 == 0 else "f",
		"attack_cd": 0.0,
		"combat_state": "idle",
	}
	for k in extra.keys():
		rec[k] = extra[k]
	var u := _gs.add_unit(rec)
	_gs.bus.unit_spawned.emit(u)
	return u


func _spawn_captive(q: Dictionary) -> void:
	# The captive waits at an uncleared bandit dungeon — never beside the
	# hero's hall (that would auto-complete the rescue on accept).
	var spot := _wild_spot(700.0)
	var dg: Dictionary = {}
	for d: Dictionary in dungeons:
		if not bool(d.get("cleared", false)) \
				and not bool(d.get("is_stronghold", false)):
			dg = d
			break
	if not dg.is_empty():
		spot = (dg.get("pos", _world_size * 0.5) as Vector2) + Vector2(40, 40)
		dg["discovered"] = true
	var u := _spawn_unit_raw(faction, "worker", spot, {
		"_adv_npc": true, "_adv_captive": true, "_adv_follow": false,
		"name": "Captive",
	})
	if u.is_empty():
		return
	q["npc_id"] = int(u["id"])
	_toast("%s was taken! Find the bandit camp." % String(u.get("name", "A townsfolk")))
	_say("Hold on — I'm coming!")


func _spawn_traveler(q: Dictionary) -> void:
	var hall := _home_hall_pos()
	var u := _spawn_unit_raw(faction, "worker", hall + Vector2(40, 40), {
		"_adv_npc": true, "_adv_traveler": true, "_adv_follow": true,
		"name": "Pilgrim",
	})
	if u.is_empty():
		return
	q["npc_id"] = int(u["id"])
	var shrine_spot := _wild_spot(700.0)
	(q["obj"] as Dictionary)["shrine"] = [shrine_spot.x, shrine_spot.y]
	_toast("Escort %s to the old shrine (they follow you)." % String(u.get("name", "the traveler")))


## Rescue/escort NPC follow logic.
## Quest NPCs get the full urge system like regular NPCs -- but passive:
## urges decay and auto-satisfy without ever overriding quest behavior
## (no wandering off to find a bed mid-escort).
func tick_quest_npc(u: Dictionary, delta: float) -> void:
	if not active or not u.get("alive", false):
		return
	if mind != null:
		mind.tick_passive(u, delta, true)
	var h := hero()
	if h.is_empty() or not h.get("alive", false):
		return
	var hpos: Vector2 = h.get("position", Vector2.ZERO)
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var d := upos.distance_to(hpos)
	for q: Dictionary in quests:
		if String(q.get("state", "")) != "active":
			continue
		if int(q.get("npc_id", -1)) != int(u.get("id", -1)):
			continue
		var kind := String((q["obj"] as Dictionary).get("kind", ""))
		if kind == "rescue" and not bool(u.get("_adv_follow", false)):
			if d < 260.0:
				u["_adv_follow"] = true
				_toast("%s: \"You came! Lead me home!\"" % String(u.get("name", "They")))
		if bool(u.get("_adv_follow", false)) and d > 120.0:
			_walk_to(u, hpos, 130.0, delta)
		if kind == "rescue" and bool(u.get("_adv_follow", false)) \
				and _near_any_hall(hpos, 420.0):
			complete_quest(String(q["id"]))
		elif kind == "escort":
			var sh: Array = (q["obj"] as Dictionary).get("shrine", [])
			if sh.size() == 2:
				var spos := Vector2(float(sh[0]), float(sh[1]))
				if hpos.distance_to(spos) < 220.0 and d < 260.0:
					complete_quest(String(q["id"]))


func _near_any_hall(pos: Vector2, dist: float) -> bool:
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) in HALL_TYPES \
				and pos.distance_to(b.get("position", Vector2.ZERO)) < dist:
			return true
	return false


func _plant_quest_item(q: Dictionary) -> void:
	var item := String((q["obj"] as Dictionary).get("item", ""))
	# Pass 1: a fresh, uncleared dungeon whose chest holds no other quest's
	# item. The Bandit King's stronghold can never be cleared, so a quest
	# item planted there would be uncompletable — it is never eligible. A
	# chest already holding another quest's item would be overwritten (the
	# chest has a single quest_item key).
	var dg: Dictionary = _find_plant_dungeon(false)
	if dg.is_empty():
		# Pass 2 (quest-failure-run parity): every dungeon is cleared. Fall
		# back to a cleared non-stronghold chest and re-stock it — accepting
		# a fetch after a full clear must still work.
		dg = _find_plant_dungeon(true)
	if dg.is_empty():
		# No plantable dungeon: every chest is claimed, cleared-and-claimed,
		# or the stronghold's. accept_quest rolls this back loudly instead
		# of handing the player a quest that can never complete.
		(q["obj"] as Dictionary)["plant_failed"] = true
		return
	(dg["chest"] as Dictionary)["quest_item"] = item
	# The quest re-stocks the chest: a previously looted chest must not
	# seal the item away forever (accepting the fetch after a full clear
	# used to plant into a sealed chest — an uncompletable quest).
	dg["chest_looted"] = false
	(q["obj"] as Dictionary)["dg_name"] = String(dg.get("name", ""))


## First dungeon eligible to hold a quest item: never the stronghold, and
## never a chest already holding another quest's item. When allow_cleared
## is false (pass 1) the dungeon must also be uncleared; when true (pass 2)
## a cleared dungeon is re-stocked.
func _find_plant_dungeon(allow_cleared: bool) -> Dictionary:
	for d: Dictionary in dungeons:
		if bool(d.get("is_stronghold", false)):
			continue
		if not allow_cleared and bool(d.get("cleared", false)):
			continue
		if String((d.get("chest", {}) as Dictionary).get("quest_item", "")) \
				!= "":
			continue
		return d
	return {}


# ------------------------------------------------------------------ dungeons

func _spawn_dungeons() -> void:
	var i := 0
	for def: Dictionary in DUNGEON_DEFS:
		var pos := _wild_spot(1200.0)
		var dg := {
			"id": "dg%d" % i,
			"name": String(def["name"]),
			"kind": String(def["kind"]),
			"pos": pos,
			"discovered": false,
			"cleared": false,
			"chest_looted": false,
			"chest": _make_chest(i),
			"denizen_ids": [],
			"is_stronghold": false,
		}
		dungeons.append(dg)
		_spawn_denizens(dg)
		i += 1
	_toast("Rumors speak of dungeons in the wilds...")


func _spawn_stronghold() -> void:
	for d: Dictionary in dungeons:
		if bool(d.get("is_stronghold", false)):
			return
	var pos := _wild_spot(1400.0)
	var dg := {
		"id": "dg_stronghold",
		"name": String(STRONGHOLD_DEF["name"]),
		"kind": String(STRONGHOLD_DEF["kind"]),
		"pos": pos,
		"discovered": true,
		"cleared": false,
		"chest_looted": false,
		"chest": {"gold": 800.0, "gear_id": "", "quest_item": ""},
		"denizen_ids": [],
		"is_stronghold": true,
	}
	dungeons.append(dg)
	# Royal guard: 5 elite denizens + the King himself.
	_spawn_denizens(dg)
	var boss := _spawn_unit_raw("bandit", "bandit", pos + Vector2(0, -60), {
		"hp": 700.0, "max_hp": 700.0,
		"dmg_override": 30.0,
		"_adv_denizen": true, "_adv_boss": true, "_adv_lvl": 6,
		"name": "The Bandit King",
	})
	if not boss.is_empty():
		(dg["denizen_ids"] as Array).append(int(boss["id"]))
	_toast("The Bandit King's Stronghold rises in the wilds. End him.")


func _stronghold_exists() -> bool:
	for d: Dictionary in dungeons:
		if bool(d.get("is_stronghold", false)):
			return true
	return false


func _boss_alive() -> bool:
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and bool(u.get("_adv_boss", false)):
			return true
	return false


## Tears down a boss-less stronghold shell (a first finale accept whose King
## never spawned at the unit cap). Keeps a later accept from inheriting an
## empty stronghold that would read as "the King died while abandoned".
func _remove_stronghold() -> void:
	for i in range(dungeons.size() - 1, -1, -1):
		var d: Dictionary = dungeons[i]
		if bool(d.get("is_stronghold", false)):
			dungeons.remove_at(i)


func _make_chest(idx: int) -> Dictionary:
	var pool: Array[String] = []
	for gid in ["dragonfang", "dragonscale", "berserker_totem"]:
		if not bag.has(gid) and String(gear.get(String((GEAR[gid] as Dictionary).get("slot", "")))) != gid:
			pool.append(gid)
	var gear_id := ""
	if not pool.is_empty() and randf() < 0.65:
		gear_id = pool[randi() % pool.size()]
	return {
		"gold": 120.0 + float(idx) * 60.0 + float(level) * 25.0 \
			+ float(randi() % 80),
		"gear_id": gear_id,
		"quest_item": "",
	}


func _spawn_denizens(dg: Dictionary) -> void:
	var n := 3 + mini(3, level / 2)
	var dpos: Vector2 = dg.get("pos", _world_size * 0.5)
	for i in range(n):
		var alive_bandits := 0
		for u: Dictionary in _gs.units:
			if u.get("alive", false) and String(u.get("faction", "")) == "bandit":
				alive_bandits += 1
		if alive_bandits >= MAX_BANDITS:
			return
		var ang := randf() * TAU
		var r := randf_range(60.0, 150.0)
		var hp := 70.0 * (1.0 + float(level - 1) * 0.25)
		var u := _spawn_unit_raw("bandit", "bandit",
			dpos + Vector2(cos(ang), sin(ang)) * r, {
			"hp": hp, "max_hp": hp,
			"dmg_override": 10.0 * (1.0 + float(level - 1) * 0.2),
			"_adv_denizen": true, "_adv_lvl": level,
			"name": "Bandit",
		})
		if u.is_empty():
			return
		(dg["denizen_ids"] as Array).append(int(u["id"]))


func _dungeon_tick(h: Dictionary, _delta: float) -> void:
	var hpos: Vector2 = h.get("position", Vector2.ZERO)
	for dg: Dictionary in dungeons:
		var ids: Array = dg.get("denizen_ids", [])
		var alive: Array = []
		for uid in ids:
			var u := _gs.get_unit(int(uid))
			if not u.is_empty() and u.get("alive", false):
				alive.append(uid)  # the boss counts until slain
		dg["denizen_ids"] = alive
		var dpos: Vector2 = dg.get("pos", Vector2.ZERO)
		if not bool(dg.get("cleared", false)) and alive.is_empty() \
				and not bool(dg.get("is_stronghold", false)):
			dg["cleared"] = true
			_deed("Cleared %s." % String(dg.get("name", "")))
			_toast("Cleared %s! Loot its chest." % String(dg.get("name", "")))
			for q: Dictionary in quests:
				if String(q.get("state", "")) == "active" \
						and String((q["obj"] as Dictionary).get("kind", "")) == "clear_dungeon" \
						and String((q["obj"] as Dictionary).get("dg_id", "")) == String(dg.get("id", "")):
					(q["obj"] as Dictionary)["count"] = \
						int((q["obj"] as Dictionary).get("count", 0)) + 1
					if int((q["obj"] as Dictionary).get("count", 0)) \
							>= int((q["obj"] as Dictionary).get("n", 1)):
						complete_quest(String(q["id"]))
		if h.get("alive", false) and not bool(dg.get("discovered", false)) \
				and hpos.distance_to(dpos) < 700.0:
			dg["discovered"] = true
			_deed("Discovered %s." % String(dg.get("name", "")))
			_toast("Discovered: %s!" % String(dg.get("name", "")))


## Loot a cleared dungeon's chest. Returns a summary message.
func loot_chest(dg_id: String) -> String:
	var dg := _dungeon_by_id(dg_id)
	if dg.is_empty() or bool(dg.get("chest_looted", false)) \
			or not bool(dg.get("cleared", false)):
		return "The chest is sealed — clear the dungeon first."
	dg["chest_looted"] = true
	var h := hero()
	var chest: Dictionary = dg.get("chest", {})
	var gold := float(chest.get("gold", 0.0))
	if not h.is_empty():
		h["gold"] = float(h.get("gold", 0.0)) + gold
	var msg := "Looted %dg from %s!" % [int(gold), String(dg.get("name", ""))]
	var gear_id := String(chest.get("gear_id", ""))
	if gear_id != "" and GEAR.has(gear_id):
		bag.append(gear_id)
		msg += " Found %s!" % String((GEAR[gear_id] as Dictionary).get("name", gear_id))
	var item := String(chest.get("quest_item", ""))
	if item != "":
		for q: Dictionary in quests:
			if String(q.get("state", "")) == "active" \
					and String((q["obj"] as Dictionary).get("kind", "")) == "fetch" \
					and String((q["obj"] as Dictionary).get("item", "")) == item:
				complete_quest(String(q["id"]))
		msg += " Recovered the quest item!"
	_deed("Looted %s." % String(dg.get("name", "")))
	_toast(msg)
	return msg


func _dungeon_by_id(dg_id: String) -> Dictionary:
	for d: Dictionary in dungeons:
		if String(d.get("id", "")) == dg_id:
			return d
	return {}


func _spawn_beasts() -> void:
	# Wild monsters for "The Old Threat" — rogue wizards prowl the wilds.
	# Their disaster budget is frozen by _beast_upkeep so they never wander off.
	for i in range(3):
		var u := _spawn_unit_raw("monster", "rogue_wizard",
			_wild_spot(900.0), {"_adv_beast": true, "name": "Wild Beast"})
		if u.is_empty():
			return


func _beast_upkeep() -> void:
	for u: Dictionary in _gs.units:
		if bool(u.get("_adv_beast", false)) and u.get("alive", false):
			u["age"] = 0.0  # never leave on disaster budget


# ------------------------------------------------------------------ gear & shop

## Buy gear from the outfitter. Returns a message.
func buy_gear(gid: String) -> String:
	if not GEAR.has(gid):
		return "No such gear."
	var it: Dictionary = GEAR[gid]
	var cost := float(it.get("cost", 0.0))
	if cost <= 0.0:
		return "That one only comes from dungeon chests."
	var h := hero()
	if h.is_empty():
		return "No hero."
	if String(gear.get(String(it.get("slot", "")))) == gid or bag.has(gid):
		return "Already owned."
	if float(h.get("gold", 0.0)) < cost:
		return "Need %dg for %s." % [int(cost), String(it.get("name", gid))]
	h["gold"] = float(h.get("gold", 0.0)) - cost
	bag.append(gid)
	_deed("Bought %s." % String(it.get("name", gid)))
	return "Bought %s! Equip it from the Gear panel." % String(it.get("name", gid))


func equip(gid: String) -> String:
	if not GEAR.has(gid) or not bag.has(gid):
		return "Not in your bag."
	var it: Dictionary = GEAR[gid]
	var slot := String(it.get("slot", ""))
	var cur := String(gear.get(slot, ""))
	bag.erase(gid)
	if cur != "":
		bag.append(cur)
	gear[slot] = gid
	_apply_stats()
	return "Equipped %s." % String(it.get("name", gid))


func unequip(slot: String) -> String:
	var cur := String(gear.get(slot, ""))
	if cur == "":
		return "Nothing equipped there."
	bag.append(cur)
	gear[slot] = ""
	_apply_stats()
	return "Unequipped %s." % String((GEAR[cur] as Dictionary).get("name", cur))


# ------------------------------------------------------------------ supplies

## Consumable inventory (HTML playerInventory parity): simple counters,
## listed (nonzero) in the inventory panel. Zero-count slots are dropped.
func inv_count(id: String) -> int:
	return int(inventory.get(id, 0))


func inv_add(id: String, n: int) -> void:
	inventory[id] = inv_count(id) + n


## Consumes n of a supply. Returns false when the hero doesn't carry enough.
func inv_use(id: String, n: int = 1) -> bool:
	if inv_count(id) < n:
		return false
	inventory[id] = inv_count(id) - n
	return true


# ------------------------------------------------------------------ rep & deeds

func bump_rep(key: String, rep_name: String, amt: float, why: String) -> void:
	var e: Dictionary = rep.get(key, {"score": 0.0, "name": rep_name})
	e["score"] = clampf(float(e.get("score", 0.0)) + amt, -100.0, 100.0)
	if rep_name != "":
		e["name"] = rep_name
	rep[key] = e
	if why != "":
		_deed("%s: %s (%+d)" % [String(e.get("name", key)), why, int(amt)])


func rep_status(score: float) -> String:
	if score >= 40.0:
		return "beloved"
	if score >= 10.0:
		return "liked"
	if score > -10.0:
		return "neutral"
	if score > -40.0:
		return "disliked"
	return "feared"


func _wanted_tick(delta: float) -> void:
	want_t += delta
	if want_t < WANTED_DECAY:
		return
	want_t = 0.0
	for k in wanted.keys():
		wanted[k] = maxf(0.0, float(wanted[k]) - 1.0)


func _deed(text: String) -> void:
	deeds.append("[day %d] %s" % [_gs.day_number, text])
	while deeds.size() > 60:
		deeds.pop_front()
	_gs.bus.adventure_deed.emit(text)


func _toast(text: String) -> void:
	_gs.bus.adventure_deed.emit(text)


func _say(text: String) -> void:
	_gs.bus.unit_said.emit(hero_id, text)
	_toast("%s: \"%s\"" % [hero_name, text])


# ------------------------------------------------------------------ win / lose

func _win() -> void:
	if won or lost:
		return
	won = true
	_deed("Became a Legend of the Wilds.")
	_gs.bus.adventure_won.emit()


func _lose() -> void:
	if won or lost:
		return
	lost = true
	_deed("The wilds claimed another hero.")
	_gs.bus.adventure_lost.emit()


# ------------------------------------------------------------------ internals

func _hero_target(u: Dictionary) -> Dictionary:
	var forced := int(u.get("attack_target", -1))
	if forced >= 0:
		var t := _gs.get_unit(forced)
		if not t.is_empty() and t.get("alive", false) \
				and SimCombat.is_hostile(faction, String(t.get("faction", ""))):
			return t
		u["attack_target"] = -1
	# Auto-combat only picks bandits/monsters — never start faction wars
	# by accident (attacking anyone else is a manual order, and a crime).
	var pos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := HERO_AGGRO * HERO_AGGRO
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		var xf: String = String(x.get("faction", ""))
		if xf != "bandit" and xf != "monster":
			continue
		var d2: float = pos.distance_squared_to(
			x.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = x
	return best


## Walk toward a point. Returns true on arrival.
## Long hauls route around buildings/obstacles (A*); short hops steer direct.
func _walk_to(u: Dictionary, target_pos: Vector2, speed: float,
		delta: float) -> bool:
	var arrived := SimPathfinder.walk_to(_gs, u, target_pos, speed, delta)
	u["combat_state"] = "moving"
	return arrived


# ------------------------------------------------------------------ save / load

## Plain-dict snapshot (Vector2s encoded as [x, y] for JSON safety).
func save_data() -> Dictionary:
	var dg_out: Array = []
	for d: Dictionary in dungeons:
		var dd := d.duplicate(true)
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		dd["pos"] = [p.x, p.y]
		dg_out.append(dd)
	return {
		"version": 1,
		"active": active,
		"faction": faction,
		"hero_id": hero_id,
		"hero_name": hero_name,
		"hero_job": hero_job,
		"hero_gender": hero_gender,
		"level": level,
		"xp": xp,
		"attr": attr.duplicate(),
		"attr_pts": attr_pts,
		"mana": mana,
		"max_mana": max_mana,
		"base_hp": base_hp,
		"gear": gear.duplicate(),
		"bag": bag.duplicate(),
		"inventory": inventory.duplicate(),
		"quests": quests.duplicate(true),
		"offered": offered.duplicate(),
		"deeds": deeds.duplicate(),
		"rep": rep.duplicate(true),
		"wanted": wanted.duplicate(),
		"dungeons": dg_out,
		"ability_cd": ability_cd,
		"strike_buff_t": strike_buff_t,
		"respawn_t": respawn_t,
		"deaths": deaths,
		"won": won,
		"lost": lost,
		"next_quest_num": _next_quest_num,
	}


func load_data(d: Dictionary) -> bool:
	if d.is_empty() or int(d.get("version", 0)) != 1:
		return false
	active = bool(d.get("active", false))
	faction = String(d.get("faction", ""))
	hero_id = int(d.get("hero_id", -1))
	hero_name = String(d.get("hero_name", "Hero"))
	hero_job = String(d.get("hero_job", "swordsman"))
	hero_gender = String(d.get("hero_gender", "male"))
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	attr = (d.get("attr", {}) as Dictionary).duplicate()
	attr_pts = int(d.get("attr_pts", 0))
	mana = float(d.get("mana", 60.0))
	max_mana = float(d.get("max_mana", 60.0))
	base_hp = float(d.get("base_hp", 180.0))
	gear = (d.get("gear", {}) as Dictionary).duplicate()
	bag.clear()
	for g in d.get("bag", []):
		bag.append(String(g))
	quests.clear()
	for q in d.get("quests", []):
		quests.append((q as Dictionary).duplicate(true))
	inventory = (d.get("inventory", {}) as Dictionary).duplicate()
	offered.clear()
	for o in d.get("offered", []):
		offered.append(String(o))
	deeds.clear()
	for dd in d.get("deeds", []):
		deeds.append(String(dd))
	rep = (d.get("rep", {}) as Dictionary).duplicate(true)
	wanted = (d.get("wanted", {}) as Dictionary).duplicate()
	dungeons.clear()
	for dd in d.get("dungeons", []):
		var d2 := (dd as Dictionary).duplicate(true)
		var p: Array = d2.get("pos", [2048.0, 2048.0])
		d2["pos"] = Vector2(float(p[0]), float(p[1]))
		dungeons.append(d2)
	ability_cd = float(d.get("ability_cd", 0.0))
	strike_buff_t = float(d.get("strike_buff_t", 0.0))
	respawn_t = float(d.get("respawn_t", 0.0))
	deaths = int(d.get("deaths", 0))
	won = bool(d.get("won", false))
	lost = bool(d.get("lost", false))
	_next_quest_num = int(d.get("next_quest_num", 1))
	return true
