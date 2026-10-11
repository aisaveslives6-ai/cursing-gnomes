class_name ProjectileNode
extends Node2D
## Cursing Gnomes — projectile visual (Milestone 4: combat & disasters).
##
## Dumb visual only: the SimCombat record owns motion and hit resolution;
## the world sync copies record positions here each tick. Kinds:
##   arrow: small fast streak (archers, guard towers)
##   spell: glowing orb (mages, rogue wizard)
##   cannonball: heavy dark ball with smoke trail (cannoneers)
##
## Drawn with _draw (no textures needed) so zero art dependencies and
## trivial 60 fps cost. Freed by the world on projectile_done.


var proj_id := -1
var kind := "arrow"
var _trail: PackedVector2Array = PackedVector2Array()
var _age := 0.0


func setup(p_id: int, p_kind: String) -> void:
	proj_id = p_id
	kind = p_kind


func _process(delta: float) -> void:
	_age += delta
	_trail.append(position)
	if _trail.size() > 6:
		_trail.remove_at(0)
	queue_redraw()


func _draw() -> void:
	match kind:
		"arrow":
			# Short white-yellow streak along the trail.
			if _trail.size() >= 2:
				draw_line(_trail[0] - position, Vector2.ZERO,
					Color(1.0, 0.95, 0.7, 0.9), 3.0)
			draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.9, 0.6))
		"spell":
			# Pulsing violet orb.
			var r: float = 6.0 + sin(_age * 14.0) * 1.5
			draw_circle(Vector2.ZERO, r + 3.0, Color(0.7, 0.3, 0.9, 0.25))
			draw_circle(Vector2.ZERO, r, Color(0.75, 0.4, 1.0))
			draw_circle(Vector2.ZERO, r * 0.45, Color(1, 1, 1, 0.9))
		"cannonball":
			# Dark iron ball + fading smoke puffs.
			for i: int in range(_trail.size()):
				var a: float = float(i) / 6.0 * 0.35
				draw_circle(_trail[i] - position, 7.0 * (1.0 - a),
					Color(0.5, 0.5, 0.5, a))
			draw_circle(Vector2.ZERO, 7.0, Color(0.12, 0.12, 0.14))
			draw_circle(Vector2(-2, -2), 2.5, Color(0.35, 0.35, 0.38))
		"nuke":
			# Jeremy 2026-10-04: ICBM — long white missile body, red nose
			# cone, green glow at the tail, fire trail. Reads as a nuke,
			# not another cannonball.
			var dir := Vector2.RIGHT
			if _trail.size() >= 2:
				var d: Vector2 = position - _trail[_trail.size() - 2]
				if d.length() > 0.5:
					dir = d.normalized()
			var perp := Vector2(-dir.y, dir.x)
			for i: int in range(_trail.size()):
				var ta: float = float(i) / 6.0 * 0.5
				draw_circle(_trail[i] - position, 9.0 * (1.0 - ta),
					Color(1.0, 0.55, 0.15, ta))
			# Body.
			var tip: Vector2 = dir * 22.0
			var tail: Vector2 = -dir * 18.0
			draw_line(tail, tip, Color(0.85, 0.87, 0.9), 10.0)
			draw_line(tail, tip - dir * 4.0, Color(0.55, 0.58, 0.62), 10.0)
			# Nose cone.
			draw_colored_polygon(
				PackedVector2Array([tip, tip - dir * 10.0 + perp * 5.0,
					tip - dir * 10.0 - perp * 5.0]),
				Color(0.85, 0.15, 0.12))
			# Fins + engine glow.
			draw_line(tail + perp * 8.0, tail - dir * 6.0, Color(0.7, 0.72, 0.75), 4.0)
			draw_line(tail - perp * 8.0, tail - dir * 6.0, Color(0.7, 0.72, 0.75), 4.0)
			draw_circle(tail - dir * 4.0, 5.0 + sin(_age * 30.0) * 1.5,
				Color(0.55, 1.0, 0.35, 0.9))
		_:
			draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1))
