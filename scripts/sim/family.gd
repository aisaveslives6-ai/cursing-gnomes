class_name SimFamily
extends RefCounted

## Cursing Gnomes — Family & Belonging (HTML fix79 port, 2026-10-05).
##
## Ports the "FAMILY & BELONGING" section (fix79 index.html ~lines 31909-32391),
## Unit.tryRomance / tryVisitMilitarySpouse (~lines 34815-34920), and the
## leadership soul system (soulOf / leaderDeed / tickLeadership, ~32397-32496).
## This was the largest fully-unported life-sim chunk: Godot had zero spouse,
## bond, pregnancy, child, adventurer, or leadership-standing state.
##
## Systems ported (HTML-verbatim numbers noted):
##  1. Romance & marriage — workers court (opposite gender, nearby, low trait
##     friction); love builds while close; both love > 75 -> married.
##     Cross-faction weddings allowed (rarer, harder). Race-flavored lines.
##  2. Social bonds — background sampling: nearby pairs slowly form
##     like/dislike opinions (-100..100, capped at 24 bonds/unit, decay).
##  3. Pregnancy & children — happily married couples (love > 55, sharing a
##     claimed home) conceive; births respect Jeremy's pop caps AND need a
##     free bed at home; mixed-faction babies get blended heritage; children
##     stay near mother, then grow into jobless adults the guild hall hires.
##     The dead do not breed (C61).
##  4. Belonging — workers who hate their town petition to leave and become
##     adventurers; adventurers wander and may petition to join a faction
##     they like (cross-faction immigration, born_faction tracked).
##  5. Life decisions — the player's call goes through the Royal Court
##     petition list (Approve/Deny on the phone, per Jeremy's UI rules);
##     AI factions auto-resolve with HTML-verbatim odds (leave 0.12, join 0.55).
##  6. Leadership soul — per-faction standing/morality meters fed by deeds;
##     the leader's standing colors every citizen's mood drift; crossing a
##     band notifies the player.
##
## Improvements over HTML: decisions persist through save/load (HTML dropped
## them); romance/belonging run on staggered sweeps instead of per-frame
## unit methods (perf); speech bubbles are cooldown-throttled (HTML could
## bubble 1.8x/sec for close couples); children/adventurer movement reuses
## one walker instead of per-unit moveTarget fields.

const PREG_DAYS := 0.15        # HTML-verbatim: pregnancy length in game-days
const CHILD_GROW_DAYS := 1.2  # HTML-verbatim: childhood length in game-days
const MAX_BONDS := 24         # HTML-verbatim: max tracked relationships/unit
const SOCIAL_TICK := 1.5      # bond sampling cadence (HTML tickSocialSampling)
const FAMILY_TICK := 1.0      # pregnancy/birth cadence (HTML tickFamily)
const BELONG_TICK := 4.0      # belonging cadence (HTML tickBelonging)
const ADV_TICK := 3.0         # adventurer cadence (HTML tickAdventurers)
const SOUL_TICK := 3.0        # leadership cadence (HTML tickLeadership)
const LEAVE_AUTOYES := 0.12   # HTML-verbatim: AI lets a hater leave
const JOIN_AUTOYES := 0.55    # HTML-verbatim: AI welcomes a wanderer
const LEAVE_CD_DAYS := 120.0  # HTML-verbatim: factions bleed out slowly
const JOIN_CD_DAYS := 25.0    # HTML-verbatim: no re-asking for 25 days
const MARRY_LOVE := 75.0      # HTML-verbatim: wedding threshold
const CONCEIVE_LOVE := 55.0   # HTML-verbatim: conception needs happy couples
const BUBBLE_CD := 25.0       # anti-spam: min seconds between romance bubbles
const DECISION_TICK := 4.0    # stale-decision sweep cadence (matches belonging)
const DECISION_STALE_DAYS := 2.0  # unanswered player petitions auto-decide after this

var _gs: GameState
var _bus: Object
var _urges: SimUrges
var _court = null       # SimRoyalCourt — set by world; null in headless tests
var _spawner = null     # SimSpawner — set by world; null in headless tests
var _rng := RandomNumberGenerator.new()

# Leadership souls: faction -> {standing, morality, deeds: Array}
var _souls: Dictionary = {}
# Pending player decisions: petition_id -> {kind, unit_id, faction, auto_yes}
var _pending: Dictionary = {}
var _petition_seq := 1

var _social_acc := 0.0
var _family_acc := 0.0
var _belong_acc := 0.0
var _adv_acc := 0.0
var _soul_acc := 0.0
var _decision_acc := 0.0  # stale-decision sweep accumulator; ephemeral (not saved)
var _move_frame := 0  # movement-sweep stagger counter; ephemeral (not saved)
var _belong_tick := 0
var _leave_throttle: Dictionary = {}  # faction -> last belong_tick petition


func _init(game_state: GameState) -> void:
	_gs = game_state
	_bus = game_state.bus
	_urges = SimUrges.new(game_state)
	_rng.randomize()
	if _bus != null and _bus.has_signal("petition_decided"):
		_bus.petition_decided.connect(_on_petition_decided)


## Lazily stamps family fields on a unit record. Idempotent.
func ensure(unit: Dictionary) -> void:
	if unit.has("spouse_uid"):
		return
	unit["spouse_uid"] = -1
	unit["partner_uid"] = -1
	unit["love"] = 0.0
	unit["romance_cd"] = 8.0 + _rng.randf() * 20.0
	unit["bonds"] = {}
	unit["heritage"] = ""
	unit["is_child"] = false
	unit["is_baby"] = false
	unit["age_days"] = 0.0
	unit["mother_uid"] = -1
	unit["father_uid"] = -1
	unit["preg_timer"] = 0.0
	unit["leave_cd"] = 0.0
	unit["adventurer"] = false
	unit["join_cd"] = 0.0
	unit["born_faction"] = String(unit.get("faction", ""))
	unit["last_intimacy"] = 0.0
	unit["family_walk"] = Vector2.ZERO
	unit["family_walking"] = false
	unit["family_bubble_cd"] = 0.0
	unit["birth_msg_cd"] = 0.0


func _days(delta: float) -> float:
	return delta * 24.0 / Config.DAY_LENGTH_SECONDS


func _unit_by_id(uid: int) -> Dictionary:
	if uid < 0:
		return {}
	return _gs.get_unit(uid)


func _unit_name(u: Dictionary) -> String:
	return SimPersonality.display_name(u)


func _say(unit_id: int, text: String) -> void:
	if _bus != null:
		_bus.unit_said.emit(unit_id, text)


func _gazette(headline: String, body: String, kind: String) -> void:
	if _bus != null:
		# Jeremy 2026-10-06 launch readiness (gate 4): story text must be
		# glyph-free (test_gazette_glyphs.gd standing rule) — publish_story
		# sanitizes on the Chronicle path (tofu boxes on iPhone otherwise).
		SimGazette.publish_or_emit(_gs,
			SimGazette.sanitize_story_text(headline),
			SimGazette.sanitize_story_text(body), kind)


func _is_player_faction(faction: String) -> bool:
	if faction == "":
		return false
	var pf = _gs.get("player_faction")
	return pf != null and faction == String(pf)


# --- master tick ------------------------------------------------------------

## Called every physics frame by world.gd. The movement sweep staggers to
## every 3rd frame (20 Hz, delta-scaled: identical walker speed, arrival timing
## and wander probabilities); the life-sim state machines run on their HTML
## cadences via accumulators.
func tick(delta: float) -> void:
	_move_frame += 1
	if _move_frame % 3 == 0:
		_move_walkers(delta * 3.0)
	_social_acc += delta
	if _social_acc >= SOCIAL_TICK:
		_tick_social(_social_acc)
		_social_acc = 0.0
	_family_acc += delta
	if _family_acc >= FAMILY_TICK:
		_tick_family(_family_acc)
		_family_acc = 0.0
	_belong_acc += delta
	if _belong_acc >= BELONG_TICK:
		_tick_belonging(_belong_acc)
		_belong_acc = 0.0
	_adv_acc += delta
	if _adv_acc >= ADV_TICK:
		_tick_adventurers(_adv_acc)
		_adv_acc = 0.0
	_decision_acc += delta
	if _decision_acc >= DECISION_TICK:
		_tick_decisions(_decision_acc)
		_decision_acc = 0.0
	_soul_acc += delta
	if _soul_acc >= SOUL_TICK:
		_tick_leadership()
		_soul_acc = 0.0


## Walks family-owned movers: romance partners, intimacy reunions, children,
## adventurers. Never fights other systems: only units WE flagged.
func _move_walkers(delta: float) -> void:
	for u in _gs.units:
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		ensure(u)
		if bool(u.get("is_child", false)):
			_tick_child_move(u, delta)
			continue
		if not bool(u.get("family_walking", false)):
			continue
		# Yield to anything more important the brain is doing.
		if _busy(u):
			u["family_walking"] = false
			continue
		var target: Vector2 = u["family_walk"]
		var pos: Vector2 = u.get("position", Vector2.ZERO)
		var speed := float(u.get("speed", 30.0))
		var d := target - pos
		if d.length() < 12.0:
			u["family_walking"] = false
			_check_reunion(u)
			continue
		# Jeremy 2026-10-05: water rules — family walks avoid water
		# unless fleeing.
		var fstep: Vector2 = d.normalized() * speed * delta
		var fnp: Vector2 = pos + fstep
		if WaterNav.unit_avoids_water(u):
			fnp = WaterNav.dry_step(_gs.map_data, pos, fstep)
		u["position"] = fnp
		u["swimming"] = WaterNav.is_water_at(_gs.map_data, fnp)


## True when the unit is committed to something family movement must not
## interrupt (combat, orders, urges, work, flight).
func _busy(u: Dictionary) -> bool:
	if bool(u.get("fleeing", false)) or bool(u.get("withdrawing", false)):
		return true
	if bool(u.get("flood_flee", false)) or bool(u.get("_siege_hide", false)):
		return true
	if String(u.get("mind_state", "")).begins_with("satisfying:"):
		return true
	if u.get("player_order") != null:
		return true
	if String(u.get("work_state", "")) != "" and String(u.get("work_state", "idle")) != "idle":
		return true
	return false


func _civilian_worker(u: Dictionary) -> bool:
	if bool(u.get("is_child", false)) or bool(u.get("is_leader", false)):
		return false
	if bool(u.get("adventurer", false)):
		return false
	if bool(u.get("is_advisor", false)):
		return false
	var job := String(u.get("job", "worker"))
	if JobDefs.is_military(job):
		return false
	return job == "worker" or job == "roadbuilder" or bool(u.get("is_worker", false))


# --- leadership soul --------------------------------------------------------

func soul_of(faction: String) -> Dictionary:
	if not _souls.has(faction):
		_souls[faction] = {"standing": 20.0, "morality": 10.0, "deeds": []}
	return _souls[faction]


static func standing_label(v: float) -> String:
	if v >= 70.0: return "Adored"
	if v >= 40.0: return "Loved"
	if v >= 10.0: return "Trusted"
	if v >= -10.0: return "Tolerated"
	if v >= -40.0: return "Disliked"
	return "Despised"


static func morality_label(v: float) -> String:
	if v >= 70.0: return "Saintly"
	if v >= 40.0: return "Honorable"
	if v >= 10.0: return "Decent"
	if v >= -10.0: return "Gray"
	if v >= -40.0: return "Ruthless"
	return "Tyrannical"


## Every choice is a deed: moves standing/morality, is remembered (cap 10),
## and teaches. HTML leaderDeed verbatim, minus the DOM HUD/toast.
func leader_deed(faction: String, d_stand: float, d_mor: float,
		text: String, lesson: String = "") -> void:
	var s := soul_of(faction)
	var old_s := float(s["standing"])
	var old_m := float(s["morality"])
	s["standing"] = clampf(old_s + d_stand, -100.0, 100.0)
	s["morality"] = clampf(old_m + d_mor, -100.0, 100.0)
	var deeds: Array = s["deeds"]
	deeds.push_front({"text": text, "ds": d_stand, "dm": d_mor,
		"day": int(_gs.get("day_number"))})
	while deeds.size() > 10:
		deeds.pop_back()
	_check_soul_thresholds(faction, old_s, old_m)
	if _is_player_faction(faction) and _bus != null:
		# HTML queueLeaderToast -> player phone message with the lesson.
		var msg := text
		if lesson != "":
			msg += " " + lesson
		_bus.phone_message.emit("leader", msg)


func _check_soul_thresholds(faction: String, old_s: float, old_m: float) -> void:
	if not _is_player_faction(faction) or _bus == null:
		return
	var s := soul_of(faction)
	if standing_label(old_s) != standing_label(float(s["standing"])):
		_bus.phone_message.emit("leader",
			"Your people now see you as %s. Trust is earned in drops and kept the same way."
			% standing_label(float(s["standing"])))
	if morality_label(old_m) != morality_label(float(s["morality"])):
		_bus.phone_message.emit("leader",
			"Your faction drifts toward %s. Cruelty is a habit; your people learn it from you."
			% morality_label(float(s["morality"])))


## HTML tickLeadership: the leader's standing colors every citizen's mood.
func _tick_leadership() -> void:
	if _gs.units.is_empty():
		return
	for k in 8:
		var u: Dictionary = _gs.units[_rng.randi() % _gs.units.size()]
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		if bool(u.get("is_child", false)):
			continue
		ensure(u)
		var s := soul_of(String(u.get("faction", "")))
		var drift := float(s["standing"]) / 120.0 + float(s["morality"]) / 160.0
		var urges: Dictionary = _urges.ensure(u)
		urges["mood"] = clampf(float(urges.get("mood", 50.0)) + drift * 3.0, 0.0, 100.0)


# --- social bonds -----------------------------------------------------------

## HTML C58C_FRIEND_SCORE: bond value at/above which two NPCs count as
## friends (matches the game's existing friends threshold).
const FRIEND_SCORE := 35.0
## HTML pickVictim55: a crook only targets NPCs it dislikes this much.
const VICTIM_DISLIKE := -14.0
## How far an NPC will look for a friend when the social urge bites.
const FRIEND_SEEK_RADIUS := 900.0


func get_affinity(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	ensure(a)
	var bonds: Dictionary = a["bonds"]
	return float(bonds.get(str(int(b.get("id", -1))), 0.0))


## HTML bondsScore: the stored affinity, else trait friction * -22
## (strangers are judged on personality alone).
func bonds_score(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	ensure(a)
	var bonds: Dictionary = a["bonds"]
	var kb := str(int(b.get("id", -1)))
	if bonds.has(kb):
		return float(bonds[kb])
	return trait_friction(a, b) * -22.0


## HTML c58cIsFriendOrBetter, NPC-NPC edition. Friendship needs a real
## stored bond (shared-personality strangers are NOT friends — the
## trait-friction fallback in bonds_score is for first impressions only).
func is_friend(a: Dictionary, b: Dictionary) -> bool:
	return get_affinity(a, b) >= FRIEND_SCORE


## Best friend in range: highest bond at/above FRIEND_SCORE, alive, same
## faction. Children and leaders never formed bonds (HTML's
## tickSocialSampling skipped them), so they are not valid targets.
func best_friend(unit: Dictionary, max_dist: float) -> Dictionary:
	if unit.is_empty() or not bool(unit.get("alive", false)):
		return {}
	ensure(unit)
	var uid: int = int(unit.get("id", -1))
	var faction := String(unit.get("faction", ""))
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_score := FRIEND_SCORE
	for c: Dictionary in _gs.units:
		if not (c is Dictionary):
			continue
		if int(c.get("id", -1)) == uid:
			continue
		if not bool(c.get("alive", false)):
			continue
		if bool(c.get("is_child", false)) or bool(c.get("is_leader", false)):
			continue
		if String(c.get("faction", "")) != faction:
			continue
		if upos.distance_to(c.get("position", Vector2.ZERO)) > max_dist:
			continue
		# Stored bonds only: first-impression friction is not friendship.
		var s := get_affinity(unit, c)
		if s >= best_score:
			best_score = s
			best = c
	return best


func _trim_bonds(u: Dictionary) -> void:
	var bonds: Dictionary = u["bonds"]
	if bonds.size() <= MAX_BONDS:
		return
	var keys := bonds.keys()
	keys.sort_custom(func(x, y): return absf(float(bonds[y])) < absf(float(bonds[x])))
	for i in range(MAX_BONDS, keys.size()):
		bonds.erase(keys[i])


## HTML bumpAffinity: mutual like/dislike shift, clamped [-100, 100].
func bump_affinity(a: Dictionary, b: Dictionary, d: float) -> void:
	if a.is_empty() or b.is_empty() or a == b:
		return
	if not bool(a.get("alive", false)) or not bool(b.get("alive", false)):
		return
	if bool(a.get("is_child", false)) or bool(b.get("is_child", false)):
		return
	ensure(a)
	ensure(b)
	var ka := str(int(a.get("id", -1)))
	var kb := str(int(b.get("id", -1)))
	a["bonds"][kb] = clampf(float(a["bonds"].get(kb, 0.0)) + d, -100.0, 100.0)
	b["bonds"][ka] = clampf(float(b["bonds"].get(ka, 0.0)) + d * 0.9, -100.0, 100.0)
	_trim_bonds(a)
	_trim_bonds(b)


## HTML traitFriction, mapped onto Godot's float traits (has = > 0.65):
## cheerful/grumpy -> friendly/crude, industrious/lazy -> diligent,
## brave/coward -> brave; shared strong traits ease friction.
func trait_friction(a: Dictionary, b: Dictionary) -> float:
	var ta: Dictionary = SimPersonality.traits_for(int(a.get("id", 0)), String(a.get("faction", "humans")))
	var tb: Dictionary = SimPersonality.traits_for(int(b.get("id", 0)), String(b.get("faction", "humans")))
	var f := 0.0
	if float(ta.get("friendly", 0.0)) > 0.65 and float(tb.get("crude", 0.0)) > 0.65:
		f += 1.0
	if float(ta.get("diligent", 0.0)) > 0.65 and float(tb.get("diligent", 0.0)) < 0.35:
		f += 1.0
	if float(ta.get("brave", 0.0)) > 0.65 and float(tb.get("brave", 0.0)) < 0.35:
		f += 0.5
	for t in ["brave", "friendly", "diligent", "crude", "proud"]:
		if float(ta.get(t, 0.0)) > 0.65 and float(tb.get(t, 0.0)) > 0.65:
			f -= 0.6
	return f


## HTML tickSocialSampling: 6 random nearby pairs per 1.5s form opinions;
## one random unit's bonds decay toward neutral.
func _tick_social(step: float) -> void:
	var units := _gs.units
	if units.is_empty():
		return
	for k in 6:
		var a: Dictionary = units[_rng.randi() % units.size()]
		if not (a is Dictionary) or not bool(a.get("alive", false)):
			continue
		if bool(a.get("is_child", false)) or bool(a.get("is_leader", false)):
			continue
		ensure(a)
		var b: Dictionary = {}
		for t in 12:
			var c: Dictionary = units[_rng.randi() % units.size()]
			if not (c is Dictionary) or c == a or not bool(c.get("alive", false)):
				continue
			if bool(c.get("is_child", false)):
				continue
			var pa: Vector2 = a.get("position", Vector2.ZERO)
			var pc: Vector2 = c.get("position", Vector2.ZERO)
			if pa.distance_to(pc) < 420.0:
				b = c
				break
		if b.is_empty():
			continue
		var fr := trait_friction(a, b)
		var d := (_rng.randf() - 0.5) * 4.0 - fr * 1.2
		if int(a.get("spouse_uid", -1)) == int(b.get("id", -2)):
			d += 2.0
		bump_affinity(a, b, d)
	# Slow decay toward neutral for one random unit's bonds.
	var u: Dictionary = units[_rng.randi() % units.size()]
	if (u is Dictionary) and bool(u.get("alive", false)) and u.has("bonds"):
		ensure(u)
		var bonds: Dictionary = u["bonds"]
		for key in bonds.keys():
			var other := _unit_by_id(int(key))
			if other.is_empty():
				bonds.erase(key)
				continue
			bonds[key] = float(bonds[key]) * 0.995
			if absf(float(bonds[key])) < 0.5:
				bonds.erase(key)
	# Romance sweep rides the social tick (HTML called tryRomance from the
	# unit's social slot; a staggered sweep is the perf-safe equivalent).
	_tick_romance(step)


# --- romance & marriage -----------------------------------------------------

## HTML Unit.tryRomance, adapted to a sweep: per-frame probabilities are
## normalized to the sweep cadence (p_step = 1-(1-p)^(60*step)).
func _tick_romance(step: float) -> void:
	var units := _gs.units
	if units.is_empty():
		return
	for u in units:
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		if not _civilian_worker(u):
			continue
		if _busy(u):
			continue
		ensure(u)
		u["romance_cd"] = float(u.get("romance_cd", 0.0)) - step
		u["last_intimacy"] = float(u.get("last_intimacy", 0.0)) - step
		u["family_bubble_cd"] = maxf(0.0, float(u.get("family_bubble_cd", 0.0)) - step)
		_try_intimacy(u)
		_try_romance(u, step)
		_try_visit_military_spouse(u, step)


func _bubble(u: Dictionary, text: String) -> void:
	if float(u.get("family_bubble_cd", 0.0)) > 0.0:
		return
	u["family_bubble_cd"] = BUBBLE_CD
	_say(int(u.get("id", 0)), text)


func _try_romance(u: Dictionary, step: float) -> void:
	var spouse := _unit_by_id(int(u.get("spouse_uid", -1)))
	if not spouse.is_empty():
		# Already married — love deepens; seek spouse occasionally.
		u["love"] = minf(100.0, float(u.get("love", 50.0)) + step * 0.4)
		if float(u.get("romance_cd", 0.0)) <= 0.0 \
				and _roll(0.01, step) \
				and _dist(u, spouse) < 200.0:
			_bubble(u, _married_line(String(u.get("faction", ""))))
			u["romance_cd"] = 20.0
		return
	var partner := _unit_by_id(int(u.get("partner_uid", -1)))
	if not partner.is_empty():
		# Courtship: love grows near each other, eased by low friction.
		var fr := trait_friction(u, partner)
		u["love"] = minf(100.0, float(u.get("love", 0.0)) + step * (1.2 - fr * 0.3))
		if _dist(u, partner) < 40.0:
			var urges: Dictionary = _urges.ensure(u)
			urges["social"] = minf(100.0, float(urges.get("social", 50.0)) + step * 12.0)
			if float(u.get("love", 0.0)) > MARRY_LOVE \
					and float(partner.get("love", 0.0)) > MARRY_LOVE \
					and int(u.get("spouse_uid", -1)) < 0:
				_marry(u, partner)
			elif _roll(0.03, step):
				_bubble(u, _court_line(String(u.get("faction", ""))))
		elif float(u.get("romance_cd", 0.0)) <= 0.0:
			u["family_walk"] = partner.get("position", Vector2.ZERO)
			u["family_walking"] = true
		return
	# Find a partner (HTML: 0.015/frame, cross-faction rarer and harder).
	if float(u.get("romance_cd", 0.0)) > 0.0:
		return
	if not _roll(0.015, step):
		u["romance_cd"] = 10.0
		return
	var best: Dictionary = {}
	var best_s := INF
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	for c in _gs.units:
		if not (c is Dictionary) or c == u or not bool(c.get("alive", false)):
			continue
		if bool(c.get("is_child", false)):
			continue
		if not _civilian_worker(c):
			continue
		if int(c.get("spouse_uid", -1)) >= 0:
			continue
		if String(c.get("gender", "")) == String(u.get("gender", "")):
			continue
		if int(c.get("partner_uid", -1)) >= 0 \
				and int(c.get("partner_uid", -1)) != int(u.get("id", -1)):
			continue
		var cross := String(c.get("faction", "")) != String(u.get("faction", ""))
		if cross and _rng.randf() < 0.7:
			continue  # cross-faction love is uncommon
		var d := upos.distance_to(c.get("position", Vector2.ZERO)) \
			+ trait_friction(u, c) * 40.0 + (170.0 if cross else 0.0)
		if d < best_s and d < (220.0 if cross else 280.0):
			best_s = d
			best = c
	if not best.is_empty():
		u["partner_uid"] = int(best.get("id", -1))
		best["partner_uid"] = int(u.get("id", -1))
		u["love"] = 15.0
		best["love"] = maxf(float(best.get("love", 0.0)), 10.0)
		u["romance_cd"] = 12.0
		_bubble(u, _meet_line(String(u.get("faction", ""))))
	else:
		u["romance_cd"] = 10.0


func _marry(a: Dictionary, b: Dictionary) -> void:
	a["spouse_uid"] = int(b.get("id", -1))
	b["spouse_uid"] = int(a.get("id", -1))
	a["partner_uid"] = int(b.get("id", -1))
	b["partner_uid"] = int(a.get("id", -1))
	bump_affinity(a, b, 80.0)
	_bubble(a, _wed_line(String(a.get("faction", ""))))
	_say(int(b.get("id", 0)), "❤")
	var cross := String(a.get("faction", "")) != String(b.get("faction", ""))
	if cross:
		_gazette("💍 CROSS-FACTION WEDDING",
			"%s (%s) married %s (%s)!" % [_unit_name(a), String(a.get("faction", "")),
				_unit_name(b), String(b.get("faction", ""))], "family")
	# A wedding is a deed for both factions' leaders to remember.
	leader_deed(String(a.get("faction", "")), 2.0, 1.0,
		"%s married %s." % [_unit_name(a), _unit_name(b)])
	if cross:
		leader_deed(String(b.get("faction", "")), 2.0, 1.0,
			"%s married into the %s." % [_unit_name(b), String(a.get("faction", ""))])


## HTML intimacy: married couples with low social need reunite at home.
func _try_intimacy(u: Dictionary) -> void:
	if float(u.get("last_intimacy", 0.0)) > 0.0:
		return
	var spouse := _unit_by_id(int(u.get("spouse_uid", -1)))
	if spouse.is_empty():
		return
	if _urges.value(u, "social") >= SimUrges.SOCIAL_DONE:
		return
	var home: Dictionary = u.get("home", {})
	var shome: Dictionary = spouse.get("home", {})
	if home.is_empty() or shome.is_empty():
		return
	if int(home.get("id", -1)) != int(shome.get("id", -2)):
		return  # HTML C58c: conception/intimacy needs a SHARED home
	u["last_intimacy"] = 300.0
	var hp: Vector2 = home.get("position", Vector2.ZERO)
	u["family_walk"] = hp
	u["family_walking"] = true
	spouse["family_walk"] = hp
	spouse["family_walking"] = true


## When both spouses reach home for a reunion, closeness pays off.
func _check_reunion(u: Dictionary) -> void:
	var spouse := _unit_by_id(int(u.get("spouse_uid", -1)))
	if spouse.is_empty():
		return
	if bool(spouse.get("family_walking", false)):
		return  # still on the way
	var up: Vector2 = u.get("position", Vector2.ZERO)
	var sp: Vector2 = spouse.get("position", Vector2.ZERO)
	var home: Dictionary = u.get("home", {})
	var hp: Vector2 = home.get("position", Vector2.ZERO)
	if up.distance_to(hp) < 60.0 and sp.distance_to(hp) < 60.0:
		var uu: Dictionary = _urges.ensure(u)
		var us: Dictionary = _urges.ensure(spouse)
		uu["social"] = minf(100.0, float(uu.get("social", 50.0)) + 40.0)
		us["social"] = minf(100.0, float(us.get("social", 50.0)) + 40.0)
		uu["mood"] = minf(100.0, float(uu.get("mood", 50.0)) + 30.0)
		us["mood"] = minf(100.0, float(us.get("mood", 50.0)) + 30.0)
		u["love"] = minf(100.0, float(u.get("love", 50.0)) + 10.0)
		spouse["love"] = minf(100.0, float(spouse.get("love", 50.0)) + 10.0)


## HTML tryVisitMilitarySpouse: civilians visit a soldier spouse at the base.
func _try_visit_military_spouse(u: Dictionary, step: float) -> void:
	var spouse := _unit_by_id(int(u.get("spouse_uid", -1)))
	if spouse.is_empty():
		return
	if not JobDefs.is_military(String(spouse.get("job", ""))):
		return
	if not _roll(0.002, step):
		return
	u["family_walk"] = spouse.get("position", Vector2.ZERO)
	u["family_walking"] = true
	_bubble(u, "Visiting my love at the base.")


func _roll(p_per_frame: float, step: float) -> bool:
	return _rng.randf() < 1.0 - pow(1.0 - p_per_frame, 60.0 * step)


func _dist(a: Dictionary, b: Dictionary) -> float:
	return (a.get("position", Vector2.ZERO) as Vector2).distance_to(
		b.get("position", Vector2.ZERO))


func _married_line(faction: String) -> String:
	match faction:
		"ogres": return "Love you. Big."
		"gnomes": return "Still stuck with you…"
		"elves": return "My heart is yours."
		_: return "My love."


func _court_line(faction: String) -> String:
	match faction:
		"ogres": return "Like you."
		"gnomes": return "You're… alright."
		_: return "I adore you."


func _meet_line(faction: String) -> String:
	match faction:
		"ogres": return "You nice."
		"gnomes": return "Oi… fancy a drink?"
		"elves": return "Walk with me under the leaves."
		_: return "Might I walk beside you?"


func _wed_line(faction: String) -> String:
	match faction:
		"ogres": return "We married!"
		"gnomes": return "Fine, we're married, bastard."
		"elves": return "Bound under the trees."
		_: return "We're married!"


# --- pregnancy, birth, children ---------------------------------------------

## HTML tickFamily: pregnancies count down; happily married couples sharing
## a claimed home conceive (HTML-verbatim gates + C58c shared-bed rule).
func _tick_family(step: float) -> void:
	var dt_days := _days(step)
	for u in _gs.units:
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		if bool(u.get("is_child", false)):
			continue
		ensure(u)
		if float(u.get("preg_timer", 0.0)) > 0.0:
			u["preg_timer"] = float(u.get("preg_timer", 0.0)) - dt_days
			if float(u.get("preg_timer", 0.0)) <= 0.0:
				_birth_child(u)
			continue
		_try_conceive(u, step, dt_days)
	# Children age on the same tick.
	for u in _gs.units:
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		if not bool(u.get("is_child", false)):
			continue
		ensure(u)
		u["age_days"] = float(u.get("age_days", 0.0)) + dt_days
		if float(u.get("age_days", 0.0)) >= CHILD_GROW_DAYS:
			_grow_up(u)


func _try_conceive(u: Dictionary, step: float, _dt_days: float) -> void:
	if String(u.get("gender", "")) != "f":
		return
	var spouse := _unit_by_id(int(u.get("spouse_uid", -1)))
	if spouse.is_empty() or bool(spouse.get("is_child", false)):
		return
	if bool(u.get("adventurer", false)):
		return
	if String(u.get("faction", "")) == "undead":
		return  # C61: the dead do not breed
	if float(u.get("love", 0.0)) <= CONCEIVE_LOVE:
		return
	if float(spouse.get("love", 0.0)) <= CONCEIVE_LOVE:
		return
	var home: Dictionary = u.get("home", {})
	if home.is_empty():
		return
	var up: Vector2 = u.get("position", Vector2.ZERO)
	var hp: Vector2 = home.get("position", Vector2.ZERO)
	if up.distance_to(hp) >= 220.0:
		return
	# C58c: spontaneous conception only for couples sharing a claimed home.
	var shome: Dictionary = spouse.get("home", {})
	if shome.is_empty() or int(shome.get("id", -1)) != int(home.get("id", -2)):
		return
	if _rng.randf() < step * 0.004:
		u["preg_timer"] = PREG_DAYS
		_bubble(u, "Expecting!")


## HTML birthChild: pop caps, a free bed at home, then the baby arrives.
## Mixed-faction parents make a mixed baby (blended heritage tag).
func _birth_child(mother: Dictionary) -> void:
	mother["preg_timer"] = 0.0
	if String(mother.get("faction", "")) == "undead":
		return  # C61: necromancers raise the fallen instead
	var faction := String(mother.get("faction", ""))
	var town_id := int(mother.get("town_id", -1))
	# Jeremy 2026-09-28: no births past the civilian cap — full towns wait.
	if _spawner != null and _spawner.has_method("check_spawn"):
		if String(_spawner.check_spawn(faction, "child", town_id)) != "ok":
			mother["preg_timer"] = 0.02  # wait for room, never a silent loss
			return
	# C58c: the birth waits for a free bed — a clear in-game reason.
	var home: Dictionary = mother.get("home", {})
	if not home.is_empty():
		var residents: Array = home.get("residents", [])
		if residents.size() >= SimHousing.HOUSEHOLD_CAP:
			mother["preg_timer"] = 0.02
			mother["birth_msg_cd"] = float(mother.get("birth_msg_cd", 0.0)) - 0.02
			if float(mother.get("birth_msg_cd", 0.0)) <= 0.0:
				mother["birth_msg_cd"] = 1.0
				_bubble(mother, "No free bed at home!")
				if _is_player_faction(faction):
					_bus.phone_message.emit("family",
						"%s is ready to give birth, but there's no free bed at home."
						% _unit_name(mother))
			return
	var father := _unit_by_id(int(mother.get("spouse_uid", -1)))
	var mpos: Vector2 = mother.get("position", Vector2.ZERO)
	var child: Dictionary
	if _spawner != null and _spawner.has_method("spawn_unit"):
		child = _spawner.spawn_unit(faction, "child", town_id, mpos + Vector2(10, 10))
	else:
		child = _gs.add_unit({"faction": faction, "job": "child",
			"town_id": town_id, "position": mpos + Vector2(10, 10), "alive": true})
	if child.is_empty():
		mother["preg_timer"] = 0.02
		return
	ensure(child)
	child["is_child"] = true
	child["is_baby"] = true
	child["age_days"] = 0.0
	child["mother_uid"] = int(mother.get("id", -1))
	child["father_uid"] = int(father.get("id", -1)) if not father.is_empty() else -1
	child["born_faction"] = faction
	if not home.is_empty():
		child["home"] = home
		var residents: Array = home.get("residents", [])
		var cid := int(child.get("id", -1))
		if not cid in residents and residents.size() < SimHousing.HOUSEHOLD_CAP:
			residents.append(cid)
	var frace := String(father.get("faction", faction)) if not father.is_empty() else faction
	if frace != faction:
		child["heritage"] = "%s|%s" % [frace, faction]
	_bubble(mother, "👶")
	_gazette("👶 BIRTH",
		"%s gave birth%s!" % [_unit_name(mother),
			(" — a %s-%s child" % [frace, faction]) if frace != faction else ""],
		"family")


## HTML growUp: children become jobless adults; the guild hall finds them work.
func _grow_up(u: Dictionary) -> void:
	u["is_child"] = false
	u["is_baby"] = false
	u["job"] = "worker"
	u["is_worker"] = true
	u["mother_uid"] = -1
	u["father_uid"] = -1
	_say(int(u.get("id", 0)), "I'm grown!")
	if _is_player_faction(String(u.get("faction", ""))):
		_gazette("🧑 GROWN UP",
			"%s has grown up and is ready to work%s." % [_unit_name(u),
				(" (%s heritage)" % String(u.get("heritage", "")).replace("|", "-"))
				if String(u.get("heritage", "")) != "" else ""],
			"family")


## HTML updateChild: babies/children stay near mother (or home), wander a
## little, never march off. Runs on the staggered movement sweep (every 3rd
## frame, delta-scaled); movement is cheap.
func _tick_child_move(u: Dictionary, delta: float) -> void:
	if not bool(u.get("alive", false)):
		return
	var mom := _unit_by_id(int(u.get("mother_uid", -1)))
	var anchor_pos := Vector2.ZERO
	var has_anchor := false
	if not mom.is_empty():
		anchor_pos = mom.get("position", Vector2.ZERO)
		has_anchor = true
	else:
		var home: Dictionary = u.get("home", {})
		if not home.is_empty():
			anchor_pos = home.get("position", Vector2.ZERO)
			has_anchor = true
	var walking: bool = bool(u.get("family_walking", false))
	var pos: Vector2 = u.get("position", Vector2.ZERO)
	if walking:
		var target: Vector2 = u["family_walk"]
		var d := target - pos
		if d.length() < 8.0:
			u["family_walking"] = false
		else:
			var speed := float(u.get("speed", 30.0)) * 0.7
			# Jeremy 2026-10-05: water rules — avoid unless fleeing.
			var wstep: Vector2 = d.normalized() * speed * delta
			var wnp: Vector2 = pos + wstep
			if WaterNav.unit_avoids_water(u):
				wnp = WaterNav.dry_step(_gs.map_data, pos, wstep)
			u["position"] = wnp
			u["swimming"] = WaterNav.is_water_at(_gs.map_data, wnp)
			return
	# Wander rolls are scaled to the sweep step via _roll (3-frame step keeps
	# the per-second probability identical to the old per-frame rolls).
	if has_anchor and (pos.distance_to(anchor_pos) > 150.0 or _roll(0.004, delta)):
		u["family_walk"] = anchor_pos + Vector2(
			(_rng.randf() - 0.5) * 180.0, (_rng.randf() - 0.5) * 180.0)
		u["family_walking"] = true
	elif not has_anchor and _roll(0.002, delta):
		u["family_walk"] = pos + Vector2(
			(_rng.randf() - 0.5) * 160.0, (_rng.randf() - 0.5) * 160.0)
		u["family_walking"] = true


# --- belonging: leaving town ------------------------------------------------

## HTML townAffinity: sample up to 10 same-faction neighbors within 900px.
func _town_affinity(u: Dictionary):
	var sum := 0.0
	var n := 0
	var hated := 0
	var units := _gs.units
	for i in 40:
		if n >= 10:
			break
		var v: Dictionary = units[_rng.randi() % units.size()]
		if not (v is Dictionary) or v == u or not bool(v.get("alive", false)):
			continue
		if bool(v.get("is_child", false)):
			continue
		if String(v.get("faction", "")) != String(u.get("faction", "")):
			continue
		if _dist(u, v) > 900.0:
			continue
		var a := get_affinity(u, v)
		sum += a
		n += 1
		if a < -45.0:
			hated += 1
	if n == 0:
		return {}
	return {"avg": sum / n, "n": n, "hated": hated}


func _leave_bar(faction: String) -> float:
	var s := soul_of(faction)
	return -25.0 - float(s["standing"]) * 0.25 - float(s["morality"]) * 0.1


## HTML tickBelonging: miserable workers petition to leave town.
func _tick_belonging(step: float) -> void:
	_belong_tick += 1
	var dt_days := _days(step)
	var units := _gs.units
	if units.is_empty():
		return
	for k in 6:
		var u: Dictionary = units[_rng.randi() % units.size()]
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		if not _civilian_worker(u):
			continue
		ensure(u)
		u["leave_cd"] = maxf(0.0, float(u.get("leave_cd", 0.0)) - dt_days)
		if float(u.get("leave_cd", 0.0)) > 0.0:
			continue
		var t: Dictionary = _town_affinity(u)
		if t.is_empty() or int(t.get("n", 0)) < 4:
			continue
		var faction := String(u.get("faction", ""))
		if float(t.get("avg", 0.0)) < _leave_bar(faction) \
				and int(t.get("hated", 0)) >= 4:
			# Max one leave-petition per faction per 8 ticks — a miserable
			# faction trickles, never floods (Jeremy 2026-09-22 fix).
			if _belong_tick - int(_leave_throttle.get(faction, -99)) < 8:
				continue
			_leave_throttle[faction] = _belong_tick
			_petition_leave_town(u, t)


func _petion_hated_names(u: Dictionary) -> Array:
	var names: Array = []
	var bonds: Dictionary = u.get("bonds", {})
	for key in bonds.keys():
		if float(bonds[key]) < -45.0 and names.size() < 3:
			var v := _unit_by_id(int(key))
			if not v.is_empty() and String(v.get("faction", "")) == String(u.get("faction", "")):
				names.append(_unit_name(v))
	return names


func _petition_leave_town(u: Dictionary, t: Dictionary) -> void:
	u["leave_cd"] = LEAVE_CD_DAYS
	var hated := int(t.get("hated", 0))
	var names: Array = _petion_hated_names(u)
	var body := "%s can't stand it here anymore — they %s %d townsfolk%s and feel unwelcome overall. Let them walk away and live as an adventurer? They may one day settle with another faction." % [
		_unit_name(u),
		"despise" if hated >= 5 else "strongly dislike",
		hated,
		(" (%s)" % ", ".join(names)) if not names.is_empty() else "",
	]
	_queue_life_decision({
		"kind": "leave", "unit_id": int(u.get("id", -1)),
		"faction": String(u.get("faction", "")),
		"title": "⛺ %s wants to leave town" % _unit_name(u),
		"body": body, "auto_yes": LEAVE_AUTOYES,
	})


func _apply_leave(decision: Dictionary, yes: bool) -> void:
	var u := _unit_by_id(int(decision.get("unit_id", -1)))
	var faction := String(decision.get("faction", ""))
	if yes:
		if not u.is_empty():
			_make_adventurer(u)
		leader_deed(faction, 5.0, 3.0,
			"You let %s leave with dignity." % _unit_name(u),
			"A good leader knows when to let go.")
	else:
		if not u.is_empty():
			# Grudgingly stays — small thaw so it doesn't instantly re-trigger.
			ensure(u)
			var bonds: Dictionary = u["bonds"]
			for key in bonds.keys():
				bonds[key] = minf(0.0, float(bonds[key]) + 12.0)
			_say(int(u.get("id", 0)), "Fine. I'll stay.")
		leader_deed(faction, -6.0, -2.0,
			"You forced %s to stay against their will." % _unit_name(u),
			"Caging the unwilling breeds resentment. They will remember this.")


## HTML makeAdventurer: the unit walks away from town life.
func _make_adventurer(u: Dictionary) -> void:
	ensure(u)
	u["adventurer"] = true
	u["job"] = "adventurer"
	u["is_worker"] = false
	u["home"] = {}
	u["join_cd"] = 2.0  # game-days before they may petition to join
	u["bonds"] = {}
	_say(int(u.get("id", 0)), "I'm leaving this town.")
	if _is_player_faction(String(u.get("faction", ""))):
		_gazette("🧭 ADVENTURER", "%s left town to wander as an adventurer."
			% _unit_name(u), "family")


# --- adventurers ------------------------------------------------------------

## HTML tickAdventurers: wander toward distant points / foreign towns; when
## fond of another faction, petition to join it.
func _tick_adventurers(step: float) -> void:
	var dt_days := _days(step)
	for u in _gs.units:
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		if not bool(u.get("adventurer", false)) or bool(u.get("is_child", false)):
			continue
		ensure(u)
		u["join_cd"] = maxf(0.0, float(u.get("join_cd", 0.0)) - dt_days)
		if not bool(u.get("family_walking", false)) or _rng.randf() < 0.12:
			var up: Vector2 = u.get("position", Vector2.ZERO)
			var tx := up.x + (_rng.randf() - 0.5) * 1600.0
			var ty := up.y + (_rng.randf() - 0.5) * 1600.0
			if _rng.randf() < 0.4:
				var halls := _foreign_halls(u)
				if not halls.is_empty():
					var h: Dictionary = halls[_rng.randi() % halls.size()]
					var hp2: Vector2 = h.get("position", Vector2.ZERO)
					tx = hp2.x + (_rng.randf() - 0.5) * 500.0
					ty = hp2.y + (_rng.randf() - 0.5) * 500.0
			u["family_walk"] = Vector2(tx, ty)
			u["family_walking"] = true
		if float(u.get("join_cd", 0.0)) > 0.0:
			continue
		var best_race := ""
		# DEVIATION 2026-10-05 (launch readiness): HTML-verbatim was 45, but
		# that bar is unreachable in practice — the 30-sample average over
		# >=2 foreigners needs on the order of 50+ game-days of lingering
		# for even very compatible pairs, so the petition effectively never
		# fired. 25 keeps a genuine-fondness bar (neutral pairs hover near
		# single digits) while letting real sessions see immigrants.
		var best_avg := 25.0
		var by_race: Dictionary = {}
		var up2: Vector2 = u.get("position", Vector2.ZERO)
		for i in 30:
			var v: Dictionary = _gs.units[_rng.randi() % _gs.units.size()]
			if not (v is Dictionary) or not bool(v.get("alive", false)):
				continue
			if bool(v.get("is_child", false)):
				continue
			if String(v.get("faction", "")) == String(u.get("faction", "")):
				continue
			if up2.distance_to(v.get("position", Vector2.ZERO)) > 700.0:
				continue
			var fr2 := String(v.get("faction", ""))
			if not by_race.has(fr2):
				by_race[fr2] = {"sum": 0.0, "n": 0}
			by_race[fr2]["sum"] = float(by_race[fr2]["sum"]) + get_affinity(u, v)
			by_race[fr2]["n"] = int(by_race[fr2]["n"]) + 1
		for r in by_race.keys():
			var b: Dictionary = by_race[r]
			if int(b["n"]) >= 2 and float(b["sum"]) / float(b["n"]) > best_avg:
				best_avg = float(b["sum"]) / float(b["n"])
				best_race = String(r)
		if best_race != "":
			_petition_join_faction(u, best_race, best_avg)


func _foreign_halls(u: Dictionary) -> Array:
	var out: Array = []
	var my := String(u.get("faction", ""))
	for b in _gs.buildings:
		if not (b is Dictionary) or not bool(b.get("alive", false)):
			continue
		if String(b.get("type", "")) != "hall":
			continue
		if String(b.get("faction", "")) == my:
			continue
		out.append(b)
	return out


func _petition_join_faction(u: Dictionary, new_race: String, avg: float) -> void:
	u["join_cd"] = JOIN_CD_DAYS  # don't ask again for 25 days, either way
	_queue_life_decision({
		"kind": "join", "unit_id": int(u.get("id", -1)),
		"faction": String(u.get("faction", "")),
		"new_faction": new_race,
		"title": "🧭 %s seeks a new home" % _unit_name(u),
		"body": "%s the %s has been wandering as an adventurer and has grown genuinely fond of the %s (bond %d). Let them join that faction? They'll settle in their town and live as one of them — keeping their name and their past." % [
			_unit_name(u), str(u.get("born_faction", u.get("faction", ""))),
			new_race, int(round(avg))],
		"auto_yes": JOIN_AUTOYES,
	})


func _apply_join(decision: Dictionary, yes: bool) -> void:
	var u := _unit_by_id(int(decision.get("unit_id", -1)))
	var new_race := String(decision.get("new_faction", ""))
	if yes:
		if not u.is_empty():
			_join_faction(u, new_race)
		leader_deed(new_race, 3.0, 4.0,
			"You welcomed %s into the %s." % [_unit_name(u), new_race],
			"A faction that welcomes strangers grows stronger.")
	else:
		if not u.is_empty():
			_say(int(u.get("id", 0)), "Maybe I'll keep wandering.")
		leader_deed(new_race, -2.0, -3.0,
			"You turned %s away." % _unit_name(u),
			"Every wanderer turned away tells a story somewhere else.")


## HTML joinFaction: cross-faction immigration, origin race remembered.
## DEVIATION 2026-10-05 (launch readiness): HTML left job="adventurer" and
## is_worker=false after the move, and the Godot hiring sweep only hires
## job="unemployed" — so every accepted immigrant idled forever as a citizen
## no system would hire (a silent dead end). They now enter the labor market
## as unemployed seekers (same as SimHiring.lay_off: the guild hall hires
## them like any laid-off worker); sprites stay the worker chibi.
func _join_faction(u: Dictionary, new_race: String) -> void:
	ensure(u)
	var old := String(u.get("faction", ""))
	if String(u.get("born_faction", "")) == "":
		u["born_faction"] = old
	u["faction"] = new_race
	u["home"] = {}
	u["adventurer"] = false
	WorkerAI.assign_job(u, "unemployed")
	u["join_cd"] = 20.0
	u["bonds"] = {}
	_say(int(u.get("id", 0)), "A new home!")
	if _is_player_faction(old) or _is_player_faction(new_race):
		_gazette("🧭 NEW CITIZEN",
			"%s (%s) has joined the %s!" % [_unit_name(u),
				String(u.get("born_faction", old)), new_race], "family")


# --- life decisions ---------------------------------------------------------

## HTML queueLifeDecision: the player's faction gets a real choice (Royal
## Court petition -> phone Approve/Deny); AI factions auto-resolve with the
## HTML-verbatim odds. Cap 6 pending like the HTML queue.
func _queue_life_decision(d: Dictionary) -> void:
	if _pending.size() >= 6:
		return
	d["_queued_day"] = int(_gs.day_number)
	if _is_player_faction(String(d.get("faction", ""))) and _court != null:
		var u := _unit_by_id(int(d.get("unit_id", -1)))
		if u.is_empty():
			_auto_resolve(d)
			return
		var p: Dictionary = _court.petition(u, "life_" + String(d.get("kind", "")),
			"%s\n\n%s" % [String(d.get("title", "")), String(d.get("body", ""))],
			["Allow", "Refuse"] as Array[String])
		_pending[int(p.get("id", _petition_seq))] = d
		_petition_seq += 1
	else:
		_auto_resolve(d)


func _auto_resolve(d: Dictionary) -> void:
	var yes := _rng.randf() < float(d.get("auto_yes", 0.5))
	_apply_decision(d, yes)


func _on_petition_decided(petition: Dictionary, choice: String) -> void:
	var pid := int(petition.get("id", -1))
	if not _pending.has(pid):
		return
	var d: Dictionary = _pending[pid]
	_pending.erase(pid)
	var c := choice.to_lower()
	_apply_decision(d, "allow" in c or "yes" in c)


func _apply_decision(d: Dictionary, yes: bool) -> void:
	match String(d.get("kind", "")):
		"leave":
			_apply_leave(d, yes)
		"join":
			_apply_join(d, yes)


## Failsafe: a life petition the player never answers must not hang the
## citizen's decision forever (and must not wedge the 6-slot queue). Every
## DECISION_TICK seconds, petitions older than DECISION_STALE_DAYS are
## decided BY the court with the HTML-verbatim AI odds — through the exact
## same path as a player tap (court.decide -> petition_decided bus ->
## _on_petition_decided), so the card closes, one ruling story publishes,
## and the outcome applies exactly once.
func _tick_decisions(_delta: float) -> void:
	if _pending.is_empty() or _court == null:
		return
	var today := int(_gs.day_number)
	var stale: Array = []
	for pid in _pending.keys():
		var d: Dictionary = _pending[pid]
		var waited := maxi(0, today - int(d.get("_queued_day", today)))
		if float(waited) >= DECISION_STALE_DAYS:
			stale.append(pid)
	for pid in stale:
		if not _pending.has(pid):
			continue
		var d: Dictionary = _pending[pid]
		var yes := _rng.randf() < float(d.get("auto_yes", 0.5))
		# court.decide emits petition_decided synchronously, which runs
		# _on_petition_decided: erases the pending entry and applies the
		# outcome exactly once.
		_court.decide(int(pid), 0 if yes else 1)


## One-line bond summary for the inspect panel (HTML bondSummaryHtml).
func bond_summary(u: Dictionary) -> String:
	if u.is_empty() or not u.has("bonds"):
		return ""
	var bonds: Dictionary = u.get("bonds", {})
	var entries: Array = []
	for key in bonds.keys():
		var v := _unit_by_id(int(key))
		if not v.is_empty():
			entries.append({"n": _unit_name(v), "a": float(bonds[key])})
	if entries.is_empty():
		return ""
	entries.sort_custom(func(x, y): return absf(float(y["a"])) < absf(float(x["a"])))
	var top: Array = []
	for e in entries.slice(0, 3):
		var a := float(e["a"])
		top.append(("%s %s (%d)" % ["💚" if a >= 20.0 else ("💔" if a <= -20.0 else "🤝"),
			String(e["n"]), int(round(a))]))
	return "Bonds: " + ", ".join(top)


# --- save / load ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"souls": _souls.duplicate(true),
		"leave_throttle": _leave_throttle.duplicate(),
		"belong_tick": _belong_tick,
		"petition_seq": _petition_seq,
	}


func from_dict(d: Dictionary) -> void:
	_souls = (d.get("souls", {}) as Dictionary).duplicate(true)
	_leave_throttle = (d.get("leave_throttle", {}) as Dictionary).duplicate()
	_belong_tick = int(d.get("belong_tick", 0))
	_petition_seq = int(d.get("petition_seq", 1))
	_pending.clear()  # in-flight player choices re-fire naturally
