class_name SimProposals
extends RefCounted

## Cursing Gnomes — strategic proposal protocol (Jeremy 2026-10-04:
## "AI plays the game, player approves").
##
## Advisers handle routine work autonomously but submit MAJOR decisions as
## proposals. A proposal is a Dictionary:
##   id: int, faction: String, kind: String, details: Dictionary,
##   day: int, status: String
## Status: "open" | "approved" | "denied" | "executed" | "expired".
##
## Proposal kinds:
##   declare_war       — authorize a war campaign against a target faction
##   monastery_assault — authorize a coordinated assault on a held monastery
##   expand_territory  — authorize founding a new settlement
##   major_buildup     — authorize a military buildup (raise army targets)
##   sue_for_peace     — authorize suing for peace when losing a war
##   scout_mission     — Jeremy 2026-10-06 (lane 6): a hot rumor of enemy
##                       buildup — the War Advisor asks to send scouts
##   investigate_cache — Jeremy 2026-10-06 (lane 6): a hot rumor of a
##                       hidden cache — the Civic Advisor asks to mount
##                       an expedition
##
## Player faction: propose() emits bus.strategic_proposal -> phone_ui shows
## an Approve/Deny modal; the answer returns via resolve_proposal(). Open
## proposals expire after PROPOSAL_TTL_DAYS; a denial arms a cooldown so the
## adviser doesn't nag.
##
## AI factions: the proposal goes to that faction's "main AI" — the AI
## director evaluates it strategically (_ai_evaluate) and approves/denies
## without player involvement. Approval executes immediately.
##
## Pure logic — no rendering, no input, no audio. Owned by World
## (game.proposals); day-cadence expiry via bus.day_changed.


const KIND_DECLARE_WAR := "declare_war"
const KIND_MONASTERY_ASSAULT := "monastery_assault"
const KIND_POST_ASSAULT := "command_post_assault"  # Jeremy 2026-10-06:
	# Battlefront — assaults on war-held command posts of any kind
	# (crystal, town); monasteries keep their legacy kind
const KIND_EXPAND_TERRITORY := "expand_territory"
const KIND_MAJOR_BUILDUP := "major_buildup"
const KIND_SUE_FOR_PEACE := "sue_for_peace"
const KIND_SCOUT := "scout_mission"
const KIND_INVESTIGATE := "investigate_cache"
## Jeremy 2026-10-06 (Lane 3, Postworks): the attacker's assault-vs-starve
## choice for a besieged command post. Filed by SimCommandPosts when a
## siege is detected; approving executes the recommended doctrine.
const KIND_SIEGE_CHOICE := "siege_choice"
const KINDS := [KIND_DECLARE_WAR, KIND_MONASTERY_ASSAULT,
	KIND_POST_ASSAULT, KIND_EXPAND_TERRITORY, KIND_MAJOR_BUILDUP,
	KIND_SUE_FOR_PEACE, KIND_SCOUT, KIND_INVESTIGATE, KIND_SIEGE_CHOICE]

const STATUS_OPEN := "open"
const STATUS_APPROVED := "approved"
const STATUS_DENIED := "denied"
const STATUS_EXECUTED := "executed"
const STATUS_EXPIRED := "expired"

## Open player proposals expire after this many days without an answer.
const PROPOSAL_TTL_DAYS := 3
## After a denial (or an ignored expiry), the same kind+target can't be
## re-proposed until this many days pass — no nagging the crown.
const DENY_COOLDOWN_DAYS := 5

var _gs  # GameState (untyped: avoids a core<->sim class cycle).
var proposals: Array[Dictionary] = []
var _seq := 1
var _cooldowns := {}  # "faction|kind|target" -> day re-proposable


func _init(game_state) -> void:
	_gs = game_state
	_gs.bus.day_changed.connect(_on_day)


## --- Public API ---------------------------------------------------------------

## File a strategic proposal. Returns the proposal record (with "ok": true
## merged in), or {"ok": false, "reason": ...} when blocked by cooldown /
## an identical open proposal / invalid input.
func propose(faction: String, kind: String,
		details: Dictionary = {}) -> Dictionary:
	if kind not in KINDS:
		return {"ok": false, "reason": "unknown kind"}
	if faction == "" or not _gs.active_factions.has(faction):
		return {"ok": false, "reason": "unknown faction"}
	# One open ask at a time per kind+target — never stack modals.
	for p: Dictionary in proposals:
		if String(p.get("status", "")) == STATUS_OPEN \
				and String(p.get("faction", "")) == faction \
				and String(p.get("kind", "")) == kind \
				and _target_of(p.get("details", {})) == _target_of(details):
			var dup: Dictionary = {"ok": true, "duplicate": true}
			dup.merge(p)
			return dup
	var cd := _cooldown_key(faction, kind, details)
	if int(_gs.day_number) < int(_cooldowns.get(cd, 0)):
		return {"ok": false, "reason": "cooldown"}
	var p2: Dictionary = {
		"id": _seq, "faction": faction, "kind": kind,
		"details": details.duplicate(true), "day": int(_gs.day_number),
		"status": STATUS_OPEN,
	}
	# Jeremy 2026-10-06: advisors present REASONS, not verdicts. War/peace
	# proposals carry the strategic brief (strength ratios, enemy weakness,
	# truce checks, treasury runway) so the phone modal / Messenger can
	# show the actual case. Fully defensive — never blocks a proposal.
	if _is_player(faction) \
			and kind in [KIND_DECLARE_WAR, KIND_SUE_FOR_PEACE] \
			and not (p2["details"] as Dictionary).has("brief"):
		var rv = _gs.get("rulers_voice")
		if rv != null and rv.has_method("strategic_brief"):
			var b: Dictionary = rv.strategic_brief(
				String((p2["details"] as Dictionary).get("target", "")))
			if String(b.get("text", "")) != "":
				(p2["details"] as Dictionary)["brief"] = String(b["text"])
	_seq += 1
	proposals.append(p2)
	if _is_player(faction):
		# The crown decides: phone modal via the bus.
		_gs.bus.strategic_proposal.emit(p2)
	else:
		# AI faction: the faction's main AI evaluates strategically.
		if _ai_evaluate(p2):
			p2["status"] = STATUS_APPROVED
			_gs.bus.strategic_proposal_decided.emit(p2, true)
			_execute(p2)
		else:
			_deny(p2, "ai")
	var out: Dictionary = {"ok": true}
	out.merge(p2)
	return out


## Answer a proposal (player via the phone modal; also callable by tests).
## On approve the decision executes; on deny a cooldown arms.
func resolve_proposal(pid: int, approved: bool,
		by: String = "player") -> Dictionary:
	var p: Dictionary = get_proposal(pid)
	if p.is_empty():
		return {"ok": false, "reason": "unknown proposal"}
	if String(p.get("status", "")) != STATUS_OPEN:
		return {"ok": false, "reason": "not open"}
	p["decided_by"] = by
	p["decided_day"] = int(_gs.day_number)
	if approved:
		p["status"] = STATUS_APPROVED
		_gs.bus.strategic_proposal_decided.emit(p, true)
		_execute(p)
	else:
		_deny(p, by)
	return {"ok": true, "approved": approved}


## Record a denial: status, cooldown, signal, and let the strategist stand
## down (a denied war drops its campaign — no nagging the crown).
func _deny(p: Dictionary, by: String) -> void:
	p["status"] = STATUS_DENIED
	p["decided_by"] = by
	p["decided_day"] = int(_gs.day_number)
	_cooldowns[_cooldown_key(String(p.get("faction", "")),
		String(p.get("kind", "")), p.get("details", {}))] = \
		int(_gs.day_number) + DENY_COOLDOWN_DAYS
	_gs.bus.strategic_proposal_decided.emit(p, false)
	var dir = _gs.get("ai_director")
	if dir != null and dir.has_method("on_proposal_denied"):
		dir.on_proposal_denied(p)


func get_proposal(pid: int) -> Dictionary:
	for p: Dictionary in proposals:
		if int(p.get("id", -1)) == pid:
			return p
	return {}


## Open proposals awaiting an answer (the phone lists these).
func open_proposals(faction: String = "") -> Array:
	var out := []
	for p: Dictionary in proposals:
		if String(p.get("status", "")) != STATUS_OPEN:
			continue
		if faction != "" and String(p.get("faction", "")) != faction:
			continue
		out.append(p)
	return out


## --- Day cadence -----------------------------------------------------------------

func _on_day(day: int, _is_night: bool) -> void:
	for p: Dictionary in proposals:
		if String(p.get("status", "")) != STATUS_OPEN:
			continue
		if day - int(p.get("day", day)) >= PROPOSAL_TTL_DAYS:
			p["status"] = STATUS_EXPIRED
			# Ignored = soft no: mild cooldown so it doesn't nag.
			_cooldowns[_cooldown_key(String(p.get("faction", "")),
				String(p.get("kind", "")), p.get("details", {}))] = \
				day + DENY_COOLDOWN_DAYS
			_gs.bus.strategic_proposal_decided.emit(p, false)


## --- The faction "main AI": strategic evaluation -------------------------------

## Decides a proposal for an AI faction the way its ruler would — HTML
## war32AiWarTick gates ported where they exist (strength estimate,
## economic viability), strategic need otherwise. No player involvement.
func _ai_evaluate(p: Dictionary) -> bool:
	var faction: String = String(p.get("faction", ""))
	var kind: String = String(p.get("kind", ""))
	var d: Dictionary = p.get("details", {})
	var dip = _gs.diplomacy
	match kind:
		KIND_DECLARE_WAR:
			return _ai_war_ok(faction, String(d.get("target", "")), dip)
		KIND_MONASTERY_ASSAULT:
			return _ai_assault_ok(faction, int(d.get("monastery_id", -1)))
		KIND_POST_ASSAULT:
			return _ai_post_assault_ok(faction,
				String(d.get("post_kind", "")), int(d.get("post_id", -1)))
		KIND_EXPAND_TERRITORY:
			return _ai_expand_ok(faction)
		KIND_MAJOR_BUILDUP:
			return _ai_buildup_ok(faction)
		KIND_SUE_FOR_PEACE:
			return _ai_peace_ok(faction, String(d.get("target", "")), dip)
		# Jeremy 2026-10-06 (lane 6): rumor-born asks are low-stakes —
		# scouting and cache-hunting are always worth doing.
		KIND_SCOUT:
			return true
		KIND_INVESTIGATE:
			return true
		KIND_SIEGE_CHOICE:
			return _ai_siege_ok(faction, d)
	return false


## HTML war32AiWarTick gates, ported: never attack friends, truce binds,
## liking the player prohibits attack, the winnable-by-estimate gate
## (need = 1.15 - aggro/400 with aggro 0..100), economic viability
## (expected gains must cover estimated costs).
func _ai_war_ok(faction: String, target: String, dip) -> bool:
	if dip == null or target == "" or target == faction:
		return false
	if not _gs.active_factions.has(target):
		return false
	var rel: String = dip.relation_state(faction, target)
	if rel == "war" or rel == "allied":
		return false
	if dip.truce_active(faction, target):
		return false
	# Jeremy 2026-10-06: the picked leader's personality bends the faction's
	# war appetite — an aggressive warlord pushes for war, a patient sage
	# holds back.
	var fl = _gs.get("faction_leaders")
	var ltraits: Dictionary = {}
	if fl != null and fl.has_method("traits_of"):
		ltraits = fl.traits_of(faction)
	if target == _gs.player_faction \
			and dip.relation_score(faction, target) > 15.0 \
			and not _treachery_backstab(faction, ltraits, dip, target):
		return false  # HTML: liking the player prohibits attack, period
	var aggro := float(dip.faction_traits(faction).get("aggro", 0.5))
	if not ltraits.is_empty():
		aggro = clampf(aggro * 0.6
			+ float(ltraits.get("aggression", 0.5)) * 0.4, 0.0, 1.0)
	var need := 1.15 - aggro * 0.25
	var own = dip.military_strength(faction)
	var est = dip.military_strength(target)
	if own <= est * need:
		return false
	var cost := maxf(1.0, own) * 0.8
	var gain = dip.faction_wealth(target) * 2.0 + est * 0.5
	if gain < cost * 0.6:
		return false
	return true


## Jeremy 2026-10-06: treachery is real — a deeply treacherous leader
## (treachery > 0.75) may backstab even a liked player, but only when the
## prize is enormous (expected gains triple the cost). Rare by design.
func _treachery_backstab(faction: String, ltraits: Dictionary, dip,
		target: String) -> bool:
	if float(ltraits.get("treachery", 0.0)) <= 0.75:
		return false
	var own = dip.military_strength(faction)
	var est = dip.military_strength(target)
	var cost := maxf(1.0, own) * 0.8
	var gain = dip.faction_wealth(target) * 2.0 + est * 0.5
	return gain > cost * 3.0


## Assault a held monastery: only at war with the holder (peacetime is
## hands-off per the capture rules), and only with a real force ready.
func _ai_assault_ok(faction: String, mid: int) -> bool:
	var mons = _gs.get("monasteries")
	if mons == null or not mons.has_method("get_monastery"):
		return false
	var m: Dictionary = mons.get_monastery(mid)
	if m.is_empty():
		return false
	var owner: String = String(m.get("owner", ""))
	if owner == faction:
		return false
	if owner != "":
		var dip = _gs.diplomacy
		if dip == null or dip.relation_state(faction, owner) != "war":
			return false
	return _military_of(faction).size() >= 6


## Jeremy 2026-10-06: Battlefront — AI auto-resolve gate for assaults on
## war-held command posts of any kind (crystal, town).
func _ai_post_assault_ok(faction: String, kind: String, pid: int) -> bool:
	var post := _find_post(kind, pid)
	if post.is_empty():
		return false
	var holder: String = String(post.get("holder", ""))
	if holder == "" or holder == faction:
		return false
	var dip = _gs.diplomacy
	if dip == null or dip.relation_state(faction, holder) != "war":
		return false
	return _military_of(faction).size() >= 6


## Jeremy 2026-10-06 (Lane 3, Postworks): the AI honors a siege-choice ask
## while the siege is still real — war enemy still holds the post, and the
## faction still fields a besieging-worthy force. The assault-vs-starve
## recommendation itself was computed at filing time (HTML estimate gate).
func _ai_siege_ok(faction: String, d: Dictionary) -> bool:
	var cps = _gs.get("command_posts")
	if cps == null or not cps.has_method("siege_of"):
		return false
	var kind := String(d.get("post_kind", ""))
	var pid := int(d.get("post_id", -1))
	var s: Dictionary = cps.siege_of(kind, pid)
	if s.is_empty():
		return false
	if String(s.get("attacker", "")) != faction:
		return false
	var post := _find_post(kind, pid)
	if post.is_empty():
		return false
	var holder: String = String(post.get("holder", ""))
	if holder == "" or holder == faction:
		return false
	var dip = _gs.diplomacy
	if dip == null or dip.relation_state(faction, holder) != "war":
		return false
	return _military_of(faction).size() >= 4


## Find a command post by kind+id via the wired SimCommandPosts model.
func _find_post(kind: String, pid: int) -> Dictionary:
	var cps = _gs.get("command_posts")
	if cps == null or not cps.has_method("posts_of"):
		return {}
	for p: Dictionary in cps.posts_of():
		if String(p.get("kind", "")) == kind \
				and int(p.get("id", 0)) == pid:
			return p
	return {}


## Found a settlement: population pressure + can afford the hall.
## (Mirrors the AI director's founding checks.)
func _ai_expand_ok(faction: String) -> bool:
	if _pop_of(faction) < int(float(Config.POP_CAP_FACTION) * 0.8):
		return false
	var r = _gs.resources
	if r == null:
		return false
	return r.get_amount(faction, "wood") >= 200.0


## Mass troops: threatened, at war, or nursing a grudge it can't act on yet.
func _ai_buildup_ok(faction: String) -> bool:
	var dir = _gs.get("ai_director")
	if dir != null and dir.has_method("threat_level_of"):
		if int(dir.threat_level_of(faction)) >= 1:
			return true
	var dip = _gs.diplomacy
	if dip == null:
		return false
	for o: String in _gs.active_factions:
		if o == faction:
			continue
		if dip.relation_state(faction, o) == "war":
			return true
		if dip.grudge_against(faction, o) < -20.0:
			return true
	return false


## Sue for peace: only when genuinely losing the war.
func _ai_peace_ok(faction: String, target: String, dip) -> bool:
	if dip == null or target == "":
		return false
	if dip.relation_state(faction, target) != "war":
		return false
	var foe = dip.military_strength(target)
	if foe <= 0.0:
		return true  # enemy wiped out; peace is free
	if dip.military_strength(faction) < foe * 0.5:
		return true  # crushed; anyone sues for peace
	# Jeremy 2026-10-06: a patient, generous leader settles sooner — they
	# accept peace when merely outmatched, not only when crushed.
	var fl = _gs.get("faction_leaders")
	if fl != null and fl.has_method("traits_of"):
		var tr: Dictionary = fl.traits_of(faction)
		var peace_will: float = float(tr.get("patience", 0.5)) * 0.6 \
			+ float(tr.get("generosity", 0.5)) * 0.4
		if dip.military_strength(faction) < foe * (0.5 + peace_will * 0.5):
			return true
	return false


## --- Execution ---------------------------------------------------------------------

## Carry out an approved proposal. Delegates to the AI director (the
## strategist) or diplomacy; guarded so bare tests don't crash.
func _execute(p: Dictionary) -> void:
	var faction: String = String(p.get("faction", ""))
	var kind: String = String(p.get("kind", ""))
	var d: Dictionary = p.get("details", {})
	var dir = _gs.get("ai_director")
	match kind:
		KIND_DECLARE_WAR:
			if dir != null and dir.has_method("campaign_authorized"):
				dir.campaign_authorized(faction, String(d.get("target", "")))
		KIND_MONASTERY_ASSAULT:
			if dir != null and dir.has_method("launch_monastery_assault"):
				dir.launch_monastery_assault(faction,
					int(d.get("monastery_id", -1)))
		KIND_POST_ASSAULT:
			if dir != null and dir.has_method("launch_post_assault"):
				dir.launch_post_assault(faction,
					String(d.get("post_kind", "")),
					int(d.get("post_id", -1)))
		KIND_EXPAND_TERRITORY:
			if dir != null and dir.has_method("found_settlement_at"):
				var pos: Vector2 = d.get("position", Vector2.INF)
				if pos != Vector2.INF:
					dir.found_settlement_at(faction, pos)
		KIND_MAJOR_BUILDUP:
			if dir != null and dir.has_method("set_buildup_bias"):
				dir.set_buildup_bias(faction, true)
		KIND_SUE_FOR_PEACE:
			if _gs.diplomacy != null:
				_gs.diplomacy.offer_surrender(faction,
					String(d.get("target", "")))
		# Jeremy 2026-10-06 (lane 6): rumor-born proposals execute
		# through SimHearsay (scout reports, cache expeditions).
		# Guarded so bare tests without a phone don't crash.
		KIND_SCOUT, KIND_INVESTIGATE:
			var hs = null
			var psys = _gs.get("phone_sys")
			if psys != null:
				hs = psys.get("hearsay")
			if hs != null and hs.has_method("quest_approved"):
				hs.quest_approved(kind, d)
		# Jeremy 2026-10-06 (Lane 3, Postworks): the siege doctrine is
		# set on the post; an assault also launches the storm immediately.
		KIND_SIEGE_CHOICE:
			var cps = _gs.get("command_posts")
			var pk := String(d.get("post_kind", ""))
			var pid := int(d.get("post_id", -1))
			var mode := String(d.get("mode", "starve"))
			if cps != null and cps.has_method("set_siege_mode"):
				cps.set_siege_mode(faction, pk, pid, mode)
			if mode == "assault" and dir != null \
					and dir.has_method("launch_post_assault"):
				dir.launch_post_assault(faction, pk, pid)
	p["status"] = STATUS_EXECUTED


## --- Helpers -------------------------------------------------------------------------

func _is_player(faction: String) -> bool:
	return faction != "" and faction == _gs.player_faction


## The "target" of a proposal for cooldown/duplicate purposes.
func _target_of(details: Dictionary) -> String:
	if details.has("target"):
		return String(details.get("target", ""))
	if details.has("monastery_id"):
		return "monastery_%d" % int(details.get("monastery_id", -1))
	if details.has("post_kind"):
		return "post_%s_%d" % [String(details.get("post_kind", "")),
			int(details.get("post_id", -1))]
	if details.has("position"):
		var pos: Vector2 = details.get("position", Vector2.ZERO)
		return "pos_%d_%d" % [int(pos.x), int(pos.y)]
	return ""


func _cooldown_key(faction: String, kind: String,
		details: Dictionary) -> String:
	return "%s|%s|%s" % [faction, kind, _target_of(details)]


func _military_of(faction: String) -> Array:
	var out := []
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			out.append(u)
	return out


func _pop_of(faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == faction:
			n += 1
	return n


## --- Save / load -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"seq": _seq,
		"proposals": proposals.duplicate(true),
		"cooldowns": _cooldowns.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_seq = int(data.get("seq", 1))
	# assign() re-types the decoded plain Array back into Array[Dictionary];
	# a direct = would throw "Trying to assign an array of type Array".
	proposals.assign((data.get("proposals", []) as Array).duplicate(true))
	_cooldowns = (data.get("cooldowns", {}) as Dictionary).duplicate(true)
