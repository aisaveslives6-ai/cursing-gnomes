extends SceneTree
## Cursing Gnomes — farm plot layer tests (launch-readiness 2026-10-05, gate 2).
##
## The auto-plots pass gave every farm/farmhouse a working 4x4 field, but
## plots were sim-only. FarmPlotLayer renders them as isometric tilled
## beds with per-tile crop growth. Verifies the iso geometry, growth
## ramps, command building (incl. camera culling behavior), and node
## basics. Mirrors the TradeWagonLayer test pattern.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_farm_plot_layer.gd
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


func _approx(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) < eps


func _mk_tiles(grown: int = 0, watered: int = 0) -> Array:
	var tiles: Array = []
	for i in 16:
		tiles.append({
			"g": 0.6 if i < grown else 0.0,
			"watered": i < watered,
			"waterT": 0.0,
		})
	return tiles


func _mk_plot(pos := Vector2(400, 300), faction := "humans") -> Dictionary:
	return {
		"id": 1, "faction": faction, "building_id": 7,
		"position": pos, "seed_bin": 4, "tiles": _mk_tiles(5, 3),
	}


func _test_iso_geometry() -> void:
	# Diamond corners: N(0,-HH) E(HW,0) S(0,HH) W(-HW,0).
	var n := FarmPlotLayer.bed_point(0.0, 0.0)
	_check("bed: north corner", _approx(n.x, 0.0) and _approx(n.y, -28.0))
	var e := FarmPlotLayer.bed_point(1.0, 0.0)
	_check("bed: east corner", _approx(e.x, 56.0) and _approx(e.y, 0.0))
	var s := FarmPlotLayer.bed_point(1.0, 1.0)
	_check("bed: south corner", _approx(s.x, 0.0) and _approx(s.y, 28.0))
	var w := FarmPlotLayer.bed_point(0.0, 1.0)
	_check("bed: west corner", _approx(w.x, -56.0) and _approx(w.y, 0.0))
	# 2:1 iso ratio: north->east edge runs 56px out, 28px down.
	var edge := e - n
	_check("bed: 2:1 iso", _approx(absf(edge.x), 2.0 * absf(edge.y)))


func _test_tile_centers() -> void:
	var seen: Array = []
	var ok := true
	for i in 4:
		for j in 4:
			var c := FarmPlotLayer.tile_center(i, j)
			# Inside the diamond: |x|/HW + |y|/HH <= 1.
			if absf(c.x) / 56.0 + absf(c.y) / 28.0 > 1.001:
				ok = false
			for prev in seen:
				if (prev as Vector2).distance_to(c) < 0.01:
					ok = false
			seen.append(c)
	_check("tiles: 16 distinct centers inside the diamond", ok)
	var nw := FarmPlotLayer.tile_center(0, 0)
	var se := FarmPlotLayer.tile_center(3, 3)
	_check("tiles: (0,0) sits north (y<0)", nw.y < 0.0)
	_check("tiles: (3,3) sits south (y>0)", se.y > 0.0)
	_check("tiles: row-major order spreads x",
		FarmPlotLayer.tile_center(3, 0).x > FarmPlotLayer.tile_center(0, 0).x)


func _test_growth_ramps() -> void:
	_check("sprout: g=0 -> no blades", FarmPlotLayer.sprout_height(0.0) == 0.0)
	_check("sprout: below threshold -> bare soil",
		FarmPlotLayer.sprout_height(0.04) == 0.0)
	_check("sprout: threshold sprouts",
		FarmPlotLayer.sprout_height(0.05) > 0.0)
	_check("sprout: g=1 -> 13px",
		_approx(FarmPlotLayer.sprout_height(1.0), 13.0))
	_check("sprout: monotonic",
		FarmPlotLayer.sprout_height(0.9) > FarmPlotLayer.sprout_height(0.2))
	var pale := FarmPlotLayer.sprout_color(0.0)
	_check("color: g=0 is pale", pale.is_equal_approx(FarmPlotLayer.SPROUT_PALE))
	var deep := FarmPlotLayer.sprout_color(1.0)
	_check("color: g=1 is deep", deep.is_equal_approx(FarmPlotLayer.SPROUT_DEEP))
	var mid := FarmPlotLayer.sprout_color(0.5)
	# Hand-computed lerp: (0.55,0.85,0.45)->(0.22,0.60,0.24) at t=0.5.
	_check("color: mid blends r",
		_approx(mid.r, 0.55 + 0.5 * (0.22 - 0.55)))
	_check("color: mid blends g",
		_approx(mid.g, 0.85 + 0.5 * (0.60 - 0.85)))
	_check("color: mid blends b",
		_approx(mid.b, 0.45 + 0.5 * (0.24 - 0.45)))
	_check("color: clamps above 1",
		FarmPlotLayer.sprout_color(2.0).is_equal_approx(deep))


func _test_build_commands() -> void:
	var layer := FarmPlotLayer.new()
	# No camera: view is empty rect, no culling — commands always built.
	layer.set_provider(func() -> Array: return [_mk_plot()])
	var cmds := layer._build_commands(layer._plot_list())
	_check("commands: one plot -> one command", cmds.size() == 1)
	var c: Dictionary = cmds[0]
	_check("commands: kind plot", String(c.get("kind", "")) == "plot")
	_check("commands: position carried",
		(c.get("at") as Vector2).is_equal_approx(Vector2(400, 300)))
	_check("commands: faction carried", String(c.get("faction", "")) == "humans")
	_check("commands: 16 tiles", (c.get("tiles") as Array).size() == 16)
	var fc: Dictionary = Config.FACTIONS.get("humans", {})
	_check("commands: faction color resolved",
		(c.get("color") as Color).is_equal_approx(
			fc.get("color", Color.WHITE)))
	# Empty plots -> no commands.
	layer.set_provider(func() -> Array: return [])
	_check("commands: empty -> none", layer._build_commands([]).is_empty())
	# Non-dict entries skipped, missing tiles default to [].
	layer.set_provider(func() -> Array: return ["junk", {"position": Vector2(1, 1)}])
	cmds = layer._build_commands(layer._plot_list())
	_check("commands: junk skipped, tile-less plot kept", cmds.size() == 1)
	_check("commands: missing tiles -> empty",
		(cmds[0].get("tiles") as Array).is_empty())
	layer.free()


func _test_culling_needs_camera() -> void:
	# Without a camera the layer must NOT cull (view == Rect2()).
	var layer := FarmPlotLayer.new()
	layer.set_provider(func() -> Array:
		return [_mk_plot(Vector2(99999, 99999))])
	var cmds := layer._build_commands(layer._plot_list())
	_check("culling: no camera -> far plot still commanded", cmds.size() == 1)
	layer.free()


func _test_node_basics() -> void:
	var layer := FarmPlotLayer.new()
	_check("z_index: above ground, below units (5)", layer.z_index == 5)
	_check("provider: unset is invalid", not layer._provider.is_valid())
	layer.set_provider(func() -> Array: return [_mk_plot()])
	_check("provider: stores callable", layer._provider.is_valid())
	_check("plot list: provider wins",
		(layer._plot_list() as Array).size() == 1)
	layer._process(0.1)
	_check("visible: plots present", layer.visible)
	_check("commands: built on process", layer._commands.size() == 1)
	layer.set_provider(func() -> Array: return [])
	layer._process(0.1)
	_check("visible: no plots -> hidden", not layer.visible)
	_check("commands: cleared when hidden", layer._commands.is_empty())
	layer.free()


func _initialize() -> void:
	_test_iso_geometry()
	_test_tile_centers()
	_test_growth_ramps()
	_test_build_commands()
	_test_culling_needs_camera()
	_test_node_basics()
	print("farm_plot_layer: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("FAILURES: ", _failures)
	quit(1 if _failed > 0 else 0)
