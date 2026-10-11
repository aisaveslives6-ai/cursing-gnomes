class_name SimBackchannel
extends RefCounted

## Cursing Gnomes — The Backchannel (HTML fix79 port, 2026-10-05).
##
## Ports "Candidate21: The Backchannel" (fix79 index.html ~lines 76140-76661):
## AI rulers trade private letters off-screen. Each letter shifts a pairwise
## affinity matrix (-100..100); warm pairs climb the diplomacy ladder (neutral
## -> trade pact -> alliance), cold pairs slide down; rarely, letters talk a
## real war down to white peace or talk a frigid pair up into war. The player
## never sees the letters themselves: the only surfaces are Gazette stories
## (<=1/day) and gossip lines rulers can drop into conversation.
##
## All state is plain JSON-serializable (aff/log/day/flags/throttles).
## The daily tick is idempotent and cheap (a few RNG rolls, no per-frame work).
##
## Improvements over HTML:
##  - Undead voice added (HTML only wrote lines for 4 races; Godot has 5).
##  - Player-topic lines use the real player ruler's name ({P}) instead of
##    hardcoded "human king" — the player can be any faction.
##  - Diplomacy changes go through Godot's REAL hooks (activate_trade,
##    form_alliance, break_treaty, declare_war, make_peace) instead of raw
##    matrix writes, so trade routes, truces, morale and signals all behave.
##  - Player-involved relation shifts become Royal Court petitions
##    (Approve/Deny on the phone); player-involved wars/peaces become
##    strategic proposals — the backchannel never moves the player's
##    pieces without consent (faction sovereignty).
##  - Notable gossip also lands in each ruler's memory, so it colors their
##    Messenger conversations with the player naturally.
##  - Same-court weighting kept for future multi-ruler support; Godot
##    currently has one leader per faction, so it is dormant, not dead.

const KIND_COMPLIMENT := "compliment"
const KIND_TRADE := "trade"
const KIND_TREATY := "treaty"
const KIND_INSULT := "insult"
const KIND_SCHEME := "scheme"
const KIND_WAR := "war"
const KIND_GOSSIP := "gossip"
const KIND_PLAYER := "player"

## HTML-verbatim: how each letter kind moves affinity.
const VALENCE := {
	"compliment": 1, "trade": 1, "treaty": 1,
	"insult": -1, "scheme": -1, "war": -1,
	"gossip": 0, "player": 0,
}

## HTML-verbatim gossip phrasing per letter kind.
const KIND_PHRASE := {
	"compliment": "nothing but honeyed words, the sickening pair",
	"trade": "haggling like fishwives over tariffs",
	"treaty": "treaty-talk, all seals and ceremony",
	"insult": "pure poison, every line",
	"scheme": "scheming — I didn't catch against whom",
	"war": "war-talk. Grim stuff",
	"gossip": "court gossip, the usual rot",
	"player": "whispering about YOU, if you can believe it",
}

const WARM_AT := 60.0        # HTML-verbatim affinity thresholds
const COLD_AT := -60.0
const LOG_CAP := 40          # HTML-verbatim: letter log cap
const DRAMATIC_CHANCE := 0.05  # HTML-verbatim: rare war up/down per day
const TRADE_PACT_CHANCE := 0.35  # HTML-verbatim ladder odds
const ALLIANCE_CHANCE := 0.30
const COOL_CHANCE := 0.30
const DISSOLVE_CHANCE := 0.30
const GOLD_GRANT := 120      # HTML-verbatim: addRes(fa, 120, ...) on new pact

var _gs = null               # GameState (untyped: headless-test friendly)
var _bus = null
var _court = null            # SimRoyalCourt — injected by World (null in tests)
var _rng := RandomNumberGenerator.new()

var _aff: Dictionary = {}    # pair_key -> float (-100..100)
var _log: Array = []         # [{day, a, b, kind, msgs}] newest last, cap 40
var _day := 0
var _flags: Dictionary = {}  # pair_key -> {"warm": bool, "cold": bool}
var _story_day := -1         # Gazette throttle: at most one story/day
var _mention_day := -1       # gossip-line throttle: at most one/day
var _td_day := -1            # dramatic-event throttle: at most one/day
var _pending: Dictionary = {}  # court petition id -> decision record
var _petition_seq := 1


func _init(game_state) -> void:
	_gs = game_state
	_bus = game_state.get("bus") if game_state != null else null
	_rng.randomize()
	if _bus != null:
		if _bus.has_signal("day_changed"):
			_bus.day_changed.connect(_on_day)
		if _bus.has_signal("petition_decided"):
			_bus.petition_decided.connect(_on_petition_decided)


## --- public API ---------------------------------------------------------------

## Faction voices for private letters (HTML-verbatim for gnome/human/elf/ogre;
## undead voice is new — HTML had no undead lines). Slots: {X} recipient name,
## {S} speaker name, {T} third-faction name, {P} the player's ruler name.
const BC_LINES := {
	"gnomes": {
		"compliment": [
			"Dear {X}, your letter didn't make me want to vomit. That's basically a love poem from me.",
			"{X}, I've read your letter twice and only insulted it once. Progress! You're my favorite pen-pal, you magnificent bastard."],
		"insult": [
			"{X}, I wiped my arse with your last letter and it came back cleaner. Kindly fuck off.",
			"{X}, your opinions are like your breath — stale, and best kept at a distance."],
		"trade": [
			"{X}, I've got mushrooms and grudges to sell. Name a price before I drink the profits myself.",
			"{X}, my cellar's full of the good rotgut. Trade you a barrel for whatever's rusting in your yard."],
		"treaty": [
			"{X}, fine. I'll sign your poxy little treaty. Bring your own quill — mine's chewed.",
			"{X}, a treaty it is. If you cross me I'll eat the parchment in front of you."],
		"war": [
			"{X}, if your lads cross our border again I'll shove a boot so far up— well. You know the drill.",
			"{X}, this war is costing me good drinking money. Call off your idiots before I call off mine."],
		"scheme": [
			"{X}, between you and me, the {T} lot are ripe for a kicking. Split the loot?",
			"{X}, the {T} throne wobbles. One good shove and it's ours. You in, you sneaky bastard?"],
		"gossip": [
			"{X}, word is the human's hall is held together with spit and prayers. Pass it on.",
			"{X}, the elf court bathes in flower water. FLOWER WATER. I shit you not."],
		"player": [
			"{X}, {P} keeps sniffing around my borders. If they write you, charge them double.",
			"{X}, {P} asked about you. I said you were tolerable. Don't make a liar of me."]},
	"humans": {
		"compliment": [
			"{X} — your last letter was, against all odds, sensible. I've framed it.",
			"{X}, I disagree with nearly everything you wrote, and yet I enjoyed reading it. Curious."],
		"insult": [
			"{X}, your strategic thinking remains as impressive as ever. Which is to say: not.",
			"{X}, I've filed your letter under 'entertaining fiction'. Do try harder."],
		"trade": [
			"{X}, grain prices are up. I'd like a standing arrangement, assuming your arithmetic holds.",
			"{X}, my merchants report your roads are passable. Shall we make that profitable for us both?"],
		"treaty": [
			"{X}, I've drafted terms. Twelve pages. Sign the last one; the rest is decoration.",
			"{X}, a treaty benefits us both, which is precisely why I suspect a trap. Sign anyway."],
		"war": [
			"{X}, let us be candid: this war is expensive for us both. My ledger weeps.",
			"{X}, our generals grow bored and my coffers grow thin. There must be a cheaper way to hate each other."],
		"scheme": [
			"{X}, the {T} throne sits empty most nights. Just an observation. A profitable one.",
			"{X}, a quiet word: the {T} coffers are full and their guard is thin. Purely academic, of course."],
		"gossip": [
			"{X}, rumor: the ogres tried to tax a beehive. The beehive won.",
			"{X}, the gnome court is aging its ale in old boots. I have it on good authority."],
		"player": [
			"{X}, {P} has been cozying up to my rivals. Watch your own back, as always.",
			"{X}, {P} writes everyone these days. I suggest reading twice and answering once."]},
	"elves": {
		"compliment": [
			"Dearest {X}, your words bloom like night-garden flowers. I read your letter thrice. 🌸",
			"{X}, darling, your letter quite made my morning. The dryads are jealous of your prose. ✨"],
		"insult": [
			"{X}, darling, your penmanship is the only sharp thing about you. 💅",
			"{X}, sweetling, even the thorns in my garden have more point than your arguments. 🌹"],
		"trade": [
			"{X}, sweetling — silk for spices? The caravans leave at moonrise, be quick. ✨",
			"{X}, I have moonwine and star-silk, and a weakness for your honey-cakes. Trade? 🌙"],
		"treaty": [
			"{X}, a treaty sealed with petals and promises. Try not to trample it, dear. 🌷",
			"{X}, let our courts be entwined like ivy. Ivy, mind you — not kudzu. 🌿"],
		"war": [
			"{X}, must our spears do the talking? Mine are so much prettier than yours. 🌙",
			"{X}, war is so unbecoming. My battle-gowns are simply wasted on it. Call a truce, darling?"],
		"scheme": [
			"{X}, between us flowers — the {T} court's roots are rotting. Shall we prune? 🌿",
			"{X}, the {T} throne would look better with our vines on it, don't you think? Purely decorative. 🌸"],
		"gossip": [
			"{X}, you didn't hear it from me, but the gnome court bathes once a season. Once. 🌸",
			"{X}, darling, the ogre king wept at a butterfly yesterday. I found it adorable. Don't tell him. 🦋"],
		"player": [
			"{X}, {P} asked after you. I said only kind things. Mostly. 🌙",
			"{X}, {P} is collecting allies like pressed flowers. Stay stemmy, dear. 🌷"]},
	"ogres": {
		"compliment": [
			"{X}! YOUR LETTER GOOD! ME READ IT TO PIG! PIG AGREE! YOU SMART! (pig smart too)",
			"{X}! ME LIKE YOU! YOU NOT DUMB LIKE OTHER KINGS! YOU DUMB LIKE ME! BEST KIND!"],
		"insult": [
			"{X} SMELL LIKE OLD BOOT! ME TELL BOOT! BOOT SAY SORRY FOR YOU!",
			"{X}! YOUR HEAD EMPTY LIKE DRUM! ME PLAY DRUM ON IT! BAD MUSIC!"],
		"trade": [
			"{X}! YOU WANT ROCKS? ME HAVE ROCKS! BIG ROCKS! TRADE FOR MEAT! MEAT GOOD!",
			"{X}! ME TRADE YOU SHINY STICK FOR FOOD! STICK VERY SHINY! ME POLISH WITH TONGUE!"],
		"treaty": [
			"{X}! ME SIGN TREATY! ME MAKE X WITH FINGER PAINT! VERY OFFICIAL!",
			"{X}! WE FRIENDS NOW! ME NOT SMASH YOUR TOWN! (me smash other town. okay?)"],
		"war": [
			"{X}! YOUR ARMY SMALL! ME ARMY BIG! ME NOT WANT SMASH BUT ME WILL! ...ME WANT SMASH LITTLE.",
			"{X}! WAR MAKE ME HUNGRY! YOU STOP WAR, ME SHARE SNACKS! SNACKS = WHOLE PIG!"],
		"scheme": [
			"{X}! ME AND YOU BONK {T}! THEY NOT EXPECT! (me tell everyone. still not expect.)",
			"{X}! {T} KING SIT ON THRONE! ME SIT ON {T} KING! NEW PLAN! YOU LAUGH!"],
		"gossip": [
			"{X}! ME HEAR ELF EAT FLOWER! WHY EAT PRETTY?! ME CONFUSE! ME STILL LIKE ELF!",
			"{X}! GNOME KING FART IN COUNCIL! ME HEAR FROM WALL! WALL TELL ME!"],
		"player": [
			"{X}! {P} FUNNY! ME LIKE THEM! ME NOT SMASH THEM! (yet.)",
			"{X}! {P} GIVE ME HAT! HAT TOO SMALL! ME STILL WEAR! ME LOOK GOOD!"]},
	"undead": {
		"compliment": [
			"Dear {X}, your correspondence pleases me. I have kept it. I keep everything. Forever.",
			"{X}, among the living you are the least tedious. From me, that is a high honor."],
		"insult": [
			"{X}, your letter was compost before it arrived. I buried it with the others.",
			"{X}, I have outlived better minds than yours. I shall outlive yours too."],
		"trade": [
			"{X}, the dead need no grain, but my servants do. Name your price, quickly.",
			"{X}, I offer grave-iron and old gold for flesh and timber. The living always need timber."],
		"treaty": [
			"{X}, I shall sign. Ink fades; oaths sworn to me do not.",
			"{X}, a treaty. Even death honors paperwork."],
		"war": [
			"{X}, you mistake my patience for weakness. The grave is patient too.",
			"{X}, war? I have an endless supply of soldiers. You do not."],
		"scheme": [
			"{X}, the {T} throne will be empty soon. It is only a matter of... waiting. Together?",
			"{X}, between us: the {T} court fears death. I AM death. Advantage: ours."],
		"gossip": [
			"{X}, the living courts gossip that I sleep in a coffin. I sleep in a BED. The coffin is for guests.",
			"{X}, word is the gnome king pickles his own feet. Even I find that excessive."],
		"player": [
			"{X}, {P} watches the borders with living eyes. Remind them the dead are patient.",
			"{X}, the one they call {P} asked after you. I said nothing. Silence is also an answer."]},
}


## --- state helpers ------------------------------------------------------------


## HTML-verbatim pair key (order-independent).
static func pair_key(ka: String, kb: String) -> String:
	return ka + "|" + kb if ka < kb else kb + "|" + ka


## Affinity getter: -100..100, 0 when the pair never exchanged letters.
func affinity(ka: String, kb: String) -> float:
	return float(_aff.get(pair_key(ka, kb), 0.0))


func _day_number() -> int:
	if _gs != null and _gs.get("day_number") != null:
		return int(_gs.day_number)
	return 1


func _player_faction() -> String:
	if _gs != null and _gs.get("player_faction") != null:
		return String(_gs.player_faction)
	return ""


func _involves_player(fa: String, fb: String) -> bool:
	var pf := _player_faction()
	return pf != "" and (fa == pf or fb == pf)


func _dip():
	if _gs == null:
		return null
	return _gs.get("diplomacy")


func _leaders():
	if _gs == null:
		return null
	return _gs.get("faction_leaders")


func _fname(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


## --- rulers -------------------------------------------------------------------


## Leader records for every active faction: key, name, faction, and the
## personality numbers the letter engine weights on (dip/aggro/weird, 0..100,
## derived from the faction soul via SimDiplomacy.faction_traits).
## The player's own faction has no AI leader (durable design: the player IS
## the leader) — it gets a synthetic ruler record under the player's own
## ruler name so the backchannel still seats that faction at the table:
## {P} name lines, court petitions, dramatic proposals, and mention names.
func _rulers() -> Array:
	var out: Array = []
	if _gs == null:
		return out
	var fl = _leaders()
	var dip = _dip()
	var factions: Array = []
	if _gs.get("active_factions") != null:
		for f in _gs.active_factions:
			factions.append(String(f))
	var pf := _player_faction()
	for f in factions:
		var rec: Dictionary = {}
		if fl != null:
			rec = fl.leader_of(f)
		if rec.is_empty():
			if f == pf and pf != "":
				rec = _player_ruler_record(f)
			else:
				continue
		var tr: Dictionary = {}
		if dip != null:
			tr = dip.faction_traits(f)
		out.append({
			"key": SimFactionLeaders.key_for(f),
			"name": String(rec.get("name", f)),
			"faction": f,
			"dip": float(tr.get("diplomacy_value", 0.5)) * 100.0,
			"aggro": float(tr.get("aggro", 0.5)) * 100.0,
			"weird": float(tr.get("humor_value", 0.5)) * 100.0,
		})
	return out


## Synthetic ruler record for the player's faction: the player themself.
## Neutral personality numbers — the player has no AI temperament; the
## letter engine weights on these, so neutral keeps the weighting honest.
## Name is the player's chosen ruler name verbatim (never trimmed); when no
## name was chosen yet, falls back to the same "the player-king" the {P}
## slot uses.
func _player_ruler_record(faction: String) -> Dictionary:
	var nm := ""
	if _gs != null and _gs.get("ruler_name") != null:
		nm = String(_gs.ruler_name)
	if nm == "":
		nm = "the player-king"
	return {
		"key": SimFactionLeaders.key_for(faction),
		"name": nm,
		"faction": faction,
		"player": true,
	}


func _ruler_by_key(rulers: Array, key: String) -> Dictionary:
	for r in rulers:
		if String(r.get("key", "")) == key:
			return r
	return {}


func _ruler_of_faction(rulers: Array, faction: String) -> Dictionary:
	for r in rulers:
		if String(r.get("faction", "")) == faction:
			return r
	return {}


func _ruler_name(key: String) -> String:
	var r := _ruler_by_key(_rulers(), key)
	if r.is_empty():
		return key
	return String(r.get("name", key))


## --- pair picking -------------------------------------------------------------


## HTML-verbatim: recent pairs (last 2 days) are excluded; compatible
## personalities talk more; warm pairs write more; shared foes bond.
func _pick_pair(rulers: Array, day: int) -> Array:
	var recent: Dictionary = {}
	for e in _log:
		var ed: Dictionary = e
		if int(ed.get("day", -999)) >= day - 2:
			recent[pair_key(String(ed.get("a", "")), String(ed.get("b", "")))] = true
	var cands := _collect_pairs(rulers, recent, true)
	if cands.is_empty():
		cands = _collect_pairs(rulers, recent, false)  # relax recency, don't stall
	if cands.is_empty():
		return []
	var total := 0.0
	for c in cands:
		total += float(c[2])
	if total <= 0.0:
		return []
	var roll := _rng.randf() * total
	for c in cands:
		roll -= float(c[2])
		if roll <= 0.0:
			return [c[0], c[1]]
	var last: Array = cands[cands.size() - 1]
	return [last[0], last[1]]


func _collect_pairs(rulers: Array, recent: Dictionary, skip_recent: bool) -> Array:
	var out: Array = []
	for i in range(rulers.size()):
		for j in range(i + 1, rulers.size()):
			var a: Dictionary = rulers[i]
			var b: Dictionary = rulers[j]
			if skip_recent and recent.has(pair_key(String(a["key"]), String(b["key"]))):
				continue
			var w := _pair_weight(a, b)
			if w > 0.0:
				out.append([a, b, w])
	return out


func _pair_weight(a: Dictionary, b: Dictionary) -> float:
	var w := 1.0
	if String(a["faction"]) == String(b["faction"]):
		# Same court: like minds (dormant in Godot — one leader per faction).
		w += 10.0 - absf(float(a["aggro"]) - float(b["aggro"])) / 10.0
	else:
		w += (float(a["dip"]) + float(b["dip"])) / 25.0   # diplomats talk
	w += affinity(String(a["key"]), String(b["key"])) / 25.0  # warm pairs write
	w += float(_shared_enemies(String(a["faction"]), String(b["faction"]))) * 3.0
	return w


func _shared_enemies(fa: String, fb: String) -> int:
	var dip = _dip()
	if dip == null:
		return 0
	var n := 0
	if _gs == null or _gs.get("active_factions") == null:
		return 0
	for f in _gs.active_factions:
		var fs := String(f)
		if fs == fa or fs == fb:
			continue
		if String(dip.relation_state(fa, fs)) == "war" \
				and String(dip.relation_state(fb, fs)) == "war":
			n += 1
	return n


func _war_pairs() -> Array:
	var dip = _dip()
	var out: Array = []
	if dip == null or _gs == null or _gs.get("active_factions") == null:
		return out
	var factions: Array = []
	for f in _gs.active_factions:
		factions.append(String(f))
	for i in range(factions.size()):
		for j in range(i + 1, factions.size()):
			if String(dip.relation_state(factions[i], factions[j])) == "war":
				out.append([factions[i], factions[j]])
	return out


## --- topics -------------------------------------------------------------------


## HTML-verbatim: pick a letter topic grounded in real game state.
func _topic_for(a: Dictionary, b: Dictionary) -> Dictionary:
	var fa := String(a["faction"])
	var fb := String(b["faction"])
	var dip = _dip()
	var wars := _war_pairs()
	var fa_fb_war := false
	var a_war_other := ""
	var b_war_other := ""
	for p in wars:
		var p0 := String(p[0])
		var p1 := String(p[1])
		if (p0 == fa and p1 == fb) or (p0 == fb and p1 == fa):
			fa_fb_war = true
		else:
			if p0 == fa or p1 == fa:
				a_war_other = p1 if p0 == fa else p0
			if p0 == fb or p1 == fb:
				b_war_other = p1 if p0 == fb else p0
	var rel := ""
	if dip != null:
		rel = String(dip.relation_state(fa, fb))
	var trade_or_allied := rel == "allied" \
		or (dip != null and bool(dip.has_trade_deal(fa, fb)))
	# Player entanglement: the pair's courts care about the player's faction.
	var pf := _player_faction()
	var player_tied := false
	var fl = _leaders()
	if pf != "" and fl != null:
		for fx in [fa, fb]:
			if absf(float(fl.opinion_of(fx, pf))) > 0.01 \
					or String(fl.mood_toward(fx, pf)) != "neutral":
				player_tied = true
				break
	var player_war_either := false
	if dip != null and pf != "":
		player_war_either = String(dip.relation_state(pf, fa)) == "war" \
			or String(dip.relation_state(pf, fb)) == "war"
	var topics: Array = []
	_add_topic(topics, KIND_WAR, 10.0 if fa_fb_war else 0.0)
	_add_topic(topics, KIND_WAR,
		3.0 if (a_war_other != "" or b_war_other != "") else 0.0,
		a_war_other if a_war_other != "" else b_war_other)
	_add_topic(topics, KIND_TREATY, 5.0 if trade_or_allied else 0.0)
	_add_topic(topics, KIND_TRADE, (float(a["dip"]) + float(b["dip"])) / 60.0)
	_add_topic(topics, KIND_PLAYER, 6.0 if player_tied
		else (4.0 if player_war_either else 0.5))
	_add_topic(topics, KIND_COMPLIMENT, (float(a["dip"]) + float(b["dip"])) / 80.0)
	_add_topic(topics, KIND_INSULT, (float(a["aggro"]) + float(b["aggro"])) / 100.0)
	_add_topic(topics, KIND_SCHEME, maxf(float(a["weird"]), float(b["weird"])) / 90.0)
	_add_topic(topics, KIND_GOSSIP, 1.2)
	var total := 0.0
	for t in topics:
		total += float(t["w"])
	var pick: Dictionary = {"kind": KIND_GOSSIP, "third": ""}
	if total > 0.0:
		var roll := _rng.randf() * total
		pick = topics[0]
		for t in topics:
			roll -= float(t["w"])
			if roll <= 0.0:
				pick = t
				break
	if String(pick["kind"]) == KIND_SCHEME and String(pick["third"]) == "":
		pick["third"] = _random_third(fa, fb)
	return pick


func _add_topic(topics: Array, kind: String, w: float, third: String = "") -> void:
	if w > 0.0:
		topics.append({"kind": kind, "w": w, "third": third})


func _random_third(fa: String, fb: String) -> String:
	var pool: Array = []
	if _gs != null and _gs.get("active_factions") != null:
		for f in _gs.active_factions:
			var fs := String(f)
			if fs != fa and fs != fb:
				pool.append(fs)
	if pool.is_empty():
		return fa
	return String(pool[_rng.randi_range(0, pool.size() - 1)])


## --- letters ------------------------------------------------------------------


## HTML-verbatim line render with {X}/{S}/{T}/{P} slots.
func _line(kind: String, speaker: Dictionary, recip: Dictionary, third: String) -> String:
	var set: Array = []
	var voices: Dictionary = BC_LINES.get(String(speaker["faction"]), {})
	if voices.has(kind):
		set = voices[kind]
	if set.is_empty():
		set = BC_LINES["gnomes"]["gossip"]
	var t := String(set[_rng.randi_range(0, set.size() - 1)])
	var tf := third if third != "" else _random_third(
		String(speaker["faction"]), String(recip["faction"]))
	var player_name := _ruler_name(SimFactionLeaders.key_for(_player_faction())) \
		if _player_faction() != "" else "the player-king"
	return t.replace("{X}", String(recip["name"])) \
		.replace("{S}", String(speaker["name"])) \
		.replace("{T}", _fname(tf)) \
		.replace("{P}", player_name)


## A taught word from the Living Lexicon, dropped naturally.
## Guarded exactly like HTML (the lexicon block may not exist).
func _lexicon_word() -> Dictionary:
	if _gs == null:
		return {}
	var lx = _gs.get("lexicon")
	if lx == null or not lx.has_method("taught_words"):
		return {}
	var words: Array = lx.taught_words()
	if words.is_empty():
		return {}
	var w: Dictionary = words[_rng.randi_range(0, words.size() - 1)]
	return w


## One background exchange: pick a pair, pick a real-state topic, write 1-3
## faction-voiced letters, shift affinity, log it, feed the diplomacy sim.
func _exchange(rulers: Array, day: int) -> void:
	var pair := _pick_pair(rulers, day)
	if pair.size() < 2:
		return
	var a: Dictionary = pair[0]
	var b: Dictionary = pair[1]
	var pk := pair_key(String(a["key"]), String(b["key"]))
	var topic := _topic_for(a, b)
	var kind := String(topic["kind"])
	var old_aff := affinity(String(a["key"]), String(b["key"]))
	var v := int(VALENCE.get(kind, 0))
	var mag: int
	var delta: float
	if v == 0:
		mag = 1 + _rng.randi_range(0, 3)
		delta = -mag if _rng.randf() < 0.5 else mag
	else:
		mag = 3 + _rng.randi_range(0, 9)
		delta = float(v * mag)
	var new_aff := clampf(old_aff + delta, -100.0, 100.0)
	_aff[pk] = new_aff
	var msgs: Array = []
	var n_msgs := 1 + (1 if _rng.randf() < 0.5 else 0) + (1 if _rng.randf() < 0.2 else 0)
	for m in range(n_msgs):
		var spk: Dictionary = a if m % 2 == 0 else b
		var rcp: Dictionary = b if m % 2 == 0 else a
		msgs.append(_line(kind, spk, rcp, String(topic["third"])))
	if _rng.randf() < 0.25:
		var lx := _lexicon_word()
		if not lx.is_empty():
			msgs.append("P.S. — the scholars taught me a new word: '%s'. It means %s, says %s. I've said it nine times today." % [
				String(lx.get("word", "?")), String(lx.get("meaning", "something")),
				String(lx.get("taught_by", "someone"))])
	_push_log(day, String(a["key"]), String(b["key"]), kind, msgs)
	_remember_gossip(a, b, kind)
	_threshold_story(rulers, day, pk, a, b, old_aff, new_aff)
	_diplomacy_feed(a, b, old_aff, new_aff)


func _push_log(day: int, a_key: String, b_key: String, kind: String, msgs: Array) -> void:
	_log.append({"day": day, "a": a_key, "b": b_key, "kind": kind,
		"msgs": msgs})
	while _log.size() > LOG_CAP:
		_log.pop_front()


## Notable gossip lands in each ruler's memory so it colors their
## conversations with the player (improvement over HTML's log-only path).
func _remember_gossip(a: Dictionary, b: Dictionary, kind: String) -> void:
	if kind != KIND_GOSSIP and kind != KIND_SCHEME and kind != KIND_PLAYER:
		return
	if _rng.randf() >= 0.30:
		return
	var fl = _leaders()
	if fl == null:
		return
	var ph := String(KIND_PHRASE.get(kind, "letters, letters, letters"))
	fl.remember(String(a["faction"]), "gossip", String(b["name"]),
		"Word in the courts: %s and %s have been exchanging letters — %s." % [
			String(a["name"]), String(b["name"]), ph], 0.15)
	fl.remember(String(b["faction"]), "gossip", String(a["name"]),
		"Word in the courts: %s and %s have been exchanging letters — %s." % [
			String(a["name"]), String(b["name"]), ph], 0.15)


## --- diplomacy feed -----------------------------------------------------------


## HTML-verbatim ladder odds; Godot improvements: real diplomacy hooks, and
## any pair touching the player faction becomes a Royal Court petition
## (sovereignty — the backchannel never moves the player's pieces unasked).
func _diplomacy_feed(a: Dictionary, b: Dictionary, old_aff: float, new_aff: float) -> void:
	if String(a["faction"]) == String(b["faction"]):
		return
	var dip = _dip()
	if dip == null:
		return
	var fa := String(a["faction"])
	var fb := String(b["faction"])
	var rel := String(dip.relation_state(fa, fb))
	var trade_active := bool(dip.has_trade_deal(fa, fb))
	var player_pair := _involves_player(fa, fb)
	if new_aff > WARM_AT and new_aff > old_aff:
		if rel == "neutral" and not trade_active and _rng.randf() < TRADE_PACT_CHANCE:
			if player_pair:
				_court_petition("trade", a, b)
			else:
				dip.activate_trade(fa, fb, 3)
				_grant_gold(fa, GOLD_GRANT)
				_grant_gold(fb, GOLD_GRANT)
				_story("TRADE PACT SIGNED",
					"After an exchange of letters, %s of the %s has warmed to %s of the %s — a trade pact is signed, and tariffs flow both ways." % [
						String(a["name"]), _fname(fa), String(b["name"]), _fname(fb)],
					"🤝", false)
		elif trade_active and rel != "allied" and _rng.randf() < ALLIANCE_CHANCE:
			if player_pair:
				_court_petition("ally", a, b)
			else:
				dip.form_alliance(fa, fb)
				_story("ALLIANCE SEALED",
					"After an exchange of letters, %s has warmed to %s — their courts now stand as allies." % [
						String(a["name"]), String(b["name"])],
					"🛡️", false)
	elif new_aff < COLD_AT and new_aff < old_aff:
		if rel == "allied" and _rng.randf() < COOL_CHANCE:
			if player_pair:
				_court_petition("cool", a, b)
			else:
				dip.break_treaty(fa, fb)
				_story("ALLIANCE COOLS",
					"Poisoned letters between %s and %s have cooled their alliance to a mere trade pact." % [
						String(a["name"]), String(b["name"])],
					"📉", false)
		elif trade_active and rel != "allied" and _rng.randf() < DISSOLVE_CHANCE:
			if player_pair:
				_court_petition("dissolve", a, b)
			else:
				dip.break_treaty(fa, fb)
				_story("TRADE PACT DISSOLVED",
					"After a bitter exchange of letters, %s has soured on %s — their trade pact is dissolved." % [
						String(a["name"]), String(b["name"])],
					"📉", false)


func _grant_gold(faction: String, amount: int) -> void:
	if _gs == null:
		return
	var res = _gs.get("resources")
	if res != null and res.has_method("add_resource"):
		res.add_resource(faction, "gold", float(amount))


## --- dramatic events ----------------------------------------------------------


## HTML-verbatim rare event (<=5%/day, once/day): a real war gets talked down
## to white peace, or a frigid pair talks a war up. Through the real hooks
## (declare_war / make_peace — trade routes, truces, morale, signals).
## Player-involved events become strategic proposals instead of auto-firing.
func _dramatic_event(rulers: Array, day: int) -> void:
	if _td_day == day:
		return
	var dip = _dip()
	if dip == null:
		return
	var wars := _war_pairs()
	var cold: Array = []
	for k in _aff.keys():
		if float(_aff[k]) < COLD_AT:
			cold.append(String(k))
	var do_down := wars.size() > 0 and (_rng.randf() < 0.5 or cold.is_empty())
	if do_down:
		var p: Array = wars[_rng.randi_range(0, wars.size() - 1)]
		var ra := _ruler_of_faction(rulers, String(p[0]))
		var rb := _ruler_of_faction(rulers, String(p[1]))
		if ra.is_empty() or rb.is_empty():
			return
		_td_day = day
		if _involves_player(String(p[0]), String(p[1])):
			_propose_peace(ra, rb)
			return
		_story("WHITE PEACE",
			"Letters, not lances: %s and %s have talked their war down to a white peace between the %s and the %s. The borders go quiet." % [
				String(ra["name"]), String(rb["name"]), _fname(String(p[0])), _fname(String(p[1]))],
			"🕊️", true)
		dip.make_peace(String(p[0]), String(p[1]))
		_push_log(day, String(ra["key"]), String(rb["key"]), KIND_TREATY,
			["Peace, sealed with ink. (The full correspondence stays private, thank the stars.)"])
	elif not cold.is_empty():
		var coldest := String(cold[0])
		var cv := float(_aff[coldest])
		for k in cold:
			var ks := String(k)
			if float(_aff[ks]) < cv:
				coldest = ks
				cv = float(_aff[ks])
		var parts := coldest.split("|")
		if parts.size() < 2:
			return
		var ra2 := _ruler_by_key(rulers, String(parts[0]))
		var rb2 := _ruler_by_key(rulers, String(parts[1]))
		if ra2.is_empty() or rb2.is_empty():
			return
		var fa2 := String(ra2["faction"])
		var fb2 := String(rb2["faction"])
		if fa2 == fb2:
			return
		if String(dip.relation_state(fa2, fb2)) != "neutral":
			return
		_td_day = day
		if _involves_player(fa2, fb2):
			_propose_war(ra2, rb2)
			return
		var res: Dictionary = dip.declare_war(fa2, fb2,
			"Letters curdled into threats between the courts")
		if not bool(res.get("ok", false)):
			return
		_story("WAR OF LETTERS",
			"Letters curdled into threats between %s and %s — the %s and the %s are at war." % [
				String(ra2["name"]), String(rb2["name"]), _fname(fa2), _fname(fb2)],
			"⚔️", true)
		_push_log(day, String(ra2["key"]), String(rb2["key"]), KIND_WAR,
			["The last letter was a threat. The next one will be an arrow."])


## --- threshold stories --------------------------------------------------------


func _threshold_story(rulers: Array, day: int, pk: String, a: Dictionary,
		b: Dictionary, old_aff: float, new_aff: float) -> void:
	var fl: Dictionary = _flags.get(pk, {})
	if fl.is_empty():
		fl = {"warm": false, "cold": false}
		_flags[pk] = fl
	var n := _letters_this_week(day, pk)
	var nn := "1 letter" if n <= 1 else "%d letters" % n
	if new_aff >= WARM_AT and old_aff < WARM_AT and not bool(fl["warm"]):
		fl["warm"] = true
		_story("ROYAL CORRESPONDENCE",
			"Sources say %s and %s exchanged %s this week — their courts are thick as thieves." % [
				String(a["name"]), String(b["name"]), nn],
			"💌", false)
	elif new_aff <= COLD_AT and old_aff > COLD_AT and not bool(fl["cold"]):
		fl["cold"] = true
		_story("ROYAL CORRESPONDENCE",
			"Sources say %s and %s exchanged %s this week — every one of them poison." % [
				String(a["name"]), String(b["name"]), nn],
			"💌", false)
	if new_aff > COLD_AT and new_aff < WARM_AT:
		fl["warm"] = false
		fl["cold"] = false


func _letters_this_week(day: int, pk: String) -> int:
	var n := 0
	for e in _log:
		var ed: Dictionary = e
		if int(ed.get("day", -999)) >= day - 7 \
				and pair_key(String(ed.get("a", "")), String(ed.get("b", ""))) == pk:
			n += 1
	return n


## --- gazette surface ----------------------------------------------------------


## HTML-verbatim: at most ONE backchannel story per game day.
func _story(headline: String, body: String, icon: String, urgent: bool) -> bool:
	if _bus == null:
		return false
	var day := _day_number()
	if _story_day == day:
		return false
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	# icon + urgent ride both paths via extra.
	SimGazette.publish_or_emit(_gs, headline,
		"%s (Day %d)" % [body, day], "court",
		{"icon": icon, "urgent": urgent})
	_story_day = day
	return true


## --- player routing (sovereignty) ----------------------------------------------


## A relation shift touching the player faction becomes a Royal Court
## petition: the crown approves or denies on the phone.
func _court_petition(kind: String, a: Dictionary, b: Dictionary) -> void:
	if _court == null:
		return
	var pf := _player_faction()
	var other: Dictionary = b if String(a["faction"]) == pf else a
	var other_name := String(other["name"])
	var other_f := _fname(String(other["faction"]))
	var title := ""
	var body := ""
	match kind:
		"trade":
			title = "Trade pact proposed"
			body = "After an exchange of letters, %s of the %s proposes a trade pact with your court. Tariffs would flow both ways." % [other_name, other_f]
		"ally":
			title = "Alliance proposed"
			body = "Letters have warmed %s of the %s toward your court — they propose a full alliance. Shared maps, shared markets, shared spears." % [other_name, other_f]
		"cool":
			title = "Alliance cooling"
			body = "Poisoned letters between your court and %s of the %s have soured things. Your advisers ask: let the alliance cool to a trade pact, or smooth it over?" % [other_name, other_f]
		"dissolve":
			title = "Trade pact souring"
			body = "A bitter exchange of letters with %s of the %s has your merchants nervous. Dissolve the trade pact, or hold it together?" % [other_name, other_f]
		_:
			return
	var envoy := {
		"id": 0, "faction": pf,
		"mind": {"gov_role": "royal_envoy", "name": "Royal Envoy"},
	}
	var p: Dictionary = _court.petition(envoy, "bc_" + kind,
		"%s\n\n%s" % [title, body], ["Approve", "Deny"] as Array[String])
	_pending[int(p.get("id", _petition_seq))] = {
		"kind": kind, "fa": String(a["faction"]), "fb": String(b["faction"]),
	}
	_petition_seq += 1


func _on_petition_decided(petition: Dictionary, choice: String) -> void:
	var pid := int(petition.get("id", -1))
	if not _pending.has(pid):
		return
	var d: Dictionary = _pending[pid]
	_pending.erase(pid)
	var yes := "approve" in choice.to_lower() or "allow" in choice.to_lower()
	if yes:
		_apply_court_decision(d)


func _apply_court_decision(d: Dictionary) -> void:
	var dip = _dip()
	if dip == null:
		return
	var fa := String(d.get("fa", ""))
	var fb := String(d.get("fb", ""))
	match String(d.get("kind", "")):
		"trade":
			if String(dip.relation_state(fa, fb)) == "neutral" \
					and not bool(dip.has_trade_deal(fa, fb)):
				dip.activate_trade(fa, fb, 3)
				_grant_gold(fa, GOLD_GRANT)
				_grant_gold(fb, GOLD_GRANT)
		"ally":
			if bool(dip.has_trade_deal(fa, fb)) \
					and String(dip.relation_state(fa, fb)) != "allied":
				dip.form_alliance(fa, fb)
		"cool", "dissolve":
			dip.break_treaty(fa, fb)


## A dramatic war/peace touching the player becomes a strategic proposal
## (the existing Approve/Deny modal), never an auto-fire.
func _propose_war(ra: Dictionary, rb: Dictionary) -> void:
	if _gs == null:
		return
	var pr = _gs.get("proposals")
	if pr == null:
		return
	var pf := _player_faction()
	var other := String(rb["faction"]) if String(ra["faction"]) == pf else String(ra["faction"])
	pr.propose(pf, "declare_war", {
		"target": other,
		"reason": "Letters from %s curdled into threats — your war council demands an answer." % String(rb["name"] if String(ra["faction"]) == pf else ra["name"]),
	})


func _propose_peace(ra: Dictionary, rb: Dictionary) -> void:
	if _gs == null:
		return
	var pr = _gs.get("proposals")
	if pr == null:
		return
	var pf := _player_faction()
	var other := String(rb["faction"]) if String(ra["faction"]) == pf else String(ra["faction"])
	pr.propose(pf, "sue_for_peace", {
		"target": other,
		"reason": "A graceful exchange of letters with %s has opened a path to white peace." % String(rb["name"] if String(ra["faction"]) == pf else ra["name"]),
	})


## --- gossip surface ------------------------------------------------------------


## HTML-verbatim BackchannelMention: a gossip line a ruler can drop into a
## player DM. Returns "" ~70% of the time, at most once per game day.
## Names are always real rulers from real recent exchanges.
func mention(ruler_faction: String) -> String:
	var day := _day_number()
	if _mention_day == day:
		return ""
	if _rng.randf() < 0.70:
		return ""
	var rk := SimFactionLeaders.key_for(ruler_faction)
	var cands: Array = []
	for e in _log:
		var ed: Dictionary = e
		if int(ed.get("day", -999)) >= day - 7 \
				and String(ed.get("a", "")) != rk and String(ed.get("b", "")) != rk:
			cands.append(ed)
	if cands.is_empty():
		return ""
	var pick: Dictionary = cands[_rng.randi_range(0, cands.size() - 1)]
	var na := _ruler_name(String(pick.get("a", "")))
	var nb := _ruler_name(String(pick.get("b", "")))
	var ph := String(KIND_PHRASE.get(String(pick.get("kind", "")), "letters, letters, letters"))
	var lines: Array[String] = [
		"you'll never guess what %s just wrote to %s — %s." % [na, nb, ph],
		"word in the courts: %s and %s have been exchanging letters. %s." % [na, nb, ph],
		"between us — %s's letters to %s lately? %s." % [na, nb, ph],
	]
	_mention_day = day
	return lines[_rng.randi_range(0, lines.size() - 1)]


## --- daily tick ---------------------------------------------------------------


func _on_day(day: int, _is_night: bool) -> void:
	_daily_tick(day)


## HTML-verbatim cadence: 2–4 background exchanges (1 early-game), plus the
## rare dramatic event. Idempotent: once per game day.
func _daily_tick(day: int) -> void:
	if _day == day:
		return
	_day = day
	var rulers := _rulers()
	if rulers.size() < 2:
		return
	var n := 1 if day < 12 else 2 + _rng.randi_range(0, 2)
	if n > 4:
		n = 4
	for k in range(n):
		_exchange(rulers, day)
	if _rng.randf() < DRAMATIC_CHANCE:
		_dramatic_event(rulers, day)


## --- persistence --------------------------------------------------------------


func to_dict() -> Dictionary:
	var log_out: Array = []
	for e in _log:
		var ed: Dictionary = e
		log_out.append({
			"day": int(ed.get("day", 0)), "a": String(ed.get("a", "")),
			"b": String(ed.get("b", "")), "kind": String(ed.get("kind", "")),
			"msgs": (ed.get("msgs", []) as Array).duplicate(),
		})
	return {
		"aff": _aff.duplicate(), "log": log_out, "day": _day,
		"flags": _flags.duplicate(true), "_story_day": _story_day,
		"_mention_day": _mention_day, "_td_day": _td_day,
	}


func from_dict(d: Dictionary) -> void:
	_aff = d.get("aff", {}) as Dictionary
	_log = []
	for e in (d.get("log", []) as Array).slice(0, LOG_CAP):
		var ed: Dictionary = e
		_log.append({
			"day": int(ed.get("day", 0)), "a": String(ed.get("a", "")),
			"b": String(ed.get("b", "")), "kind": String(ed.get("kind", "")),
			"msgs": (ed.get("msgs", []) as Array).duplicate(),
		})
	_day = int(d.get("day", 0))
	_flags = d.get("flags", {}) as Dictionary
	_story_day = int(d.get("_story_day", -1))
	_mention_day = int(d.get("_mention_day", -1))
	_td_day = int(d.get("_td_day", -1))
	_pending.clear()
