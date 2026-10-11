extends SceneTree
## Cursing Gnomes — blood & gore tests (HTML rollInjury / bleedRate /
## spawnGore / bloodStains parity).
##
## fix79/index.html: Unit.rollInjury(dmgTaken) sets injured, bleedRate
## (capped 20, +0.6 + dmg/80), bloodTrailCd = 8, then rolls limb loss
## (chance min(0.22, 0.03 + dmg/200); artillery min(0.55, chance*2.8+0.08),
## 25% double loss). Each severed limb: blood bursts, gore limbs, speech,
## bleedRate +6 (max 25), 14 persistent ground stains. bleedRate drains the
## blood pool (rate = bleedRate + 2.5/missing limb + 0.8 if injured); at 0
## the unit bleeds out with a gore burst. Doctors heal hp/blood/bleedRate.
## Godot port:
##   - SimCombat.roll_injury / _tick_bleed / _limbs_missing / _limb_cry
##   - CombatFX.gore (physics pieces, cap 240) / blood_stain (cap 400)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gore.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


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
	gs.setup(["humans"])
	var combat := SimCombat.new(gs)
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary) -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(500, 500))
	return u


## Lightweight unit dict for high-volume statistical tests (bypasses the
## spawner so population caps can't return {} mid-run). roll_injury only
## needs alive/faction/position/id; _ensure_gore_fields fills the rest.
func _mock_unit(i: int) -> Dictionary:
	return {"alive": true, "faction": "humans",
		"position": Vector2(500, 500), "id": 100000 + i}


func _initialize() -> void:
	print("=== Cursing Gnomes blood & gore tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_gore_fields_lazy_init()
	_test_injury_sets_flags()
	_test_bleed_rate_caps()
	_test_limb_loss_chance_bounds()
	_test_artillery_worse_odds()
	_test_double_limb_loss_possible()
	_test_seek_doctor_on_limb_loss()
	_test_limbs_missing_counts()
	_test_limb_cry_voices()
	_test_bleedout_kills()
	_test_bleed_rate_formula()
	_test_healed_amputee_no_bleed()
	_test_doctor_heals_injured()
	_test_fx_gore_cap()
	_test_fx_stain_cap()
	_test_fx_tick_cleans_up()
	_test_fx_gib_spawns_parts()
	_test_fx_gib_cap()
	_test_fx_gib_tick_cleans_up()
	_test_fx_crater_persists()
	_test_fx_crater_cap()
	_test_artillery_death_gibs()
	_test_artillery_impact_craters()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


## Fresh units get the gore fields lazily on first injury touch.
func _test_gore_fields_lazy_init() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _spawn(w)
	_check("fresh unit: no limbs key yet", not u.has("limbs"))
	# De-flaked 2026-10-08: roll_injury severs a random limb, so an unseeded
	# roll can take the left arm and fail the check below spuriously.
	seed(20261008)
	combat.roll_injury(u, 1.0, false)
	_check("after injury: limbs dict exists", u.has("limbs"))
	var limbs: Dictionary = u["limbs"]
	_check("after injury: 4 limbs tracked", limbs.size() == 4)
	_check("after injury: leftArm present",
		bool(limbs.get("leftArm", false)))
	_check("after injury: bleed_rate tracked", u.has("bleed_rate"))
	_check("after injury: blood pool tracked", u.has("blood"))
	_check("after injury: injured flag tracked", u.has("injured"))
	_free_world(w)


## Any survived hit marks the unit injured with an 8 s blood trail.
func _test_injury_sets_flags() -> void:
	seed(777)
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u := _spawn(w)
	var uid: int = int(u.get("id", 0))
	var mhp: float = float(u.get("max_hp", 100.0))
	combat.damage_unit(uid, mhp * 0.1, "ogres", -1, "melee")
	var rec: Dictionary = gs.get_unit(uid)
	_check("survived hit: unit alive", bool(rec.get("alive", false)))
	_check("survived hit: injured = true", bool(rec.get("injured", false)))
	_check("survived hit: blood_trail_cd == 8.0",
		is_equal_approx(float(rec.get("blood_trail_cd", 0.0)), 8.0))
	_check("survived hit: bleed_rate > 0",
		float(rec.get("bleed_rate", 0.0)) > 0.0)
	_free_world(w)


## bleed_rate from hits caps at 20; limb bonuses cap at 25.
func _test_bleed_rate_caps() -> void:
	seed(4242)
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _spawn(w)
	# Tiny hits: chance ~= 0.03, but bleed_rate still accumulates.
	for i: int in range(200):
		combat.roll_injury(u, 1.0, false)
		u["limbs"] = {"leftArm": true, "rightArm": true,
			"leftLeg": true, "rightLeg": true}
	_check("bleed_rate: never exceeds 25",
		float(u.get("bleed_rate", 0.0)) <= 25.0)
	_free_world(w)


## Limb-loss odds land near the HTML 22% at high damage (statistical).
func _test_limb_loss_chance_bounds() -> void:
	seed(20261004)
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var lost := 0
	var trials := 1200
	for t: int in range(trials):
		var u := _mock_unit(t)
		combat.roll_injury(u, 100.0, false)
		var limbs: Dictionary = u["limbs"]
		for k: String in ["leftArm", "rightArm", "leftLeg", "rightLeg"]:
			if not bool(limbs.get(k, true)):
				lost += 1
				break
	var rate: float = float(lost) / float(trials)
	_check("limb loss: rate sane at dmg 100 (0.10..0.35), got %f" % rate,
		rate > 0.10 and rate < 0.35)
	_free_world(w)


## Artillery hits are brutal: ~55% limb loss at high damage.
func _test_artillery_worse_odds() -> void:
	seed(20261004)
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var lost := 0
	var trials := 1200
	for t: int in range(trials):
		var u := _mock_unit(t)
		combat.roll_injury(u, 100.0, true)
		var limbs: Dictionary = u["limbs"]
		for k: String in ["leftArm", "rightArm", "leftLeg", "rightLeg"]:
			if not bool(limbs.get(k, true)):
				lost += 1
				break
	var rate: float = float(lost) / float(trials)
	_check("artillery: rate sane at dmg 100 (0.40..0.70), got %f" % rate,
		rate > 0.40 and rate < 0.70)
	_free_world(w)


## 25% of limb-loss events take 2 limbs — observed over many trials.
func _test_double_limb_loss_possible() -> void:
	seed(999)
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var saw_double := false
	for t: int in range(400):
		var u := _mock_unit(t)
		combat.roll_injury(u, 120.0, true)
		var missing := 0
		var limbs: Dictionary = u["limbs"]
		for k: String in ["leftArm", "rightArm", "leftLeg", "rightLeg"]:
			if not bool(limbs.get(k, true)):
				missing += 1
		if missing >= 2:
			saw_double = true
			break
	_check("double limb loss: observed in 400 artillery trials", saw_double)
	_free_world(w)


## Losing a limb flags the unit to seek a doctor.
func _test_seek_doctor_on_limb_loss() -> void:
	seed(31337)
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := {}
	var lost := false
	for t: int in range(300):
		u = _mock_unit(t)
		combat.roll_injury(u, 120.0, true)
		var limbs: Dictionary = u["limbs"]
		for k: String in ["leftArm", "rightArm", "leftLeg", "rightLeg"]:
			if not bool(limbs.get(k, true)):
				lost = true
				break
		if lost:
			break
	_check("limb loss occurred in 300 trials", lost)
	if lost:
		_check("limb loss: seek_doctor = true",
			bool(u.get("seek_doctor", false)))
	_free_world(w)


## _limbs_missing counts severed limbs.
func _test_limbs_missing_counts() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _spawn(w)
	combat._ensure_gore_fields(u)
	_check("limbs missing: 0 fresh", combat._limbs_missing(u) == 0)
	(u["limbs"] as Dictionary)["leftArm"] = false
	(u["limbs"] as Dictionary)["rightLeg"] = false
	_check("limbs missing: 2 severed", combat._limbs_missing(u) == 2)
	_free_world(w)


## Faction-voiced cries, no emoji (tofu rule).
func _test_limb_cry_voices() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var ogre: String = combat._limb_cry("ogres", "left arm")
	var gnome: String = combat._limb_cry("gnomes", "right leg")
	var human: String = combat._limb_cry("humans", "left leg")
	_check("ogre cry: uppercase label", ogre == "MY LEFT ARM!")
	_check("gnome cry: voice line",
		gnome == "Bloody hell — my right leg!")
	_check("human cry: voice line", human == "Ahh! My left leg!")
	for cry: String in [ogre, gnome, human]:
		_check("cry has no blood emoji: " + cry,
			not cry.contains("🩸"))
	_free_world(w)


## Drained blood pool kills with a gore burst.
func _test_bleedout_kills() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u := _spawn(w)
	var uid: int = int(u.get("id", 0))
	combat._ensure_gore_fields(u)
	u["injured"] = true
	u["bleed_rate"] = 50.0
	u["blood"] = 1.0
	combat._tick_bleed(1.0)
	var rec: Dictionary = gs.get_unit(uid)
	_check("bleedout: unit dead", not bool(rec.get("alive", false)))
	_free_world(w)


## Bleed formula: bleedRate + 2.5/missing limb + 0.8 if injured.
## HTML guard: only ticks while injured or bleedRate > 0.
func _test_bleed_rate_formula() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _spawn(w)
	combat._ensure_gore_fields(u)
	u["injured"] = true
	u["bleed_rate"] = 0.0
	(u["limbs"] as Dictionary)["leftArm"] = false
	(u["limbs"] as Dictionary)["rightLeg"] = false
	combat._tick_bleed(1.0)
	# rate = 0 + 2*2.5 + 0.8 = 5.8 → blood 100 → 94.2.
	_check("bleed formula: 2 missing limbs + injured drain 5.8/s",
		is_equal_approx(float(u.get("blood", 0.0)), 94.2))
	_free_world(w)


## Healed amputees (injured=false, bleed_rate=0) stop bleeding — HTML parity.
func _test_healed_amputee_no_bleed() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _spawn(w)
	combat._ensure_gore_fields(u)
	u["injured"] = false
	u["bleed_rate"] = 0.0
	(u["limbs"] as Dictionary)["leftArm"] = false
	combat._tick_bleed(1.0)
	_check("healed amputee: blood untouched",
		is_equal_approx(float(u.get("blood", 0.0)), 100.0))
	_free_world(w)


## Doctors stabilize limb-loss victims: hp/blood full, bleeding stopped.
func _test_doctor_heals_injured() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var doc: Dictionary = gs.spawner.spawn_unit("humans", "doctor", -1,
		Vector2(500, 500))
	var u := _spawn(w)
	u["position"] = Vector2(510, 500)
	combat._ensure_gore_fields(u)
	u["injured"] = true
	u["seek_doctor"] = true
	u["bleed_rate"] = 12.0
	u["blood"] = 40.0
	u["hp"] = 20.0
	# Limbs stay lost even after healing (permanent, HTML parity).
	(u["limbs"] as Dictionary)["leftLeg"] = false
	combat.tick_medics(0.5)
	_check("doctor: bleed stopped", float(u.get("bleed_rate", 1.0)) == 0.0)
	_check("doctor: blood restored",
		is_equal_approx(float(u.get("blood", 0.0)), 100.0))
	_check("doctor: hp restored",
		is_equal_approx(float(u.get("hp", 0.0)),
			float(u.get("max_hp", 100.0))))
	_check("doctor: injured cleared", not bool(u.get("injured", true)))
	_check("doctor: seek_doctor cleared",
		not bool(u.get("seek_doctor", true)))
	_check("doctor: limb stays lost",
		not bool((u["limbs"] as Dictionary).get("leftLeg", true)))
	_check("doctor: other limbs intact",
		bool((u["limbs"] as Dictionary).get("rightLeg", false)))
	var _doc_id: int = int(doc.get("id", 0))
	_free_world(w)


## Gore pieces respect the 240 cap.
func _test_fx_gore_cap() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	fx.gore(Vector2(100, 100), "limb", 300)
	_check("gore: capped at 240", fx._gore.size() == 240)
	fx.gore(Vector2(100, 100), "chunk", 10)
	_check("gore: stays capped after more", fx._gore.size() == 240)
	fx.free()


## Blood stains respect the 400 cap.
func _test_fx_stain_cap() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	fx.blood_stain(Vector2(100, 100), 500)
	_check("stains: capped at 400", fx._stains.size() == 400)
	fx.free()


## Gore and stains expire after their lifetimes.
func _test_fx_tick_cleans_up() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	fx.gore(Vector2(100, 100), "chunk", 5)
	fx.blood_stain(Vector2(100, 100), 5)
	_check("fx: pieces present", fx._gore.size() == 5)
	_check("fx: stains present", fx._stains.size() == 5)
	fx._tick_gore(61.0)
	fx._tick_stains(80.0)
	_check("fx: gore expired", fx._gore.is_empty())
	_check("fx: stains expired", fx._stains.is_empty())
	fx.free()


## Gibbing spawns 6 chibi parts (head, torso, 2 arms, 2 legs).
func _test_fx_gib_spawns_parts() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	fx.gib(Vector2(200, 200), "humans")
	_check("gib: 6 parts spawned", fx._gibs.size() == 6)
	var parts := {}
	for g: Dictionary in fx._gibs:
		parts[String(g["part"])] = true
	_check("gib: head part present", parts.has("head"))
	_check("gib: torso part present", parts.has("torso"))
	_check("gib: arm part present", parts.has("arm"))
	_check("gib: leg part present", parts.has("leg"))
	fx.free()


## Gibs respect the 60 cap.
func _test_fx_gib_cap() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	for i: int in range(15):
		fx.gib(Vector2(200, 200), "ogres")
	_check("gib: capped at 60", fx._gibs.size() == 60)
	fx.free()


## Gibs expire after their 5 s life.
func _test_fx_gib_tick_cleans_up() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	fx.gib(Vector2(200, 200), "elves")
	_check("gib: parts present", fx._gibs.size() == 6)
	fx._tick_gibs(6.0)
	_check("gib: expired", fx._gibs.is_empty())
	fx.free()


## Craters persist (no aging) and respect the 60 cap.
func _test_fx_crater_persists() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	fx.crater(Vector2(300, 300), 90.0)
	_check("crater: added", fx._craters.size() == 1)
	var c: Dictionary = fx._craters[0]
	_check("crater: radius kept", is_equal_approx(float(c["radius"]), 90.0))
	fx.free()


func _test_fx_crater_cap() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	for i: int in range(80):
		fx.crater(Vector2(i * 10, 100), 90.0)
	_check("crater: capped at 60", fx._craters.size() == 60)
	fx.free()


## Artillery kills emit a gib event with the victim's faction.
func _test_artillery_death_gibs() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var emitted: Array = []
	gs.bus.combat_fx.connect(func(kind: String, _pos: Vector2) -> void:
		emitted.append(kind))
	var u := _spawn(w)
	var uid: int = int(u.get("id", 0))
	combat.damage_unit(uid, 99999.0, "ogres", -1, "cannonball")
	var rec: Dictionary = gs.get_unit(uid)
	_check("artillery kill: unit dead", not bool(rec.get("alive", false)))
	_check("artillery kill: gib event emitted", emitted.has("gib_humans"))
	_free_world(w)


## Cannonball impacts emit a crater event.
func _test_artillery_impact_craters() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var emitted: Array = []
	gs.bus.combat_fx.connect(func(kind: String, _pos: Vector2) -> void:
		emitted.append(kind))
	# Fire a cannonball with splash at a far point (no units there).
	var p: Dictionary = combat.fire_projectile(
		Vector2(0, 0), -1, Vector2(5000, 5000), "cannonball",
		80.0, 180.0, "ogres", 900.0)
	combat._tick_projectiles(30.0)
	_check("cannonball impact: crater event emitted", emitted.has("crater"))
	_free_world(w)
