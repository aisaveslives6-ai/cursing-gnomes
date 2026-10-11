class_name UnitAnimator
extends RefCounted
## Cursing Gnomes — per-unit animation state machine + procedural choreography.
##
## Faithful port of the HTML build's AnimationController + toonPose()
## (v0930.59), the system Jeremy approved on his iPhone 2026-09-22/23.
##
## Animation-law compliance (2026-09-20):
##   - Discrete poses: one choreography clip per state, selected one at a
##     time by the state machine (mirrors the HTML's AnimationClip-per-state
##     design). The sprite texture is never scrolled, panned, or translated
##     to fake frames — only the choreography transform moves.
##   - Walk cycle is visibly performed (bounce pivoting at the feet, forward
##     rock, squash alternation). Movement across the screen never counts:
##     the animator only ever touches the Body node (feet pivot); the
##     UnitNode position is owned exclusively by the sim/world movement.
##   - Freeze-position: a unit with state "walk" and a fixed position plays
##     its full cycle in place (covered by tests/test_art.gd).
##   - Transitions: IDLE/WALK loop; MINE/CHOP/HAMMER/HOE/FISH/HUNT loop
##     while the unit works; ATTACK/HURT play once then release back to
##     idle/walk; DEATH plays once, holds, and is uninterruptible.
##   - Facing: 8-way facing exists in the state data (HTML kept it vestigial
##     at 'S'); render facing is the horizontal flip, like the HTML.
##
## Units are RefCounted (no tree membership); the UnitNode owns one and
## applies pose() to its Body child each frame.


## Choreography states.
const IDLE := "idle"
const WALK := "walk"
const WORK := "work"      # gather / build / repair / heal rhythms
const MINE := "mine"      # pickaxe swing loop (Jeremy 2026-10-04)
const CHOP := "chop"      # axe swing loop (Jeremy 2026-10-04)
const HAMMER := "hammer"  # smith's hammer build loop (Jeremy 2026-10-05)
const HOE := "hoe"        # field hoe till loop (Jeremy 2026-10-05)
const FISH := "fish"      # rod cast / wait / yank loop (Jeremy 2026-10-06)
const HUNT := "hunt"      # stalk / strike / recover loop (Jeremy 2026-10-06)
const SIT := "sit"        # seated desk-work loop (Jeremy 2026-10-06)
const ATTACK := "attack"  # one-shot, 0.28 s
const HURT := "hurt"      # one-shot, 0.45 s
const DEATH := "death"     # one-shot, 0.45 s, then holds forever
const CELEBRATE := "celebrate"  # one-shot, 2.4 s (HTML _celebrateT parity)
const DANCE := "dance"    # festival dance loop (the Gazette's "Dancing!")

const ATTACK_LEN := 0.28
const HURT_LEN := 0.45
const DEATH_LEN := 0.45
## HTML celebrate: _celebrateT = 2.4 s of happy hops, one hop per 0.9 s
## (fix79 "interact": it = t / 0.9, lift = -sin(it*PI) * s * 0.16).
const CELEBRATE_LEN := 2.4
const CELEBRATE_HOP := 0.9
## Work-swing loop lengths (s) and the cycle fraction where the tool lands
## (the UnitNode fires its impact FX on this edge).
const MINE_LEN := 0.9
const CHOP_LEN := 0.8
const HAMMER_LEN := 1.0
const HOE_LEN := 1.1
# FISH_LEN matches the sim's FISH_TICK (work.gd: 1.1 s per cast) so every
# loop can land a catch — the yank and the pickup stay in sync.
const FISH_LEN := 1.1
const FISH_STRIKE_AT := 0.70  # the yank: rod snaps back, splash fires
const HUNT_LEN := 1.0     # matches the sim's HUNT_CD (work.gd) — one strike per loop
const HUNT_STRIKE_AT := 0.55  # the kill blow lands
const SIT_LEN := 1.6      # seated desk-work rhythm — deliberate office pace
const MINE_STRIKE_AT := 0.50
const CHOP_STRIKE_AT := 0.55
const HAMMER_STRIKE_AT := 0.55
const HOE_STRIKE_AT := 0.60

var state: String = IDLE
var state_t: float = 0.0   # seconds spent in the current state
var phase: float = 0.0     # per-unit offset so crowds never move in sync
var moving: bool = false   # set by the node each frame from sim movement

## Five-books upgrade (Jeremy 2026-10-06 — Survival Kit, Timing for
## Animation, Illusion of Life, Preston Blair, Unity 2D guide):
##   - weight: body-mass factor. Heavy bodies move through loop cycles
##     slower and squash deeper (Timing for Animation: weight-based timing —
##     ogres move differently than gnomes, not just look different).
##     Set by the UnitNode from faction; default 1.0.
##   - Follow-through: after a one-shot settles, the body rings with 2-3
##     decaying waves (Illusion of Life; Timing: overlapping action).
var weight: float = 1.0
var _follow_t := 999.0
var _follow_amp := 0.0
const FOLLOW_LEN := 0.6


## Body-mass factor per faction (Timing for Animation). Nimble gnomes are
## quick and light; ogres are slow and hit the ground hard.
static func weight_for_faction(faction: String) -> float:
	match faction:
		"gnomes":
			return 0.7
		"elves":
			return 0.85
		"humans":
			return 1.0
		"undead":
			return 1.15
		"ogres":
			return 1.8
	return 1.0


## Loop states run on the weight-scaled clock; one-shots (ATTACK/HURT/
## DEATH/CELEBRATE) keep game-matched timing — damage is the game's clock,
## this is pure choreography matched to it.
func _is_loop() -> bool:
	return state == IDLE or state == WALK or state == WORK \
		or state == MINE or state == CHOP or state == HAMMER or state == HOE \
		or state == FISH or state == HUNT or state == SIT or state == DANCE


## Squash/exaggeration scale: heavier bodies squash deeper, and every body
## gets the Blair/Williams ~20% exaggeration push. Clamped so the
## silhouette stays readable (staging).
func _sq() -> float:
	return clampf(sqrt(weight) * 1.2, 0.85, 1.5)


static func for_uid(uid: int) -> UnitAnimator:
	var a := UnitAnimator.new()
	a.phase = float(uid) * 1.71
	return a


## Request a state. One-shots interrupt; death is terminal.
func set_state(s: String) -> void:
	if state == DEATH:
		return
	if s == state:
		return
	state = s
	state_t = 0.0


## Advance the clock; release one-shots back to idle/walk when finished.
## Loop states advance on the weight-scaled clock (heavy = slower);
## one-shots keep real time so choreography stays matched to the game.
func tick(delta: float) -> void:
	_follow_t += delta
	state_t += delta / (weight if _is_loop() else 1.0)
	match state:
		ATTACK:
			if state_t >= ATTACK_LEN:
				_settle()
		HURT:
			if state_t >= HURT_LEN:
				_settle()
		CELEBRATE:
			if state_t >= CELEBRATE_LEN:
				_settle()
		DEATH:
			pass  # holds forever


func _settle() -> void:
	# The strike's energy rings out as follow-through on the next state.
	_follow_amp = 1.0 if state == ATTACK else 0.7
	_follow_t = 0.0
	state = WALK if moving else IDLE
	state_t = 0.0


## Current choreography pose. All values are deltas applied to the Body node
## whose origin is the unit's feet: lift/crouch shift it vertically (never
## horizontally), rock rotates about the feet, sway is the phase-lagged
## lateral companion of rock (Blair's line of action read as an S-curve
## through time — rotation only, the freeze-position law holds), squash
## scales it.
## Returns {"lift": float, "rock": float, "crouch": float, "squash": float,
## "sway": float}.
func pose() -> Dictionary:
	var t: float = state_t
	var sq := _sq()
	var p := {"lift": 0.0, "rock": 0.0, "crouch": 0.0, "squash": 0.0,
		"sway": 0.0}
	# Follow-through ring after a settled one-shot (Illusion of Life):
	# 2-3 decaying waves on the loop states.
	var fo := 0.0
	if _follow_t < FOLLOW_LEN:
		fo = sin(_follow_t * 28.0) * _follow_amp * exp(-6.0 * _follow_t)
	match state:
		WALK:
			var freq := 9.0
			var ph: float = t * freq + phase
			var c := sin(ph)              # line of action: the stride curve
			var up1 := maxf(c, 0.0)       # primary bounce...
			var up2 := maxf(-c, 0.0) * 0.6  # ...second bounce at 60%
			                              # (Survival Kit double bounce)
			p["lift"] = -(up1 + up2) * 4.4  # bounce: always up, feet never sink
			p["rock"] = c * 0.055            # derived from the same curve
			p["sway"] = sin(ph - 1.2) * 0.02
			p["squash"] = (up1 + up2) * 0.06 * sq  # leg-alternation read
		IDLE:
			var bt: float = t * 2.0 + phase
			var c2 := sin(bt)             # line of action: the breath wave
			p["lift"] = c2 * -0.5         # breathing, barely-there
			# Moving hold (Timing for Animation): idle is never frozen —
			# breathing squash plus a slow weight-shift drift in rock.
			p["squash"] = sin(bt * 0.5) * 0.015 * sq
			p["rock"] = sin(bt * 0.7) * 0.012 \
				+ sin(t * 0.45 + phase) * 0.018
			p["sway"] = sin(bt * 0.5 + 1.0) * 0.008
		WORK:
			var ph2: float = t * 7.0 + phase
			var sw2: float = sin(ph2)
			p["lift"] = -absf(sw2) * 1.5
			p["rock"] = 0.06 + sw2 * 0.05      # lean into the work
			p["crouch"] = 1.2
			p["sway"] = sin(ph2 - 1.0) * 0.015
			p["squash"] = absf(sw2) * 0.02 * sq
		MINE:
			# Overhead pickaxe swing: ANTICIPATE (coil back, squash) ->
			# STRIKE (slam down into the deposit) -> recover. Loops. The
			# strike window ends exactly at MINE_STRIKE_AT, where the tool
			# lands and the UnitNode fires its impact FX.
			var mat: float = fmod(t, MINE_LEN) / MINE_LEN
			var mrs: float = MINE_STRIKE_AT - 0.12
			if mat < mrs:
				var k: float = mat / mrs
				var e: float = k * k
				p["lift"] = lerpf(0.0, -5.0, e)
				p["rock"] = lerpf(0.02, -0.18, e)
				p["squash"] = 0.06 * e * sq   # coil back (anticipation)
				p["sway"] = sin(mat * TAU) * 0.015
			elif mat < MINE_STRIKE_AT:
				var k2: float = (mat - mrs) / 0.12
				var e2: float = k2 * k2
				p["lift"] = lerpf(-5.0, 3.0, e2)
				p["rock"] = lerpf(-0.18, 0.22, e2)
				p["squash"] = lerpf(0.06, -0.06, e2) * sq
				p["crouch"] = lerpf(0.0, 2.0, e2)
			else:
				var k3: float = (mat - MINE_STRIKE_AT) / (1.0 - MINE_STRIKE_AT)
				var e3: float = 1.0 - (1.0 - k3) * (1.0 - k3)
				p["lift"] = lerpf(3.0, 0.0, e3)
				p["rock"] = lerpf(0.22, 0.02, e3)
				p["squash"] = lerpf(-0.06, 0.0, e3) * sq
				p["crouch"] = lerpf(2.0, 0.0, e3)
		CHOP:
			# Side-arc axe swing: ANTICIPATE (coil) -> CHOP (twist through
			# the trunk) -> recover. Loops. The chop lands at CHOP_STRIKE_AT.
			var cat: float = fmod(t, CHOP_LEN) / CHOP_LEN
			var cws: float = CHOP_STRIKE_AT - 0.12
			if cat < cws:
				var k4: float = cat / cws
				var e4: float = k4 * k4
				p["rock"] = lerpf(0.0, -0.14, e4)
				p["squash"] = lerpf(0.0, 0.05, e4) * sq
				p["crouch"] = lerpf(0.0, 1.0, e4)  # coil into the wind-up
				p["sway"] = sin(cat * TAU) * 0.02
			elif cat < CHOP_STRIKE_AT:
				var k5: float = (cat - cws) / 0.12
				var e5: float = k5 * k5
				p["rock"] = lerpf(-0.14, 0.20, e5)
				p["lift"] = lerpf(0.0, 2.5, e5)
				p["squash"] = lerpf(0.05, -0.05, e5) * sq
				p["crouch"] = lerpf(1.0, 1.5, e5)
			else:
				var k6: float = (cat - CHOP_STRIKE_AT) / (1.0 - CHOP_STRIKE_AT)
				var e6: float = 1.0 - (1.0 - k6) * (1.0 - k6)
				p["rock"] = lerpf(0.20, 0.0, e6)
				p["lift"] = lerpf(2.5, 0.0, e6)
				p["squash"] = lerpf(-0.05, 0.0, e6) * sq
				p["crouch"] = lerpf(1.5, 0.0, e6)
		HAMMER:
			# Overhead build swing: ANTICIPATE (rear up, both hands high) ->
			# STRIKE (drive the hammer down onto the scaffold) -> recover.
			# Loops while the unit builds or repairs. A touch heavier than
			# MINE.
			var hat: float = fmod(t, HAMMER_LEN) / HAMMER_LEN
			var hws: float = HAMMER_STRIKE_AT - 0.14
			if hat < hws:
				var k7: float = hat / hws
				var e7: float = k7 * k7
				p["lift"] = lerpf(0.0, -6.0, e7)
				p["rock"] = lerpf(0.02, -0.20, e7)
				p["squash"] = 0.06 * e7 * sq  # coil back (anticipation)
				p["sway"] = sin(hat * TAU) * 0.015
			elif hat < HAMMER_STRIKE_AT:
				var k8: float = (hat - hws) / 0.14
				var e8: float = k8 * k8
				p["lift"] = lerpf(-6.0, 3.5, e8)
				p["rock"] = lerpf(-0.20, 0.24, e8)
				p["squash"] = lerpf(0.06, -0.07, e8) * sq
				p["crouch"] = lerpf(0.0, 2.5, e8)
			else:
				var k9: float = (hat - HAMMER_STRIKE_AT) / (1.0 - HAMMER_STRIKE_AT)
				var e9: float = 1.0 - (1.0 - k9) * (1.0 - k9)
				p["lift"] = lerpf(3.5, 0.0, e9)
				p["rock"] = lerpf(0.24, 0.02, e9)
				p["squash"] = lerpf(-0.07, 0.0, e9) * sq
				p["crouch"] = lerpf(2.5, 0.0, e9)
		HOE:
			# Field till: ANTICIPATE (coil) -> STRIKE (drag the hoe down
			# into the soil and pull back) -> recover. The slowest loop —
			# farming is deliberate. Loops while the unit tends a plot.
			var hot: float = fmod(t, HOE_LEN) / HOE_LEN
			var ows: float = HOE_STRIKE_AT - 0.14
			if hot < ows:
				var k10: float = hot / ows
				var e10: float = k10 * k10
				p["lift"] = lerpf(0.0, -1.0, e10)
				p["rock"] = lerpf(0.0, -0.16, e10)
				p["squash"] = lerpf(0.0, 0.06, e10) * sq
				p["crouch"] = lerpf(0.0, 1.0, e10)  # coil into the wind-up
				p["sway"] = sin(hot * TAU) * 0.02
			elif hot < HOE_STRIKE_AT:
				var k11: float = (hot - ows) / 0.14
				var e11: float = k11 * k11
				p["lift"] = lerpf(-1.0, 3.0, e11)
				p["rock"] = lerpf(-0.16, 0.22, e11)
				p["squash"] = lerpf(0.06, -0.05, e11) * sq
				p["crouch"] = lerpf(1.0, 3.0, e11)
			else:
				var k12: float = (hot - HOE_STRIKE_AT) / (1.0 - HOE_STRIKE_AT)
				var e12: float = 1.0 - (1.0 - k12) * (1.0 - k12)
				p["lift"] = lerpf(3.0, 0.0, e12)
				p["rock"] = lerpf(0.22, 0.0, e12)
				p["squash"] = lerpf(-0.05, 0.0, e12) * sq
				p["crouch"] = lerpf(3.0, 0.0, e12)
		FISH:
			# Rod fishing: CAST (lean in, line arcs out) -> WAIT (patient
			# hold — a moving hold with a rod-tip tremble, never frozen) ->
			# YANK (snap back at FISH_STRIKE_AT, the catch moment) ->
			# recover. Loops on the sim's catch cadence. Freeze-position:
			# the body never shifts horizontally.
			var fit: float = fmod(t, FISH_LEN) / FISH_LEN
			var cast_end := 0.28
			var yank_end: float = FISH_STRIKE_AT + 0.12
			if fit < cast_end:
				var k13: float = fit / cast_end
				var e13: float = k13 * k13
				p["lift"] = lerpf(0.0, -2.0, e13)
				p["rock"] = lerpf(0.02, 0.16, e13)   # lean into the cast
				p["crouch"] = lerpf(0.0, 1.5, e13)
				p["squash"] = lerpf(0.0, -0.04, e13) * sq  # stretch forward
				p["sway"] = sin(fit * TAU) * 0.012
			elif fit < FISH_STRIKE_AT:
				var bob: float = sin(t * 6.0 + phase)  # rod-tip tremble
				p["lift"] = -2.0 + bob * 0.6
				p["rock"] = 0.16 + bob * 0.012
				p["crouch"] = 1.5
				p["squash"] = -0.04 * sq
				p["sway"] = sin(fit * TAU * 2.0) * 0.008
			elif fit < yank_end:
				var k14: float = (fit - FISH_STRIKE_AT) / 0.12
				var e14: float = k14 * k14
				p["lift"] = lerpf(-2.0, 2.5, e14)
				p["rock"] = lerpf(0.16, -0.20, e14)  # snap back with the rod
				p["crouch"] = lerpf(1.5, 0.5, e14)
				p["squash"] = lerpf(-0.04, 0.05, e14) * sq
			else:
				var k15: float = (fit - yank_end) / (1.0 - yank_end)
				var e15: float = 1.0 - (1.0 - k15) * (1.0 - k15)
				p["lift"] = lerpf(2.5, 0.0, e15)
				p["rock"] = lerpf(-0.20, 0.02, e15)
				p["crouch"] = lerpf(0.5, 0.0, e15)
				p["squash"] = lerpf(0.05, 0.0, e15) * sq
		HUNT:
			# The hunt: STALK (low crouch, weapon coiled back — a moving
			# hold with a slow stalking weight shift, never frozen) ->
			# STRIKE (the kill blow lands at HUNT_STRIKE_AT, on the sim's
			# HUNT_CD cadence) -> RECOVER. Freeze-position: the body never
			# shifts horizontally.
			var hut: float = fmod(t, HUNT_LEN) / HUNT_LEN
			var stalk_end := 0.41
			if hut < stalk_end:
				var k16: float = hut / stalk_end
				var e16: float = k16 * k16
				var shift: float = sin(t * 3.0 + phase)
				p["lift"] = lerpf(0.0, -1.5, e16)
				p["rock"] = lerpf(0.0, -0.12, e16) + shift * 0.02
				p["crouch"] = lerpf(0.0, 2.5, e16)
				p["squash"] = lerpf(0.0, 0.05, e16) * sq
				p["sway"] = sin(hut * TAU) * 0.015
			elif hut < HUNT_STRIKE_AT:
				var k17: float = (hut - stalk_end) / (HUNT_STRIKE_AT - stalk_end)
				var e17: float = k17 * k17
				p["lift"] = lerpf(-1.5, 2.0, e17)
				p["rock"] = lerpf(-0.12, 0.24, e17)  # the blow lands
				p["crouch"] = lerpf(2.5, 1.0, e17)
				p["squash"] = lerpf(0.05, -0.06, e17) * sq
			else:
				var k18: float = (hut - HUNT_STRIKE_AT) / (1.0 - HUNT_STRIKE_AT)
				var e18: float = 1.0 - (1.0 - k18) * (1.0 - k18)
				p["lift"] = lerpf(2.0, 0.0, e18)
				p["rock"] = lerpf(0.24, 0.0, e18)
				p["crouch"] = lerpf(1.0, 0.0, e18)
				p["squash"] = lerpf(-0.06, 0.0, e18) * sq
		SIT:
			# Seated desk work: LEAN-IN (reach for the quill/ledger) ->
			# SCRIBE (writing/typing bursts — a moving hold, never frozen)
			# -> LEAN-BACK (read what you wrote) -> loop. The body stays
			# lowered on the chair the whole cycle (crouch ~6) and leans
			# toward the desk; the wrap eases back to the lean-in values so
			# the loop never pops. Freeze-position: the body never shifts
			# horizontally — the lean reads through rock, not position.
			var sit: float = fmod(t, SIT_LEN) / SIT_LEN
			var scribe_end := 0.70
			if sit < 0.25:
				var k19: float = sit / 0.25
				var e19: float = k19 * k19
				p["lift"] = lerpf(0.0, -1.0, e19)
				p["rock"] = lerpf(0.10, 0.20, e19)   # lean into the desk
				p["crouch"] = lerpf(6.5, 6.0, e19)   # perch up to reach
				p["squash"] = lerpf(0.03, 0.01, e19) * sq
				p["sway"] = sin(sit * TAU) * 0.008
			elif sit < scribe_end:
				var scrib: float = sin(t * 9.0 + phase)  # writing bursts
				p["lift"] = -1.0 + scrib * 0.7
				p["rock"] = 0.20 + sin(t * 9.0 + phase - 0.6) * 0.02
				p["crouch"] = 6.0 + sin(t * 4.5 + phase) * 0.3
				p["squash"] = 0.01 * sq
				p["sway"] = sin(t * 2.0 + phase) * 0.008
			else:
				var k20: float = (sit - scribe_end) / (1.0 - scribe_end)
				var e20: float = 1.0 - (1.0 - k20) * (1.0 - k20)
				p["lift"] = lerpf(-1.0, 0.0, e20)
				p["rock"] = lerpf(0.20, 0.10, e20)   # lean back, read it
				p["crouch"] = lerpf(6.0, 6.5, e20)
				p["squash"] = lerpf(0.01, 0.03, e20) * sq
		ATTACK:
			# 0.28 s: ANTICIPATE (dip back, coil) -> IMPACT (eased arc, not
			# linear) -> recover. Heavy bodies wind up longer within the
			# same game-matched window (Timing for Animation). Damage
			# itself is the game's clock; this is pure choreography.
			var at: float = clampf(t / ATTACK_LEN, 0.0, 1.0)
			var wu_end := lerpf(0.30, 0.42,
				clampf((weight - 0.7) / 1.1, 0.0, 1.0))
			if at < wu_end:
				var k: float = at / wu_end
				var e := k * k
				p["rock"] = -0.10 * e
				p["crouch"] = 1.5 * e        # anticipation dip
				p["squash"] = 0.05 * e * sq  # coil back
			elif at < 0.55:
				var k2: float = (at - wu_end) / (0.55 - wu_end)
				var e2 := k2 * k2            # eased arc (was linear)
				p["rock"] = -0.10 + 0.22 * e2
				p["squash"] = lerpf(0.05, -0.05, e2) * sq  # stretch into the hit
				p["crouch"] = lerpf(1.5, 0.0, e2)
			else:
				var k3: float = (at - 0.55) / 0.45
				var e: float = 1.0 - (1.0 - k3) * (1.0 - k3)
				p["rock"] = 0.12 * (1.0 - e)
				p["squash"] = -0.05 * (1.0 - e) * sq
		HURT:
			var ht: float = clampf(t / HURT_LEN, 0.0, 1.0)
			p["rock"] = -0.14 * (1.0 - ht) + sin(ht * 30.0) * 0.03 * (1.0 - ht)
			p["squash"] = 0.08 * (1.0 - ht) * sq   # flinch squash
		DEATH:
			# Fall flat over 0.45 s, then HOLD (uninterruptible). The hold
			# keeps a tiny settle — a moving hold, not a frozen frame.
			var dt: float = clampf(t / DEATH_LEN, 0.0, 1.0)
			var e2: float = 1.0 - pow(1.0 - dt, 3.0)
			p["rock"] = -PI / 2.0 * e2 * 0.94
			p["squash"] = 0.10 * e2 * sq
			if dt >= 1.0:
				p["rock"] += sin(t * 1.5) * 0.004 \
					* exp(-maxf(0.0, t - DEATH_LEN) * 3.0)
		CELEBRATE:
			# HTML "interact" (fix79): happy hop, arms up — one hop per
			# 0.9 s over the 2.4 s _celebrateT window. The crew that raised
			# a building hops with joy when it goes live.
			var hop: float = fmod(t, CELEBRATE_HOP) / CELEBRATE_HOP
			var hp := sin(hop * PI)
			p["lift"] = -hp * 7.0            # the hop (HTML s*0.16)
			p["crouch"] = (1.0 - hp) * 1.5   # coil at takeoff / landing
			p["squash"] = (hp * -0.05 + (1.0 - hp) * 0.04) * sq
			p["rock"] = sin(hop * TAU) * 0.05  # joyful wiggle
			p["sway"] = sin(hop * TAU + phase) * 0.01
		DANCE:
			# Festival dance loop: side-step groove on the weight-scaled
			# clock — ogres stomp slow, gnomes bounce fast. Per-unit phase
			# keeps the crowd out of sync; the Gazette's promised "Dancing!".
			var dp: float = t * 7.0 + phase
			var beat := sin(dp)
			p["lift"] = -absf(beat) * 3.0
			p["rock"] = beat * 0.14           # side-to-side line of action
			p["sway"] = sin(dp - 1.2) * 0.03
			p["squash"] = absf(beat) * 0.04 * sq
			p["crouch"] = 0.8
	# Follow-through ring lands on the loop states only.
	if (state == IDLE or state == WALK or state == DANCE) and fo != 0.0:
		p["rock"] = float(p["rock"]) + fo * 0.05
		p["squash"] = float(p["squash"]) + fo * 0.04
	# The sway channel rides on rotation (parity with apply_to, which sets
	# body.rotation = rock + sway); squash is clamped so the silhouette
	# stays readable (staging).
	p["rock"] = float(p["rock"]) + float(p["sway"])
	p["squash"] = clampf(float(p["squash"]), -0.16, 0.16)
	return p


## Apply the current pose to a feet-pivot Body node.
## Jeremy 2026-10-04: computes the choreography inline — no Dictionary
## allocation (was 14,400 allocs/sec across 240 units). pose() is kept for
## tests; this is the hot path.
func apply_to(body: Node2D) -> void:
	var lift := 0.0
	var rock := 0.0
	var crouch := 0.0
	var squash := 0.0
	var sway := 0.0
	var sq := _sq()
	var t: float = state_t
	# Follow-through ring after a settled one-shot (loop states only).
	var fo := 0.0
	if _follow_t < FOLLOW_LEN:
		fo = sin(_follow_t * 28.0) * _follow_amp * exp(-6.0 * _follow_t)
	match state:
		WALK:
			var ph: float = t * 9.0 + phase
			var c := sin(ph)
			var up1 := maxf(c, 0.0)
			var up2 := maxf(-c, 0.0) * 0.6   # Survival Kit double bounce
			lift = -(up1 + up2) * 4.4
			rock = c * 0.055
			sway = sin(ph - 1.2) * 0.02
			squash = (up1 + up2) * 0.06 * sq
		IDLE:
			var bt: float = t * 2.0 + phase
			var c2 := sin(bt)
			lift = c2 * -0.5
			squash = sin(bt * 0.5) * 0.015 * sq   # breathing (moving hold)
			rock = sin(bt * 0.7) * 0.012 \
				+ sin(t * 0.45 + phase) * 0.018  # weight-shift drift
			sway = sin(bt * 0.5 + 1.0) * 0.008
		WORK:
			var ph2: float = t * 7.0 + phase
			var sw2: float = sin(ph2)
			lift = -absf(sw2) * 1.5
			rock = 0.06 + sw2 * 0.05
			crouch = 1.2
			sway = sin(ph2 - 1.0) * 0.015
			squash = absf(sw2) * 0.02 * sq
		MINE:
			var mat: float = fmod(t, MINE_LEN) / MINE_LEN
			var mrs: float = MINE_STRIKE_AT - 0.12
			if mat < mrs:
				var k: float = mat / mrs
				var e: float = k * k
				lift = lerpf(0.0, -5.0, e)
				rock = lerpf(0.02, -0.18, e)
				squash = 0.06 * e * sq
				sway = sin(mat * TAU) * 0.015
			elif mat < MINE_STRIKE_AT:
				var k2: float = (mat - mrs) / 0.12
				var e2: float = k2 * k2
				lift = lerpf(-5.0, 3.0, e2)
				rock = lerpf(-0.18, 0.22, e2)
				squash = lerpf(0.06, -0.06, e2) * sq
				crouch = lerpf(0.0, 2.0, e2)
			else:
				var k3: float = (mat - MINE_STRIKE_AT) / (1.0 - MINE_STRIKE_AT)
				var e3: float = 1.0 - (1.0 - k3) * (1.0 - k3)
				lift = lerpf(3.0, 0.0, e3)
				rock = lerpf(0.22, 0.02, e3)
				squash = lerpf(-0.06, 0.0, e3) * sq
				crouch = lerpf(2.0, 0.0, e3)
		CHOP:
			var cat: float = fmod(t, CHOP_LEN) / CHOP_LEN
			var cws: float = CHOP_STRIKE_AT - 0.12
			if cat < cws:
				var k4: float = cat / cws
				var e4: float = k4 * k4
				rock = lerpf(0.0, -0.14, e4)
				squash = lerpf(0.0, 0.05, e4) * sq
				crouch = lerpf(0.0, 1.0, e4)
				sway = sin(cat * TAU) * 0.02
			elif cat < CHOP_STRIKE_AT:
				var k5: float = (cat - cws) / 0.12
				var e5: float = k5 * k5
				rock = lerpf(-0.14, 0.20, e5)
				lift = lerpf(0.0, 2.5, e5)
				squash = lerpf(0.05, -0.05, e5) * sq
				crouch = lerpf(1.0, 1.5, e5)
			else:
				var k6: float = (cat - CHOP_STRIKE_AT) / (1.0 - CHOP_STRIKE_AT)
				var e6: float = 1.0 - (1.0 - k6) * (1.0 - k6)
				rock = lerpf(0.20, 0.0, e6)
				lift = lerpf(2.5, 0.0, e6)
				squash = lerpf(-0.05, 0.0, e6) * sq
				crouch = lerpf(1.5, 0.0, e6)
		HAMMER:
			var hat: float = fmod(t, HAMMER_LEN) / HAMMER_LEN
			var hws: float = HAMMER_STRIKE_AT - 0.14
			if hat < hws:
				var k7: float = hat / hws
				var e7: float = k7 * k7
				lift = lerpf(0.0, -6.0, e7)
				rock = lerpf(0.02, -0.20, e7)
				squash = 0.06 * e7 * sq
				sway = sin(hat * TAU) * 0.015
			elif hat < HAMMER_STRIKE_AT:
				var k8: float = (hat - hws) / 0.14
				var e8: float = k8 * k8
				lift = lerpf(-6.0, 3.5, e8)
				rock = lerpf(-0.20, 0.24, e8)
				squash = lerpf(0.06, -0.07, e8) * sq
				crouch = lerpf(0.0, 2.5, e8)
			else:
				var k9: float = (hat - HAMMER_STRIKE_AT) / (1.0 - HAMMER_STRIKE_AT)
				var e9: float = 1.0 - (1.0 - k9) * (1.0 - k9)
				lift = lerpf(3.5, 0.0, e9)
				rock = lerpf(0.24, 0.02, e9)
				squash = lerpf(-0.07, 0.0, e9) * sq
				crouch = lerpf(2.5, 0.0, e9)
		HOE:
			var hot: float = fmod(t, HOE_LEN) / HOE_LEN
			var ows: float = HOE_STRIKE_AT - 0.14
			if hot < ows:
				var k10: float = hot / ows
				var e10: float = k10 * k10
				lift = lerpf(0.0, -1.0, e10)
				rock = lerpf(0.0, -0.16, e10)
				squash = lerpf(0.0, 0.06, e10) * sq
				crouch = lerpf(0.0, 1.0, e10)
				sway = sin(hot * TAU) * 0.02
			elif hot < HOE_STRIKE_AT:
				var k11: float = (hot - ows) / 0.14
				var e11: float = k11 * k11
				lift = lerpf(-1.0, 3.0, e11)
				rock = lerpf(-0.16, 0.22, e11)
				squash = lerpf(0.06, -0.05, e11) * sq
				crouch = lerpf(1.0, 3.0, e11)
			else:
				var k12: float = (hot - HOE_STRIKE_AT) / (1.0 - HOE_STRIKE_AT)
				var e12: float = 1.0 - (1.0 - k12) * (1.0 - k12)
				lift = lerpf(3.0, 0.0, e12)
				rock = lerpf(0.22, 0.0, e12)
				squash = lerpf(-0.05, 0.0, e12) * sq
				crouch = lerpf(3.0, 0.0, e12)
		FISH:
			var fit: float = fmod(t, FISH_LEN) / FISH_LEN
			var cast_end := 0.28
			var yank_end: float = FISH_STRIKE_AT + 0.12
			if fit < cast_end:
				var k13: float = fit / cast_end
				var e13: float = k13 * k13
				lift = lerpf(0.0, -2.0, e13)
				rock = lerpf(0.02, 0.16, e13)
				crouch = lerpf(0.0, 1.5, e13)
				squash = lerpf(0.0, -0.04, e13) * sq
				sway = sin(fit * TAU) * 0.012
			elif fit < FISH_STRIKE_AT:
				var bob: float = sin(t * 6.0 + phase)
				lift = -2.0 + bob * 0.6
				rock = 0.16 + bob * 0.012
				crouch = 1.5
				squash = -0.04 * sq
				sway = sin(fit * TAU * 2.0) * 0.008
			elif fit < yank_end:
				var k14: float = (fit - FISH_STRIKE_AT) / 0.12
				var e14: float = k14 * k14
				lift = lerpf(-2.0, 2.5, e14)
				rock = lerpf(0.16, -0.20, e14)
				crouch = lerpf(1.5, 0.5, e14)
				squash = lerpf(-0.04, 0.05, e14) * sq
			else:
				var k15: float = (fit - yank_end) / (1.0 - yank_end)
				var e15: float = 1.0 - (1.0 - k15) * (1.0 - k15)
				lift = lerpf(2.5, 0.0, e15)
				rock = lerpf(-0.20, 0.02, e15)
				crouch = lerpf(0.5, 0.0, e15)
				squash = lerpf(0.05, 0.0, e15) * sq
		HUNT:
			var hut: float = fmod(t, HUNT_LEN) / HUNT_LEN
			var stalk_end := 0.41
			if hut < stalk_end:
				var k16: float = hut / stalk_end
				var e16: float = k16 * k16
				var shift: float = sin(t * 3.0 + phase)
				lift = lerpf(0.0, -1.5, e16)
				rock = lerpf(0.0, -0.12, e16) + shift * 0.02
				crouch = lerpf(0.0, 2.5, e16)
				squash = lerpf(0.0, 0.05, e16) * sq
				sway = sin(hut * TAU) * 0.015
			elif hut < HUNT_STRIKE_AT:
				var k17: float = (hut - stalk_end) / (HUNT_STRIKE_AT - stalk_end)
				var e17: float = k17 * k17
				lift = lerpf(-1.5, 2.0, e17)
				rock = lerpf(-0.12, 0.24, e17)
				crouch = lerpf(2.5, 1.0, e17)
				squash = lerpf(0.05, -0.06, e17) * sq
			else:
				var k18: float = (hut - HUNT_STRIKE_AT) / (1.0 - HUNT_STRIKE_AT)
				var e18: float = 1.0 - (1.0 - k18) * (1.0 - k18)
				lift = lerpf(2.0, 0.0, e18)
				rock = lerpf(0.24, 0.0, e18)
				crouch = lerpf(1.0, 0.0, e18)
				squash = lerpf(-0.06, 0.0, e18) * sq
		SIT:
			var sit2: float = fmod(t, SIT_LEN) / SIT_LEN
			var scribe_end2 := 0.70
			if sit2 < 0.25:
				var k19: float = sit2 / 0.25
				var e19: float = k19 * k19
				lift = lerpf(0.0, -1.0, e19)
				rock = lerpf(0.10, 0.20, e19)
				crouch = lerpf(6.5, 6.0, e19)
				squash = lerpf(0.03, 0.01, e19) * sq
				sway = sin(sit2 * TAU) * 0.008
			elif sit2 < scribe_end2:
				var scrib2: float = sin(t * 9.0 + phase)
				lift = -1.0 + scrib2 * 0.7
				rock = 0.20 + sin(t * 9.0 + phase - 0.6) * 0.02
				crouch = 6.0 + sin(t * 4.5 + phase) * 0.3
				squash = 0.01 * sq
				sway = sin(t * 2.0 + phase) * 0.008
			else:
				var k20: float = (sit2 - scribe_end2) / (1.0 - scribe_end2)
				var e20: float = 1.0 - (1.0 - k20) * (1.0 - k20)
				lift = lerpf(-1.0, 0.0, e20)
				rock = lerpf(0.20, 0.10, e20)
				crouch = lerpf(6.0, 6.5, e20)
				squash = lerpf(0.01, 0.03, e20) * sq
		ATTACK:
			var at: float = clampf(t / ATTACK_LEN, 0.0, 1.0)
			var wu_end := lerpf(0.30, 0.42,
				clampf((weight - 0.7) / 1.1, 0.0, 1.0))
			if at < wu_end:
				var k: float = at / wu_end
				var e := k * k
				rock = -0.10 * e
				crouch = 1.5 * e
				squash = 0.05 * e * sq
			elif at < 0.55:
				var k2: float = (at - wu_end) / (0.55 - wu_end)
				var e2 := k2 * k2
				rock = -0.10 + 0.22 * e2
				squash = lerpf(0.05, -0.05, e2) * sq
				crouch = lerpf(1.5, 0.0, e2)
			else:
				var k3: float = (at - 0.55) / 0.45
				var e: float = 1.0 - (1.0 - k3) * (1.0 - k3)
				rock = 0.12 * (1.0 - e)
				squash = -0.05 * (1.0 - e) * sq
		HURT:
			var ht: float = clampf(t / HURT_LEN, 0.0, 1.0)
			rock = -0.14 * (1.0 - ht) + sin(ht * 30.0) * 0.03 * (1.0 - ht)
			squash = 0.08 * (1.0 - ht) * sq
		DEATH:
			var dt: float = clampf(t / DEATH_LEN, 0.0, 1.0)
			var e2: float = 1.0 - pow(1.0 - dt, 3.0)
			rock = -PI / 2.0 * e2 * 0.94
			squash = 0.10 * e2 * sq
			if dt >= 1.0:
				rock += sin(t * 1.5) * 0.004 \
					* exp(-maxf(0.0, t - DEATH_LEN) * 3.0)
		CELEBRATE:
			# HTML "interact" (fix79): happy hop, arms up — one hop per
			# 0.9 s over the 2.4 s _celebrateT window. Parity with pose().
			var hop: float = fmod(t, CELEBRATE_HOP) / CELEBRATE_HOP
			var hp := sin(hop * PI)
			lift = -hp * 7.0
			crouch = (1.0 - hp) * 1.5
			squash = (hp * -0.05 + (1.0 - hp) * 0.04) * sq
			rock = sin(hop * TAU) * 0.05
			sway = sin(hop * TAU + phase) * 0.01
		DANCE:
			# Festival dance loop, weight-scaled. Parity with pose().
			var dp: float = t * 7.0 + phase
			var beat := sin(dp)
			lift = -absf(beat) * 3.0
			rock = beat * 0.14
			sway = sin(dp - 1.2) * 0.03
			squash = absf(beat) * 0.04 * sq
			crouch = 0.8
	# Follow-through ring lands on the loop states only.
	if (state == IDLE or state == WALK or state == DANCE) and fo != 0.0:
		rock += fo * 0.05
		squash += fo * 0.04
	squash = clampf(squash, -0.16, 0.16)  # staging: silhouette stays readable
	body.position.y = lift + crouch
	body.rotation = rock + sway
	body.scale = Vector2(1.0 + squash, 1.0 - squash)


## Tool swing for MINE/CHOP (Jeremy 2026-10-04). Returns Vector2(angle,
## extension): the pivot rotation (radians; 0 = tool as drawn, negative =
## raised back, positive = swung down in front) and the forward reach in
## px. Value type — no allocation on the per-frame path. For any other
## state it returns the rest pose.
func tool_swing() -> Vector2:
	var t: float = state_t
	match state:
		MINE:
			var mat: float = fmod(t, MINE_LEN) / MINE_LEN
			var mrs: float = MINE_STRIKE_AT - 0.12
			var ang := 0.35
			var ext := 0.0
			if mat < mrs:
				var k: float = mat / mrs
				ang = lerpf(0.35, -2.3, k * k)
			elif mat < MINE_STRIKE_AT:
				var k2: float = (mat - mrs) / 0.12
				var e2: float = k2 * k2
				ang = lerpf(-2.3, 1.05, e2)
				ext = 6.0 * e2
			else:
				var k3: float = (mat - MINE_STRIKE_AT) / (1.0 - MINE_STRIKE_AT)
				var e3: float = 1.0 - (1.0 - k3) * (1.0 - k3)
				ang = lerpf(1.05, 0.35, e3)
				ext = lerpf(6.0, 0.0, e3)
			return Vector2(ang, ext)
		CHOP:
			var cat: float = fmod(t, CHOP_LEN) / CHOP_LEN
			var cws: float = CHOP_STRIKE_AT - 0.12
			var ang2 := 0.5
			var ext2 := 0.0
			if cat < cws:
				var k4: float = cat / cws
				ang2 = lerpf(0.5, -1.8, k4 * k4)
			elif cat < CHOP_STRIKE_AT:
				var k5: float = (cat - cws) / 0.12
				var e5: float = k5 * k5
				ang2 = lerpf(-1.8, 0.95, e5)
				# Jeremy 2026-10-05: bigger forward reach on the strike so
				# the chop reads clearly — the axe should visibly hit the tree.
				ext2 = 8.0 * e5
			else:
				var k6: float = (cat - CHOP_STRIKE_AT) / (1.0 - CHOP_STRIKE_AT)
				var e6: float = 1.0 - (1.0 - k6) * (1.0 - k6)
				ang2 = lerpf(0.95, 0.5, e6)
				ext2 = lerpf(8.0, 0.0, e6)
			return Vector2(ang2, ext2)
		HAMMER:
			# Overhead: rest at the shoulder -> both hands high -> slam down
			# in front -> recover. Heavier reach than MINE so the blow lands
			# visibly on the scaffold.
			var hat2: float = fmod(t, HAMMER_LEN) / HAMMER_LEN
			var hws2: float = HAMMER_STRIKE_AT - 0.14
			var ang7 := 0.4
			var ext7 := 0.0
			if hat2 < hws2:
				var k7: float = hat2 / hws2
				ang7 = lerpf(0.4, -2.5, k7 * k7)
			elif hat2 < HAMMER_STRIKE_AT:
				var k8: float = (hat2 - hws2) / 0.14
				var e8: float = k8 * k8
				ang7 = lerpf(-2.5, 1.1, e8)
				ext7 = 7.0 * e8
			else:
				var k9: float = (hat2 - HAMMER_STRIKE_AT) / (1.0 - HAMMER_STRIKE_AT)
				var e9: float = 1.0 - (1.0 - k9) * (1.0 - k9)
				ang7 = lerpf(1.1, 0.4, e9)
				ext7 = lerpf(7.0, 0.0, e9)
			return Vector2(ang7, ext7)
		HOE:
			# Side sweep: coil -> drag down into the soil (reach shortens —
			# the hoe digs IN, not through) -> pull back.
			var hot2: float = fmod(t, HOE_LEN) / HOE_LEN
			var ows2: float = HOE_STRIKE_AT - 0.14
			var ang10 := 0.5
			var ext10 := 0.0
			if hot2 < ows2:
				var k10: float = hot2 / ows2
				ang10 = lerpf(0.5, -1.6, k10 * k10)
			elif hot2 < HOE_STRIKE_AT:
				var k11: float = (hot2 - ows2) / 0.14
				var e11: float = k11 * k11
				ang10 = lerpf(-1.6, 1.0, e11)
				ext10 = 5.0 * e11
			else:
				var k12: float = (hot2 - HOE_STRIKE_AT) / (1.0 - HOE_STRIKE_AT)
				var e12: float = 1.0 - (1.0 - k12) * (1.0 - k12)
				ang10 = lerpf(1.0, 0.5, e12)
				ext10 = lerpf(5.0, 0.0, e12)
			return Vector2(ang10, ext10)
		FISH:
			# Rod work: cast the line out (reach grows as the line flies),
			# hold with a tremble, then YANK back over the shoulder at the
			# strike — the splash fires on that edge.
			var fit2: float = fmod(t, FISH_LEN) / FISH_LEN
			var ang11 := 0.35
			var ext11 := 0.0
			if fit2 < 0.28:
				var k13: float = fit2 / 0.28
				var e13: float = k13 * k13
				ang11 = lerpf(0.35, 1.15, e13)
				ext11 = 14.0 * e13
			elif fit2 < FISH_STRIKE_AT:
				ang11 = 1.15 + sin(t * 9.0 + phase) * 0.05
				ext11 = 14.0
			elif fit2 < FISH_STRIKE_AT + 0.12:
				var k14: float = (fit2 - FISH_STRIKE_AT) / 0.12
				var e14: float = k14 * k14
				ang11 = lerpf(1.15, -0.9, e14)
				ext11 = lerpf(14.0, 5.0, e14)
			else:
				var k15: float = (fit2 - FISH_STRIKE_AT - 0.12) \
					/ (1.0 - FISH_STRIKE_AT - 0.12)
				var e15: float = 1.0 - (1.0 - k15) * (1.0 - k15)
				ang11 = lerpf(-0.9, 0.35, e15)
				ext11 = lerpf(5.0, 0.0, e15)
			return Vector2(ang11, ext11)
		HUNT:
			# Spear/club arc: coil the weapon back low during the stalk,
			# whip it forward into the prey at the strike, ease home.
			var hut2: float = fmod(t, HUNT_LEN) / HUNT_LEN
			var ang12 := -0.5
			var ext12 := 0.0
			if hut2 < 0.41:
				var k16: float = hut2 / 0.41
				ang12 = lerpf(-0.5, -1.9, k16 * k16)
				ext12 = 4.0 * k16
			elif hut2 < HUNT_STRIKE_AT:
				var k17: float = (hut2 - 0.41) / (HUNT_STRIKE_AT - 0.41)
				var e17: float = k17 * k17
				ang12 = lerpf(-1.9, 1.2, e17)
				ext12 = lerpf(4.0, 10.0, e17)
			else:
				var k18: float = (hut2 - HUNT_STRIKE_AT) / (1.0 - HUNT_STRIKE_AT)
				var e18: float = 1.0 - (1.0 - k18) * (1.0 - k18)
				ang12 = lerpf(1.2, -0.5, e18)
				ext12 = lerpf(10.0, 0.0, e18)
			return Vector2(ang12, ext12)
	return Vector2(0.35, 0.0)


## Swing-loop length for the current state (0 when not a work swing), so
## the UnitNode can detect the strike edge without knowing the constants.
func work_loop_len() -> float:
	match state:
		MINE:
			return MINE_LEN
		CHOP:
			return CHOP_LEN
		HAMMER:
			return HAMMER_LEN
		HOE:
			return HOE_LEN
		FISH:
			return FISH_LEN
		HUNT:
			return HUNT_LEN
	return 0.0


## Cycle fraction where the tool lands (-1 when not a work swing).
func strike_frac() -> float:
	match state:
		MINE:
			return MINE_STRIKE_AT
		CHOP:
			return CHOP_STRIKE_AT
		HAMMER:
			return HAMMER_STRIKE_AT
		HOE:
			return HOE_STRIKE_AT
		FISH:
			return FISH_STRIKE_AT
		HUNT:
			return HUNT_STRIKE_AT
	return -1.0
