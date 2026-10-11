extends SceneTree
## Cursing Gnomes — resource node icon tests.
##
## Resource nodes (wood/oil/gold) must show the real pixel-art icons
## (assets/art/icons/icon_*.png) on the map instead of the old flat
## colored diamonds. Covers Art.resource_icon() and MapProp setup for
## res kinds, including the diamond fallback when an icon is missing.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_resource_icons.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes resource icon tests ===")
	_test_resource_icon_textures()
	_test_map_prop_res_sprites()
	_test_map_prop_fallback()
	_test_icon_world_size()
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


## Art.resource_icon resolves the three real icon PNGs at their baked
## sizes and returns null for unknown keys (never crashes).
func _test_resource_icon_textures() -> void:
	var wood: Texture2D = Art.resource_icon("wood")
	var oil: Texture2D = Art.resource_icon("oil")
	var gold: Texture2D = Art.resource_icon("gold")
	_check("icon: wood texture loads", wood != null)
	_check("icon: oil texture loads", oil != null)
	_check("icon: gold texture loads", gold != null)
	if wood != null:
		_check("icon: wood is 83x64", wood.get_width() == 83 and wood.get_height() == 64)
	if oil != null:
		_check("icon: oil is 76x64", oil.get_width() == 76 and oil.get_height() == 64)
	if gold != null:
		_check("icon: gold is 63x64", gold.get_width() == 63 and gold.get_height() == 64)
	_check("icon: unknown key returns null", Art.resource_icon("platinum") == null)
	_check("icon: repeated calls hit the cache", Art.resource_icon("wood") == wood)


## A MapProp set up as a resource node gets a Sprite2D child textured with
## the matching icon, scaled to RES_ICON_WORLD_H, base grounded at the node
## origin. Trees are untouched by this path.
func _test_map_prop_res_sprites() -> void:
	var pairs := [["res_wood", "wood"], ["res_oil", "oil"], ["res_gold", "gold"]]
	for pair in pairs:
		var prop := MapProp.new()
		prop.setup(pair[0], Vector2(100, 100))
		var sprites := _sprite_children(prop)
		_check("prop: %s gets exactly one sprite" % pair[0], sprites.size() == 1)
		if sprites.size() == 1:
			var sp: Sprite2D = sprites[0]
			# Jeremy 2026-10-04: deposits now use proper node art, not HUD icons.
			_check("prop: %s sprite has the right icon" % pair[0],
				sp.texture == Art.resource_node_texture(pair[1]))
			var want_h: float = float(MapProp.RES_ICON_WORLD_H)
			var got_h: float = float(sp.texture.get_height()) * sp.scale.y
			_check("prop: %s icon world height is 36" % pair[0],
				absf(got_h - want_h) < 0.01)
			_check("prop: %s sprite sits above the ground point" % pair[0],
				sp.position.y < 0.0)
		prop.queue_free()


## Unknown res kinds (and trees with missing art) have no sprite child, so
## _draw falls back to the drawn diamond — no crash, node still renders.
func _test_map_prop_fallback() -> void:
	var prop := MapProp.new()
	prop.setup("res_platinum", Vector2(50, 50))
	_check("prop: unknown res kind gets no sprite", _sprite_children(prop).is_empty())
	_check("prop: unknown res kind stored", prop.kind == "res_platinum")
	prop.queue_free()


## The old diamond marker was 24 px tall; the icon art must be bigger to
## justify the swap but stay small enough not to dominate the map.
func _test_icon_world_size() -> void:
	_check("icon: world height is 36 px", MapProp.RES_ICON_WORLD_H == 36.0)


func _sprite_children(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Sprite2D:
			out.append(c)
	return out
