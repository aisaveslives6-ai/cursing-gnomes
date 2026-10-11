class_name SimPhone
extends RefCounted
## Cursing Gnomes — phone simulation core (Milestone 6).
##
## Design ported from the HTML build (not its code):
##   - Phone opens on a Home Screen: Messenger and Squabble app icons.
##   - Contacts: a pinned "My Government" section on top (advisers +
##     guild masters / role-holders of the player's faction). Everyone else
##     appears ONLY if the player adds them — no auto-populated
##     kingdom-wide phonebook (Jeremy's law).
##   - Every character has a pfp (portrait art key) that opens their
##     Squabble profile. Bios read like a life from REAL events/memories
##     only — nothing invented.
##   - Messenger: conversation threads with a remembered sort switcher
##     (latest / most_used / unread_first). Answered threads sink; threads
##     with unanswered incoming rise.
##   - NPC replies are 100% OFFLINE/scripted: intent parsing + deterministic
##     line tables from SimDialogue. No network, no LLM, ever.
##   - Squabble: social feed. Posts come from real sim events (gazette
##     stories, moods, feuds/praise). Likes, comments (scripted replies),
##     resquabbles.
##
## CONTACT KEY: "u<unit_id>". GOVERNMENT roles live on unit records under
##   mind["gov_role"] ("adviser" | "guild_master" | "watch_captain" |
##   "mayor" | "commander") — set by SimRoyalCourt.
##
## Pure logic — no rendering, no input, no audio, no network.


## Messenger sort modes (remembered across sessions on the state dict).
const SORTS: Array[String] = ["latest", "most_used", "unread_first"]

## Government role rank: pinned section order (HTML msgrRoleRank).
const GOV_RANK := {
	"adviser": 0, "guild_master": 1, "watch_captain": 2, "commander": 3,
	"mayor": 5, "lord": 6, "envoy": 41,
}

## Scripted messenger intents. {name} = NPC name, {ruler} = raw ruler name.
const REPLY_GREET: Array[String] = [
	"Hey! Good to hear from you.",
	"Oh! Hi! Wasn't expecting a message.",
	"Sup. What's up?",
]
const REPLY_NEWS: Array[String] = [
	"News? The Gazette's got the official version. Ask me after you've read it.",
	"Quiet around here lately — suspiciously quiet.",
	"Heard the {ruler} roasted someone at court again. Shocking. Truly.",
]
const REPLY_HELP: Array[String] = [
	"I'll see what I can do. No promises — my back's killing me.",
	"Help? From ME? ...fine. FINE. What do you need?",
	"Ask the guild master. That's literally their job.",
]
const REPLY_BYE: Array[String] = [
	"Later!",
	"Gotta run — stew's burning. Probably.",
	"Talk soon. Don't get cursed.",
]
const REPLY_DEFAULT: Array[String] = [
	"Huh. Interesting. Tell me more.",
	"Ha! Anyway —",
	"Noted. I'll pretend I understood that.",
	"You've got my attention. Mostly.",
]
const REPLY_ROASTBACK: Array[String] = [
	"Bold words from someone named by {ruler}.",
	"I'm telling the Gazette you said that.",
	"Oh, it's ON now. Meet me at the tavern. Bring stew.",
]


var _gs: GameState

## Gossip engine (owned here so the phone's feed/DMs stay in sync).
var hearsay  # SimHearsay — created in _init

## Hearsay conversation engine (Jeremy 2026-10-04: the full conversation
## system port — fluent NPC dialogue with memory, personality, mood,
## and the Living Lexicon).
var conversation: SimConversation  # created in _init

## Royal court (set by the world for Gazette two-way chat).
var _court = null  # SimRoyalCourt — duck-typed to avoid cyclic reference

## Phone state (plain data — survives save/load):
##   sort: String, added: Array[String] (contact keys),
##   threads: Dictionary (key -> thread dict),
##   posts: Array[Dictionary], post_seq: int,
##   blocked: Dictionary (key -> {day}) — HTML msgrSocial().blocked parity
var state: Dictionary

## Jeremy 2026-10-04: realistic texting — typing indicators, send delays,
## read receipts, online status. Pending NPC replies queue (NOT in state —
## transient, rebuilt on load as empty): Array of {key, reply_text,
## typing_until, deliver_at} using _gs.game_time.
var _pending: Array = []

## Jeremy 2026-10-04: wall-raise hearsay questions. Maps thread key ->
## region_name for the ONE pending wall question per thread. The player
## answers by replying yes/no in conversation; the answer is emitted via
## the wall_answer bus signal and the question is cleared (one ask, one
## answer — never repeated). Transient, not saved.
var _wall_questions: Dictionary = {}

## Jeremy 2026-10-06: last reply's effect dict, stashed by _npc_reply so
## send_message can act on it (unhinged spam burst). Transient, not saved.
var _last_reply_effect: Dictionary = {}

## Jeremy 2026-10-11: MR SMART BITCH — phone-only tutor contact. Owned
## lazily by the phone (game_state.gd is lane-locked); the brain is
## SimSmartBitch, which carries its own dialogue tree + NPC knowledge.
var _smartbitch: SimSmartBitch = null

## Jeremy 2026-10-11: visible NPC social life — NPCs DM each other, argue
## on Squabble, gossip in visible chains, and remember what was said
## (dislike memories with verbatim quotes). Owned here like hearsay.
var social_life  # SimSocialLife — created in _init


## Lazy accessor — the brain needs game state + conversation memory.
func _smartbitch_obj() -> SimSmartBitch:
	if _smartbitch == null:
		_smartbitch = SimSmartBitch.new(_gs)
		_smartbitch.conversation = conversation
	else:
		_smartbitch.conversation = conversation
	return _smartbitch


## Smart Bitch pseudo-unit dict (thread header, rows, pfp).
func _smartbitch_unit() -> Dictionary:
	return _smartbitch_obj().pseudo_unit()

## Typing indicator durations (HTML parity: longer messages take longer).
const TYPING_BASE := 1.2      # seconds before typing starts showing
const TYPING_PER_CHAR := 0.03 # extra seconds per character of reply
const TYPING_MAX := 4.5       # cap so long replies don't take forever
const SEND_DELAY := 0.6       # player's message shows "sending" this long
const SEEN_DELAY := 2.0       # NPC marks player message "seen" after this


func _init(game_state: GameState) -> void:
	_gs = game_state
	state = {
		"sort": "latest",
		"added": [],
		"threads": {},
		"posts": [],
		"post_seq": 1,
		"blocked": {},
	}
	hearsay = SimHearsay.new(game_state, self)
	conversation = SimConversation.new()
	social_life = SimSocialLife.new(self)
	# Jeremy 2026-10-04: NPCs live their Squabble lives — ambient posts and
	# engagement run once per game day.
	_gs.bus.day_changed.connect(_on_day_changed)
	# Jeremy 2026-10-07: petition_opened finally has a listener. The court
	# emitted it for every petition, but nothing ever listened — petitions
	# sat silently in the Gazette's Messages tab and rulers never knew
	# their subjects (or foreign envoys) were begging. Now the petitioner
	# DMs the ruler directly and a toast announces it.
	_gs.bus.petition_opened.connect(_on_petition_opened)


## Daily NPC Squabble activity.
## Jeremy 2026-10-06 live-fire: the bus day_changed signal carries
## (day, is_night); the second param was missing, so this handler errored
## and NEVER RAN in the live game — killing daily Squabble posts, gossip,
## ambush/assface ticks, and LANE-4 rumor DMs.
func _on_day_changed(_day: int, _is_night: bool) -> void:
	npc_ambient_tick()
	# Jeremy 2026-10-04: likes/dislikes engine — NPCs gossip to EACH OTHER
	# about what the ruler said (hearsay rumors + Squabble posts).
	SimLikesDislikes.daily_gossip(_gs, self)
	_unhinged_ambush_tick()
	_assface_day_tick()
	# Jeremy 2026-10-06 (LANE 4): hot rumors about the player make NPCs
	# DM first ("heard you torched Thornwall — true?").
	conversation.rumor_dm_tick(_gs, self)
	# Jeremy 2026-10-11: visible NPC social life — NPC-to-NPC DMs,
	# Squabble arguments, gossip chains, dislike memories. Day tick,
	# hard-budgeted, never per-frame.
	social_life.daily_tick(_day)


## Jeremy 2026-10-06: unhinged ambushes — furious unhinged NPCs can
## PREEMPTIVELY DM the player a cuss-out. They come at YOU: the ambush is a
## single opener drawn from the same no-repeat cuss-out pools as the
## reactive path (shared SimUnhinged._draw tracking, so no line repeats).
## Tier follows live fury: first ambushes draw "heated", repeat ambushes
## climb to "furious"/"unhinged" as mood worsens. If the player replies,
## the reactive cuss-out + spam chain takes over naturally (reply
## short-circuits while they're still furious+unhinged).
## Hard caps: per-NPC once per in-game day, global cap per day, blocked and
## dead NPCs never send. npc_message marks the thread unread + bumps
## last_ts, so the ambush surfaces at the top under newest-first ordering.
const AMBUSH_GLOBAL_CAP := 3
const AMBUSH_CHANCE := {"heated": 0.15, "furious": 0.30, "unhinged": 0.50}

## Transient ambush bookkeeping (not saved): uid -> day_number of last
## ambush; plus the day the global counter was last reset.
var _ambush_day: Dictionary = {}
var _ambush_cap_day := -1
var _ambush_sent_today := 0


func _unhinged_ambush_tick(force: bool = false) -> void:
	var today := int(_gs.day_number)
	if _ambush_cap_day != today:
		_ambush_cap_day = today
		_ambush_sent_today = 0
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if not SimUnhinged.is_unhinged(u):
			continue
		var uid := int(u.get("id", 0))
		if conversation.ruler_mood(uid) > SimUnhinged.FURIOUS_AT:
			continue
		if is_blocked(uid):
			continue
		if int(_ambush_day.get(uid, -1)) >= today:
			continue  # per-NPC cooldown: once per day max
		cands.append(u)
	# Angriest first — they get priority under the global cap.
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return conversation.ruler_mood(int(a.get("id", 0))) \
			< conversation.ruler_mood(int(b.get("id", 0))))
	for u: Dictionary in cands:
		if _ambush_sent_today >= AMBUSH_GLOBAL_CAP:
			break
		var uid := int(u.get("id", 0))
		var tier := SimUnhinged.tier_for(conversation.ruler_mood(uid))
		if not force and randf() > float(AMBUSH_CHANCE.get(tier, 0.15)):
			continue
		var line: String = conversation.unhinged.ambush_line(
			conversation, u, _gs.ruler_name)
		if line.is_empty() or line == "...":
			continue
		npc_message(uid, line)
		_ambush_day[uid] = today
		_ambush_sent_today += 1


## Jeremy 2026-10-04: realistic texting tick — processes the pending
## reply queue. Called every physics frame from world.gd. Uses game_time
## so delays pause with the sim.
var _seen_last_t := -1.0  # Jeremy 2026-10-04 perf: _mark_seen at 1Hz


func tick(_delta: float) -> void:
	var now_t: float = _gs.game_time
	# Jeremy 2026-10-04 perf: _mark_seen iterates ALL threads x ALL messages.
	# Throttle to 1Hz — "seen" receipts don't need frame precision.
	# Uses game_time (not delta accumulation) so test time-skips work.
	var do_seen: bool = _seen_last_t < 0.0 or now_t - _seen_last_t >= 1.0
	if do_seen:
		_seen_last_t = now_t
	if _pending.is_empty() and not do_seen:
		return
	var now: float = _gs.game_time
	# Iterate backwards so we can remove delivered items safely.
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		var key: String = String(p.get("key", ""))
		var th: Dictionary = _thread(key)
		# Start showing the typing indicator once typing_until is reached.
		if not bool(p.get("typing_shown", false)) \
				and now >= float(p.get("typing_until", 0.0)):
			p["typing_shown"] = true
			th["typing"] = true
			_gs.bus.phone_typing.emit(key, true)
		# Deliver the reply once deliver_at is reached.
		if now >= float(p.get("deliver_at", 0.0)):
			_pending.remove_at(i)
			th["typing"] = false
			_gs.bus.phone_typing.emit(key, false)
			(th["messages"] as Array).append({
				"from": "npc", "text": String(p.get("reply_text", "")),
				"day": _gs.day_number, "ts": now, "status": "delivered"})
			th["unread"] = int(th["unread"]) + 1
			th["answered"] = false  # NPC spoke last
			_gs.bus.phone_message.emit(key, String(p.get("reply_text", "")))
	# Jeremy 2026-10-06: ASSFACE burst-end — unlock the contact + seed the
	# hearsay aftermath once the 30 seconds are up.
	_assface_burst_tick(now)
	# Mark recently-sent player messages as "seen" once the NPC reads them.
	if do_seen:
		_mark_seen(now)


## Marks player messages "seen" after SEEN_DELAY (NPC read them).
func _mark_seen(now: float) -> void:
	var threads: Dictionary = state["threads"]
	for key: String in threads:
		var th: Dictionary = threads[key]
		var changed := false
		for m: Dictionary in th["messages"]:
			if String(m.get("from", "")) == "player" \
					and String(m.get("status", "")) == "delivered" \
					and now - float(m.get("ts", 0.0)) >= SEEN_DELAY:
				m["status"] = "seen"
				changed = true
		if changed:
			_gs.bus.phone_message_status.emit(key, -1, "seen")


## Is this contact currently showing a typing indicator?
func is_typing(key: String) -> bool:
	return bool(_thread(key).get("typing", false))


## Typing duration for a reply (HTML parity: longer = slower).
static func typing_duration(reply_text: String) -> float:
	return minf(TYPING_BASE + float(reply_text.length()) * TYPING_PER_CHAR,
		TYPING_MAX)


## Online status: NPCs are "online" if they messaged recently or are
## government (advisers are always reachable). Otherwise "last seen".
func is_online(key: String) -> bool:
	var th: Dictionary = _thread(key)
	var last: float = float(th.get("last_ts", 0.0))
	# Government contacts are always online (HTML: court is reachable).
	var u: Dictionary = _unit_for_key(key)
	if not u.is_empty():
		var role: String = String((u.get("mind", {}) as Dictionary).get("gov_role", ""))
		if role != "":
			return true
	# Anyone who messaged in the last 2 game hours counts as online.
	return _gs.game_time - last < 7200.0


## Human-readable presence: "online" or "last seen X ago".
func presence_text(key: String) -> String:
	if is_online(key):
		return "online"
	var th: Dictionary = _thread(key)
	var ago: float = _gs.game_time - float(th.get("last_ts", 0.0))
	if ago < 3600.0:
		return "last seen %dm ago" % int(ago / 60.0)
	if ago < 86400.0:
		return "last seen %dh ago" % int(ago / 3600.0)
	return "last seen %dd ago" % int(ago / 86400.0)


## --- Contacts ---------------------------------------------------------------

## Pinned "My Government": role-holders of the player's faction, ranked.
## Returns contact dicts {key, name, sub, faction, unit_id, pfp, gov, rank}.
func government_contacts() -> Array:
	var out: Array = []
	var pf: String = _gs.player_faction
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		var mind: Dictionary = u.get("mind", {})
		var role: String = String(mind.get("gov_role", ""))
		if role == "" or not GOV_RANK.has(role):
			continue
		out.append(_contact_for(u, true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rank", 50)) < int(b.get("rank", 50)))
	return out


## Player-added contacts only — never auto-populated (Jeremy's law).
func my_contacts() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for key: String in state["added"]:
		if seen.has(key):
			continue
		seen[key] = true
		# Jeremy 2026-10-06: ASSFACE — permanent contact after his disaster
		# fires. Custom dict (his pfp resolves via _leader_pfp, like leaders).
		if key == SimAssface.KEY:
			out.append({
				"key": SimAssface.KEY,
				"name": SimAssface.NAME,
				"sub": "Professional idiot · prank caller",
				"faction": "",
				"unit_id": SimAssface.UID,
				"pfp": "assface",
				"gov": false,
				"rank": 50,
			})
			continue
		# Jeremy 2026-10-11: MR SMART BITCH — permanent tutor contact.
		# Custom dict (his pfp resolves via _leader_pfp, like leaders).
		if key == SimSmartBitch.KEY:
			out.append({
				"key": SimSmartBitch.KEY,
				"name": SimSmartBitch.NAME,
				"sub": "Knows everything. Judges you anyway.",
				"faction": "",
				"unit_id": SimSmartBitch.UID,
				"pfp": "smartbitch",
				"gov": false,
				"rank": 50,
			})
			continue
		var u: Dictionary = _unit_for_key(key)
		if u.is_empty() or not u.get("alive", false):
			continue
		out.append(_contact_for(u, false))
	return out


## Enemy commanders (Jeremy 2026-10-04): role-holders of non-player
## factions, grouped by faction with factions ordered nearest-first.
## Distance = town-centroid distance to the player's faction centroid.
## Returns Array of {faction, faction_name, color, dist_tiles, contacts},
## contacts sorted by GOV_RANK like the pinned government section.
func enemy_commander_groups() -> Array:
	var pf: String = _gs.player_faction
	# Faction centroids from town positions (world px).
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for tid: int in _gs.towns:
		var town: Dictionary = _gs.towns[tid]
		var f: String = String(town.get("faction", ""))
		var pos: Vector2 = town.get("position", Vector2.ZERO)
		sums[f] = (sums.get(f, Vector2.ZERO) as Vector2) + pos
		counts[f] = int(counts.get(f, 0)) + 1
	var centroids: Dictionary = {}
	for f: String in sums:
		centroids[f] = (sums[f] as Vector2) / float(maxi(1, int(counts[f])))
	var home: Vector2 = centroids.get(pf, Vector2.ZERO)
	# Collect role-holders of foreign factions.
	var groups: Dictionary = {}
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var f: String = String(u.get("faction", ""))
		if f == "" or f == pf:
			continue
		var role: String = String((u.get("mind", {}) as Dictionary).get("gov_role", ""))
		if role == "" or not GOV_RANK.has(role):
			continue
		if not groups.has(f):
			var fc: Vector2 = centroids.get(f, home)
			var dist_tiles: int = int(home.distance_to(fc) / 32.0)
			groups[f] = {
				"faction": f,
				"faction_name": _faction_display_name(f),
				"color": _faction_color(f),
				"dist_tiles": dist_tiles,
				"contacts": [],
			}
		(groups[f]["contacts"] as Array).append(_contact_for(u, false))
	var out: Array = groups.values()
	for g: Dictionary in out:
		(g["contacts"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("rank", 50)) < int(b.get("rank", 50)))
	# Nearest faction first.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("dist_tiles", 0)) < int(b.get("dist_tiles", 0)))
	return out


## Faction display name + color (falls back to the raw id / white).
func _faction_display_name(f: String) -> String:
	var info: Dictionary = Config.FACTIONS.get(f, {})
	return String(info.get("name", f.capitalize()))


func _faction_color(f: String) -> Color:
	var info: Dictionary = Config.FACTIONS.get(f, {})
	return info.get("color", Color.WHITE) as Color


## Adds a unit to the player's contacts. Returns false if already added
## or the unit doesn't exist.
func add_contact(unit_id: int) -> bool:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return false
	var key: String = _key_for(unit_id)
	if (state["added"] as Array).has(key):
		return false
	(state["added"] as Array).append(key)
	_gs.bus.phone_contact_added.emit(key)
	return true


## Removes a contact (and keeps their thread history).
func remove_contact(unit_id: int) -> bool:
	var key: String = _key_for(unit_id)
	if not (state["added"] as Array).has(key):
		return false
	(state["added"] as Array).erase(key)
	return true


func is_contact(unit_id: int) -> bool:
	return (state["added"] as Array).has(_key_for(unit_id))


## --- Blocking -------------------------------------------------------------------
## HTML msgrBlockCit / msgrBlockRuler / msgrBlockToggle / msgrIsBlocked parity.
## Blocked = FULLY SILENCED: no incoming messages, no outgoing messages,
## no Squabble posts visible, no chat replies. Thread history is kept
## (HTML keeps the thread; the composer is disabled instead).

const BLOCK_FAREWELLS: Array[String] = [
	"Blocked?! FINE. I'll remember this at the next summit. 😤",
	"Oh, it's like THAT? Enjoy the silence, {ruler}.",
	"Feuding with the crown now. It's not personal. It's extremely personal. ⚔️",
]


func is_blocked(unit_id: int) -> bool:
	return is_blocked_key(_key_for(unit_id))


func is_blocked_key(key: String) -> bool:
	return (state["blocked"] as Dictionary).has(key)


func blocked_keys() -> Array:
	return (state["blocked"] as Dictionary).keys()


## Block a citizen NPC (HTML msgrBlockCit): silent block, removed from
## contacts, feud recorded. Returns false if already blocked.
func block_citizen(unit_id: int) -> bool:
	return _block_key(_key_for(unit_id), "")


## Block a ruler-like NPC (HTML msgrBlockRuler): they fire one angry
## farewell DM first (sent directly, bypassing the delivery guard),
## then the block lands.
func block_ruler(unit_id: int) -> bool:
	var key: String = _key_for(unit_id)
	if is_blocked_key(key):
		return false
	var u: Dictionary = _gs.get_unit(unit_id)
	if not u.is_empty():
		var fw: String = BLOCK_FAREWELLS[absi(unit_id * 7 + 3) % BLOCK_FAREWELLS.size()]
		_append_dm(key, "npc", _fill(u, fw))
	return _block_key(key, "")


func _block_key(key: String, _note: String) -> bool:
	if is_blocked_key(key):
		return false
	(state["added"] as Array).erase(key)  # blocked contacts leave the list
	(state["blocked"] as Dictionary)[key] = {"day": _gs.day_number}
	return true


## Unblock: the NPC sends one wary hello (HTML msgrUnblockCit).
func unblock(unit_id: int) -> bool:
	return unblock_key(_key_for(unit_id))


func unblock_key(key: String) -> bool:
	if not is_blocked_key(key):
		return false
	(state["blocked"] as Dictionary).erase(key)
	var u: Dictionary = _unit_for_key(key)
	if not u.is_empty():
		_append_dm(key, "npc", "Oh. Hi again. I'll try not to hold it against you.")
	return true


## One-tap Block <-> Unblock toggle (HTML msgrBlockToggle).
func toggle_block(unit_id: int) -> bool:
	if is_blocked(unit_id):
		return unblock(unit_id)
	return block_citizen(unit_id)


## Direct DM append that bypasses the blocked-delivery guard (used for the
## block farewell and the unblock hello — HTML msgrAppendDM parity).
func _append_dm(key: String, who: String, text: String) -> void:
	var th: Dictionary = _thread(key)
	(th["messages"] as Array).append({"from": who, "text": text,
		"day": _gs.day_number, "ts": _gs.game_time})
	th["last_ts"] = _gs.game_time
	th["unread"] = int(th["unread"]) + 1
	th["answered"] = false
	_gs.bus.phone_message.emit(key, text)


func _contact_for(u: Dictionary, gov: bool) -> Dictionary:
	var mind: Dictionary = u.get("mind", {})
	var role: String = String(mind.get("gov_role", ""))
	var town_name: String = _town_name_of(u)
	var sub: String = role.replace("_", " ").capitalize()
	if town_name != "":
		sub += " · " + town_name
	return {
		"key": _key_for(int(u.get("id", 0))),
		"name": SimPersonality.display_name(u),
		"sub": sub if sub != "" else String(u.get("job", "citizen")).capitalize(),
		"faction": String(u.get("faction", "")),
		"unit_id": int(u.get("id", 0)),
		"pfp": pfp_key_for(u),
		"gov": gov,
		"rank": int(GOV_RANK.get(role, 50)),
	}


## Portrait art key for a unit (deterministic per unit id).
## Jeremy 2026-10-06: portrait files use SINGULAR faction names
## (portrait_human_3, not portrait_humans_3) — map plural ids down.
const _PFP_FACTION_SINGULAR := {
	"humans": "human", "elves": "elf", "ogres": "ogre",
	"gnomes": "gnome",
}
## Undead portrait pool (no portrait_undead_* files exist — cycle the
## undead character portraits instead).
const _PFP_UNDEAD_POOL := ["skeleton", "zombie", "ghoul", "wraith",
	"necromancer", "plaguebearer", "lich_a", "lich_b"]


static func pfp_key_for(unit: Dictionary) -> String:
	var faction: String = String(unit.get("faction", "humans"))
	if faction == "undead":
		var uidx: int = absi(int(unit.get("id", 1)) * 7 + 3) \
			% _PFP_UNDEAD_POOL.size()
		return _PFP_UNDEAD_POOL[uidx]
	var sing: String = String(_PFP_FACTION_SINGULAR.get(faction, faction))
	var slot: int = absi(int(unit.get("id", 1)) * 7 + 3) % 8
	return "portrait_%s_%d" % [sing, slot]


## --- Faction leaders (Jeremy 2026-10-04) ------------------------------------
## Leaders are special contacts with keys "leader_<faction>". They use the
## same realistic-texting queue as units (typing indicators, delays).

## Voice -> subtitle flavor for the contacts list.
const LEADER_VOICE_FLAVOR := {
	"diplomatic": "measured and fair",
	"blunt": "blunt and brutal",
	"elegant": "ancient and proud",
	"mischievous": "cunning and sly",
	"cold": "cold and patient",
}

## All faction leaders as contacts (for the Messenger contact list).
## The player's own faction is EXCLUDED — the player is that faction's
## leader (Jeremy 2026-10-06).
func leader_contacts() -> Array:
	var out: Array = []
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return out
	for l: Dictionary in fl.all_leaders():
		var f: String = String(l.get("faction", ""))
		if f == _gs.player_faction:
			continue
		var fname: String = String(
			Config.FACTIONS.get(f, {}).get("name", f.capitalize()))
		var flavor: String = String(LEADER_VOICE_FLAVOR.get(
			String(l.get("voice", "")), "not to be trifled with"))
		out.append({
			"key": SimFactionLeaders.key_for(f),
			"name": "%s %s" % [String(l.get("name", "")), String(l.get("title", ""))],
			"sub": "Leader of the %s — %s" % [fname, flavor],
			"faction": f,
			"unit_id": -1,
			"pfp": String(l.get("pfp", "")),
			"gov": true,
			"rank": -1,  # leaders pin above government
			"leader": true,
		})
	return out


## Player sends a message to a faction leader. Async like send_message.
func send_leader_message(faction: String, text: String) -> void:
	# Jeremy 2026-10-06: ASSFACE rides the leader_* key routing (his key is
	# "leader_assface") — intercept before real leader handling.
	if faction == SimAssface.FACTION_TAG:
		send_assface_message(text)
		return
	# Jeremy 2026-10-11: MR SMART BITCH rides the same routing (his key is
	# "leader_smartbitch") — intercept before real leader handling.
	if faction == SimSmartBitch.FACTION_TAG:
		send_smartbitch_message(text)
		return
	var key: String = SimFactionLeaders.key_for(faction)
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return
	var th: Dictionary = _thread(key)
	var now: float = _gs.game_time
	(th["messages"] as Array).append({"from": "player", "text": text,
		"day": _gs.day_number, "ts": now, "status": "sending"})
	th["uses"] = int(th["uses"]) + 1
	th["last_ts"] = now
	th["answered"] = true
	_gs.bus.phone_message_status.emit(key,
		(th["messages"] as Array).size() - 1, "sending")
	# Hate-slur check applies to leaders too (Jeremy 2026-10-06): ANY IRL
	# racial or anti-LGBTQ slur from the player is the same hard line as
	# the hard-r — full SimRacistOutrage cascade.
	if SimHateSpeech.is_hate_slur(text):
		SimRacistOutrage.trigger(_gs, self)
		var l: Dictionary = fl.leader_of(faction)
		var outrage: String = "\"%s\" — even from you? WAR." % String(l.get("name", ""))
		_queue_reply(key, outrage)
		return
	var reply: String = _leader_full_reply(faction, text)
	_queue_reply(key, reply)


## Jeremy 2026-10-06: conversation-system integration — faction leaders go
## through the FULL Hearsay conversation engine (79 intents, Living Lexicon,
## shared memory/mood/affection, faction voice) like every other NPC. The old
## keyword router is retired; diplomatic SIDE EFFECTS still resolve through
## the systems that own them (peace offers run real diplomacy).
## The leader is presented to the engine as a pseudo-unit with a stable
## negative id (real unit ids are always positive), so per-leader
## conversation memory, chatx affect, and learned words persist in the
## shared conversation state and save data.
func _leader_unit(faction: String) -> Dictionary:
	var fl = _gs.get("faction_leaders")
	var l: Dictionary = fl.leader_of(faction) if fl != null else {}
	var lname := String(l.get("name", "Leader"))
	var uid := -1 - absi(hash("leader:" + faction))
	return {
		"id": uid,
		"faction": faction,
		"name": lname,
		"display_name": lname,
		"town": "",
		"job": "ruler",
		"alive": true,
		"mind": {
			"name": lname,
			"persona": String(l.get("voice", "diplomatic")),
			"gov_role": "leader",
		},
	}


func _leader_full_reply(faction: String, text: String) -> String:
	var fl = _gs.get("faction_leaders")
	# Keep the leader's own message log (drives mood_toward etc.).
	if fl != null:
		fl.remember(faction, "message", _gs.player_faction,
			"Player said: \"%s\"" % text, 0.0)
	var unit := _leader_unit(faction)
	# Jeremy 2026-10-06: the leader IS the faction's controller, symmetric
	# to the player — their first words must track the real relationship
	# (war, betrayals, alliances, grudges), not open neutral. Seed the
	# conversation mood from the leader's standing mood on first contact;
	# afterwards the dialogue system owns it.
	if fl != null:
		var uid := int(unit.get("id", 0))
		var mem_mood: float = conversation.ruler_mood(uid)
		if mem_mood == 0.0:
			conversation.set_ruler_mood(uid, _leader_standing_mood(faction))
	var result: Dictionary = conversation.reply(unit, text, _gs)
	var reply_text := String(result.get("text", ""))
	if reply_text.is_empty():
		reply_text = "..."
	# Consequential intent with a real game-state side effect: a "peace
	# offer" in a ruler DM resolves through diplomacy (HTML offerPeace62
	# parity), and the outcome grounds the reply.
	if String(result.get("intent", "")) == "peace_offer":
		var dip = _gs.get("diplomacy")
		if dip != null:
			var res: Dictionary = dip.offer_peace(faction)
			var msg := String(res.get("msg", "..."))
			if not bool(res.get("ok", false)):
				reply_text = "\"" + msg + "\""
			elif bool(res.get("accepted", false)):
				reply_text = "\"Very well. The banners come down. " + msg + "\""
			else:
				reply_text = "\"" + msg + " So the war continues.\""
	return reply_text


## --- ASSFACE: the phone disaster (Jeremy 2026-10-06) ---------------------------
## Assface is a phone-only entity on thread key "leader_assface" (he rides
## the leader_* key routing in the UI). The disaster: 30 REAL seconds of
## prank-texting — rapid-fire stupid texts to the player AND prank texts
## dropped into every AI leader's thread (leaders react in-character via
## the full engine). Afterwards he's a permanent, messageable contact.
##
## Design correction: he goes through the FULL 79-intent engine for
## comprehension, but his response generation is persona-locked to pure
## idiocy (SimAssface.idiot_reply) — a moron who understands you perfectly
## and STILL only talks about butts. He never breaks into competence.

## Player sends a message to Assface. Async like send_leader_message.
func send_assface_message(text: String) -> void:
	var key: String = SimAssface.KEY
	if is_blocked_key(key):
		return
	var az = _gs.get("assface")
	if az == null:
		return
	var th: Dictionary = _thread(key)
	var now: float = _gs.game_time
	(th["messages"] as Array).append({"from": "player", "text": text,
		"day": _gs.day_number, "ts": now, "status": "sending"})
	th["uses"] = int(th["uses"]) + 1
	th["last_ts"] = now
	th["answered"] = true
	_gs.bus.phone_message_status.emit(key,
		(th["messages"] as Array).size() - 1, "sending")
	# The game's hard line applies to Assface too: ANY IRL racial or
	# anti-LGBTQ slur from the player triggers the full outrage cascade.
	# Even Assface thinks that's too far.
	if SimHateSpeech.is_hate_slur(text):
		SimRacistOutrage.trigger(_gs, self)
		_queue_reply(key, "whoa whoa WHOAH. even *I* don't say THAT word, %s. that's fucked up and I know fucked up. I'm telling everyone you're a butt!!!" % _gs.ruler_name)
		return
	# Full engine for comprehension...
	var result: Dictionary = conversation.reply(az.pseudo_unit(), text, _gs)
	var reply_text := String(result.get("text", ""))
	# ...then the persona lock: discard the competent text, stay an idiot.
	var idiot: String = az.idiot_reply(result, text, _gs.ruler_name)
	if idiot != "":
		reply_text = idiot
	if reply_text == "":
		reply_text = "butts!!!"
	_queue_reply(key, reply_text)


## --- MR SMART BITCH: the phone tutor (Jeremy 2026-10-11) ---------------------
## Smart Bitch is a phone-only entity on thread key "leader_smartbitch"
## (he rides the leader_* key routing in the UI, like Assface). He is a
## permanent, messageable contact: a self-aware tutor who teaches Jeremy
## the game — controls, systems, strategy, what's new — with real answers
## verified against the repo, plus NPC knowledge from real data
## (SimLikesDislikes, SimPersonality, SimConversation memory).

## Player sends a message to Smart Bitch. Async like send_leader_message.
func send_smartbitch_message(text: String) -> void:
	var key: String = SimSmartBitch.KEY
	if is_blocked_key(key):
		return
	var sb := _smartbitch_obj()
	var th: Dictionary = _thread(key)
	var now: float = _gs.game_time
	(th["messages"] as Array).append({"from": "player", "text": text,
		"day": _gs.day_number, "ts": now, "status": "sending"})
	th["uses"] = int(th["uses"]) + 1
	th["last_ts"] = now
	th["answered"] = true
	_gs.bus.phone_message_status.emit(key,
		(th["messages"] as Array).size() - 1, "sending")
	# The game's hard line applies to Smart Bitch too: ANY IRL racial or
	# anti-LGBTQ slur from the player triggers the full outrage cascade.
	if SimHateSpeech.is_hate_slur(text):
		SimRacistOutrage.trigger(_gs, self)
		_queue_reply(key, "Whoa. Even *I* have lines I won't cross, %s — and I'm the crude one. That's a hard no, from everyone, forever. We're done here." % _gs.ruler_name)
		return
	# His own brain: keyword intent -> verified answers, NPC data lookups,
	# numbered-menu follow-ups. Never invents mechanics.
	var reply_text: String = sb.reply(text, _gs.ruler_name)
	if reply_text == "":
		reply_text = "Ask me about the game, %s. I know everything. It's exhausting." % _gs.ruler_name
	_queue_reply(key, reply_text)


## Queue one Assface message at an explicit delivery time (burst use).
func _assface_pending(key: String, text: String, deliver_at: float) -> void:
	var typing_for: float = typing_duration(text)
	_pending.append({
		"key": key,
		"reply_text": text,
		"typing_until": maxf(deliver_at - typing_for, _gs.game_time),
		"deliver_at": deliver_at,
		"typing_shown": false,
	})


## Daily disaster roll (called from _on_day_changed).
func _assface_day_tick() -> void:
	var az = _gs.get("assface")
	if az == null:
		return
	if az.roll_fire(_gs.day_number):
		_fire_assface_burst(az)


## Fire the 30-second prank burst: player gets spammed, every AI leader
## gets prank-texted in their own thread and reacts in-character.
func _fire_assface_burst(az) -> void:
	var now: float = _gs.game_time
	var plan: Dictionary = az.begin_burst(now)
	var pkey: String = SimAssface.KEY
	# The player's phone blows up: ~18 texts over 30 seconds. Blocked =
	# completely silent (the leaders still get theirs — that's not the
	# player's phone).
	if not is_blocked_key(pkey):
		var cursor := now + 1.0
		for line in plan.get("player", []):
			_assface_pending(pkey, String(line), cursor)
			cursor += SimAssface.BURST_GAP
	# Every AI faction leader gets prank-texted in their thread and
	# answers in-character through the full engine.
	var fl = _gs.get("faction_leaders")
	var leaders: Dictionary = plan.get("leaders", {})
	var li := 0
	for f: String in leaders:
		var lkey: String = SimFactionLeaders.key_for(f)
		var lcursor := now + 4.0 + float(li) * 5.0
		var last_prank := ""
		for pl in leaders[f]:
			var ptext := "[Prank text from ASSFACE]: %s" % String(pl)
			_assface_pending(lkey, ptext, lcursor)
			last_prank = String(pl)
			lcursor += 3.0
		# The leader reacts to the prank like anyone ambushed by an idiot.
		if fl != null and last_prank != "":
			var react := _leader_full_reply(f, last_prank)
			_assface_pending(lkey, react, lcursor + 2.5)
		li += 1


## Burst-end check, called every tick: unlock the contact and seed the
## aftermath (the realm talks about the stupid shit he said).
func _assface_burst_tick(now: float) -> void:
	var az = _gs.get("assface")
	if az == null:
		return
	if az.burst_active and now >= az.burst_ends_at:
		az.end_burst()
		_unlock_assface_contact()
		_assface_aftermath(az)


## Permanent contact after the event (Jeremy: "in the player's contact
## list after the event and you can message him").
func _unlock_assface_contact() -> void:
	var added: Array = state["added"]
	if not added.has(SimAssface.KEY):
		added.append(SimAssface.KEY)
		_gs.bus.phone_contact_added.emit(SimAssface.KEY)


## Aftermath: the other NPCs TALK about the stupid shit Assface said.
## Seeds a high-heat comedy rumor (spreads through normal gossip), drops
## Squabble posts quoting his burst lines, and gives every pranked leader
## a real memory of it. Reactions are amusement/mockery — never anger at
## Assface (hearsay "assface" kind handling); he's a lovable menace.
func _assface_aftermath(az) -> void:
	var quoted: Array = az._burst_lines
	if quoted.is_empty():
		return
	var quote := String(quoted[randi() % quoted.size()])
	var hs = hearsay
	var knower := _assface_random_citizen()
	var kid := int(knower.get("id", -1)) if not knower.is_empty() else -1
	if hs != null and hs.has_method("seed_rumor"):
		hs.seed_rumor(
			"ASSFACE struck again! Thirty seconds of prank texts terrorized every phone in the realm — witnesses are still wheezing about the legendary \"%s\"." % quote,
			"assface", "assface", 0.85, kid)
	# Squabble: NPCs quote his stupidest texts.
	for i in range(3):
		var author := _assface_random_citizen()
		if author.is_empty():
			continue
		var q2 := String(quoted[randi() % quoted.size()])
		var posts := [
			"did anyone else just get prank-texted by ASSFACE?? \"%s\" I'M CRYING" % q2,
			"ASSFACE got me again. \"%s\" at 3 in the morning. respect." % q2,
			"my leader got prank-texted by ASSFACE: \"%s\" and I have never laughed so hard" % q2,
		]
		npc_post(author, posts[i % posts.size()], "mood")
	# Every AI leader remembers being pranked.
	var fl = _gs.get("faction_leaders")
	if fl != null:
		for l: Dictionary in fl.all_leaders():
			var f := String(l.get("faction", ""))
			if f == "" or f == String(_gs.player_faction):
				continue
			fl.remember(f, "assface_prank", "Assface",
				"Prank-texted by Assface during his 30-second rampage: \"%s\"" % quote,
				0.6)


## Random living citizen (any faction) for aftermath posts/knowers.
func _assface_random_citizen() -> Dictionary:
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)):
			cands.append(u)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


## The leader's standing conversation-mood (-100..100) from their real
## relationship with the player's faction: wars, betrayals, alliances,
## racist incidents, and decayed memories. Mirrors mood_toward() tiers.
func _leader_standing_mood(faction: String) -> float:
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return 0.0
	match String(fl.mood_toward(faction, _gs.player_faction)):
		"furious":
			return -85.0
		"hostile":
			return -45.0
		"warm":
			return 45.0
		"friendly":
			return 65.0
		"angry":
			return -55.0
		"happy":
			return 55.0
	return 0.0


## A faction leader messages the player (async, with typing indicator).
func leader_message(faction: String, text: String) -> void:
	var key: String = SimFactionLeaders.key_for(faction)
	# Leader-initiated messages get a short typing delay for realism.
	_pending.append({
		"key": key,
		"reply_text": text,
		"typing_until": _gs.game_time + 0.8,
		"deliver_at": _gs.game_time + 0.8 + typing_duration(text),
		"typing_shown": false,
	})


## Pseudo-unit dict for a leader key, for avatar/name rendering in the
## phone UI (leaders are not world units). Carries the leader's distinct
## persona portrait key (_leader_pfp).
func leader_pseudo_unit(key: String) -> Dictionary:
	var f: String = SimFactionLeaders.faction_for_key(key)
	var fl = _gs.get("faction_leaders")
	var l: Dictionary = fl.leader_of(f) if fl != null else {}
	if l.is_empty():
		return {}
	return {
		"faction": f, "job": "ruler", "id": 0, "gender": "m",
		"_leader_name": String(l.get("name", "?")),
		"_leader_pfp": String(l.get("pfp", "")),
	}


## Leader display name for a key (for typing indicators etc.).
func leader_name_for_key(key: String) -> String:
	# Jeremy 2026-10-06: ASSFACE rides the leader_* key routing.
	if key == SimAssface.KEY:
		return SimAssface.NAME
	# Jeremy 2026-10-11: MR SMART BITCH rides the same routing.
	if key == SimSmartBitch.KEY:
		return SimSmartBitch.NAME
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return key
	var l: Dictionary = fl.leader_of(SimFactionLeaders.faction_for_key(key))
	if l.is_empty():
		return key
	return String(l.get("name", key))


## Bio from REAL events/memories only — never invented (Jeremy's law).
## Returns "" when the NPC has no recorded life yet.
func bio_for(unit: Dictionary) -> String:
	var mems: Array = unit.get("memories", [])
	if mems.is_empty():
		return ""
	var bits: Array[String] = []
	var counts: Dictionary = {}
	for m: Dictionary in mems:
		var t: String = String(m.get("type", ""))
		counts[t] = int(counts.get(t, 0)) + 1
	var name: String = SimPersonality.display_name(unit)
	if int(counts.get("hurt_by", 0)) > 0:
		bits.append("has survived %d attack(s)" % counts["hurt_by"])
	if int(counts.get("helped_by", 0)) > 0:
		bits.append("owes %d debt(s) of gratitude" % counts["helped_by"])
	if int(counts.get("worked_with", 0)) > 0:
		bits.append("has worked alongside %d folk" % counts["worked_with"])
	if int(counts.get("insulted_by", 0)) + int(counts.get("mocked_by", 0)) > 0:
		bits.append("has been mocked and remembers it")
	if int(counts.get("friend_died", 0)) > 0:
		bits.append("has buried %d friend(s)" % counts["friend_died"])
	if int(counts.get("saved_by", 0)) > 0:
		bits.append("was saved from death itself")
	if bits.is_empty():
		return ""
	return name + " " + ", ".join(bits) + "."


## --- Messenger ----------------------------------------------------------------

## Thread schema: {key, messages: Array[{from, text, day, ts, status}],
##   unread: int, uses: int, last_ts: float, answered: bool,
##   typing: bool} — status is "sending"|"delivered"|"seen" (player msgs).

func _thread(key: String) -> Dictionary:
	var threads: Dictionary = state["threads"]
	if not threads.has(key):
		threads[key] = {"key": key, "messages": [], "unread": 0,
			"uses": 0, "last_ts": 0.0, "answered": true, "typing": false}
	return threads[key]


## Player sends a message. Jeremy 2026-10-04: realistic texting — the
## player's message shows "sending" briefly, then the NPC "types" for a
## bit (typing indicator) before the reply arrives. Returns "" immediately
## now (reply arrives async via the pending queue + phone_message signal).
## Blocked threads can't send (HTML msgrSendDM guard).
func send_message(unit_id: int, text: String) -> String:
	var key: String = _key_for(unit_id)
	if is_blocked_key(key):
		return ""
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return ""
	var th: Dictionary = _thread(key)
	var now: float = _gs.game_time
	# Player's message: starts as "sending", flips to "delivered" in tick.
	(th["messages"] as Array).append({"from": "player", "text": text,
		"day": _gs.day_number, "ts": now, "status": "sending"})
	th["uses"] = int(th["uses"]) + 1
	th["last_ts"] = now
	th["answered"] = true  # player answered the NPC; NPC now owes a reply
	_gs.bus.phone_message_status.emit(key,
		(th["messages"] as Array).size() - 1, "sending")
	# THE HATE-SLUR LINE (Jeremy 2026-10-02, broadened 2026-10-06): if the
	# PLAYER uses any IRL racial or anti-LGBTQ slur, every faction declares
	# war on the player and the whole realm reacts — Gazette scandal,
	# hearsay, furious DMs (SimRacistOutrage). Factions at war trash-talking
	# each other is allowed; this line is not.
	if SimHateSpeech.is_hate_slur(text):
		var outrage_reply: String = SimRacistOutrage.outrage_reply_for(
			u, _gs.ruler_name)
		SimRacistOutrage.trigger(_gs, self)
		_queue_reply(key, outrage_reply)
		return ""
	# Jeremy 2026-10-04: wall-raise hearsay — if this thread has a pending
	# wall question and the player said yes/no, answer it through hearsay
	# instead of the normal conversation flow.
	var wall_reply: String = _check_wall_answer(key, text)
	if wall_reply != "":
		_queue_reply(key, wall_reply)
		return ""
	var reply: String = _npc_reply(u, text)
	var delivered_at: float = _queue_reply(key, reply)
	# Jeremy 2026-10-06: unhinged NPC spam burst — extra cuss-outs chained
	# after the main reply, each with its own typing indicator. Capped with
	# a per-thread cooldown so rapid player messages can't flood the queue.
	# Block-safe: send_message returns early on blocked threads, and the
	# Squabble comment paths call _npc_reply directly (never reach here).
	if String(_last_reply_effect.get("type", "")) == "unhinged_spam":
		_queue_spam(key, _last_reply_effect.get("extras", []), delivered_at)
	_last_reply_effect = {}
	return ""


## Queues an NPC reply: "sending" -> "delivered" for the player's message,
## then a typing indicator, then the reply arrives. All timed off game_time.
## Returns the scheduled delivery time (for chaining follow-ups like spam).
func _queue_reply(key: String, reply_text: String) -> float:
	var now: float = _gs.game_time
	var typing_for: float = typing_duration(reply_text)
	# Player's message flips to delivered just before typing starts.
	var th: Dictionary = _thread(key)
	for m: Dictionary in th["messages"]:
		if String(m.get("from", "")) == "player" \
				and String(m.get("status", "")) == "sending":
			m["status"] = "delivered"
	_gs.bus.phone_message_status.emit(key, -1, "delivered")
	var deliver_at: float = now + SEND_DELAY + typing_for
	_pending.append({
		"key": key,
		"reply_text": reply_text,
		"typing_until": now + SEND_DELAY,
		"deliver_at": deliver_at,
		"typing_shown": false,
	})
	return deliver_at


## Jeremy 2026-10-06: unhinged spam burst. Extras are chained AFTER the main
## reply's delivery, spaced so they arrive in rapid succession — each with
## its own typing indicator, like a real furious person hammering out texts.
## Hard cap + per-thread cooldown: no floods, no soft-locks.
const UNHINGED_SPAM_CAP := 3
const UNHINGED_SPAM_GAP := 1.5
const UNHINGED_BURST_COOLDOWN := 45.0

func _queue_spam(key: String, extras: Array, after: float) -> void:
	var th: Dictionary = _thread(key)
	var now: float = _gs.game_time
	if now - float(th.get("_unhinged_burst_at", -1000000.0)) \
			< UNHINGED_BURST_COOLDOWN:
		return
	th["_unhinged_burst_at"] = now
	var cursor: float = after
	var n := 0
	for e in extras:
		if n >= UNHINGED_SPAM_CAP:
			break
		var et := String(e)
		if et.is_empty():
			continue
		var typing_for: float = typing_duration(et)
		cursor += UNHINGED_SPAM_GAP + typing_for
		_pending.append({
			"key": key,
			"reply_text": et,
			"typing_until": cursor - typing_for,
			"deliver_at": cursor,
			"typing_shown": false,
		})
		n += 1


## Backwards-compat: some callers still expect the reply text synchronously.
## Prefer send_message (async). Only used by tests.
func send_message_sync(unit_id: int, text: String) -> String:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return ""
	if SimHateSpeech.is_hate_slur(text):
		return SimRacistOutrage.outrage_reply_for(u, _gs.ruler_name)
	return _npc_reply(u, text)


## Jeremy 2026-10-04: sends a wall-raise prompt ONCE per region and records
## it as a pending hearsay question. The player answers by replying yes/no
## in this thread; _check_wall_answer() handles the response. Never sends
## if a question is already pending for this thread (one ask, one answer).
func ask_wall_question(unit_id: int, region_name: String, text: String) -> void:
	var key: String = _key_for(unit_id)
	# One ask per thread — if a question is already pending, don't re-send.
	if _wall_questions.has(key):
		return
	npc_message(unit_id, text)
	# Only record if the message actually went through (not blocked).
	var u: Dictionary = _gs.get_unit(unit_id)
	if not u.is_empty() and not is_blocked_key(key):
		_wall_questions[key] = region_name


## Checks whether the player's reply answers a pending wall question.
## Returns the NPC's confirmation reply, or "" if no wall question pending.
## Emits wall_answer on the bus when the player says yes or no.
func _check_wall_answer(key: String, player_text: String) -> String:
	if not _wall_questions.has(key):
		return ""
	var region: String = String(_wall_questions[key])
	var verdict := _parse_wall_verdict(player_text)
	if verdict < 0:
		return ""  # not a yes/no — let normal conversation handle it
	_wall_questions.erase(key)
	_gs.bus.wall_answer.emit(region, verdict == 1)
	if verdict == 1:
		return "Done — walls going up around %s. The workers are on it." % region
	return "Understood — no walls for %s. Say the word if you change your mind." % region


## Parses a yes/no verdict from player text. Returns 1 (yes), 0 (no),
## or -1 (not a yes/no answer). Checks "no" patterns first so "no, wait —
## yes" style corrections lean toward the explicit "no".
static func _parse_wall_verdict(text: String) -> int:
	var t: String = " " + text.to_lower().strip_edges() + " "
	# Explicit "no" — check first.
	var no_pats: Array[String] = [
		" no ", " nope ", " nah ", " no way ", " negative ",
		" disagree ", " don\\'t ", " dont ", " do not ",
		" skip ", " skip them ", " never ", " stop ",
		" hell no ", " absolutely not",
	]
	for p: String in no_pats:
		# Handle the escaped apostrophe pattern.
		var pat: String = p.replace("\\'", "'")
		if t.contains(pat):
			return 0
	# Explicit "yes".
	var yes_pats: Array[String] = [
		" yes ", " yeah ", " yep ", " yup ", " yes please ",
		" agree ", " agreed ", " do it ", " raise ", " raise them ",
		" build ", " build them ", " go ahead ", " ok ", " okay ",
		" sure ", " definitely ", " absolutely ", " please ",
	]
	for p2: String in yes_pats:
		if t.contains(p2):
			return 1
	return -1
## NPC-initiated message (events, petitions). Marks thread unread.
## Blocked NPCs' messages stop arriving (HTML msgrDeliverRuler guard).
func npc_message(unit_id: int, text: String) -> void:
	var key: String = _key_for(unit_id)
	if is_blocked_key(key):
		return
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return
	var th: Dictionary = _thread(key)
	var msgs: Array = th["messages"] as Array
	# Jeremy 2026-10-04: dedupe — never queue an identical message twice in
	# a row (the border-wall prompt spammed 57 identical texts because the
	# caller re-sent every tick). Collapse exact consecutive duplicates.
	if not msgs.is_empty():
		var last: Dictionary = msgs[msgs.size() - 1]
		if String(last.get("from", "")) == "npc" \
				and String(last.get("text", "")) == text:
			return
	msgs.append({"from": "npc", "text": text,
		"day": _gs.day_number, "ts": _gs.game_time})
	th["last_ts"] = _gs.game_time
	th["unread"] = int(th["unread"]) + 1
	th["answered"] = false
	_gs.bus.phone_message.emit(key, text)


## Jeremy 2026-10-07: a petition was opened before the crown. The petitioner
## DMs the ruler directly (blockable + deduped via npc_message, thread rises
## as unanswered) and a toast announces it — previously the petition sat
## silently in the Gazette's Messages tab with zero notification.
func _on_petition_opened(p: Dictionary) -> void:
	if _gs.player_faction == "":
		return  # sandbox observer — no crown to petition
	var from_key := String(p.get("from_key", ""))
	if not from_key.begins_with("u"):
		return
	var unit_id := int(from_key.trim_prefix("u"))
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty() or not bool(u.get("alive", false)):
		return
	var from_name := String(p.get("from_name", "A courtier"))
	var role := String(p.get("role", "courtier"))
	# The DM is the petitioner's own voice: the casual "talk" line when the
	# template has one, else the petition text trimmed to DM length.
	var hook := String(p.get("talk", "")).strip_edges()
	if hook == "":
		hook = String(p.get("text", "")).strip_edges()
		if hook.length() > 110:
			hook = hook.substr(0, 110).strip_edges() + "…"
	if hook == "":
		hook = "A matter begs the crown's attention."
	var dm := "%s — I've laid it before the crown. You'll find it in the Gazette, under Messages." % hook
	npc_message(unit_id, dm)
	# The toast is the court's public announcement (not the NPC speaking),
	# so it fires even when the petitioner is blocked.
	_gs.bus.toast.emit("New petition: %s (%s) — see the Gazette." % [from_name, role])


## Marks a thread read.
func read_thread(unit_id: int) -> void:
	var th: Dictionary = _thread(_key_for(unit_id))
	th["unread"] = 0


## Jeremy 2026-10-06: mark any thread read by key (units AND leaders).
func read_thread_key(key: String) -> void:
	var th: Dictionary = _thread(key)
	th["unread"] = 0


## Threads sorted per the remembered mode. Answered threads sink; threads
## with unanswered incoming rise (HTML rule).
func sorted_threads() -> Array:
	var arr: Array = (state["threads"] as Dictionary).values()
	match String(state.get("sort", "latest")):
		"most_used":
			arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("uses", 0)) > int(b.get("uses", 0)))
		"unread_first":
			arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var au: int = int(a.get("unread", 0))
				var bu: int = int(b.get("unread", 0))
				if (au > 0) != (bu > 0):
					return au > bu
				return float(a.get("last_ts", 0.0)) > float(b.get("last_ts", 0.0)))
		_:  # latest
			arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var aa: bool = not bool(a.get("answered", true))
				var ba: bool = not bool(b.get("answered", true))
				if aa != ba:
					return aa  # unanswered incoming rises
				return float(a.get("last_ts", 0.0)) > float(b.get("last_ts", 0.0)))
	return arr


func set_sort(mode: String) -> bool:
	if not mode in SORTS:
		return false
	state["sort"] = mode
	return true


## Offline intent parsing: keywords -> reply table, deterministic pick.
## True if this unit has an unresolved court petition.
func _has_open_petition(unit: Dictionary) -> bool:
	if _court == null:
		return false
	var key := "u%d" % int(unit.get("id", 0))
	for p in _court.open_petitions():
		if String(p.get("from_key", "")) == key:
			return true
	return false


## True if the text reads as a yes/no verdict on a petition.
static func _is_petition_verdict(text: String) -> bool:
	var t := " " + text.to_lower().strip_edges() + " "
	var agree := ["yes", "yeah", "yep", "aye", "agree", "agreed", "accept",
		"accepted", "approve", "approved", "deal", "done", "of course",
		"certainly", "absolutely", "fine", "ok", "okay", "granted", "do it",
		"go ahead"]
	var refuse := ["no", "nope", "nah", "never", "refuse", "refused",
		"decline", "declined", "deny", "denied", "reject", "rejected",
		"forbid", "forbidden", "no way", "not interested"]
	for w in agree:
		if t.contains(" " + w + " ") or t.contains(" " + w + ",") \
				or t.contains(" " + w + ".") or t.contains(" " + w + "!"):
			return true
	for w in refuse:
		if t.contains(" " + w + " ") or t.contains(" " + w + ",") \
				or t.contains(" " + w + ".") or t.contains(" " + w + "!"):
			return true
	return false


## {name} and {ruler} filled verbatim; ruler name never trimmed.
## Court character reply via the Gazette two-way chat (HTML gazCraftReply).
## Builds the character dict from the unit, parses intent, crafts the reply
## with persona voice and mood memory. If the reply resolves a pending
## petition, the petition is decided.
func _court_reply(unit: Dictionary, text: String, role: String) -> String:
	var GazetteScript := load("res://scripts/sim/gazette.gd")
	var gaz: RefCounted = GazetteScript.new(_gs)
	var intent: String = gaz.parse_intent(text)
	# Build the character dict (HTML court character schema).
	var mind: Dictionary = unit.get("mind", {})
	var character := {
		"name": SimPersonality.display_name(unit),
		"role": role,
		"race": String(unit.get("faction", "")),
		"persona": String(mind.get("persona", "pragmatic")),
		"mood": float(mind.get("court_mood", 50.0)),
		"_agreed": int(mind.get("_court_agreed", 0)),
		"_refused": int(mind.get("_court_refused", 0)),
		"_threatened": int(mind.get("_court_threatened", 0)),
	}
	# Find pending petition from this unit (if any).
	var pending := {}
	if _court != null:
		for p in _court.open_petitions():
			if String(p.get("from_key", "")) == "u%d" % int(unit.get("id", 0)):
				pending = {
					"text": String(p.get("text", "")),
					"choices": [{"outcome": "Accepted."}, {"outcome": "Refused."}],
					"petition_id": int(p.get("id", 0)),
				}
				break
	var result: Dictionary = GazetteScript.craft_reply(character, intent, text, pending, _gs)
	# Persist mood memory back to the unit's mind.
	mind["court_mood"] = float(character.get("mood", 50.0))
	mind["_court_agreed"] = int(character.get("_agreed", 0))
	mind["_court_refused"] = int(character.get("_refused", 0))
	mind["_court_threatened"] = int(character.get("_threatened", 0))
	# If the reply resolved a petition, decide it.
	if bool(result.get("resolved", false)) and not pending.is_empty():
		var pid: int = int(pending.get("petition_id", 0))
		if pid > 0 and _court != null:
			# agree -> choice 0, refuse -> last choice
			var choice_idx := 0 if intent == "agree" else 1
			_court.decide(pid, choice_idx)
	# HTML parity (fix79 ~61085): a lord threatened 2+ times seethes — the
	# Gazette covers it. publish_story sanitizes glyphs (tofu rule), so the
	# dagger emoji never reaches the page.
	if bool(result.get("lord_seethes", false)) and _court != null \
			and _court.has_method("publish_story"):
		_court.publish_story("LORD SEETHES",
			"%s was heard swearing vengeance after the ruler's threats. Daggers are being sharpened somewhere." % SimPersonality.display_name(unit),
			"court")
	return str(result.get("text", ""))


func _npc_reply(unit: Dictionary, text: String) -> String:
	# Jeremy 2026-10-06: reset the stashed reply effect; the conversation
	# block below re-stashes it when present (unhinged spam burst).
	_last_reply_effect = {}
	# HTML parity: in the original, EVERY Messenger DM went through
	# msgrEngineReply (the full 79-intent engine) — gazCraftReply was only
	# for the Gazette's own court message threads. Court characters only
	# use the court engine here when answering an open petition.
	var mind: Dictionary = unit.get("mind", {})
	var gov_role := String(mind.get("gov_role", ""))
	if gov_role in ["mayor", "lord", "commander"] \
			and _has_open_petition(unit) and _is_petition_verdict(text):
		return _court_reply(unit, text, gov_role)
	# C67: court characters (mayor/lord/commander) answer "how many X" /
	# troop-report questions with LIVE per-job counts (HTML ~61055) even
	# when there is no open petition — computed at speak time, never
	# cached. Falls through to the full engine otherwise.
	if gov_role in ["mayor", "lord", "commander"]:
		var GazetteScript := load("res://scripts/sim/gazette.gd")
		var cans: String = GazetteScript.court_forces_answer(
			_gs, String(unit.get("faction", "")),
			text, SimPersonality.display_name(unit),
			GazetteScript.persona_voice(String(mind.get("persona", "pragmatic"))))
		if cans != "":
			mind["court_mood"] = float(mind.get("court_mood", 50.0)) + 2.0
			return cans
	# Jeremy 2026-10-06: Ruler's Voice — the player's cabinet takes spoken
	# orders in Messenger ("build 3 farms", "train 10 soldiers", "muster
	# the army", "raise taxes", "hold a festival") and carries them out.
	# Foreign cabinets refuse (sovereignty). Returns "" when the text
	# isn't an order — normal conversation proceeds.
	var rv = _gs.get("rulers_voice")
	if rv != null and rv.has_method("try_order"):
		var order_reply: String = rv.try_order(unit, text)
		if order_reply != "":
			return order_reply
	# Wake deep-work 2026-10-08 (Disaster #26): Prince Gnomba's DM thread
	# is a live con — scam verdicts ("send"/"block", incl. the inline
	# thread buttons) resolve through the disaster sim before the
	# conversation engine sees them. Anything else falls through to
	# normal chat untouched.
	var ds = _gs.get("disasters")
	if ds != null and ds.has_method("gnomba_scam_reply"):
		var scam_reply: String = ds.gnomba_scam_reply(unit, text)
		if scam_reply != "":
			return scam_reply
	# Rapid-iteration 2026-10-08 (Disaster #29): Milo the Podcast Bro's DM
	# thread is a live sponsor offer — verdicts ("sponsor"/"unplug", incl.
	# the inline thread buttons) resolve through the disaster sim before
	# the conversation engine sees them. Anything else falls through to
	# normal chat untouched.
	if ds != null and ds.has_method("podcast_offer_reply"):
		var offer_reply: String = ds.podcast_offer_reply(unit, text)
		if offer_reply != "":
			return offer_reply
	# Jeremy 2026-10-03: message the guild master to influence recruiting.
	# "recruit more warriors" / "recruit more workers" sets the faction's
	# recruiting priority; the guild master confirms and hiring biases
	# training queues toward that job.
	if gov_role == "guild_master":
		var rcmd: String = _guild_recruit_command(unit, text)
		if rcmd != "":
			return rcmd
	# C67: the Guild Master and the Financial Adviser answer "how many X" /
	# troop-report questions with LIVE per-job counts (HTML guild master /
	# financial adviser forces-report path ~104125) — computed at speak
	# time, never cached. Falls through to normal chat otherwise.
	if gov_role == "guild_master" or gov_role == "adviser":
		var forces: String = _forces_report_reply(unit, text)
		if forces != "":
			return forces
	# Jeremy 2026-10-04: Full Hearsay conversation engine.
	# Fluent, contextual dialogue with memory, personality, mood,
	# follow-ups, and the Living Lexicon — ported from HTML fix79.
	if conversation != null:
		var result: Dictionary = conversation.reply(unit, text, _gs)
		var reply_text := String(result.get("text", ""))
		if not reply_text.is_empty():
			# Handle effects (e.g., name setting)
			var effect: Dictionary = result.get("effect", {})
			_last_reply_effect = effect
			if String(effect.get("type", "")) == "set_name":
				_set_npc_known_name(unit, String(effect.get("name", "")))
			return reply_text
	# Fallback: mood-driven chatter line (should rarely hit now).
	var line: String = SimDialogue.line_for(_gs, unit, "chatter")
	if line != "":
		return line
	return "..."


## C67 live muster-roll for Guild Master / Financial Adviser DMs
## (HTML guild master / financial adviser forces-report path ~104125).
## Returns the live forces report when the text is a troop-count question,
## "" when it is not (the caller falls through to normal chat).
func _forces_report_reply(unit: Dictionary, text: String) -> String:
	var GazetteScript := load("res://scripts/sim/gazette.gd")
	var faction := String(unit.get("faction", ""))
	return GazetteScript.adviser_forces_answer(_gs, faction, text)


## Jeremy 2026-10-03: guild master recruiting commands via phone chat.
## Returns the guild master's reply if the message is a recruiting command,
## "" if not (caller falls through to normal chatter). Sets the faction's
## recruiting priority on the hiring system.
func _guild_recruit_command(unit: Dictionary, text: String) -> String:
	var t: String = text.to_lower()
	if not (t.contains("recruit") or t.contains("hire") or t.contains("train")):
		return ""
	var faction: String = String(unit.get("faction", ""))
	var job: String = ""
	var job_name: String = ""
	if _has_any(t, ["warrior", "soldier", "fighter", "army", "military"]):
		job = "soldier"
		job_name = "warriors"
	elif _has_any(t, ["archer", "ranger", "bow"]):
		job = "archer"
		job_name = "archers"
	elif _has_any(t, ["mage", "wizard", "magic"]):
		job = "mage"
		job_name = "mages"
	elif _has_any(t, ["worker", "laborer", "gather"]):
		job = "worker"
		job_name = "workers"
	elif _has_any(t, ["builder", "build"]):
		job = "builder"
		job_name = "builders"
	elif _has_any(t, ["farmer", "farm", "food"]):
		job = "farmer"
		job_name = "farmers"
	elif _has_any(t, ["woodcutter", "wood", "lumber"]):
		job = "woodcutter"
		job_name = "woodcutters"
	if job == "":
		return ""
	if _gs.get("hiring") != null:
		_gs.hiring.set_recruit_priority(faction, job)
	var nm: String = SimPersonality.display_name(unit)
	return "Very well, %s. I'll focus our recruiting on %s. The guild will prioritize %s from now on." % [_gs.ruler_name, job_name, job_name]


static func _has_any(t: String, words: Array) -> bool:
	for w: String in words:
		if t.contains(w):
			return true
	return false


func _fill(unit: Dictionary, line: String) -> String:
	var out: String = line.replace("{ruler}", _gs.ruler_name)
	out = out.replace("{name}", SimPersonality.display_name(unit))
	return out


## Store a player-set name for an NPC (from conversation name_set effect).
## Jeremy's rule: full names, never truncated.
func _set_npc_known_name(unit: Dictionary, new_name: String) -> void:
	if new_name.is_empty():
		return
	unit["player_given_name"] = new_name


## --- Squabble -----------------------------------------------------------------
## Post schema: {id, author_key, author_name, faction, pfp, text, day,
##   kind, likes, resquabbles, comments: Array[{author, text}],
##   hashtags: Array[String]}

## Extracts #hashtags from text (lowercased, no duplicates).
static func extract_hashtags(text: String) -> Array:
	var tags: Array = []
	var re := RegEx.new()
	if re.compile("#([A-Za-z0-9_]+)") != OK:
		return tags
	for m in re.search_all(text):
		var tag: String = m.get_string(1).to_lower()
		if not tag in tags:
			tags.append(tag)
	return tags


## NPCs post about REAL sim events. kind: news | roast | praise | mood.
func npc_post(unit: Dictionary, text: String, kind: String = "mood") -> Dictionary:
	var filled: String = _fill(unit, text)
	var post: Dictionary = {
		"id": int(state["post_seq"]),
		"author_key": _key_for(int(unit.get("id", 0))),
		"author_name": SimPersonality.display_name(unit),
		"faction": String(unit.get("faction", "")),
		"pfp": pfp_key_for(unit),
		"text": filled,
		"day": _gs.day_number,
		"kind": kind,
		"likes": 0,
		"resquabbles": 0,
		"comments": [],
		"hashtags": extract_hashtags(filled),
	}
	state["post_seq"] = int(state["post_seq"]) + 1
	(state["posts"] as Array).append(post)
	_gs.bus.squabble_post.emit(post)
	return post


## Player posts as themselves (the ruler).
func ruler_post(text: String) -> Dictionary:
	var post: Dictionary = {
		"id": int(state["post_seq"]),
		"author_key": "ruler",
		"author_name": _gs.ruler_name,
		"faction": _gs.player_faction,
		"pfp": "portrait_ruler",
		"text": text,
		"day": _gs.day_number,
		"kind": "ruler",
		"likes": 0,
		"resquabbles": 0,
		"comments": [],
		"hashtags": extract_hashtags(text),
	}
	state["post_seq"] = int(state["post_seq"]) + 1
	(state["posts"] as Array).append(post)
	_gs.bus.squabble_post.emit(post)
	return post


## Deletes a post. Only the author (or the ruler for their own) can delete.
## Returns true when a post was removed.
func delete_post(post_id: int, requester_key: String) -> bool:
	var posts: Array = state["posts"]
	for i in posts.size():
		var p: Dictionary = posts[i]
		if int(p.get("id", 0)) == post_id:
			if String(p.get("author_key", "")) != requester_key:
				return false
			posts.remove_at(i)
			return true
	return false


## All posts containing the given hashtag (without the #), newest first.
func posts_with_tag(tag: String) -> Array:
	var t: String = tag.trim_prefix("#").to_lower()
	var out: Array = []
	for p: Dictionary in state["posts"]:
		if is_blocked_key(String(p.get("author_key", ""))):
			continue
		var tags: Array = p.get("hashtags", [])
		if t in tags:
			out.append(p)
	out.reverse()
	return out


## Trending hashtags: top tags by post count, as [{tag, count}].
func trending_tags(limit: int = 10) -> Array:
	var counts := {}
	for p: Dictionary in state["posts"]:
		if is_blocked_key(String(p.get("author_key", ""))):
			continue
		for t: String in p.get("hashtags", []):
			counts[t] = int(counts.get(t, 0)) + 1
	var arr: Array = []
	for t: String in counts.keys():
		arr.append({"tag": t, "count": int(counts[t])})
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["count"]) > int(b["count"]))
	return arr.slice(0, limit)


func like_post(post_id: int) -> bool:
	var p: Dictionary = _find_post(post_id)
	if p.is_empty():
		return false
	p["likes"] = int(p.get("likes", 0)) + 1
	return true


func resquabble(post_id: int) -> bool:
	var p: Dictionary = _find_post(post_id)
	if p.is_empty():
		return false
	p["resquabbles"] = int(p.get("resquabbles", 0)) + 1
	return true


## Player comments; the author replies with a scripted line (offline).
## Returns the author's reply text. Blocked authors get no chat.
func comment_post(post_id: int, text: String) -> String:
	var p: Dictionary = _find_post(post_id)
	if p.is_empty():
		return ""
	if is_blocked_key(String(p.get("author_key", ""))):
		return ""
	(p["comments"] as Array).append({"author": _gs.ruler_name, "text": text})
	var u: Dictionary = _unit_for_key(String(p.get("author_key", "")))
	var reply: String
	if u.is_empty():
		reply = "Noted."
	else:
		reply = _npc_reply(u, text)
	(p["comments"] as Array).append(
		{"author": String(p.get("author_name", "?")), "text": reply})
	return reply


## Jeremy 2026-10-04: NPC comments on another NPC's post (for event-driven
## threads like the moose mooning). No scripted reply — just the comment.
func npc_comment(post_id: int, unit: Dictionary, text: String) -> bool:
	var p: Dictionary = _find_post(post_id)
	if p.is_empty():
		return false
	if is_blocked_key(String(p.get("author_key", ""))):
		return false
	(p["comments"] as Array).append(
		{"author": SimPersonality.display_name(unit), "text": text})
	return true


## Newest-first feed. Blocked contacts' posts are filtered out for real:
## a blocked citizen is fully silenced — their posts never appear
## (HTML parity: blocked authors are skipped at render).
func feed() -> Array:
	var arr: Array = []
	for p: Dictionary in state["posts"]:
		if is_blocked_key(String(p.get("author_key", ""))):
			continue
		arr.append(p)
	arr.reverse()
	return arr


## Jeremy 2026-10-04: NPC ambient Squabble activity. Called once per game
## day: random NPCs post about sim life, and NPCs like / resquabble /
## comment on EACH OTHER's posts. Keeps the platform alive.
const AMBIENT_POSTS := [
	"Beautiful day in the kingdom. #blessed",
	"Anyone else smell that? No? Just me? #weird",
	"Work work work. #grind",
	"The tavern has a new ale. Life is good. #ale",
	"Saw the army marching today. Impressive stuff. #army",
	"My crops are coming in nicely. #farmlife",
	"Rain again. My boots are never dry. #weather",
	"Just got paid! Feast tonight! #payday",
	"The market has fresh bread. Get it before it's gone. #bread",
	"Beautiful sunset over the walls tonight. #sunset",
	"Heard a rumor about the neighbors. Spicy. #gossip",
	"My back hurts. Getting old. #ouch",
	"The blacksmith made me a new blade. Shiny! #newgear",
	"Storm's coming. Batten down the hatches. #storm",
	"Won at dice last night! The tavern keeper hates me now. #lucky",
	"Someone's building something big across town. #construction",
	"The well water tastes funny today. #concerned",
	"Day off tomorrow. Sleeping until noon. #rest",
	"My neighbor's rooster is the WORST. #rooster",
	"Good harvest this season. The gods provide. #harvest",
	# Jeremy 2026-10-06: expanded — more voice, more variety.
	"The guild hall coffee is terrible and I will die on this hill. #truth",
	"Just saw the ruler's procession. Fancy hats. Very fancy. #royalty",
	"My kid wants to be a soldier. I'm terrified and proud. #parenting",
	"Lost my favorite hammer. If you see it, no you didn't. #tools",
	"The new tax rate is... a choice. #taxes",
	"Three-legged race at the festival was RIGGED. I demand a recount. #festival",
	"My sheep got out again. If you see them, they're friendly. Mostly. #sheep",
	"Just fixed the roof. My arms are noodles now. #diy",
	"The healer says I need 'rest'. The healer doesn't have my workload. #grind",
	"Found a weird mushroom. Ate it. 10/10 would hallucinate again. #foraging",
	"Someone left pies on my doorstep. I don't ask questions anymore. #blessed",
	"The night watch fell asleep again. The goblins are laughing at us. #security",
	"My apprentice burned the bread. Again. I'm eating charcoal for dinner. #apprentice",
	"Beautiful aurora last night. The sky was showing off. #sky",
	"Just paid off my debts! Freedom tastes like cheap ale! #debtfree",
	"The river's running high. Good fishing, bad bridges. #river",
	"My grandmother's stew recipe > your grandmother's stew recipe. Fight me. #food",
	"Training with the militia. I can barely lift my arms. Worth it. #training",
	"The stars are out and the owls are judging me. #night",
	"New boots! No more wet socks! This is the best day of my life! #boots",
	"Someone's been stealing my cabbages. I have suspects. #mystery",
	"The chapel bells rang at dawn. Peaceful. I almost cried. #faith",
	"My dog learned a new trick. He still won't do the old ones. #dog",
	"Harvest festival planning is chaos and I love it. #festival",
	"The road to the next town is finally paved. My feet thank you. #roads",
	"Just witnessed a proposal in the square. She said yes! I'm emotional! #love",
	"My forge is the hottest in town. Literally. Send water. #blacksmith",
	"The library got new scrolls. Nerd paradise. #books",
	"Rainbow over the eastern fields. The gods are in a good mood. #blessed",
	"My pickaxe broke mid-swing. The mountain laughed at me. #mining",
	"Caught the biggest fish of my life today. It was THIS big. #fishing",
	"The wind took my hat. It's living its best life now. #windy",
	"Just brewed the perfect batch. The tavern will weep with joy. #brewing",
]

const AMBIENT_COMMENTS := [
	"Facts.",
	"lol",
	"Same.",
	"Couldn't agree more.",
	"This.",
	"Big if true.",
	"Tell me about it.",
	"Classic.",
	"Preach!",
	"100%.",
]


## Jeremy 2026-10-06: conversation-system integration — port of HTML
## fix79's sqbGenLexicon. When the Living Lexicon holds player-taught
## words, an NPC may post showing one off, so learned vocabulary is
## visible on Squabble: shared state across channels, not a Messenger-only
## fork. Templates follow the port's no-emoji post style.
const LEXICON_POST_LINES := [
	"{r} just learned the word '{w}' and has used it 40 times today. Send help. #vocabulary",
	"Breaking: {r} says '{w}' now. It means '{m}'. The realm is 3% smarter. #vocabulary",
]


## Posts a lexicon showoff from a random alive NPC. Returns false when
## there is nothing to show off (no player-taught words yet).
func _lexicon_post(u: Dictionary) -> bool:
	var lx = _gs.get("lexicon")
	if lx == null:
		return false
	var words: Array = lx.taught_words()
	# Prefer genuinely player-taught words over baseline seeds.
	var fresh: Array = []
	for w: Dictionary in words:
		if not bool(w.get("seed", false)):
			fresh.append(w)
	if not fresh.is_empty():
		words = fresh
	if words.is_empty():
		return false
	var w: Dictionary = words[randi() % words.size()]
	var word := String(w.get("word", ""))
	if word == "":
		return false
	var meaning := String(w.get("meaning", "")).left(60)
	if meaning == "":
		meaning = "something clever, allegedly"
	var showoff := String(w.get("taught_by", "someone"))
	var tpl: String = LEXICON_POST_LINES[randi() % LEXICON_POST_LINES.size()]
	var text := tpl.replace("{r}", showoff).replace("{w}", word)\
		.replace("{m}", meaning)
	npc_post(u, text, "lexicon")
	return true


## Runs one day of NPC Squabble life: ambient posts + engagement.
## Call once per game day from the sim tick.
func npc_ambient_tick() -> void:
	var alive: Array = []
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)):
			alive.append(u)
	if alive.is_empty():
		return
	# 1-3 NPCs post something ambient.
	var posters: Array = alive.duplicate()
	posters.shuffle()
	for i in mini(3, posters.size()):
		if randf() < 0.7:
			var u: Dictionary = posters[i]
			# Lexicon showoff posts get first shot — learned words
			# surface on Squabble (HTML sqbGenLexicon parity).
			if randf() < 0.25 and _lexicon_post(u):
				continue
			npc_post(u, str(AMBIENT_POSTS.pick_random()), "mood")
	# NPCs engage with recent posts (not their own).
	var recent: Array = feed().slice(0, 10)
	for p: Dictionary in recent:
		var pid: int = int(p.get("id", 0))
		var author: String = String(p.get("author_key", ""))
		var engagers: Array = alive.duplicate()
		engagers.shuffle()
		for u: Dictionary in engagers.slice(0, 3):
			if _key_for(int(u.get("id", 0))) == author:
				continue
			var roll := randf()
			if roll < 0.35:
				like_post(pid)
			elif roll < 0.45:
				resquabble(pid)
			elif roll < 0.55:
				_comment_on_post(p, u)
			break  # one engagement per post per day keeps it natural


## Jeremy 2026-10-06: conversation-system integration — an NPC comments
## on a Squabble post through the FULL conversation engine (the post
## text is the prompt), so replies share memory, mood, affection, and
## the Living Lexicon with Messenger. No template-comment fork.
func _comment_on_post(p: Dictionary, u: Dictionary) -> String:
	var reply_text := _npc_reply(u, String(p.get("text", "")))
	(p["comments"] as Array).append(
		{"author": SimPersonality.display_name(u), "text": reply_text})
	return reply_text


func posts_by(unit_id: int) -> Array:
	var key: String = _key_for(unit_id)
	if is_blocked_key(key):
		return []
	var out: Array = []
	for p: Dictionary in state["posts"]:
		if String(p.get("author_key", "")) == key:
			out.append(p)
	out.reverse()
	return out


func _find_post(post_id: int) -> Dictionary:
	for p: Dictionary in state["posts"]:
		if int(p.get("id", 0)) == post_id:
			return p
	return {}


## --- helpers ------------------------------------------------------------------

static func _key_for(unit_id: int) -> String:
	# Jeremy 2026-10-06: ASSFACE is a phone-only entity — his pseudo-id
	# maps to his thread key so every block/contact API resolves correctly.
	if unit_id == SimAssface.UID:
		return SimAssface.KEY
	# Jeremy 2026-10-11: MR SMART BITCH — same phone-only pattern.
	if unit_id == SimSmartBitch.UID:
		return SimSmartBitch.KEY
	return "u%d" % unit_id


func _unit_for_key(key: String) -> Dictionary:
	# Jeremy 2026-10-06: ASSFACE pseudo-unit (phone-only, no world unit).
	if key == SimAssface.KEY:
		return _assface_unit()
	# Jeremy 2026-10-11: MR SMART BITCH pseudo-unit (phone-only).
	if key == SimSmartBitch.KEY:
		return _smartbitch_unit()
	if not key.begins_with("u"):
		return {}
	return _gs.get_unit(int(key.trim_prefix("u")))


## ASSFACE pseudo-unit dict (shared by thread header, rows, engine).
func _assface_unit() -> Dictionary:
	var az = _gs.get("assface")
	if az != null:
		return az.pseudo_unit()
	return SimAssface.new(null).pseudo_unit()


## NPC affinity toward the ruler, for the thread-header relationship meter.
## HTML parity: msgrAff54 / _affScore / _affTier — score -100..100, tier
## hostile | cold | neutral | warm | devoted. Blocked or at war reads as
## hostile; fond_ruler (mood >= 60) reads at least warm, like a friend.
## Returns {score: float, tier: String, mood_word: String}.
func affinity_for(unit: Dictionary) -> Dictionary:
	var uid := int(unit.get("id", 0))
	if is_blocked(uid):
		return {"score": -100.0, "tier": "hostile", "mood_word": "Furious"}
	var fac := String(unit.get("faction", ""))
	if fac != "" and fac != _gs.player_faction and _gs.diplomacy != null:
		if _gs.diplomacy.relation_state(_gs.player_faction, fac) == "war":
			return {"score": -100.0, "tier": "hostile", "mood_word": "Furious"}
	var score := 0.0
	if conversation != null:
		score = conversation.ruler_mood(uid)
	score = clampf(score, -100.0, 100.0)
	var tier := "neutral"
	if score <= -60.0:
		tier = "hostile"
	elif score <= -20.0:
		tier = "cold"
	elif score >= 75.0:
		tier = "devoted"
	elif score >= 35.0:
		tier = "warm"
	# Mood subtitle word (HTML rulerMoodWord, text-only — no emoji in UI).
	var mood_word := "Wary"
	if score >= 60.0:
		mood_word = "Adoring"
	elif score >= 25.0:
		mood_word = "Pleased"
	elif score <= -40.0:
		mood_word = "Furious"
	elif score <= -10.0:
		mood_word = "Sour"
	return {"score": score, "tier": tier, "mood_word": mood_word}


func _town_name_of(u: Dictionary) -> String:
	var tid: int = int(u.get("town_id", -1))
	var town: Dictionary = _gs.towns.get(tid, {})
	return String(town.get("name", ""))


## --- save -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	state = {
		"sort": String(data.get("sort", "latest")),
		"added": (data.get("added", []) as Array).duplicate(),
		"threads": (data.get("threads", {}) as Dictionary).duplicate(true),
		"posts": (data.get("posts", []) as Array).duplicate(true),
		"post_seq": int(data.get("post_seq", 1)),
		"blocked": (data.get("blocked", {}) as Dictionary).duplicate(true),
	}
