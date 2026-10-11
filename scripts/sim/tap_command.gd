class_name SimTapCommand
extends RefCounted
## Cursing Gnomes — tap-to-command military controls (Jeremy 2026-10-07).
##
## The player taps a map location (no unit selection required — Jeremy
## 2026-10-09) and issues tactical orders to the ENTIRE military: Move
## (walk there, ignore enemies) or Attack-Move (advance, engaging nearest
## enemy unit first, then nearest enemy building when no units remain). Orders live on the unit dict as `player_order`
## plus `move_target` (which combat.tick_unit already honors), so the AI
## director and other systems treat ordered units as player-directed.
##
## Faction sovereignty: ONLY the player's own faction can be commanded.
## Foreign units are refused — their leaders' `refuse_direct_control`
## applies to direct unit orders (see SimArmy._sovereignty_check).


## Radius (world px) for the "include nearby troops" squad option.
const SQUAD_RADIUS := 400.0


var _gs  # GameState (untyped: sim <-> world cycle)


func _init(game_state) -> void:
	_gs = game_state


## True when the player may command this unit: alive, own faction,
## military job. Guards are commandable too (they'll leash back to post
## via the existing guard logic in combat.tick_unit).
func can_command(unit: Dictionary) -> bool:
	if unit.is_empty():
		return false
	if not bool(unit.get("alive", false)):
		return false
	if bool(unit.get("downed", false)):
		return false
	if String(unit.get("faction", "")) != String(_gs.player_faction):
		return false
	return SimCombat.is_fighter(unit)


## Move order: walk to pos. Units do NOT seek enemies (aggro suppressed
## in combat.tick_unit for pure move), but auto-retaliation still fires
## if they are attacked en route.
func order_move(unit_ids: Array, pos: Vector2) -> int:
	return _issue(unit_ids, pos, "move")


## Attack-move: advance to pos, engaging on the way. combat.tick_unit
## acquires the nearest hostile unit first (existing aggro); when no
## units remain in range, attack-move units also target the nearest
## hostile building (unlike plain aggro, which only sieges do).
func order_attack_move(unit_ids: Array, pos: Vector2) -> int:
	return _issue(unit_ids, pos, "attack_move")


func _issue(unit_ids: Array, pos: Vector2, order_type: String) -> int:
	var n := 0
	for uid in unit_ids:
		var u: Dictionary = _gs.get_unit(int(uid))
		if not can_command(u):
			continue
		u["player_order"] = {"type": order_type, "tx": pos.x, "ty": pos.y}
		u["move_target"] = pos
		u["combat_target"] = -1
		u.erase("retaliate_id")
		# A fresh player order cancels AI-driven deployments for this unit
		# so the two don't fight over move_target.
		u.erase("deploy_target_id")
		u.erase("deploy_target_kind")
		u["deployed_for_war"] = false
		n += 1
	return n


## Clear player orders — units return to AI control.
func clear_orders(unit_ids: Array) -> int:
	var n := 0
	for uid in unit_ids:
		var u: Dictionary = _gs.get_unit(int(uid))
		if u.is_empty():
			continue
		if String(u.get("faction", "")) != String(_gs.player_faction):
			continue
		u["player_order"] = {}
		u.erase("move_target")
		u.erase("retaliate_id")
		n += 1
	return n


## Jeremy 2026-10-07: tap-to-command orders the ENTIRE military — no
## individual selection, no squad toggle. Touch game: tap a spot, everyone
## marches. Returns IDs of all commandable player-faction military units.
func all_military_ids() -> Array:
	var ids: Array = []
	for u: Dictionary in _gs.units:
		if can_command(u):
			ids.append(int(u.get("id", -1)))
	return ids


## Move order to the ENTIRE military.
func order_all_move(pos: Vector2) -> int:
	return order_move(all_military_ids(), pos)


## Attack-move order to the ENTIRE military.
func order_all_attack_move(pos: Vector2) -> int:
	return order_attack_move(all_military_ids(), pos)


## Player military unit IDs within radius of pos (squad option).
## Excludes downed units; includes the unit at pos itself.
func nearby_troops(pos: Vector2, radius: float = SQUAD_RADIUS) -> Array:
	var ids: Array = []
	var pf: String = String(_gs.player_faction)
	var r2: float = radius * radius
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if not SimCombat.is_fighter(u):
			continue
		var up: Vector2 = u.get("position", Vector2.ZERO)
		if up.distance_squared_to(pos) <= r2:
			ids.append(int(u.get("id", -1)))
	return ids


## Order type currently on the unit ("" when order-free).
static func order_type_of(unit: Dictionary) -> String:
	return String(unit.get("player_order", {}).get("type", ""))
