extends SceneTree
## Test: Cliffs.try_step_fast == Cliffs.try_step on all inputs.
## Verifies the zero-dict-get fast path is behavior-identical.

var _checks := 0
var _fails := 0


func _check(label: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FAIL: ", label)


func _make_map(sx: int, sy: int, tile: int, levels: PackedByteArray) -> Dictionary:
	return {"levels": levels, "size_tiles": Vector2i(sx, sy),
		"tile_size": tile}


func _run() -> void:
	var sx := 8
	var sy := 8
	var tile := 32
	var levels := PackedByteArray()
	levels.resize(sx * sy)
	# Varied terrain: flat, a plateau (level 3), a sheer cliff to level 5.
	for y in range(sy):
		for x in range(sx):
			var l := 1
			if x >= 5:
				l = 3
			if x == 7 and y >= 6:
				l = 5
			levels[y * sx + x] = l
	var md := _make_map(sx, sy, tile, levels)
	# Sweep positions and steps; fast must equal slow exactly.
	var positions := [Vector2(10, 10), Vector2(150, 40), Vector2(200, 200),
		Vector2(225, 210), Vector2(100, 230), Vector2(250, 250)]
	var steps := [Vector2(5, 0), Vector2(-7, 3), Vector2(40, 40),
		Vector2(100, 0), Vector2(0.5, 0.2), Vector2(-50, -50)]
	for p in positions:
		for s in steps:
			var slow: Vector2 = Cliffs.try_step(md, p, s)
			var fast: Vector2 = Cliffs.try_step_fast(levels, sx, sy,
				tile, p, s)
			_check("try_step parity p=%s s=%s slow=%s fast=%s"
				% [p, s, slow, fast], slow == fast)
			var slow_l: int = Cliffs.level_at(md, p + s)
			var fast_l: int = Cliffs.level_at_fast(levels, sx, sy,
				tile, p + s)
			_check("level_at parity p=%s" % (p + s), slow_l == fast_l)
	# Degenerate: empty levels -> pos + step in both.
	var empty_md := _make_map(4, 4, 32, PackedByteArray())
	for p in positions:
		var s := Vector2(9, 9)
		_check("empty levels parity",
			Cliffs.try_step(empty_md, p, s)
			== Cliffs.try_step_fast(PackedByteArray(), 4, 4, 32, p, s))
	# Degenerate: mismatched size -> 0 level in both.
	var bad_md := _make_map(8, 8, 32, PackedByteArray([1, 2, 3]))
	_check("short levels level_at==0",
		Cliffs.level_at(bad_md, Vector2(10, 10)) == 0)
	_check("short levels fast==0",
		Cliffs.level_at_fast(PackedByteArray([1, 2, 3]), 8, 8, 32,
			Vector2(10, 10)) == 0)
	print("checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		quit(1)
	else:
		quit(0)


func _initialize() -> void:
	_run()
