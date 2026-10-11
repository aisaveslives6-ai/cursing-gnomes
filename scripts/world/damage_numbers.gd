class_name DamageNumbers
extends Node2D
## Cursing Gnomes — floating combat damage numbers (rapid-iteration 2026-10-08).
##
## Combat computed damage but never displayed it: battles read as mush and
## the whole weapon-upgrade economy (AI armament program, fighter weapon
## shopping, firearm tiers) was invisible on the battlefield. SimCombat
## now emits bus.unit_damaged with the final mitigated amount; this layer
## turns each hit into a small floating number.
##
## Jeremy 2026-10-05 bubble ban: these are PLAIN TEXT ONLY — no bubble,
## chip, panel, or rounded-background visuals of any kind. Readability
## comes from a dark font outline, not a backdrop.
##
## PERFORMANCE: fixed pool (NUM_POOL = 24); spawn reuses the oldest active
## slot when the pool is exhausted, never allocates under fire. Chip damage
## (< 1.0) is skipped. _process runs only while at least one number is
## active (thermal budget: zero cost in peacetime).


const NUM_POOL := 24
const LIFE := 0.75          # seconds each number lives
const RISE_PX := 52.0       # pixels risen over LIFE
const FADE_START := 0.45    # age at which fade-out begins
const CHIP_SKIP := 1.0      # hits below this show nothing
const Y_LIFT := -34.0       # spawn above the victim's feet
const X_JITTER := 14.0      # stacked hits don't perfectly overlap

# Tiers mirror the military stat table (swordsman 9 / soldier 15 /
# mage 26 / cannoneer 70): grazes read small white, real hits gold,
# siege-grade hits big and red-orange.
const TIER_LIGHT := 15.0
const TIER_HEAVY := 30.0
const COL_LIGHT := Color(1.0, 1.0, 1.0)
const COL_HEAVY := Color(1.0, 0.85, 0.35)
const COL_MASSIVE := Color(1.0, 0.45, 0.20)
const SIZE_LIGHT := 20
const SIZE_HEAVY := 25
const SIZE_MASSIVE := 31
const OUTLINE := Color(0.05, 0.04, 0.03, 0.9)
const OUTLINE_SIZE := 6

var _pool: Array[Dictionary] = []  # {label, age, active}
var _ls_cache: Array[LabelSettings] = []  # one per tier, shared, never
	# allocated under fire (CombatFX pool idiom)


## Pure tier math, unit-testable without a tree.
static func tier_for(amount: float) -> int:
	if amount >= TIER_HEAVY:
		return 2
	if amount >= TIER_LIGHT:
		return 1
	return 0


static func color_for(tier: int) -> Color:
	match tier:
		1:
			return COL_HEAVY
		2:
			return COL_MASSIVE
	return COL_LIGHT


static func size_for(tier: int) -> int:
	match tier:
		1:
			return SIZE_HEAVY
		2:
			return SIZE_MASSIVE
	return SIZE_LIGHT


func _ready() -> void:
	z_index = 60  # above units and combat particles, below UI chrome
	_ensure_pool()
	set_process(false)


func _ensure_pool() -> void:
	if not _pool.is_empty():
		return
	for tier in range(3):
		var cached := LabelSettings.new()
		cached.font_size = size_for(tier)
		cached.font_color = color_for(tier)
		cached.outline_size = OUTLINE_SIZE
		cached.outline_color = OUTLINE
		_ls_cache.append(cached)
	for i in range(NUM_POOL):
		var lbl := Label.new()
		lbl.visible = false
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.z_index = 1
		add_child(lbl)
		_pool.append({"label": lbl, "age": 0.0, "active": false})


## Spawn one floating number. kind is reserved for future per-school
## tinting (currently unused — tiers carry the read).
func spawn(amount: float, pos: Vector2, kind: String = "") -> void:
	if amount < CHIP_SKIP:
		return
	_ensure_pool()
	var tier: int = tier_for(amount)
	var slot: Dictionary = _free_slot()
	var lbl: Label = slot["label"]
	lbl.label_settings = _ls_cache[tier]
	lbl.text = "%d" % int(roundf(amount))
	lbl.position = pos + Vector2(randf_range(-X_JITTER, X_JITTER), Y_LIFT)
	lbl.modulate = Color(1, 1, 1, 1)
	lbl.visible = true
	slot["age"] = 0.0
	slot["active"] = true
	set_process(true)


func _free_slot() -> Dictionary:
	for slot in _pool:
		if not bool(slot["active"]):
			return slot
	# Pool exhausted: steal the oldest active number (never allocate).
	var oldest: Dictionary = _pool[0]
	for slot in _pool:
		if float(slot["age"]) > float(oldest["age"]):
			oldest = slot
	return oldest


func _process(delta: float) -> void:
	var any_active := false
	for slot in _pool:
		if not bool(slot["active"]):
			continue
		any_active = true
		slot["age"] = float(slot["age"]) + delta
		var age: float = slot["age"]
		var lbl: Label = slot["label"]
		if age >= LIFE:
			slot["active"] = false
			lbl.visible = false
			continue
		lbl.position.y -= RISE_PX * delta
		if age > FADE_START:
			var t: float = 1.0 - (age - FADE_START) / (LIFE - FADE_START)
			lbl.modulate.a = clampf(t, 0.0, 1.0)
	if not any_active:
		set_process(false)


## Test helper: how many numbers are currently flying.
func active_count() -> int:
	var n := 0
	for slot in _pool:
		if bool(slot["active"]):
			n += 1
	return n
