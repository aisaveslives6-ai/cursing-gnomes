extends SceneTree
## Cursing Gnomes — Chad the MLM Bro disaster tests (dedicated-porting
## 2026-10-08, original content).
##
## Disaster #22: a chibi gnome in a cheap navy suit with a briefcase full
## of "opportunity" and a blinding white grin. 0 dmg; the weapon is the
## pitch — citizens in aura range join his downline (hustling flag,
## honored by WorkerAI.tick_unit), pay a starter-kit fee from the faction
## treasury (capped), and recruit their neighbors — a pyramid scheme that
## walks. Soldiers see through the pitch; market saturation (cap or timer)
## sends him home. Singleton. Own stinger (mlm_arrive), own sprite,
## Gazette beats.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_mlm_bro.gd
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
	print("=== Cursing Gnomes MLM bro tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_stinger_distinct()
	_test_spawn()
	_test_town_pick_and_announce()
	_test_aura()
	_test_recruit_and_cap()
	_test_work_hold()
	_test_soldier_flee()
	_test_saturation()
	_test_slain_story()
	_test_moved_on_story()
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
	_check("def: mlm_bro in MONSTERS", DisasterSim.MONSTERS.has("mlm_bro"))
	var m: Dictionary = DisasterSim.MONSTERS.get("mlm_bro", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", -1.0)) == 0.0)
	_check("def: speed 75", float(m.get("speed", 0.0)) == 75.0)
	_check("def: desc non-empty", String(m.get("desc", "")) != "")
	_check("def: not-a-pyramid-scheme gag in desc",
		String(m.get("desc", "")).to_lower().find("pyramid") >= 0)


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Chad the MLM Bro",
		d._label_for("mlm_bro") == "Chad the MLM Bro")
	w[0].queue_free()


func _test_stinger_mapping() -> void:
	_check("mlm_bro -> mlm_arrive",
		DisasterSim.stinger_for_kind("mlm_bro") == "mlm_arrive")


func _test_stinger_synth() -> void:
	var am := AudioManager.new()
	var wav: AudioStreamWAV = am._synthesize_sfx("mlm_arrive")
	_check("mlm_arrive: synthesizes non-null", wav != null)
	if wav == null:
		am.queue_free()
		return
	_check("mlm_arrive: has frames", wav.data.size() > 0)
	var dur := float(wav.data.size()) / float(wav.mix_rate)
	_check("mlm_arrive: under 1.2s (%.2fs)" % dur, dur <= 1.2)
	_check("mlm_arrive: 8-bit mono", wav.format == AudioStreamWAV.FORMAT_8_BITS
		and not wav.stereo)
	am.queue_free()


func _test_stinger_distinct() -> void:
	var am := AudioManager.new()
	var mine: AudioStreamWAV = am._synthesize_sfx("mlm_arrive")
	_check("mlm_arrive: synth ok for distinct", mine != null)
	if mine == null:
		am.queue_free()
		return
	var mine_sum := _checksum(mine.data)
	var names := ["karen_arrive", "wizard_arrive", "bastard_arrive",
		"gig_arrive", "prophet_arrive", "taxman_arrive", "ooze_arrive",
		"gull_arrive", "moose_arrive", "jesus_arrive",
		"ass_arrive", "lizard_arrive", "cat_arrive", "twister_arrive",
		"doom_arrive", "warranty_arrive"]
	var clash := false
	for n in names:
		var w: AudioStreamWAV = am._synthesize_sfx(n)
		if w != null and _checksum(w.data) == mine_sum:
			clash = true
	_check("mlm_arrive: distinct from the 16", not clash)
	am.queue_free()


func _test_spawn() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	var u: Dictionary = d.spawn("mlm_bro", Vector2(2000, 2000))
	_check("mlm_bro spawns", not u.is_empty())
	_check("spawn: job set", String(u.get("job", "")) == "mlm_bro")
	_check("spawn: monster faction",
		String(u.get("faction", "")) == DisasterSim.MONSTER_FACTION)
	_check("spawn: emits mlm_arrive, not boom",
		_sfx_seen.has("mlm_arrive") and not _sfx_seen.has("boom"))
	var u2: Dictionary = d.spawn("mlm_bro", Vector2(100, 100))
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
	var u: Dictionary = d.spawn("mlm_bro", Vector2(100, 100))
	d._tick_mlm(u, 75.0, 1.0)
	_check("town pick: center set", u.has("mlm_center"))
	var c: Vector2 = u.get("mlm_center", Vector2.ZERO)
	_check("town pick: center near town", c.distance_to(Vector2(3000, 3000)) < 1.0)
	_check("town pick: visit timer armed",
		float(u.get("mlm_visit_left", 0.0)) > 0.0)
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("town pick: arrival story filed", headlines.has("MLM BRO SPOTTED"))
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
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	var u: Dictionary = d.spawn("mlm_bro", Vector2(2000, 2000))
	u["mlm_center"] = Vector2(2000, 2000)  # already arrived
	u["mlm_visit_left"] = 300.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	var far := _citizen(gs, Vector2(3500, 3500), "worker")
	far["hustling"] = true  # stale flag — aura must self-heal it off
	var guard := _citizen(gs, Vector2(2050, 2050), "soldier")
	d._mlm_aura(u, Vector2(2000, 2000), 3.0)
	_check("aura: near citizen hustling", bool(near.get("hustling", false)))
	_check("aura: near citizen work held", String(near.get("work_state", "")) == "idle")
	_check("aura: far citizen flag self-healed", not bool(far.get("hustling", false)))
	_check("aura: soldier keeps discipline", not bool(guard.get("hustling", false)))
	_check("aura: starter kit skimmed from treasury",
		gold_before - gs.resources.get_amount("humans", "gold") >= 8.0)
	_check("aura: downline counter bumped", int(u.get("mlm_hustlers", 0)) >= 1)
	gs.queue_free()


func _test_recruit_and_cap() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	var u: Dictionary = d.spawn("mlm_bro", Vector2(2000, 2000))
	var mood := SimMood.new()
	# Recruit up to the cap via the direct path (chain path is RNG-gated).
	# (Seed under the storage cap: add_resource without ignore_cap clamps.)
	for i in range(DisasterSim.MLM_MAX_HUSTLERS + 4):
		var c := _citizen(gs, Vector2(2000 + i * 10, 2000), "worker")
		d._mlm_recruit(u, c, mood)
	_check("cap: downline never exceeds MLM_MAX_HUSTLERS",
		int(u.get("mlm_hustlers", 0)) == DisasterSim.MLM_MAX_HUSTLERS)
	var skimmed: float = gold_before - gs.resources.get_amount("humans", "gold")
	_check("cap: skim capped at MLM_MAX_SKIM",
		skimmed <= DisasterSim.MLM_MAX_SKIM + 0.001)
	_check("cap: skim equals cap * starter kit",
		absf(skimmed - DisasterSim.MLM_MAX_SKIM) < 0.001)
	# Broke faction: skim clamps at 0, never negative.
	var w2 := _make_world()
	var gs2: GameState = w2[0]
	var d2 = w2[1]
	gs2.resources.add_resource("humans", "gold", 3.0, true)
	var u2: Dictionary = d2.spawn("mlm_bro", Vector2(2000, 2000))
	d2._mlm_recruit(u2, _citizen(gs2, Vector2(2050, 2000), "worker"), SimMood.new())
	_check("broke: gold never goes negative",
		gs2.resources.get_amount("humans", "gold") >= 0.0)
	gs.queue_free()
	gs2.queue_free()


func _test_work_hold() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var bs := SimBuildings.new(gs)
	var ai := WorkerAI.new(gs)
	var u := _citizen(gs, Vector2(2000, 2000), "worker")
	u["hustling"] = true
	u["work_state"] = "gathering"
	ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("work: hustling unit stays idle",
		String(u.get("work_state", "")) == "idle")
	var u2 := _citizen(gs, Vector2(2000, 2000), "worker")
	u2["work_state"] = "gathering"
	ai.tick_unit(u2, bs, 1.0 / 60.0)
	_check("work: clean unit not flagged hustling",
		not bool(u2.get("hustling", false)))
	gs.queue_free()


func _test_soldier_flee() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("mlm_bro", Vector2(2000, 2000))
	u["mlm_center"] = Vector2(2000, 2000)
	u["mlm_visit_left"] = 300.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["hustling"] = true
	_citizen(gs, Vector2(2060, 2000), "soldier")  # inside flee radius
	d._tick_mlm(u, 75.0, 1.0)
	_check("flee: leaving set", bool(u.get("leaving", false)))
	_check("flee: fled flag", bool(u.get("mlm_fled", false)))
	_check("flee: citizen flag cleared", not bool(near.get("hustling", false)))
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("flee: DEBUNKED story filed", headlines.has("MLM BRO DEBUNKED"))
	gs.queue_free()


func _test_saturation() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("mlm_bro", Vector2(2000, 2000))
	u["mlm_center"] = Vector2(2000, 2000)
	u["mlm_visit_left"] = 0.5
	u["mlm_hustlers"] = 4
	d._tick_mlm(u, 75.0, 1.0)
	_check("saturation: leaving set", bool(u.get("leaving", false)))
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("saturation: MARKET SATURATED story filed",
		headlines.has("MARKET SATURATED"))
	gs.queue_free()


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("mlm_bro", Vector2(2000, 2000))
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["hustling"] = true
	u["alive"] = false
	d._mlm_departed(u)
	_check("slain: flags cleared", not bool(near.get("hustling", false)))
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("slain: CANCELLED story filed",
		headlines.has("MLM BRO CANCELLED"))
	gs.queue_free()


func _test_moved_on_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("mlm_bro", Vector2(2000, 2000))
	u["mlm_hustlers"] = 3
	d._mlm_departed(u)  # alive, not fled -> moved on
	var headlines: Array = []
	for s in court.stories:
		headlines.append(String(s.get("headline", "")))
	_check("departed: MOVES ON story filed", headlines.has("MLM BRO MOVES ON"))
	gs.queue_free()
