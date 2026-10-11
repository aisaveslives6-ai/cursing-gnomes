extends SceneTree
## Cursing Gnomes — burning-building fire FX tests (HTML c59 parity).
##
## Burning buildings (sim on_fire == true) must get: an animated roof fire
## sprite, faction-tinted smoke (alive cap 5, rate dt*(1.4+bs)) and rising
## embers (alive cap 7, rate dt*(2.0+bs)), driven by the world sync.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_building_fire_fx.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame: int = 0
var _fx: CombatFX = null
var _world: Node = null


func _initialize() -> void:
	print("=== Cursing Gnomes building-fire FX tests ===")
	_fx = CombatFX.new()
	_test_spawn_idempotent()
	_test_max_cap()
	_test_faction_tints()
	_test_caps_under_load()
	_test_intensity_scale()
	_test_frame_caching()
	_test_clear()
	# World wiring needs frames (scene _ready); deferred to _process.
	var ps: PackedScene = load("res://scenes/world/world.tscn")
	_check("world scene loads", ps != null)
	if ps != null:
		_world = ps.instantiate()
		root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_test_world_sync()
		_fx.queue_free()
		if _world != null:
			root.remove_child(_world)
			_world.free()
		print("=== %d passed, %d failed ===" % [_passed, _failed])
		for f: String in _failures:
			print("  FAIL: ", f)
		quit(1 if _failed > 0 else 0)
		return true
	return false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _test_spawn_idempotent() -> void:
	_fx.spawn_building_fire(1, Vector2(100, 100), "human", 1.0)
	_fx.spawn_building_fire(1, Vector2(100, 100), "human", 1.0)
	_check("spawn idempotent", _fx.building_fire_count() == 1)
	_check("has_building_fire", _fx.has_building_fire(1))


func _test_max_cap() -> void:
	for i in range(2, 40):
		_fx.spawn_building_fire(i, Vector2(i * 10, 50), "ogres", 1.0)
	_check("max building fires capped",
		_fx.building_fire_count() == CombatFX.MAX_BUILDING_FIRES)
	_fx.clear_all_building_fires()
	_check("clear_all empties", _fx.building_fire_count() == 0)


func _test_faction_tints() -> void:
	_fx.spawn_building_fire(11, Vector2.ZERO, "elves", 1.0)
	_fx.spawn_building_fire(12, Vector2.ZERO, "gnomes", 1.0)
	_fx.spawn_building_fire(13, Vector2.ZERO, "undead", 1.0)
	_fx.spawn_building_fire(14, Vector2.ZERO, "ogres", 1.0)
	_fx.spawn_building_fire(15, Vector2.ZERO, "humans", 1.0)
	_fx.spawn_building_fire(16, Vector2.ZERO, "mystery", 1.0)
	_check("elf tint", _fx.building_fire(11)._tint == Color8(150, 230, 190))
	_check("gnome tint", _fx.building_fire(12)._tint == Color8(240, 220, 150))
	_check("undead tint", _fx.building_fire(13)._tint == Color8(180, 180, 200))
	_check("ogre tint", _fx.building_fire(14)._tint == Color8(255, 150, 120))
	_check("human tint", _fx.building_fire(15)._tint == Color8(212, 216, 221))
	_check("unknown faction falls back to human",
		_fx.building_fire(16)._tint == Color8(212, 216, 221))
	_fx.clear_all_building_fires()


func _test_caps_under_load() -> void:
	# High intensity for 4 simulated seconds: pools must never exceed caps.
	_fx.spawn_building_fire(21, Vector2.ZERO, "human", 1.8)
	var bf = _fx.building_fire(21)
	for i in range(240):
		bf._process(1.0 / 60.0)
	_check("smoke alive <= cap",
		bf.alive_smoke() <= CombatFX.BUILDING_SMOKE_CAP)
	_check("embers alive <= cap",
		bf.alive_embers() <= CombatFX.BUILDING_EMBER_CAP)
	_check("smoke spawns at all", bf.alive_smoke() > 0)
	_check("embers spawn at all", bf.alive_embers() > 0)
	# Wind bends smoke: strong wind must displace particles downwind.
	var before: Vector2 = bf._smoke[0]["p"]
	bf.set_wind(Vector2(10, 0))
	for i in range(120):
		bf._process(1.0 / 60.0)
	var moved := false
	for s in bf._smoke:
		if bool(s["alive"]) and (s["p"] as Vector2).x > (before.x + 20.0):
			moved = true
	_check("wind displaces smoke", moved)
	_fx.clear_all_building_fires()


func _test_intensity_scale() -> void:
	_fx.spawn_building_fire(31, Vector2.ZERO, "human", 0.8)
	_fx.spawn_building_fire(32, Vector2.ZERO, "human", 1.8)
	var low = _fx.building_fire(31)
	var high = _fx.building_fire(32)
	low._process(0.1)
	high._process(0.1)
	_check("higher intensity = bigger fire sprite",
		high.fire_sprite_scale() > low.fire_sprite_scale())
	_fx.clear_all_building_fires()


func _test_frame_caching() -> void:
	# 2026-10-04 perf: _animate_fire caches the frame index so the fire
	# sprite's texture/scale are written only when the frame changes
	# (~11Hz) or the intensity changes — not every frame (60Hz).
	_fx.spawn_building_fire(51, Vector2.ZERO, "human", 1.0)
	var bf = _fx.building_fire(51)
	bf._process(0.1)
	var last1: int = int(bf._last_frame)
	_check("first process writes a fire frame", last1 >= 0)
	# Same frame again: must not rewrite (cached).
	bf._animate_fire()
	_check("same frame does not rewrite",
		int(bf._last_frame) == last1)
	# Advance less than one frame boundary: still cached.
	bf._age = float(last1) * CombatFX.FIRE_FRAME_TIME + 0.01
	bf._animate_fire()
	_check("sub-frame advance does not rewrite",
		int(bf._last_frame) == last1)
	# Cross the frame boundary: must write.
	bf._age = float(last1) * CombatFX.FIRE_FRAME_TIME \
		+ CombatFX.FIRE_FRAME_TIME + 0.001
	bf._animate_fire()
	_check("frame boundary triggers rewrite",
		int(bf._last_frame) != last1)
	# set_intensity re-applies the scale immediately.
	var scale_before := bf.fire_sprite_scale()
	bf.set_intensity(2.0)
	_check("set_intensity updates scale immediately",
		bf.fire_sprite_scale() > scale_before)
	_fx.clear_all_building_fires()


func _test_clear() -> void:
	_fx.spawn_building_fire(41, Vector2.ZERO, "human", 1.0)
	_fx.clear_building_fire(41)
	_check("clear removes", not _fx.has_building_fire(41))
	_fx.clear_building_fire(41)  # double clear must not error
	_check("double clear safe", _fx.building_fire_count() == 0)


## World wiring: the sync mirrors sim on_fire into FX and clears on put-out.
func _test_world_sync() -> void:
	_check("world ready", _world != null and _world.game != null)
	if _world == null or _world.game == null:
		return
	var w = _world
	var b: Dictionary = {}
	for rec: Dictionary in w.game.buildings:
		if bool(rec.get("alive", true)):
			b = rec
			break
	_check("demo building found", not b.is_empty())
	if b.is_empty():
		return
	var bid := int(b.get("id", 0))
	b["on_fire"] = true
	b["hp"] = 40.0
	b["max_hp"] = 100.0
	w._sync_building_fire_visuals()
	_check("burning building gets FX", w.fx.has_building_fire(bid))
	b["on_fire"] = false
	w._sync_building_fire_visuals()
	_check("put-out building clears FX", not w.fx.has_building_fire(bid))
