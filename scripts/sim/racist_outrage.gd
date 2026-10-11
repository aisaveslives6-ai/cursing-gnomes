class_name SimRacistOutrage
extends RefCounted
## Cursing Gnomes — consequences for the PLAYER crossing the hard-r line.
##
## Jeremy 2026-10-02: "if you say some racist shit in the chat that everyone
## goes to war with you and cusses you out for being a racist."
## Refined: THE trigger is the player using the hard-r n-word. Factions at
## war trash-talking each other is allowed — this is not that.
##
## trigger() fires the full realm-wide scandal:
##   1. Every other faction declares war on the player's faction.
##   2. The player's reputation tanks to 0.
##   3. NPCs from ALL factions (including the player's own people) send
##      furious DMs cussing the player out for being racist.
##   4. The Gazette publishes a FRONT-PAGE scandal story (Jeremy confirmed:
##      "RULER'S RACIST RANT SPARKS OUTRAGE"), via the real Gazette system
##      (SimRoyalCourt.publish_story -> SimGazette sections/reporters).
##   5. Hearsay seeds a max-heat realm-wide rumor.
##
## NPC lines condemn the racism. They never repeat slurs.

const HEADLINE := "RULER'S RACIST RANT SPARKS OUTRAGE"
const DMS_PER_FACTION := 2

## persona -> reaction style.
const STYLE_FOR_PERSONA := {
	"proud": "furious", "grizzled": "furious", "blunt": "furious",
	"honorable": "disgusted", "earnest": "disgusted", "haughty": "disgusted",
	"loyal": "disappointed", "worried": "disappointed", "pragmatic": "disappointed",
	"scheming": "cold", "oily": "cold", "jolly": "cold",
}

## Jeremy 2026-10-06: 100+ roast lines (27 per style x 4 = 108). The roasts
## target the PLAYER's bigotry — their racism, cowardice, crown, legacy,
## and name. They NEVER contain actual slurs and never punch at protected
## characteristics (a test asserts zero matches against every HateTerms
## pattern). {ruler} and {faction} slots are substituted at send time.
const LINES := {
	"furious": [
		"WHAT did you just say?! Say that word in my hearing again and I'll take your tongue for a trophy, you racist piece of shit!",
		"You vile, bigoted, racist bastard. Every soldier in this realm is marching on your hall as we speak — and I'll be leading them.",
		"That's the line, {ruler}. You crossed it. I'm telling EVERYONE what a racist piece of filth wears your crown.",
		"{ruler}! I have buried friends for less than what just came out of your racist mouth. Draw steel or abdicate — those are your options.",
		"A racist on the throne. My grandmother warned me this day would come. She also told me what to do about it. WAR.",
		"You just pissed on every oath you ever swore, {ruler}. The crown doesn't protect a racist from THIS.",
		"Racist. Say it again. I dare you. My axe is already thirsty and your hall is already surrounded.",
		"Every tavern from here to the coast will know what {ruler} really is by nightfall: a coward hiding racist hate behind a crown.",
		"You don't get to wear that crown and talk racist like that. Not while I breathe. WAR, {ruler}. Real war.",
		"My soldiers are already marching. You wanted to show your true racist colors? Congratulations — they're painted on a target now.",
		"{ruler}, you just declared war on decency itself with one racist rant, and decency has a bigger army than you.",
		"Filth. Absolute filth. The throne room will need fumigating after a racist like you sat in it.",
		"I have fought monsters with more honor than you, {ruler}. At least monsters aren't racist.",
		"That racist word just cost you your kingdom. Every faction. Every blade. Coming for you.",
		"Coward! Hiding racist bigotry behind a crown doesn't make you a ruler — it makes you a target.",
		"The only thing you've conquered today, {ruler}, is the title of most hated racist ruler in history.",
		"Racists don't get parleys. Racists get sieges. See you at your gates.",
		"You think a crown makes racist hate respectable? It makes it unforgivable. To arms!",
		"{ruler} the Racist. That's your legacy now. Carved in every history book, sung in every tavern — forever.",
		"I would rather serve a goblin with manners than a racist with a crown.",
		"Your racist hate just united five realms against you, {ruler}. That's the only unifying thing you'll ever do.",
		"Take it back? You can't take back the racist rot inside you. The realm saw. The realm remembers.",
		"A racist ruler is a dead ruler walking. Your move, {ruler} — the whole world is watching.",
		"You disgrace the crown, the throne, and every soul who ever bowed to you, you racist. WAR.",
		"My grandmother's ghost is already sharpening her shovel for your racist grave, {ruler}.",
		"Racists are the one enemy every faction agrees on. You just made yourself public enemy number one.",
		"Say it to my face on the battlefield, {ruler}. Oh wait — racist cowards like you only hate from thrones.",
	],
	"disgusted": [
		"I feel physically ill. Years of loyal service — for THIS? A racist on the throne? I'm done.",
		"Disgusting. Absolutely disgusting. A racist doesn't deserve the crown, the throne, or the air you breathe.",
		"My grandmother warned me about racist rulers like you. I laughed at her. I'm not laughing now.",
		"{ruler}, I have cleaned plague wards less foul than your racist mouth.",
		"You make my skin crawl, you racist. And I've shaken hands with ogres.",
		"A racist's crown is just a shiny chamber pot, {ruler}. History will remember the smell.",
		"I defended you once, racist. That memory now makes me want to wash my brain with lye.",
		"Racist filth from the throne — the rot starts at the head, {ruler}, and you are rotten to the core.",
		"Every racist word out of your mouth is a stain. The crown can't cover it. Nothing can.",
		"I have seen battlefield latrines with more dignity than you, you racist {ruler}.",
		"You sicken me, you racist. Not as a soldier — as a living soul with eyes.",
		"{ruler} the Pure? {ruler} the Just? Try {ruler} the Racist. Rolls right off the tongue, doesn't it.",
		"Your racist legacy is a skid mark on history, {ruler}. Future bards will need nose plugs.",
		"I would rather drink swamp water than share a realm with a racist ruler.",
		"The crown chose poorly. Or maybe it chose exactly what you are: racist hate in a fancy hat.",
		"You know what's worse than a tyrant, {ruler}? A racist tyrant. You're both.",
		"My dog has better judgment than you, you racist, and he eats his own vomit.",
		"Racist rulers are like plague rats, {ruler} — everyone agrees they need dealing with.",
		"I am embarrassed to have ever bowed to a racist. Consider every bow retroactively unbowed.",
		"Your racist bigotry is the only impressive thing about you, {ruler} — impressive in its sheer, staggering ugliness.",
		"The throne deserves better than a racist. The {faction} deserve better. Even the rats in your cellar deserve better.",
		"You wear racist hate like a cloak, {ruler}, but everyone can see the coward underneath.",
		"Disgusting doesn't begin to cover it, you racist. There should be a stronger word. There will be — your name.",
		"I have met demons with more tolerance than you, you racist. Demons, {ruler}.",
		"Your name will be a curse mothers use to frighten children: 'Behave, or the racist {ruler} will come.'",
		"A racist on the throne is a wound on the realm, and I intend to cauterize it.",
		"You are the reason the word 'ruler' needs airing out, you racist {ruler}.",
	],
	"disappointed": [
		"I stood by you through wars, famines, the giant ass incident... and you throw it all away with one racist rant? We deserved better, {ruler}.",
		"We believed in you. Every one of us. And a racist is what was hiding underneath the whole time? Shame on you.",
		"I defended your name in every tavern from here to the coast. Never again. A racist has shown their true colors.",
		"{ruler}, I named my child after you, you racist. I am changing the paperwork tomorrow.",
		"All those speeches about unity. All those promises. And a racist is what was underneath. We deserved better.",
		"I fought beside you, bled for you — for a racist. My scars are ashamed of me, {ruler}.",
		"You were supposed to be different, not a racist. That's the worst part. We actually believed.",
		"My father died believing in your reign, {ruler}. I will never forgive you for making his faith a racist joke.",
		"We gave you everything — loyalty, taxes, our sons and daughters for your wars. And you repay us with racist hate.",
		"I taught my children that our ruler was just. I have some very difficult explaining to do about our racist {ruler}.",
		"The saddest part? Some of us saw the racist signs and talked ourselves out of it. Never again.",
		"{ruler}, you broke something today that no army can rebuild: trust. And you did it with racist hate.",
		"I kept your portrait above my hearth, you racist. It's firewood now.",
		"We deserved a ruler. We got a racist cautionary tale, {ruler}.",
		"Every good thing you ever did just got a footnote: 'but also, a racist.'",
		"I wept when you took the throne — with joy. I weep now for our racist {ruler}, for very different reasons.",
		"You had the love of five realms in your hand, and you traded it for racist hate. Worst trade in history.",
		"My loyalty had a limit, you racist {ruler}. You found it. Congratulations.",
		"I will tell my grandchildren about the day the racist crown revealed its rot. Your name will be the punchline.",
		"We built statues of you, you racist {ruler}. The pigeons have already claimed them. Fitting.",
		"You didn't just lose a throne today, racist. You lost every heart that ever beat for you.",
		"I hope the racist hate keeps you warm at night, {ruler}. Nothing else will.",
		"The {faction} gave you a crown, you racist. You gave the realm a reason to melt it down.",
		"Shame. Just... shame on you, you racist {ruler}. That word will follow you longer than any title.",
		"I stood in the rain for your coronation, you racist. I would not cross the street for your funeral.",
		"You were our hope, {ruler}. Now you're our racist lesson.",
		"History will say you had everything — and chose to be a racist nothing.",
	],
	"cold": [
		"Oh, the mighty {ruler} finally shows their true racist face. Don't worry — by nightfall every realm will know. Every. Word.",
		"A racist on the throne? How... convenient. For everyone except you. The other four factions already have the full quote.",
		"Well, well. The racist mask slips at last. The Gazette is going to simply ADORE this story.",
		"Fascinating strategy, you racist {ruler}: unite all five realms — against yourself. Bold. Stupid, but bold.",
		"Oh good, the racist bigotry finally matches the haircut. I was wondering which would embarrass you first.",
		"Let me guess — next you'll tell us the crown made you do it. The crown is innocent, you racist {ruler}. You are not.",
		"A racist AND a coward? Pick a struggle, {ruler}. Actually, don't — you're losing both.",
		"The Gazette is going to love this. Front page. Big letters. Your name, {ruler}, right under the word 'racist.'",
		"Do go on, you racist. Every word is another nail, and I am simply delighted to watch you build your own coffin.",
		"Your reign, you racist {ruler}: a masterclass in how to turn victory into infamy in one sentence.",
		"I do admire the efficiency, you racist. Most tyrants take years to become universally despised. You did it before lunch.",
		"The other factions send their thanks, you racist {ruler}. Nothing unites people like a common embarrassment.",
		"Hate from the throne — how original. The last ten racist rulers send their regards. From the history books. Where you'll join them.",
		"Your racist legacy needed a footnote, {ruler}. You gave it a whole chapter. In red ink.",
		"Oh, {ruler} thought racist hate was a personality. Adorable. The realm disagrees.",
		"Some rulers are remembered for conquests. Racists like you will be remembered for this sentence. Just this one.",
		"The crown must be so proud of its racist. Pity it's the only thing that still respects you.",
		"Racist bigotry: the last refuge of a ruler with nothing else to offer. And you offer so little, {ruler}.",
		"I have seen smarter battle plans drawn in mud by drunk goblins. And kinder ones than your racist scheming, too.",
		"Your racist name will trend in every tavern tonight, {ruler}. Not the way you hoped.",
		"A throne built on racist hate has excellent resale value — as firewood. Asking for a friend. The friend is everyone.",
		"Congratulations, you racist {ruler}. You just speedran 'how to lose five realms.' New record.",
		"The racist mask slipped, the crown slipped, and soon the throne will slip right out from under you.",
		"Racist hate is a heavy crown, {ruler}. Heavier than gold. And far less flattering.",
		"I would offer thoughts and prayers, but you spent all the {faction} goodwill on being a racist.",
		"Your court applauds out of fear, you racist {ruler}. The rest of us applaud your downfall.",
		"Every bard in five realms just got the easiest material of their careers, you racist. Thank you for your service, {ruler}.",
	],
}


static func _hash(s: String) -> int:
	var h := 5381
	for i in range(s.length()):
		h = ((h << 5) + h + s.unicode_at(i)) & 0xFFFFFFFF
	return h


static func _style_for(unit: Dictionary) -> String:
	var mind: Dictionary = unit.get("mind", {})
	return STYLE_FOR_PERSONA.get(String(mind.get("persona", "blunt")), "furious")


## Jeremy 2026-10-06: without-replacement sampling per NPC per style —
## repeat offenders get fresh roasts every time; the pool reshuffles only
## at full exhaustion (same pattern as unhinged.gd).
static var _used := {}


static func _sample(style: String, uid: int) -> int:
	var pool: Array = LINES[style]
	var key := "%d:%s" % [uid, style]
	var used: Array = (_used.get(key, []) as Array).duplicate()
	if used.size() >= pool.size():
		used = []
	var idx := randi() % pool.size()
	var guard := 0
	while idx in used and guard < pool.size() * 2:
		idx = randi() % pool.size()
		guard += 1
	used.append(idx)
	_used[key] = used
	return idx


static func _fill(line: String, unit: Dictionary, ruler_name: String) -> String:
	var faction := String(unit.get("faction", "the realm"))
	return line.replace("{ruler}", ruler_name).replace("{faction}", faction)


## The immediate reply from the NPC the player was talking to.
static func outrage_reply_for(unit: Dictionary, ruler_name: String) -> String:
	var style := _style_for(unit)
	var pool: Array = LINES[style]
	return _fill(String(pool[_sample(style, int(unit.get("id", 0)))]), unit, ruler_name)


## A furious DM line for some other NPC cussing the player out.
static func dm_line_for(unit: Dictionary, ruler_name: String) -> String:
	var style := _style_for(unit)
	var pool: Array = LINES[style]
	return _fill(String(pool[_sample(style, int(unit.get("id", 0)))]), unit, ruler_name)


## Fires the full scandal. phone is duck-typed SimPhone.
## Returns {triggered, wars: Array, dms_sent: int, headline: String}.
static func trigger(gs: GameState, phone) -> Dictionary:
	var pf: String = gs.player_faction
	var ruler: String = gs.ruler_name
	var result := {"triggered": true, "wars": [], "dms_sent": 0,
		"headline": HEADLINE}

	# 1. Everyone declares war on the player.
	for f: String in Config.FACTIONS.keys():
		if f == pf:
			continue
		var res: Dictionary = gs.diplomacy.declare_war(
			f, pf, "the ruler's racist rant")
		if bool(res.get("ok", false)):
			(result["wars"] as Array).append(f)

	# 2. Reputation tanks.
	gs.diplomacy.tarnish_reputation(pf, -60.0)

	# 3. Furious DMs from every faction — including the player's own people.
	var dms := 0
	for f: String in Config.FACTIONS.keys():
		var sent := 0
		for u: Dictionary in gs.units:
			if sent >= DMS_PER_FACTION:
				break
			if not u.get("alive", false):
				continue
			if String(u.get("faction", "")) != f:
				continue
			phone.npc_message(int(u.get("id", 0)), dm_line_for(u, ruler))
			sent += 1
			dms += 1
	result["dms_sent"] = dms

	# 4. Gazette front page (Jeremy confirmed). Uses the real Gazette system:
	# publish_story -> SimGazette section/reporter/cartoon/caption.
	if phone._court != null:
		var fname: String = String((Config.FACTIONS[pf] as Dictionary)["name"])
		var others: Array[String] = []
		for f2: String in Config.FACTIONS.keys():
			if f2 != pf:
				others.append(String((Config.FACTIONS[f2] as Dictionary)["name"]))
		var body := "In a scandal shaking all five realms, %s of the %s was overheard using the hard-r n-word — the vilest slur in the common tongue. Within the hour, the %s had each declared war on the %s. \"There are lines you do not cross,\" said one envoy, visibly shaking. \"The crown crossed it.\"" % [
			ruler, fname, ", ".join(PackedStringArray(others)), fname]
		# urgent + kicker ride the publish (emit-time), so the urgent toast
		# and Chronicle article see them — post-emit mutation was too late
		# for bus listeners.
		phone._court.publish_story(HEADLINE, body, "war",
			{"urgent": true, "kicker": "WAR DESK"})

	# 5. Hearsay: max-heat realm-wide rumor.
	if phone.hearsay != null:
		phone.hearsay.seed_rumor(
			"The ruler (%s) went on a racist rant — used the hard-r n-word. Every faction declared war." % ruler,
			"scandal", ruler, 1.0)

	# 6. Jeremy 2026-10-04: the racist incident goes into leaders' memory.
	# Every faction leader remembers who did it.
	var fl = gs.get("faction_leaders")
	if fl != null:
		fl.note_racist_incident(pf, ruler)

	return result
