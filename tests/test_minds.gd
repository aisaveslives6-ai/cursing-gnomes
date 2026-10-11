extends SceneTree
## Cursing Gnomes — Milestone 5 headless NPC mind tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_minds.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []  # captured (unit_id, text) from unit_said


func _initialize() -> void:
	print("=== Cursing Gnomes mind tests ===")
	_test_personality_deterministic()
	_test_urge_decay()
	_test_hunger_override()
	_test_eat_food()
	_test_starving_no_food()
	_test_energy_rest()
	_test_sleep_two_hours_math()
	_test_rough_sleep_caps_low()
	_test_bladder_instant()
	_test_bladder_needs_toilet()
	_test_hygiene_needs_wash()
	_test_passive_tick_no_hijack()
	_test_bed_furniture_matters()
	_test_no_bed_rough_sleep()
	_test_coward_flees()
	_test_brave_stands()
	_test_memory_grudge()
	_test_memory_decay()
	_test_grief()
	_test_name_roast()
	_test_ruler_name_verbatim()
	_test_chatter_emits()
	_test_combat_mind_hook()
	_test_dialogue_offline()
	_test_no_banned_word()
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


## Fresh game + mind systems, capturing unit_said.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	_said.clear()
	gs.bus.unit_said.connect(func(uid: int, text: String) -> void:
		_said.append([uid, text]))
	var mind := SimMind.new(gs)
	return {"gs": gs, "mind": mind}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


## Spawns a unit via the spawner (caps respected) at a position.
func _spawn(w: Dictionary, faction: String, job: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


## Spawns units until one has the wanted bravery (rejects are killed+purged,
## so caps never fill). want_coward=true -> brave < 0.4, else brave >= 0.4.
func _spawn_pick_trait(w: Dictionary, want_coward: bool, faction: String,
		job: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	while true:
		var u: Dictionary = gs.spawner.spawn_unit(faction, job, -1, Vector2(100, 100))
		if u.is_empty():
			return {}  # caps exhausted — shouldn't happen in tests
		mind.ensure(u)
		var brave: float = SimPersonality.trait_of(u, "brave")
		if (brave < 0.4) == want_coward:
			return u
		gs.kill_unit(int(u["id"]))
		gs.purge_dead()
	return {}  # unreachable — the while loop always returns first


func _test_personality_deterministic() -> void:
	var a: Dictionary = SimPersonality.traits_for(7, "gnomes")
	var b: Dictionary = SimPersonality.traits_for(7, "gnomes")
	_check("personality deterministic", a["brave"] == b["brave"] and a["name"] == b["name"])
	_check("personality name non-empty", String(a["name"]) != "")
	var c: Dictionary = SimPersonality.traits_for(8, "gnomes")
	_check("personality varies by id", a["brave"] != c["brave"] or a["name"] != c["name"])


func _test_urge_decay() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	var before: float = mind.urges.value(u, "hunger")
	mind.urges.tick(u, 10.0)
	var after: float = mind.urges.value(u, "hunger")
	_check("hunger decays", after < before)
	_check("hunger decay rate", is_equal_approx(after, before - 0.35 * 10.0))
	_free_world(w)


func _test_hunger_override() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["hunger"] = 5.0  # critical
	var busy: bool = mind.tick_unit(u, 1.0)
	_check("critical hunger overrides job", busy)
	_check("mind state set", String(u["mind_state"]) == "satisfying:hunger")
	_free_world(w)


func _test_eat_food() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	gs.resources.add_resource("humans", "food", 100.0)
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["hunger"] = 5.0
	_check("override starts", mind.tick_unit(u, 1.0))
	# Second tick: satisfy runs — food is spent, hunger restored.
	var busy2: bool = mind.tick_unit(u, 1.0)
	_check("eating finishes", not busy2)
	_check("hunger restored", float(u["urges"]["hunger"]) >= 55.0)
	_check("food spent", gs.resources.get_amount("humans", "food") < 100.0)
	_check("ate line said", _said.size() > 0)
	_free_world(w)


func _test_starving_no_food() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["hunger"] = 5.0
	_check("override starts", mind.tick_unit(u, 1.0))
	# No food in stores: satisfy returns "cant", override clears, unit works.
	var busy2: bool = mind.tick_unit(u, 1.0)
	_check("starving unit works anyway", not busy2)
	_check("override cleared", String(u["mind_state"]) == "")
	_free_world(w)


func _test_energy_rest() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["energy"] = 5.0
	_check("tired overrides", mind.tick_unit(u, 1.0))
	var done := false
	# A full rest is 2 in-game hours in a bed = 2 * DAY_LENGTH_SECONDS / 24
	# real seconds — derived from Config so this survives day-length changes.
	# Ticks needed scale with day length: ~76 at 960s day.
	var ticks_needed: int = int(ceil(80.0 * Config.DAY_LENGTH_SECONDS / 960.0)) + 10
	for i: int in range(ticks_needed):
		if not mind.tick_unit(u, 1.0):
			done = true
			break
	_check("rest restores energy", done)
	_check("energy high after rest", float(u["urges"]["energy"]) >= 95.0)
	_free_world(w)


func _test_sleep_two_hours_math() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	# 2 in-game hours = 2 * DAY_LENGTH_SECONDS / 24 real seconds of
	# bed-sleep takes 0 -> ~100 (was 40 s at the 480 s day, now 80 s at the
	# 960 s day — derived from Config, never hardcoded).
	var full_rest_s: float = 2.0 * Config.DAY_LENGTH_SECONDS / 24.0
	_check("sleep rate is 2h for full rest",
		is_equal_approx(SimUrges.SLEEP_RATE, 100.0 / full_rest_s))
	u["urges"]["energy"] = 0.0
	_check("full bed sleep finishes",
		mind.urges.satisfy(u, "energy", full_rest_s, true) == "done")
	_check("full bed sleep fully rests",
		float(u["urges"]["energy"]) >= 95.0)
	_free_world(w)


func _test_rough_sleep_caps_low() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["energy"] = 5.0
	# No bed: floor-sleep is shallow -- finishes, but never fully rested.
	var done := false
	for i: int in range(400):
		if mind.urges.satisfy(u, "energy", 1.0, false) == "done":
			done = true
			break
	_check("rough sleep finishes", done)
	_check("rough sleep caps at 50",
		float(u["urges"]["energy"]) <= SimUrges.SLEEP_CAP_ROUGH + 0.01)
	_check("rough sleep below full rest",
		float(u["urges"]["energy"]) < SimUrges.SLEEP_DONE)
	_free_world(w)


func _test_bladder_needs_toilet() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	# With a toilet: instant, full relief.
	u["urges"]["bladder"] = 5.0
	_check("toilet instant", mind.urges.satisfy(u, "bladder", 1.0, true) == "done")
	_check("toilet full", float(u["urges"]["bladder"]) >= 99.0)
	# Without: slow and partial (behind a bush).
	u["urges"]["bladder"] = 5.0
	var done := false
	for i: int in range(30):
		if mind.urges.satisfy(u, "bladder", 1.0, false) == "done":
			done = true
			break
	_check("bush relief finishes", done)
	_check("bush relief partial",
		float(u["urges"]["bladder"]) <= SimUrges.BLADDER_CAP_ROUGH + 0.01)
	_free_world(w)


func _test_hygiene_needs_wash() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	# With sink/tub: full wash.
	u["urges"]["hygiene"] = 5.0
	var done := false
	for i: int in range(20):
		if mind.urges.satisfy(u, "hygiene", 1.0, true) == "done":
			done = true
			break
	_check("wash finishes", done)
	_check("wash full", float(u["urges"]["hygiene"]) >= 90.0)
	# Without: bird-bath only goes so far.
	u["urges"]["hygiene"] = 5.0
	done = false
	for i: int in range(60):
		if mind.urges.satisfy(u, "hygiene", 1.0, false) == "done":
			done = true
			break
	_check("bird-bath finishes", done)
	_check("bird-bath caps low",
		float(u["urges"]["hygiene"]) <= SimUrges.WASH_CAP_ROUGH + 0.01)
	_free_world(w)


func _test_passive_tick_no_hijack() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	gs.resources.add_resource("humans", "food", 100.0)
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	# Hero-style passive tick: urges decay...
	var before: float = mind.urges.value(u, "hunger")
	mind.tick_passive(u, 10.0, true)
	_check("passive decays hunger",
		mind.urges.value(u, "hunger") < before or float(u["urges"]["hunger"]) > 60.0)
	# ...critical hunger auto-eats from stores without an override...
	u["urges"]["hunger"] = 5.0
	var crit: String = mind.tick_passive(u, 1.0, true)
	_check("passive auto-eats", crit != "hunger")
	_check("passive spends food", gs.resources.get_amount("humans", "food") < 100.0)
	_check("passive sets no override", String(u.get("mind_state", "")) == "")
	# ...critical bladder relieves instantly...
	u["urges"]["bladder"] = 5.0
	u["urges"]["hunger"] = 80.0
	crit = mind.tick_passive(u, 1.0, true)
	_check("passive relieves bladder", crit != "bladder")
	# ...idle rest recovers energy at the bed rate...
	u["urges"]["energy"] = 50.0
	u["urges"]["hunger"] = 80.0
	u["urges"]["bladder"] = 80.0
	mind.tick_passive(u, 10.0, true)
	# Decay (0.22/s) applies first, then idle rest at the 8h bed rate.
	var want_e: float = 50.0 - 0.22 * 10.0 + SimUrges.SLEEP_RATE * 10.0
	_check("passive idle rest",
		is_equal_approx(float(u["urges"]["energy"]), want_e))
	# ...but no rest when not idle (decay only).
	u["urges"]["energy"] = 50.0
	mind.tick_passive(u, 10.0, false)
	var e: float = float(u["urges"]["energy"])
	_check("passive no rest when busy", is_equal_approx(e, 50.0 - 0.22 * 10.0))
	_free_world(w)


func _test_bladder_instant() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["bladder"] = 5.0
	_check("bladder overrides", mind.tick_unit(u, 1.0))
	_check("bladder relieves instantly", not mind.tick_unit(u, 0.5))
	_check("bladder full", float(u["urges"]["bladder"]) >= 99.0)
	_free_world(w)


func _test_coward_flees() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var victim: Dictionary = _spawn_pick_trait(w, true, "humans", "worker")
	_check("found coward", not victim.is_empty())
	var attacker: Dictionary = _spawn(w, "ogres", "soldier", Vector2(200, 100))
	victim["position"] = Vector2(100, 100)
	mind.on_attacked(victim, attacker, 30.0, "ogres")
	_check("coward flees", bool(victim["fleeing"]))
	_check("coward scared", mind.emotion.dominant(victim) == "scared")
	var before: Vector2 = victim["position"]
	_check("flee consumes slice", mind.tick_unit(victim, 1.0))
	var after: Vector2 = victim["position"]
	_check("flee moves away", after.x < before.x)
	_free_world(w)


func _test_brave_stands() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var victim: Dictionary = _spawn_pick_trait(w, false, "humans", "soldier")
	_check("found brave", not victim.is_empty())
	var attacker: Dictionary = _spawn(w, "ogres", "soldier", Vector2(200, 100))
	mind.on_attacked(victim, attacker, 30.0, "ogres")
	_check("brave does not flee", not bool(victim["fleeing"]))
	_check("brave gets angry", mind.emotion.dominant(victim) == "angry")
	_free_world(w)


func _test_memory_grudge() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	var attacker: Dictionary = _spawn(w, "ogres", "soldier", Vector2(200, 100))
	mind.on_attacked(victim, attacker, 30.0, "ogres")
	var aid: int = int(attacker["id"])
	_check("remembers attacker", mind.memories.recall(victim, "hurt_by", aid) > 0.5)
	_check("relationship negative", mind.memories.relationship(victim, aid) < 0.0)
	_check("holds grudge", mind.memories.holds_grudge(victim, aid))
	_free_world(w)


func _test_memory_decay() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	var attacker: Dictionary = _spawn(w, "ogres", "soldier", Vector2(200, 100))
	mind.on_attacked(victim, attacker, 30.0, "ogres")
	var aid: int = int(attacker["id"])
	var fresh: float = mind.memories.recall(victim, "hurt_by", aid)
	var t0: float = gs.game_time
	gs.game_time = t0 + 240.0  # one halflife after the memory formed
	var half: float = mind.memories.recall(victim, "hurt_by", aid)
	_check("memory decays", half < fresh)
	_check("memory halves", absf(half - fresh * 0.5) < 0.05)
	gs.game_time = t0 + 240.0 * 20.0  # long forgotten
	_check("memory forgotten", mind.memories.recall(victim, "hurt_by", aid) == 0.0)
	_free_world(w)


func _test_grief() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	# Jeremy 2026-10-05: grief needs a real bond (or marriage) — strangers
	# in earshot no longer get a fake friend_died memory.
	var family := SimFamily.new(gs)
	gs.family = family
	var friend: Dictionary = _spawn(w, "humans", "worker", Vector2(110, 100))
	var stranger: Dictionary = _spawn(w, "humans", "worker", Vector2(120, 100))
	var doomed: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	family.ensure(friend)
	family.ensure(stranger)
	family.ensure(doomed)
	family.bump_affinity(friend, doomed, 40.0)
	mind.ensure(friend)
	mind.ensure(stranger)
	mind.on_unit_died(int(doomed["id"]), "humans")
	_check("friend grieves", mind.emotion.dominant(friend) == "sad")
	_check("friend remembers", mind.memories.recall(friend, "friend_died", int(doomed["id"])) > 0.0)
	_check("stranger gets no friend_died memory",
		mind.memories.recall(stranger, "friend_died", int(doomed["id"])) == 0.0)
	_free_world(w)


func _test_name_roast() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var u: Dictionary = _spawn(w, "gnomes", "worker", Vector2(100, 100))
	_check("ruler default is blank", gs.ruler_name == "")
	gs.set_ruler_name("ass")  # Name-roasting still works when a name is set.
	var line: String = SimDialogue.line_for(gs, u, "roast_ruler")
	_check("roast mentions ruler", "ass" in line)
	_check("roast has no token left", "{ruler}" not in line)
	_free_world(w)


func _test_ruler_name_verbatim() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	gs.set_ruler_name("  ass  ")  # padded — the pipeline must NOT trim it
	_check("name stored verbatim", gs.ruler_name == "  ass  ")
	var u: Dictionary = _spawn(w, "gnomes", "worker", Vector2(100, 100))
	var line: String = SimDialogue.line_for(gs, u, "roast_ruler")
	_check("roast keeps padding verbatim", "  ass  " in line)
	_free_world(w)


func _test_chatter_emits() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["chatter_cd"] = 0.0
	mind.tick_unit(u, 0.1)
	_check("chatter emitted", _said.size() > 0)
	_check("chatter non-empty", String(_said[0][1]).length() > 0)
	_free_world(w)


func _test_combat_mind_hook() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var combat := SimCombat.new(gs)
	combat.mind = mind  # world does this in _ready
	var victim: Dictionary = _spawn_pick_trait(w, true, "humans", "worker")
	_check("found coward", not victim.is_empty())
	var attacker: Dictionary = _spawn(w, "ogres", "soldier", Vector2(200, 100))
	victim["hp"] = 100.0
	victim["max_hp"] = 100.0
	combat.damage_unit(int(victim["id"]), 10.0, "ogres", int(attacker["id"]))
	_check("combat feeds mind", bool(victim["fleeing"]))
	_check("combat records grudge",
		mind.memories.recall(victim, "hurt_by", int(attacker["id"])) > 0.0)
	_free_world(w)  # RefCounted systems are garbage-collected; no free() needed


func _read_source(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


func _test_dialogue_offline() -> void:
	var files: Array[String] = [
		"res://scripts/sim/dialogue.gd",
		"res://scripts/sim/mind.gd",
		"res://scripts/sim/urges.gd",
		"res://scripts/sim/emotion.gd",
		"res://scripts/sim/memories.gd",
		"res://scripts/sim/personality.gd",
	]
	for path: String in files:
		var src: String = _read_source(path).to_lower()
		# "http" catches http://, https://, HTTPRequest, HTTPClient.
		_check("offline: no http in " + path.get_file(), src.find("http") == -1)


func _test_no_banned_word() -> void:
	# Jeremy's law: the need system is "urges" — the Sims word never appears.
	var files: Array[String] = [
		"res://scripts/sim/urges.gd",
		"res://scripts/sim/emotion.gd",
		"res://scripts/sim/memories.gd",
		"res://scripts/sim/dialogue.gd",
		"res://scripts/sim/personality.gd",
		"res://scripts/sim/mind.gd",
	]
	for path: String in files:
		var src: String = _read_source(path).to_lower()
		_check("urges not whims in " + path.get_file(), src.find("whim") == -1)


func _test_bed_furniture_matters() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	mind.interiors = SimInteriors.new(gs)
	# Town hall (bathroom, NO bed) is closer; house (real bed) is farther.
	# The mind must prefer the furnished building for sleep.
	gs.add_building({"type": "town_hall", "faction": "humans",
		"position": Vector2(110, 100), "complete": true, "alive": true})
	var house: Dictionary = gs.add_building({"type": "house",
		"faction": "humans", "position": Vector2(300, 100),
		"complete": true, "alive": true})
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["energy"] = 5.0
	_check("tired overrides", mind.tick_unit(u, 1.0))
	_check("prefers building with a bed",
		int(u.get("inside_building_id", 0)) == int(house.get("id", 0)))
	# Sleep it off at the 2-in-game-hours bed rate: full rest to 95.
	# Tick budget scales with day length (the old 200-tick loop was
	# calibrated to the 960 s day; at 14,400 s the bed rate needs ~1,080
	# ticks) — same pattern as _test_energy_rest above.
	var ticks_needed: int = \
		int(ceil(80.0 * Config.DAY_LENGTH_SECONDS / 960.0)) + 10
	var done := false
	for i: int in range(ticks_needed):
		if not mind.tick_unit(u, 1.0):
			done = true
			break
	_check("bed sleep finishes", done)
	_check("bed sleep fully rests", float(u["urges"]["energy"]) >= 95.0)
	_check("left the house", int(u.get("inside_building_id", 0)) == 0)
	_free_world(w)


func _test_no_bed_rough_sleep() -> void:
	# Only a bed-less town hall nearby: the NPC sleeps rough (capped low).
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	mind.interiors = SimInteriors.new(gs)
	gs.add_building({"type": "town_hall", "faction": "humans",
		"position": Vector2(110, 100), "complete": true, "alive": true})
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["energy"] = 5.0
	_check("tired overrides", mind.tick_unit(u, 1.0))
	_check("entered the hall", int(u.get("inside_building_id", 0)) > 0)
	var done := false
	for i: int in range(600):
		if not mind.tick_unit(u, 1.0):
			done = true
			break
	_check("rough sleep finishes", done)
	_check("rough sleep caps low",
		float(u["urges"]["energy"]) <= SimUrges.SLEEP_CAP_ROUGH + 0.01)
	_free_world(w)
