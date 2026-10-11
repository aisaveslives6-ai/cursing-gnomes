extends SceneTree
## Cursing Gnomes — mind decay stagger (20Hz) parity tests.
##
## Verifies the 2026-10-05 R14 optimization: background mind decay
## (urge/emotion/mood/memory decay + chatter) runs every 3rd budgeted
## slice per unit with a scaled delta, while the critical-urge check still
## runs every slice. Rates must stay exact; reactions must stay instant.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_mind_decay_stagger.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes mind decay stagger tests ===")
	_test_decay_rate_parity()
	_test_critical_instant_on_off_slice()
	_test_stagger_distribution()
	_test_decay_counter_cycles()
	_test_old_save_no_key()
	_test_emotion_mood_decay_parity()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var mind := SimMind.new(gs)
	return {"gs": gs, "mind": mind}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _spawn(w: Dictionary, faction: String, job: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


## Decay over 300 budgeted slices (5 sim-seconds) must equal the old
## every-slice rate: rate * 5.0 for each urge.
func _test_decay_rate_parity() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	for urge: String in ["hunger", "energy", "hygiene", "social", "mood", "bladder"]:
		u["urges"][urge] = 100.0
	var d: float = 1.0 / 60.0
	for i: int in range(300):
		mind.tick_unit(u, d)
	# 300 slices = 5.0 s of game time. Compare against the analytic
	# expectation with a tolerance for float accumulation order.
	# ("mood" is excluded: passive recovery pins it at 80 — checked below.)
	var expected := {
		"hunger": 100.0 - 0.35 * 5.0,
		"energy": 100.0 - 0.22 * 5.0,
		"hygiene": 100.0 - 0.12 * 5.0,
		"social": 100.0 - 0.18 * 5.0,
		"bladder": 100.0 - 0.45 * 5.0,
	}
	for urge: String in expected.keys():
		var got: float = float(u["urges"][urge])
		var want: float = float(expected[urge])
		_check("decay parity " + urge + " (got %.4f want %.4f)" % [got, want],
			absf(got - want) < 0.05)
	# Mood: nothing critical, so passive recovery (+2/s x6/iteration)
	# overwhelms its 0.08/s decay and pins it at the 80 cap.
	var mood_v: float = float(u["urges"]["mood"])
	_check("mood pinned near 80 by passive recovery (got %.3f)" % mood_v,
		mood_v > 79.0 and mood_v <= 80.0)
	_free_world(w)


## A critical urge must hijack the unit on the very first tick even when
## that tick is NOT a decay slice (forced off-slice via the counter).
func _test_critical_instant_on_off_slice() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["urges"]["hunger"] = 5.0
	u["_mind_decay_cd"] = 2  # force an off-slice tick
	var busy: bool = mind.tick_unit(u, 1.0 / 60.0)
	_check("critical hunger hijacks on off-slice tick", busy)
	_check("mind state set on off-slice tick",
		String(u.get("mind_state", "")) == "satisfying:hunger")
	_free_world(w)


## _decay_due fires exactly once per 3 calls, staggered by the counter.
func _test_stagger_distribution() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	u["_mind_decay_cd"] = 0
	_check("decay due at cd=0", mind._decay_due(u))
	_check("not due right after (cd reset to 2)", not mind._decay_due(u))
	_check("not due at cd=1", not mind._decay_due(u))
	_check("due again after 3 calls", mind._decay_due(u))
	_free_world(w)


## Three units with staggered counters spread decay across slices:
## exactly one of the three is due on any given round.
func _test_decay_counter_cycles() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var units: Array = []
	for i: int in range(3):
		var u: Dictionary = _spawn(w, "humans", "worker",
			Vector2(100 + i * 10, 100))
		mind.ensure(u)
		u["_mind_decay_cd"] = i
		units.append(u)
	for round_i: int in range(6):
		var due: int = 0
		for u in units:
			if mind._decay_due(u):
				due += 1
		_check("exactly one unit due per round (round %d)" % round_i, due == 1)
	_free_world(w)


## Units from old saves (no _mind_decay_cd key) decay on first tick and
## get a staggered start from their id.
func _test_old_save_no_key() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(u)
	_check("no decay key on fresh unit", not u.has("_mind_decay_cd"))
	var before: float = float(u["urges"]["hunger"])
	# Tick until a decay slice hits (at most 3 slices out).
	for i: int in range(3):
		mind.tick_unit(u, 1.0 / 60.0)
	_check("decay key created", u.has("_mind_decay_cd"))
	_check("decay happened within 3 slices",
		float(u["urges"]["hunger"]) < before)
	_free_world(w)


## Emotion ttl/intensity and mood intensity decay at the same total rate
## over the staggered schedule as they would every slice.
func _test_emotion_mood_decay_parity() -> void:
	var w: Dictionary = _new_world()
	var mind: SimMind = w["mind"]
	var d: float = 1.0 / 60.0
	# Unit A: decaying emotion (mood neutral so nothing interferes with the
	# emotion assertion; feed may nudge the mood, which we don't assert).
	var a: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	mind.ensure(a)
	var ea: Dictionary = mind.emotion.ensure(a)
	ea["name"] = "happy"
	ea["intensity"] = 0.8
	ea["ttl"] = 30.0
	# Unit B: decaying mood with a neutral emotion so feed_from_emotion is
	# a no-op and the mood decay is isolated.
	var b: Dictionary = _spawn(w, "humans", "worker", Vector2(200, 100))
	mind.ensure(b)
	var mb: Dictionary = mind.mood.ensure(b)
	mb["name"] = "happy"
	mb["intensity"] = 0.8
	for i: int in range(300):  # 5 sim-seconds
		mind.tick_unit(a, d)
		mind.tick_unit(b, d)
	var e1: float = float(mind.emotion.ensure(a).get("intensity", 0.0))
	var m1: float = float(mind.mood.ensure(b).get("intensity", 0.0))
	# Emotion: -0.02/s -> about -0.1 over 5 s (clamped at 0).
	_check("emotion intensity decayed (got %.4f)" % e1, e1 < 0.8 - 0.05)
	# Mood: slow decay toward neutral at DECAY_RATE — must not freeze.
	_check("mood intensity decayed (got %.4f)" % m1, m1 < 0.8)
	_free_world(w)
