extends SceneTree
## Cursing Gnomes — celebration animation deep-pass headless tests.
##
## Covers the 2026-10-08 deep animation pass:
##   1. One-shot stomp fix: ATTACK/HURT (and CELEBRATE) survive the
##      per-frame world-sync set_work_state — previously stomped after a
##      single rendered frame, so battles showed no attack animation.
##   2. CELEBRATE one-shot (HTML _celebrateT parity): the build crew hops
##      with joy for 2.4 s when their building goes live.
##   3. DANCE loop: off-shift citizens dance at the festival plaza during
##      the joy window (the Gazette's promised "Dancing!"), with
##      weight-scaled timing and per-unit phase so crowds stay out of sync.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_celebration.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes celebration tests ===")
	_test_oneshot_survives_sync()
	_test_oneshot_settles()
	_test_celebrate_hops()
	_test_celebrate_death_interrupts()
	_test_dance_loops()
	_test_dance_freeze_position()
	_test_dance_weight_timing()
	_test_dance_crowd_out_of_sync()
	_test_offshift_dance_mapping()
	_test_completion_celebrates_crew()
	_test_completion_ignores_bystanders()
	_test_festival_joy_town()
	_test_offshift_parties_during_festival()
	_test_celebrate_recovers_and_dances()
	_test_stale_party_plan_dropped()
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


func _tick(a: UnitAnimator, secs: float) -> void:
	var n: int = int(secs * 60.0)
	for i: int in n:
		a.tick(1.0 / 60.0)


## --- the stomp fix ----------------------------------------------------------

## The headless-verified bug: play_attack() then one idle sync stomped the
## one-shot back to "idle" — a single rendered frame of attack, forever.
func _test_oneshot_survives_sync() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(3, "gnomes", "soldier", Vector2(500, 500), "m")
	un.set_work_state("idle")
	un.play_attack()
	un.set_work_state("idle")  # what the world sync does next frame
	_check("stomp: attack survives the next sync", un.anim.state == UnitAnimator.ATTACK)
	un.play_hurt()
	un.set_work_state("idle")
	_check("stomp: hurt survives the next sync", un.anim.state == UnitAnimator.HURT)
	un.play_celebrate()
	un.set_work_state("idle")
	_check("stomp: celebrate survives the next sync", un.anim.state == UnitAnimator.CELEBRATE)
	un.queue_free()


## One-shots still release when their clip finishes — the guard must not
## freeze the body on ATTACK forever.
func _test_oneshot_settles() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(4, "gnomes", "soldier", Vector2(500, 500), "m")
	un.set_work_state("idle")
	un.play_attack()
	_tick(un.anim, 0.5)
	un.set_work_state("idle")  # sync resumes driving after the clip
	_check("stomp: attack releases to idle after 0.28s",
		un.anim.state == UnitAnimator.IDLE)
	un.queue_free()


## --- CELEBRATE (HTML _celebrateT parity) -------------------------------------

func _test_celebrate_hops() -> void:
	var a := UnitAnimator.for_uid(11)
	a.set_state(UnitAnimator.CELEBRATE)
	_check("celebrate: one-shot state set", a.state == UnitAnimator.CELEBRATE)
	_tick(a, 0.45)  # mid-hop
	var mid: Dictionary = a.pose()
	_check("celebrate: mid-hop lift is up", float(mid["lift"]) < -3.0)
	var b2 := UnitAnimator.for_uid(11)
	b2.set_state(UnitAnimator.CELEBRATE)
	_tick(b2, 0.02)  # hop boundary — coiled, near ground
	var edge: Dictionary = b2.pose()
	_check("celebrate: hop boundary near ground", float(edge["lift"]) > -2.0)
	_tick(a, 2.4)
	_check("celebrate: settles after 2.4s", a.state == UnitAnimator.IDLE)


func _test_celebrate_death_interrupts() -> void:
	var a := UnitAnimator.for_uid(12)
	a.set_state(UnitAnimator.CELEBRATE)
	a.set_state(UnitAnimator.DEATH)
	_check("celebrate: death interrupts", a.state == UnitAnimator.DEATH)
	_tick(a, 5.0)
	_check("celebrate: death still holds", a.state == UnitAnimator.DEATH)


## --- DANCE (festival loop) ----------------------------------------------------

func _test_dance_loops() -> void:
	var a := UnitAnimator.for_uid(13)
	a.set_state(UnitAnimator.DANCE)
	_tick(a, 5.0)
	_check("dance: still dancing after 5s", a.state == UnitAnimator.DANCE)


## Jeremy's freeze-position law: the dance plays with the node planted —
## the body moves, the position never does.
func _test_dance_freeze_position() -> void:
	var a := UnitAnimator.for_uid(14)
	a.set_state(UnitAnimator.DANCE)
	var lo := 999.0
	var hi := -999.0
	var rock_lo := 999.0
	var rock_hi := -999.0
	for i: int in 120:
		a.tick(1.0 / 60.0)
		var p: Dictionary = a.pose()
		lo = minf(lo, float(p["lift"]))
		hi = maxf(hi, float(p["lift"]))
		rock_lo = minf(rock_lo, float(p["rock"]))
		rock_hi = maxf(rock_hi, float(p["rock"]))
	_check("dance: body bounces in place", hi - lo > 1.0)
	_check("dance: sways side to side", rock_lo < -0.05 and rock_hi > 0.05)
	_check("dance: feet never sink", lo <= 0.01)


## Weight-scaled clock: a gnome bounces through more beats than an ogre in
## the same 3 seconds (Timing for Animation — weight-based timing).
func _test_dance_weight_timing() -> void:
	var gnome := UnitAnimator.for_uid(15)
	gnome.weight = UnitAnimator.weight_for_faction("gnomes")
	var ogre := UnitAnimator.for_uid(16)
	ogre.weight = UnitAnimator.weight_for_faction("ogres")
	gnome.set_state(UnitAnimator.DANCE)
	ogre.set_state(UnitAnimator.DANCE)
	var g_beats := 0
	var o_beats := 0
	var g_prev := 0.0
	var o_prev := 0.0
	for i: int in 180:
		gnome.tick(1.0 / 60.0)
		ogre.tick(1.0 / 60.0)
		var gr: float = float(gnome.pose()["rock"])
		var or_: float = float(ogre.pose()["rock"])
		if g_prev <= 0.0 and gr > 0.0:
			g_beats += 1
		if o_prev <= 0.0 and or_ > 0.0:
			o_beats += 1
		g_prev = gr
		o_prev = or_
	_check("dance: gnome out-dances the ogre", g_beats > o_beats)


## Per-unit phase: two dancers never move in sync.
func _test_dance_crowd_out_of_sync() -> void:
	var a := UnitAnimator.for_uid(21)
	var b := UnitAnimator.for_uid(22)
	a.set_state(UnitAnimator.DANCE)
	b.set_state(UnitAnimator.DANCE)
	_tick(a, 0.3)
	_tick(b, 0.3)
	var pa: Dictionary = a.pose()
	var pb: Dictionary = b.pose()
	_check("dance: crowd out of sync",
		absf(float(pa["rock"]) - float(pb["rock"])) > 0.01)


func _test_offshift_dance_mapping() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(5, "gnomes", "worker", Vector2(500, 500), "m")
	un.set_work_state("off_shift", "", "", "dance")
	_check("dance: off_shift + dance pose -> DANCE", un.anim.state == UnitAnimator.DANCE)
	un.set_work_state("off_shift", "", "", "rest")
	_check("dance: rest pose still maps to IDLE", un.anim.state == UnitAnimator.IDLE)
	un.queue_free()


## --- sim: completion celebration (HTML parity) ---------------------------------

func _make_gs() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	return gs


func _test_completion_celebrates_crew() -> void:
	var gs := _make_gs()
	var bs := SimBuildings.new(gs)
	var b: Dictionary = gs.add_building({"type": "farm", "faction": "gnomes",
		"position": Vector2(1000, 1000), "alive": true, "complete": false,
		"progress": 0.99, "hp": 100.0, "max_hp": 500.0})
	var bid: int = int(b.get("id", -1))
	var crew: Dictionary = gs.add_unit({"faction": "gnomes", "job": "worker",
		"position": Vector2(1010, 1010), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "work_state": "building", "work_building": bid})
	bs.tick_construction(b, 500.0, 1.0)
	_check("celebrate: building completed", bool(b.get("complete", false)))
	_check("celebrate: crew flagged (HTML _celebrateT = 2.4)",
		float(crew.get("_celebrate_t", 0.0)) == 2.4)


func _test_completion_ignores_bystanders() -> void:
	var gs := _make_gs()
	var bs := SimBuildings.new(gs)
	var b: Dictionary = gs.add_building({"type": "farm", "faction": "gnomes",
		"position": Vector2(1000, 1000), "alive": true, "complete": false,
		"progress": 0.99, "hp": 100.0, "max_hp": 500.0})
	var bid: int = int(b.get("id", -1))
	var walker: Dictionary = gs.add_unit({"faction": "gnomes", "job": "worker",
		"position": Vector2(1010, 1010), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "work_state": "idle", "work_building": bid})
	var far_crew: Dictionary = gs.add_unit({"faction": "gnomes", "job": "worker",
		"position": Vector2(3000, 3000), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "work_state": "building", "work_building": 999999})
	bs.tick_construction(b, 500.0, 1.0)
	_check("celebrate: idle bystander not flagged",
		float(walker.get("_celebrate_t", 0.0)) == 0.0)
	_check("celebrate: other site's crew not flagged",
		float(far_crew.get("_celebrate_t", 0.0)) == 0.0)


## --- sim: festival dancing ------------------------------------------------------

func _make_party_world() -> Array:
	var gs := _make_gs()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	gs.day_number = 100
	court.policies.state["last_festival_day"] = 100
	court.policies.state["last_festival_town"] = "Testville"
	gs.towns[1] = {"name": "Testville", "faction": "gnomes",
		"position": Vector2(1000, 1000)}
	return [gs, court]


func _party_unit(gs: GameState, pos: Vector2, uid: int) -> Dictionary:
	return gs.add_unit({"id": uid, "faction": "gnomes", "job": "worker",
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0, "work_state": "off_shift",
		"urges": {"energy": 80.0, "social": 80.0, "mood": 80.0}})


func _test_festival_joy_town() -> void:
	var parts: Array = _make_party_world()
	var court: SimRoyalCourt = parts[1]
	_check("joy: town named in window",
		court.policies.festival_joy_town() == "Testville")
	court.policies.state["last_festival_day"] = 90  # 10 days ago
	_check("joy: empty after the window",
		court.policies.festival_joy_town() == "")
	court.policies.state["last_festival_day"] = 0
	_check("joy: empty with no festival",
		court.policies.festival_joy_town() == "")


func _test_offshift_parties_during_festival() -> void:
	var parts: Array = _make_party_world()
	var gs: GameState = parts[0]
	var ai := WorkerAI.new(gs)
	var u: Dictionary = _party_unit(gs, Vector2(1100, 1000), 42)
	ai.tick_off_shift(u, 1.0)
	var plan: Dictionary = u.get("_downtime", {})
	_check("party: off-shift citizen picks celebrate",
		String(plan.get("plan", "")) == "celebrate")
	var target: Vector2 = plan.get("target", Vector2.ZERO)
	_check("party: plaza is near the town center",
		target.distance_to(Vector2(1000, 1000)) < 190.0)


func _test_celebrate_recovers_and_dances() -> void:
	var parts: Array = _make_party_world()
	var gs: GameState = parts[0]
	var ai := WorkerAI.new(gs)
	var u: Dictionary = _party_unit(gs, Vector2(1100, 1000), 43)
	ai.tick_off_shift(u, 1.0)  # picks the plan
	var plan: Dictionary = u.get("_downtime", {})
	u["position"] = plan.get("target", Vector2(1000, 1000))  # arrive
	var mood0: float = float((u["urges"] as Dictionary).get("mood", 80.0))
	ai.tick_off_shift(u, 1.0)
	_check("party: arrived celebrant dances",
		String(u.get("work_pose", "")) == "dance")
	var mood1: float = float((u["urges"] as Dictionary).get("mood", 80.0))
	_check("party: dancing lifts mood", mood1 > mood0)


func _test_stale_party_plan_dropped() -> void:
	var parts: Array = _make_party_world()
	var gs: GameState = parts[0]
	var court: SimRoyalCourt = parts[1]
	var ai := WorkerAI.new(gs)
	var u: Dictionary = _party_unit(gs, Vector2(1100, 1000), 44)
	ai.tick_off_shift(u, 1.0)
	_check("party: plan picked", String(u.get("_downtime", {}).get("plan", "")) == "celebrate")
	# The festival ends mid-off-shift.
	court.policies.state["last_festival_day"] = 0
	ai.tick_off_shift(u, 1.0)
	_check("party: stale celebrate plan dropped",
		String(u.get("_downtime", {}).get("plan", "")) != "celebrate")
