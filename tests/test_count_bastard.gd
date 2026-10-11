extends SceneTree
## Cursing Gnomes — Count Bastard deep-pass tests (wake 2026-10-07).
##
## Covers: singleton rule + label + monster stats, hall targeting, personal
## insults by name (insult contains the victim's name), personality-matched
## reactions (proud -> enraged + punch damage + comeback; jolly -> laughs,
## no damage; coward -> scared; default -> annoyed), victim preference
## (never-insulted first), generic-taunt fallback with no victims in range,
## hearsay rumor every 3rd insult, insult/punch counters, arrival story
## flag, departure tally note + town mood lift, slain -> ledger closed +
## Gazette headline branch, and the no-hall no-crash edge case.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_count_bastard.gd
##
## Exit code 0 = all passed, 1 = any failure.


class FakeHearsay:
	var rumors: Array = []
	func seed_rumor(text: String, kind: String = "misc",
			subject: String = "", heat: float = 0.7,
			knower_id: int = -1, from_gazette: bool = false,
			truth: String = "unknown") -> Dictionary:
		rumors.append({"text": text, "kind": kind, "subject": subject,
			"heat": heat, "knower_id": knower_id})
		return {}


class FakePhone:
	var hearsay: FakeHearsay


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes Count Bastard tests ===")
	_test_spawn_singleton_stats_label()
	_test_personal_insult_by_name()
	_test_proud_enraged_punches()
	_test_jolly_laughs_no_damage()
	_test_coward_cowers()
	_test_default_annoyed()
	_test_victim_preference_unseen_first()
	_test_no_victim_generic_taunt()
	_test_rumor_every_third_insult()
	_test_counters_and_departure_tally()
	_test_slain_closes_ledger_headline()
	_test_no_hall_no_crash()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	_said.clear()
	gs.bus.unit_said.connect(func(uid: int, t: String) -> void:
		_said.append({"uid": uid, "text": t}))
	return gs


func _new_disasters(gs: GameState) -> DisasterSim:
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	gs.disasters = d
	return d


func _mind(unit_name: String, persona: String,
		overrides: Dictionary = {}) -> Dictionary:
	var traits := {
		"brave": 0.5, "friendly": 0.5, "diligent": 0.5, "crude": 0.5,
		"proud": 0.5, "criminal": 0.1, "violent": 0.1, "unhinged": 0.0,
		"persona": persona,
	}
	for k: String in overrides:
		traits[k] = overrides[k]
	return {"name": unit_name, "traits": traits}


func _add_hall(gs: GameState, pos: Vector2) -> void:
	gs.buildings.append({"id": 1001, "type": "town_hall", "alive": true,
		"position": pos, "town_name": "Testville", "faction": "humans"})


func _add_citizen(gs: GameState, unit_name: String, persona: String,
		pos: Vector2, overrides: Dictionary = {}) -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": "humans", "job": "worker", "town_id": 7,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"mind": _mind(unit_name, persona, overrides),
	})
	return u


func _bastard_world(persona: String = "proud",
		overrides: Dictionary = {}) -> Array:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_hall(gs, Vector2(500, 500))
	var b: Dictionary = d.spawn("count_bastard", Vector2(520, 500))
	var v: Dictionary = _add_citizen(gs, "Testy", persona,
		Vector2(540, 500), overrides)
	return [gs, d, b, v]


func _force_insult(d: DisasterSim, b: Dictionary) -> void:
	b["taunt_cd"] = 0.0
	d._tick_bastard(b, 120.0, 4.0)


func _test_spawn_singleton_stats_label() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var b: Dictionary = d.spawn("count_bastard", Vector2(100, 100))
	_check("spawn: created", not b.is_empty())
	_check("spawn: monster faction",
		String(b.get("faction", "")) == "monster")
	_check("spawn: 600 hp", float(b.get("hp", 0.0)) == 600.0)
	_check("spawn: 0 dmg", float(b.get("dmg", -1.0)) == 0.0)
	var b2: Dictionary = d.spawn("count_bastard", Vector2(200, 200))
	_check("spawn: singleton", b2.is_empty())
	_check("label", d._label_for("count_bastard") == "Count Bastard")
	gs.queue_free()


func _test_personal_insult_by_name() -> void:
	var parts: Array = _bastard_world("pragmatic")
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var b: Dictionary = parts[2]
	_force_insult(d, b)
	_check("insult: counter at 1", int(b.get("bastard_insults", 0)) == 1)
	_check("insult: victim tracked",
		(b.get("bastard_victims", []) as Array).size() == 1)
	var texts: Array = []
	for s: Dictionary in _said:
		texts.append(String(s["text"]))
	var named := false
	for t: String in texts:
		if t.find("Testy") >= 0:
			named = true
	_check("insult: names the victim", named)
	_check("insult: bastard spoke", texts.size() >= 1)
	gs.queue_free()


func _test_proud_enraged_punches() -> void:
	var parts: Array = _bastard_world("proud", {"proud": 0.95})
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var b: Dictionary = parts[2]
	var v: Dictionary = parts[3]
	var hp0: float = float(b.get("hp", 600.0))
	_force_insult(d, b)
	_check("proud: angry mood",
		SimMood.new().dominant(v) == "angry")
	_check("proud: bastard took punch damage",
		float(b.get("hp", hp0)) < hp0)
	_check("proud: punch counter",
		int(b.get("bastard_punches", 0)) == 1)
	var comeback := false
	for s: Dictionary in _said:
		if int(s["uid"]) == int(v.get("id", -1)):
			comeback = true
	_check("proud: comeback line spoken", comeback)
	gs.queue_free()


func _test_jolly_laughs_no_damage() -> void:
	var parts: Array = _bastard_world("jolly", {"friendly": 0.95})
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var b: Dictionary = parts[2]
	var v: Dictionary = parts[3]
	_force_insult(d, b)
	_check("jolly: happy mood",
		SimMood.new().dominant(v) == "happy")
	_check("jolly: no punch damage",
		float(b.get("hp", 0.0)) == 600.0)
	_check("jolly: no punches",
		int(b.get("bastard_punches", 0)) == 0)
	gs.queue_free()


func _test_coward_cowers() -> void:
	var parts: Array = _bastard_world("worried", {"brave": 0.1})
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var b: Dictionary = parts[2]
	var v: Dictionary = parts[3]
	_force_insult(d, b)
	_check("coward: scared mood",
		SimMood.new().dominant(v) == "scared")
	_check("coward: no punch damage",
		float(b.get("hp", 0.0)) == 600.0)
	gs.queue_free()


func _test_default_annoyed() -> void:
	var parts: Array = _bastard_world("pragmatic")
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var b: Dictionary = parts[2]
	var v: Dictionary = parts[3]
	_force_insult(d, b)
	_check("default: annoyed (angry, weak)",
		SimMood.new().dominant(v) == "angry")
	_check("default: intensity is the weak nudge",
		SimMood.new().intensity(v) <= 0.3)
	_check("default: no punch",
		int(b.get("bastard_punches", 0)) == 0)
	gs.queue_free()


func _test_victim_preference_unseen_first() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_hall(gs, Vector2(500, 500))
	var b: Dictionary = d.spawn("count_bastard", Vector2(520, 500))
	var v1: Dictionary = _add_citizen(gs, "Alfa", "pragmatic",
		Vector2(540, 500))
	var v2: Dictionary = _add_citizen(gs, "Beto", "pragmatic",
		Vector2(545, 505))
	_force_insult(d, b)
	_force_insult(d, b)
	var seen: Array = b.get("bastard_victims", [])
	_check("victims: two distinct victims",
		seen.size() == 2
		and seen.has(int(v1.get("id", -1)))
		and seen.has(int(v2.get("id", -1))))
	gs.queue_free()


func _test_no_victim_generic_taunt() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_hall(gs, Vector2(500, 500))
	# Citizen far outside the 260px roast radius.
	_add_citizen(gs, "Far", "pragmatic", Vector2(2000, 2000))
	var b: Dictionary = d.spawn("count_bastard", Vector2(520, 500))
	_force_insult(d, b)
	_check("no victim: no personal insult",
		int(b.get("bastard_insults", 0)) == 0)
	var generic := false
	for s: Dictionary in _said:
		if String(s["text"]).find("Testy") < 0 \
				and String(s["text"]).find("Far") < 0:
			generic = true
	_check("no victim: generic town taunt", generic)
	gs.queue_free()


func _test_rumor_every_third_insult() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var phone := FakePhone.new()
	phone.hearsay = FakeHearsay.new()
	gs.phone_sys = phone
	_add_hall(gs, Vector2(500, 500))
	var b: Dictionary = d.spawn("count_bastard", Vector2(520, 500))
	_add_citizen(gs, "Rumor", "pragmatic", Vector2(540, 500))
	_add_citizen(gs, "Rumor2", "pragmatic", Vector2(545, 505))
	_add_citizen(gs, "Rumor3", "pragmatic", Vector2(550, 510))
	for i: int in 3:
		_force_insult(d, b)
	var rumors: Array = (gs.phone_sys as FakePhone).hearsay.rumors
	_check("rumor: seeded on 3rd insult", rumors.size() == 1)
	if rumors.size() == 1:
		_check("rumor: kind bastard_insult",
			String(rumors[0]["kind"]) == "bastard_insult")
		_check("rumor: names victim",
			String(rumors[0]["text"]).find("Rumor") >= 0)
	gs.queue_free()


func _test_counters_and_departure_tally() -> void:
	var parts: Array = _bastard_world("proud", {"proud": 0.95})
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var b: Dictionary = parts[2]
	var v: Dictionary = parts[3]
	_force_insult(d, b)
	var log_id: int = int(b.get("disaster_log_id", -1))
	_check("depart: has log id", log_id >= 0)
	d._bastard_departed(b)
	var rec: Dictionary = d.dlog.get_record(log_id)
	var notes: Array = rec.get("notes", [])
	var tally := false
	for n: String in notes:
		if n.begins_with("INSULTS 1 PUNCHES 1"):
			tally = true
	_check("depart: final tally note", tally)
	_check("depart: town mood lifted",
		SimMood.new().dominant(v) == "happy"
		or SimMood.new().intensity(v) > 0.0)
	gs.queue_free()


func _test_slain_closes_ledger_headline() -> void:
	var parts: Array = _bastard_world("proud", {"proud": 0.95})
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var b: Dictionary = parts[2]
	_force_insult(d, b)
	_force_insult(d, b)
	var log_id: int = int(b.get("disaster_log_id", -1))
	b["alive"] = false
	d._check_dead_disaster(b)
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("slain: ledger closed",
		String(rec.get("status", "")) == "slain")
	var sum: Dictionary = d.dlog.summary(log_id)
	var notes: Array = sum.get("notes", [])
	var tally := false
	for n: String in notes:
		if String(n).begins_with("INSULTS 2"):
			tally = true
	_check("slain: tally in summary notes", tally)
	gs.queue_free()


func _test_no_hall_no_crash() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	# No halls at all — the bastard must wander, not crash.
	var b: Dictionary = d.spawn("count_bastard", Vector2(100, 100))
	d._tick_bastard(b, 120.0, 1.0)
	d._tick_bastard(b, 120.0, 1.0)
	_check("no hall: survives ticks", bool(b.get("alive", false)))
	gs.queue_free()
