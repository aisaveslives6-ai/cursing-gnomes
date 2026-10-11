class_name Selection
extends Node2D
## Cursing Gnomes — tap-to-select (Milestone 2).
##
## Listens to CameraController.tapped, picks the nearest selectable Node2D
## within PICK_RADIUS world px, and draws a white ring on the selection.
## Tap empty ground to deselect. Multi-select / drag-box comes later.


const PICK_RADIUS := 60.0


var camera: CameraController
var selectables: Array[Node2D] = []
var selected: Node2D = null

## Wired by World: lets the overlay draw the selected unit's live route.
var game = null  # GameState (untyped: ui <-> sim cycle)


func _draw() -> void:
	if selected == null or not is_instance_valid(selected):
		return
	var p: Vector2 = selected.position
	draw_arc(p, 30.0, 0.0, TAU, 32, Color.WHITE, 3.0)
	draw_arc(p, 36.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)
	# Jeremy 2026-10-05: lumber camps show their tree coverage radius
	# (Rise of Nations style) when selected.
	if "btype" in selected and String(selected.get("btype")) == "lumber_camp":
		var r := SimBuildings.LUMBER_CAMP_RADIUS
		draw_arc(p, r, 0.0, TAU, 96, Color(0.45, 0.9, 0.45, 0.55), 3.0)
		draw_arc(p, r, 0.0, TAU, 96, Color(0.45, 0.9, 0.45, 0.18), 10.0)
	_draw_route()


## Path visualization: the selected unit's projected A* route, drawn as a
## dotted gold trail through the remaining waypoints. Updates live as the
## unit walks it (Jeremy 2026-10-04: show paths when selected).
func _draw_route() -> void:
	if game == null:
		return
	var pf = game.get("pathfinder")
	if pf == null:
		return
	var uid := int(selected.get("unit_id")) if "unit_id" in selected else -1
	if uid < 0:
		return
	var unit: Dictionary = game.get_unit(uid)
	if unit.is_empty():
		return
	var r: Dictionary = (pf as SimPathfinder).get_route(unit)
	if r.is_empty():
		return
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	var idx := int(r.get("idx", 0))
	if wps.size() - idx < 1:
		return
	var col := Color(1.0, 0.85, 0.35, 0.8)
	var prev: Vector2 = selected.position
	for k in range(idx, wps.size()):
		var w: Vector2 = wps[k]
		# Dotted trail: small dots along each leg.
		var d := prev.distance_to(w)
		var n := maxi(1, int(d / 18.0))
		for s in range(1, n + 1):
			draw_circle(prev.lerp(w, float(s) / float(n)), 2.5, col)
		prev = w
	# Destination flag.
	draw_circle(prev, 6.0, col)
	draw_circle(prev, 6.0, Color(1, 1, 1, 0.9), false, 1.5)


## Connected to CameraController.tapped by World.
func on_tapped(screen_pos: Vector2) -> void:
	if camera == null:
		return
	var wp: Vector2 = camera.screen_to_world(screen_pos)
	var idx: int = pick(wp, selectables, PICK_RADIUS)
	selected = selectables[idx] if idx >= 0 else null
	queue_redraw()


## Pure pick math — headless-testable. Returns the index or -1.
static func pick(world_pos: Vector2, nodes: Array, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for i in nodes.size():
		var n: Node2D = nodes[i] as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var d: float = world_pos.distance_to(n.position)
		if d < best_d:
			best_d = d
			best = i
	return best


func _process(_delta: float) -> void:
	# Follow the target if it moves; cheap (one ring redraw per frame).
	if selected != null:
		if not is_instance_valid(selected):
			selected = null
		queue_redraw()
