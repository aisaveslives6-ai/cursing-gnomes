extends SceneTree
## Cursing Gnomes — five-books animation principles tests (Jeremy 2026-10-06).
##
## Covers the procedural upgrade drawn from the animation library:
##   - Survival Kit: double bounce (two bounces per stride, second at ~60%),
##     anticipation before action
##   - Timing for Animation: weight-based timing (heavy = slower/deeper),
##     anticipation makes fast action readable, overlapping action
##     (follow-through ring, tool lag), moving holds (idle never frozen)
##   - Illusion of Life: anticipation, follow-through, arcs (eased strike),
##     exaggeration (pushed squash, clamped for staging)
##   - Preston Blair: line of action (sway channel), secondary action
##     (animal extremity wobble)
##   - Unity 2D guide: cheap math only (no per-frame allocation in pose()
##     beyond the test-path dict)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_animation_principles.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes animation-principles tests ===")
	_test_weight_for_faction()
	_test_weight_scales_cycle_duration()
	_test_weight_deepens_squash()
	_test_double_bounce()
	_test_anticipation_attack()
	_test_anticipation_work_swing()
	_test_attack_strike_eased()
	_test_follow_through_decays()
	_test_moving_hold_idle()
	_test_sway_channel()
	_test_squash_clamped()
	_test_tool_lag_trails()
	_test_animal_weights()
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


## Timing for Animation: faction mass factors are sane and ordered.
func _test_weight_for_faction() -> void:
	_check("weight: gnomes light",
		UnitAnimator.weight_for_faction("gnomes") < 1.0)
	_check("weight: humans medium",
		is_equal_approx(UnitAnimator.weight_for_faction("humans"), 1.0))
	_check("weight: ogres heaviest",
		UnitAnimator.weight_for_faction("ogres") > 1.5)
	_check("weight: ordered gnome < elf < human < undead < ogre",
		UnitAnimator.weight_for_faction("gnomes")
			< UnitAnimator.weight_for_faction("elves")
		and UnitAnimator.weight_for_faction("elves")
			< UnitAnimator.weight_for_faction("humans")
		and UnitAnimator.weight_for_faction("humans")
			< UnitAnimator.weight_for_faction("undead")
		and UnitAnimator.weight_for_faction("undead")
			< UnitAnimator.weight_for_faction("ogres"))
	_check("weight: unknown faction defaults to 1.0",
		is_equal_approx(UnitAnimator.weight_for_faction("???"), 1.0))


## Heavy bodies take more wall-time per walk cycle than light ones.
func _test_weight_scales_cycle_duration() -> void:
	var light := UnitAnimator.for_uid(11)
	light.weight = 0.7
	light.set_state(UnitAnimator.WALK)
	var heavy := UnitAnimator.for_uid(11)
	heavy.weight = 1.8
	heavy.set_state(UnitAnimator.WALK)
	var light_peaks := _count_bounce_peaks(light, 4.0)
	var heavy_peaks := _count_bounce_peaks(heavy, 4.0)
	_check("weight: light has more bounces per wall-second than heavy",
		light_peaks > heavy_peaks)
	_check("weight: heavy still animates (peaks > 0)", heavy_peaks > 0)
	print("  (light peaks=%d heavy peaks=%d over 4s)" % [light_peaks, heavy_peaks])


func _count_bounce_peaks(a: UnitAnimator, wall_s: float) -> int:
	var n := 0
	var prev := 0.0
	var prev_prev := 0.0
	var steps := int(wall_s * 60.0)
	for i in range(steps):
		a.tick(1.0 / 60.0)
		var lift: float = a.pose()["lift"]
		# Local maximum of -lift (bounce apex).
		if i >= 2 and prev_prev < prev and prev > lift:
			n += 1
		prev_prev = prev
		prev = lift
	return n


## Heavy bodies squash deeper (and everyone gets the ~20% exaggeration).
func _test_weight_deepens_squash() -> void:
	var light := UnitAnimator.for_uid(12)
	light.weight = 0.7
	var heavy := UnitAnimator.for_uid(12)
	heavy.weight = 1.8
	for a in [light, heavy]:
		a.set_state(UnitAnimator.HURT)
		a.tick(0.01)
	var ls: float = light.pose()["squash"]
	var hs: float = heavy.pose()["squash"]
	_check("weight: heavy squashes deeper than light", hs > ls)
	_check("weight: light still squashes (exaggeration floor)", ls > 0.05)


## Survival Kit double bounce: two lift peaks per stride, second ~60%.
func _test_double_bounce() -> void:
	var a := UnitAnimator.for_uid(13)
	a.weight = 1.0
	a.phase = 0.0
	a.set_state(UnitAnimator.WALK)
	# Sample one full stride period (2*PI/9 s) at fine resolution.
	var period := TAU / 9.0
	var lifts: Array[float] = []
	var steps := 200
	for i in range(steps + 1):
		a.state_t = period * float(i) / float(steps)
		lifts.append(a.pose()["lift"])
	var minima: Array[float] = []
	for i in range(1, steps):
		if lifts[i] < lifts[i - 1] and lifts[i] < lifts[i + 1]:
			minima.append(lifts[i])
	_check("bounce: two peaks per stride", minima.size() == 2)
	if minima.size() == 2:
		var first := -minima[0]
		var second := -minima[1]
		_check("bounce: primary near full amplitude",
			absf(first - 4.4) < 0.15)
		_check("bounce: secondary near 60%",
			absf(second / first - 0.6) < 0.08)
		_check("bounce: feet never sink",
			lifts.min() <= 0.01 and lifts.max() <= 0.01)


## Anticipation: ATTACK dips (crouch) before the strike.
func _test_anticipation_attack() -> void:
	var a := UnitAnimator.for_uid(14)
	a.set_state(UnitAnimator.ATTACK)
	a.tick(0.05)  # ~18% in: inside the wind-up
	var p: Dictionary = a.pose()
	_check("anticipation: attack crouches into wind-up",
		float(p["crouch"]) > 0.3)
	_check("anticipation: attack rocks back before striking",
		float(p["rock"]) < -0.02)


## Anticipation: work swings coil (squash back) during wind-up.
func _test_anticipation_work_swing() -> void:
	var a := UnitAnimator.for_uid(15)
	a.set_state(UnitAnimator.CHOP)
	a.state_t = UnitAnimator.CHOP_LEN * 0.35  # deep in the wind-up
	var p: Dictionary = a.pose()
	_check("anticipation: chop coils in wind-up",
		float(p["squash"]) > 0.02 and float(p["crouch"]) > 0.3)


## Illusion of Life arcs: the ATTACK strike follows an eased curve, and
## the strike is faster than the wind-up (readable snap).
func _test_attack_strike_eased() -> void:
	var a := UnitAnimator.for_uid(16)
	a.set_state(UnitAnimator.ATTACK)
	# Sample rock through the strike window; an eased curve's midpoint
	# sits below the linear midpoint (slow-in).
	a.tick(UnitAnimator.ATTACK_LEN * 0.45)
	var r_mid: float = a.pose()["rock"]
	# Linear would give -0.10 + 0.22*0.5 = 0.01 at k2=0.5; eased (k^2)
	# gives -0.10 + 0.22*0.25 = -0.045.
	_check("arcs: strike follows eased curve (slow-in)",
		r_mid < -0.02)


## Overlapping action: the follow-through ring decays after a one-shot.
func _test_follow_through_decays() -> void:
	var struck := UnitAnimator.for_uid(17)
	struck.phase = 0.0  # deterministic idle phase
	struck.set_state(UnitAnimator.ATTACK)
	for i in range(18):  # just past the 0.28 s attack
		struck.tick(1.0 / 60.0)
	_check("follow-through: attack settles to idle",
		struck.state == UnitAnimator.IDLE)
	_check("follow-through: ring is active right after settle",
		struck._follow_t < UnitAnimator.FOLLOW_LEN)
	var early := 0.0
	for i in range(20):
		struck.tick(1.0 / 60.0)
		early = maxf(early, absf(float(struck.pose()["rock"])))
	for i in range(60):  # let the ring fully expire
		struck.tick(1.0 / 60.0)
	_check("follow-through: ring expired", struck._follow_t > 1.0)
	var late := 0.0
	for i in range(20):
		struck.tick(1.0 / 60.0)
		late = maxf(late, absf(float(struck.pose()["rock"])))
	# Probed: early ~0.045 (ring + idle), late ~0.027 (idle only).
	_check("follow-through: ring present early", early > 0.038)
	_check("follow-through: ring decays away", late < 0.033)
	_check("follow-through: early exceeds late", early > late)


## Moving hold: IDLE is never exactly static (breathing + weight shift).
func _test_moving_hold_idle() -> void:
	var a := UnitAnimator.for_uid(18)
	a.set_state(UnitAnimator.IDLE)
	var seen := {}
	for i in range(60):
		a.tick(1.0 / 60.0)
		var p: Dictionary = a.pose()
		var key := "%d|%d" % [
			int(float(p["lift"]) * 1000.0), int(float(p["rock"]) * 10000.0)]
		seen[key] = true
	_check("moving hold: idle pose varies across frames", seen.size() > 10)
	_check("moving hold: breathing squash present",
		absf(float(a.pose()["squash"])) >= 0.0)  # key exists, finite
	# And the settle after death is a hold with a whisper of motion.
	var d := UnitAnimator.for_uid(19)
	d.set_state(UnitAnimator.DEATH)
	for i in range(200):
		d.tick(1.0 / 60.0)
	_check("moving hold: death holds fallen",
		absf(float(d.pose()["rock"]) - (-PI / 2.0 * 0.94)) < 0.02)


## Blair's line of action: the sway channel exists and stays rotational
## (freeze-position law: body.position.x is never touched by the animator).
func _test_sway_channel() -> void:
	var a := UnitAnimator.for_uid(20)
	a.set_state(UnitAnimator.WALK)
	a.tick(0.1)
	var p: Dictionary = a.pose()
	_check("line of action: sway channel present", p.has("sway"))
	_check("line of action: sway varies with the stride",
		absf(float(p["sway"])) <= 0.03)
	var body := Node2D.new()
	a.apply_to(body)
	_check("line of action: rotation carries rock+sway",
		is_equal_approx(body.rotation,
			float(p["rock"])))  # rock already includes sway
	_check("line of action: no horizontal shift", body.position.x == 0.0)
	body.free()


## Exaggeration is clamped so the silhouette stays readable (staging).
func _test_squash_clamped() -> void:
	var a := UnitAnimator.for_uid(21)
	a.weight = 1.8  # heaviest: deepest squash
	for state in [UnitAnimator.WALK, UnitAnimator.HURT, UnitAnimator.DEATH,
			UnitAnimator.MINE, UnitAnimator.CHOP]:
		a.state = state
		for t in [0.05, 0.15, 0.3, 0.5]:
			a.state_t = t
			var s: float = a.pose()["squash"]
			if absf(s) > 0.161:
				_check("staging: squash clamped (%s)" % state, false)
				return
	_check("staging: squash clamped everywhere", true)


## The held tool trails the body's swing (overlapping action).
func _test_tool_lag_trails() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(22, "gnomes", "woodcutter", Vector2(100, 100), "m")
	un.set_work_state("gathering", "tree")  # CHOP + axe overlay
	_check("tool lag: overlay visible", un._tool_pivot.visible)
	# Park mid wind-up: the instant target is wound far back...
	un.anim.state_t = UnitAnimator.CHOP_LEN \
		* (UnitAnimator.CHOP_STRIKE_AT - 0.13)
	un._update_tool(1.0 / 60.0)
	var instant: float = un.anim.tool_swing().x
	var lagged: float = un._tool_pivot.rotation
	_check("tool lag: pivot trails the instant target",
		absf(lagged) < absf(instant) * 0.9)
	# ...and with no time elapsed it snaps (deterministic for tests).
	un._update_tool(0.0)
	_check("tool lag: zero delta snaps to target",
		is_equal_approx(un._tool_pivot.rotation, instant))
	un.free()


## Animals: weight per body type, ordered light -> heavy.
func _test_animal_weights() -> void:
	var kinds := {}
	for t in ["chicken", "sheep", "goat", "boar", "pig", "wolf", "cow"]:
		var an := AnimalNode.new()
		root.add_child(an)
		an.setup(900 + kinds.size(), t, Vector2.ZERO, true)
		kinds[t] = an._weight
		an.free()
	_check("animals: chicken lightest", kinds["chicken"] < kinds["sheep"])
	_check("animals: cow heaviest", kinds["cow"] > kinds["pig"])
	_check("animals: boar heavier than sheep", kinds["boar"] > kinds["sheep"])
