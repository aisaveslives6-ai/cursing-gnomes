class_name SimResources
extends RefCounted
## Cursing Gnomes — per-faction resource ledgers (Milestone 1: sim core).
##
## Tracks the 5 resources (gold, wood, food, seeds, oil) for every faction.
## All mutations go through here so resource_changed is always emitted.
## Storage caps (HTML clampResourcesToCapacity parity): baseline caps plus
## bonuses from stock buildings (Gold Vault, Lumber Yard, etc.).
## Pure logic — no rendering, no input, no audio.


## Baseline storage caps (HTML: gold 1500/wood 1200/food 600/oil 200/seeds 150).
const BASE_CAPS := {
	"gold": 1500.0, "wood": 1200.0, "food": 600.0,
	"oil": 200.0, "seeds": 150.0,
	# Soul essence is uncapped in HTML — use a near-infinite cap.
	"soul_essence": 99999.0,
}

## Stock buildings add storage (HTML STOCK_BUILDINGS parity).
const STOCK_BONUSES := {
	"stock_gold": {"gold": 800.0},
	"stock_wood": {"wood": 1000.0},
	"stock_food": {"food": 500.0},
	"stock_oil": {"oil": 300.0},
	"stock_seeds": {"seeds": 150.0},
}


var _gs: GameState
var _ledgers: Dictionary = {}  # faction -> {resource -> float}


## _init takes the owning GameState (used only for the event bus).
func _init(game_state: GameState) -> void:
	_gs = game_state


## Clears every ledger. Called by GameState.setup() on new game.
func reset() -> void:
	_ledgers.clear()


## Creates a zeroed ledger for a faction if it does not exist yet.
func ensure_faction(faction: String) -> void:
	if _ledgers.has(faction):
		return
	var ledger: Dictionary = {}
	for r: String in Config.RESOURCES:
		ledger[r] = 0.0
	_ledgers[faction] = ledger


## Returns the current amount of a resource for a faction (0.0 if unknown).
func get_amount(faction: String, resource: String) -> float:
	if not _ledgers.has(faction):
		return 0.0
	var ledger: Dictionary = _ledgers[faction]
	return float(ledger.get(resource, 0.0))


## Adds (or removes, if negative) an amount of a resource. Clamped to
## [0, storage cap]. Returns the new amount. Emits resource_changed.
## ignore_cap=true bypasses the cap (for test setup / admin grants).
func add_resource(faction: String, resource: String, amount: float, ignore_cap: bool = false) -> float:
	if not resource in Config.RESOURCES:
		push_error("[SimResources] unknown resource: %s" % resource)
		return 0.0
	ensure_faction(faction)
	var ledger: Dictionary = _ledgers[faction]
	var new_amount: float
	if ignore_cap:
		new_amount = maxf(0.0, float(ledger[resource]) + amount)
	else:
		var cap := get_cap(faction, resource)
		new_amount = clampf(float(ledger[resource]) + amount, 0.0, cap)
	ledger[resource] = new_amount
	_gs.bus.resource_changed.emit(faction, resource, new_amount)
	return new_amount


## Storage cap for a resource: baseline + stock building bonuses.
## (HTML clampResourcesToCapacity parity — Jeremy 2026-10-02 audit.)
func get_cap(faction: String, resource: String) -> float:
	var cap: float = float(BASE_CAPS.get(resource, 999999.0))
	if _gs == null:
		return cap
	for b in _gs.buildings:
		if not (b is Dictionary):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not bool(b.get("alive", true)):
			continue
		var bonus: Dictionary = STOCK_BONUSES.get(String(b.get("type", "")), {})
		cap += float(bonus.get(resource, 0.0))
	return cap


## True if the faction can afford every entry in costs ({resource -> amount}).
func can_afford(faction: String, costs: Dictionary) -> bool:
	for resource: String in costs.keys():
		if get_amount(faction, resource) < float(costs[resource]):
			return false
	return true


## Atomically deducts costs ({resource -> amount}). If anything is unaffordable,
## nothing is deducted and the function returns false.
func spend(faction: String, costs: Dictionary) -> bool:
	if not can_afford(faction, costs):
		return false
	for resource: String in costs.keys():
		# Bypass cap on deductions: if the ledger is above cap (admin/test
		# grant), spending must deduct from the actual amount, not clamp.
		add_resource(faction, resource, -float(costs[resource]), true)
	return true


## Returns a copy of a faction's whole ledger ({resource -> amount}).
func get_ledger(faction: String) -> Dictionary:
	ensure_faction(faction)
	return (_ledgers[faction] as Dictionary).duplicate()


## Milestone 7: export all ledgers for save files.
func to_dict() -> Dictionary:
	var out := {}
	for f in _ledgers.keys():
		out[f] = (_ledgers[f] as Dictionary).duplicate()
	return out


## Milestone 7: restore ledgers from a save file.
func from_dict(data: Dictionary) -> void:
	_ledgers.clear()
	for f in data.keys():
		var ledger: Dictionary = {}
		var src: Dictionary = data[f] as Dictionary
		for r in Config.RESOURCES:
			ledger[r] = float(src.get(r, 0.0))
		_ledgers[str(f)] = ledger
