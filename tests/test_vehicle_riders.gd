extends SceneTree
## Cursing Gnomes — seated vehicle riders (graphics-hourly 2026-10-11).
##
## Boarded units used to render as full-size sprites glued to the vehicle
## (firefighters standing ON the firetruck). Now world.gd hides boarded
## units' UnitNodes via set_inside() while aboard, and VehicleLayer draws
## the driver + crew seated in the vehicle as upper-body crops of their real
## chibi sprites (VehicleArt.rider_seats / _draw_riders).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_vehicle_riders.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes vehicle rider tests ===")
	_test_seat_layouts()
	_test_aboard_set()
	_test_command_rider_textures()
	_test_rider_draw_smoke()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var veh := SimVehicles.new(gs)
	return {"gs": gs, "veh": veh}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


## Seat tables: driver-first, sane counts, driver seat at the front
## (+x in facing-right space).
func _test_seat_layouts() -> void:
	_check("rider crop fraction sane",
		VehicleArt.RIDER_FRAC > 0.0 and VehicleArt.RIDER_FRAC < 1.0)
	_check("rider world height matches unit sprites",
		VehicleArt.RIDER_WORLD_H == 44.0)
	var wagon := VehicleArt.rider_seats("wagon")
	var cart := VehicleArt.rider_seats("cart")
	var carriage := VehicleArt.rider_seats("carriage")
	var firetruck := VehicleArt.rider_seats("firetruck")
	_check("wagon: driver only (crew rides inside the canvas)",
		wagon.size() == 1)
	_check("cart: driver + 2 crew", cart.size() == 3)
	_check("carriage: driver only (passengers inside)", carriage.size() == 1)
	_check("firetruck: driver + 2 crew", firetruck.size() == 3)
	_check("unknown type falls back to wagon seats",
		VehicleArt.rider_seats("hovercar").size() == wagon.size())
	for seats in [wagon, cart, carriage, firetruck]:
		var s0: Vector2 = (seats as Array)[0]
		_check("driver seat at the front (+x)", s0.x > 0.0)


## aboard_set(): driver + crew collected across the fleet; dismount clears.
func _test_aboard_set() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	_check("empty fleet -> empty aboard set",
		veh.aboard_set().is_empty())
	var a: Dictionary = veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	var b: Dictionary = veh.spawn_vehicle("firetruck", Vector2(200, 200), "humans")
	var aid := int(a["id"])
	var bid := int(b["id"])
	veh.board_vehicle(aid, 11)  # first boarder drives
	veh.board_vehicle(aid, 12)
	veh.board_vehicle(aid, 13)
	veh.board_vehicle(bid, 21)
	veh.board_vehicle(bid, 22)
	var aboard: Dictionary = veh.aboard_set()
	for uid in [11, 12, 13, 21, 22]:
		_check("aboard has unit %d" % uid, aboard.has(uid))
	_check("aboard set size", aboard.size() == 5)
	veh.disembark_vehicle(aid, 12)
	aboard = veh.aboard_set()
	_check("disembarked unit leaves the set", not aboard.has(12))
	_check("driver + rest stay aboard",
		aboard.has(11) and aboard.has(13) and aboard.has(21))
	veh.despawn_vehicle(bid)
	aboard = veh.aboard_set()
	_check("despawned vehicle clears its riders",
		not aboard.has(21) and not aboard.has(22) and aboard.size() == 2)
	_free_world(w)


## _build_commands resolves driver-first rider textures through the unit
## provider; unknown units yield nulls (no crash), never white squares.
func _test_command_rider_textures() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	var vid := int(v["id"])
	veh.board_vehicle(vid, 11)
	veh.board_vehicle(vid, 12)
	veh.board_vehicle(vid, 999)  # unknown unit: texture must be null
	var units := [
		{"id": 11, "faction": "humans", "job": "worker", "gender": "m"},
		{"id": 12, "faction": "gnome", "job": "soldier", "gender": "f"},
	]
	var layer := VehicleLayer.new()
	root.add_child(layer)
	layer.set_provider(func() -> Array: return veh.vehicles)
	layer.set_unit_provider(func() -> Array: return units)
	var cmds := layer._build_commands(veh.vehicles, {11: units[0], 12: units[1]})
	_check("one vehicle command", cmds.size() == 1)
	var rider_texs: Array = cmds[0].get("rider_texs", [])
	_check("rider count = min(riders, seats)", rider_texs.size() == 3)
	_check("driver texture resolved",
		rider_texs[0] is Texture2D and rider_texs[0] != null)
	_check("crew texture resolved",
		rider_texs[1] is Texture2D and rider_texs[1] != null)
	_check("unknown unit -> null texture (no crash, no white square)",
		rider_texs[2] == null)
	# No unit provider -> rider slots resolve to nulls (seat alignment kept,
	# draw skips them), still renders.
	var layer2 := VehicleLayer.new()
	root.add_child(layer2)
	layer2.set_provider(func() -> Array: return veh.vehicles)
	var cmds2 := layer2._build_commands(veh.vehicles)
	var rider_texs2: Array = cmds2[0].get("rider_texs", [])
	_check("no unit provider -> rider slots all null",
		rider_texs2.size() == 3 and rider_texs2[0] == null \
		and rider_texs2[1] == null and rider_texs2[2] == null)
	layer.free()
	layer2.free()
	_free_world(w)


class RiderDrawProbe extends Node2D:
	var tex: Texture2D
	var drew := false

	func _draw() -> void:
		for vtype in ["wagon", "cart", "carriage", "firetruck", "hovercar"]:
			# With riders and without (default arg keeps old callers working).
			VehicleArt.draw_vehicle(self, vtype, Vector2(50, 50), 1.0,
				0.3, 1.2, Color.WHITE, [tex, tex, tex])
			VehicleArt.draw_vehicle(self, vtype, Vector2(50, 50), -1.0,
				0.0, 0.0, Color.WHITE)
			VehicleArt.draw_vehicle(self, vtype, Vector2(50, 50), 1.0,
				0.0, 0.0, Color.WHITE, [null])
		drew = true


## Live draw path: real chibi texture as a seated rider must not error.
func _test_rider_draw_smoke() -> void:
	var tex: Texture2D = Art.unit_texture("gnome", "worker", 0, "m")
	if tex == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 0, 1, 1))
		tex = ImageTexture.create_from_image(img)
	_check("rider texture available", tex != null)
	var probe := RiderDrawProbe.new()
	probe.tex = tex
	root.add_child(probe)
	probe.queue_redraw()
	await process_frame
	await process_frame
	_check("draw_vehicle rider paths render without error", probe.drew)
	probe.free()
