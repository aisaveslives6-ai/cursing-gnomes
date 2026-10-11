extends SceneTree
## Cursing Gnomes — Milo the Doomscroller disaster tests (massive-dev
## 2026-10-08, original content).
##
## Disaster #21: a chibi gnome with glazed eyes and a glowing phone who
## shuffles town to town. 0 dmg; the weapon is the feed — citizens in
## screen-glow range stop working and stare (doomscrolling flag, honored
## by WorkerAI.tick_unit), mood rotting slowly. A soldier closing in yells
## TOUCH GRASS and he flees; when the battery dies he panics for the map
## edge. Singleton. Own stinger (doom_arrive), own sprite, Gazette beats.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_doomscroller.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no audio output.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sfx_seen: Array = []


class _StubCourt:
	var stories: Array = []
	func publish_story(headline: String, body: String, _kind: String) -> void:
		stories.append({"headline": headline, "body": body})


func _initialize() -> void:
	print("=== Cursing Gnomes doomscroller tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_stinger_distinct()
	_test_spawn()
	_test_town_pick_and_announce()
	_test_aura()
	_test_work_hold()
	_test_soldier_flee()
	_test_battery_panic()
	_test_slain_story()
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


## FNV-1a 32-bit checksum: PackedByteArray has no md5 in Godot 4.
static func _checksum(data: PackedByteArray) -> int:
	var h := 2166136261
	for b in data:
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	var combat = SimCombat.new(gs)
	var d = DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	return [gs, d]


func _on_sfx(sfx_name: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(sfx_name)


func _test_def() -> void:
	_check("def: doomscroller in MONSTERS", DisasterSim.MONSTERS.has("doomscroller"))
	var m: Dictionary = DisasterSim.MONSTERS.get("doomscroller", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", -1.0)) == 0.0)
	_check("def: speed 55", float(m.get("speed", 0.0)) == 55.0)
	_check("def: desc non-empty", String(m.get("desc", "")) != "")


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Milo the Doomscroller",
		d._label_for("doomscroller") == "Milo the Doomscroller")
	w[0].queue_free()


func _test_stinger_mapping() -> void:
	_check("doomscroller -> doom_arrive",
		DisasterSim.stinger_for_kind("doomscroller") == "doom_arrive")


func _test_stinger_synth() -> void:
	var am := AudioManager.new()
	var wav: AudioStreamWAV = am._synthesize_sfx("doom_arrive")
	_check("doom_arrive: synthesizes non-null", wav != null)
	if wav == null:
		am.queue_free()
		return
	_check("doom_arrive: has frames", wav.data.size() > 0)
	var dur := float(wav.data.size()) / float(wav.mix_rate)
	_check("doom_arrive: under 1.2s (%.2fs)" % dur, dur <= 1.2)
	_check("doom_arrive: 8-bit mono", wav.format == AudioStreamWAV.FORMAT_8_BITS
		and not wav.stereo)
	am.queue_free()


func _test_stinger_distinct() -> void:
	var am := AudioManager.new()
	var mine: AudioStreamWAV = am._synthesize_sfx("doom_arrive")
	_check("doom_arrive: synth ok for distinct", mine != null)
	if mine == null:
		am.queue_free()
		return
	var mine_sum := _checksum(mine.data)
	var names := ["karen_arrive", "wizard_arrive", "bastard_arrive",
		"gig_arrive", "prophet_arrive", "taxman_arrive", "ooze_arrive",
		"gull_arrive", "moose_arrive", "jesus_arrive",
		"ass_arrive", "lizard_arrive", "cat_arrive", "twister_arrive"]
	var clash := false
	for n in names:
		var w: AudioStreamWAV = am._synthesize_sfx(n)
		if w != null and _checksum(w.data) == mine_sum:
			clash = true
	_check("doom_arrive: distinct from the 14", not clash)
	am.queue_free()


func _test_spawn() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	var u: Dictionary = d.spawn("doomscroller", Vector2(2000, 2000))
	_check("doomscroller spawns", not u.is_empty())
	_check("spawn: job set", String(u.get("job", "")) == "doomscroller")
	_check("spawn: monster faction",
		String(u.get("faction", "")) == DisasterSim.MONSTER_FACTION)
	_check("spawn: emits doom_arrive, not boom",
		_sfx_seen.has("doom_arrive") and not _sfx_seen.has("boom"))
	var u2: Dictionary = d.spawn("doomscroller", Vector2(100, 100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()


func _test_town_pick_and_announce() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.towns[1] = {"position": Vector2(3000, 3000), "name": "Teston"}
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("doomscroller", Vector2(100, 100))
	d._tick_doomscroll(u, 55.0, 1.0)
	_check("town pick: center set", u.has("doomscroll_center"))
	var c: Vector2 = u.get("doomscroll_center", Vector2.ZERO)
	_check("town pick: center near town", c.distance_to(Vector2(3000, 3000)) < 1.0)
	_check("town pick: battery armed",
		float(u.get("doomscroll_battery", 0.0)) > 0.0)
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("town pick: arrival story filed", headlines.has("DOOMSCROLLER SPOTTED"))
	gs.queue_free()


func _citizen(gs: GameState, pos: Vector2, job: String) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"work_state": "gathering", "stress": 0.0,
	})


func _test_aura() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("doomscroller", Vector2(2000, 2000))
	u["doomscroll_center"] = Vector2(2000, 2000)  # already arrived
	u["doomscroll_battery"] = 240.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	var far := _citizen(gs, Vector2(3500, 3500), "worker")
	far["doomscrolling"] = true  # stale flag — aura must self-heal it off
	var guard := _citizen(gs, Vector2(2050, 2050), "soldier")
	d._doomscroll_aura(u, Vector2(2000, 2000), 2.0)
	_check("aura: near citizen doomscrolling", bool(near.get("doomscrolling", false)))
	_check("aura: near citizen work held", String(near.get("work_state", "")) == "idle")
	_check("aura: far citizen flag self-healed", not bool(far.get("doomscrolling", false)))
	_check("aura: soldier keeps discipline", not bool(guard.get("doomscrolling", false)))
	_check("aura: stress climbs", float(near.get("stress", 0.0)) > 0.0)
	gs.queue_free()


func _test_work_hold() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var bs := SimBuildings.new(gs)
	var ai := WorkerAI.new(gs)
	var u := _citizen(gs, Vector2(2000, 2000), "worker")
	u["doomscrolling"] = true
	u["work_state"] = "gathering"
	ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("work: doomscrolling unit stays idle",
		String(u.get("work_state", "")) == "idle")
	var u2 := _citizen(gs, Vector2(2000, 2000), "worker")
	u2["work_state"] = "gathering"
	ai.tick_unit(u2, bs, 1.0 / 60.0)
	_check("work: clean unit not forced idle",
		not bool(u2.get("doomscrolling", false)))
	gs.queue_free()


func _test_soldier_flee() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("doomscroller", Vector2(2000, 2000))
	u["doomscroll_center"] = Vector2(2000, 2000)
	u["doomscroll_battery"] = 240.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["doomscrolling"] = true
	_citizen(gs, Vector2(2060, 2000), "soldier")  # inside flee radius
	d._tick_doomscroll(u, 55.0, 1.0)
	_check("flee: leaving set", bool(u.get("leaving", false)))
	_check("flee: grassed flag", bool(u.get("doomscroll_grassed", false)))
	_check("flee: citizen flag cleared", not bool(near.get("doomscrolling", false)))
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("flee: TOUCH GRASS story filed", headlines.has("DOOMSCROLLER TOUCHES GRASS"))
	gs.queue_free()


func _test_battery_panic() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("doomscroller", Vector2(2000, 2000))
	u["doomscroll_center"] = Vector2(2000, 2000)
	u["doomscroll_battery"] = 0.5
	d._tick_doomscroll(u, 55.0, 1.0)
	_check("battery: panic leave", bool(u.get("leaving", false)))
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("battery: phone-dies story filed", headlines.has("DOOMSCROLLER'S PHONE DIES"))
	gs.queue_free()


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("doomscroller", Vector2(2000, 2000))
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["doomscrolling"] = true
	u["alive"] = false
	d._doomscroll_departed(u)
	_check("slain: flags cleared", not bool(near.get("doomscrolling", false)))
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("slain: logged-off story filed",
		headlines.has("DOOMSCROLLER LOGGED OFF (PERMANENTLY)"))
	gs.queue_free()
