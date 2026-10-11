extends SceneTree
## Cursing Gnomes — spark-driver delivery-fee coin flight
## (Jeremy 2026-10-07 graphics hourly).
##
## The sim skims a treasury fee every 45s and announces it over
## bus.unit_said ("Service charge ($14)"). The world answers with a visual:
## gold coins arc from the town center into the driver's bag and pop with a
## small gold flash — the meter becomes something Jeremy can SEE.
## Zero sim touch: fee amounts, cadence, and lines live in disasters.gd.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_driver_fee_fx.gd
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


func _initialize() -> void:
	print("=== Cursing Gnomes gig-gnome visual tests ===")
	_test_fee_line_detection()
	_test_gig_gnome_art_mapping()
	_test_fee_spawns_coins()
	_test_shout_spawns_no_coins()
	_test_guilt_trip_spawns_no_coins()
	_test_non_driver_fee_text_spawns_no_coins()
	_test_coins_fly_to_driver()
	_test_coins_complete_and_clear()
	_test_landing_flashes_gold()
	_test_backpressure()
	_test_no_crash_without_roots()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _new_gs() -> GameState:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	return gs


func _harness() -> Array:
	var gs := _new_gs()
	var w = load("res://scripts/world/world.gd").new()
	w.game = gs
	var root := Node2D.new()
	root.name = "Projectiles"
	w.projectiles_root = root
	return [gs, w]


func _spawn_driver(gs: GameState) -> Dictionary:
	# The sim renamed the spark_driver job to gig_gnome (2026-10-07).
	return gs.add_unit({
		"faction": "monsters", "job": "gig_gnome", "alive": true,
		"position": Vector2(800, 600),
		"driver_center": Vector2(400, 300),
		"mind": {},
	})


## The sim rename must not leave the gig gnome invisible: the monster art
## table maps the new job onto the existing delivery-driver sprite.
func _test_gig_gnome_art_mapping() -> void:
	var un = load("res://scripts/world/unit_node.gd").new()
	un.job = "gig_gnome"
	_check("gig_gnome: in the monster job table",
		"gig_gnome" in un._MONSTER_JOBS)
	var tex: Texture2D = un._monster_texture()
	_check("gig_gnome: monster texture resolves (not invisible)", tex != null)
	_check("gig_gnome: monster scale is driver-sized",
		is_equal_approx(un._monster_scale(), un.SPRITE_WORLD_H * 1.15))


func _test_fee_line_detection() -> void:
	var w = load("res://scripts/world/world.gd").new()
	_check("fee: 'Service charge ($14)' is a fee line",
		w._is_driver_fee_line("Service charge ($14)"))
	_check("fee: 'Delivery fee ($10)' is a fee line",
		w._is_driver_fee_line("Delivery fee ($10)"))
	_check("fee: 'Peak pricing ($25)' is a fee line",
		w._is_driver_fee_line("Peak pricing ($25)"))
	_check("fee: delivery shout is not a fee line",
		not w._is_driver_fee_line("Your package is 8 stops away!"))
	_check("fee: guilt trip is not a fee line",
		not w._is_driver_fee_line("No tip? Bold. Rude. Fine."))
	_check("fee: flee line is not a fee line",
		not w._is_driver_fee_line("MARKED AS DELIVERED! BYE!"))
	_check("fee: empty text is not a fee line",
		not w._is_driver_fee_line("   "))


func _test_fee_spawns_coins() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var d := _spawn_driver(gs)
	w._on_unit_said(int(d.get("id", 0)), "Service charge ($14)")
	_check("fee: exactly 5 coins spawn", w._fee_coins.size() == 5)
	var tex_ok := true
	for f in w._fee_coins:
		var n: Node2D = f["node"]
		if not (n is Sprite2D) or (n as Sprite2D).texture == null:
			tex_ok = false
	_check("fee: coins are sprites with the gold coin texture", tex_ok)


func _test_shout_spawns_no_coins() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var d := _spawn_driver(gs)
	w._on_unit_said(int(d.get("id", 0)), "Your package is 8 stops away!")
	_check("shout: no coins spawn", w._fee_coins.is_empty())


func _test_guilt_trip_spawns_no_coins() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var d := _spawn_driver(gs)
	w._on_unit_said(int(d.get("id", 0)), "No tip? Bold. Rude. Fine.")
	_check("guilt trip: no coins spawn", w._fee_coins.is_empty())


func _test_non_driver_fee_text_spawns_no_coins() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var s: Dictionary = gs.add_unit({
		"faction": "humans", "job": "soldier", "alive": true,
		"position": Vector2(100, 100), "mind": {},
	})
	w._on_unit_said(int(s.get("id", 0)), "Service charge ($14)")
	_check("non-driver fee text: no coins spawn", w._fee_coins.is_empty())


func _test_coins_fly_to_driver() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var d := _spawn_driver(gs)
	w._on_unit_said(int(d.get("id", 0)), "Delivery fee ($12)")
	var first: Dictionary = w._fee_coins[0]
	var start: Vector2 = (first["node"] as Node2D).position
	# Start near the town center (driver_center), not on the driver.
	_check("coins: launch from the town center",
		start.distance_to(Vector2(400, 300)) < 80.0)
	_check("coins: launch away from the driver",
		start.distance_to(Vector2(800, 600)) > 200.0)
	# Half the flight in: coins have left the start and arc upward.
	w._tick_fee_coins(0.45)
	var mid: Vector2 = (first["node"] as Node2D).position
	_check("coins: mid-flight position moved toward the driver",
		mid.distance_to(Vector2(800, 600)) < start.distance_to(Vector2(800, 600)))
	_check("coins: mid-flight arcs above the straight line",
		mid.y < (start.y + 600.0) * 0.5)


func _test_coins_complete_and_clear() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var d := _spawn_driver(gs)
	w._on_unit_said(int(d.get("id", 0)), "Peak pricing ($20)")
	# Flight is 0.9s with 4 x 0.09s stagger: 2s finishes everything.
	for i in 12:
		w._tick_fee_coins(0.2)
	_check("coins: all entries clear after the flight", w._fee_coins.is_empty())


func _test_landing_flashes_gold() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var rig := LightingRig.new()
	rig.setup(null, "low")
	w.lighting = rig
	var d := _spawn_driver(gs)
	w._on_unit_said(int(d.get("id", 0)), "Small order fee ($11)")
	for i in 12:
		w._tick_fee_coins(0.2)
	var gold_flashes := 0
	for slot in rig._flash_lights:
		if float(slot["life"]) > 0.0:
			var l: PointLight2D = slot["light"]
			if (l.color as Color).is_equal_approx(Color(1.0, 0.84, 0.35)) \
					and (l.position as Vector2).distance_to(Vector2(800, 600)) < 5.0:
				gold_flashes += 1
	# The flash pool reuses slots, so 5 landings may share them — what
	# matters is a gold flash fired at the driver's bag on landing.
	_check("coins: landings pop a gold flash at the driver's bag",
		gold_flashes >= 1)


func _test_backpressure() -> void:
	var h := _harness()
	var gs: GameState = h[0]
	var w = h[1]
	var d := _spawn_driver(gs)
	# Three fees back to back: 15 coins in flight hits the cap.
	for i in 3:
		w._on_unit_said(int(d.get("id", 0)), "Delivery fee ($10)")
	_check("backpressure: 15 coins in flight", w._fee_coins.size() == 15)
	w._on_unit_said(int(d.get("id", 0)), "Delivery fee ($10)")
	_check("backpressure: a fourth fee adds nothing", w._fee_coins.size() == 15)


func _test_no_crash_without_roots() -> void:
	# Bare world (no projectiles_root, no lighting): the FX path no-ops.
	var w = load("res://scripts/world/world.gd").new()
	w._driver_fee_fx({"position": Vector2(1, 1)})
	_check("no roots: fee FX no-ops without crashing", w._fee_coins.is_empty())
	w._tick_fee_coins(0.5)
	_check("no roots: tick no-ops without crashing", true)
