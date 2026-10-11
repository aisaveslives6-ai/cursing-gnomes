class_name WorldFarmSfx
extends RefCounted
## Cursing Gnomes — farm/ranch/trade world sounds (Jeremy 2026-10-07 wake
## lane: "the food economy talks back").
##
## World-side companion to scripts/sim/food_feedback.gd. Consumes the
## food-economy bus signals that previously fired into the void and routes
## them through bus.sfx_spatial, following the 2026-10-07 audio lane's
## pattern (sim stays pure-logic; the world layer owns sound):
##   farm_plot_created -> "place" at the plot (infrequent)
##   farm_harvested    -> "harvest" at the plot (throttled: 4 per 1 s
##                        game-time bucket — a full plot harvests 16 tiles)
##   animal_yield      -> "harvest" at the plot (shared throttle bucket)
##   animals_stocked   -> "place" at the plot (infrequent)
##   trade_done        -> "coin" at the wandering caravan (skipped while
##                        the caravan is off-map)
## animal_died stays silent — death isn't celebrated (die-offs reach the
## Gazette via SimFoodFeedback). seeds_bought is a player-initiated
## purchase whose UI already clicks.


const HARVEST_BUCKET := 1.0  # game-time seconds per throttle bucket
const HARVEST_PER_BUCKET := 4


var _gs  # GameState (untyped: avoids a cyclic class reference)
var _bucket := -1
var _n := 0


func _init(game_state) -> void:
	_gs = game_state
	if _gs == null or _gs.get("bus") == null:
		return
	var bus = _gs.bus
	if bus.has_signal("farm_plot_created"):
		bus.farm_plot_created.connect(_on_plot_created)
	if bus.has_signal("farm_harvested"):
		bus.farm_harvested.connect(_on_harvested)
	if bus.has_signal("animal_yield"):
		bus.animal_yield.connect(_on_yield)
	if bus.has_signal("animals_stocked"):
		bus.animals_stocked.connect(_on_stocked)
	if bus.has_signal("trade_done"):
		bus.trade_done.connect(_on_trade)


func _plot_pos(plot_id: int) -> Vector2:
	var farming = _gs.get("farming")
	if farming == null:
		return Vector2.INF
	for plot: Dictionary in farming.plots:
		if int(plot.get("id", 0)) == plot_id:
			return plot.get("position", Vector2.INF) as Vector2
	return Vector2.INF


## Throttled "harvest" pluck (audio-lane bucket pattern: SimCombat's
## 8-per-0.1s melee throttle, widened to 4 per 1 s for farm work).
func _emit_harvest(pos: Vector2) -> void:
	var bucket: int = int(float(_gs.game_time) / HARVEST_BUCKET)
	if bucket != _bucket:
		_bucket = bucket
		_n = 0
	if _n >= HARVEST_PER_BUCKET:
		return
	_n += 1
	_gs.bus.sfx_spatial.emit("harvest", pos, Vector2.ZERO)


func _on_plot_created(plot: Dictionary) -> void:
	var pos := plot.get("position", Vector2.INF) as Vector2
	if pos == Vector2.INF:
		return
	_gs.bus.sfx_spatial.emit("place", pos, Vector2.ZERO)


func _on_harvested(plot_id: int, _food: float, _seeds: float) -> void:
	var pos := _plot_pos(plot_id)
	if pos == Vector2.INF:
		return
	_emit_harvest(pos)


func _on_yield(plot_id: int, _faction: String, _food: float) -> void:
	var pos := _plot_pos(plot_id)
	if pos == Vector2.INF:
		return
	_emit_harvest(pos)


func _on_stocked(plot_id: int, _kind: String, _types: Array) -> void:
	var pos := _plot_pos(plot_id)
	if pos == Vector2.INF:
		return
	_gs.bus.sfx_spatial.emit("place", pos, Vector2.ZERO)


func _on_trade(_faction: String, _give: String, _take: String,
		_give_amt: float, _take_amt: float) -> void:
	var industry = _gs.get("industry")
	if industry == null:
		return
	if not bool(industry.funky_on_map):
		return
	var pos: Vector2 = industry.funky_pos
	_gs.bus.sfx_spatial.emit("coin", pos, Vector2.ZERO)
