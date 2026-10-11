class_name SimFactions
extends RefCounted
## Cursing Gnomes — faction military rosters (Milestone 5).
##
## Faithful port of the HTML build's per-faction military units (fix79):
##   - RACES bases: human hp 200/dmg 9/range 42/speed 1.0,
##     ogre hp 550/dmg 38/range 58/speed 1.6,
##     gnome hp 160/dmg 14/range 40/speed 1.35,
##     elf hp 180/dmg 11/range 40/speed 1.2.
##   - Unit job-branch stat multipliers (the `if (job === ...)` branches),
##     COSTS training costs, TRAIN_TIME, and the Building.canTrain gates.
##   - C61 faction uniques: cleric, tinker_mech, saboteur, warlord,
##     blunderbuss, treant, spellweaver — with their special abilities:
##     cleric smite (x1.6 vs undead) + heals/cures plague (HTML MEDIC_JOBS),
##     warlord aura (1 s pulse, 320 px radius, allies hit x1.25 for 3 s),
##     blunderbuss 5-pellet cone (each floor(dmg*0.55), splash 32/0.5,
##     0.16 rad spread), treant siege (x2 vs buildings), saboteur wall shred
##     (x1.5 vs walls), spellweaver snare (speed x0.5 for 6 s),
##     warlock nature-spirit summons (35% while fighting, 8 s cooldown,
##     spirit hp 40 / dmg 12 / range 40 / 18 s life),
##     knight cavalry charge (x2.2 after a >200 px approach),
##     mage rotating spells (fireball x1.15 r110, lightning x1.35 r90,
##     arcane x1.0 r130, splash 120/0.85).
##
## Follows the SimUndead roster pattern: a ROSTER const with hp_mul/dmg_mul/
## speed(px/s)/attack_rate/range/cost/train_time/trained_at + an
## apply_faction_stats() that stamps the multipliers onto a spawned unit
## record (base hp comes from the spawner, base dmg falls back to the
## faction's race dmg). Speeds are the HTML speed multipliers mapped onto
## Godot px/s (soldier 95), rounded like the undead roster.
##
## Decoupling: combat.gd calls the thin hooks (maybe_snare_on_hit from
## damage_unit, cleric smite / knight charge / blunderbuss pellets / aura61
## from _attack, cleric medic duty from tick_medics) — this class never
## touches combat internals. Pure logic — no rendering, no input, no audio.


## HTML RACES verbatim (combat-relevant fields).
const FACTION_BASES := {
	"humans": {"hp": 200.0, "dmg": 9.0, "range": 42.0, "speed": 1.0},
	"ogres": {"hp": 550.0, "dmg": 38.0, "range": 58.0, "speed": 1.6},
	"gnomes": {"hp": 160.0, "dmg": 14.0, "range": 40.0, "speed": 1.35},
	"elves": {"hp": 180.0, "dmg": 11.0, "range": 40.0, "speed": 1.2},
}

## Per-faction military roster. Derivations (HTML Unit job branches):
##   hp = floor(race.hp * hp_mul), dmg = floor(race.dmg * dmg_mul),
##   speed px/s = round(race.speed * factor * 95).
const FACTION_ROSTERS := {
	"humans": {
		"swordsman": {  # basic line infantry — barracks
			"hp_mul": 1.0, "dmg_mul": 1.05, "speed": 95.0, "attack_rate": 0.42,
			"range": 42.0,
			"cost": {"gold": 40.0, "wood": 22.0}, "train_time": 3.4,
			"trained_at": ["barracks"],
		},
		"archer": {  # ranged line — barracks
			"hp_mul": 0.85, "dmg_mul": 0.95, "speed": 106.0, "attack_rate": 0.55,
			"range": 115.0,
			"cost": {"gold": 40.0, "wood": 35.0}, "train_time": 3.8,
			"trained_at": ["barracks"],
		},
		"knight": {  # elite: fast slashes + cavalry charge — knights_castle
			"hp_mul": 1.55, "dmg_mul": 1.35, "speed": 119.0, "attack_rate": 0.22,
			"range": 48.0, "charge": true,
			"cost": {"gold": 80.0, "wood": 45.0}, "train_time": 5.5,
			"trained_at": ["knights_castle"],
		},
		"cleric": {  # holy support: smites undead, heals, cures plague — barracks
			"hp_mul": 1.1, "dmg_mul": 0.9, "speed": 100.0, "attack_rate": 0.55,
			"range": 50.0, "smite": true, "medic": true,
			"cost": {"gold": 70.0, "wood": 30.0}, "train_time": 7.0,
			"trained_at": ["barracks"],
		},
	},
	"ogres": {
		"clubber": {  # basic line — barracks
			"hp_mul": 1.0, "dmg_mul": 1.1, "speed": 137.0, "attack_rate": 0.55,
			"range": 58.0,
			"cost": {"gold": 50.0, "wood": 20.0}, "train_time": 4.2,
			"trained_at": ["barracks"],
		},
		"musketeer": {  # long-range gunner — barracks
			"hp_mul": 0.85, "dmg_mul": 1.35, "speed": 129.0, "attack_rate": 0.95,
			"range": 210.0,
			"cost": {"gold": 60.0, "wood": 30.0}, "train_time": 4.8,
			"trained_at": ["barracks"],
		},
		"berserker": {  # elite: hammer splash — war_hut
			"hp_mul": 1.45, "dmg_mul": 1.5, "speed": 236.0, "attack_rate": 0.65,
			"range": 68.0, "splash": 72.0, "splash_mul": 0.55,
			"cost": {"gold": 90.0, "wood": 35.0}, "train_time": 5.8,
			"trained_at": ["war_hut"],
		},
		"warlord": {  # commander: aura buffs nearby allies' attacks — war_hut
			"hp_mul": 2.2, "dmg_mul": 1.8, "speed": 167.0, "attack_rate": 0.7,
			"range": 70.0, "splash": 80.0, "splash_mul": 0.5, "aura_buff": true,
			"cost": {"gold": 160.0, "wood": 60.0}, "train_time": 20.0,
			"trained_at": ["war_hut"],
		},
		"blunderbuss": {  # shotgun: 5-pellet cone — barracks
			"hp_mul": 1.3, "dmg_mul": 1.1, "speed": 137.0, "attack_rate": 0.9,
			"range": 95.0, "pellets": true,
			"cost": {"gold": 130.0, "wood": 70.0}, "train_time": 11.0,
			"trained_at": ["barracks"],
		},
		"cannoneer": {  # siege cannon — war_hut
			"hp_mul": 1.2, "dmg_mul": 2.2, "speed": 84.0, "attack_rate": 1.6,
			"range": 300.0, "splash": 90.0, "splash_mul": 0.7, "artillery": true,
			"cost": {"gold": 95.0, "wood": 50.0}, "train_time": 6.2,
			"trained_at": ["war_hut"],
		},
	},
	"gnomes": {
		"axeman": {  # basic line — barracks
			"hp_mul": 1.0, "dmg_mul": 1.2, "speed": 135.0, "attack_rate": 0.45,
			"range": 40.0,
			"cost": {"gold": 35.0, "wood": 28.0}, "train_time": 3.6,
			"trained_at": ["barracks"],
		},
		"mage": {  # glass cannon, rotating spells — barracks + mage_spire
			"hp_mul": 0.9, "dmg_mul": 2.8, "speed": 135.0, "attack_rate": 0.85,
			"range": 130.0, "splash": 120.0, "splash_mul": 0.85, "spells": true,
			"cost": {"gold": 55.0, "wood": 45.0}, "train_time": 5.2,
			"trained_at": ["barracks", "mage_spire"],
		},
		"tinker_mech": {  # mech suit: tanky, big splash punches — mage_spire
			"hp_mul": 3.2, "dmg_mul": 2.2, "speed": 90.0, "attack_rate": 0.8,
			"range": 54.0, "splash": 90.0, "splash_mul": 0.6,
			"cost": {"gold": 150.0, "wood": 90.0}, "train_time": 16.0,
			"trained_at": ["mage_spire"],
		},
		"saboteur": {  # infiltrator: shreds walls — barracks
			"hp_mul": 0.8, "dmg_mul": 0.8, "speed": 192.0, "attack_rate": 0.4,
			"range": 40.0, "wall_shred": true,
			"cost": {"gold": 60.0, "wood": 30.0}, "train_time": 8.0,
			"trained_at": ["barracks"],
		},
	},
	"elves": {
		"ranger": {  # basic line — barracks
			"hp_mul": 1.0, "dmg_mul": 1.15, "speed": 137.0, "attack_rate": 0.48,
			"range": 130.0,
			"cost": {"gold": 42.0, "wood": 38.0}, "train_time": 4.0,
			"trained_at": ["barracks"],
		},
		"warlock": {  # summons nature spirits — tome_library
			"hp_mul": 1.05, "dmg_mul": 2.2, "speed": 125.0, "attack_rate": 0.9,
			"range": 125.0, "splash": 70.0, "splash_mul": 0.5, "summoner": true,
			"cost": {"gold": 70.0, "wood": 55.0}, "train_time": 5.8,
			"trained_at": ["tome_library"],
		},
		"treant": {  # siege: shreds buildings — barracks
			"hp_mul": 4.0, "dmg_mul": 2.6, "speed": 68.0, "attack_rate": 1.1,
			"range": 56.0, "siege": true,
			"cost": {"gold": 120.0, "wood": 90.0}, "train_time": 16.0,
			"trained_at": ["barracks"],
		},
		"spellweaver": {  # crowd control: snares enemies — tome_library
			"hp_mul": 1.0, "dmg_mul": 1.1, "speed": 114.0, "attack_rate": 0.75,
			"range": 230.0, "snare": true,
			"cost": {"gold": 110.0, "wood": 60.0}, "train_time": 10.0,
			"trained_at": ["tome_library"],
		},
	},
}

## HTML Building.canTrain gates (the authority for what trains where).
const TRAIN_GATES := {
	"humans": {
		"barracks": ["swordsman", "archer", "cleric"],
		"knights_castle": ["knight"],
	},
	"ogres": {
		"barracks": ["clubber", "musketeer", "blunderbuss"],
		"war_hut": ["berserker", "cannoneer", "warlord"],
	},
	"gnomes": {
		"barracks": ["axeman", "mage", "saboteur"],
		"mage_spire": ["mage", "tinker_mech"],
	},
	"elves": {
		"barracks": ["ranger", "treant"],
		"tome_library": ["warlock", "spellweaver"],
	},
	"undead": {
		"barracks": ["skeleton", "zombie", "ghoul"],
		"necropolis": ["necromancer", "wraith", "plaguebearer", "bone_golem"],
	},
}

## Warlock summoning (HTML: 35% roll while fighting, 8 s cooldown).
const WARLOCK_SUMMON_CHANCE := 0.35
const WARLOCK_SUMMON_CD := 8.0
## Nature spirit (HTML: hp 40, dmg 12, range 40, 18 s life, named 'Spirit').
const SPIRIT_HP := 40.0
const SPIRIT_DMG := 12.0
const SPIRIT_RANGE := 40.0
const SPIRIT_LIFE := 18.0

## Warlord aura (HTML warlordAuraPulse61): 1 s pulse, 320 px radius,
## same-faction allies hit x1.25 (floor) for 3 s.
const WARLORD_AURA_PULSE := 1.0
const WARLORD_AURA_RADIUS := 320.0
const WARLORD_AURA_TIME := 3.0
const WARLORD_AURA_MUL := 1.25

## Spellweaver snare (HTML spellweaverSnare61): speed x0.5 for 6 s.
const SNARE_TIME := 6.0
const SNARE_MUL := 0.5

## Cleric smite vs undead (HTML x1.6, floored).
const CLERIC_SMITE_MUL := 1.6
## Siege engines shred buildings x2; saboteurs shred walls x1.5 (HTML).
const SIEGE_BUILDING_MUL := 2.0
const SABOTEUR_WALL_MUL := 1.5
## Knight cavalry charge: striking after a >200 px approach hits x2.2 (HTML).
const KNIGHT_CHARGE_RANGE2 := 40000.0
const KNIGHT_CHARGE_MUL := 2.2

## Blunderbuss cone (HTML): 5 pellets, 0.16 rad spread each, each
## floor(dmg*0.55), splash 32/0.5, 95 px cone length, 520 px/s shot.
const BLUNDER_PELLETS := 5
const BLUNDER_SPREAD := 0.16
const BLUNDER_PELLET_DMG_MUL := 0.55
const BLUNDER_SPLASH := 32.0
const BLUNDER_SPLASH_MUL := 0.5
const BLUNDER_RANGE := 95.0
const BLUNDER_PROJ_SPEED := 520.0

## Mage rotating spells (HTML: fireball x1.15 r110, lightning x1.35 r90,
## arcane x1.0 r130, splashMul 0.85).
const MAGE_SPELLS := [
	{"mul": 1.15, "r": 110.0, "kind": "fireball"},
	{"mul": 1.35, "r": 90.0, "kind": "lightning"},
	{"mul": 1.0, "r": 130.0, "kind": "arcane"},
]
const MAGE_SPLASH_MUL := 0.85

## Canonical faction personalities (HTML FACTION_SOUL, verbatim).
## Undead falls back to human (HTML factionSoul: FACTION_SOUL[f] || FACTION_SOUL.human).
const FACTION_SOUL := {
	"gnome": {
		"epithet": "the foul-mouthed little shits",
		"values": {"tribute": 0.70, "strength": 0.45, "trade": 0.85, "humor": 1.00, "ceremony": 0.10, "diplomacy": 0.55, "honor": 0.50},
		"trade_stance": "haggler",
		"military": {"aggro": 0.55, "style": "tricky"},
		"voice": {
			"greet": ["Oi, {name}.", "Right, listen up {name}.", "Ah shit, it's {name}.", "Oi oi! {name}, ya little legend."],
			"quip": ["Absolute shitshow, but OUR shitshow.", "I'd pay good gold to watch that again. Actually no, I wouldn't. Gold's gold.", "Somewhere a gnome just laughed so hard he shat himself. Probably me.", "Bloody marvelous. Pass the ale and the bandages.", "That's the funniest thing since the Great Trout Incident. Don't ask.", "Piss and thunder, what a day."],
			"praise": ["Not bad, {name}! Not bad at all, ya magnificent bastard.", "Ha! The {name} actually did a thing! Ale's on me. (It isn't.)", "Alright, credit where it's due, ya smug little monarch — nicely done."],
			"threat": ["Keep pushin', {name}, and I'll shove me boot so far up yer arse you'll taste leather for a month.", "You're one bad decision from a proper gnome kicking, {name}. And we kick DIRTY.", "Last warning, shithead. Next time it's torches and pitchforks. Mostly pitchforks."],
			"insult": ["yer about as useful as a chocolate teapot, {name}", "{name}? More like {name} the Arse. (Sorry. Not sorry.)", "I've seen smarter cabbages, {name}, and I've EATEN smarter cabbages", "ya walk like a duck with hemorrhoids, {name}"],
			"mock": ["{name}?! HA! Did yer parents lose a bet? \"{name}\"?!", "\"{name}\". Piss me, that's the daftest thing I ever heard, and I once knew a gnome named Fartbucket.", "{name}… {name}… say it again slower so I can laugh properly. \"{name}.\" GOLD.", "Yer royal name is \"{name}\"? I've taken shits with more dignity. Lovely to meet ya though."],
			"tradeAsk": ["Right, {name}, let's do business before my sobriety wears off. I got goods, you got gold. Simple as piss.", "Fancy a deal, {name}? No refunds, no crying, no telling yer mum."],
			"tributeDemand": ["Right then, {name}. The clan's short on coin and long on grudges. {gold} gold. Pay up or piss off.", "Tribute time, {name}. {gold} gold, and make it snappy — me patience has the lifespan of a mayfly with gout."],
			"helpPlea": ["Alright, I'll say it once and never again: we need help, {name}. Don't make it weird.", "We're in the shit here, {name}. Proper shit. Knee-deep. Send aid or send a shovel."],
			"weird": ["Do ya ever wonder if the moon's just the sun's shy brother? Anyway. Taxes.", "I trained me pet rock to fetch. It fetched. Once. I'm basically a wizard now.", "If a tree falls in the forest and no gnome hears it, does it still owe me money? Asking for a friend. The friend is me. I'm owed money."],
			"agree": ["Deal, ya beautiful bastard.", "Aye! Done. Someone write that down before I forget.", "Pleasure doing business, {name}. (Mild pleasure. Don't push it.)"],
			"refuse": ["Piss off, then.", "Fine! See if I care. (I care a little.)", "Yer loss, {name}. Yer massive, gaping loss."],
		},
	},
	"human": {
		"epithet": "the plain-spoken folk",
		"values": {"tribute": 0.50, "strength": 0.50, "trade": 1.00, "humor": 0.20, "ceremony": 0.50, "diplomacy": 0.70, "honor": 0.70},
		"trade_stance": "steady",
		"military": {"aggro": 0.50, "style": "balanced"},
		"voice": {
			"greet": ["{name}.", "Good day, {name}.", "{name} — we need to talk.", "A word, {name}."],
			"quip": ["That's the way of things. Could be worse.", "Well. That happened. We'll deal with it.", "Huh. Didn't see that coming, and I've seen harvests fail.", "Noted. The clerks will write it down and someone will file it.", "A hard day's work, that. Nothing more to say.", "The roads are muddy but passable. Like most news."],
			"praise": ["Well done, {name}. That was solid work — no more, no less.", "Credit where it's due, {name}. You handled that right.", "Good. That's the kind of ruling people remember fondly."],
			"threat": ["{name}. Push us further and we'll push back. That's not a threat, it's arithmetic.", "We don't want war, {name}. But we'll finish one. Think carefully.", "Last chance, {name}. Our levies are mustered and our patience is spent."],
			"insult": ["you rule like a man trying to read in the dark, {name}", "I've met mules with better judgment than you, {name}", "{name}, you couldn't organize a harvest in autumn"],
			"mock": ["\"{name}\". Hm. Well. I'm sure it means something dignified… somewhere.", "{name}? That's… a name, {name}. Technically.", "They call you \"{name}\". The men-at-arms have started a betting pool on what it means.", "\"{name}\". Right. I'll try to say it with a straight face at court. No promises."],
			"tradeAsk": ["{name}. Straight terms, no tricks: goods for gold, weighed fair. Interested?", "Our merchants are ready, {name}. Fair prices, honest weights, regular caravans. Say the word."],
			"tributeDemand": ["{name}, the council has voted: a levy of {gold} gold. It's not personal — the granaries don't fill themselves.", "We ask {gold} gold as tribute, {name}. Pay it and we all sleep easier."],
			"helpPlea": ["{name}, I'll be plain: we need help, and we need it soon.", "No flowery words — our stores are low, {name}. Anything you can spare."],
			"weird": ["My neighbor's goat got into the turnips again. Reminded me of tax season.", "Rain's coming. You can smell it. Anyway — state business.", "The well in Millford finally got fixed. Took eleven years. Felt worth mentioning."],
			"agree": ["Agreed, {name}. We'll hold to it.", "Done. A handshake on it.", "Fair enough. It's settled."],
			"refuse": ["No, {name}.", "We'll pass. Nothing personal.", "Not today, {name}."],
		},
	},
	"elf": {
		"epithet": "the luminous wise ones",
		"values": {"tribute": 0.30, "strength": 0.30, "trade": 0.60, "humor": 0.10, "ceremony": 1.00, "diplomacy": 0.85, "honor": 1.00},
		"trade_stance": "principled",
		"military": {"aggro": 0.35, "style": "tactical"},
		"voice": {
			"greet": ["Ah, {name}. The stars incline toward this conversation. ✨", "{name}, beloved chaos. Speak. 🌙", "Greetings, {name}. The forest has been whispering your name. 🍃"],
			"quip": ["The old songs will remember this day, though they may choose kinder words.", "Even the willows paused to watch. That is… significant. 🌿", "A thousand years from now, bards will argue about what just happened. Adorable.", "The moon saw it all and told the owls. The owls told me. ✨", "How… mortal. How wonderfully, terribly mortal.", "The petals fall where they will, and today they fell HERE. 🌸"],
			"praise": ["Beautifully done, {name}. The forest itself seems to approve. 🌿", "Oh, well played, little king. Even the dryads are applauding. ✨", "{name}, that was… genuinely elegant. I did not expect elegance. Delightful."],
			"threat": ["{name}, dear. Even starlight casts a shadow. Do not make us become yours. 🌑", "We have ended older kingdoms than yours with a sigh and a song. Reconsider, sweetling.", "This is the part of the story where the wise ruler turns back, {name}. Be the wise ruler. 🍃"],
			"insult": ["darling, you have the strategic depth of a puddle, and the puddle at least reflects the sky ✨", "{name}, I have seen more wisdom in a mushroom. A cute mushroom, but still", "oh, {name}. The stars weep. Mostly from secondhand embarrassment 🌙"],
			"mock": ["\"{name}\"? Oh, precious. It sounds like a sneeze the forest would find adorable. 🌸", "{name}… say it like a poem and perhaps it becomes one. \"{name}.\" …No. Still adorable though. ✨", "The ancient tongue has no word for \"{name}\". The ancient tongue is grateful. 🍃", "\"{name}\". Hm. The dryads are giggling. I am trying very hard not to. 🌙"],
			"tradeAsk": ["{name}, let us trade as civilized beings: fair measure for fair measure, sealed with courtesy. ✨", "Our artisans offer their finest, {name}. We ask only honest exchange — and honorable conduct. 🌿"],
			"tributeDemand": ["{name}, custom demands a gesture: {gold} gold, offered gracefully. The manner of giving matters more than the sum. 🌙", "A tribute of {gold} gold would please the court, {name}. Offer it beautifully and all is forgiven. ✨"],
			"helpPlea": ["{name}, the groves are troubled, and pride is a poor shield. Will you help us? 🌿", "Even the eternal sometimes need a friend, {name}. The forest asks — I ask. ✨"],
			"weird": ["I taught a nightingale your tax policy. It now sings only in minor key. 🌙", "Did you know clouds have favorite shapes? Today's is \"disappointed\". ✨", "I have been alive 400 years and I still don't understand pockets. Where do things GO? 🍃"],
			"agree": ["It is agreed, {name}. The stars witness it. ✨", "Yes, little king. Gracefully, gladly. 🌿", "So be it — beautifully so. 🌙"],
			"refuse": ["No, {name}. Gently, but no. 🍃", "The forest declines. As do I. ✨", "I think not, dear. 🌙"],
		},
	},
	"ogre": {
		"epithet": "the lovable brutes",
		"values": {"tribute": 0.95, "strength": 1.00, "trade": 0.40, "humor": 0.60, "ceremony": 0.00, "diplomacy": 0.20, "honor": 0.60},
		"trade_stance": "bully",
		"military": {"aggro": 1.00, "style": "aggressive"},
		"voice": {
			"greet": ["{name}!! YOU COME TALK! GOOD!", "OH. It {name}. The tiny king. Hello!", "{name}! ME HAPPY YOU HERE! (me not happy. me hungry.)"],
			"quip": ["HA! THAT WAS GREAT! ME LAUGH SO HARD ME DROPPED ME CLUB! (me found it.)", "OOH! SHINY EVENT! ME LIKE! ME TELL EVERYONE! (me forget by dinner.)", "THAT REMIND ME OF TIME ME SAT ON A HOUSE. GOOD TIMES.", "ME SAW IT HAPPEN! ME WAS EATING! BEST LUNCH EVER!", "WOW! BIG NOISES! ME LOVE BIG NOISES!", "ME TELL THE BOYS! THE BOYS LOVE STORIES! (boys asleep. me tell anyway.)"],
			"praise": ["{name} STRONG! ME LIKE STRONG! YOU GOOD TINY KING!", "HA! {name} DID THE THING! ME CLAP! (me clap broke a table. worth it.)", "YOU SMART FOR TINY PERSON, {name}! ME RESPECT!"],
			"threat": ["{name}. YOU MAKE ME ANGRY. YOU NOT LIKE ME WHEN ME ANGRY. (nobody like me when me angry. me break furniture.)", "ME COUNT TO TEN! ONE… TWO… ME FORGOT REST! THAT MEAN WAR SOON, {name}!", "YOU PUSH OGRE, OGRE PUSH BACK! OGRE PUSH BACK WITH A TREE, {name}!"],
			"insult": ["YOU DUMB LIKE A ROCK, {name}! (me like rocks. rocks better than you.)", "{name} SMELL LIKE FEET! OGRE FEET! AND OGRE FEET SMELL BAD!", "ME ARM WRESTLE YOU, {name}! ME WIN! ME ALWAYS WIN! YOU TINY!"],
			"mock": ["{name}?! HAHAHA! ME NAME BETTER! ME NAME IS… uh… ME FORGOT! STILL BETTER!", "\"{name}\"! THAT FUNNY NAME! ME LAUGH! ME LAUGH SO MUCH! …\"{name}\"! HA!", "{name}?? WHAT KIND OF NAME IS {name}?! ME CALL YOU… TINY! YOU ARE TINY NOW!", "ME HEARD YOUR NAME IS \"{name}\"! ME TELL ALL OGRES! ALL OGRES LAUGH! (ogres laugh at everything. but still.)"],
			"tradeAsk": ["{name}! YOU GIVE ME GOLD! ME GIVE YOU… STUFF! GOOD STUFF! (stuff heavy. you like heavy?)", "TRADE! TRADE! ME LOVE TRADE! YOU GIVE SHINY, ME GIVE BIG! FAIR! (fair-ish.)"],
			"tributeDemand": ["{name}! GIVE ME {gold} GOLD! TRIBUTE! ME STRONGEST! STRONGEST GETS GOLD! THAT RULES!", "ME NEED {gold} GOLD, {name}! NOT ASKING! …okay me asking. BUT LOUDLY!"],
			"helpPlea": ["{name}! OGRES HUNGRY! BELLY EMPTY! PLEASE HELP! ME REMEMBER KINDNESS! (me forget most things. not kindness. probably.)", "ME NEED HELP, {name}! YOU HELP OGRE, OGRE HELP YOU SMASH THINGS LATER!"],
			"weird": ["ME WONDER… IF ME EAT THE MOON, WOULD IT BE CHEESE? ME THINK YES. ME TRY SOMEDAY.", "ME NAMED ALL ME TEETH! THIS ONE IS STEVE! (steve loose. me worried about steve.)", "ME DREAMED ME WAS A BUTTERFLY! THEN ME WOKE UP! STILL OGRE! BEST DREAM!", "WHY IS THE SKY UP? ME THINK ABOUT THIS A LOT. ME SMART. (me not smart.)"],
			"agree": ["YES! DEAL! ME HAPPY! (me always happy. except hungry.)", "OKAY! WE DO IT! HIGH FIVE! (gentle high five. me break your hand otherwise.)"],
			"refuse": ["NO! ME SAY NO! LOUD NO!", "HM. NO. ME THINK… NO."],
		},
	},
}


## ---- canonical personalities (HTML FACTION_SOUL) ----------------------------

## Returns the canonical soul for a faction. Undead falls back to human,
## mirroring HTML factionSoul(): FACTION_SOUL[f] || FACTION_SOUL.human.
## Handles Godot's plural faction ids (ogres -> ogre, etc.).
static func soul_of(faction: String) -> Dictionary:
	var key := faction
	# Map Godot plural ids to HTML singular FACTION_SOUL keys.
	if key == "ogres":
		key = "ogre"
	elif key == "elves":
		key = "elf"
	elif key == "humans":
		key = "human"
	elif key == "gnomes":
		key = "gnome"
	return FACTION_SOUL.get(key, FACTION_SOUL["human"])


## Aggression 0..1 (ogres 1.0, elves 0.35). Drives war likelihood,
## tribute demands, and raid behavior.
static func soul_aggro(faction: String) -> float:
	return float((soul_of(faction).get("military", {}) as Dictionary).get("aggro", 0.5))


## Trade stance: haggler (gnome), steady (human), principled (elf), bully (ogre).
static func soul_trade_stance(faction: String) -> String:
	return String(soul_of(faction).get("trade_stance", "steady"))


## A values dict: tribute/strength/trade/humor/ceremony/diplomacy/honor.
static func soul_values(faction: String) -> Dictionary:
	return soul_of(faction).get("values", {})


## Picks a random voice line from a category, substituting {name}, {gold},
## and any extra keys in replacements. Returns "" when missing.
static func soul_say(faction: String, category: String,
		replacements: Dictionary = {}) -> String:
	var voice: Dictionary = (soul_of(faction).get("voice", {}) as Dictionary)
	var lines: Array = voice.get(category, [])
	if lines.is_empty():
		return ""
	var line: String = String(lines[randi() % lines.size()])
	for k: String in replacements.keys():
		line = line.replace("{%s}" % k, str(replacements[k]))
	return line



var _gs: GameState

## Perf R19: faction special tick runs every 3rd frame (20Hz) instead of
## every frame (full unit scan/frame, ~0.38ms/f probe-verified). Snare /
## aura / summon timers stay identical via delta*3; warlock summon rolls
## scale with delta so the expected summon rate is unchanged; the warlord
## aura pulse already runs on its own 1 s timer, so allies are re-marked
## no later than before plus one stagger frame. Ephemeral counter, no
## save/load needed (same pattern as the R17 crime-global stagger).
var _tick_frame := 0


func _init(game_state: GameState) -> void:
	_gs = game_state


## HTML Building.canTrain gate: does this faction's building train the type?
static func can_train_gate(faction: String, btype: String,
		unit_type: String) -> bool:
	var fg: Dictionary = TRAIN_GATES.get(faction, {})
	var list: Array = fg.get(btype, [])
	return unit_type in list


## ---- roster stats ------------------------------------------------------------

## Applies the HTML Unit job-branch multipliers to a spawned unit record,
## mirroring SimUndead.apply_undead_stats. Base hp comes from the record
## (spawner sets the faction race hp); base dmg falls back to the faction's
## race dmg when the record carries none. Static: pure data transform.
static func apply_faction_stats(unit: Dictionary) -> void:
	var faction: String = String(unit.get("faction", ""))
	var r: Dictionary = (FACTION_ROSTERS.get(faction, {}) as Dictionary).get(
		String(unit.get("job", "")), {})
	if r.is_empty():
		return
	var base: Dictionary = FACTION_BASES.get(faction, {})
	var base_hp: float = float(unit.get("hp", 0.0))
	if base_hp <= 0.0:
		base_hp = float(base.get("hp", 100.0))
	var hp: float = floor(base_hp * float(r.get("hp_mul", 1.0)))
	unit["hp"] = hp
	unit["max_hp"] = hp
	var base_dmg: float = float(unit.get("dmg", 0.0))
	if base_dmg <= 0.0:
		base_dmg = float(base.get("dmg", 9.0))
	unit["dmg"] = floor(base_dmg * float(r.get("dmg_mul", 1.0)))
	unit["speed"] = float(r.get("speed", 95.0))
	unit["attack_rate"] = float(r.get("attack_rate", 0.5))
	unit["range"] = float(r.get("range", 42.0))
	if r.has("splash"):
		unit["splash"] = float(r["splash"])
		unit["splash_mul"] = float(r.get("splash_mul", 0.5))
	for flag: String in ["charge", "smite", "medic", "aura_buff", "pellets",
			"artillery", "spells", "wall_shred", "summoner", "siege", "snare"]:
		if r.has(flag):
			unit[flag] = r[flag]


## ---- special abilities ---------------------------------------------------------

## Spellweaver snare hook (HTML spellweaverSnare61): call from whoever
## resolves a hit — spellweaver hits slow the victim x0.5 for 6 s.
func maybe_snare_on_hit(attacker: Dictionary, target: Dictionary) -> bool:
	if attacker.is_empty() or target.is_empty():
		return false
	if String(attacker.get("job", "")) != "spellweaver":
		return false
	if not target.get("alive", false):
		return false
	if float(target.get("snare_t", 0.0)) <= 0.0:
		target["_snare_base"] = float(target.get("speed", 90.0))
	target["snare_t"] = SNARE_TIME
	target["speed"] = float(target.get("_snare_base", 90.0)) * SNARE_MUL
	return true


## ---- per-tick ------------------------------------------------------------------

func tick(delta: float) -> void:
	_tick_frame += 1
	if _tick_frame < 3:
		return
	_tick_frame = 0
	var d3: float = delta * 3.0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var job: String = String(u.get("job", ""))
		_tick_snare(u, d3)
		_tick_aura_decay(u, d3)
		if bool(u.get("is_summon", false)):
			u["summon_life"] = float(u.get("summon_life", 0.0)) - d3
			if float(u.get("summon_life", 0.0)) <= 0.0:
				_gs.kill_unit(int(u.get("id", -1)))
				continue
		if job == "warlock":
			_tick_warlock(u, d3)
		elif job == "warlord":
			_tick_warlord_aura(u, d3)


func _tick_snare(u: Dictionary, delta: float) -> void:
	if float(u.get("snare_t", 0.0)) <= 0.0:
		return
	u["snare_t"] = float(u.get("snare_t")) - delta
	if float(u.get("snare_t")) <= 0.0:
		if u.has("_snare_base"):
			u["speed"] = float(u["_snare_base"])
			u.erase("_snare_base")
		u.erase("snare_t")


func _tick_aura_decay(u: Dictionary, delta: float) -> void:
	if float(u.get("aura61", 0.0)) > 0.0:
		u["aura61"] = maxf(0.0, float(u.get("aura61")) - delta)


## Warlocks summon nature spirits while fighting (HTML: 35% roll per attack
## with an 8 s cooldown; here a per-second roll while attacking).
func _tick_warlock(u: Dictionary, delta: float) -> void:
	u["summon_cd"] = maxf(0.0, float(u.get("summon_cd", 0.0)) - delta)
	if float(u.get("summon_cd", 0.0)) > 0.0:
		return
	if String(u.get("combat_state", "")) != "attacking":
		return
	if randf() >= WARLOCK_SUMMON_CHANCE * delta:
		return
	var faction: String = String(u.get("faction", ""))
	var town_id: int = int(u.get("town_id", -1))
	# Summons respect the population caps (HTML POPCAP11 guard).
	if _gs.spawner.check_spawn(faction, "ranger", town_id) != "ok":
		return
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var s: Dictionary = _gs.spawner.spawn_unit(faction, "ranger", town_id,
		upos + Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0)))
	if s.is_empty():
		return
	s["hp"] = SPIRIT_HP
	s["max_hp"] = SPIRIT_HP
	s["dmg"] = SPIRIT_DMG
	s["range"] = SPIRIT_RANGE
	s["is_summon"] = true
	s["summon_life"] = SPIRIT_LIFE
	s["name"] = "Spirit"
	u["summon_cd"] = WARLOCK_SUMMON_CD


## Warlord aura pulse (HTML warlordAuraPulse61): 1 s pulse marks
## same-faction allies within 320 px; they hit x1.25 for 3 s.
func _tick_warlord_aura(u: Dictionary, delta: float) -> void:
	u["aura_pulse_t"] = float(u.get("aura_pulse_t", 0.0)) - delta
	if float(u.get("aura_pulse_t", 0.0)) > 0.0:
		return
	u["aura_pulse_t"] = WARLORD_AURA_PULSE
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var faction: String = String(u.get("faction", ""))
	var r2: float = WARLORD_AURA_RADIUS * WARLORD_AURA_RADIUS
	for o: Dictionary in _gs.units:
		if o == u or not o.get("alive", false) or bool(o.get("downed", false)):
			continue
		if String(o.get("faction", "")) != faction:
			continue
		if upos.distance_squared_to(o.get("position", Vector2.ZERO)) < r2:
			o["aura61"] = WARLORD_AURA_TIME
