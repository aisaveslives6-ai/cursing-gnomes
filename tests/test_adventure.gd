extends SceneTree
## Cursing Gnomes — adventure mode headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_adventure.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes adventure tests ===")
	_test_start()
	_test_hero_movement()
	_test_bounty_quest()
	_test_rescue_quest()
	_test_dungeon_clear_and_loot()
	_test_gear_and_ability()
	_test_level_up()
	_test_crime_and_wanted()
	_test_win()
	_test_lose()
	_test_save_load()
	_test_save_system_wiring()
	_test_faction_hero_jobs()
	_test_hero_job_primary_attr()
	_test_starting_inventory()
	_test_inventory_save_load()
	_test_hero_urges()
	_test_hero_exhaustion()
	_test_hero_starving_weakens()
	_test_quest_npc_urges()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_adventure() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var factions: Array[String] = ["humans", "ogres", "elves", "gnomes",
		"undead"]
	gs.setup(factions)
	var town: Dictionary = gs.found_town("gnomes", "Testville",
		Vector2(2048, 2048))
	gs.add_building({"type": "town_hall", "faction": "gnomes",
		"town_id": int(town["id"]), "position": Vector2(2048, 2048)})
	var adv := SimAdventure.new(gs)
	var ok: bool = adv.start("gnomes", "TestHero", "soldier",
		Vector2(4096, 4096))
	return [gs, adv, ok]


func _bandit_count(gs: GameState) -> int:
	var n := 0
	for u: Dictionary in gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == "bandit":
			n += 1
	return n


func _test_start() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_check("start: returns true", bool(parts[2]))
	_check("start: active", adv.active)
	_check("start: hero spawned", adv.hero_id > 0)
	var h: Dictionary = adv.hero()
	_check("start: hero flagged", bool(h.get("is_hero", false)))
	_check("start: hero name", String(h.get("name", "")) == "TestHero")
	_check("start: hero hp", float(h.get("max_hp", 0.0)) >= 180.0)
	_check("start: hero gold seeded", float(h.get("gold", 0.0)) >= 50.0)
	_check("start: 3 dungeons", adv.dungeons.size() == 3)
	_check("start: 3 offered quests", adv.offered.size() == 3)
	var beasts := 0
	for u: Dictionary in gs.units:
		if bool(u.get("_adv_beast", false)):
			beasts += 1
	_check("start: 3 wild beasts", beasts == 3)
	_check("start: denizens spawned", _bandit_count(gs) >= 9)
	gs.free()


func _test_hero_movement() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	var start_pos: Vector2 = h.get("position", Vector2.ZERO)
	adv.order_move(start_pos + Vector2(500, 0))
	_check("move: order stored", bool(h.get("has_move_order", false)))
	adv.tick_hero(h, 1.0)
	var moved: float = start_pos.distance_to(
		h.get("position", Vector2.ZERO))
	_check("move: hero walked ~115px", absf(moved - 115.0) < 2.0)
	# Attack order overrides movement.
	adv.order_attack(999)
	_check("attack: move cleared", not bool(h.get("has_move_order", false)))
	_check("attack: target set", int(h.get("attack_target", 0)) == 999)
	gs.free()


func _test_bounty_quest() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_check("bounty: offered has q_bounty1", adv.offered.has("q_bounty1"))
	_check("bounty: accept", adv.accept_quest("q_bounty1"))
	var h: Dictionary = adv.hero()
	var gold0 := float(h.get("gold", 0.0))
	for i in range(4):
		var b: Dictionary = gs.add_unit({"faction": "bandit", "job": "bandit",
			"town_id": -1, "position": Vector2(i * 10, 0), "alive": true,
			"hp": 50.0, "max_hp": 50.0, "_adv_denizen": true,
			"_adv_lvl": 1, "name": "Bandit"})
		adv._on_hero_kill(b)
	_check("bounty: quest done", adv.completed_count() == 1)
	_check("bounty: gold reward", float(h.get("gold", 0.0)) >= gold0 + 300.0)
	_check("bounty: xp reward", adv.xp >= 250 or adv.level > 1)
	_check("bounty: gear reward", adv.bag.has("iron_sword"))
	gs.free()


func _test_rescue_quest() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	# q_rescue1 may not be in the first 3 offered — force it on the board.
	if not adv.offered.has("q_rescue1"):
		adv.offered.append("q_rescue1")
	_check("rescue: accept", adv.accept_quest("q_rescue1"))
	var q: Dictionary = adv.active_quests()[0]
	var npc: Dictionary = gs.get_unit(int(q.get("npc_id", -1)))
	_check("rescue: captive spawned", not npc.is_empty())
	_check("rescue: captive waits", not bool(npc.get("_adv_follow", false)))
	# Hero approaches -> captive follows.
	var h: Dictionary = adv.hero()
	h["position"] = npc.get("position", Vector2.ZERO)
	adv.tick(0.1)
	_check("rescue: captive follows", bool(npc.get("_adv_follow", false)))
	# Hero returns to the hall -> quest completes.
	h["position"] = Vector2(2048, 2048)
	adv.tick(0.1)
	_check("rescue: quest done", adv.completed_count() == 1)
	gs.free()


func _test_dungeon_clear_and_loot() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var dg: Dictionary = adv.dungeons[0]
	_check("dungeon: not cleared at start", not bool(dg.get("cleared", false)))
	for uid in (dg.get("denizen_ids", []) as Array).duplicate():
		gs.kill_unit(int(uid))
	adv.tick(0.1)
	_check("dungeon: cleared when denizens dead", bool(dg.get("cleared", false)))
	var h: Dictionary = adv.hero()
	var gold0 := float(h.get("gold", 0.0))
	var msg: String = adv.loot_chest(String(dg.get("id", "")))
	_check("dungeon: loot message", msg.begins_with("Looted"))
	_check("dungeon: gold looted", float(h.get("gold", 0.0)) > gold0)
	_check("dungeon: chest looted", bool(dg.get("chest_looted", false)))
	_check("dungeon: double-loot blocked",
		adv.loot_chest(String(dg.get("id", ""))).begins_with("The chest"))
	gs.free()


func _test_gear_and_ability() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	h["gold"] = 500.0
	_check("gear: buy", adv.buy_gear("rusty_sword").begins_with("Bought"))
	_check("gear: in bag", adv.bag.has("rusty_sword"))
	_check("gear: buy owned blocked",
		adv.buy_gear("rusty_sword") == "Already owned.")
	_check("gear: equip", adv.equip("rusty_sword").begins_with("Equipped"))
	_check("gear: slot set",
		String(adv.gear.get("weapon", "")) == "rusty_sword")
	_check("gear: attack bonus", adv.hero_attack_bonus(12.0) == 16.0)
	_check("gear: strike armed",
		adv.heroic_strike().begins_with("Heroic Strike armed"))
	_check("gear: strike x2.5", adv.hero_attack_bonus(12.0) == 40.0)
	_check("gear: strike on cooldown",
		adv.heroic_strike().begins_with("Heroic Strike ready"))
	_check("gear: unequip", adv.unequip("weapon").begins_with("Unequipped"))
	_check("gear: slot cleared", String(adv.gear.get("weapon", "")) == "")
	# Armor mitigation: chainmail (12 armor) softens a 100-dmg hit.
	h["gold"] = 500.0
	adv.buy_gear("chainmail")
	adv.equip("chainmail")
	_check("gear: mitigation", adv.mitigate_damage(adv.hero_id, 100.0) < 100.0)
	_check("gear: mitigation ignores others",
		adv.mitigate_damage(424242, 100.0) == 100.0)
	gs.free()


func _test_level_up() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	h["hp"] = 10.0
	adv.gain_xp(100000)
	_check("level: leveled up", adv.level > 1)
	_check("level: full heal on level",
		float(h.get("hp", 0.0)) == float(h.get("max_hp", 0.0)))
	_check("level: str grew (soldier)", int(adv.attr.get("str", 8)) > 8)
	_check("level: vit grew", int(adv.attr.get("vit", 8)) > 8)
	gs.free()


func _test_crime_and_wanted() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	# A human witness stands near the hero; the hero slays an elf.
	gs.add_unit({"faction": "humans",
		"job": "worker", "town_id": -1, "position": h.get("position", Vector2.ZERO),
		"alive": true, "hp": 100.0, "max_hp": 100.0, "name": "Witness"})
	var victim: Dictionary = gs.add_unit({"faction": "elves",
		"job": "worker", "town_id": -1, "position": h.get("position", Vector2.ZERO),
		"alive": true, "hp": 100.0, "max_hp": 100.0, "name": "Victim"})
	adv._on_hero_kill(victim)
	_check("crime: wanted heat", float(adv.wanted.get("elves", 0.0)) == 10.0)
	adv.tick(95.0)
	_check("crime: heat decays", float(adv.wanted.get("elves", 0.0)) < 10.0)
	gs.free()


func _test_win() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	# Complete all six base quests.
	var guard := 0
	while adv.completed_count() < 6 and guard < 20:
		for did in adv.offered.duplicate():
			if did == "q_finale":
				continue
			if adv.accept_quest(did):
				var act: Array = adv.active_quests()
				if not act.is_empty():
					adv.complete_quest(String(act[0].get("id", "")))
		guard += 1
	_check("win: all 6 done", adv.completed_count() == 6)
	_check("win: finale offered", adv.offered.has("q_finale"))
	_check("win: finale accepted", adv.accept_quest("q_finale"))
	var boss: Dictionary = {}
	for u: Dictionary in gs.units:
		if bool(u.get("_adv_boss", false)):
			boss = u
	_check("win: boss spawned", not boss.is_empty())
	adv._on_hero_kill(boss)
	_check("win: campaign won", adv.won)
	gs.free()


func _test_lose() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	for i in range(5):
		gs.kill_unit(adv.hero_id)
		adv.on_unit_died(adv.hero_id)
		if i < 4:
			h["alive"] = true  # field revive between falls
			adv.respawn_t = 0.0
	_check("lose: 5 deaths", adv.deaths == 5)
	_check("lose: campaign lost", adv.lost)
	gs.free()


func _test_save_load() -> void:
	# SaveSystem.snapshot/restore must include adventure state (was missing).
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	adv.accept_quest("q_bounty1")
	adv.gain_xp(300)
	adv.hero()["gold"] = 500.0
	adv.buy_gear("rusty_sword")
	adv.equip("rusty_sword")
	var data: Dictionary = adv.save_data()
	var adv2 := SimAdventure.new(gs)
	_check("save: load ok", adv2.load_data(data))
	_check("save: level kept", adv2.level == adv.level)
	_check("save: xp kept", adv2.xp == adv.xp)
	_check("save: bag kept", adv2.bag == adv.bag)
	_check("save: gear kept",
		String(adv2.gear.get("weapon", "")) == "rusty_sword")
	_check("save: quests kept", adv2.quests.size() == adv.quests.size())
	_check("save: dungeons kept", adv2.dungeons.size() == adv.dungeons.size())
	_check("save: hero id kept", adv2.hero_id == adv.hero_id)
	_check("save: dungeon pos kept",
		(adv2.dungeons[0].get("pos") as Vector2).distance_to(
			adv.dungeons[0].get("pos", Vector2.ZERO)) < 0.01)
	gs.free()


func _test_save_system_wiring() -> void:
	# SaveSystem.snapshot/restore must include adventure state (was missing
	# from saves entirely — Jeremy 2026-10-02 audit).
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	adv.gain_xp(500)
	adv.buy_gear("rusty_sword")
	var snap := SaveSystem.snapshot(gs, adv)
	_check("wiring: snapshot has adventure", snap.has("adventure"))
	# Restore into fresh instances.
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	var factions: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs2.setup(factions)
	var adv2 := SimAdventure.new(gs2)
	var ok := SaveSystem.restore(gs2, snap, adv2)
	_check("wiring: restore ok", ok)
	_check("wiring: adventure active restored", adv2.active)
	_check("wiring: xp restored", adv2.xp == adv.xp)
	_check("wiring: hero name restored", adv2.hero_name == adv.hero_name)
	# Backward compat: no adventure key when no adventure passed.
	var snap2 := SaveSystem.snapshot(gs)
	_check("wiring: no adventure key without adventure", not snap2.has("adventure"))
	gs.free()
	gs2.free()


func _test_faction_hero_jobs() -> void:
	# HTML setupCharCreate `paths` parity (Godot faction ids).
	var expect := {
		"humans": ["swordsman", "archer", "knight", "cleric"],
		"ogres": ["clubber", "musketeer", "berserker", "blunderbuss"],
		"gnomes": ["axeman", "mage", "tinker_mech", "saboteur"],
		"elves": ["ranger", "warlock", "treant", "spellweaver"],
		"undead": ["skeleton", "zombie", "ghoul", "necromancer"],
	}
	for f in expect.keys():
		_check("jobs: %s table matches HTML" % f,
			SimAdventure.hero_jobs_for(f) == expect[f])
	_check("jobs: default is first in list",
		SimAdventure.default_hero_job("gnomes") == "axeman")
	_check("jobs: unknown faction falls back to humans",
		SimAdventure.default_hero_job("bogus") == "swordsman")
	_check("jobs: labels exist for every job",
		SimAdventure.HERO_JOB_NAMES.size() == 20
		and String(SimAdventure.HERO_JOB_NAMES["tinker_mech"]) == "Tinker Mech")


func _test_hero_job_primary_attr() -> void:
	# HTML advOnLevelUp / advHeroAtkBonus parity.
	_check("attr: mage -> intel", SimAdventure.job_primary_attr("mage") == "intel")
	_check("attr: warlock -> intel",
		SimAdventure.job_primary_attr("warlock") == "intel")
	_check("attr: archer -> agi",
		SimAdventure.job_primary_attr("archer") == "agi")
	_check("attr: ranger -> agi",
		SimAdventure.job_primary_attr("ranger") == "agi")
	_check("attr: musketeer -> agi",
		SimAdventure.job_primary_attr("musketeer") == "agi")
	_check("attr: swordsman -> str",
		SimAdventure.job_primary_attr("swordsman") == "str")
	_check("attr: necromancer -> str",
		SimAdventure.job_primary_attr("necromancer") == "str")
	# Attack bonus scales with the job's primary attribute.
	var parts: Array = _new_adventure()
	var adv: SimAdventure = parts[1]
	adv.attr["intel"] = 18
	adv.hero_job = "warlock"
	var with_intel: float = adv.hero_attack_bonus(12.0)
	adv.attr["intel"] = 8
	var without_intel: float = adv.hero_attack_bonus(12.0)
	_check("attr: warlock bonus scales with intel",
		with_intel > without_intel)
	adv.hero_job = "ranger"
	adv.attr["agi"] = 18
	var with_agi: float = adv.hero_attack_bonus(12.0)
	adv.attr["agi"] = 8
	_check("attr: ranger bonus scales with agi",
		with_agi > adv.hero_attack_bonus(12.0))
	# Level-up grows the job's primary attribute.
	adv.hero_job = "mage"
	var before: int = int(adv.attr.get("intel", 8))
	adv._on_level_up()
	_check("attr: mage level-up grows intel",
		int(adv.attr.get("intel", 8)) == before + 1)
	parts[0].free()


func _test_starting_inventory() -> void:
	# HTML startAdventureGame playerInventory parity.
	var parts: Array = _new_adventure()
	var adv: SimAdventure = parts[1]
	_check("inv: granted on start", not adv.inventory.is_empty())
	_check("inv: 3 bread", adv.inv_count("bread") == 3)
	_check("inv: 1 ale", adv.inv_count("ale") == 1)
	_check("inv: 2 bandages", adv.inv_count("bandage") == 2)
	_check("inv: 1 pickaxe", adv.inv_count("pickaxe") == 1)
	_check("inv: 1 hatchet", adv.inv_count("hatchet") == 1)
	_check("inv: unknown item is 0", adv.inv_count("gem") == 0)
	adv.inv_add("fish", 2)
	_check("inv: add works", adv.inv_count("fish") == 2)
	_check("inv: use works", adv.inv_use("bread", 2))
	_check("inv: count drops", adv.inv_count("bread") == 1)
	_check("inv: use refuses shortage", not adv.inv_use("bread", 5))
	_check("inv: shortage leaves count", adv.inv_count("bread") == 1)
	parts[0].free()


func _test_inventory_save_load() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	adv.inv_add("fish", 4)
	adv.inv_use("bread", 1)
	var data: Dictionary = adv.save_data()
	_check("inv-save: inventory key present", data.has("inventory"))
	var adv2 := SimAdventure.new(gs)
	_check("inv-save: load ok", adv2.load_data(data))
	_check("inv-save: bread kept", adv2.inv_count("bread") == 2)
	_check("inv-save: fish kept", adv2.inv_count("fish") == 4)
	_check("inv-save: bandage kept", adv2.inv_count("bandage") == 2)
	gs.free()


func _test_hero_urges() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	adv.mind.ensure(h)
	# The hero gets the full 6-urge system: urges decay...
	var before: float = adv.mind.urges.value(h, "hunger")
	adv.tick_hero(h, 10.0)
	_check("hero hunger decays", adv.mind.urges.value(h, "hunger") < before)
	# ...critical hunger auto-eats from the faction stores...
	gs.resources.add_resource("gnomes", "food", 100.0)
	h["urges"]["hunger"] = 5.0
	h["has_move_order"] = false
	h["combat_state"] = "idle"
	adv.tick_hero(h, 1.0)
	_check("hero auto-eats", float(h["urges"]["hunger"]) > 50.0)
	# ...but the player keeps full control: no mind override, no hijack.
	_check("hero keeps control", String(h.get("mind_state", "")) == "")
	_check("hero not entering", int(h.get("inside_building_id", 0)) == 0)
	gs.free()


func _test_hero_exhaustion() -> void:
	var parts: Array = _new_adventure()
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	adv.mind.ensure(h)
	h["urges"]["energy"] = 5.0  # critical -- exhausted
	var start: Vector2 = h.get("position", Vector2.ZERO)
	adv.order_move(start + Vector2(500, 0))
	adv.tick_hero(h, 1.0)
	var moved: float = start.distance_to(h.get("position", Vector2.ZERO))
	# Exhausted hero moves at 0.7x: ~80.5px instead of 115px. The player
	# still decides where to go -- only the pace suffers.
	_check("exhausted hero slower", moved < 115.0 and moved > 1.0)
	_check("exhausted speed ~0.7x", absf(moved - 115.0 * 0.7) < 3.0)
	_check("exhausted flagged", adv._hero_exhausted(h))
	parts[0].free()


func _test_hero_starving_weakens() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var h: Dictionary = adv.hero()
	adv.mind.ensure(h)
	# Drain the stores so the hero truly starves (auto-eat fails).
	while gs.resources.get_amount("gnomes", "food") >= 2.0:
		gs.resources.spend("gnomes", {"food": 2.0})
	h["urges"]["hunger"] = 5.0
	h["has_move_order"] = false
	h["combat_state"] = "idle"
	adv.tick_hero(h, 0.1)
	_check("hero starving flagged", bool(h.get("_urge_starving", false)))
	var dmg_starving: float = adv.hero_attack_bonus(12.0)
	h["_urge_starving"] = false
	var dmg_fed: float = adv.hero_attack_bonus(12.0)
	_check("starving hits weaker", dmg_starving < dmg_fed)
	_check("starving penalty ~25%", dmg_starving >= dmg_fed * 0.7)
	gs.free()


func _test_quest_npc_urges() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var u: Dictionary = gs.spawner.spawn_unit("gnomes", "worker", -1,
		Vector2(4096, 4096))
	u["_adv_npc"] = true
	adv.mind.ensure(u)
	# Quest NPCs feel urges like regular NPCs...
	var before: float = adv.mind.urges.value(u, "hunger")
	adv.tick_quest_npc(u, 10.0)
	_check("quest npc hunger decays", adv.mind.urges.value(u, "hunger") < before)
	# ...but quest behavior is never overridden: no mind state, no detour
	# into a building mid-quest.
	_check("quest npc not hijacked", String(u.get("mind_state", "")) == "")
	_check("quest npc not entering", int(u.get("inside_building_id", 0)) == 0)
	gs.free()
