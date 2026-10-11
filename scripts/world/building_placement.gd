class_name BuildingPlacement
extends Node2D
## Cursing Gnomes — building placement ghost preview (Milestone 3).
##
## While placing, a translucent ghost follows the tap point: green when the
## spot is legal (no overlap, inside map, affordable), red when it isn't.
## A second tap confirms; the build menu's cancel button (or tapping the
## same building button again) aborts.
##
## Validity rules come from SimBuildings.can_place_at + affordability.
## The world routes CameraController.tapped here while placing is active.


var game: GameState
var buildings_sys: SimBuildings
var map_rect := Rect2()
## MapGen's output, kept so near-water placement rules (fishing dock) can
## query tiles. Set by the world after generation.
var map_data: Dictionary = {}

var placing := false
var btype := ""
var ghost_pos := Vector2.ZERO
var ghost_valid := false
var player_faction := ""
## AoE2 drag-to-place for walls (buildings port): press-hold-release plans
## a run via WallDrag; release commits per-segment staged blueprints.
var wall_dragging := false
var _wall_press := Vector2.ZERO
var _wall_plan: Dictionary = {}


## Wall-drag press: begins a run plan.
func on_wall_press(world_pos: Vector2) -> void:
	if not placing or btype != "wall":
		return
	wall_dragging = true
	_wall_press = world_pos
	_wall_plan = WallDrag.plan_path(world_pos, world_pos, game.buildings,
		player_faction, map_rect)
	visible = true
	queue_redraw()


## Wall-drag move: updates the run preview.
func on_wall_move(world_pos: Vector2) -> void:
	if not wall_dragging:
		return
	_wall_plan = WallDrag.plan_path(_wall_press, world_pos, game.buildings,
		player_faction, map_rect)
	queue_redraw()


## Wall-drag release: commits valid segments; a tap (no drag) places one.
func on_wall_release(world_pos: Vector2) -> void:
	if not wall_dragging:
		return
	wall_dragging = false
	var plan: Dictionary = WallDrag.plan_path(_wall_press, world_pos,
		game.buildings, player_faction, map_rect)
	if int(plan.get("valid_count", 0)) == 0:
		plan = WallDrag.plan_tap(world_pos, game.buildings, player_faction,
			map_rect)
	_wall_plan = {}
	var town_id: int = _town_for(player_faction)
	WallDrag.new().commit(buildings_sys, plan, player_faction, town_id)
	cancel()
	queue_redraw()


## Jeremy 2026-10-11 (road infrastructure, direct order): the player's own
## road tool. AoE2-style press-hold-release, mirroring the wall-drag path:
## release plans a road link through the existing road-construction pipeline
## (WorkerAI.plan_road_link -> roadbuilder crews build surveyed -> grading
## -> paving, with work zones and lane closures). Roads are free; the
## roadbuilder crew's labor is the cost (AI parity). Water crossings are
## rejected at commit (bridges are the crossing tool, in the Roads tab).
var road_dragging := false
var _road_press := Vector2.ZERO
var _road_current := Vector2.ZERO
var _road_wet := false  # preview validity: drag crosses water


## Road-drag press: begins a road plan.
func on_road_press(world_pos: Vector2) -> void:
	if not placing or btype != "road":
		return
	road_dragging = true
	_road_press = world_pos
	_road_current = world_pos
	_road_wet = _road_crosses_water(_road_press, world_pos)
	visible = true
	queue_redraw()


## Road-drag move: updates the plan preview.
func on_road_move(world_pos: Vector2) -> void:
	if not road_dragging:
		return
	_road_current = world_pos
	_road_wet = _road_crosses_water(_road_press, world_pos)
	queue_redraw()


## Road-drag release: plans the road through the construction pipeline.
## A tap (no drag) or a water crossing plans nothing; water crossings toast.
func on_road_release(world_pos: Vector2) -> void:
	if not road_dragging:
		return
	road_dragging = false
	var wet := _road_crosses_water(_road_press, world_pos)
	_road_wet = false
	queue_redraw()
	if wet:
		cancel()
		if game != null and game.bus != null:
			game.bus.toast.emit("Roads can't cross water — use a bridge.")
		return
	if _road_press.distance_to(world_pos) >= 1.0:
		var wai = game.get("worker_ai") if game != null else null
		if wai != null:
			wai.plan_road_link(player_faction, _road_press, world_pos)
	cancel()


## True when any 32px sample along a->b sits on a water tile.
func _road_crosses_water(a: Vector2, b: Vector2) -> bool:
	if map_data.is_empty():
		return false
	var steps := maxi(1, int(a.distance_to(b) / 32.0))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if WaterNav.is_water_at(map_data, p):
			return true
	return false


func setup(p_game: GameState, p_buildings: SimBuildings, p_map_rect: Rect2,
		p_faction: String) -> void:
	game = p_game
	buildings_sys = p_buildings
	map_rect = p_map_rect
	player_faction = p_faction


func start_placement(p_btype: String) -> void:
	if p_btype != "road" and not SimBuildings.is_building(p_btype):
		return
	# Tapping the active building again cancels (touch-friendly toggle).
	if placing and btype == p_btype:
		cancel()
		return
	placing = true
	btype = p_btype
	ghost_valid = false
	visible = true


func cancel() -> void:
	placing = false
	btype = ""


## Called by the world with a world-space tap while placing is active.
## First tap with no ghost yet only moves the ghost; a tap while the ghost
## is showing confirms. Returns true if the tap was consumed.
func on_tap(world_pos: Vector2) -> bool:
	if not placing:
		return false
	if btype == "road":
		return false  # road tool uses the drag path only, never tap-to-place
	if ghost_pos.distance_to(world_pos) > 8.0 or not visible:
		ghost_pos = world_pos
		_refresh_validity()
		visible = true
		queue_redraw()
		return true
	# Second tap near the ghost = confirm.
	if ghost_valid:
		var town_id: int = _town_for(player_faction)
		var bp: Dictionary = buildings_sys.place_blueprint(
			btype, player_faction, town_id, ghost_pos)
		# Jeremy 2026-10-04 (faction sovereignty): tag the player's own
		# blueprints so the AI director's advisor mode defers to them —
		# the advisers never place a competing building nearby.
		if not bp.is_empty():
			bp["player_placed"] = true
	cancel()
	queue_redraw()
	return true


## Nearest town of the faction to the ghost (blueprints belong to a town).
func _town_for(faction: String) -> int:
	var best := -1
	var best_d := INF
	for tid: int in game.towns.keys():
		var t: Dictionary = game.towns[tid]
		if String(t.get("faction", "")) != faction:
			continue
		var d: float = ghost_pos.distance_to(t.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = tid
	return best


## Validity: overlap + map bounds + affordability + near-water rules.
## fishing_dock needs a water tile within DOCK_WATER_TILES.
const DOCK_WATER_TILES := 6


func _refresh_validity() -> void:
	# Territory: foreign builds are blocked on claimed land (territory port).
	var ok_place: bool = SimBuildings.can_place_at(
		game.buildings, btype, ghost_pos, map_rect, player_faction, 0.0,
		SimCommandPosts.claimants_of_game(game), map_data)
	var ok_money: bool = game.resources.can_afford(
		player_faction, SimBuildings.cost_of(btype))
	var ok_water := true
	if SimBuildings.requires_water(btype) and not map_data.is_empty():
		ok_water = MapGen.nearest_water_tile(
			map_data, ghost_pos, DOCK_WATER_TILES) != Vector2i(-1, -1)
	ghost_valid = ok_place and ok_money and ok_water


func _process(_delta: float) -> void:
	visible = placing


func _draw() -> void:
	if not placing:
		return
	# Wall-drag run preview: green = valid segment, red = blocked.
	if wall_dragging and not _wall_plan.is_empty():
		for sg: Dictionary in _wall_plan.get("segments", []):
			var a := Vector2(float(sg.get("x0", 0.0)), float(sg.get("y0", 0.0)))
			var b := Vector2(float(sg.get("x1", 0.0)), float(sg.get("y1", 0.0)))
			var c := Color(0.2, 1.0, 0.3, 0.8) \
				if bool(sg.get("valid", false)) else Color(1.0, 0.25, 0.2, 0.8)
			draw_line(a, b, c, 6.0)
		return
	# Jeremy 2026-10-11 (player road tool): planned-road preview — thick
	# line from press to finger; green = dry, red = crosses water.
	if road_dragging:
		var rc := Color(1.0, 0.25, 0.2, 0.85) \
			if _road_wet else Color(0.2, 1.0, 0.3, 0.85)
		draw_line(_road_press, _road_current, rc, 10.0)
		draw_circle(_road_press, 8.0, rc)
		draw_circle(_road_current, 8.0, rc)
		return
	if btype == "road":
		return  # tool armed, no drag yet: nothing to preview
	var r: float = SimBuildings.footprint(btype)
	var c := Color(0.2, 1.0, 0.3, 0.45) if ghost_valid \
		else Color(1.0, 0.25, 0.2, 0.45)
	draw_circle(ghost_pos, r, c)
	draw_arc(ghost_pos, r, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.9), 2.0)
	# Near-water buildings show the water search radius (faint blue ring):
	# water must be found inside it for the ghost to go green.
	if SimBuildings.requires_water(btype):
		var wr: float = DOCK_WATER_TILES * 32.0
		draw_arc(ghost_pos, wr, 0.0, TAU, 48, Color(0.35, 0.65, 1.0, 0.35), 2.0)
