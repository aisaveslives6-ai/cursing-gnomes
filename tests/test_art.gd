extends SceneTree
## Cursing Gnomes — art port + animation-law headless tests.
##
## Covers: every unit sprite key resolves to an extracted PNG, job tags and
## building art exist, the UnitAnimator state machine (transitions), and
## Jeremy's freeze-position test (walk cycle plays with position fixed).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_art.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes art & animation tests ===")
	_test_unit_sprite_keys()
	_test_archetypes()
	_test_job_tags()
	_test_building_art()
	_test_animator_transitions()
	_test_freeze_position()
	_test_idle_moving_bounces()
	await _test_vertical_movement_detected()
	_test_gender_deterministic()
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


## Every faction x archetype x gender x variant key has an extracted PNG.
func _test_unit_sprite_keys() -> void:
	var missing: Array[String] = []
	for faction: String in ["gnome", "human", "elf", "ogre"]:
		for arch: String in ["worker", "warrior", "ranger", "mage"]:
			for g: String in ["m", "f"]:
				for v: int in [0, 1]:
					var key: String = "%s_%s_%s%d" % [faction, arch, g, v]
					var path: String = "res://assets/art/units/%s.png" % key
					if not ResourceLoader.exists(path):
						missing.append(key)
	_check("art: all 96 unit sprites extracted", missing.is_empty())


func _test_archetypes() -> void:
	_check("arch: doctor->mage", Art.archetype_for_job("doctor") == "mage")
	_check("arch: soldier->warrior",
		Art.archetype_for_job("soldier") == "warrior")
	_check("arch: firefighter->worker (HTML regex has no match -> worker)",
		Art.archetype_for_job("firefighter") == "worker")
	_check("arch: archer->ranger",
		Art.archetype_for_job("archer") == "ranger")
	_check("arch: woodcutter->worker",
		Art.archetype_for_job("woodcutter") == "worker")
	_check("arch: builder->worker",
		Art.archetype_for_job("builder") == "worker")
	# appearance_key is deterministic per unit.
	var k1: String = Art.appearance_key("gnomes", "woodcutter", 42, "m")
	var k2: String = Art.appearance_key("gnomes", "woodcutter", 42, "m")
	_check("art: appearance key deterministic", k1 == k2)
	_check("art: appearance key resolves",
		ResourceLoader.exists("res://assets/art/units/%s.png" % k1))


func _test_job_tags() -> void:
	var missing: Array[String] = []
	for job: String in JobDefs.JOBS.keys():
		var t: Texture2D = Art.job_tag(job)
		if t == null:
			missing.append(job)
	_check("art: every job has a tag icon", missing.is_empty())


func _test_building_art() -> void:
	for btype: String in ["town_hall", "house", "guard_tower", "barracks",
			"gate", "wall"]:
		_check("art: building %s has art" % btype,
			Art.building_texture(btype) != null)
	# Types with no source art fall back to programmer silhouettes.
	_check("art: farm has no source art (programmer fallback)",
		Art.building_texture("farm") == null)
	_check("art: trees extracted",
		Art.tree_texture(Vector2(100, 100)) != null)


## State machine: one-shots play once and settle; death holds forever.
func _test_animator_transitions() -> void:
	var a := UnitAnimator.for_uid(7)
	_check("anim: starts idle", a.state == UnitAnimator.IDLE)
	a.set_state(UnitAnimator.WALK)
	_check("anim: walk set", a.state == UnitAnimator.WALK)
	# ATTACK plays 0.28 s then settles back to idle (not moving).
	a.set_state(UnitAnimator.ATTACK)
	for i: int in range(40):
		a.tick(1.0 / 60.0)
	_check("anim: attack settles to idle", a.state == UnitAnimator.IDLE)
	# HURT while moving settles back to walk.
	a.moving = true
	a.set_state(UnitAnimator.HURT)
	for i: int in range(60):
		a.tick(1.0 / 60.0)
	_check("anim: hurt settles to walk", a.state == UnitAnimator.WALK)
	# DEATH plays once, holds, and can't be interrupted.
	a.moving = false
	a.set_state(UnitAnimator.DEATH)
	for i: int in range(120):
		a.tick(1.0 / 60.0)
	_check("anim: death holds", a.state == UnitAnimator.DEATH)
	a.set_state(UnitAnimator.WALK)
	_check("anim: death uninterruptible", a.state == UnitAnimator.DEATH)
	# Death pose is actually fallen (rock near -PI/2).
	var p: Dictionary = a.pose()
	_check("anim: death pose fallen",
		absf(float(p["rock"]) - (-PI / 2.0 * 0.94)) < 0.01)


## Jeremy's freeze-position test: the WALK cycle plays with the node planted.
## Position must not move; the Body must bounce (cycle actually plays).
func _test_freeze_position() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(3, "gnomes", "woodcutter", Vector2(500, 500), "m")
	var body: Node2D = un.get_node("Body")
	un.anim.set_state(UnitAnimator.WALK)
	var lifts: Array[float] = []
	for i: int in range(120):  # 2 s at 60 Hz
		un.anim.tick(1.0 / 60.0)
		un.anim.apply_to(body)
		lifts.append(body.position.y)
	_check("freeze: node position fixed",
		un.position == Vector2(500, 500))
	_check("freeze: body never shifts horizontally",
		body.position.x == 0.0)
	var lo: float = lifts.min()
	var hi: float = lifts.max()
	_check("freeze: walk cycle actually plays (lift oscillates)",
		hi - lo > 1.0)
	_check("freeze: bounce only goes up (feet never sink)",
		hi <= 0.01)
	un.free()


## Jeremy 2026-10-06: an "idle"-declared unit that is actually moving must
## play the walk bounce, never fidget-slide. (Boddle the gnome wandered
## while the sim left work_state "idle".) Actual displacement always wins
## over the declared idle — but one-shots, work loops, and death are never
## interrupted by the override.
func _test_idle_moving_bounces() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(3, "gnomes", "worker", Vector2(500, 500), "m")
	# World sync declares idle while the unit stands still.
	un.anim.moving = false
	un.set_work_state("idle")
	_check("idle+still: animator idle", un.anim.state == UnitAnimator.IDLE)
	# The unit really travels (what _process measures each frame).
	un.anim.moving = true
	un.set_work_state("idle")
	_check("idle+moving: animator walks (bounce)",
		un.anim.state == UnitAnimator.WALK)
	# The bounce actually plays: lift oscillates over a few ticks.
	var lifts: Array[float] = []
	for i: int in range(60):
		un.anim.tick(1.0 / 60.0)
		var p: Dictionary = un.anim.pose()
		lifts.append(float(p["lift"]))
	_check("idle+moving: bounce cycle oscillates",
		lifts.max() - lifts.min() > 1.0)
	# Stops again -> back to idle.
	un.anim.moving = false
	un.set_work_state("idle")
	_check("idle+stopped: animator idle again",
		un.anim.state == UnitAnimator.IDLE)
	# A declared idle at rest resets work loops, as before.
	un.anim.moving = false
	un.anim.set_state(UnitAnimator.HAMMER)
	un.set_work_state("idle")
	_check("idle+still: work loop resets to idle",
		un.anim.state == UnitAnimator.IDLE)
	# One-shots own the body until they settle (Jeremy 2026-10-08: the old
	# per-frame sync stomped ATTACK after a single rendered frame, so
	# battles showed no attack animation at all). Travel wins after the
	# clip releases; death never yields.
	un.anim.moving = true
	un.anim.set_state(UnitAnimator.ATTACK)
	un.set_work_state("idle")
	_check("attack+moving: one-shot owns the body",
		un.anim.state == UnitAnimator.ATTACK)
	for i: int in range(30):
		un.anim.tick(1.0 / 60.0)
	un.set_work_state("idle")
	_check("attack+moving: travel wins after the clip",
		un.anim.state == UnitAnimator.WALK)
	# Death is terminal even if the corpse slides.
	un.anim.set_state(UnitAnimator.DEATH)
	un.set_work_state("idle")
	_check("death+moving: death holds",
		un.anim.state == UnitAnimator.DEATH)
	un.free()


## The old movement check was x-only: a unit traveling straight up/down
## (dx ~ 0) read as "not moving" and fidget-slid. Full 2D displacement
## must count.
func _test_vertical_movement_detected() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(4, "gnomes", "worker", Vector2(500, 500), "m")
	await process_frame
	await process_frame
	_check("still: not moving", not un.anim.moving)
	# Straight up: dx == 0, dy large.
	un.position = Vector2(500, 400)
	await process_frame
	_check("vertical move: moving detected", un.anim.moving)
	# And the sync-level override puts the bounce on.
	un.set_work_state("idle")
	_check("vertical move: animator walks",
		un.anim.state == UnitAnimator.WALK)
	un.free()


func _test_gender_deterministic() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var town: Dictionary = gs.found_town("humans", "T", Vector2(0, 0))
	var tid: int = int(town["id"])
	var genders: Array[String] = []
	for i: int in range(4):
		var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", tid,
			Vector2(i * 10, 0))
		genders.append(String(u.get("gender", "?")))
	# _next_unit_id starts at 1: id 1 -> f, 2 -> m, 3 -> f, 4 -> m.
	_check("gender: assigned", genders == ["f", "m", "f", "m"])
	gs.free()
