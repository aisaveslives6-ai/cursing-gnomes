class_name DisasterSim
extends RefCounted
## Cursing Gnomes — disaster simulation (Milestone 4: combat & disasters).
##
## Wildfire + the HTML build's joke-disaster roster, ported as design
## (not code):
##   - FIRE: grid-free fire records {position, intensity}. Spreads to nearby
##     trees, damages units/buildings in radius, burns out over time.
##     Firefighters auto-dispatch and extinguish; far dispatches ride the
##     fire truck (abstracted as rapid response speed — Jeremy's
##     "fire trucks dispatch autonomously").
##   - GIANT ASS: 1200 HP, 55 dmg smasher. Rampages on a budget (~150 s),
##     then heads for the nearest map edge and leaves (HTML: "Giant Ass
##     disaster times out and leaves after its rampage").
##   - THICC MOOSE: 800 HP, 0 dmg — harassment only. Wanders town to town,
##     moons 3 halls, then leaves.
##   - BANDIT RAID: 5-8 raiders attack the nearest town (HTML BanditRaid
##     "Smaller, weaker pack": const n = 5 + Math.floor(Math.random() * 4)).
##   - GIANT LIZARD: smaller ass (900 HP, 40 dmg, 120 s budget).
##   - ROGUE WIZARD: hostile spellcaster, 90 s visit.
##   - CARDBOARD CAT: wanders, menaces nothing, leaves after 60 s.
##   - VOLCANO: timer-driven TERRAIN event (never on the calendar). Every
##     10-25 min an eruption forges 4-6 volcanic peaks (unmineable,
##     unattackable ground that hardens into minable mineral deposits after
##     5-8 min), shoves nearby units clear, and seeds fires at the blast
##     points. Max 10 sites. No pre-eruption warning in the HTML — it is
##     announced when the mountains form.
##
## Monsters bypass the spawner (they're not citizens) via add_unit directly;
## they're faction "monster", hostile to everyone, and don't count against
## town caps (town_id -1 = countryside). Only one giant ass / one moose at
## a time (HTML rule).
##
## PERFORMANCE: fire spread ticks at 2 Hz via accumulator; monster AI is a
## handful of records; fire cap 80.
##
## Pure logic — no rendering, no input, no audio.


const FIRE_TICK := 0.5          # fire spread/damage ticks at 2 Hz
const FIRE_CAP := 80            # max simultaneous fire records
const FIRE_SPREAD_RADIUS := 90.0
const FIRE_DAMAGE_RADIUS := 70.0
const EXTINGUISH_RATE := 30.0   # firefighter intensity/sec
const EXTINGUISH_RANGE := 70.0
const FIREFIGHTER_SPEED := 95.0
const TRUCK_SPEED := 210.0       # legacy fallback walk-boost (no truck)
const TRUCK_MIN_DIST := 400.0    # dispatches beyond this ride the truck
const TRUCK_BOARD_RANGE := 30.0  # walk-to range for mounting the truck
## Jeremy 2026-10-10 fire-truck dispatch: station lot spot (SE of the hall).
const TRUCK_LOT_OFFSET := Vector2(54.0, 36.0)

const MONSTER_FACTION := "monster"

## Jeremy 2026-10-07 (wake audio lane): wildfire ignition SFX throttle.
## ignite() runs from volcano blasts, spread ticks (2 Hz), and arson —
## cap at 4 "fire" sounds per 1 s game-time bucket.
const SFX_FIRE_BUCKET := 1.0
const SFX_FIRE_PER_BUCKET := 4
var _sfx_fire_bucket := -1
var _sfx_fire_n := 0

## HTML parity (scareNearby): the thicc moose screams on a cooldown while
## active, panicking nearby civilians. While mooning a hall the scare is big
## (220px, +35 stress, 1.2s scream); while traveling between halls it is
## smaller (140px, +18 stress, 2.0s scream). Speech stays with the hearsay
## moose_mooned reactions so the scream does not double-shout over them.
const MOOSE_SCARE_CD_MOON := 1.2
const MOOSE_SCARE_CD_WANDER := 2.0
const MOOSE_SCARE_BIG_RADIUS := 220.0
const MOOSE_SCARE_RADIUS := 140.0

## Monster archetypes: {hp, dmg, speed, budget (s), desc}.
const MONSTERS := {
	"giant_ass":    {"hp": 1200.0, "dmg": 55.0, "speed": 70.0,
		"budget": 150.0, "desc": "A colossal rear approaches."},
	"thicc_moose": {"hp": 800.0,  "dmg": 0.0,  "speed": 110.0,
		"budget": 240.0, "desc": "It moons your villages."},
	"giant_lizard": {"hp": 900.0,  "dmg": 40.0, "speed": 85.0,
		"budget": 120.0, "desc": "A big lizard with big opinions."},
	"rogue_wizard": {"hp": 200.0,  "dmg": 26.0, "speed": 80.0,
		"budget": 90.0,  "desc": "A wizard gone feral."},
	"cardboard_cat": {"hp": 300.0, "dmg": 0.0,  "speed": 60.0,
		"budget": 60.0,  "desc": "It sits in a box. Menacingly."},
	"count_bastard": {"hp": 600.0,  "dmg": 0.0,  "speed": 120.0,
		"budget": 150.0, "desc": "Hide your self-esteem."},
	## Jeremy 2026-10-04 (massive-dev): HOA KAREN — an original disaster in
	## the Nasty Monastery spirit. She flies in on a broom, orbits the
	## richest town, and issues citations: gold fines per citation, and at 3
	## citations the building is LIENED (production paused) until she leaves
	## or is slain. She never fights back (dmg 0) — she just keeps citing.
	## Slaying her refunds the fines she collected.
	"hoa_karen": {"hp": 700.0, "dmg": 0.0, "speed": 95.0,
		"budget": 180.0, "desc": "She'd like to speak to your manager."},
	## Jeremy 2026-10-04: JESUS — he shows up randomly, walks across the
	## map firing a sawn-off shotgun while smoking a cigarette. Singleton.
	## High damage shotgun blasts with splash; leaves at the far edge.
	"jesus": {"hp": 500.0, "dmg": 35.0, "speed": 85.0,
		"budget": 150.0, "desc": "He's back. He's armed."},
	## Jeremy 2026-10-07 (wake deep-disasters): SEAGULL SWARM — a furious
	## flock that descends on the town with the most food buildings, steals
	## food from the faction stockpile, and craps on buildings (crapped
	## buildings stress nearby citizens until it wears off). Harassment
	## only, like the moose. Singleton.
	"seagull_swarm": {"hp": 350.0, "dmg": 0.0, "speed": 150.0,
		"budget": 150.0, "desc": "They want your chips."},
	## Jeremy 2026-10-07 (wake deep-disasters): THE TAXMAN — a humorless
	## auditor who plants himself at the richest faction's hall and
	## garnishes a cut of the treasury on a timer. Slaying him ends the
	## audit (hero headline). Singleton.
	"taxman": {"hp": 400.0, "dmg": 0.0, "speed": 70.0,
		"budget": 180.0, "desc": "He's here about your back taxes."},
	## Jeremy 2026-10-07 (wake deep-disasters): BOOZE OOZE — a sentient
	## beer puddle that oozes town to town throwing an involuntary party:
	## citizens in radius get their stress wiped (bliss) and the ooze
	## shouts party lines. 0 dmg. Singleton.
	"booze_ooze": {"hp": 500.0, "dmg": 0.0, "speed": 55.0,
		"budget": 150.0, "desc": "Baron von Foam, a sentient beer puddle. Party!"},
	## Wake rapid-iteration 2026-10-07: THE DOOM PROPHET — a wild-eyed
	## gnome with a "THE END IS NIGH" sign. Marches to the most populous
	## town and doom-preaches: citizens in radius gain stress (dread) and
	## he shouts his lines. He's a coward — any military unit closing in
	## sends him fleeing, screaming, for the map edge. When his predicted
	## doomsday passes uneventfully he leaves in shame. 0 dmg. Singleton.
	"doom_prophet": {"hp": 300.0, "dmg": 0.0, "speed": 75.0,
		"budget": 150.0, "desc": "The end is nigh. Probably Tuesday."},
	## Wake 2026-10-07: THE GIG GNOME — a delivery gnome with an
	## insulated bag who circles the most populous town, forever "8 stops
	## away". Citizens nearby gain delivery-anxiety stress; every 45s he
	## skims a flat delivery fee from the town's faction treasury. Like
	## the prophet he's a coward: a soldier closing in makes him drop a
	## refunded tip and speed off, marking the order "delivered". 0 dmg.
	## Singleton.
	"gig_gnome": {"hp": 400.0, "dmg": 0.0, "speed": 95.0,
		"budget": 180.0, "desc": "Your package is 8 stops away."},
	## Wake 2026-10-08: BILL THE BORG CRAB — a cybernetic crab (original
	## design, Borg-inspired but not a copy) who scuttles in from the map
	## edge and "assimilates" town technology: he bolts useless cybernetic
	## attachments onto buildings (a toaster on the town hall, a USB port
	## on the farm). Assimilated buildings run at -15% efficiency and the
	## occupants complain. He never destroys anything — he's "helping".
	## A soldier closing in makes him eject his cybernetics and scuttle
	## off; slain, the upgrades pop off too. 0 dmg. Singleton.
	"borg_crab_bill": {"hp": 500.0, "dmg": 0.0, "speed": 85.0,
		"budget": 240.0, "desc": "We are Bill. Your toaster will be assimilated."},
	## Wake rapid-iteration 2026-10-08: TWISTER SISTER — a sentient
	## glam-metal tornado. Wanders town to town flinging citizens to
	## random spots (displacement chaos — no other disaster displaces)
	## and ripping roofs off buildings in her path. She can't be
	## reasoned with; she leaves when her set ends. Singleton.
	"twister_sister": {"hp": 900.0, "dmg": 10.0, "speed": 115.0,
		"budget": 170.0, "desc": "She's not gonna take your roof. She's TAKING it."},
	## Wake rapid-iteration 2026-10-08: BRAX THE KARAOKE BARBARIAN — a
	## loinclothed barbarian who drags a lute to the town hall and
	## performs power ballads. 0 dmg; the weapon is his voice: citizens
	## in earshot gain secondhand-embarrassment stress, and a few can't
	## resist joining as backup singers (morale up, dignity down). A
	## soldier closing in boos him off stage; when all 47 verses are
	## sung he takes a bow and leaves. Singleton.
	"karaoke_barbarian": {"hp": 600.0, "dmg": 0.0, "speed": 80.0,
		"budget": 210.0, "desc": "He only knows one song. It has 47 verses."},
	## Wake rapid-iteration 2026-10-08: YAPPER THE GOSSIP GNOME — a
	## chibi gnome with a giant brass ear trumpet and a quill who waddles
	## town to town SEEDING REAL HEARSAY RUMORS about citizens via the
	## rumor mill (no other disaster weaponizes gossip). 0 dmg, a coward:
	## a soldier closing in makes him drop the quill and leg it.
	## Singleton.
	"gossip_gnome": {"hp": 450.0, "dmg": 0.0, "speed": 90.0,
		"budget": 180.0, "desc": "He knows what you did."},
	## Wally the Warranty Salesman (wake rapid-iteration 2026-10-08):
	## chibi gnome in a cheap suit with a briefcase full of "extended
	## warranties". Goes door to door pitching buildings; a sale costs the
	## faction gold and covers absolutely nothing. 0 dmg, a coward: a
	## soldier closing in gets a "FINE! No warranty for YOU!" and a sprint.
	## Singleton.
	"warranty_salesman": {"hp": 400.0, "dmg": 0.0, "speed": 85.0,
		"budget": 180.0, "desc": "Your hut's warranty is EXPIRED."},
	## Milo the Doomscroller (massive-dev 2026-10-08): a chibi gnome
	## with glazed eyes and a glowing phone who shuffles town to town.
	## 0 dmg; the weapon is the feed: citizens in screen-glow range stop
	## working and stare at their own phones (doomscrolling), mood
	## rotting slowly. A soldier closing in yells "TOUCH GRASS" and he
	## flees; when the battery dies he panics for the nearest charger
	## (the map edge). Singleton.
	"doomscroller": {"hp": 500.0, "dmg": 0.0, "speed": 55.0,
		"budget": 200.0, "desc": "He's seen every video. He remembers none of them."},
	## Chad the MLM Bro (dedicated-porting 2026-10-08): a chibi gnome in a
	## cheap navy suit with a briefcase full of "opportunity" and a blinding
	## white grin. 0 dmg; the weapon is the pitch: citizens in range get
	## recruited into his downline (hustling flag, honored by WorkerAI),
	## pay a starter-kit fee out of the faction treasury, and recruit their
	## neighbors — a pyramid scheme that walks. Soldiers see through the
	## pitch; market saturation sends him home. Singleton.
	"mlm_bro": {"hp": 500.0, "dmg": 0.0, "speed": 75.0,
		"budget": 200.0, "desc": "It's NOT a pyramid scheme. It's a reverse funnel system."},
	## Dave the DMV Clerk (wake rapid-iteration 2026-10-08): a surly chibi
	## gnome in a grey cardigan who wheels a folding table into the town
	## square and opens an unauthorized DMV branch. 0 dmg; the weapon is
	## the queue: citizens in range take a number and WAIT IN LINE
	## (waiting_in_line flag, honored by WorkerAI) instead of working.
	## Dave serves one ticket at a time (slowly), skims a processing fee,
	## and closes for lunch. Soldiers shut him down on sight. Singleton.
	"dmv_clerk": {"hp": 500.0, "dmg": 0.0, "speed": 70.0,
		"budget": 200.0, "desc": "Take a number. The number is 847. Now serving 3."},
	## Kyle the CrossFit Gnome (massive-dev 2026-10-08): a chibi gnome in a
	## neon tank top and headband who IS the equipment. 0 dmg; the weapon is
	## the WOD: citizens in range do burpees (workouting flag, honored by
	## WorkerAI), draining energy but building swole stacks (slower energy
	## decay via SimUrges). Soldiers win the burpee contest; the timer sends
	## him to leg day. Singleton.
	"crossfit_gnome": {"hp": 500.0, "dmg": 0.0, "speed": 80.0,
		"budget": 200.0, "desc": "He does burpees. You do burpees. Everybody does burpees."},
	## Vicky the Influencer (dedicated-porting 2026-10-08 — original content):
	## a chibi gnome girl with a ring light and selfie stick. 0 dmg; the
	## weapon is CLOUT: citizens in range stop working to gawk and pose for
	## her stream (gawking flag, honored by WorkerAI). Every gawker feeds
	## her viral meter; at 100 she GOES VIRAL (Gazette). Soldiers confiscate
	## the ring light; the timer gets her canceled. Singleton.
	"influencer_gnome": {"hp": 500.0, "dmg": 0.0, "speed": 80.0,
		"budget": 200.0, "desc": "Like and subscribe. The ring light is non-negotiable."},
	## Prince Gnomba (wake deep-work 2026-10-08 — original content): a
	## Nigerian-prince email scammer in gnome form. 0 dmg; the weapon is
	## CONFIDENCE. He DMs the ruler a 100%-legitimate treasury-unlock
	## proposal (inline Send 500g / Block buttons in Messenger) while his
	## aura skims "processing fees" off the town's treasury. Send the gold
	## and he might double it — or rug. Singleton.
	"prince_gnomba": {"hp": 500.0, "dmg": 0.0, "speed": 80.0,
		"budget": 200.0, "desc": "GREETINGS DEAR RULER. I am a prince. This is legitimate."},
	## DJ Weddington (massive-dev 2026-10-08 — original content): an
	## unbooked wedding DJ — the wedding got canceled but he kept the
	## deposit AND the gear, so the town square is now a dance floor.
	## 0 dmg; the weapon is THE DROP. Citizens stop working to dance;
	## dancers feed the hype meter; soldiers confiscate the turntables.
	"dj_weddington": {"hp": 500.0, "dmg": 0.0, "speed": 80.0,
		"budget": 200.0, "desc": "The wedding was canceled. The party was not. FEEL THE DROP."},
	## Ricky the Repo Gnome (dedicated-porting 2026-10-08 — original
	## content): a repo man with a tiny tow truck. He hooks the fanciest
	## non-essential building in town and drags it to the map edge. 0 dmg;
	## the weapon is REPOSSESSION. Soldiers impound the tow truck.
	"repo_gnome": {"hp": 500.0, "dmg": 0.0, "speed": 95.0,
		"budget": 240.0, "desc": "He's here for the loveseat. And the house. And the tiny tow truck is already warmed up."},
	## Milo the Podcast Bro (rapid-iteration 2026-10-08 — original
	## content, Disaster #29). Rolls into the most populous town with a
	## folding table, two giant mics and a ring light, flips the ON AIR
	## sign, and records THE MILO EXPERIENCE live from the square. 0 dmg;
	## the weapon is ENGAGEMENT — citizens in range stop working to queue
	## as guests (podcasting flag, honored by WorkerAI.tick_unit), feeding
	## the download counter (cap 10k; 1k shout, 5k Gazette, 10k viral).
	## Interactive like Prince Gnomba: he DMs the ruler a sponsor pitch —
	## [Sponsor 300g] hypes the town and he leaves to "edit"; [Unplug]
	## cancels the podcast and the guests go back to work. A soldier who
	## closes in confiscates the mics (deplatformed); the visit timer ends
	## the episode ("that's a wrap"). Singleton.
	"podcast_bro": {"hp": 450.0, "dmg": 0.0, "speed": 75.0,
		"budget": 180.0, "desc": "He's live. You're the content. Smash that subscribe."},
}

## HOA Karen tuning (Jeremy 2026-10-04 co-owner design — original content,
## not an HTML port; the HTML has no HOA).
const KAREN_CITE_INTERVAL := 12.0   # seconds between citations
const KAREN_FINE_MIN := 15.0        # gold per citation
const KAREN_FINE_MAX := 40.0
const KAREN_LIEN_AT := 3            # citations before a building is liened
const KAREN_ORBIT_RADIUS := 150.0   # orbit distance around the town hall
const KAREN_DAILY_CHANCE := 0.02    # rare natural visit, like the priest
const KAREN_MIN_DAY := 10
## Citation one-liners she shouts (speech bubble) while citing.
const KAREN_CITATIONS := [
	"Your grass is 0.3 inches over regulation. FINE.",
	"That gnome is a non-compliant color. $25.",
	"Mailbox insufficiently beige. $40.",
	"Trash cans visible from the street. $35.",
	"Unregistered emotional-support dragon. $50.",
	"Your wall is 2 inches too tall. TEAR IT DOWN. Also, fine.",
	"Curtains open after 8pm. The neighbors can SEE you.",
	"That roof is not an approved shade of thatch.",
	"Lawn gnomes must face the street. Yours face EACH OTHER.",
	"Your barbican lacks a permit. And a personality.",
]
## Wake rapid-iteration 2026-10-07: KAREN GRISTLETHWAITE flesh-out — the
## thinnest named disaster gets the Zorblax treatment. She never fights
## back (dmg 0 by design) — she fines. Attacking her files an ASSAULT
## COMPLAINT: a non-refundable surcharge on the attacker's faction, so
## evicting her 700 HP is an economic decision. Citation fines escalate
## the longer she stays (repeat-offender schedule); she cites citizens
## too, not just buildings; and she demands to speak to the ruler.
const KAREN_NAME := "Karen Gristlethwaite"
const KAREN_ASSAULT_FINE := 25.0    # flat surcharge per assault complaint
const KAREN_ASSAULT_CD := 8.0       # seconds between complaints
const KAREN_ASSAULT_RADIUS := 600.0 # nearest soldier = presumed attacker
const KAREN_FINE_ESCALATION := 0.10 # +10% fine per citation this visit
const KAREN_FINE_MULT_CAP := 3.0    # escalation ceiling
const KAREN_UNIT_CITE_CHANCE := 0.30
const KAREN_UNIT_FINE_MIN := 5.0
const KAREN_UNIT_FINE_MAX := 15.0
const KAREN_UNIT_CITE_RADIUS := 400.0
const KAREN_DEMAND_INTERVAL := 45.0  # seconds between ruler demands
const KAREN_ARRIVE_LINES := [
	"I'm Karen Gristlethwaite, HOA PRESIDENT, and this neighborhood is a DISGRACE.",
	"Which one of you is in charge here? I have a clipboard and I'm not afraid to use it.",
	"I pay dues in THREE neighborhoods. This one needs the most work.",
]
const KAREN_ASSAULT_LINES := [
	"ASSAULT! That's a $25 surcharge and I'm telling the board!",
	"You TOUCHED me! This is going on the permanent complaint!",
	"My lawyer flies faster than this broom, pal.",
	"VIOLENCE is a covenant violation! $25!",
]
const KAREN_UNIT_CITATIONS := [
	"Your tunic is NOT an approved color.",
	"That beard violates Section 4, Paragraph 2.",
	"Loitering. In your OWN town. Bold.",
	"Your posture is lowering property values.",
	"Unlicensed breathing near a common area.",
	"Those boots have seen MUD. I can tell.",
	"Smiling without a permit.",
	"Your aura clashes with the neighborhood palette.",
]
const KAREN_DEMAND_LINES := [
	"I DEMAND to speak to the RULER of this town!",
	"Fetch me your manager. The BIG one. The one with the crown.",
	"I've been citing for a full minute and NO ONE has groveled yet!",
]
const KAREN_HALL_LINES := [
	"I'm citing the HALL ITSELF. Nobody is above the covenants.",
	"Even the seat of power needs a permit for that roofline.",
]

## HTML BanditRaid parity (fix79, "Smaller, weaker pack"):
##   const n = 5 + Math.floor(Math.random() * 4); // 5-8
const BANDIT_COUNT_MIN := 5
const BANDIT_COUNT_MAX := 8

## Monthly disaster forecast (HTML generateDisasterCalendar parity):
## one of each major disaster on distinct days 3-27 of the month;
## the rogue wizard only answers the calendar's call ~3 months in 10.
const FORECAST_EVENTS := [
	{"type": "bandit_raid",   "label": "Bandit Raid"},
	{"type": "giant_ass",     "label": "Giant Ass"},
	{"type": "thicc_moose",   "label": "Thicc Moose"},
	{"type": "giant_lizard",  "label": "Giant Lizard"},
	{"type": "cardboard_cat", "label": "Real Cat"},
	{"type": "count_bastard",  "label": "Count Bastard"},
]
const FORECAST_WIZARD := {"type": "rogue_wizard", "label": "Rogue Wizard"}
const FORECAST_DAY_MIN := 3
const FORECAST_DAY_MAX := 27
const FORECAST_WIZARD_CHANCE := 0.3
## Forecast disasters fire around mid-day (HTML: timeOfDay 10-16), once.
const FORECAST_HOUR_MIN := 10.0
const FORECAST_HOUR_MAX := 16.0

## Volcano (HTML VOLCANO80/91, verbatim numbers): a timer-driven terrain
## event — never on the monthly calendar. Eruptions forge REAL terrain:
## 4-6 volcanic peaks around a raised vent, unmineable and unattackable
## until they harden into mineral deposits.
const VOLCANO_PERIOD_MIN := 600.0   # 10 min between eruptions
const VOLCANO_PERIOD_MAX := 1500.0  # 600 + rand*900 -> up to 25 min
const VOLCANO_MAX_SITES := 10
const VOLCANO_RADIUS := 280.0       # eruption radius / height-edit radius
const VOLCANO_PEAK_ELEV := 0.26     # height-edit peak (HTML cgHeightEdits)
const VOLCANO_EDGE_MARGIN := 240.0  # site must clear the map edge
const VOLCANO_HALL_DIST := 380.0    # site must clear any town hall
const VOLCANO_SHOVE_INNER := 180.0  # units inside this get shoved...
const VOLCANO_SHOVE_OUT := 200.0    # ...out to this distance
const VOLCANO_PEAKS_MIN := 4        # 4 + floor(rand*3) -> 4-6 peaks
const VOLCANO_PEAKS_EXTRA := 3
const VOLCANO_HARDEN_MIN := 300.0   # 5 min: peaks start hardening...
const VOLCANO_HARDEN_MAX := 480.0   # ...by 8 min
const VOLCANO_MINERALS: Array[String] = ["crystal", "gold", "silver",
	"iron", "stone"]
## HTML seedFire intensities run 0-3; Godot ignite() runs 0-100. Mortar
## blasts seed 1.4 (-> ~47) plus a 0.63 (-> ~21) side fire.
const VOLCANO_BLAST_INTENSITY := 47.0
const VOLCANO_BLAST_SIDE_INTENSITY := 21.0

## Jeremy 2026-10-04: THE NASTY MONASTERY — Father Filthwick opens a
## monastery in a random town, then bursts out screaming about boobies.
## Brand-new disaster designed by Jeremy (not in the HTML).
const NASTY_PRIEST_JOB := "nasty_priest"
const NASTY_PRIEST_DAILY_CHANCE := 0.05   # 5% per day
const NASTY_PRIEST_BURST_MIN := 40.0      # seconds between outbursts
const NASTY_PRIEST_BURST_MAX := 100.0
const NASTY_PRIEST_MAX_BURSTS := 6        # leaves after this many outbursts
const NASTY_PRIEST_BUDGET := 420.0        # ...or after 7 min, whichever first
const NASTY_PRIEST_REACT_RANGE := 320.0
const NASTY_PRIEST_REACT_CHANCE := 0.45
const NASTY_PRIEST_MONASTERY_DIST := 160.0  # monastery offset from town hall

var _priest_day: int = 1  # last day the nasty-priest roll ran
var _karen_day: int = -1  # last day the HOA-karen roll ran
var _jesus_day: int = -1  # last day the jesus roll ran
var _gull_day: int = -1  # last day the seagull-swarm roll ran
var _tax_day: int = -1  # last day the taxman roll ran
var _ooze_day: int = -1  # last day the booze-ooze roll ran
var _prophet_day: int = -1  # last day the doom-prophet roll ran
var _driver_day: int = -1   # last day the spark-driver roll ran
var _borg_day: int = -1     # last day the borg-crab roll ran
# Jeremy 2026-10-04: monster cache — stagger the per-frame full-unit scan.
# Monsters are 0-5 units; scanning all 240 every frame (14,400/s) to find
# them is wasteful. Rescan every 0.5s, tick from cache every frame.
var _monster_cache: Array[int] = []
var _monster_scan_accum := 0.0
const MONSTER_SCAN_INTERVAL := 0.5
## Jeremy 2026-10-07 (wake deep-systems): COUNT BASTARD, fleshed out.
## He no longer shouts generic town taunts into the void — he singles out
## INDIVIDUAL citizens by name and roasts them personally, and they react
## in personality-matched ways (Jeremy 2026-10-06 brief: NPCs get enraged
## or laugh depending on how they feel about the target):
##   - proud / haughty -> ENRAGED: anger, a thrown punch (real damage via
##     SimCombat — he has 600 HP and 0 dmg, so he never fights back, he
##     just keeps talking), a shouted comeback.
##   - jolly / very friendly -> LAUGHS IT OFF: amusement, a laugh line.
##   - cowardly (brave < 0.3) / worried -> COWERS: fear, a whimper.
##   - very violent -> punches him too (bar-brawl instinct).
##   - everyone else -> ANNOYED: a grumbled comeback.
## Punches are the counter-play: enough of them slays him. Insults spread
## as hearsay rumors; slaying him makes the Gazette and lifts town mood.
## Tokens: {name} {job} {town}.
const COUNT_BASTARD_TAUNTS: Array[String] = [
	"Your walls look like shit and so do you!",
	"I've seen goblins with better urban planning!",
	"This town smells like feet and bad decisions!",
	"Nice houses. Be a shame if someone JUDGED them!",
	"Your mayor's hat is stupid and so is your face!",
	"Your roads go nowhere, like your ambitions!",
	"I pay more in hat tax than your whole treasury holds!",
	"Even the thicc moose moons this place IRONICALLY!",
	"Call that a town?! I've sneezed bigger!",
	"Your guards couldn't stop a determined hamster!",
	"This place has the Feng Shui of a garbage fire!",
	"I'm not lost — I'm just disappointed to be here!",
	"Your farms grow nothing but regret!",
	"I'd conquer this dump but it's not worth the paperwork!",
]
## Personal insults, picked by the victim's traits (SimPersonality).
const BASTARD_INSULT_PROUD: Array[String] = [
	"{name}, that posture! You walk like the ground owes YOU an apology.",
	"I've seen better cheekbones on a soup tureen, {name}.",
	"{name}, you have the bearing of minor royalty and the talent of minor mold.",
	"That {job} sash, {name}? Participation trophy, darling.",
	"{name}, your nose could open letters. Sealed ones.",
	"Pride? {name}, you couldn't afford it — I checked.",
]
const BASTARD_INSULT_DILIGENT: Array[String] = [
	"{name}, I've seen glaciers with a better work ethic.",
	"You call that {job} work? The guild wants its tools back, {name}.",
	"{name}, even the mules filed a grievance about your pace.",
	"Hard worker? {name}, the sun sets faster than you finish.",
]
const BASTARD_INSULT_COWARD: Array[String] = [
	"{name}, you'd lose a staring contest with your own shadow.",
	"Brave? {name}, I've seen braver puddles.",
	"{name}, your knees knock louder than the town bell.",
]
const BASTARD_INSULT_FRIENDLY: Array[String] = [
	"{name}, smiling at me? Your friends told me EVERYTHING.",
	"So friendly, {name}. The knives behind your back are showing.",
	"{name}, you'd compliment a hangman on his knotwork.",
]
const BASTARD_INSULT_CRUDE: Array[String] = [
	"{name}, you smell like a tavern floor at closing time.",
	"Bathed recently, {name}? The river sent its condolences.",
	"{name}, your boots have a restraining order against your feet.",
]
const BASTARD_INSULT_GENERIC: Array[String] = [
	"{name}, your mother sews better comebacks than you'll ever speak.",
	"Intelligence called, {name} — it wants nothing to do with you.",
	"{name}, I've met rocks with stronger opinions.",
	"That haircut, {name}. Bold. Wrong, but bold.",
	"{name}, the village idiot just asked for his job back.",
	"You have the charisma of a damp sock, {name}.",
	"{name}, if ugly were a currency you'd fund the treasury.",
	"I'd insult your {job} skills, {name}, but I can't find any.",
]
const BASTARD_COMEBACKS_ANGRY: Array[String] = [
	"SAY THAT TO MY FIST, COUNT!",
	"My {job} hands will redecorate your face!",
	"Come down from that cape and say it slower!",
	"I'LL KNOCK THAT MONOCLE INTO NEXT WEEK!",
]
const BASTARD_COMEBACKS_ANNOYED: Array[String] = [
	"Oh, piss off.",
	"Bite me, Count.",
	"Your cape's last season.",
	"Nobody asked you.",
	"Tell it to the moose.",
]
const BASTARD_LAUGHS: Array[String] = [
	"HA! Good one, Count!",
	"He's got me there!",
	"Oh, that's rich!",
	"*wheezing* Say the sock one again!",
]
const BASTARD_WHIMPERS: Array[String] = [
	"P-please don't hurt me...",
	"I'm sorry! I'm sorry!",
	"*whimpers*",
	"Why is he looking at ME?!",
]
const BASTARD_INSULT_CD := 3.5        # seconds between personal insults
const BASTARD_VICTIM_RADIUS := 260.0  # roast range around him
const BASTARD_PUNCH_MIN := 3.0
const BASTARD_PUNCH_MAX := 7.0
const BASTARD_RUMOR_EVERY := 3        # seed a hearsay rumor every N insults


var _gs: GameState
var _combat: SimCombat
var fires: Array[Dictionary] = []  # fire records
var _next_fire_id: int = 1
## Jeremy 2026-10-05: shared wildfire ledger record. ignite() opens one
## "wildfire" DisasterLog record (reused while any fire burns) so burn
## deaths reach the ledger and the Gazette's Disaster Desk; without it,
## attribute_death() could never match a fire death to a record and the
## wildfire toll was always 0. -1 = no record open.
var _wildfire_log_id: int = -1
var _fire_accum: float = 0.0
var _ambient_accum: float = 0.0  # drunk/hangover decay cadence (0.5 s)
var world_bounds := Rect2(Vector2.ZERO, Vector2(4096, 4096))
## Monthly forecast: day-of-month -> {type, label, done} (HTML disasterCalendar).
var forecast: Dictionary = {}
var _last_day: int = 1
## Volcano state: countdown + site records
## {position, radius, peak, born, peak_ids (work-site ids)}.
var volcano_sites: Array[Dictionary] = []
var volcano_timer: float = 0.0
var _volcano_accum: float = 0.0  # hardening checks run at 1 Hz
## Jeremy 2026-10-04: disaster tracking ledger — towns entered, death
## tolls, military/citizen orders. Feeds the Gazette + calendar panel.
var dlog: DisasterLog


func _init(game_state: GameState, combat: SimCombat) -> void:
	_gs = game_state
	_combat = combat
	dlog = DisasterLog.new()
	# New-game parity: the HTML sets the eruption timer on every new game.
	volcano_timer = randf_range(VOLCANO_PERIOD_MIN, VOLCANO_PERIOD_MAX)
	# Jeremy 2026-10-04: generate the forecast calendar on new game —
	# process_calendar_disasters() only regenerates on month rollover, and
	# _last_day starts at 1, so a fresh game starting day 1 never got a
	# forecast (Disasters menu showed "No disasters forecast" forever).
	generate_disaster_calendar()


func setup_bounds(bounds: Rect2) -> void:
	world_bounds = bounds


## ---- fire --------------------------------------------------------------


## Jeremy 2026-10-07 (wake graphics-hourly): disaster arrival fanfare.
## Monster/volcano/raid arrivals were silent — every arrival now gets a
## spatial stinger at the entry point.
## 2026-10-07 (wake graphics-hourly): every NAMED disaster gets its own
## signature sting (they all shared the generic "boom"). Pure mapping so
## tests can pin it; _arrival_sfx stays the single emission choke point.
static func stinger_for_kind(kind: String) -> String:
	match kind:
		"volcano":
			return "explode"
		"bandit_raid":
			return "war_horn"
		"hoa_karen":
			return "karen_arrive"
		"rogue_wizard":
			return "wizard_arrive"
		"count_bastard":
			return "bastard_arrive"
		"borg_crab_bill":
			return "borg_arrive"
		"twister_sister":
			return "twister_arrive"
		"gig_gnome":
			return "gig_arrive"
		"doom_prophet":
			return "prophet_arrive"
		"taxman":
			return "taxman_arrive"
		"booze_ooze":
			return "ooze_arrive"
		"seagull_swarm":
			return "gull_arrive"
		"thicc_moose":
			return "moose_arrive"
		"jesus":
			return "jesus_arrive"
		"giant_ass":
			return "ass_arrive"
		"giant_lizard":
			return "lizard_arrive"
		"cardboard_cat":
			return "cat_arrive"
		"karaoke_barbarian":
			return "karaoke_arrive"
		"gossip_gnome":
			return "gossip_arrive"
		"doomscroller":
			return "doom_arrive"
		"warranty_salesman":
			return "warranty_arrive"
		"mlm_bro":
			return "mlm_arrive"
		"dmv_clerk":
			return "dmv_arrive"
		"crossfit_gnome":
			return "crossfit_arrive"
		"influencer_gnome":
			return "influencer_arrive"
		"prince_gnomba":
			return "gnomba_arrive"
		"dj_weddington":
			return "dj_arrive"
		"repo_gnome":
			return "repo_arrive"
		"podcast_bro":
			return "podcast_arrive"
	return "boom"


func _arrival_sfx(kind: String, pos: Vector2) -> void:
	_gs.bus.sfx_spatial.emit(stinger_for_kind(kind), pos, Vector2.ZERO)


## Starts a fire at a position. Returns the record ({} if at the cap).
func ignite(pos: Vector2, intensity: float = 60.0) -> Dictionary:
	if fires.size() >= FIRE_CAP:
		return {}
	var f: Dictionary = {
		"id": _next_fire_id,
		"position": pos,
		"intensity": clampf(intensity, 1.0, 100.0),
		"radius": FIRE_DAMAGE_RADIUS,
		"born": _gs.game_time,
	}
	_next_fire_id += 1
	fires.append(f)
	_gs.bus.fire_started.emit(f)
	# Jeremy 2026-10-07 (wake audio lane): ignition whoosh, throttled —
	# volcano blasts and spread ticks can light several fires at once.
	var fbucket: int = int(_gs.game_time / SFX_FIRE_BUCKET)
	if fbucket != _sfx_fire_bucket:
		_sfx_fire_bucket = fbucket
		_sfx_fire_n = 0
	if _sfx_fire_n < SFX_FIRE_PER_BUCKET:
		_sfx_fire_n += 1
		_gs.bus.sfx_spatial.emit("fire", pos, Vector2.ZERO)
	_open_wildfire_record()
	return f


## Opens the shared wildfire ledger record if none is active (all fires
## from one event — nuclear, director, volcano, spread — share it).
func _open_wildfire_record() -> void:
	if dlog == null:
		return
	var rec: Dictionary = dlog.active_for_kind("wildfire")
	if not rec.is_empty():
		_wildfire_log_id = int(rec.get("id", -1))
		return
	_wildfire_log_id = dlog.start_disaster("wildfire",
		_label_for("wildfire"), _gs.day_number, _gs.game_time)


## Closes the wildfire record once the last fire is out. The Gazette
## story only publishes when someone actually died — a scorched tree is
## not news — but the ledger keeps the record either way.
func _close_wildfire_record_if_done() -> void:
	if _wildfire_log_id < 0 or not fires.is_empty():
		return
	if dlog == null:
		_wildfire_log_id = -1
		return
	var rec: Dictionary = dlog.get_record(_wildfire_log_id)
	if rec.is_empty() or String(rec.get("status", "")) != "active":
		_wildfire_log_id = -1
		return
	dlog.end_disaster(_wildfire_log_id, _gs.day_number, "burned_out")
	if dlog.death_toll(_wildfire_log_id) > 0:
		_publish_disaster_story(_wildfire_log_id)
	_wildfire_log_id = -1


## Puts out a fire record immediately.
func extinguish(fire: Dictionary) -> void:
	if fires.has(fire):
		fires.erase(fire)
		_gs.bus.fire_out.emit(int(fire.get("id", 0)))
	_close_wildfire_record_if_done()


func nearest_fire(pos: Vector2, max_dist: float = 1e9) -> Dictionary:
	var best: Dictionary = {}
	var best_d2: float = max_dist * max_dist
	for f: Dictionary in fires:
		var d2: float = pos.distance_squared_to(f.get("position",
			Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = f
	return best


## Firefighter AI: auto-dispatch to the nearest fire, extinguish on
## arrival. Called from the world's AI budget instead of WorkerAI (M3 left
## firefighters parked).
##
## Jeremy 2026-10-10 fire-truck dispatch (direct order): far fires ride a
## REAL firetruck record with driving physics — mount up at the station
## lot, ride to the fire, dismount and fight it, ride back, re-park. The
## old "rapid response speed" abstraction survives only as a fallback when
## no truck record exists (headless tests, missing station).
func tick_firefighter(unit: Dictionary, delta: float) -> void:
	if not unit.get("alive", false):
		return
	var veh = _gs.get("vehicles")
	# Aboard a real truck: the station-truck tick drives; hold still.
	var riding := int(unit.get("truck_id", -1))
	if riding > 0 and veh != null:
		var rtruck: Dictionary = (veh as SimVehicles).vehicle_by_id(riding)
		if not rtruck.is_empty():
			unit["work_state"] = "on_truck"
			unit["on_truck"] = false
			return
		unit["truck_id"] = -1  # truck gone — fall through on foot
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var f: Dictionary = nearest_fire(upos)
	if f.is_empty():
		unit["on_truck"] = false
		_firefighter_return(unit, delta)
		return
	var fpos: Vector2 = f.get("position", Vector2.ZERO)
	var dist: float = upos.distance_to(fpos)
	unit["work_state"] = "to_fire"
	if dist <= EXTINGUISH_RANGE:
		unit["on_truck"] = false
		var inten: float = float(f.get("intensity", 0.0)) \
			- EXTINGUISH_RATE * delta
		f["intensity"] = inten
		unit["work_state"] = "extinguishing"
		# HTML SFX parity (fix79 c59FirefighterSpray -> SFX.hose59 at the
		# unit): the hose hisses while water is applied. Throttled per
		# unit (HTML throttled only the truck at 1.1 s; the 16-voice 2D
		# pool + 5600-unit distance cull make a per-unit 1.1 s gate the
		# performance-safe port of the same trigger).
		var hose_cd: float = float(unit.get("_hose_sfx_cd", 0.0)) - delta
		if hose_cd <= 0.0:
			hose_cd = 1.1
			_gs.bus.sfx_spatial.emit("hose59", upos, Vector2.ZERO)
		unit["_hose_sfx_cd"] = hose_cd
		if inten <= 0.0:
			# HTML SFX parity (fix79 c59OnFireOut -> SFX.hiss59): fire put
			# OUT by water steams. Only on the firefighting put-out —
			# natural burnout (dead-list extinguish below) is silent in
			# the HTML too.
			_gs.bus.sfx_spatial.emit("hiss59", fpos, Vector2.ZERO)
			extinguish(f)
		return
	# Far fire: real truck dispatch.
	var st := _home_station(unit)
	var truck: Dictionary = {}
	if veh != null and not st.is_empty():
		truck = (veh as SimVehicles).vehicle_by_id(
			int(st.get("truck_id", -1)))
	if dist > TRUCK_MIN_DIST and not truck.is_empty():
		var tpos: Vector2 = truck.get("pos", _station_lot(st))
		if upos.distance_to(tpos) <= TRUCK_BOARD_RANGE:
			if (veh as SimVehicles).board_vehicle(int(truck["id"]),
					int(unit.get("id", -1))):
				unit["truck_id"] = int(truck["id"])
				unit["work_state"] = "on_truck"
				unit["on_truck"] = false
		else:
			unit["work_state"] = "to_truck"
			unit["on_truck"] = false
			_walk_to(unit, tpos, FIREFIGHTER_SPEED, delta)
		return
	# Near fire, or no truck record: on-foot response. The legacy speed
	# boost + fake truck visual apply ONLY when no real truck exists.
	unit["on_truck"] = dist > TRUCK_MIN_DIST
	var speed: float = TRUCK_SPEED if dist > TRUCK_MIN_DIST \
		else FIREFIGHTER_SPEED
	_walk_to(unit, fpos, speed, delta)


## No fires: head home. If the station truck is out, walk to it and ride
## back; if it is parked at the lot, idle there (never re-board a parked
## truck — that loops).
func _firefighter_return(unit: Dictionary, delta: float) -> void:
	var veh = _gs.get("vehicles")
	var st := _home_station(unit)
	if veh == null or st.is_empty():
		unit["work_state"] = "idle"
		return
	var tid := int(st.get("truck_id", -1))
	var truck: Dictionary = (veh as SimVehicles).vehicle_by_id(tid)
	if truck.is_empty():
		unit["work_state"] = "idle"
		return
	var lot := _station_lot(st)
	var tpos: Vector2 = truck.get("pos", lot)
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var truck_home: bool = tpos.distance_to(lot) <= TRUCK_BOARD_RANGE \
		and String(truck.get("state", "parked")) == "parked"
	if truck_home:
		unit["work_state"] = "idle"
		if upos.distance_to(lot) > TRUCK_BOARD_RANGE * 2.0:
			_walk_to(unit, lot, FIREFIGHTER_SPEED, delta)
		return
	if upos.distance_to(tpos) <= TRUCK_BOARD_RANGE:
		if (veh as SimVehicles).board_vehicle(tid,
				int(unit.get("id", -1))):
			unit["truck_id"] = tid
			unit["work_state"] = "on_truck"
	else:
		unit["work_state"] = "returning"
		_walk_to(unit, tpos, FIREFIGHTER_SPEED, delta)


## ---- fire-truck dispatch ------------------------------------------------
## Jeremy 2026-10-10 direct order: every complete fire station owns one
## parked firetruck at its lot. Full loop: firefighters mount up at the
## lot, the truck drives to the fire with real physics, they dismount and
## fight it, re-board, the truck drives back and re-parks. Called from the
## world's _process right after game.vehicles.tick(delta).


## All complete fire stations (live buildings only).
func _fire_stations() -> Array:
	var out: Array = []
	for b in _gs.buildings:
		var bd: Dictionary = b
		if String(bd.get("type", "")) != "fire_station":
			continue
		if not bool(bd.get("complete", false)):
			continue
		out.append(bd)
	return out


## The station's parking lot spot — where its truck lives.
func _station_lot(station: Dictionary) -> Vector2:
	return station.get("position", Vector2.ZERO) + TRUCK_LOT_OFFSET


## Nearest complete fire station of the unit's faction.
func _home_station(unit: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d2 := 1e18
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var fac := String(unit.get("faction", ""))
	for st in _fire_stations():
		if String(st.get("faction", "")) != fac:
			continue
		var d2: float = upos.distance_squared_to(
			st.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = st
	return best


## Idempotent: every station gets exactly one live truck; trucks whose
## station is gone release their crew and are despawned.
func _ensure_station_trucks() -> void:
	var veh = _gs.get("vehicles")
	if veh == null:
		return
	var sv := veh as SimVehicles
	for st in _fire_stations():
		var tid := int(st.get("truck_id", -1))
		var truck: Dictionary = sv.vehicle_by_id(tid) if tid > 0 else {}
		if truck.is_empty():
			var nv: Dictionary = sv.spawn_vehicle("firetruck",
				_station_lot(st), String(st.get("faction", "")))
			if not nv.is_empty():
				st["truck_id"] = int(nv["id"])
	for v in sv.vehicles.duplicate():
		if String(v.get("type", "")) != "firetruck":
			continue
		var owned := false
		for st in _fire_stations():
			if int(st.get("truck_id", -1)) == int(v.get("id", -1)):
				owned = true
				break
		if not owned:
			for uid in sv.aboard_ids(int(v.get("id", -1))):
				var u := _gs.get_unit(int(uid))
				if not u.is_empty():
					u["truck_id"] = -1
					u["on_truck"] = false
					u["work_state"] = "idle"
			sv.despawn_vehicle(int(v.get("id", -1)))


## Per-frame station-truck driver. Runs after the vehicle physics tick.
func tick_station_trucks(_delta: float) -> void:
	var veh = _gs.get("vehicles")
	if veh == null:
		return
	_ensure_station_trucks()
	for st in _fire_stations():
		_tick_station_truck(st, veh as SimVehicles)


## One station's truck: carry the crew to the fire, drop them off, bring
## the truck home when the work is done.
func _tick_station_truck(st: Dictionary, sv: SimVehicles) -> void:
	var tid := int(st.get("truck_id", -1))
	var truck := sv.vehicle_by_id(tid)
	if truck.is_empty():
		return
	var lot := _station_lot(st)
	var tpos: Vector2 = truck.get("pos", lot)
	# Purge dead/missing riders; glue live riders to the truck (they read
	# as riding the wagon — small offsets so the crew doesn't z-stack).
	var riders: Array = []
	for uid in sv.aboard_ids(tid):
		var u := _gs.get_unit(int(uid))
		if u.is_empty() or not bool(u.get("alive", false)):
			sv.disembark_vehicle(tid, int(uid))
			continue
		riders.append(u)
	var i := 0
	for u in riders:
		u["position"] = tpos + Vector2(0.0, 5.0 * float(i))
		u["truck_id"] = tid
		u["on_truck"] = false  # real truck — suppress the fake sprite
		u["work_state"] = "on_truck"
		i += 1
	var f := nearest_fire(lot)
	if f.is_empty():
		# No fire: bring the truck (and any riders) home, re-park.
		if tpos.distance_to(lot) > TRUCK_BOARD_RANGE:
			sv.drive_to(tid, lot)
		else:
			sv.park(tid)
			truck["pos"] = lot
			# Jeremy 2026-10-10 (hearsay flesh-out): home and parked — the
			# next fire gets its own rollout announcement.
			truck["brigade_announced"] = -1
			for u in riders:
				sv.disembark_vehicle(tid, int(u.get("id", -1)))
				u["truck_id"] = -1
				u["work_state"] = "idle"
				u["position"] = lot + Vector2(10.0, 10.0)
		return
	var fpos: Vector2 = f.get("position", Vector2.ZERO)
	if riders.is_empty():
		# No crew yet: wait at the lot for firefighters to board.
		if tpos.distance_to(lot) > TRUCK_BOARD_RANGE:
			sv.drive_to(tid, lot)
		else:
			sv.park(tid)
		return
	# Crew aboard: drive to the fire; on arrival, dismount to fight.
	if tpos.distance_to(fpos) <= EXTINGUISH_RANGE + 20.0:
		sv.park(tid)
		for u in riders:
			sv.disembark_vehicle(tid, int(u.get("id", -1)))
			u["truck_id"] = -1
			u["on_truck"] = false
			u["work_state"] = "to_fire"
			u["position"] = tpos
	else:
		# Jeremy 2026-10-10 (hearsay flesh-out): the brigade rolling out
		# with crew aboard is a public spectacle — announce it once per
		# dispatch so the grapevine hears the bells (repeat ticks en route
		# stay silent; the rumor dedups by fire id anyway).
		var fid := int(f.get("id", 0))
		if int(truck.get("brigade_announced", -1)) != fid:
			truck["brigade_announced"] = fid
			_gs.bus.fire_brigade_rolled.emit(int(st.get("id", -1)), fid,
				String(st.get("faction", "")))
		sv.drive_to(tid, fpos)


## ---- volcano -----------------------------------------------------------


## Resets the eruption countdown (new-game parity: the HTML re-rolls the
## timer on every new game).
func reset_volcano_timer() -> void:
	volcano_timer = randf_range(VOLCANO_PERIOD_MIN, VOLCANO_PERIOD_MAX)


## Site validation (HTML volcanoSiteOk, verbatim): inside the margins, at
## least VOLCANO_HALL_DIST from any town, not in water, and clear of
## existing sites by (site radius + VOLCANO_RADIUS).
func volcano_site_ok(pos: Vector2) -> bool:
	if pos.x < VOLCANO_EDGE_MARGIN or pos.y < VOLCANO_EDGE_MARGIN \
			or pos.x > world_bounds.size.x - VOLCANO_EDGE_MARGIN \
			or pos.y > world_bounds.size.y - VOLCANO_EDGE_MARGIN:
		return false
	for t: int in _gs.towns.keys():
		var town: Dictionary = _gs.towns[t]
		if pos.distance_to(town.get("position", Vector2.ZERO)) \
				< VOLCANO_HALL_DIST:
			return false
	if _in_water(pos):
		return false
	for s: Dictionary in volcano_sites:
		var keep_out: float = float(s.get("radius", VOLCANO_RADIUS)) \
			+ VOLCANO_RADIUS
		if pos.distance_squared_to(s.get("position", Vector2.ZERO)) \
				< keep_out * keep_out:
			return false
	return true


## Water check via MapGen (HTML inWaterAt). No terrain data (headless
## tests) means not water — same as the HTML's guarded check.
func _in_water(pos: Vector2) -> bool:
	var terrain = _gs.map_data.get("terrain", null)
	if terrain == null:
		return false
	var tpx := float(_gs.map_data.get("tile_size", 32.0))
	var tx := int(pos.x / tpx)
	var ty := int(pos.y / tpx)
	if tx < 0 or ty < 0 or tx >= MapGen.MAP_TILES \
			or ty >= MapGen.MAP_TILES:
		return false
	# Jeremy 2026-10-04 (commando audit): the terrain array may be smaller
	# than MAP_TILES^2 (different map size / corrupt data) — never index
	# past its end (PackedByteArray OOB is a hard error).
	var idx := ty * MapGen.MAP_TILES + tx
	if idx < 0 or idx >= terrain.size():
		return false
	return MapGen.is_water(int(terrain[idx]))


## Erupts a volcano at pos (HTML eruptVolcanoAt, verbatim): records the
## height edit, forges 4-6 volcanic peaks, shoves units clear of the fresh
## rock, and seeds fires at the two mortar blast points. Peaks are
## unmineable, unattackable terrain until they harden. Returns false when
## the site is invalid — silent, like the HTML timer path. This is also
## the sandbox-volcano entry point (HTML spawnVolcano).
func erupt_volcano_at(pos: Vector2) -> bool:
	if not volcano_site_ok(pos):
		return false
	var n_pk: int = VOLCANO_PEAKS_MIN \
		+ randi_range(0, VOLCANO_PEAKS_EXTRA - 1)
	var peak_ids: Array[int] = []
	for i in n_pk:
		var an: float = (float(i) / float(n_pk)) * TAU \
			+ randf_range(0.0, 0.6)
		var dd: float = 0.0 if i == 0 \
			else randf_range(80.0, VOLCANO_RADIUS - 70.0)
		var pk_pos := pos + Vector2(cos(an) * dd, sin(an) * dd * 0.85)
		if _in_water(pk_pos):
			# HTML moves water-bound peaks to the nearest dry point; the
			# vent itself is dry, so fall back to it.
			pk_pos = pos
		var vscale: float = randf_range(2.5, 3.0) if i == 0 \
			else randf_range(1.25, 1.85)
		var site: Dictionary = _gs.add_work_site({
			"kind": "volcano_peak",
			"position": pk_pos,
			"amount": 0.0,
			"vscale": vscale,
			"volcanic": true,
			"born": _gs.game_time,
			"harden_after": randf_range(VOLCANO_HARDEN_MIN,
				VOLCANO_HARDEN_MAX),
			"mineral": "",
		})
		peak_ids.append(int(site["id"]))
	# Shove units clear of the new peaks (HTML: "so nobody is entombed in
	# fresh rock"). No damage — the danger is the fires and the terrain.
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		var d: float = pos.distance_to(upos)
		if d < VOLCANO_SHOVE_INNER and d > 0.01:
			u["position"] = pos + (upos - pos) / d * VOLCANO_SHOVE_OUT
	# The two mortar blasts seed fires (HTML spawnExplosion kind 'mortar'):
	# blast 1 at (0,-60), blast 2 at (60,30), each with a weak side fire.
	ignite(pos + Vector2(0.0, -60.0), VOLCANO_BLAST_INTENSITY)
	ignite(pos + Vector2(18.0, -68.0), VOLCANO_BLAST_SIDE_INTENSITY)
	ignite(pos + Vector2(60.0, 30.0), VOLCANO_BLAST_INTENSITY)
	ignite(pos + Vector2(78.0, 22.0), VOLCANO_BLAST_SIDE_INTENSITY)
	# Height-edit record (HTML cgHeightEdits entry {x, y, r, peak}).
	volcano_sites.append({
		"position": pos,
		"radius": VOLCANO_RADIUS,
		"peak": VOLCANO_PEAK_ELEV,
		"born": _gs.game_time,
		"peak_ids": peak_ids,
	})
	# Announced when the mountains truly form (HTML: floating "🌋
	# ERUPTION!" + system message; the bus fanfare covers the sim side).
	_gs.bus.disaster_spawned.emit("volcano", pos)
	_arrival_sfx("volcano", pos)
	return true


## Volcano timer + peak hardening, called from tick().
func _tick_volcano(delta: float) -> void:
	volcano_timer -= delta
	if volcano_timer <= 0.0:
		volcano_timer = randf_range(VOLCANO_PERIOD_MIN, VOLCANO_PERIOD_MAX)
		if volcano_sites.size() < VOLCANO_MAX_SITES:
			_erupt_timer_volcano()
	_volcano_accum += delta
	if _volcano_accum >= 1.0:
		_volcano_accum = 0.0
		_harden_volcano_peaks()


## Timer path: 20 placement tries anywhere valid, silent when no site
## forms (HTML: 12 view-biased tries then 10 anywhere — the sim has no
## camera, so it uses the anywhere-valid fallback).
func _erupt_timer_volcano() -> void:
	for _i in 20:
		var p := Vector2(
			randf_range(VOLCANO_EDGE_MARGIN,
				world_bounds.size.x - VOLCANO_EDGE_MARGIN),
			randf_range(VOLCANO_EDGE_MARGIN,
				world_bounds.size.y - VOLCANO_EDGE_MARGIN))
		if volcano_site_ok(p):
			erupt_volcano_at(p)
			return


## VOLCANO91: 5-8 min after birth the peaks harden into minable mineral
## deposits (HTML: volcanic=false, random mineral type, 1500-3000 left).
## They mine as gold veins; the mineral tag records which kind hardened.
func _harden_volcano_peaks() -> void:
	for vsite: Dictionary in volcano_sites:
		for pid in vsite.get("peak_ids", []):
			var s: Dictionary = _gs.get_work_site(int(pid))
			if s.is_empty() or not bool(s.get("volcanic", false)):
				continue
			var age: float = _gs.game_time - float(s.get("born", 0.0))
			if age >= float(s.get("harden_after", VOLCANO_HARDEN_MAX)):
				s["volcanic"] = false
				s["kind"] = "gold_vein"
				s["mineral"] = VOLCANO_MINERALS[
					randi_range(0, VOLCANO_MINERALS.size() - 1)]
				s["amount"] = 1500.0 + randf_range(0.0, 1500.0)


## ---- monsters -----------------------------------------------------------


## Spawns a disaster. Returns the unit record ({} if already present for
## singletons, or on unknown kind).
func spawn(kind: String, pos: Vector2) -> Dictionary:
	if kind == NASTY_PRIEST_JOB:
		return _spawn_nasty_priest(pos)
	if not MONSTERS.has(kind) and kind != "bandit_raid":
		return {}
	if kind == "bandit_raid":
		return _spawn_bandits(pos)
	if kind == "giant_ass" or kind == "thicc_moose" \
			or kind == "count_bastard" or kind == "hoa_karen" \
			or kind == "jesus" or kind == "seagull_swarm" \
			or kind == "taxman" or kind == "booze_ooze" \
			or kind == "doom_prophet" or kind == "gig_gnome" \
			or kind == "borg_crab_bill" or kind == "twister_sister" \
			or kind == "karaoke_barbarian" \
			or kind == "gossip_gnome" \
			or kind == "warranty_salesman" \
			or kind == "doomscroller" \
			or kind == "mlm_bro" \
			or kind == "dmv_clerk" \
			or kind == "crossfit_gnome" \
			or kind == "influencer_gnome" \
			or kind == "prince_gnomba" \
			or kind == "dj_weddington" \
			or kind == "repo_gnome" \
			or kind == "podcast_bro" \
			or kind == "rogue_wizard":
		for u: Dictionary in _gs.units:
			if u.get("alive", false) \
					and String(u.get("job", "")) == kind:
				return {}  # HTML rule: only one at a time
	# Jeremy 2026-10-04 (commando audit): .get() with fallback instead of a
	# direct subscript — a bad kind can never hard-error here.
	var m: Dictionary = MONSTERS.get(kind, {})
	if m.is_empty():
		return {}
	var u: Dictionary = _gs.add_unit({
		"faction": MONSTER_FACTION,
		"job": kind,
		"town_id": -1,
		"position": pos,
		"alive": true,
		"hp": float(m["hp"]),
		"max_hp": float(m["hp"]),
		"dmg": float(m["dmg"]),
		"speed": float(m["speed"]),
		"age": 0.0,
		"leaving": false,
		"attack_cd": 0.0,
		"moons_done": 0,
		"mooned_halls": [],
		"moon_pause": 0.0,
		"wander_target": pos,
		"gender": "m",
	})
	_gs.bus.unit_spawned.emit(u)
	_gs.bus.disaster_spawned.emit(kind, pos)
	_arrival_sfx(kind, pos)
	# Jeremy 2026-10-04: add to monster cache immediately so the next
	# tick() sees it (cache rescans every 0.5s; spawn must be instant).
	var uid: int = int(u.get("id", -1))
	if uid >= 0 and not _monster_cache.has(uid):
		_monster_cache.append(uid)
	if kind == "hoa_karen" or kind == "influencer_gnome":
		u["gender"] = "f"
	# Jeremy 2026-10-04: open a tracking record for the Gazette.
	var log_id: int = dlog.start_disaster(kind, _label_for(kind), _gs.day_number,
		_gs.game_time, [int(u.get("id", -1))], _forecast_day_for(kind))
	u["disaster_log_id"] = log_id
	_apply_forecast_orders(log_id, kind)
	return u


## Jeremy 2026-10-04 (commando audit): safe random pick from a line pool —
## randi() % 0 is a hard crash, so an empty pool yields the fallback.
## Used for the NastyPriestData pools (external data source).
func _pick_line(pool: Array, fallback: String) -> String:
	if pool.is_empty():
		return fallback
	return String(pool[randi() % pool.size()])


## Jeremy 2026-10-04: display label for a disaster kind.
func _label_for(kind: String) -> String:
	if kind == NASTY_PRIEST_JOB:
		return "Nasty Priest"
	if kind == "hoa_karen":
		return "HOA Karen"
	if kind == "jesus":
		return "Jesus"
	if kind == "seagull_swarm":
		return "Seagull Swarm"
	if kind == "taxman":
		return "The Taxman"
	if kind == "booze_ooze":
		return "Booze Ooze"
	if kind == "doom_prophet":
		return "Doom Prophet"
	if kind == "gig_gnome":
		return "Gig Gnome"
	if kind == "borg_crab_bill":
		return "Bill the Borg Crab"
	if kind == "twister_sister":
		return "Twister Sister"
	if kind == "karaoke_barbarian":
		return "Brax the Karaoke Barbarian"
	if kind == "gossip_gnome":
		return "Yapper the Gossip Gnome"
	if kind == "warranty_salesman":
		return "Wally the Warranty Salesman"
	if kind == "doomscroller":
		return "Milo the Doomscroller"
	if kind == "mlm_bro":
		return "Chad the MLM Bro"
	if kind == "dmv_clerk":
		return "Dave the DMV Clerk"
	if kind == "crossfit_gnome":
		return "Kyle the CrossFit Gnome"
	if kind == "influencer_gnome":
		return "Vicky the Influencer"
	if kind == "prince_gnomba":
		return "Prince Gnomba"
	if kind == "dj_weddington":
		return "DJ Weddington"
	if kind == "repo_gnome":
		return "Ricky the Repo Gnome"
	if kind == "podcast_bro":
		return "Milo the Podcast Bro"
	for e in FORECAST_EVENTS:
		if String(e.get("type", "")) == kind:
			return String(e.get("label", kind))
	if kind == FORECAST_WIZARD.get("type", ""):
		return String(FORECAST_WIZARD.get("label", kind))
	return kind.capitalize().replace("_", " ")


## Jeremy 2026-10-04: which forecast day (if any) spawned this kind.
func _forecast_day_for(kind: String) -> int:
	for d in forecast.keys():
		var e: Dictionary = forecast[d]
		if String(e.get("type", "")) == kind:
			return int(d)
	return -1


## Jeremy 2026-10-04: carry calendar-set orders onto a fresh log record.
func _apply_forecast_orders(log_id: int, kind: String) -> void:
	for d in forecast.keys():
		var e: Dictionary = forecast[d]
		if String(e.get("type", "")) != kind:
			continue
		dlog.set_military_order(log_id,
			String(e.get("military_order", "ignore")))
		dlog.set_citizen_order(log_id,
			String(e.get("citizen_order", "free")))
		return


## Jeremy 2026-10-04: THE NASTY MONASTERY. Father Filthwick spawns and
## opens a monastery building in a random town. Singleton (one at a time).
## pos == Vector2.INF means "pick a town yourself".
func _spawn_nasty_priest(pos: Vector2) -> Dictionary:
	for u: Dictionary in _gs.units:
		if u.get("alive", false) \
				and String(u.get("job", "")) == NASTY_PRIEST_JOB:
			return {}  # only one nasty priest at a time
	var town: Dictionary = {}
	var mpos := pos
	if pos == Vector2.INF:
		town = _random_town()
		if town.is_empty():
			return {}
		var hpos: Vector2 = town.get("position", Vector2.ZERO)
		var ang := randf() * TAU
		mpos = hpos + Vector2(cos(ang), sin(ang)) \
			* NASTY_PRIEST_MONASTERY_DIST
	else:
		town = _town_near(pos)
	var tname: String = String(town.get("name", "the realm"))
	var tfaction: String = String(town.get("faction", ""))
	var tid: int = int(town.get("id", -1))
	var mname: String = _pick_line(NastyPriestData.MONASTERY_NAMES,
		"The Nasty Monastery")
	var b: Dictionary = _gs.add_building({
		"type": "monastery",
		"name": mname,
		"position": mpos,
		"faction": tfaction,
		"town_id": tid,
		"complete": true,
	})
	var u: Dictionary = _gs.add_unit({
		"faction": MONSTER_FACTION,
		"job": NASTY_PRIEST_JOB,
		"town_id": tid,
		"position": mpos + Vector2(0, 48),
		"alive": true,
		"hp": 200.0,
		"max_hp": 200.0,
		"speed": 70.0,
		"age": 0.0,
		"leaving": false,
		"gender": "m",
		"mind": {"name": NastyPriestData.PRIEST_NAME},
		"bursts_done": 0,
		"burst_timer": randf_range(NASTY_PRIEST_BURST_MIN,
			NASTY_PRIEST_BURST_MAX),
		"monastery_id": int(b.get("id", -1)),
		"monastery_pos": mpos,
		"monastery_name": mname,
		"town_name": tname,
	})
	_gs.bus.unit_spawned.emit(u)
	_gs.bus.disaster_spawned.emit(NASTY_PRIEST_JOB, mpos)
	_arrival_sfx(NASTY_PRIEST_JOB, mpos)
	# Jeremy 2026-10-04: open a tracking record for the Gazette.
	var log_id: int = dlog.start_disaster(NASTY_PRIEST_JOB, "Nasty Priest",
		_gs.day_number, _gs.game_time, [int(u.get("id", -1))],
		_forecast_day_for(NASTY_PRIEST_JOB))
	u["disaster_log_id"] = log_id
	dlog.set_monastery_name(log_id, mname)
	if tid >= 0:
		dlog.record_town(log_id, tid, tname, tfaction, _gs.day_number)
	# Jeremy 2026-10-04: add to monster cache immediately (see spawn()).
	var puid: int = int(u.get("id", -1))
	if puid >= 0 and not _monster_cache.has(puid):
		_monster_cache.append(puid)
	return u


## Random town record, or {} when there are no towns.
func _random_town() -> Dictionary:
	var cands: Array = []
	for t: Variant in _gs.towns.values():
		cands.append(t)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


## Nearest town to a position, or {} when there are no towns.
func _town_near(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d2 := 1e18
	for t: Variant in _gs.towns.values():
		var d2: float = pos.distance_squared_to(
			(t as Dictionary).get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = t
	return best


## The priest lingers by his monastery, then bursts out screaming at
## random intervals. After enough outbursts (or the budget), he leaves.
func _tick_priest(u: Dictionary, delta: float) -> void:
	u["age"] = float(u.get("age", 0.0)) + delta
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if float(u.get("age", 0.0)) >= NASTY_PRIEST_BUDGET \
			or int(u.get("bursts_done", 0)) >= NASTY_PRIEST_MAX_BURSTS:
		_start_leaving(u)
		return
	# Linger near the monastery doors.
	var mpos: Vector2 = u.get("monastery_pos", upos)
	if upos.distance_to(mpos) > 130.0:
		_walk_to(u, mpos, 70.0, delta)
		u["combat_state"] = "walking"
	else:
		u["combat_state"] = "idle"
	var timer: float = float(u.get("burst_timer", 60.0)) - delta
	u["burst_timer"] = timer
	if timer <= 0.0:
		u["burst_timer"] = randf_range(NASTY_PRIEST_BURST_MIN,
			NASTY_PRIEST_BURST_MAX)
		_priest_burst(u)


## One outburst: the priest screams, the realm hears about it.
func _priest_burst(u: Dictionary) -> void:
	u["bursts_done"] = int(u.get("bursts_done", 0)) + 1
	var outburst: String = _pick_line(NastyPriestData.OUTBURSTS,
		"BOOBIES!!!")
	var pid: int = int(u.get("id", -1))
	_gs.bus.unit_said.emit(pid, outburst)
	_gs.bus.priest_burst.emit(pid, u.get("position", Vector2.ZERO), outburst)
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id >= 0:
		dlog.record_outburst(log_id)


func _spawn_bandits(pos: Vector2) -> Dictionary:
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("job", "")) == "bandit":
			return {}  # one raid at a time
	var first: Dictionary = {}
	var bandit_ids: Array = []
	var pack_size := randi_range(BANDIT_COUNT_MIN, BANDIT_COUNT_MAX)
	for i: int in range(pack_size):
		var p := pos + Vector2(randf_range(-60.0, 60.0),
			randf_range(-60.0, 60.0))
		var u: Dictionary = _gs.add_unit({
			"faction": MONSTER_FACTION,
			"job": "bandit",
			"town_id": -1,
			"position": p,
			"alive": true,
			"hp": 80.0,
			"max_hp": 80.0,
			"gender": "m",
		})
		_gs.bus.unit_spawned.emit(u)
		bandit_ids.append(int(u.get("id", -1)))
		if first.is_empty():
			first = u
	_gs.bus.disaster_spawned.emit("bandit_raid", pos)
	_arrival_sfx("bandit_raid", pos)
	# Jeremy 2026-10-04: track the raid too.
	var log_id: int = dlog.start_disaster("bandit_raid", "Bandit Raid",
		_gs.day_number, _gs.game_time, bandit_ids, _forecast_day_for("bandit_raid"))
	for u2: Dictionary in _gs.units:
		if int(u2.get("id", -1)) in bandit_ids:
			u2["disaster_log_id"] = log_id
	_apply_forecast_orders(log_id, "bandit_raid")
	return first


## ---- per-tick ------------------------------------------------------------


func tick(delta: float) -> void:
	_fire_accum += delta
	if _fire_accum >= FIRE_TICK:
		_tick_fires(_fire_accum)
		_fire_accum = 0.0
	_tick_volcano(delta)
	process_calendar_disasters()
	_maybe_spawn_nasty_priest()
	_maybe_spawn_hoa_karen()
	_maybe_spawn_jesus()
	_maybe_spawn_seagulls()
	_maybe_spawn_taxman()
	_maybe_spawn_ooze()
	_maybe_spawn_prophet()
	_maybe_spawn_driver()
	_maybe_spawn_borg_crab()
	_maybe_spawn_twister()
	_maybe_spawn_karaoke()
	_maybe_spawn_gossip()
	_maybe_spawn_warranty()
	_maybe_spawn_doomscroll()
	_maybe_spawn_mlm()
	_maybe_spawn_dmv()
	_maybe_spawn_crossfit()
	_maybe_spawn_influencer()
	_maybe_spawn_prince_gnomba()
	_maybe_spawn_dj()
	_maybe_spawn_repo()
	_maybe_spawn_podcast()
	# Jeremy 2026-10-04: staggered monster scan — rescan all units every
	# 0.5s into _monster_cache, tick from cache every frame. Was 240
	# iterations/frame (14,400/s); now ~8 scans/s + 0-5 cache ticks/frame.
	_monster_scan_accum += delta
	if _monster_scan_accum >= MONSTER_SCAN_INTERVAL:
		_monster_scan_accum = 0.0
		_rescan_monsters()
	_tick_cached_monsters(delta)
	_apply_orders(delta)
	# Jeremy 2026-10-07: drunk/hangover decay on the 0.5 s scan cadence,
	# not per frame — a per-frame full-unit loop would reintroduce the
	# 240-iterations/frame cost the 2026-10-04 scan optimization killed.
	_ambient_accum += delta
	if _ambient_accum >= MONSTER_SCAN_INTERVAL:
		_tick_ambient(_ambient_accum)
		_ambient_accum = 0.0


## Rebuild the monster cache: unit IDs of alive monster-faction disaster
## units (nasty priest + MONSTERS). Bandits excluded (combat AI owns them).
func _rescan_monsters() -> void:
	# Jeremy 2026-10-07 (wake deep-disasters): close ledgers for monsters
	# that died since the last scan. The per-frame cache tick only checks
	# deaths for units still in the cache — a monster slain between two
	# rescans would otherwise drop out silently, leaking an "active"
	# ledger forever with no Gazette story. _check_dead_disaster is
	# idempotent (it no-ops on non-active records), so a unit checked here
	# and again in the cache tick closes exactly once.
	for uid: int in _monster_cache:
		var old: Dictionary = _gs.get_unit(uid)
		if not old.is_empty() and not bool(old.get("alive", false)):
			_check_dead_disaster(old)
	_monster_cache.clear()
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != MONSTER_FACTION:
			continue
		var job: String = String(u.get("job", ""))
		if job == "bandit":
			continue
		if job == NASTY_PRIEST_JOB or MONSTERS.has(job):
			_monster_cache.append(int(u.get("id", -1)))


## Public: world positions of live disaster monsters for map markers.
## Graphics-hourly 2026-10-05: HTML drawDisasterMarkers parity — the
## marker layer reads this (never _monster_cache directly).
func monster_marker_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for uid: int in _monster_cache:
		var u: Dictionary = _gs.get_unit(uid)
		if u.is_empty() or not u.get("alive", false):
			continue
		out.append(u.get("position", Vector2.ZERO))
	return out


## Tick monsters from the cache (60Hz, smooth movement). Dead or
## despawned monsters close their ledger and drop from the cache.
func _tick_cached_monsters(delta: float) -> void:
	var i := _monster_cache.size() - 1
	while i >= 0:
		# Jeremy 2026-10-04: bounds check — tick functions can modify the
		# cache during iteration (hard-lock fix).
		if i >= _monster_cache.size():
			i -= 1
			continue
		var uid: int = _monster_cache[i]
		var u: Dictionary = _gs.get_unit(uid)
		if u.is_empty() or not u.get("alive", false):
			if not u.is_empty():
				_check_dead_disaster(u)
			_monster_cache.remove_at(i)
			i -= 1
			continue
		var job: String = String(u.get("job", ""))
		if job == NASTY_PRIEST_JOB:
			_tick_priest(u, delta)
		elif MONSTERS.has(job):
			_tick_monster(u, job, delta)
		else:
			# Job changed (e.g. converted) — drop from cache.
			_monster_cache.remove_at(i)
		i -= 1


## Jeremy 2026-10-04: THE NASTY MONASTERY — small daily chance for Father
## Filthwick to show up and open his monastery (never on the calendar).
func _maybe_spawn_nasty_priest() -> void:
	if _gs.day_number == _priest_day:
		return
	_priest_day = _gs.day_number
	if randf() < NASTY_PRIEST_DAILY_CHANCE:
		_spawn_nasty_priest(Vector2.INF)


func _tick_fires(delta: float) -> void:
	var dead: Array[Dictionary] = []
	# Weather interplay (HTML updateWorldFire, verbatim): rain/storm dampen
	# fires; storm wind boosts spread, rain kills it.
	var wx := "clear"
	var wind_boost := 0.85
	var seas = _gs.get("seasons")
	if seas != null:
		wx = String(seas.weather)
		wind_boost = 1.15 if wx == "storm" \
			else (0.2 if wx == "rain" else 0.85)
	var raining: bool = wx == "rain" or wx == "storm"
	# Jeremy 2026-10-04 (commando audit): iterate snapshots. _spread()
	# ignites new fires (appends to `fires`), damage_unit() flips unit
	# flags, and damage_building() ERASES destroyed buildings from
	# _gs.buildings — all mid-iteration without this.
	var fire_snap: Array = fires.duplicate()
	var unit_snap: Array = _gs.units.duplicate()
	var bld_snap: Array = _gs.buildings.duplicate()
	for f: Dictionary in fire_snap:
		var inten: float = float(f.get("intensity", 0.0))
		var fpos: Vector2 = f.get("position", Vector2.ZERO)
		# Damage units in radius.
		var dps: float = 14.0 * inten / 100.0
		for u: Dictionary in unit_snap:
			if not u.get("alive", false):
				continue
			if fpos.distance_to(u.get("position", Vector2.ZERO)) \
					<= FIRE_DAMAGE_RADIUS:
				_combat.damage_unit(int(u.get("id", 0)), dps * delta,
					"fire")
		# Damage buildings in radius; mark them burning.
		for b: Dictionary in bld_snap:
			if fpos.distance_to(b.get("position", Vector2.ZERO)) \
					<= FIRE_DAMAGE_RADIUS + 20.0:
				b["on_fire"] = true
				_combat.damage_building(int(b.get("id", 0)),
					10.0 * inten / 100.0 * delta, "fire")
		# Spread to nearby trees.
		_spread(f, fpos, wind_boost)
		# Natural burnout: rain hurries it (HTML: life -= dt*(raining?4.0:1.55)).
		inten -= (1.4 + (3.5 if raining else 0.0)) * delta
		f["intensity"] = inten
		if inten <= 0.0:
			dead.append(f)
	for f: Dictionary in dead:
		extinguish(f)


func _spread(f: Dictionary, fpos: Vector2, wind_boost: float = 0.85) -> void:
	# Each fire tries one spread roll per fire-tick: find a nearby live
	# tree site and ignite it (bounded work — one scan per fire per tick).
	# Storm wind boosts spread, rain kills it (HTML windBoost).
	if randf() > 0.35 * wind_boost:
		return
	for s: Dictionary in _gs.work_sites:
		if String(s.get("kind", "")) != "tree":
			continue
		if float(s.get("amount", 0.0)) <= 0.0:
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		if fpos.distance_to(sp) <= FIRE_SPREAD_RADIUS:
			s["amount"] = 0.0  # the tree burns
			s["felled"] = true  # Jeremy 2026-10-05: burnt trees fall too
			ignite(sp, 55.0)
			return  # one new fire per tick per fire


func _tick_monster(u: Dictionary, job: String, delta: float) -> void:
	# Jeremy 2026-10-04 (commando audit): .get() with fallback instead of
	# a direct subscript — a bad job can never hard-error here.
	var m: Dictionary = MONSTERS.get(job, {})
	if m.is_empty():
		return
	u["age"] = float(u.get("age", 0.0)) + delta
	u["attack_cd"] = maxf(0.0, float(u.get("attack_cd", 0.0)) - delta)
	var upos: Vector2 = u.get("position", Vector2.ZERO)

	# Budget spent or cardboard-cat-style timer: leave.
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if float(u.get("age", 0.0)) >= float(m["budget"]):
		_start_leaving(u)
		return

	match job:
		"giant_ass", "giant_lizard":
			_tick_smasher(u, float(m["dmg"]), float(m["speed"]), delta)
		"thicc_moose":
			_tick_moose(u, float(m["speed"]), delta)
		"rogue_wizard":
			_tick_wizard(u, delta)
		"count_bastard":
			_tick_bastard(u, float(m["speed"]), delta)
		"hoa_karen":
			_tick_karen(u, float(m["speed"]), delta)
		"jesus":
			_tick_jesus(u, float(m["dmg"]), float(m["speed"]), delta)
		"seagull_swarm":
			_tick_seagulls(u, float(m["speed"]), delta)
		"taxman":
			_tick_taxman(u, float(m["speed"]), delta)
		"booze_ooze":
			_tick_ooze(u, float(m["speed"]), delta)
		"doom_prophet":
			_tick_prophet(u, float(m["speed"]), delta)
		"gig_gnome":
			_tick_driver(u, float(m["speed"]), delta)
		"borg_crab_bill":
			_tick_borg_crab(u, float(m["speed"]), delta)
		"twister_sister":
			_tick_twister(u, float(m["speed"]), delta)
		"karaoke_barbarian":
			_tick_karaoke(u, float(m["speed"]), delta)
		"gossip_gnome":
			_tick_gossip(u, float(m["speed"]), delta)
		"warranty_salesman":
			_tick_warranty(u, float(m["speed"]), delta)
		"doomscroller":
			_tick_doomscroll(u, float(m["speed"]), delta)
		"mlm_bro":
			_tick_mlm(u, float(m["speed"]), delta)
		"dmv_clerk":
			_tick_dmv(u, float(m["speed"]), delta)
		"crossfit_gnome":
			_tick_crossfit(u, float(m["speed"]), delta)
		"influencer_gnome":
			_tick_influencer(u, float(m["speed"]), delta)
		"prince_gnomba":
			_tick_gnomba(u, float(m["speed"]), delta)
		"dj_weddington":
			_tick_dj(u, float(m["speed"]), delta)
		"repo_gnome":
			_tick_repo(u, float(m["speed"]), delta)
		"podcast_bro":
			_tick_podcast(u, float(m["speed"]), delta)
		"cardboard_cat":
			_tick_wanderer(u, float(m["speed"]), delta)


## Smasher: seeks the nearest building or unit, smashes on arrival.
func _tick_smasher(u: Dictionary, dmg: float, speed: float,
		delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var target_pos := Vector2.INF
	var target_unit := -1
	var target_building := -1
	var best_d2 := 800.0 * 800.0
	for b: Dictionary in _gs.buildings:
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			target_pos = b.get("position", Vector2.ZERO)
			target_building = int(b.get("id", 0))
			target_unit = -1
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var d2: float = upos.distance_squared_to(
			x.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			target_pos = x.get("position", Vector2.ZERO)
			target_unit = int(x.get("id", 0))
			target_building = -1
	if target_pos == Vector2.INF:
		_tick_wanderer(u, speed, delta)
		return
	if upos.distance_to(target_pos) <= 70.0:
		if float(u.get("attack_cd", 0.0)) <= 0.0:
			u["attack_cd"] = 1.5
			u["combat_state"] = "attacking"
			if target_unit >= 0:
				_combat.damage_unit(target_unit, dmg, MONSTER_FACTION)
			elif target_building >= 0:
				_combat.damage_building(target_building, dmg,
					MONSTER_FACTION)
				# Jeremy 2026-10-04: track which towns get smashed.
				var b: Dictionary = _get_building(target_building)
				if not b.is_empty():
					_record_rampage_town(u, b)
	else:
		u["combat_state"] = "chasing"
		_walk_to(u, target_pos, speed, delta)


## Moose: wanders town to town, moons 3 halls (harassment, no damage),
## then leaves.
func _tick_moose(u: Dictionary, speed: float, delta: float) -> void:
	if float(u.get("moon_pause", 0.0)) > 0.0:
		u["moon_pause"] = float(u.get("moon_pause")) - delta
		u["combat_state"] = "mooning"
		_tick_moose_scare(u, delta, true)  # HTML: screamCd 1.2, big scare
		return
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var mooned: Array = u.get("mooned_halls", [])
	var best: Dictionary = {}
	var best_d2 := 1e18
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) != "town_hall":
			continue
		if int(b.get("id", 0)) in mooned:
			continue
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = b
	if best.is_empty():
		_tick_wanderer(u, speed, delta)
		return
	var bpos: Vector2 = best.get("position", Vector2.ZERO)
	if upos.distance_to(bpos) <= 200.0:
		mooned.append(int(best.get("id", 0)))
		u["mooned_halls"] = mooned
		u["moons_done"] = int(u.get("moons_done", 0)) + 1
		u["moon_pause"] = 3.0
		_gs.bus.moose_mooned.emit(best)
		# Jeremy 2026-10-04: track the town + moon in the ledger.
		_record_moon_town(u, best)
		if int(u.get("moons_done", 0)) >= 3:
			_start_leaving(u)
	else:
		_walk_to(u, bpos, speed, delta)
	# HTML: screamCd 2.0 while traveling between halls (small scare).
	_tick_moose_scare(u, delta, false)


## HTML parity (scareNearby): scream cooldown, then panic nearby civilians.
func _tick_moose_scare(u: Dictionary, delta: float, big: bool) -> void:
	var cd: float = float(u.get("scare_cd", 0.0)) - delta
	if cd > 0.0:
		u["scare_cd"] = cd
		return
	u["scare_cd"] = MOOSE_SCARE_CD_MOON if big else MOOSE_SCARE_CD_WANDER
	_scare_nearby(u, big)


## HTML parity (scareNearby): stress + scared emotion for everyone in radius;
## cowards flee (mind flee keys — SimMind._tick_flee moves them away from
## threat_pos, cliff-safe). The brave hold their ground, matching the
## SimMind.on_attacked coward/brave convention (uniform brave rolls mean
## roughly 40% of civilians bolt — organic-looking panic, not a stampede).
func _scare_nearby(u: Dictionary, big: bool) -> void:
	var mpos: Vector2 = u.get("position", Vector2.ZERO)
	var radius := MOOSE_SCARE_BIG_RADIUS if big else MOOSE_SCARE_RADIUS
	var stress_hit := 35.0 if big else 18.0
	var mind: SimMind = null
	if _combat != null:
		mind = _combat.mind as SimMind
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if int(x.get("inside_building_id", 0)) > 0:
			continue  # HTML: u.insideBuilding skips the scare
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(mpos) > radius:
			continue
		x["stress"] = minf(100.0, float(x.get("stress", 0.0)) + stress_hit)
		if mind != null and mind.emotion != null:
			mind.emotion.notify(x, "monster")  # HTML: mood -15
		if SimPersonality.stands_ground(x):
			continue  # the brave hold; cowards run
		x["fleeing"] = true
		x["flee_timer"] = SimMind.FLEE_DURATION
		x["threat_pos"] = mpos


## Jeremy 2026-10-04: a slain disaster monster closes its ledger once.
func _check_dead_disaster(u: Dictionary) -> void:
	if String(u.get("faction", "")) != MONSTER_FACTION:
		return
	var job: String = String(u.get("job", ""))
	if not MONSTERS.has(job) and job != "bandit" \
			and job != NASTY_PRIEST_JOB:
		return
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return
	var rec: Dictionary = dlog.get_record(log_id)
	if rec.is_empty() or String(rec.get("status", "")) != "active":
		return  # already closed
	if job == "hoa_karen":
		_karen_slain(u)
	elif job == "seagull_swarm":
		_gulls_departed(u)
	elif job == "taxman":
		_taxman_slain(u)
	elif job == "booze_ooze":
		_ooze_slain(u)
	elif job == "doom_prophet":
		_prophet_departed(u)
	elif job == "gig_gnome":
		_driver_departed(u)
	elif job == "borg_crab_bill":
		_borg_crab_departed(u)
	elif job == "karaoke_barbarian":
		_karaoke_departed(u)
	elif job == "gossip_gnome":
		_gossip_departed(u)
	elif job == "warranty_salesman":
		_warranty_departed(u)
	elif job == "doomscroller":
		_doomscroll_departed(u)
	elif job == "mlm_bro":
		_mlm_departed(u)
	elif job == "dmv_clerk":
		_dmv_departed(u)
	elif job == "crossfit_gnome":
		_crossfit_departed(u)
	elif job == "influencer_gnome":
		_influencer_departed(u)
	elif job == "prince_gnomba":
		_gnomba_departed(u)
	elif job == "dj_weddington":
		_dj_departed(u)
	elif job == "repo_gnome":
		_repo_departed(u)
	elif job == "podcast_bro":
		_podcast_departed(u)
	elif job == "count_bastard":
		_bastard_departed(u)
	elif job == "rogue_wizard":
		_wizard_departed(u)
	_end_log_record(u, "slain")


## Jeremy 2026-10-04: close a ledger record + file the Gazette story.
func _end_log_record(u: Dictionary, how: String) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return
	var rec: Dictionary = dlog.get_record(log_id)
	if rec.is_empty() or String(rec.get("status", "")) != "active":
		return
	dlog.end_disaster(log_id, _gs.day_number, how)
	_publish_disaster_story(log_id)


## Jeremy 2026-10-04: Gazette Disaster Desk story with towns + death toll.
func _publish_disaster_story(log_id: int) -> void:
	var sum: Dictionary = dlog.summary(log_id)
	if sum.is_empty():
		return
	var court = _gs.court_sys
	if court == null or not court.has_method("publish_story"):
		return
	var label: String = String(sum.get("label", "disaster"))
	var toll: int = int(sum.get("death_toll", 0))
	var towns: Array = sum.get("towns", [])
	var status: String = String(sum.get("status", "left"))
	var headline := ""
	var karen_extra: Array[String] = []
	# Jeremy 2026-10-04: THE NASTY MONASTERY gets its own headlines.
	if String(sum.get("kind", "")) == NASTY_PRIEST_JOB:
		var bursts: int = int(sum.get("outbursts", 0))
		var tname: String = String(towns[0]) if not towns.is_empty() \
			else "THE REALM"
		var h: String = _pick_line(NastyPriestData.GAZETTE_HEADLINES,
			"FATHER FILTHWICK UP TO NO GOOD IN {t}")
		headline = h.replace("{t}", tname).replace("{n}", str(bursts))
	elif String(sum.get("kind", "")) == "thicc_moose":
		var moons: int = int(sum.get("moons", 0))
		if toll == 0:
			headline = "THICC MOOSE MOONS %s — 0 DEAD, DIGNITY WOUNDED" % (
				", ".join(towns) if not towns.is_empty() else "THE REALM")
		else:
			headline = "MOOSE MOONING TURNS DEADLY — %d DEAD" % toll
	elif String(sum.get("kind", "")) == "hoa_karen":
		var refund := ""
		var liens := 0
		for note in sum.get("notes", []):
			var ns := String(note)
			if ns.begins_with("REFUNDED"):
				refund = ns
			elif ns.begins_with("LIEN"):
				liens += 1
		if status == "slain":
			headline = "KAREN GRISTLETHWAITE EVICTED — %s, LIENS LIFTED" % (
				refund if refund != "" else "no fines to refund")
		else:
			headline = "HOA KAREN DEPARTS — SHE'LL BE BACK"
		if liens > 0:
			karen_extra.append(
				"Properties liened during the visit: %d." % liens)
		if refund != "":
			karen_extra.append("%s to the victims." % refund)
		karen_extra.append("The HOA menace has been removed from the " \
			+ "neighborhood. Lawn gnomes may face the street again.")
	elif String(sum.get("kind", "")) == "seagull_swarm":
		var stolen := 0
		for note in sum.get("notes", []):
			var ns2 := String(note)
			if ns2.begins_with("STOLEN"):
				stolen = int(ns2.get_slice(" ", 1))
		if status == "slain":
			headline = "SEAGULL SWARM SLAIN — LUNCH AVENGED"
		else:
			headline = "SEAGULL SWARM MOVES ON — %d FOOD STOLEN" % stolen
		karen_extra.append("The flock crapped on everything and took the fries.")
	elif String(sum.get("kind", "")) == "rogue_wizard":
		var casts := 0
		for note in sum.get("notes", []):
			var ns5 := String(note)
			if ns5.begins_with("ZORBLAX"):
				casts = int(ns5.get_slice(" ", 2))
		if status == "slain":
			headline = "ROGUE WIZARD DE-ROBED — %d SPELLS CAST" % casts
		else:
			headline = "ZORBLAX VANISHES IN A PUFF OF LOGIC"
		karen_extra.append("The unlicensed wizard's rampage is over. " \
			+ "Towns report singed eyebrows and strong opinions about " \
			+ "his diploma.")
	elif String(sum.get("kind", "")) == "taxman":
		var collected := 0
		for note in sum.get("notes", []):
			var ns3 := String(note)
			if ns3.begins_with("GARNISHED"):
				collected = int(ns3.get_slice(" ", 1))
		if status == "slain":
			headline = "TAXMAN SLAIN — AUDIT CANCELLED, TOWN REJOICES"
		else:
			headline = "TAXMAN DEPARTS — $%d IN BACK TAXES COLLECTED" \
				% collected
		karen_extra.append("He stamped every form twice. Nobody knows why.")
	elif String(sum.get("kind", "")) == "booze_ooze":
		var drinks := 0
		for note in sum.get("notes", []):
			var ns6 := String(note)
			if ns6.begins_with("TALLY"):
				var parts: PackedStringArray = ns6.split(" ")
				if parts.size() > 1:
					drinks = int(parts[1])
		if status == "slain":
			headline = "BARON VON FOAM SLAIN — THE TOWN DRINKS TO HIS MEMORY"
		else:
			headline = "BARON VON FOAM OOZES ON — %d DRINKS POURED" % drinks
		karen_extra.append("Hydrate, everyone. The hangovers are real this time.")
	elif String(sum.get("kind", "")) == "count_bastard":
		var insults := 0
		var punches := 0
		for note in sum.get("notes", []):
			var ns4 := String(note)
			if ns4.begins_with("INSULTS"):
				var parts: PackedStringArray = ns4.split(" ")
				if parts.size() >= 4:
					insults = int(parts[1])
					punches = int(parts[3])
		if status == "slain":
			headline = "COUNT BASTARD SLAIN — %d INSULTS AVENGED" % insults
			karen_extra.append("The realm's most punchable nobleman took %d punches before someone finished the job. Therapists report a surge in bookings." % punches)
		else:
			headline = "COUNT BASTARD DEPARTS — %d ROASTED, %d SWUNG BACK" \
				% [insults, punches]
			karen_extra.append("He roasted %d citizens by name and absorbed %d punches without spilling his tea. The town exhales." % [insults, punches])
	elif status == "slain":
		headline = "%s SLAIN — %d DEAD" % [label.to_upper(), toll]
	elif toll > 0:
		headline = "%s RAMPAGE ENDS — %d DEAD" % [label.to_upper(), toll]
	else:
		headline = "%s LEAVES — NO LIVES LOST" % label.to_upper()
	var lines: Array[String] = []
	if not towns.is_empty():
		lines.append("Towns visited: %s." % ", ".join(towns))
	var death_lines: Array = sum.get("death_lines", [])
	if not death_lines.is_empty():
		lines.append("The fallen:")
		for dl in death_lines:
			lines.append("  - %s" % dl)
	else:
		lines.append("Miraculously, no one died.")
	if String(sum.get("military_order", "ignore")) != "ignore":
		lines.append("Military order: %s." % String(sum.get("military_order")).capitalize())
	if String(sum.get("citizen_order", "free")) == "shelter":
		lines.append("Citizens sheltered indoors for the duration.")
	for ke in karen_extra:
		lines.append(ke)
	var body := "\n".join(lines)
	# Jeremy 2026-10-04: THE NASTY MONASTERY gets its own article body.
	if String(sum.get("kind", "")) == NASTY_PRIEST_JOB:
		var bursts2: int = int(sum.get("outbursts", 0))
		var tname2: String = String(towns[0]) if not towns.is_empty() \
			else "the realm"
		var mname2 := "the Nasty Monastery"
		var msum: String = String(sum.get("monastery_name", ""))
		if msum != "":
			mname2 = msum
		var b: String = _pick_line(NastyPriestData.GAZETTE_BODIES,
			"Father Filthwick burst from {m} {n} times, traumatizing {t}.")
		body = b.replace("{t}", tname2).replace("{n}", str(bursts2)) \
			.replace("{m}", mname2)
	var story = court.publish_story(headline, body, "disaster")
	# Jeremy 2026-10-04 (commando audit): publish_story is only guarded by
	# has_method — never subscript a null/non-Dictionary return.
	if story is Dictionary:
		# Pin the most specific cartoon for what happened.
		story["force_cartoon"] = _disaster_cartoon(log_id, sum)


## Jeremy 2026-10-04: pick the most specific Gazette image for a disaster.
## kind + most-affected faction + outcome -> image stem.
func _disaster_cartoon(log_id: int, sum: Dictionary) -> String:
	var kind: String = String(sum.get("kind", ""))
	var toll: int = int(sum.get("death_toll", 0))
	var outcome := "calm"
	if toll > 0:
		outcome = "deaths"
	elif String(sum.get("military_order", "ignore")) == "attack":
		outcome = "battle"
	elif kind == "thicc_moose" or kind == "hoa_karen":
		outcome = "funny"
	# Most-affected faction = faction of the first town entered.
	var target_faction := ""
	var rec: Dictionary = dlog.get_record(log_id)
	if not rec.is_empty():
		var towns: Array = rec.get("towns", [])
		if not towns.is_empty():
			target_faction = String(towns[0].get("faction", ""))
	return SimGazette.disaster_cartoon_for(kind, target_faction, outcome)


## Building lookup by id.
func _get_building(bid: int) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if int(b.get("id", -1)) == bid:
			return b
	return {}


func _record_moon_town(u: Dictionary, hall: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return
	dlog.record_moon(log_id)
	var tid: int = int(hall.get("town_id", -1))
	var town: Dictionary = _gs.towns.get(tid, {})
	if town.is_empty():
		return
	dlog.record_town(log_id, tid, String(town.get("name", "?")),
		String(town.get("faction", "?")), _gs.day_number)


## Jeremy 2026-10-04: log any town a disaster monster is rampaging through.
## Called from smasher/wizard ticks when they damage a building.
func _record_rampage_town(u: Dictionary, building: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return
	var tid: int = int(building.get("town_id", -1))
	var town: Dictionary = _gs.towns.get(tid, {})
	if town.is_empty():
		return
	dlog.record_town(log_id, tid, String(town.get("name", "?")),
		String(town.get("faction", "?")), _gs.day_number)


## Rogue wizard: hostile spellcaster, keeps distance, casts spells.
## Wake rapid-iteration 2026-10-07: ROGUE WIZARD flesh-out — "Zorblax the
## Unlicensed". The thinnest disaster (a mute 26-dmg spell turret with no
## art mapping) gets a brain: three rotating spell schools, wild-surge
## fizzles (20% backfire on himself), blink-escapes from soldiers (3 max,
## then he stands and fights), arrogant taunts, and a named Gazette arc.
const WIZARD_NAME := "Zorblax the Unlicensed"
const WIZARD_SPELL_CD := 2.2
const WIZARD_BLINK_RADIUS := 180.0   # soldier inside this -> he blinks
const WIZARD_BLINK_DIST := 340.0
const WIZARD_MAX_BLINKS := 3
const WIZARD_FIZZLE_CHANCE := 0.20
const WIZARD_FIZZLE_SELF_DMG := 12.0
const WIZARD_SCHOOLS: Array = [
	{"name": "firebolt", "dmg": 26.0, "splash": 40.0, "speed": 500.0},
	{"name": "frostbite", "dmg": 18.0, "splash": 60.0, "speed": 450.0},
	{"name": "stormcall", "dmg": 22.0, "splash": 25.0, "speed": 650.0},
]
const WIZARD_ARRIVE_LINES: Array[String] = [
	"I am ZORBLAX! Tremble, peasants!",
	"Your town offends my aura. Prepare for magic!",
	"Behold! Actual consequences!",
]
const WIZARD_TAUNT_LINES: Array[String] = [
	"Did that hurt? It was supposed to.",
	"My diploma says I'm great at this.",
	"You call that dodging? Adorable.",
	"Stand still! This is ART!",
]
const WIZARD_BLINK_LINES: Array[String] = [
	"You can't catch what you can't see!",
	"Teleportation! Bet YOU never went to wizard school.",
	"Over here, muscle-brain!",
]
const WIZARD_FIZZLE_LINES: Array[String] = [
	"That was SUPPOSED to happen. Probably.",
	"My wand has a loose thread, okay?!",
	"Note to self: fewer lightning breakfasts.",
]


func _tick_wizard(u: Dictionary, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	_announce_once(u, "wizard_announced",
		"ROGUE WIZARD LOOSE IN THE REALM",
		"A feral wizard calling himself " + WIZARD_NAME + " has wandered " \
		+ "into the realm, hurling spells at anything that moves.")
	if not bool(u.get("wizard_greeted", false)):
		u["wizard_greeted"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			WIZARD_ARRIVE_LINES[randi() % WIZARD_ARRIVE_LINES.size()])
	# Blink escape: a soldier closing in sends him elsewhere (3 max, then
	# he stands and fights). The prophet's check is the generic
	# military-proximity scan, shared here.
	if int(u.get("wizard_blinks", 0)) < WIZARD_MAX_BLINKS \
			and _prophet_soldier_near(upos):
		_wizard_blink(u, upos)
		return
	var best: Dictionary = {}
	var best_d2 := 420.0 * 420.0
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var d2: float = upos.distance_squared_to(
			x.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = x
	if best.is_empty():
		_tick_wanderer(u, 80.0, delta)
		return
	var bpos: Vector2 = best.get("position", Vector2.ZERO)
	var dist: float = upos.distance_to(bpos)
	if dist <= 340.0:
		if float(u.get("attack_cd", 0.0)) <= 0.0:
			u["attack_cd"] = WIZARD_SPELL_CD
			_wizard_cast(u, upos, best, bpos)
	elif dist > 380.0:
		_walk_to(u, bpos, 80.0, delta)


## One spell from the rotating schools; may fizzle into his own face.
func _wizard_cast(u: Dictionary, upos: Vector2, best: Dictionary,
		bpos: Vector2) -> void:
	var idx: int = int(u.get("wizard_school", 0)) % WIZARD_SCHOOLS.size()
	u["wizard_school"] = idx + 1
	u["wizard_casts"] = int(u.get("wizard_casts", 0)) + 1
	var school: Dictionary = WIZARD_SCHOOLS[idx]
	# Record the attempted school even if it fizzles back at him: a surging
	# firebolt is still a firebolt. (Kept behind the early return before,
	# fizzles silently re-reported the previous school.)
	u["wizard_last_school"] = String(school.get("name", "firebolt"))
	# Wild surge: the spell eats itself.
	if randf() < WIZARD_FIZZLE_CHANCE:
		u["wizard_fizzles"] = int(u.get("wizard_fizzles", 0)) + 1
		var hp: float = float(u.get("hp", 200.0)) - WIZARD_FIZZLE_SELF_DMG
		u["hp"] = hp
		u["combat_state"] = "dizzy"
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			WIZARD_FIZZLE_LINES[randi() % WIZARD_FIZZLE_LINES.size()])
		if hp <= 0.0:
			u["alive"] = false  # de-robed by his own surge
		return
	u["combat_state"] = "attacking"
	_combat.fire_projectile(upos, int(best.get("id", 0)), bpos,
		"spell", float(school.get("dmg", 26.0)),
		float(school.get("splash", 40.0)), MONSTER_FACTION,
		float(school.get("speed", 500.0)))
	if randf() < 0.35:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			WIZARD_TAUNT_LINES[randi() % WIZARD_TAUNT_LINES.size()])


## Teleport hop away from incoming soldiers.
func _wizard_blink(u: Dictionary, upos: Vector2) -> void:
	u["wizard_blinks"] = int(u.get("wizard_blinks", 0)) + 1
	var ang: float = randf() * TAU
	var dest: Vector2 = upos + Vector2(cos(ang), sin(ang)) * WIZARD_BLINK_DIST
	dest.x = clampf(dest.x, 60.0, world_bounds.size.x - 60.0)
	dest.y = clampf(dest.y, 60.0, world_bounds.size.y - 60.0)
	u["position"] = dest
	u["combat_state"] = "blinking"
	u["attack_cd"] = 0.6  # brief re-orient after the hop
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		WIZARD_BLINK_LINES[randi() % WIZARD_BLINK_LINES.size()])


## Slain/fled/budget: file the wizard's arc for the Gazette.
func _wizard_departed(u: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return
	var note := "ZORBLAX cast %d spells (%d fizzled, %d blinks)" % [
		int(u.get("wizard_casts", 0)),
		int(u.get("wizard_fizzles", 0)),
		int(u.get("wizard_blinks", 0)),
	]
	if not bool(u.get("alive", false)):
		note += " (de-robed)"
	dlog.record_note(log_id, note)


## Count Bastard: angry but killable nuisance, never a killer (HTML:
## 600 HP, 0 dmg, charges at a RANDOM town hall, rants taunts, leaves).
## Ports the HTML charge -> rant -> leave phases.
func _tick_bastard(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if u.get("bastard_hall", null) == null:
		var halls: Array[Dictionary] = []
		for b: Dictionary in _gs.buildings:
			if b.get("alive", false) \
					and String(b.get("type", "")) in ["town_hall", "hall"]:
				halls.append(b)
		if not halls.is_empty():
			u["bastard_hall"] = halls[randi_range(0, halls.size() - 1)]
		else:
			u["bastard_hall"] = {}
	var hall: Dictionary = u.get("bastard_hall", {})
	if hall.is_empty() or not hall.get("alive", false):
		_tick_wanderer(u, speed, delta)
		return
	var hpos: Vector2 = hall.get("position", Vector2.ZERO)
	if upos.distance_to(hpos) <= 120.0:
		u["combat_state"] = "ranting"
		# Arrival story once — the town braces for insults.
		var tname: String = String(hall.get("town_name",
			hall.get("name", "the realm")))
		_announce_once(u, "bastard_arrival_story",
			"COUNT BASTARD SIGHTED — %s BRACES FOR INSULTS" % tname,
			"A caped nobleman with a monocle and opinions has arrived. " \
			+ "He has begun roasting citizens by name. Nobody is safe.")
		u["taunt_cd"] = float(u.get("taunt_cd", 0.0)) - delta
		if float(u.get("taunt_cd", 0.0)) <= 0.0:
			u["taunt_cd"] = BASTARD_INSULT_CD
			var victim: Dictionary = _bastard_pick_victim(u, upos)
			if victim.is_empty():
				# Nobody in roast range — fall back to a town taunt.
				var idx: int = (int(u.get("taunt_idx", 0)) + 1) \
					% COUNT_BASTARD_TAUNTS.size()
				u["taunt_idx"] = idx
				_gs.bus.unit_said.emit(int(u.get("id", 0)),
					COUNT_BASTARD_TAUNTS[idx])
			else:
				_bastard_insult(u, victim)
	else:
		u["combat_state"] = "charging"
		_walk_to(u, hpos, speed, delta)


## Nearest roastable citizen in range, preferring the never-insulted.
## Monsters, the dead, and the already-departed are never victims.
func _bastard_pick_victim(u: Dictionary, upos: Vector2) -> Dictionary:
	var seen: Array = u.get("bastard_victims", [])
	var best: Dictionary = {}
	var best_d2 := BASTARD_VICTIM_RADIUS * BASTARD_VICTIM_RADIUS
	var fallback: Dictionary = {}
	var fallback_d2 := BASTARD_VICTIM_RADIUS * BASTARD_VICTIM_RADIUS
	for x: Dictionary in _gs.units:
		if x == u or not bool(x.get("alive", false)):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var d2: float = upos.distance_squared_to(
			x.get("position", Vector2.ZERO))
		var xid: int = int(x.get("id", -1))
		if seen.has(xid):
			if d2 < fallback_d2:
				fallback = x
				fallback_d2 = d2
		elif d2 < best_d2:
			best = x
			best_d2 = d2
	return best if not best.is_empty() else fallback


## One personal roast + the victim's personality-matched reaction.
func _bastard_insult(u: Dictionary, v: Dictionary) -> void:
	var bid: int = int(u.get("id", 0))
	var vid: int = int(v.get("id", -1))
	var vname: String = SimPersonality.display_name(v)
	var vjob: String = String(v.get("job", "citizen"))
	var vtown: String = _bastard_town_name(v)
	var proud: float = SimPersonality.trait_of(v, "proud")
	var brave: float = SimPersonality.trait_of(v, "brave")
	var friendly: float = SimPersonality.trait_of(v, "friendly")
	var crude: float = SimPersonality.trait_of(v, "crude")
	var diligent: float = SimPersonality.trait_of(v, "diligent")
	var violent: float = SimPersonality.trait_of(v, "violent")
	var persona: String = SimPersonality.persona_of(v)
	# Pick the insult pool that fits the victim, then fill the tokens.
	var pool: Array[String] = BASTARD_INSULT_GENERIC
	if persona == "proud" or persona == "haughty" or proud > 0.7:
		pool = BASTARD_INSULT_PROUD
	elif diligent > 0.7:
		pool = BASTARD_INSULT_DILIGENT
	elif brave < 0.3 or persona == "worried":
		pool = BASTARD_INSULT_COWARD
	elif friendly > 0.7 or persona == "jolly":
		pool = BASTARD_INSULT_FRIENDLY
	elif crude > 0.7:
		pool = BASTARD_INSULT_CRUDE
	var insult: String = String(pool[randi() % pool.size()])
	insult = insult.replace("{name}", vname).replace("{job}", vjob) \
		.replace("{town}", vtown)
	# 100% offline/scripted — NPC dialogue is never generated.
	_gs.bus.unit_said.emit(bid, insult)
	var n: int = int(u.get("bastard_insults", 0)) + 1
	u["bastard_insults"] = n
	var victims: Array = u.get("bastard_victims", [])
	if not victims.has(vid):
		victims.append(vid)
	u["bastard_victims"] = victims
	var mood := SimMood.new()
	# Personality-matched reaction (Jeremy 2026-10-06 social-consequences
	# brief: NPCs get enraged or laugh depending on the target).
	if persona == "proud" or persona == "haughty" or proud > 0.7 \
			or violent > 0.75:
		# ENRAGED: anger, a thrown punch, a shouted comeback.
		mood.nudge(v, "angry", 0.55)
		var punch := randf_range(BASTARD_PUNCH_MIN, BASTARD_PUNCH_MAX)
		if _combat != null:
			_combat.damage_unit(bid, punch,
				String(v.get("faction", "")), vid, "punch")
		u["bastard_punches"] = int(u.get("bastard_punches", 0)) + 1
		var cb: String = String(BASTARD_COMEBACKS_ANGRY[
			randi() % BASTARD_COMEBACKS_ANGRY.size()])
		_gs.bus.unit_said.emit(vid,
			cb.replace("{job}", vjob).replace("{name}", vname))
	elif persona == "jolly" or friendly > 0.7:
		# LAUGHS IT OFF: amusement, a laugh line, no punch.
		mood.nudge(v, "happy", 0.45)
		_gs.bus.unit_said.emit(vid, String(BASTARD_LAUGHS[
			randi() % BASTARD_LAUGHS.size()]))
	elif brave < 0.3 or persona == "worried":
		# COWERS: fear, a whimper.
		mood.nudge(v, "scared", 0.5)
		_gs.bus.unit_said.emit(vid, String(BASTARD_WHIMPERS[
			randi() % BASTARD_WHIMPERS.size()]))
	else:
		# ANNOYED: a grumbled comeback.
		mood.nudge(v, "angry", 0.25)
		_gs.bus.unit_said.emit(vid, String(BASTARD_COMEBACKS_ANNOYED[
			randi() % BASTARD_COMEBACKS_ANNOYED.size()]))
	# The roast spreads as hearsay — social consequences.
	if n % BASTARD_RUMOR_EVERY == 0 and _gs.phone_sys != null \
			and _gs.phone_sys.hearsay != null:
		_gs.phone_sys.hearsay.seed_rumor(
			"Count Bastard publicly humiliated %s the %s in %s: \"%s\"" \
			% [vname, vjob, vtown, insult],
			"bastard_insult", "bastard:%d" % vid, 0.7, vid,
			false, SimHearsay.TRUTH_TRUE)
	# Milestone notes feed the Gazette summary.
	if n == 5 or n == 10 or n == 20 or n == 35:
		var log_id: int = int(u.get("disaster_log_id", -1))
		if log_id >= 0:
			dlog.record_note(log_id, "INSULTS %d (punches taken: %d)" \
				% [n, int(u.get("bastard_punches", 0))])


## Town name for a unit record (falls back to the realm).
func _bastard_town_name(v: Dictionary) -> String:
	var tid: int = int(v.get("town_id", -1))
	if tid >= 0:
		var t: Dictionary = _gs.towns.get(tid, {})
		if not t.is_empty():
			return String(t.get("name", "the realm"))
	return "the realm"


## Departure hook — wired into _start_leaving and _check_dead_disaster.
## Records the final tally for the Gazette summary and lifts the mood of
## the town he tormented.
func _bastard_departed(u: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	var n: int = int(u.get("bastard_insults", 0))
	var p: int = int(u.get("bastard_punches", 0))
	if log_id >= 0:
		dlog.record_note(log_id,
			"INSULTS %d PUNCHES %d" % [n, p])
	var hall: Dictionary = u.get("bastard_hall", {})
	if not hall.is_empty():
		# The torment is over — nearby citizens breathe again.
		var hpos: Vector2 = hall.get("position", Vector2.ZERO)
		var mood := SimMood.new()
		for x: Dictionary in _gs.units:
			if not bool(x.get("alive", false)):
				continue
			if String(x.get("faction", "")) == MONSTER_FACTION:
				continue
			if hpos.distance_to(x.get("position", Vector2.ZERO)) \
					<= BASTARD_VICTIM_RADIUS * 1.5:
				mood.nudge(x, "happy", 0.25)
	if bool(u.get("alive", false)):
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"I've said what needed saying. You're all welcome.")


## Jeremy 2026-10-04 (massive-dev): HOA KAREN behavior. She flies (straight
## lines — brooms ignore terrain) to the richest town, orbits its hall, and
## issues a citation every KAREN_CITE_INTERVAL seconds: a gold fine plus a
## citation on the building. At KAREN_LIEN_AT citations the building is
## LIENED — its production pauses until she leaves or is slain.
## 2026-10-07 flesh-out: Karen Gristlethwaite, HOA President. She never
## fights back (dmg 0) — she fines: taking damage files an ASSAULT
## COMPLAINT (non-refundable surcharge on the attacker's faction), citation
## fines escalate per visit, she cites citizens as well as buildings, and
## she periodically demands to speak to the ruler.
func _tick_karen(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if not u.has("karen_hall_pos"):
		_karen_pick_town(u)
		_announce_once(u, "karen_announced",
			"KAREN GRISTLETHWAITE DEMANDS TO SPEAK TO YOUR MANAGER",
			"Karen Gristlethwaite, HOA President, has entered the realm " \
			+ "on a broom, waving a clipboard. Officials advise hiding " \
			+ "your lawn gnomes.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(KAREN_ARRIVE_LINES,
				"I'm the HOA President and this neighborhood is a DISGRACE."))
	_karen_check_assault(u, delta)
	# Ruler demands — she was promised a manager.
	var dcd: float = float(u.get("karen_demand_cd", 20.0)) - delta
	if dcd <= 0.0:
		dcd = KAREN_DEMAND_INTERVAL
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(KAREN_DEMAND_LINES,
				"I DEMAND to speak to the RULER of this town!"))
	u["karen_demand_cd"] = dcd
	var hall_pos: Vector2 = u.get("karen_hall_pos", upos)
	if upos.distance_to(hall_pos) > KAREN_ORBIT_RADIUS:
		u["combat_state"] = "swooping"
		_karen_fly_to(u, hall_pos, speed, delta)
		return
	# Orbit the hall.
	u["combat_state"] = "citing"
	var ang: float = float(u.get("karen_orbit_ang", 0.0)) + delta * 0.7
	u["karen_orbit_ang"] = ang
	var orbit := hall_pos + Vector2(cos(ang), sin(ang)) * KAREN_ORBIT_RADIUS
	_karen_fly_to(u, orbit, speed, delta)
	u["cite_cd"] = float(u.get("cite_cd", 0.0)) - delta
	if float(u.get("cite_cd", 0.0)) <= 0.0:
		u["cite_cd"] = KAREN_CITE_INTERVAL
		_karen_issue_citation(u)


## HP-drop scan: she never fights back, she files paperwork. Any damage
## taken since the last tick becomes an ASSAULT COMPLAINT against the
## nearest military unit's faction (or the town's, if none is in sight).
## Throttled so a soldier wailing on her files one complaint per cooldown.
func _karen_check_assault(u: Dictionary, delta: float) -> void:
	var cd: float = maxf(0.0, \
		float(u.get("karen_complaint_cd", 0.0)) - delta)
	u["karen_complaint_cd"] = cd
	var hp: float = float(u.get("hp", 700.0))
	var prev: float = float(u.get("karen_prev_hp", hp))
	u["karen_prev_hp"] = hp
	if hp >= prev - 0.5 or cd > 0.0:
		return
	_karen_assault_complaint(u)


## One assault complaint: flat surcharge on the presumed attacker's
## faction, tracked separately from citation fines — assault surcharges
## are NON-refundable. That's the HOA way.
func _karen_assault_complaint(u: Dictionary) -> void:
	u["karen_complaint_cd"] = KAREN_ASSAULT_CD
	u["karen_complaints"] = int(u.get("karen_complaints", 0)) + 1
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var faction := ""
	var best_d2 := KAREN_ASSAULT_RADIUS * KAREN_ASSAULT_RADIUS
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var d2: float = upos.distance_squared_to(
			x.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			faction = String(x.get("faction", ""))
	if faction == "":
		# No soldier in sight — she bills the town for allowing it.
		faction = _karen_town_faction(u)
	if faction != "" and _gs.resources != null:
		_gs.resources.add_resource(faction, "gold", -KAREN_ASSAULT_FINE)
	var af: Dictionary = u.get("karen_assault_fines", {})
	af[faction] = float(af.get(faction, 0.0)) + KAREN_ASSAULT_FINE
	u["karen_assault_fines"] = af
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id >= 0:
		dlog.record_note(log_id,
			"ASSAULT COMPLAINT filed against %s ($%d surcharge)" % [
				faction if faction != "" else "nobody", int(KAREN_ASSAULT_FINE)])
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		_pick_line(KAREN_ASSAULT_LINES,
			"ASSAULT! That's a $25 surcharge and I'm telling the board!"))


## Faction of the town she's orbiting (first living faction found there).
func _karen_town_faction(u: Dictionary) -> String:
	var town_id: int = int(u.get("karen_town", -1))
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if int(b.get("town_id", -2)) != town_id:
			continue
		var f := String(b.get("faction", ""))
		if f != "" and f != MONSTER_FACTION:
			return f
	return ""


## Jeremy 2026-10-04: JESUS disaster. He spawns at a random map edge and
## walks straight to the opposite edge, firing his sawn-off shotgun at
## nearby units and buildings every JESUS_FIRE_CD seconds. Shotgun blasts
## use the projectile system with splash damage. He smokes a cigarette
## the whole time (visual only — the renderer draws the cig). Despawns
## at the far edge or when his budget runs out.
const JESUS_FIRE_CD := 2.5        # seconds between shotgun blasts
const JESUS_FIRE_RANGE := 380.0   # targeting range for blasts
const JESUS_SPLASH := 90.0        # shotgun spread radius
const JESUS_DAILY_CHANCE := 0.08  # daily spawn chance (after day 5)
const JESUS_MIN_DAY := 5


func _tick_jesus(u: Dictionary, dmg: float, speed: float,
		delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	# Pick the far-edge target on first tick.
	if not u.has("jesus_target"):
		u["jesus_target"] = _jesus_far_edge(upos)
		# Arrival headline — filed once via the disaster log record.
		var log_id0: int = int(u.get("disaster_log_id", -1))
		if log_id0 >= 0 and _gs.court_sys != null \
				and _gs.court_sys.has_method("publish_story"):
			_gs.court_sys.publish_story(
				"LOCAL MAN RETURNS WITH SHOTGUN",
				"A robed figure has entered the realm firing a sawn-off "
				+ "shotgun and smoking. Officials advise ducking.",
				"disaster")
	var target: Vector2 = u.get("jesus_target", upos)
	# Reached the far edge: leave.
	if upos.distance_to(target) < 80.0:
		_start_leaving(u)
		return
	# Walk toward the far edge.
	u["combat_state"] = "marching"
	_walk_to(u, target, speed, delta)
	# Fire the shotgun at the nearest valid target in range.
	u["fire_cd"] = float(u.get("fire_cd", 0.0)) - delta
	if float(u.get("fire_cd", 0.0)) > 0.0:
		return
	var best_id := -1
	var best_bld := -1
	var best_pos := Vector2.INF
	var best_d2 := JESUS_FIRE_RANGE * JESUS_FIRE_RANGE
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var d2: float = upos.distance_squared_to(
			x.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best_id = int(x.get("id", -1))
			best_bld = -1
			best_pos = x.get("position", Vector2.ZERO)
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best_id = -1
			best_bld = int(b.get("id", -1))
			best_pos = b.get("position", Vector2.ZERO)
	if best_pos == Vector2.INF:
		return  # nobody in range — keep marching
	u["fire_cd"] = JESUS_FIRE_CD
	u["combat_state"] = "attacking"
	_combat.fire_projectile(upos, best_id, best_pos, "cannonball",
		dmg, JESUS_SPLASH, MONSTER_FACTION, 600.0)


## Opposite map edge from the spawn point (straight march across).
func _jesus_far_edge(from: Vector2) -> Vector2:
	var bx: float = world_bounds.size.x
	var by: float = world_bounds.size.y
	# Pick the edge farthest from the spawn position.
	var cands := [
		Vector2(from.x, -150.0),
		Vector2(from.x, by + 150.0),
		Vector2(-150.0, from.y),
		Vector2(bx + 150.0, from.y),
	]
	var best: Vector2 = cands[0]
	var best_d2: float = from.distance_squared_to(best)
	for c: Vector2 in cands:
		var d2: float = from.distance_squared_to(c)
		if d2 > best_d2:
			best_d2 = d2
			best = c
	return best


## Straight-line flight (no pathfinding — she is above it all, literally).
func _karen_fly_to(u: Dictionary, target: Vector2, speed: float,
		delta: float) -> void:
	var p: Vector2 = u.get("position", Vector2.ZERO)
	var to: Vector2 = target - p
	var dist: float = to.length()
	if dist < 1.0:
		return
	var step: float = minf(dist, speed * delta)
	u["position"] = p + to / dist * step


## Pick the richest town (most completed buildings, any living faction) and
## remember its hall position for the orbit.
func _karen_pick_town(u: Dictionary) -> void:
	var best_town := -1
	var best_n := -1
	var counts := {}
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) == MONSTER_FACTION:
			continue
		if not bool(b.get("complete", true)):
			continue
		var tid: int = int(b.get("town_id", -1))
		counts[tid] = int(counts.get(tid, 0)) + 1
	for tid in counts.keys():
		if int(counts[tid]) > best_n:
			best_n = int(counts[tid])
			best_town = int(tid)
	u["karen_town"] = best_town
	u["karen_orbit_ang"] = randf() * TAU
	u["cite_cd"] = 3.0  # first citation comes fast — she's eager
	# Hall position: prefer a hall-type building, else town centroid.
	var hall_pos := Vector2.INF
	var cx := 0.0
	var cy := 0.0
	var n := 0
	for b2: Dictionary in _gs.buildings:
		if not b2.get("alive", false):
			continue
		if int(b2.get("town_id", -2)) != best_town:
			continue
		var bp: Vector2 = b2.get("position", Vector2.ZERO)
		cx += bp.x
		cy += bp.y
		n += 1
		if hall_pos == Vector2.INF \
				and String(b2.get("type", "")) in SimTowns.HALL_TYPES:
			hall_pos = bp
	if hall_pos == Vector2.INF and n > 0:
		hall_pos = Vector2(cx / n, cy / n)
	if hall_pos == Vector2.INF:
		hall_pos = u.get("position", Vector2.ZERO)
	u["karen_hall_pos"] = hall_pos
	# Flesh-out state: assault tracking, escalation tally, demand timer.
	u["karen_prev_hp"] = float(u.get("hp", 700.0))
	u["karen_cite_total"] = 0
	u["karen_complaints"] = 0
	u["karen_demand_cd"] = 20.0  # first demand comes fast — she's eager


## One citation: fine the town's faction, stamp the building, shout a line.
## At KAREN_LIEN_AT citations the building is liened (production pauses).
## 2026-10-07: fines escalate per visit (repeat-offender schedule); 30% of
## citations target a nearby citizen instead of a building; citing a hall
## uses the hall line pool. Exactly one shout per citation (plus the lien
## shout) — the speech-bubble budget is sacred.
func _karen_issue_citation(u: Dictionary) -> void:
	if randf() < KAREN_UNIT_CITE_CHANCE \
			and _karen_issue_unit_citation(u):
		return
	var town_id: int = int(u.get("karen_town", -1))
	var cands: Array = []
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if int(b.get("town_id", -2)) != town_id:
			continue
		if not bool(b.get("complete", true)):
			continue
		cands.append(b)
	if cands.is_empty():
		return
	var b: Dictionary = cands[randi_range(0, cands.size() - 1)]
	var faction: String = String(b.get("faction", ""))
	# Repeat-offender schedule: every citation this visit makes the next
	# one pricier, capped. First citation always uses the base range.
	var total: int = int(u.get("karen_cite_total", 0))
	var mult: float = minf(KAREN_FINE_MULT_CAP,
		1.0 + KAREN_FINE_ESCALATION * total)
	var fine: float = snappedf(
		randf_range(KAREN_FINE_MIN, KAREN_FINE_MAX) * mult, 1.0)
	u["karen_cite_total"] = total + 1
	if _gs.resources != null:
		# add_resource clamps at 0 — a broke town can't go negative.
		_gs.resources.add_resource(faction, "gold", -fine)
	var fines: Dictionary = u.get("karen_fines", {})
	fines[faction] = float(fines.get(faction, 0.0)) + fine
	u["karen_fines"] = fines
	var n: int = int(b.get("hoa_citations", 0)) + 1
	b["hoa_citations"] = n
	var line: String
	if String(b.get("type", "")) in SimTowns.HALL_TYPES:
		line = _pick_line(KAREN_HALL_LINES,
			"I'm citing the HALL ITSELF. Nobody is above the covenants.")
	else:
		line = KAREN_CITATIONS[randi() % KAREN_CITATIONS.size()]
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		"%s ($%d fine)" % [line, int(fine)])
	if n >= KAREN_LIEN_AT and not bool(b.get("hoa_lien", false)):
		b["hoa_lien"] = true
		_announce_once(u, "karen_lien_announced",
			"KAREN PLACES FIRST LIEN — PRODUCTION HALTED",
			("Karen Gristlethwaite has liened a %s. Its production is " \
			+ "paused until she leaves or is evicted.") % String(
				b.get("type", "building")))
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"That's the THIRD violation. This property is LIENED.")
		var log_id: int = int(u.get("disaster_log_id", -1))
		if log_id >= 0:
			dlog.record_note(log_id,
				"LIEN placed on %s (%s)" % [
					String(b.get("type", "building")), faction])


## Citizen citation: a smaller personal fine on a nearby unit's faction,
## no lien. Returns false when no citizen is in range (caller falls back
## to a building citation). Counts toward the escalation tally.
func _karen_issue_unit_citation(u: Dictionary) -> bool:
	var hall_pos: Vector2 = u.get("karen_hall_pos",
		u.get("position", Vector2.ZERO))
	var cands: Array = []
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if x.get("position", Vector2.INF).distance_to(hall_pos) \
				> KAREN_UNIT_CITE_RADIUS:
			continue
		cands.append(x)
	if cands.is_empty():
		return false
	var x: Dictionary = cands[randi_range(0, cands.size() - 1)]
	var faction: String = String(x.get("faction", ""))
	var fine: float = snappedf(
		randf_range(KAREN_UNIT_FINE_MIN, KAREN_UNIT_FINE_MAX), 1.0)
	if _gs.resources != null:
		_gs.resources.add_resource(faction, "gold", -fine)
	var fines: Dictionary = u.get("karen_fines", {})
	fines[faction] = float(fines.get(faction, 0.0)) + fine
	u["karen_fines"] = fines
	u["karen_cite_total"] = int(u.get("karen_cite_total", 0)) + 1
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		"%s ($%d fine)" % [_pick_line(KAREN_UNIT_CITATIONS,
			"Loitering. ($%d fine)"), int(fine)])
	return true


## Clear every Karen lien in the world (she left or was slain).
func _karen_clear_liens() -> void:
	for b: Dictionary in _gs.buildings:
		if bool(b.get("hoa_lien", false)):
			b["hoa_lien"] = false
			b["hoa_citations"] = 0


## Slain: refund every CITATION fine she collected, lift the liens. Assault
## surcharges are non-refundable — that's the HOA way. The refund total
## goes on the ledger as a note; the Gazette story is filed by
## _publish_disaster_story's hoa_karen branch (single story, no dupes).
func _karen_slain(u: Dictionary) -> void:
	var fines: Dictionary = u.get("karen_fines", {})
	var total := 0.0
	if _gs.resources != null:
		for faction in fines.keys():
			var amt: float = float(fines[faction])
			total += amt
			_gs.resources.add_resource(String(faction), "gold", amt, true)
	var liens := 0
	for b: Dictionary in _gs.buildings:
		if bool(b.get("hoa_lien", false)):
			liens += 1
	_karen_clear_liens()
	var assault_total := 0.0
	for faction in u.get("karen_assault_fines", {}).keys():
		assault_total += float(u["karen_assault_fines"][faction])
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id >= 0:
		dlog.record_note(log_id, "REFUNDED $%d in fines" % int(total))
		dlog.record_note(log_id,
			("TALLY %d citations, %d liens, %d assault complaints " \
			+ "($%d non-refundable surcharges)") % [
				int(u.get("karen_cite_total", 0)), liens,
				int(u.get("karen_complaints", 0)), int(assault_total)])


## Departed (budget spent): liens lift, no refund — she keeps the fines.
## That's the HOA way.
func _karen_departed(u: Dictionary) -> void:
	var liens := 0
	for b: Dictionary in _gs.buildings:
		if bool(b.get("hoa_lien", false)):
			liens += 1
	_karen_clear_liens()
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id >= 0:
		var fines: Dictionary = u.get("karen_fines", {})
		var total := 0.0
		for faction in fines.keys():
			total += float(fines[faction])
		var assault_total := 0.0
		for faction in u.get("karen_assault_fines", {}).keys():
			assault_total += float(u["karen_assault_fines"][faction])
		dlog.record_note(log_id,
			("TALLY %d citations, %d liens, %d assault complaints " \
			+ "($%d kept, no refund)") % [
				int(u.get("karen_cite_total", 0)), liens,
				int(u.get("karen_complaints", 0)),
				int(total + assault_total)])
	if _gs.court_sys != null and _gs.court_sys.has_method("publish_story"):
		_gs.court_sys.publish_story(
			"KAREN GRISTLETHWAITE LEAVES TO FILE A COMPLAINT WITH CORPORATE",
			"She'll be back. They always come back.",
			"disaster")


## Jeremy 2026-10-04 (massive-dev): rare natural HOA visit, like the priest.
func _maybe_spawn_hoa_karen() -> void:
	if _gs.day_number == int(_karen_day):
		return
	_karen_day = _gs.day_number
	if _gs.day_number < KAREN_MIN_DAY:
		return
	if randf() < KAREN_DAILY_CHANCE:
		spawn("hoa_karen", _map_edge_point())


## Jeremy 2026-10-04: JESUS — small daily chance to walk across the map
## with a shotgun. Never on the calendar, never before day 5.
func _maybe_spawn_jesus() -> void:
	if _gs.day_number == int(_jesus_day):
		return
	_jesus_day = _gs.day_number
	if _gs.day_number < JESUS_MIN_DAY:
		return
	if randf() < JESUS_DAILY_CHANCE:
		spawn("jesus", _map_edge_point())


## ---- Jeremy 2026-10-07 (wake deep-disasters): the newcomers ------------
## Three original joke disasters — singletons, 0 damage, pure chaos.
## SEAGULL SWARM steals food and craps on buildings; THE TAXMAN garnishes
## the richest treasury; BOOZE OOZE throws an involuntary party.

const GULL_DAILY_CHANCE := 0.05
const GULL_MIN_DAY := 6
const GULL_ORBIT_RADIUS := 170.0
const GULL_STEAL_CD := 8.0
const GULL_STEAL_MIN := 6.0
const GULL_STEAL_MAX := 14.0
const GULL_CRAP_T := 60.0
const GULL_CRAP_CHANCE := 0.5
const GULL_AURA_RADIUS := 90.0
const SEAGULL_SQUAWKS := [
	"MINE!",
	"Nice chips, idiot.",
	"Your lunch is OUR lunch now.",
	"CAW! (That means 'pay up.')",
	"We saw you drop that fry. It's ours.",
	"This town's garbage is exquisite.",
	"Ever been mugged by forty birds? You have now.",
	"Bullseye. Heh.",
]

const TAXMAN_DAILY_CHANCE := 0.03
const TAXMAN_MIN_DAY := 12
const TAXMAN_AUDIT_CD := 15.0
const TAXMAN_RATE := 0.08
const TAXMAN_MIN := 10.0
const TAXMAN_MAX := 250.0
const TAXMAN_DREAD_RADIUS := 220.0  # audit-dread aura around a planted taxman
const TAXMAN_DREAD_RATE := 6.0      # stress/sec for citizens in the aura
const TAXMAN_DREAD_BARK_AT := 35.0  # stress where citizens start complaining
const TAXMAN_DREAD_BARK_CD := 14.0  # per-citizen complaint cooldown (sec)
const TAXMAN_RELIEF_RADIUS := 260.0 # slain relief burst radius
const TAXMAN_RELIEF_STRESS := 45.0  # stress wiped when the taxman is slain
const TAXMAN_LINES := [
	"I'm going to need to see your receipts.",
	"Back taxes. With interest. And fees.",
	"Your deductions are... creative. DENIED.",
	"The crown thanks you for your involuntary contribution.",
	"I'm afraid your gold is now OUR gold.",
	"Resistance is futile. Payment is mandatory.",
	"Stamp. Stamp. STAMP. All in order. For me.",
	"Let's go through your ledger. Line by line. All of it.",
	"That write-off is adorable. Also denied.",
	"Your gold has been pre-approved for confiscation.",
	"Form 88-B, subsection 'gimme'. Sign here.",
	"I'm not saying you're evading. I'm just writing it down.",
	"Every coin accounted for. Mostly mine now.",
	"The audit never ends. It merely pauses between visits.",
]
const TAXMAN_ARRIVE_LINES := [
	"TAXMAN HERE. Official business. Everyone stay calm and form an orderly line.",
	"I've reviewed your realm's finances. We'll be taking it from here.",
	"Knock knock. It's the revenue service. Open the vault.",
]
const TAXMAN_DEPART_LINES := [
	"Audit complete. Pleasure doing business. It wasn't.",
	"All forms filed in triplicate. You're welcome.",
	"Remember: the taxman always collects. Eventually. Again.",
]
const TAXMAN_DREAD_BURSTS := [
	"He's looking at MY receipts!",
	"Quick, hide the ledger!",
	"I paid everything! I swear!",
	"Why is he STAMPING so loud?",
	"My gold... my beautiful gold...",
	"Don't make eye contact with the auditor.",
	"Somebody do something! Legally!",
	"I have deductions! I HAVE DEDUCTIONS!",
]

const OOZE_DAILY_CHANCE := 0.04
const OOZE_MIN_DAY := 8
const OOZE_RADIUS := 130.0
const OOZE_SHOUT_CD := 7.0
const OOZE_LINES := [
	"WOOO! PARTY PUDDLE!",
	"Drink me! (Do not drink me.)",
	"Who wants a hug? I'm eight percent alcohol.",
	"The floor is beer! The floor is beer!",
	"I love you guys. You're my best friends.",
	"Shots! Shots! Shots! (I'm the shot.)",
	"Your liver called. It surrenders.",
	"I've been aging since this morning. Respect me.",
	"Bottoms up! All of you! Simultaneously!",
	"The foam must flow.",
	"I contain multitudes. And yeast.",
	"Somebody's getting promoted to designated oozewalker.",
]

## Wake massive-dev 2026-10-07: BARON VON FOAM — the Sentient Beer Puddle
## gets the Gristlethwaite treatment. The old tick just wiped stress and
## shouted 6 party lines; now the party has consequences. Citizens in the
## aura build drunkenness (0-100, ~17 s to blackout); drunk workers work
## slower (WorkerAI reads DisasterSim.drunk_work_mult); the Baron soaks
## buildings so the party lingers after he oozes on; and the morning
## after brings hangovers. Named identity, slurred-line escalation, a
## "too drunk to work" Gazette beat, TALLY ledger, a slain burst, and the
## missing departed hook (the ledger never closed before — a real dead
## end).
const OOZE_NAME := "Baron von Foam"
const OOZE_TITLE := "Baron von Foam, the Sentient Beer Puddle"
const OOZE_DRUNK_RATE := 6.0        # drunk/sec in the aura
const OOZE_DRUNK_DECAY := 1.5       # drunk/sec everywhere (ambient tick)
const OOZE_DRUNK_MAX := 100.0
const OOZE_SLURRED_AT := 50.0       # avg aura drunk -> slurred shout pool
const OOZE_DRUNK_BEAT := 80.0       # first citizen this drunk -> Gazette beat
const OOZE_SOAK_CD := 20.0          # seconds between beer soakings
const OOZE_SOAK_RADIUS := 260.0     # building soak pick radius
const OOZE_SOAK_T := 90.0           # soaked buildings stay wet this long
const OOZE_SOAK_AURA := 130.0       # soaked buildings keep the party going
const OOZE_SLAIN_BURST_RADIUS := 220.0
const OOZE_SLAIN_BURST_DRUNK := 60.0
const OOZE_HANGOVER_T := 120.0
const OOZE_HANGOVER_STRESS := 25.0
const OOZE_HANGOVER_DRUNK_EQUIV := 40.0  # hangover works like drunk 40
const OOZE_DRUNK_BARK_CD := 25.0    # per-unit cooldown on drunk barks
const OOZE_WORK_PENALTY := 0.006    # work x (1 - drunk * 0.006)
const OOZE_WORK_FLOOR := 0.4        # blackout drunk still does 40%
const OOZE_ARRIVE_LINES := [
	"I AM BARON VON FOAM! The party is MANDATORY!",
	"Good evening! I am a baron AND a beverage!",
	"Your town looked thirsty. I fixed it. You're welcome.",
]
const OOZE_SLURRED_LINES := [
	"I lurve you guyssh. All of yoush. Both of yoush.",
	"The room is spinning. I'm the room.",
	"One more round! (I am the round.)",
	"Shhh. The floor is a boat now.",
	"I've never been drunker and I've been beer for YEARS.",
	"Your facesh are all so... facey.",
]
const OOZE_DRUNK_BURSTS := [
	"I love you, man. No, YOU hang up.",
	"I'm not drunk, you're drunk. We're ALL drunk!",
	"The shift can wait. The Baron cannot.",
	"I can see sounds right now.",
	"Promote me. I deserve it. I can feel it.",
	"My house is also beer now. Everything is beer.",
]
const OOZE_SOAK_LINES := [
	"This one's getting the full foam treatment!",
	"Consider yourself BAPTIZED! In lager!",
	"Splash zone! You! Yes, you, the load-bearing wall!",
]


## Work-speed multiplier for a unit with drunkenness/hangover. Static so
## WorkerAI can call it without a DisasterSim instance (and so tests can
## pin the formula).
static func drunk_work_mult(unit: Dictionary) -> float:
	var d: float = float(unit.get("drunk", 0.0))
	if float(unit.get("hangover_t", 0.0)) > 0.0:
		d = maxf(d, OOZE_HANGOVER_DRUNK_EQUIV)
	return maxf(OOZE_WORK_FLOOR, 1.0 - d * OOZE_WORK_PENALTY)

## Wake rapid-iteration 2026-10-07: Doom Prophet tuning.
const PROPHET_DAILY_CHANCE := 0.035
const PROPHET_MIN_DAY := 8
const PROPHET_AURA_RADIUS := 140.0  # doom-preach dread radius
const PROPHET_STRESS_RATE := 6.0    # stress/sec for citizens in radius
const PROPHET_SHOUT_CD := 7.0
const PROPHET_FLEE_RADIUS := 220.0  # military inside this -> he bolts
const PROPHET_DOOM_LINES := [
	"THE END IS NIGH! I saw it in a puddle!",
	"Repent! The sky is falling! Probably!",
	"I did the math! We're all doomed! Ish!",
	"Doomsday is Tuesday! Bring snacks!",
	"The stars say: yikes.",
	"The gnomes laughed at me. WHO'S LAUGHING NOW?",
]
const PROPHET_FLEE_LINES := [
	"I DIDN'T SIGN UP FOR THIS!",
	"THE PROPHECY DIDN'T MENTION SWORDS!",
	"A strategic retreat! The stars demand it!",
]


## File a one-time arrival story for a newcomer disaster.
func _announce_once(u: Dictionary, flag: String, headline: String,
		body: String) -> void:
	if bool(u.get(flag, false)):
		return
	u[flag] = true
	if _gs.court_sys != null \
			and _gs.court_sys.has_method("publish_story"):
		_gs.court_sys.publish_story(headline, body, "disaster")


func _maybe_spawn_seagulls() -> void:
	if _gs.day_number == int(_gull_day):
		return
	_gull_day = _gs.day_number
	if _gs.day_number < GULL_MIN_DAY:
		return
	if randf() < GULL_DAILY_CHANCE:
		spawn("seagull_swarm", _map_edge_point())


func _maybe_spawn_taxman() -> void:
	if _gs.day_number == int(_tax_day):
		return
	_tax_day = _gs.day_number
	if _gs.day_number < TAXMAN_MIN_DAY:
		return
	if randf() < TAXMAN_DAILY_CHANCE:
		spawn("taxman", _map_edge_point())


func _maybe_spawn_ooze() -> void:
	if _gs.day_number == int(_ooze_day):
		return
	_ooze_day = _gs.day_number
	if _gs.day_number < OOZE_MIN_DAY:
		return
	if randf() < OOZE_DAILY_CHANCE:
		spawn("booze_ooze", _map_edge_point())


func _maybe_spawn_prophet() -> void:
	if _gs.day_number == int(_prophet_day):
		return
	_prophet_day = _gs.day_number
	if _gs.day_number < PROPHET_MIN_DAY:
		return
	if randf() < PROPHET_DAILY_CHANCE:
		spawn("doom_prophet", _map_edge_point())


## Prophet target: the most populous town (most alive non-monster units
## with a matching town_id). Falls back to a random town, then the spawn.
func _prophet_pick_town(u: Dictionary) -> void:
	var best: Dictionary = {}
	var best_pop := -1
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var tid: int = int(td.get("id", -1))
		var pop := 0
		for x: Dictionary in _gs.units:
			if not x.get("alive", false):
				continue
			if String(x.get("faction", "")) == MONSTER_FACTION:
				continue
			if int(x.get("town_id", -2)) == tid:
				pop += 1
		if pop > best_pop:
			best_pop = pop
			best = td
	if best.is_empty():
		best = _random_town()
	if best.is_empty():
		u["prophet_center"] = u.get("position", Vector2.ZERO)
		return
	u["prophet_center"] = best.get("position", u.get("position", Vector2.ZERO))
	u["prophet_town_name"] = String(best.get("name", "the realm"))


func _tick_prophet(u: Dictionary, speed: float, delta: float) -> void:
	u["age"] = float(u.get("age", 0.0)) + delta
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("prophet_center"):
		_prophet_pick_town(u)
		_announce_once(u, "prophet_announced",
			"A DOOM PROPHET COMETH",
			"A wild-eyed gnome waving a sign reading 'THE END IS NIGH' " \
			+ "is marching on " \
			+ String(u.get("prophet_town_name", "the realm")) \
			+ ". Citizens are rattled.")
	# Coward's courage: any military unit closing in sends him bolting.
	if _prophet_soldier_near(upos):
		u["prophet_fled"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			PROPHET_FLEE_LINES[randi() % PROPHET_FLEE_LINES.size()])
		_announce_once(u, "prophet_fled_story",
			"PROPHET FLED",
			"A soldier looked at the doom prophet funny and he fled " \
			+ "screaming for the map edge. The end is postponed.")
		_start_leaving(u)
		return
	# NOTE: budget expiry is handled by _tick_monster (generic path) before
	# _tick_prophet runs — _start_leaving routes through _prophet_departed,
	# which detects the budget case (alive + leaving + not fled) there.
	var center: Vector2 = u.get("prophet_center", upos)
	if upos.distance_to(center) > 100.0:
		u["combat_state"] = "marching"
		_walk_to(u, center, speed, delta)
		return
	# Planted in the plaza, preaching doom.
	u["combat_state"] = "preaching"
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if int(x.get("inside_building_id", 0)) > 0:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) > PROPHET_AURA_RADIUS:
			continue
		x["stress"] = minf(100.0,
			float(x.get("stress", 0.0)) + PROPHET_STRESS_RATE * delta)
		u["prophet_doomed"] = float(u.get("prophet_doomed", 0.0)) + delta
	u["shout_cd"] = float(u.get("shout_cd", 2.0)) - delta
	if float(u.get("shout_cd", 0.0)) <= 0.0:
		u["shout_cd"] = PROPHET_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			PROPHET_DOOM_LINES[randi() % PROPHET_DOOM_LINES.size()])


## True when any alive military unit is inside the prophet's flee radius.
func _prophet_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= PROPHET_FLEE_RADIUS:
			return true
	return false


## Departure/slain: file the doomsday outcome for the Gazette.
func _prophet_departed(u: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	# Budget expiry is detected here, not in _tick_prophet: _tick_monster
	# starts leaving on budget before the per-kind tick ever runs. Alive +
	# leaving + not fled can only be the budget path (slain units arrive
	# with alive == false via _check_dead_disaster).
	var shamed: bool = bool(u.get("alive", false)) \
		and not bool(u.get("prophet_fled", false))
	if log_id >= 0:
		var note := "DOOMED %d citizen-seconds" % int(
			float(u.get("prophet_doomed", 0.0)))
		if bool(u.get("prophet_fled", false)):
			note += " (fled screaming)"
		elif shamed:
			note += " (doomsday postponed)"
		dlog.record_note(log_id, note)
	if shamed:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"Recalculating... carry the two... hmm.")
		_announce_once(u, "prophet_shame_story",
			"DOOMSDAY POSTPONED",
			"The doom prophet's predicted end of the world failed to " \
			+ "occur. He is recalculating.")


## Wake 2026-10-07: Gig Gnome tuning.
const DRIVER_DAILY_CHANCE := 0.035
const DRIVER_MIN_DAY := 9
const DRIVER_AURA_RADIUS := 160.0  # delivery-anxiety radius
const DRIVER_STRESS_RATE := 5.0    # stress/sec for citizens in radius
const DRIVER_SHOUT_CD := 9.0
const DRIVER_FLEE_RADIUS := 220.0  # military inside this -> he bolts
const DRIVER_FEE_CD := 45.0        # seconds between delivery fees
const DRIVER_FEE_MIN := 10.0
const DRIVER_FEE_MAX := 25.0
const DRIVER_FEE_RATE := 0.05      # 5% of treasury per fee, clamped
const DRIVER_TIP_REFUND := 30.0    # gold refunded to the faction on flee
const DRIVER_DELIVERY_LINES := [
	"Your package is 8 stops away!",
	"GPS says I'm here! I am not here!",
	"Left at your door. A door. Somewhere.",
	"Delivery attempted. You were home. Doesn't matter.",
	"Proof of delivery: a blurry photo of a rock.",
	"Rate me 5 stars. The bag stays closed until you do.",
	"Tip your driver. I mean it. Please.",
]
const DRIVER_FEE_LINES := [
	"Delivery fee",
	"Service charge",
	"Small order fee",
	"Peak pricing",
]
const DRIVER_FLEE_LINES := [
	"MARKED AS DELIVERED! BYE!",
	"I'M NOT PAID ENOUGH FOR SWORDS!",
	"YOUR ORDER HAS BEEN CANCELLED!",
]


func _maybe_spawn_driver() -> void:
	if _gs.day_number == int(_driver_day):
		return
	_driver_day = _gs.day_number
	if _gs.day_number < DRIVER_MIN_DAY:
		return
	if randf() < DRIVER_DAILY_CHANCE:
		spawn("gig_gnome", _map_edge_point())


## Driver target: the most populous town (same rule as the prophet) —
## he goes where the most customers are. Falls back to a random town,
## then the spawn point.
func _driver_pick_town(u: Dictionary) -> void:
	var best: Dictionary = {}
	var best_pop := -1
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var tid: int = int(td.get("id", -1))
		var pop := 0
		for x: Dictionary in _gs.units:
			if not x.get("alive", false):
				continue
			if String(x.get("faction", "")) == MONSTER_FACTION:
				continue
			if int(x.get("town_id", -2)) == tid:
				pop += 1
		if pop > best_pop:
			best_pop = pop
			best = td
	if best.is_empty():
		best = _random_town()
	if best.is_empty():
		u["driver_center"] = u.get("position", Vector2.ZERO)
		u["driver_faction"] = ""
		return
	u["driver_center"] = best.get("position", u.get("position", Vector2.ZERO))
	u["driver_town_name"] = String(best.get("name", "the realm"))
	u["driver_faction"] = String(best.get("faction", ""))


func _tick_driver(u: Dictionary, speed: float, delta: float) -> void:
	u["age"] = float(u.get("age", 0.0)) + delta
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("driver_center"):
		_driver_pick_town(u)
		_announce_once(u, "driver_announced",
			"A GIG GNOME APPROACHES",
			"A delivery gnome with an insulated bag is circling " \
			+ String(u.get("driver_town_name", "the realm")) \
			+ ". He says your package is 8 stops away. " \
			+ "Delivery fees will apply.")
	# Coward's courage, gig edition: a soldier closing in and the order
	# gets marked "delivered" — he drops a refunded tip and speeds off.
	if _driver_soldier_near(upos):
		u["driver_fled"] = true
		var faction: String = String(u.get("driver_faction", ""))
		if faction != "" and _gs.resources != null:
			_gs.resources.add_resource(faction, "gold", DRIVER_TIP_REFUND)
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(DRIVER_FLEE_LINES, "MARKED AS DELIVERED! BYE!"))
		_announce_once(u, "driver_fled_story",
			"DRIVER SPED OFF",
			"A soldier approached and the spark driver marked the order " \
			+ "'delivered', dropped a refunded tip, and sped off for the " \
			+ "map edge. The package was never real.")
		_start_leaving(u)
		return
	# NOTE: budget expiry is handled by _tick_monster (generic path) before
	# _tick_driver runs — _start_leaving routes through _driver_departed,
	# which detects the budget case (alive + leaving + not fled) there.
	var center: Vector2 = u.get("driver_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "marching"
		_walk_to(u, center, speed, delta)
		return
	# In the neighborhood: lazy delivery circuit around the plaza — always
	# circling, never quite arriving.
	var wp: Vector2 = u.get("driver_wp", center)
	if upos.distance_to(wp) < 30.0:
		var ang := randf() * TAU
		var rad := 80.0 + randf() * 180.0
		wp = center + Vector2(cos(ang), sin(ang)) * rad
		u["driver_wp"] = wp
	u["combat_state"] = "delivering"
	_walk_to(u, wp, speed, delta)
	# Delivery anxiety: nearby citizens stress over their 8-stops-away order.
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if int(x.get("inside_building_id", 0)) > 0:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) > DRIVER_AURA_RADIUS:
			continue
		x["stress"] = minf(100.0,
			float(x.get("stress", 0.0)) + DRIVER_STRESS_RATE * delta)
		u["driver_doomed"] = float(u.get("driver_doomed", 0.0)) + delta
	# The meter is always running: a delivery fee every DRIVER_FEE_CD.
	u["fee_cd"] = float(u.get("fee_cd", 20.0)) - delta
	if float(u.get("fee_cd", 0.0)) <= 0.0:
		u["fee_cd"] = DRIVER_FEE_CD
		_driver_fee(u)
	u["shout_cd"] = float(u.get("shout_cd", 3.0)) - delta
	if float(u.get("shout_cd", 0.0)) <= 0.0:
		u["shout_cd"] = DRIVER_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(DRIVER_DELIVERY_LINES, "Your package is 8 stops away!"))


## One delivery fee: skim 5% of the town faction's treasury (clamped).
## A broke faction gets a guilt trip instead — never negative gold.
func _driver_fee(u: Dictionary) -> void:
	var faction: String = String(u.get("driver_faction", ""))
	if faction == "" or _gs.resources == null:
		return
	var gold: float = _gs.resources.get_amount(faction, "gold")
	if gold <= 0.0:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"No tip? Bold. Rude. Fine.")
		return
	var fee: float = snappedf(
		clampf(gold * DRIVER_FEE_RATE, DRIVER_FEE_MIN, DRIVER_FEE_MAX), 1.0)
	_gs.resources.add_resource(faction, "gold", -fee)
	u["driver_fees"] = float(u.get("driver_fees", 0.0)) + fee
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		"%s ($%d)" % [
			_pick_line(DRIVER_FEE_LINES, "Delivery fee"), int(fee)])


## True when any alive military unit is inside the driver's flee radius.
func _driver_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= DRIVER_FLEE_RADIUS:
			return true
	return false


## Departure/slain: file the delivery outcome for the Gazette.
func _driver_departed(u: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	# Budget expiry is detected here, not in _tick_driver: _tick_monster
	# starts leaving on budget before the per-kind tick ever runs. Alive +
	# leaving + not fled can only be the budget path (slain units arrive
	# with alive == false via _check_dead_disaster).
	var alive: bool = bool(u.get("alive", false))
	var fled: bool = bool(u.get("driver_fled", false))
	var fees: int = int(float(u.get("driver_fees", 0.0)))
	if log_id >= 0:
		var note := "SKIMMED %d gold" % fees
		if fled:
			note += " (fled; refunded %dg tip)" % int(DRIVER_TIP_REFUND)
		elif not alive:
			note += " (slain; fees refunded)"
		else:
			note += " (never delivered)"
		dlog.record_note(log_id, note)
	# Slain: he has been tipped — with a sword. All fees go back.
	if not alive and not fled and fees > 0:
		var faction: String = String(u.get("driver_faction", ""))
		if faction != "" and _gs.resources != null:
			_gs.resources.add_resource(faction, "gold", float(fees))
		_announce_once(u, "driver_slain_story",
			"TIP EXPECTED",
			"The spark driver has been tipped. With a sword. %d gold in " \
			% fees + "delivery fees was refunded to the treasury.")
	# Budget expiry: the order was never real.
	if alive and not fled:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"Still 8 stops away. Always 8 stops away.")
		_announce_once(u, "driver_shame_story",
			"DELIVERY NEVER CAME",
			"The spark driver circled the town for days and delivered " \
			+ "nothing. He is still 8 stops away. He will always be 8 " \
			+ "stops away.")


## Wake 2026-10-08: BILL THE BORG CRAB tuning. A cybernetic crab
## (original design) who scuttles in from the map edge and "assimilates"
## town technology — bolting useless cybernetic attachments onto
## buildings. Assimilated buildings run at BORG_EFFICIENCY_MULT and the
## occupants complain. He never destroys anything: he's "helping".
## A soldier closing in makes him eject his cybernetics (upgrades pop
## off) and scuttle away; slain, the same ejection happens.
const BORG_DAILY_CHANCE := 0.030
const BORG_MIN_DAY := 12
const BORG_ASSIMILATE_RADIUS := 220.0  # building must be this close
const BORG_ASSIMILATE_CD := 25.0       # seconds between upgrades
const BORG_EFFICIENCY_MULT := 0.85    # -15% on assimilated buildings
const BORG_FLEE_RADIUS := 220.0       # military inside this -> he bolts
const BORG_SHOUT_CD := 11.0
const BORG_COMPLAINT_RADIUS := 260.0  # occupants complain in this radius
const BORG_ARRIVE_LINES := [
	"WE ARE BILL. YOUR TOASTER WILL BE ASSIMILATED.",
	"BILL HAS ARRIVED. PREPARE YOUR TECHNOLOGY FOR IMPROVEMENT.",
	"GREETINGS. I AM BILL. I COME IN PEACE. AND METAL.",
]
const BORG_ASSIMILATE_LINES := [
	"RESISTANCE IS FUTILE. ALSO, NICE FARM.",
	"YOUR BARN HAS BEEN UPGRADED. YOU'RE WELCOME.",
	"ASSIMILATING... TOASTER INSTALLED.",
	"THIS TOWN HALL NOW HAS BLUETOOTH.",
	"UPGRADE COMPLETE. THE USB PORT DOES NOTHING. YET.",
	"YOUR TECHNOLOGY IS OURS. YOUR SNACKS ARE ALSO OURS.",
]
const BORG_FLEE_LINES := [
	"BILL HAS BEEN DEFEATED. EJECTING CYBERNETICS.",
	"FINE. KEEP YOUR PRIMITIVE HAMMERS.",
	"RETREATING. BILL WILL RETURN WITH BETTER CLAWS.",
]
const BORG_COMPLAINT_LINES := [
	"Why is there a toaster on the town hall?!",
	"My farm has a USB port now. It does nothing.",
	"The crab put antennas on my house!",
	"Bill 'upgraded' my workshop. It smells like ozone.",
]


## Work-speed multiplier for a Bill-assimilated building. Static so any
## system can call it without a DisasterSim instance (and so tests can
## pin the formula). Buildings are never "borg_upgraded" unless Bill
## bolted something onto them.
static func borg_building_mult(building: Dictionary) -> float:
	if bool(building.get("borg_upgraded", false)):
		return BORG_EFFICIENCY_MULT
	return 1.0


func _maybe_spawn_borg_crab() -> void:
	if _gs.day_number == int(_borg_day):
		return
	_borg_day = _gs.day_number
	if _gs.day_number < BORG_MIN_DAY:
		return
	if randf() < BORG_DAILY_CHANCE:
		spawn("borg_crab_bill", _map_edge_point())


## Bill target: the nearest town with buildings (he scuttles to the
## closest technology). Falls back to a random town, then the spawn.
func _borg_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", upos))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		best = _random_town()
	if best.is_empty():
		u["borg_center"] = u.get("position", Vector2.ZERO)
		return
	u["borg_center"] = best.get("position", u.get("position", Vector2.ZERO))
	u["borg_town_name"] = String(best.get("name", "the realm"))


## True when any alive military unit is inside Bill's flee radius.
func _borg_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= BORG_FLEE_RADIUS:
			return true
	return false


## Pick the nearest un-assimilated, complete, non-monster building in
## radius. Returns the building dict, or {} if none qualify.
func _borg_pick_building(upos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d2 := BORG_ASSIMILATE_RADIUS * BORG_ASSIMILATE_RADIUS
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) == MONSTER_FACTION:
			continue
		if not bool(b.get("complete", true)):
			continue
		if bool(b.get("borg_upgraded", false)):
			continue
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = b
	return best


## Bolt the cybernetics on: mark the building, shout, Gazette-notable.
func _borg_assimilate(u: Dictionary, b: Dictionary) -> void:
	b["borg_upgraded"] = true
	var targets: Array = u.get("borg_targets", [])
	targets.append(int(b.get("id", 0)))
	u["borg_targets"] = targets
	u["borg_upgrades"] = int(u.get("borg_upgrades", 0)) + 1
	var bname := String(b.get("name",
		String(b.get("type", "building"))))
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		_pick_line(BORG_ASSIMILATE_LINES, "RESISTANCE IS FUTILE."))
	# Occupants complain about the "upgrade".
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(b.get("position", Vector2.ZERO)) \
				> BORG_COMPLAINT_RADIUS:
			continue
		x["stress"] = minf(100.0,
			float(x.get("stress", 0.0)) + 8.0)
		if randf() < 0.35:
			_gs.bus.unit_said.emit(int(x.get("id", 0)),
				_pick_line(BORG_COMPLAINT_LINES, "Bill did this."))
	_announce_once(u, "borg_first_upgrade_story",
		"CYBERNETIC CRAB ASSIMILATES FARM EQUIPMENT",
		"A giant cybernetic crab named Bill has begun bolting useless " \
		+ "attachments onto " + String(u.get("borg_town_name", "a town")) \
		+ "'s buildings — the " + bname + " now sports a toaster. " \
		+ "Efficiency is down. Nobody asked for this.")


## Eject the cybernetics: every building Bill upgraded pops its
## attachments off. Called on flee AND on slain (defeat).
func _borg_eject_cybernetics(u: Dictionary) -> void:
	for b: Dictionary in _gs.buildings:
		if bool(b.get("borg_upgraded", false)):
			b["borg_upgraded"] = false


func _tick_borg_crab(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("borg_center"):
		_borg_pick_town(u)
		_announce_once(u, "borg_announced",
			"CYBERNETIC CRAB APPROACHES",
			"A giant cybernetic crab named Bill is scuttling toward " \
			+ String(u.get("borg_town_name", "the realm")) \
			+ ". He says your toaster will be assimilated. " \
			+ "Resistance is futile. Also, nice farm.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(BORG_ARRIVE_LINES, "WE ARE BILL."))
	# Coward's courage, crab edition: a soldier closing in and Bill
	# ejects his cybernetics — the upgrades pop off — and scuttles away.
	if _borg_soldier_near(upos):
		u["borg_fled"] = true
		_borg_eject_cybernetics(u)
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(BORG_FLEE_LINES, "EJECTING CYBERNETICS."))
		_announce_once(u, "borg_fled_story",
			"BILL SCUTTLED OFF",
			"A soldier approached and Bill the borg crab ejected his " \
			+ "cybernetics — toasters and USB ports popped off every " \
			+ "building — and scuttled sideways for the map edge.")
		_start_leaving(u)
		return
	# NOTE: budget expiry is handled by _tick_monster (generic path) before
	# _tick_borg_crab runs — _start_leaving routes through
	# _borg_crab_departed, which detects the budget case (alive + leaving
	# + not fled) there.
	var center: Vector2 = u.get("borg_center", upos)
	if upos.distance_to(center) > 140.0:
		u["combat_state"] = "scuttling"
		_walk_to(u, center, speed, delta)
		return
	# In the neighborhood: sidle between nearby buildings, looking for
	# technology to "improve".
	u["borg_cd"] = float(u.get("borg_cd", 8.0)) - delta
	if float(u.get("borg_cd", 0.0)) <= 0.0:
		u["borg_cd"] = BORG_ASSIMILATE_CD
		var b := _borg_pick_building(upos)
		if not b.is_empty():
			_borg_assimilate(u, b)
	# Crab drift: slow sideways sidle around the town center so he reads
	# as a crab, not a marcher.
	var wp: Vector2 = u.get("borg_wp", center)
	if upos.distance_to(wp) < 30.0:
		var ang := randf() * TAU
		var rad := 60.0 + randf() * 140.0
		# Bias perpendicular for the sideways scuttle feel.
		wp = center + Vector2(-sin(ang), cos(ang)) * rad
		u["borg_wp"] = wp
	u["combat_state"] = "scuttling"
	_walk_to(u, wp, speed * 0.6, delta)
	u["shout_cd"] = float(u.get("shout_cd", 4.0)) - delta
	if float(u.get("shout_cd", 0.0)) <= 0.0:
		u["shout_cd"] = BORG_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(BORG_ASSIMILATE_LINES, "RESISTANCE IS FUTILE."))


## Departure/slain: file the assimilation outcome for the Gazette.
func _borg_crab_departed(u: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	# Budget expiry is detected here, not in _tick_borg_crab: _tick_monster
	# starts leaving on budget before the per-kind tick ever runs. Alive +
	# leaving + not fled can only be the budget path (slain units arrive
	# with alive == false via _check_dead_disaster).
	var alive: bool = bool(u.get("alive", false))
	var fled: bool = bool(u.get("borg_fled", false))
	var n: int = int(u.get("borg_upgrades", 0))
	# Fled or slain: the cybernetics pop off. Budget expiry ("finished
	# helping"): he leaves the toasters bolted on — nobody pried them off.
	if fled or not alive:
		_borg_eject_cybernetics(u)
	if log_id >= 0:
		var note := "ASSIMILATED %d buildings" % n
		if fled:
			note += " (fled; upgrades ejected)"
		elif not alive:
			note += " (slain; upgrades ejected)"
		else:
			note += " (finished; left the toasters)"
		dlog.record_note(log_id, note)
	if not alive and not fled:
		_announce_once(u, "borg_slain_story",
			"BILL DE-ASSIMILATED",
			"Bill the borg crab has been defeated. His cybernetics " \
			+ "popped off %d buildings. " % n \
			+ "The toasters have been removed. The town is safe.")
	if alive and not fled:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"UPGRADES COMPLETE. BILL DEPARTS. YOU ARE WELCOME.")
		_announce_once(u, "borg_done_story",
			"BILL FINISHED 'HELPING'",
			"Bill the borg crab has finished upgrading the town and " \
			+ "scuttled away. %d buildings still sport useless " % n \
			+ "cybernetic attachments. Efficiency remains reduced " \
			+ "until someone pries the toasters off.")


## ---- Twister Sister ----------------------------------------------------
## Wake rapid-iteration 2026-10-08: a sentient glam-metal tornado.
## Wanders town to town. Her fling aura (130px, 2Hz) hurls citizens to
## random spots 220-380px away (10 dmg + 25s fling immunity, so nobody
## gets chain-flung), and buildings in her path take roof damage over
## time. Indoor citizens (inside_building_id > 0) are safe — the roof
## may go, but they're under it. Shouts metal-flavored lines on a
## cooldown. Budget expiry -> _start_leaving -> _twister_departed files
## the Gazette story. Singleton (spawn() gate).
const TWISTER_DAILY_CHANCE := 0.045
const TWISTER_MIN_DAY := 8
const TWISTER_FLING_RADIUS := 130.0
const TWISTER_FLING_MIN := 220.0
const TWISTER_FLING_MAX := 380.0
const TWISTER_FLING_DMG := 10.0
const TWISTER_IMMUNE_T := 25.0
const TWISTER_ROOF_DPS := 6.0
const TWISTER_SHOUT_CD := 9.0
const TWISTER_LINES := [
	"I WANNA ROCK... YOUR FOUNDATION!",
	"We're not gonna take it — WE'RE TAKING YOUR ROOF!",
	"WHEEE! Who ordered the spin cycle?!",
	"You call that a load-bearing wall? CUTE.",
	"This town needed a makeover anyway!",
	"Feel the wind beneath my... EVERYTHING!",
	"Encore? ENCORE?!",
]
var _twister_day: int = -1  # last day the twister roll ran


func _maybe_spawn_twister() -> void:
	if _gs.day_number == int(_twister_day):
		return
	_twister_day = _gs.day_number
	if _gs.day_number < TWISTER_MIN_DAY:
		return
	if randf() < TWISTER_DAILY_CHANCE:
		var u := spawn("twister_sister", _map_edge_point())
		if not u.is_empty():
			_announce_once(u, "twister_announced",
				"TWISTER SISTER HITS THE REALM",
				"A glam-metal tornado with teased hair and a tiny " \
				+ "guitar has touched down. Officials advise holding " \
				+ "onto your roof. And your grandma.")


## Nearest alive non-monster building — town-hopping emerges naturally.
func _twister_pick_target(upos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d2 := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) == MONSTER_FACTION:
			continue
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = b.get("position", Vector2.ZERO)
	if best == Vector2.INF:
		best = Vector2(world_bounds.size.x * 0.5,
			world_bounds.size.y * 0.5)
	return best


func _tick_twister(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var target: Vector2 = u.get("twister_target", Vector2.INF)
	if target == Vector2.INF or upos.distance_to(target) < 140.0:
		target = _twister_pick_target(upos)
		u["twister_target"] = target
	_walk_to(u, target, speed, delta)
	u["combat_state"] = "rampaging"
	# Fling aura at 2 Hz.
	u["twister_fling_cd"] = float(u.get("twister_fling_cd", 0.0)) - delta
	if float(u.get("twister_fling_cd", 0.0)) <= 0.0:
		u["twister_fling_cd"] = 0.5
		_twister_fling_aura(u, upos)
	# Roof damage over time.
	_twister_roof_damage(u, upos, delta)
	# Shout on cooldown.
	u["twister_shout_cd"] = float(u.get("twister_shout_cd",
		TWISTER_SHOUT_CD)) - delta
	if float(u.get("twister_shout_cd", 0.0)) <= 0.0:
		u["twister_shout_cd"] = TWISTER_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			TWISTER_LINES[randi() % TWISTER_LINES.size()])


## Hurl every eligible citizen in the aura to a random nearby spot.
## Decrements fling immunity for all units (0.5s per aura tick).
func _twister_fling_aura(u: Dictionary, upos: Vector2) -> void:
	var r2: float = TWISTER_FLING_RADIUS * TWISTER_FLING_RADIUS
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		var it: float = float(x.get("twister_immune_t", 0.0))
		if it > 0.0:
			x["twister_immune_t"] = it - 0.5
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if int(x.get("inside_building_id", 0)) > 0:
			continue  # indoors: the roof may go, they're under it
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if upos.distance_squared_to(xpos) > r2:
			continue
		_twister_fling(u, x)


## One fling: random direction, 220-380px, clamped to the map.
func _twister_fling(u: Dictionary, x: Dictionary) -> void:
	var ang: float = randf() * TAU
	var dist: float = randf_range(TWISTER_FLING_MIN, TWISTER_FLING_MAX)
	var dest: Vector2 = x.get("position", Vector2.ZERO) \
		+ Vector2(cos(ang), sin(ang)) * dist
	dest.x = clampf(dest.x, 60.0, world_bounds.size.x - 60.0)
	dest.y = clampf(dest.y, 60.0, world_bounds.size.y - 60.0)
	x["position"] = dest
	x["twister_immune_t"] = TWISTER_IMMUNE_T
	_combat.damage_unit(int(x.get("id", -1)), TWISTER_FLING_DMG,
		MONSTER_FACTION)
	u["twister_flung"] = int(u.get("twister_flung", 0)) + 1
	u["combat_state"] = "flinging"


## Roof damage: buildings in the aura take DPS; destroyed roofs count.
func _twister_roof_damage(u: Dictionary, upos: Vector2,
		delta: float) -> void:
	var r2: float = TWISTER_FLING_RADIUS * TWISTER_FLING_RADIUS
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) == MONSTER_FACTION:
			continue
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		if upos.distance_squared_to(bpos) > r2:
			continue
		var hp_before: float = float(b.get("hp", 0.0))
		_combat.damage_building(int(b.get("id", -1)),
			TWISTER_ROOF_DPS * delta, MONSTER_FACTION)
		if hp_before > 0.0 and float(b.get("hp", 0.0)) <= 0.0:
			u["twister_roofs"] = int(u.get("twister_roofs", 0)) + 1


func _twister_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	var flung: int = int(u.get("twister_flung", 0))
	var roofs: int = int(u.get("twister_roofs", 0))
	if alive:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"THANK YOU, GOODNIGHT! Tip your waitress!")
		_announce_once(u, "twister_done_story",
			"TWISTER SISTER LEAVES TOWN",
			"The glam-metal tornado has spun off into the sunset. " \
			+ "She flung %d citizens and ripped %d roofs clean off. " \
			% [flung, roofs] \
			+ "The town will be finding debris for weeks.")
	else:
		_announce_once(u, "twister_slain_story",
			"TWISTER SISTER DISPERSED",
			"Somehow, impossibly, the town dispersed a tornado. She " \
			+ "flung %d citizens before she went. " % flung \
			+ "Meteorologists are furious. Guitar sales spike.")


## Wake rapid-iteration 2026-10-08: BRAX THE KARAOKE BARBARIAN. A
## loinclothed barbarian storms the town hall with a lute and performs
## a 3-set power-ballad set list. 0 dmg — the weapon is his voice.
## Citizens in earshot gain secondhand-embarrassment stress; a few
## can't resist and join as backup singers (morale up, dignity down).
## A soldier closing in boos him off stage; when all 47 verses are
## sung he takes a bow and leaves. Singleton (spawn() gate).
const KARAOKE_DAILY_CHANCE := 0.04
const KARAOKE_MIN_DAY := 9
const KARAOKE_SETS := 3
const KARAOKE_SET_SECONDS := 75.0
const KARAOKE_RADIUS := 240.0
const KARAOKE_AURA_CD := 2.0     # aura application cadence (0.5 Hz)
const KARAOKE_STRESS_TICK := 2.0  # stress per aura application
const KARAOKE_SINGALONG_CHANCE := 0.06
const KARAOKE_FLEE_RADIUS := 200.0
const KARAOKE_SHOUT_CD := 12.0
const KARAOKE_LINES := [
	"♪ OOHHHH BABY, LIGHT MY TORCH OF LOOOOVE ♪",
	"This next one goes out to... ME!",
	"♪ DON'T STOP BRAVING... HOLD ONTO THAT FEEELING ♪",
	"*sniff* ...the lute is crying. I am crying.",
	"Verse 31 of 47. STAY WITH ME.",
	"♪ I WILL ALWAYS LOOOVE... THIS TAVERN! ♪",
	"You call THAT an encore?! LOUDER!",
]
const KARAOKE_COMPLAINT_LINES := [
	"Make it stop.",
	"My ears are bleeding.",
	"He's flat. FLAT.",
	"47 verses. FORTY-SEVEN.",
	"Somebody boo him. Somebody.",
	"That is NOT how the song goes.",
	"I can hear him THROUGH the walls.",
]
var _karaoke_day: int = -1  # last day the karaoke roll ran


func _maybe_spawn_karaoke() -> void:
	if _gs.day_number == int(_karaoke_day):
		return
	_karaoke_day = _gs.day_number
	if _gs.day_number < KARAOKE_MIN_DAY:
		return
	if randf() < KARAOKE_DAILY_CHANCE:
		spawn("karaoke_barbarian", _map_edge_point())


## Brax storms the nearest town — the stage picks him. Falls back to
## map center when the realm has no towns (mirrors _borg_pick_town).
func _karaoke_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["karaoke_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["karaoke_town_name"] = "the realm"
	else:
		u["karaoke_center"] = best.get("position", Vector2.ZERO)
		u["karaoke_town_name"] = String(
			best.get("name", "a town"))


## A soldier closing in is the heckler's veto — Brax gets booed off.
func _karaoke_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= KARAOKE_FLEE_RADIUS:
			return true
	return false


func _tick_karaoke(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("karaoke_center"):
		_karaoke_pick_town(u)
		_announce_once(u, "karaoke_announced",
			"KARAOKE BARBARIAN TAKES THE STAGE",
			"A loinclothed barbarian named Brax is dragging a lute " \
			+ "toward " + String(u.get("karaoke_town_name", "the realm")) \
			+ ". He only knows one song. It has 47 verses. " \
			+ "Lock up your ears.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(KARAOKE_LINES, "♪ OOHHHH BABY ♪"))
	# Booed off: a soldier closes in and the set ends early.
	if _karaoke_soldier_near(upos):
		u["karaoke_booed"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"BOOED?! The show must go on — ELSEWHERE.")
		_announce_once(u, "karaoke_booed_story",
			"BRAX BOOED OFF STAGE",
			"A soldier marched on the stage and Brax the karaoke " \
			+ "barbarian grabbed his lute and stormed off to boos. " \
			+ "The town's ears are saved. The backup singers are furious.")
		_start_leaving(u)
		return
	var center: Vector2 = u.get("karaoke_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "swaggering"
		_walk_to(u, center, speed, delta)
		return
	# On stage: perform the set list.
	u["combat_state"] = "belting"
	_karaoke_aura(u, upos, delta)
	u["karaoke_shout_cd"] = float(u.get("karaoke_shout_cd",
		KARAOKE_SHOUT_CD)) - delta
	if float(u.get("karaoke_shout_cd", 0.0)) <= 0.0:
		u["karaoke_shout_cd"] = KARAOKE_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(KARAOKE_LINES, "♪ OOHHHH BABY ♪"))
	u["karaoke_set_cd"] = float(u.get("karaoke_set_cd",
		KARAOKE_SET_SECONDS)) - delta
	if float(u.get("karaoke_set_cd", 0.0)) <= 0.0:
		u["karaoke_sets_done"] = int(u.get("karaoke_sets_done", 0)) + 1
		u["karaoke_set_cd"] = KARAOKE_SET_SECONDS
		if int(u.get("karaoke_sets_done", 0)) >= KARAOKE_SETS:
			u["karaoke_encore"] = true
			_start_leaving(u)


## The performance aura, applied on a 2s cadence: embarrassment stress
## for everyone in earshot, singalong conversion for the weak-willed.
func _karaoke_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["karaoke_aura_cd"] = float(u.get("karaoke_aura_cd", 0.0)) - delta
	if float(u.get("karaoke_aura_cd", 0.0)) > 0.0:
		return
	u["karaoke_aura_cd"] = KARAOKE_AURA_CD
	var r2: float = KARAOKE_RADIUS * KARAOKE_RADIUS
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_squared_to(upos) > r2:
			continue
		if bool(x.get("karaoke_singer", false)):
			continue  # backup singers are having the time of their lives
		# Secondhand embarrassment is a status effect.
		x["stress"] = minf(100.0,
			float(x.get("stress", 0.0)) + KARAOKE_STRESS_TICK)
		if randf() < KARAOKE_SINGALONG_CHANCE:
			x["karaoke_singer"] = true
			u["karaoke_singers"] = int(u.get("karaoke_singers", 0)) + 1
			var mood := SimMood.new()
			mood.nudge(x, "happy", 0.45)
			x["stress"] = maxf(0.0, float(x.get("stress", 0.0)) - 10.0)
			if randf() < 0.25:
				_gs.bus.unit_said.emit(int(x.get("id", 0)),
					_pick_line(KARAOKE_LINES, "♪ OOHHHH BABY ♪"))
		elif randf() < 0.35:
			_gs.bus.unit_said.emit(int(x.get("id", 0)),
				_pick_line(KARAOKE_COMPLAINT_LINES, "Make it stop."))


## Departure/slain: file the set-list outcome for the Gazette.
func _karaoke_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	var singers: int = int(u.get("karaoke_singers", 0))
	var sets: int = int(u.get("karaoke_sets_done", 0))
	if not alive:
		_announce_once(u, "karaoke_slain_story",
			"BRAX HAS LEFT THE BUILDING",
			"Somehow, impossibly, the town has silenced Brax the " \
			+ "karaoke barbarian — permanently. He got through %d " \
			% mini(sets, KARAOKE_SETS) \
			+ " of his 3 sets. The lute is being melted down. " \
			+ "Nobody will miss the lute.")
	elif bool(u.get("karaoke_encore", false)):
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"THANK YOU, GOODNIGHT! You've been a CAPTIVE audience!")
		_announce_once(u, "karaoke_done_story",
			"BRAX TAKES A BOW",
			"Brax the karaoke barbarian has sung all 47 verses and " \
			+ "taken a bow. %d citizens joined as backup singers. " % singers \
			+ "The town's ears will recover. The dignity will not.")
	elif bool(u.get("karaoke_booed", false)):
		pass  # booed story already filed at flee time
	else:
		_announce_once(u, "karaoke_left_story",
			"BRAX WANDERED OFF",
			"Brax the karaoke barbarian wandered off mid-verse, " \
			+ "lute under his arm, in search of a more appreciative " \
			+ "town. Nobody stopped him. Nobody waved goodbye.")


## Wake rapid-iteration 2026-10-08: YAPPER THE GOSSIP GNOME — the only
## disaster that weaponizes the rumor mill. He waddles to the most
## populous town, presses his ear trumpet to the tavern wall, and seeds
## REAL hearsay rumors about nearby citizens (kind "gossip", unknown
## truth — the mill does the rest: NPCs react, moods shift, the Gazette
## aggregates). 0 dmg; a soldier closing in makes him drop his quill
## and flee to the map edge.
const GOSSIP_DAILY_CHANCE := 0.04
const GOSSIP_MIN_DAY := 7
const GOSSIP_RADIUS := 280.0       # citizen-picking range
const GOSSIP_RUMOR_CD := 18.0      # seconds between seeded rumors
const GOSSIP_FLEE_RADIUS := 200.0  # soldier distance that routs him
const GOSSIP_SHOUT_CD := 12.0
const GOSSIP_LINES := [
	"Psst! You did NOT hear this from me!",
	"My ear trumpet NEVER lies!",
	"Oh, this one's JUICY.",
	"Don't tell anyone I told you. Tell EVERYONE.",
	"Quill's out. Somebody's DONE.",
]
const GOSSIP_RUMOR_TEMPLATES := [
	"%s the %s was spotted talking to their own reflection. The reflection looked concerned.",
	"%s the %s keeps a second, secret chamber pot. For guests.",
	"%s the %s named their axe. The axe has not forgiven them.",
	"%s the %s lost an argument with a chicken. The chicken tells everyone.",
	"%s the %s sleeps with a nightlight shaped like a tiny guillotine.",
	"%s the %s cried at a turnip harvest. A TURNIP.",
	"%s the %s irons their underwear. Pressed. Creased. Military corners.",
	"%s the %s was outbid at the market by their own grandmother.",
	"%s the %s practices evil laughter in the bathhouse. Badly.",
	"%s the %s got stuck in a barrel. Twice. Same barrel.",
]
var _gossip_day: int = -1  # last day the gossip roll ran


## ---- Wally the Warranty Salesman -------------------------------------------
## Door-to-door extended-warranty gnome. Picks the nearest complete
## building, walks up, and pitches for WARRANTY_PITCH_TIME seconds.
## Each finished pitch has WARRANTY_SALE_CHANCE of a "sale": the owning
## faction pays WARRANTY_PRICE gold for a warranty that covers nothing.
## No other disaster runs a sales route. 0 dmg, singleton, coward.
const WARRANTY_DAILY_CHANCE := 0.04
const WARRANTY_MIN_DAY := 7
const WARRANTY_PITCH_TIME := 8.0    # seconds per doorstep pitch
const WARRANTY_PITCH_RANGE := 130.0  # how close he stands to pitch
const WARRANTY_SALE_CHANCE := 0.35
const WARRANTY_PRICE := 30.0         # gold per "sale"
const WARRANTY_FLEE_RADIUS := 200.0  # soldier distance that routs him
const WARRANTY_SHOUT_CD := 6.0
const WARRANTY_PITCH_LINES := [
	"Your hut's factory warranty is EXPIRED!",
	"This is a LIMITED-TIME offer! Limited! Time! Offer!",
	"What if your roof just... fell off? Huh? EVER THINK OF THAT?",
	"Sign here. And here. Initial here. Don't read it, just sign.",
	"For only 30 gold, NOTHING bad will happen. Probably.",
	"Your neighbor bought one. Your neighbor is SMART.",
	"This warranty covers EVERYTHING. Except the things it doesn't.",
	"I'm not leaving until SOMEBODY signs something!",
	"Does your home come with... PEACE OF MIND? Didn't think so.",
	"Act now and I'll throw in a SECOND warranty. Same price. Twice.",
]
const WARRANTY_SALE_LINES := [
	"SOLD! Pleasure doing business! (The warranty covers nothing.)",
	"Congratulations! You're now protected against... things!",
	"Wise choice! Your hut is now 0% more warranted!",
]
const WARRANTY_NO_SALE_LINES := [
	"You'll be SORRY when your hut breaks!",
	"Fine! Enjoy your UNWARRANTED hut!",
	"Your loss! This offer EXPIRES! (It doesn't.)",
]
var _warranty_day: int = -1  # last day the warranty roll ran


func _maybe_spawn_warranty() -> void:
	if _gs.day_number == int(_warranty_day):
		return
	_warranty_day = _gs.day_number
	if _gs.day_number < WARRANTY_MIN_DAY:
		return
	if randf() < WARRANTY_DAILY_CHANCE:
		spawn("warranty_salesman", _map_edge_point())


## Wally works the nearest town — door to door means the CLOSEST door.
func _warranty_pick_target(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) == MONSTER_FACTION:
			continue
		if not bool(b.get("complete", true)):
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		var d2: float = upos.distance_squared_to(bp)
		if d2 < best_d2:
			best_d2 = d2
			best = b
	if best.is_empty():
		u["warranty_target_pos"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["warranty_target_bld"] = -1
	else:
		u["warranty_target_pos"] = best.get("position", Vector2.ZERO)
		u["warranty_target_bld"] = int(best.get("id", -1))


func _warranty_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= WARRANTY_FLEE_RADIUS:
			return true
	return false


## The "buyer": nearest living citizen to the pitched building.
func _warranty_pick_buyer(bpos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d2 := INF
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		var d2: float = bpos.distance_squared_to(xpos)
		if d2 < best_d2:
			best_d2 = d2
			best = x
	return best


## Resolve one finished pitch: sale or no sale.
func _warranty_resolve_pitch(u: Dictionary) -> void:
	var bpos: Vector2 = u.get("warranty_target_pos", Vector2.ZERO)
	var buyer: Dictionary = _warranty_pick_buyer(bpos)
	var uid: int = int(u.get("id", 0))
	if not buyer.is_empty() and randf() < WARRANTY_SALE_CHANCE:
		var faction: String = String(buyer.get("faction", ""))
		# add_resource clamps at 0 — a broke town can't go negative.
		_gs.resources.add_resource(faction, "gold", -WARRANTY_PRICE)
		u["warranty_sales"] = int(u.get("warranty_sales", 0)) + 1
		_gs.bus.unit_said.emit(uid,
			WARRANTY_SALE_LINES[randi() % WARRANTY_SALE_LINES.size()])
		var bname: String = String(buyer.get("display_name",
			buyer.get("name", "someone")))
		_gs.bus.unit_said.emit(int(buyer.get("id", 0)),
			"Wait... what did I just buy?")
		buyer["warranty_scammed"] = true
	else:
		_gs.bus.unit_said.emit(uid,
			WARRANTY_NO_SALE_LINES[randi() % WARRANTY_NO_SALE_LINES.size()])


func _tick_warranty(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	# A soldier closing in ends the sales route — no warranty for them.
	if _warranty_soldier_near(upos):
		u["warranty_fled"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"FINE! No warranty for YOU! You'll be SORRY!")
		_announce_once(u, "warranty_fled_story",
			"WARRANTY SALESMAN CHASED OFF",
			"A soldier got within shouting distance and Wally the " \
			+ "warranty salesman fled, briefcase flapping, loudly " \
			+ "withdrawing his limited-time offer. The offer was not " \
			+ "limited. The time was not of the essence.")
		_start_leaving(u)
		return
	if not u.has("warranty_target_pos"):
		_warranty_pick_target(u)
		_announce_once(u, "warranty_announced",
			"WARRANTY SALESMAN GOING DOOR TO DOOR",
			"A chibi gnome in a cheap suit has walked in from the " \
			+ "wilds with a briefcase full of extended warranties. " \
			+ "He says your hut's factory warranty is EXPIRED. Do not " \
			+ "sign anything. He has forms for everything.")
	var target: Vector2 = u.get("warranty_target_pos", Vector2.INF)
	var dist: float = upos.distance_to(target)
	if dist > WARRANTY_PITCH_RANGE:
		_walk_to(u, target, speed, delta)
		u["combat_state"] = "walking"
		u["warranty_pitch_left"] = WARRANTY_PITCH_TIME
	else:
		u["combat_state"] = "pitching"
		u["warranty_pitch_left"] = float(u.get("warranty_pitch_left",
			WARRANTY_PITCH_TIME)) - delta
		u["warranty_shout_cd"] = float(u.get("warranty_shout_cd",
			WARRANTY_SHOUT_CD)) - delta
		if float(u.get("warranty_shout_cd", 0.0)) <= 0.0:
			u["warranty_shout_cd"] = WARRANTY_SHOUT_CD
			_gs.bus.unit_said.emit(int(u.get("id", 0)),
				WARRANTY_PITCH_LINES[randi() % WARRANTY_PITCH_LINES.size()])
		if float(u.get("warranty_pitch_left", 0.0)) <= 0.0:
			_warranty_resolve_pitch(u)
			_warranty_pick_target(u)  # next door


func _warranty_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	var n: int = int(u.get("warranty_sales", 0))
	if not alive:
		_announce_once(u, "warranty_slain_story",
			"WARRANTY SALESMAN CANCELLED",
			"Wally the warranty salesman has been permanently " \
			+ "unsubscribed, %d sale(s) richer. " % n \
			+ "His briefcase has been seized. It contains 400 blank " \
			+ "forms and a sandwich.")
	elif bool(u.get("warranty_fled", false)):
		pass  # fled story already filed at flee time
	else:
		_announce_once(u, "warranty_left_story",
			"WARRANTY SALESMAN MOVES ON",
			"Wally the warranty salesman has left the realm, %d " % n \
			+ "sale(s) richer and out of doors to knock on. Check " \
			+ "your hut's warranty status. It's expired. It was always " \
			+ "expired.")


func _maybe_spawn_gossip() -> void:
	if _gs.day_number == int(_gossip_day):
		return
	_gossip_day = _gs.day_number
	if _gs.day_number < GOSSIP_MIN_DAY:
		return
	if randf() < GOSSIP_DAILY_CHANCE:
		spawn("gossip_gnome", _map_edge_point())


## Yapper heads for the most populous town — the most ears per waddle.
func _gossip_pick_town(u: Dictionary) -> void:
	var counts := {}
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var tid: int = int(x.get("town_id", -1))
		if tid < 0:
			continue
		counts[tid] = int(counts.get(tid, 0)) + 1
	var best_tid := -1
	var best_n := 0
	for tid: Variant in counts.keys():
		var n: int = int(counts[tid])
		if n > best_n:
			best_n = n
			best_tid = int(tid)
	if best_tid < 0:
		u["gossip_target"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
	else:
		var t: Dictionary = _gs.towns.get(best_tid, {})
		u["gossip_target"] = t.get("position", Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5))


func _gossip_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= GOSSIP_FLEE_RADIUS:
			return true
	return false


## Pick a random eligible citizen in radius as the rumor's subject.
func _gossip_pick_victim(upos: Vector2) -> Dictionary:
	var cands: Array[Dictionary] = []
	var r2: float = GOSSIP_RADIUS * GOSSIP_RADIUS
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if int(x.get("inside_building_id", 0)) > 0:
			continue  # indoors: the walls keep the secret
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_squared_to(upos) <= r2:
			cands.append(x)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


func _gossip_seed_rumor(u: Dictionary, upos: Vector2) -> void:
	if _gs.phone_sys == null or _gs.phone_sys.hearsay == null:
		return
	var v: Dictionary = _gossip_pick_victim(upos)
	if v.is_empty():
		return
	var vid: int = int(v.get("id", -1))
	var vname: String = String(v.get("display_name", v.get("name", "someone")))
	var vjob: String = String(v.get("job", "citizen"))
	var tpl: String = GOSSIP_RUMOR_TEMPLATES[
		randi() % GOSSIP_RUMOR_TEMPLATES.size()]
	var text: String = "Yapper the gossip gnome swears " + (tpl % [vname, vjob])
	_gs.phone_sys.hearsay.seed_rumor(
		text, "gossip", "gossip:%d" % vid, 0.65, vid,
		false, SimHearsay.TRUTH_UNKNOWN)
	u["gossip_rumors"] = int(u.get("gossip_rumors", 0)) + 1
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		"Did you hear about %s?!" % vname)


func _tick_gossip(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	# A soldier closing in is the end of the column — drop the quill, run.
	if _gossip_soldier_near(upos):
		u["gossip_fled"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"I HEARD NOTHING! I SAW NOTHING! PRINT NOTHING!")
		_announce_once(u, "gossip_fled_story",
			"YAPPER FLEES, DENIES EVERYTHING",
			"A soldier got within earshot and Yapper the gossip " \
			+ "gnome dropped his quill and fled, loudly denying " \
			+ "everything. The quill has been framed. It says nothing.")
		_start_leaving(u)
		return
	if not u.has("gossip_target"):
		_gossip_pick_town(u)
		_announce_once(u, "gossip_announced",
			"YAPPER THE GOSSIP GNOME IS IN TOWN",
			"A chibi gnome with a giant brass ear trumpet has " \
			+ "waddled in from the wilds, quill at the ready. " \
			+ "Lock up your secrets. He already knows the good ones.")
	var target: Vector2 = u.get("gossip_target", Vector2.INF)
	if upos.distance_to(target) < 160.0:
		_gossip_pick_town(u)
		target = u.get("gossip_target", Vector2.INF)
	_walk_to(u, target, speed, delta)
	u["combat_state"] = "yapping"
	u["gossip_rumor_cd"] = float(u.get("gossip_rumor_cd", 0.0)) - delta
	if float(u.get("gossip_rumor_cd", 0.0)) <= 0.0:
		u["gossip_rumor_cd"] = GOSSIP_RUMOR_CD
		_gossip_seed_rumor(u, upos)
	u["gossip_shout_cd"] = float(u.get("gossip_shout_cd",
		GOSSIP_SHOUT_CD)) - delta
	if float(u.get("gossip_shout_cd", 0.0)) <= 0.0:
		u["gossip_shout_cd"] = GOSSIP_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			GOSSIP_LINES[randi() % GOSSIP_LINES.size()])


func _gossip_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	var n: int = int(u.get("gossip_rumors", 0))
	if not alive:
		_announce_once(u, "gossip_slain_story",
			"YAPPER SILENCED",
			"Yapper the gossip gnome has been permanently " \
			+ "unsubscribed. He seeded %d rumor(s) before the end. " % n \
			+ "The realm exhales. Somewhere, a chamber pot stays secret.")
	elif bool(u.get("gossip_fled", false)):
		pass  # fled story already filed at flee time
	else:
		_announce_once(u, "gossip_left_story",
			"YAPPER MOVES ON TO FRESH DIRT",
			"Yapper the gossip gnome has waddled off in search of " \
			+ "fresher dirt, %d rumor(s) richer. " % n \
			+ "Check on your reflection. It's been talking.")


## Milo the Doomscroller (massive-dev 2026-10-08 — original content).
## A chibi gnome with glazed eyes and a glowing phone who shuffles to the
## nearest town and scrolls. 0 dmg; the weapon is the feed: citizens in
## screen-glow range stop working and stare (doomscrolling flag, honored
## by WorkerAI.tick_unit), mood rotting slowly. A soldier closing in yells
## TOUCH GRASS and he flees; when the battery dies he panics for the map
## edge. Singleton (HTML rule: only one at a time).
const DOOMSCROLL_DAILY_CHANCE := 0.035
const DOOMSCROLL_MIN_DAY := 8
const DOOMSCROLL_RADIUS := 260.0
const DOOMSCROLL_AURA_CD := 2.0      # aura application cadence (0.5 Hz)
const DOOMSCROLL_SHOUT_CD := 11.0
const DOOMSCROLL_FLEE_RADIUS := 130.0  # military inside this -> TOUCH GRASS
const DOOMSCROLL_BATTERY_SECONDS := 240.0  # 4 min of scrolling, then panic
const DOOMSCROLL_MOOD_TICK := 0.35   # sadness per aura application
const DOOMSCROLL_STRESS_TICK := 2.0
const DOOMSCROLL_LINES := [
	"just one more video...",
	"this algorithm GETS me",
	"bro wait. look at this. LOOK at this.",
	"my screen time is 14 hours. anyway",
	"do NOT talk to me during the unboxing",
	"touch grass? in THIS economy?",
	"one sec. one sec. one sec.",
	"I'm literally shaking. the comments agree.",
]
const DOOMSCROLL_GRUMBLES := [
	"My thumb hurts.",
	"I forgot what I do here.",
	"Was I... a farmer?",
	"Just checking the time. It's been 40 minutes.",
]


var _doomscroll_day: int = -1  # last day the doomscroll roll ran


func _maybe_spawn_doomscroll() -> void:
	if _gs.day_number == int(_doomscroll_day):
		return
	_doomscroll_day = _gs.day_number
	if _gs.day_number < DOOMSCROLL_MIN_DAY:
		return
	if randf() < DOOMSCROLL_DAILY_CHANCE:
		spawn("doomscroller", _map_edge_point())


## Chad the MLM Bro (dedicated-porting 2026-10-08 — original content).
## A chibi gnome in a cheap navy suit with a briefcase full of
## "opportunity". 0 dmg; the weapon is the pitch: citizens in aura range
## get recruited into his downline (hustling flag, honored by
## WorkerAI.tick_unit), pay a starter-kit fee from the faction treasury,
## and recruit their neighbors — a pyramid scheme that walks. Soldiers
## see through the pitch; market saturation (cap reached or timer out)
## sends him home. Singleton (HTML rule: only one at a time).
const MLM_DAILY_CHANCE := 0.035
const MLM_MIN_DAY := 8
const MLM_RADIUS := 240.0
const MLM_AURA_CD := 3.0          # aura application cadence
const MLM_SHOUT_CD := 12.0
const MLM_FLEE_RADIUS := 130.0    # military inside this -> pitch collapses
const MLM_STARTER_KIT := 8.0      # gold skimmed from the faction per recruit
const MLM_MAX_SKIM := 80.0        # total gold Chad can extract per visit
                                 # (== MAX_HUSTLERS * STARTER_KIT: aligned caps)
const MLM_MAX_HUSTLERS := 10      # downline cap — then MARKET SATURATED
const MLM_RECRUIT_RADIUS := 170.0 # chain-recruit reach of each hustler
const MLM_RECRUIT_CHANCE := 0.12  # per hustler per aura tick
const MLM_VISIT_SECONDS := 300.0   # 5 min of pitching, then he moves on
const MLM_MOOD_TICK := -1.0       # the products aren't selling themselves
const MLM_PITCH_LINES := [
	"Are you TIRED of being poor? I was poor once. For like a week.",
	"This is NOT a pyramid scheme. It's a reverse funnel system.",
	"Be your own boss! I boss myself AND twelve other bosses!",
	"You don't need a job. You need a DOWNLINE.",
	"I made six figures last month. Figures of WHAT is between me and the IRS.",
	"Your 9-to-5 is the real scam. My scam has a starter kit.",
	"Diamond level is RIGHT there. Can you taste it? That's protein powder.",
	"Excuses don't pay the bills, but my upline does! (They don't.)",
]
const MLM_GRUMBLES := [
	"I was SO close to diamond level.",
	"My garage is full of protein powder.",
	"Do NOT ask about the starter kit.",
	"I have twelve bosses and zero income.",
]
const MLM_RECRUIT_LINES := [
	"Bro. BRO. I need to tell you about an opportunity.",
	"Quick question: do you like money? Trick question, everyone does.",
	"I'm basically retired. I work 90 hours a week being retired.",
]


var _mlm_day: int = -1  # last day the MLM roll ran


func _maybe_spawn_mlm() -> void:
	if _gs.day_number == int(_mlm_day):
		return
	_mlm_day = _gs.day_number
	if _gs.day_number < MLM_MIN_DAY:
		return
	if randf() < MLM_DAILY_CHANCE:
		spawn("mlm_bro", _map_edge_point())


## Milo shuffles to the nearest town — the feed demands an audience.
## Falls back to map center when the realm has no towns.
func _doomscroll_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["doomscroll_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["doomscroll_town_name"] = "the realm"
	else:
		u["doomscroll_center"] = best.get("position", Vector2.ZERO)
		u["doomscroll_town_name"] = String(
			best.get("name", "a town"))


## A soldier closing in is the intervention — Milo gets told to touch grass.
func _doomscroll_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= DOOMSCROLL_FLEE_RADIUS:
			return true
	return false


## Clear the doomscrolling flag from every unit (departure/slain cleanup).
func _doomscroll_clear_flags() -> void:
	for x: Dictionary in _gs.units:
		if bool(x.get("doomscrolling", false)):
			x["doomscrolling"] = false
			x["work_state"] = "idle"


func _tick_doomscroll(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("doomscroll_center"):
		_doomscroll_pick_town(u)
		_announce_once(u, "doomscroll_announced",
			"DOOMSCROLLER SPOTTED",
			"Milo the doomscroller has shuffled toward " \
			+ String(u.get("doomscroll_town_name", "the realm")) \
			+ ". He has not looked up in three days. Neither will " \
			+ "your workforce.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(DOOMSCROLL_LINES, "just one more video..."))
		u["doomscroll_battery"] = DOOMSCROLL_BATTERY_SECONDS
	# Intervention: a soldier closes in and the scrolling ends early.
	if _doomscroll_soldier_near(upos):
		u["doomscroll_grassed"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"TOUCH GRASS?! ...fine. FINE.")
		_announce_once(u, "doomscroll_grass_story",
			"DOOMSCROLLER TOUCHES GRASS",
			"A soldier screamed TOUCH GRASS at Milo. He looked up, " \
			+ "saw the sky, screamed, and fled. The town's " \
			+ "productivity has been restored. His streak is ruined.")
		_doomscroll_clear_flags()
		_start_leaving(u)
		return
	# Battery: 1% is a horror no gnome can face.
	u["doomscroll_battery"] = float(u.get("doomscroll_battery",
		DOOMSCROLL_BATTERY_SECONDS)) - delta
	if float(u.get("doomscroll_battery", 0.0)) <= 0.0:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"1%?! NO NO NO—")
		_announce_once(u, "doomscroll_battery_story",
			"DOOMSCROLLER'S PHONE DIES",
			"Milo's phone hit 1%. Witnesses describe 'the scream'. " \
			+ "He is sprinting for the nearest charger (the map edge), " \
			+ "and for once he is looking where he is going.")
		_doomscroll_clear_flags()
		_start_leaving(u)
		return
	var center: Vector2 = u.get("doomscroll_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "scrolling"
		_walk_to(u, center, speed, delta)
		return
	# On the feed: hold position and radiate screen glow.
	u["combat_state"] = "scrolling"
	_doomscroll_aura(u, upos, delta)
	u["doomscroll_shout_cd"] = float(u.get("doomscroll_shout_cd",
		DOOMSCROLL_SHOUT_CD)) - delta
	if float(u.get("doomscroll_shout_cd", 0.0)) <= 0.0:
		u["doomscroll_shout_cd"] = DOOMSCROLL_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(DOOMSCROLL_LINES, "just one more video..."))


## The screen-glow aura, applied on a 2s cadence: citizens in range stop
## working and stare (doomscrolling flag, honored by WorkerAI.tick_unit),
## mood rots, stress climbs. Flags self-heal off units outside the radius.
func _doomscroll_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["doomscroll_aura_cd"] = float(u.get("doomscroll_aura_cd", 0.0)) - delta
	if float(u.get("doomscroll_aura_cd", 0.0)) > 0.0:
		return
	u["doomscroll_aura_cd"] = DOOMSCROLL_AURA_CD
	var r2: float = DOOMSCROLL_RADIUS * DOOMSCROLL_RADIUS
	var mood := SimMood.new()
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers have discipline. some of them.
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_squared_to(upos) > r2:
			if bool(x.get("doomscrolling", false)):
				x["doomscrolling"] = false
				x["work_state"] = "idle"
			continue
		if not bool(x.get("doomscrolling", false)):
			x["doomscrolling"] = true
			x["work_state"] = "idle"
			x["work_pose"] = null
		mood.nudge(x, "sad", DOOMSCROLL_MOOD_TICK)
		x["stress"] = minf(100.0,
			float(x.get("stress", 0.0)) + DOOMSCROLL_STRESS_TICK)
		if randf() < 0.3:
			_gs.bus.unit_said.emit(int(x.get("id", 0)),
				_pick_line(DOOMSCROLL_GRUMBLES, "My thumb hurts."))


## Departure/slain: file the screen-time outcome for the Gazette.
func _doomscroll_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	_doomscroll_clear_flags()
	if not alive:
		_announce_once(u, "doomscroll_slain_story",
			"DOOMSCROLLER LOGGED OFF (PERMANENTLY)",
			"Milo has been forcibly logged off. His screen time was " \
			+ "19 hours a day. The funeral will be livestreamed, " \
			+ "which he would have wanted.")
	elif bool(u.get("doomscroll_grassed", false)):
		pass  # grass story already filed at flee time
	else:
		_announce_once(u, "doomscroll_left_story",
			"DOOMSCROLLER FINDS AN OUTLET",
			"Milo the doomscroller has shuffled off, battery at 2%, " \
			+ "in search of a charger. The town blinks in the sudden " \
			+ "sunlight. Productivity resumes. Thumbs ache.")


## Chad walks to the nearest town — every downline needs a warm market.
## Falls back to map center when the realm has no towns.
func _mlm_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["mlm_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["mlm_town_name"] = "the realm"
	else:
		u["mlm_center"] = best.get("position", Vector2.ZERO)
		u["mlm_town_name"] = String(
			best.get("name", "a town"))


## A soldier closing in collapses the pitch — they see through it.
func _mlm_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= MLM_FLEE_RADIUS:
			return true
	return false


## Clear the hustling flag from every unit (departure/slain cleanup).
func _mlm_clear_flags() -> void:
	var mood := SimMood.new()
	for x: Dictionary in _gs.units:
		if bool(x.get("hustling", false)):
			x["hustling"] = false
			x["work_state"] = "idle"
			mood.nudge(x, "sad", 6.0)  # diamond level was SO close
			if randf() < 0.35:
				_gs.bus.unit_said.emit(int(x.get("id", 0)),
					_pick_line(MLM_GRUMBLES, "I was SO close to diamond level."))


func _tick_mlm(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("mlm_center"):
		_mlm_pick_town(u)
		_announce_once(u, "mlm_announced",
			"MLM BRO SPOTTED",
			"Chad the MLM Bro has strutted toward " \
			+ String(u.get("mlm_town_name", "the realm")) \
			+ " with a briefcase full of opportunity. Do not make eye " \
			+ "contact. Do not accept the free sample.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(MLM_PITCH_LINES, "You don't need a job. You need a DOWNLINE."))
		u["mlm_visit_left"] = MLM_VISIT_SECONDS
		u["mlm_skimmed"] = 0.0
		u["mlm_hustlers"] = 0
	# A soldier closes in and the pitch collapses.
	if _mlm_soldier_near(upos):
		u["mlm_fled"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"Whoa whoa — this is NOT a pyramid scheme! It's a REVERSE FUNNEL SYSTEM!")
		_announce_once(u, "mlm_fled_story",
			"MLM BRO DEBUNKED",
			"A soldier asked Chad ONE question about the compensation " \
			+ "plan and he folded like a lawn chair. The briefcase is " \
			+ "abandoned. The opportunity has expired.")
		_mlm_clear_flags()
		_start_leaving(u)
		return
	# Visit timer: the market saturates and Chad moves on.
	u["mlm_visit_left"] = float(u.get("mlm_visit_left",
		MLM_VISIT_SECONDS)) - delta
	if float(u.get("mlm_visit_left", 0.0)) <= 0.0:
		_announce_once(u, "mlm_saturated_story",
			"MARKET SATURATED",
			"Chad has declared the market saturated and moved on, " \
			+ "downline of %d strong. " % int(u.get("mlm_hustlers", 0)) \
			+ "The town blinks, checks its wallet, and goes back to work.")
		_mlm_clear_flags()
		_start_leaving(u)
		return
	var center: Vector2 = u.get("mlm_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "pitching"
		_walk_to(u, center, speed, delta)
		return
	# On the pitch: hold position and radiate opportunity.
	u["combat_state"] = "pitching"
	_mlm_aura(u, upos, delta)
	u["mlm_shout_cd"] = float(u.get("mlm_shout_cd",
		MLM_SHOUT_CD)) - delta
	if float(u.get("mlm_shout_cd", 0.0)) <= 0.0:
		u["mlm_shout_cd"] = MLM_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(MLM_PITCH_LINES, "You don't need a job. You need a DOWNLINE."))


## The pitch aura, applied on a 3s cadence: citizens in range join the
## downline (hustling flag, honored by WorkerAI.tick_unit), pay a
## starter-kit fee from the faction treasury (capped), and recruit their
## neighbors — the pyramid grows until the cap, then the market is
## declared saturated. Flags self-heal off units outside the radius.
func _mlm_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["mlm_aura_cd"] = float(u.get("mlm_aura_cd", 0.0)) - delta
	if float(u.get("mlm_aura_cd", 0.0)) > 0.0:
		return
	u["mlm_aura_cd"] = MLM_AURA_CD
	var r2: float = MLM_RADIUS * MLM_RADIUS
	var rr2: float = MLM_RECRUIT_RADIUS * MLM_RECRUIT_RADIUS
	var mood := SimMood.new()
	var hustlers: Array = []
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers have seen this pitch before
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if bool(x.get("hustling", false)):
			if xpos.distance_squared_to(upos) > r2:
				# Self-heal: the pitch no longer reaches them.
				x["hustling"] = false
				x["work_state"] = "idle"
			else:
				hustlers.append(x)
			continue
		if xpos.distance_squared_to(upos) <= r2:
			_mlm_recruit(u, x, mood)
	# Chain recruitment: hustlers pitch their neighbors. The pyramid grows.
	if hustlers.size() >= MLM_MAX_HUSTLERS:
		return
	for h: Dictionary in hustlers:
		if int(u.get("mlm_hustlers", 0)) >= MLM_MAX_HUSTLERS:
			break
		if randf() >= MLM_RECRUIT_CHANCE:
			continue
		var hpos: Vector2 = h.get("position", Vector2.ZERO)
		var target: Dictionary = {}
		for x: Dictionary in _gs.units:
			if not x.get("alive", false) or x == u or x == h:
				continue
			if String(x.get("faction", "")) == MONSTER_FACTION:
				continue
			if JobDefs.is_military(String(x.get("job", ""))):
				continue
			if bool(x.get("hustling", false)):
				continue
			var xpos: Vector2 = x.get("position", Vector2.ZERO)
			if xpos.distance_squared_to(hpos) <= rr2:
				target = x
				break
		if not target.is_empty():
			_mlm_recruit(u, target, mood)
			_gs.bus.unit_said.emit(int(h.get("id", 0)),
				_pick_line(MLM_RECRUIT_LINES,
					"Bro. BRO. I need to tell you about an opportunity."))


## Recruit one citizen: flag them, skim the starter kit from the faction
## treasury (add_resource clamps at 0 — a broke town can't go negative),
## bump the downline counter.
func _mlm_recruit(chad: Dictionary, x: Dictionary, mood: SimMood) -> void:
	if int(chad.get("mlm_hustlers", 0)) >= MLM_MAX_HUSTLERS:
		return
	x["hustling"] = true
	x["work_state"] = "idle"
	x["work_pose"] = null
	chad["mlm_hustlers"] = int(chad.get("mlm_hustlers", 0)) + 1
	mood.nudge(x, "happy", 4.0)  # the excitement phase
	var skimmed: float = float(chad.get("mlm_skimmed", 0.0))
	if skimmed < MLM_MAX_SKIM:
		var faction: String = String(x.get("faction", ""))
		_gs.resources.add_resource(faction, "gold", -MLM_STARTER_KIT)
		chad["mlm_skimmed"] = skimmed + MLM_STARTER_KIT
	if randf() < 0.3:
		_gs.bus.unit_said.emit(int(x.get("id", 0)),
			"I'm gonna be DIAMOND level by Thursday!")


## Departure/slain: file the downline outcome for the Gazette.
func _mlm_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	var n: int = int(u.get("mlm_hustlers", 0))
	_mlm_clear_flags()
	if not alive:
		_announce_once(u, "mlm_slain_story",
			"MLM BRO CANCELLED",
			"Chad the MLM Bro has been forcibly de-platformed, " \
			+ "downline of %d and all. His briefcase has been seized. " % n \
			+ "It contains 400 starter kits and a warehouse deed for " \
			+ "protein powder nobody wanted.")
	elif bool(u.get("mlm_fled", false)):
		pass  # debunked story already filed at flee time
	else:
		_announce_once(u, "mlm_left_story",
			"MLM BRO MOVES ON",
			"Chad the MLM Bro has left the realm, downline of %d " % n \
			+ "strong and wallet heavier. The town's garages are full " \
			+ "of protein powder. Productivity resumes. Wallets ache.")
## Dave the DMV Clerk (wake rapid-iteration 2026-10-08): a surly chibi
## gnome in a grey cardigan wheels a folding table into the town square
## and opens an unauthorized DMV branch. 0 dmg; the weapon is the queue:
## citizens in range take a number and WAIT IN LINE (waiting_in_line
## flag, honored by WorkerAI.tick_unit) instead of working. Dave serves
## one ticket at a time (slowly), skims a processing fee per license, and
## closes for lunch. Soldiers shut him down on sight. Singleton
## (HTML rule: only one at a time).
const DMV_DAILY_CHANCE := 0.035
const DMV_MIN_DAY := 8
const DMV_RADIUS := 240.0
const DMV_AURA_CD := 4.0            # queue-ticket application cadence
const DMV_SHOUT_CD := 14.0
const DMV_FLEE_RADIUS := 130.0      # military inside this -> branch closed
const DMV_FEE := 5.0               # gold processing fee per served citizen
const DMV_MAX_SKIM := 60.0         # total gold Dave can extract per visit
const DMV_SERVE_INTERVAL := 25.0   # seconds per citizen served (he's slow)
const DMV_LUNCH_EVERY := 120.0     # seconds of service between lunches
const DMV_LUNCH_LENGTH := 25.0     # lunch break length (queue disperses)
const DMV_VISIT_SECONDS := 300.0   # 5 min of bureaucracy, then he closes
const DMV_QUEUE_MOOD := -1.0       # waiting in line is nobody's hobby
const DMV_TICKET_LINES := [
	"Take a number. The number is 847. Now serving 3.",
	"Fill out form 12-B. In triplicate. No, I don't have a pen.",
	"Your paperwork is wrong. I can tell by looking at you.",
	"Next window, please. This window is decorative.",
	"I'm going to need to see some ID. And then more ID.",
	"That line you stood in? Wrong line. This is the line line.",
	"We're experiencing higher than normal call volumes. In person.",
	"Your license photo will be taken when you least expect it.",
]
const DMV_LUNCH_LINES := [
	"CLOSED FOR LUNCH. Back never.",
	"Window's closed. The sign says lunch. The sign is the law.",
	"Come back in 25 seconds. Or don't. I'm not your supervisor.",
]
const DMV_GRUMBLES := [
	"I waited four hours for a stamp.",
	"He looked at my form for one second and said 'no'.",
	"My number was called while I was blinking.",
	"There's a second floor? There's always a second floor.",
]


var _dmv_day: int = -1  # last day the DMV roll ran


func _maybe_spawn_dmv() -> void:
	if _gs.day_number == int(_dmv_day):
		return
	_dmv_day = _gs.day_number
	if _gs.day_number < DMV_MIN_DAY:
		return
	if randf() < DMV_DAILY_CHANCE:
		spawn("dmv_clerk", _map_edge_point())


## Dave wheels his folding table to the nearest town — bureaucracy
## demands an audience. Falls back to map center when the realm has
## no towns.
func _dmv_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["dmv_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["dmv_town_name"] = "the realm"
	else:
		u["dmv_center"] = best.get("position", Vector2.ZERO)
		u["dmv_town_name"] = String(
			best.get("name", "a town"))


## A soldier closing in shuts the branch down — unauthorized DMVs are
## a matter of civic security.
func _dmv_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= DMV_FLEE_RADIUS:
			return true
	return false


func _tick_dmv(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("dmv_center"):
		_dmv_pick_town(u)
		_announce_once(u, "dmv_announced",
			"DMV OPENS IN TOWN SQUARE",
			"Dave the DMV Clerk has wheeled a folding table toward " \
			+ String(u.get("dmv_town_name", "the realm")) \
			+ " and opened an unauthorized branch office. Take a number. " \
			+ "The number is 847. Now serving 3.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(DMV_TICKET_LINES, "Take a number."))
		u["dmv_visit_left"] = DMV_VISIT_SECONDS
		u["dmv_skimmed"] = 0.0
		u["dmv_ticket_next"] = 1
		u["dmv_lunch_in"] = DMV_LUNCH_EVERY
		u["dmv_now_serving"] = 0  # marquee starts blank, FX reads this
	# A soldier closes in and the branch is shut down.
	if _dmv_soldier_near(upos):
		_announce_once(u, "dmv_shutdown_story",
			"DMV SHUT DOWN",
			"A soldier informed Dave that you cannot simply OPEN a DMV " \
			+ "in the town square. Dave packed his folding table with " \
			+ "dignity, which is to say slowly and incorrectly.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"SIR, this is a TOWN SQUARE.")
		_dmv_clear_flags()
		_start_leaving(u)
		return
	# Visit timer: the branch closes — hours were 9 to 5.
	u["dmv_visit_left"] = float(u.get("dmv_visit_left",
		DMV_VISIT_SECONDS)) - delta
	if float(u.get("dmv_visit_left", 0.0)) <= 0.0:
		_announce_once(u, "dmv_closed_story",
			"DMV CLOSES (HOURS WERE 9-5)",
			"Dave has closed the branch for the day, %d citizens " \
			% _dmv_queue_size() \
			+ "still clutching tickets. The folding table is gone. " \
			+ "The queue remains, out of habit.")
		_dmv_clear_flags()
		_start_leaving(u)
		return
	var center: Vector2 = u.get("dmv_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "setting_up"
		_walk_to(u, center, speed, delta)
		return
	# At the table: hold position and radiate bureaucracy.
	u["combat_state"] = "serving"
	_dmv_lunch(u, delta)
	if not bool(u.get("dmv_on_lunch", false)):
		_dmv_aura(u, upos, delta)
		_dmv_serve(u, upos, delta)
	u["dmv_shout_cd"] = float(u.get("dmv_shout_cd",
		DMV_SHOUT_CD)) - delta
	if float(u.get("dmv_shout_cd", 0.0)) <= 0.0:
		u["dmv_shout_cd"] = DMV_SHOUT_CD
		if bool(u.get("dmv_on_lunch", false)):
			_gs.bus.unit_said.emit(int(u.get("id", 0)),
				_pick_line(DMV_LUNCH_LINES, "CLOSED FOR LUNCH. Back never."))
		else:
			_gs.bus.unit_said.emit(int(u.get("id", 0)),
				_pick_line(DMV_TICKET_LINES, "Take a number."))


## Lunch break: the window closes, the queue disperses (tickets voided),
## and Dave reopens hungry for paperwork.
func _dmv_lunch(u: Dictionary, delta: float) -> void:
	if bool(u.get("dmv_on_lunch", false)):
		u["dmv_lunch_left"] = float(u.get("dmv_lunch_left", 0.0)) - delta
		if float(u.get("dmv_lunch_left", 0.0)) <= 0.0:
			u["dmv_on_lunch"] = false
			u["dmv_lunch_in"] = DMV_LUNCH_EVERY
			u["dmv_ticket_next"] = 1
			u["dmv_now_serving"] = 0  # marquee rests between numbers
			_announce_once(u, "dmv_reopen_story",
				"DMV REOPENS",
				"Dave has returned from lunch. The line reforms " \
				+ "instantly, as if summoned. Now serving... number 1.")
			_gs.bus.unit_said.emit(int(u.get("id", 0)),
				"Now serving... number 1.")
		return
	u["dmv_lunch_in"] = float(u.get("dmv_lunch_in",
		DMV_LUNCH_EVERY)) - delta
	if float(u.get("dmv_lunch_in", 0.0)) <= 0.0:
		u["dmv_on_lunch"] = true
		u["dmv_lunch_left"] = DMV_LUNCH_LENGTH
		_dmv_clear_flags()
		_announce_once(u, "dmv_lunch_story",
			"DMV CLOSED FOR LUNCH",
			"Dave has closed the window for lunch. The queue disperses, " \
			+ "tickets voided, hope deferred. Estimated return: never.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(DMV_LUNCH_LINES, "CLOSED FOR LUNCH. Back never."))


## The queue aura, applied on a 4s cadence: citizens in range take a
## number and wait in line (waiting_in_line flag, honored by
## WorkerAI.tick_unit) instead of working. Flags self-heal off units
## outside the radius; lunch disperses the queue entirely.
func _dmv_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["dmv_aura_cd"] = float(u.get("dmv_aura_cd", 0.0)) - delta
	if float(u.get("dmv_aura_cd", 0.0)) > 0.0:
		return
	u["dmv_aura_cd"] = DMV_AURA_CD
	var r2: float = DMV_RADIUS * DMV_RADIUS
	var mood := SimMood.new()
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers don't do paperwork
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if bool(x.get("waiting_in_line", false)):
			if xpos.distance_squared_to(upos) > r2:
				# Self-heal: the branch no longer reaches them.
				x["waiting_in_line"] = false
				x["work_state"] = "idle"
			continue
		if xpos.distance_squared_to(upos) <= r2:
			x["waiting_in_line"] = true
			x["dmv_ticket"] = int(u.get("dmv_ticket_next", 1))
			u["dmv_ticket_next"] = int(u.get("dmv_ticket_next", 1)) + 1
			x["work_state"] = "idle"
			x["work_pose"] = null
			mood.nudge(x, "sad", 1.0)  # nobody enjoys the queue
			if randf() < 0.25:
				_gs.bus.unit_said.emit(int(x.get("id", 0)),
					"I'm number %d?! Now serving 3?!" \
					% int(x.get("dmv_ticket", 0)))


## Serve the lowest ticket holder: clear their flag, skim the
## processing fee from the faction treasury (capped), file the mood.
func _dmv_serve(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["dmv_serve_cd"] = float(u.get("dmv_serve_cd", 0.0)) - delta
	if float(u.get("dmv_serve_cd", 0.0)) > 0.0:
		return
	u["dmv_serve_cd"] = DMV_SERVE_INTERVAL
	var r2: float = DMV_RADIUS * DMV_RADIUS
	var best: Dictionary = {}
	var best_ticket := 1 << 30
	for x: Dictionary in _gs.units:
		if not bool(x.get("waiting_in_line", false)):
			continue
		if not x.get("alive", false):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_squared_to(upos) > r2:
			continue
		var t: int = int(x.get("dmv_ticket", 1 << 30))
		if t < best_ticket:
			best_ticket = t
			best = x
	if best.is_empty():
		return
	best["waiting_in_line"] = false
	best["work_state"] = "idle"
	# 2026-10-08 (wake rapid-iteration): publish the now-serving number
	# for the DMVClerkFX ticket-window marquee (driven via world's sync).
	u["dmv_now_serving"] = best_ticket
	var mood := SimMood.new()
	mood.nudge(best, "sad", 3.0)  # licensed, at what cost
	var skimmed: float = float(u.get("dmv_skimmed", 0.0))
	if skimmed < DMV_MAX_SKIM:
		var faction: String = String(best.get("faction", ""))
		_gs.resources.add_resource(faction, "gold", -DMV_FEE)
		u["dmv_skimmed"] = skimmed + DMV_FEE
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		"Now serving number %d! Number %d!" % [best_ticket, best_ticket])
	if randf() < 0.35:
		_gs.bus.unit_said.emit(int(best.get("id", 0)),
			_pick_line(DMV_GRUMBLES, "I waited four hours for a stamp."))


## Count citizens currently holding tickets (for Gazette color).
func _dmv_queue_size() -> int:
	var n := 0
	for x: Dictionary in _gs.units:
		if bool(x.get("waiting_in_line", false)) \
				and x.get("alive", false):
			n += 1
	return n


## Clear the waiting_in_line flag from every unit (lunch/departure/
## slain cleanup).
func _dmv_clear_flags() -> void:
	for x: Dictionary in _gs.units:
		if bool(x.get("waiting_in_line", false)):
			x["waiting_in_line"] = false
			x["work_state"] = "idle"


## Departure/slain: file the bureaucratic outcome for the Gazette.
func _dmv_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	var skimmed: float = float(u.get("dmv_skimmed", 0.0))
	_dmv_clear_flags()
	if not alive:
		_announce_once(u, "dmv_slain_story",
			"DMV PERMANENTLY CLOSED",
			"Dave the DMV Clerk has been forcibly retired. His folding " \
			+ "table has been seized. It contains 400 forms 12-B, a stamp " \
			+ "that only says NO, and %.0f gold in processing fees." % skimmed)
	# Alive departures (soldier shutdown, end of hours) file their own
	# stories at the moment they happen — nothing more to file here.


## Kyle the CrossFit Gnome (massive-dev 2026-10-08 — original content).
## A chibi gnome in a neon tank top and headband who wheels NOTHING into
## the town square — he IS the equipment. 0 dmg; the weapon is the WOD:
## citizens in aura range drop their tools and do burpees (workouting flag,
## honored by WorkerAI.tick_unit) instead of working. Burpees are exhausting
## (energy drains via the urges dict each aura tick) but they get the town
## SWOLE: each aura tick adds a swole stack (cap 10), and swole slows energy
## decay (see SimUrges.tick — fit citizens tire slower). Soldiers don't fall
## for it — a soldier who closes in gets challenged to a burpee contest,
## wins (they do PT daily), and Kyle leaves humbled. Otherwise he bounces
## after his visit timer, off to leg day. Singleton (HTML rule: one at a time).
const CROSSFIT_DAILY_CHANCE := 0.035
const CROSSFIT_MIN_DAY := 8
const CROSSFIT_RADIUS := 240.0
const CROSSFIT_AURA_CD := 2.5        # aura application cadence
const CROSSFIT_SHOUT_CD := 12.0
const CROSSFIT_FLEE_RADIUS := 130.0  # military inside this -> burpee contest
const CROSSFIT_VISIT_SECONDS := 240.0  # 4 min of WOD, then leg day
const CROSSFIT_ENERGY_TICK := 6.0    # energy drained per aura application
const CROSSFIT_SWOLE_MAX := 10       # swole cap: 50% slower energy decay
const CROSSFIT_MOOD_TICK := 1.5      # burpees hurt. everybody agrees.
const CROSSFIT_LINES := [
	"WOD TIME! EVERYBODY UP!",
	"NO REP! DO IT AGAIN!",
	"DO YOU EVEN LIFT?!",
	"PAIN IS WEAKNESS LEAVING THE BODY!",
	"ONE MORE REP! ...SIKE, TEN MORE!",
	"SKIP LEG DAY? NEVER HEARD OF HER.",
	"BURPEES! MY FAVORITE! (nobody's favorite)",
	"HYDRATE OR DIE-DRATE!",
]
const CROSSFIT_GRUMBLES := [
	"My arms are filing a complaint.",
	"I was a farmer. Now I'm... sore.",
	"He said 'one more'. That was 40 minutes ago.",
	"I can see my abs. I can't feel my legs.",
]


var _crossfit_day: int = -1  # last day the CrossFit roll ran


func _maybe_spawn_crossfit() -> void:
	if _gs.day_number == int(_crossfit_day):
		return
	_crossfit_day = _gs.day_number
	if _gs.day_number < CROSSFIT_MIN_DAY:
		return
	if randf() < CROSSFIT_DAILY_CHANCE:
		spawn("crossfit_gnome", _map_edge_point())


## Kyle shuffles to the nearest town — the WOD demands an audience.
## Falls back to map center when the realm has no towns.
func _crossfit_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["crossfit_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["crossfit_town_name"] = "the realm"
	else:
		u["crossfit_center"] = best.get("position", Vector2.ZERO)
		u["crossfit_town_name"] = String(
			best.get("name", "a town"))


## A soldier closing in gets challenged to a burpee contest. The soldier
## always wins (they do PT daily). Kyle leaves humbled.
func _crossfit_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= CROSSFIT_FLEE_RADIUS:
			return true
	return false


## Clear the workout flag from every unit (departure/slain cleanup).
func _crossfit_clear_flags() -> void:
	for x: Dictionary in _gs.units:
		if bool(x.get("workouting", false)):
			x["workouting"] = false
			x["work_state"] = "idle"


func _tick_crossfit(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("crossfit_center"):
		_crossfit_pick_town(u)
		_announce_once(u, "crossfit_announced",
			"CROSSFIT GNOME SPOTTED",
			"Kyle the CrossFit Gnome has set up in " \
			+ String(u.get("crossfit_town_name", "the realm")) \
			+ ". He brought nothing but a shaker bottle and unshakable " \
			+ "confidence. Your workforce will now do burpees.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(CROSSFIT_LINES, "WOD TIME! EVERYBODY UP!"))
		u["crossfit_visit_left"] = CROSSFIT_VISIT_SECONDS
	# Burpee contest: a soldier closes in, accepts the challenge, wins.
	if _crossfit_soldier_near(upos):
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"YOU! SOLDIER! BURPEE CONTEST! RIGHT NOW!")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"...401. He did 401. RESPECT. I'm gonna go cry in the sauna.")
		_announce_once(u, "crossfit_contest_story",
			"BURPEE CONTEST ENDS BADLY",
			"A soldier accepted Kyle's burpee challenge. Kyle did 400. " \
			+ "The soldier did 401. Kyle has left to cry in the sauna. " \
			+ "The town's arms hurt, but their pride is intact.")
		_crossfit_clear_flags()
		_start_leaving(u)
		return
	# Leg day: the visit timer runs out and Kyle bounces.
	u["crossfit_visit_left"] = float(u.get("crossfit_visit_left",
		CROSSFIT_VISIT_SECONDS)) - delta
	if float(u.get("crossfit_visit_left", 0.0)) <= 0.0:
		_announce_once(u, "crossfit_legday_story",
			"KYLE LEAVES FOR LEG DAY",
			"Kyle has bounced after four minutes of WOD. The town is " \
			+ "exhausted, jacked, and behind on everything. Gains: up 400%. " \
			+ "Productivity: down 100%.")
		_crossfit_clear_flags()
		_start_leaving(u)
		return
	var center: Vector2 = u.get("crossfit_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "warming_up"
		_walk_to(u, center, speed, delta)
		return
	# In the square: hold position and radiate WOD.
	u["combat_state"] = "wod"
	_crossfit_aura(u, upos, delta)
	u["crossfit_shout_cd"] = float(u.get("crossfit_shout_cd",
		CROSSFIT_SHOUT_CD)) - delta
	if float(u.get("crossfit_shout_cd", 0.0)) <= 0.0:
		u["crossfit_shout_cd"] = CROSSFIT_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(CROSSFIT_LINES, "WOD TIME! EVERYBODY UP!"))


## The WOD aura, applied on a 2.5s cadence: citizens in range drop their
## tools and do burpees (workouting flag, honored by WorkerAI.tick_unit).
## Burpees drain energy (via the urges dict) but build swole stacks (cap 10;
## see SimUrges.tick for the energy-decay benefit). Flags self-heal off units
## outside the radius; soldiers never fall for it; units mid-urge keep
## their urge (the urge system owns them).
func _crossfit_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["crossfit_aura_cd"] = float(u.get("crossfit_aura_cd", 0.0)) - delta
	if float(u.get("crossfit_aura_cd", 0.0)) > 0.0:
		return
	u["crossfit_aura_cd"] = CROSSFIT_AURA_CD
	var r2: float = CROSSFIT_RADIUS * CROSSFIT_RADIUS
	var mood := SimMood.new()
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers do their own PT. they are not impressed.
		if String(x.get("mind_state", "")).begins_with("satisfying:"):
			continue  # urge in progress — the urge system owns them
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if bool(x.get("workouting", false)):
			if xpos.distance_squared_to(upos) > r2:
				# Self-heal: the WOD no longer reaches them.
				x["workouting"] = false
				x["work_state"] = "idle"
			continue
		if xpos.distance_squared_to(upos) <= r2:
			x["workouting"] = true
			x["work_state"] = "idle"
			x["work_pose"] = null
			# Burpees are exhausting but they build swole. The urges dict
			# lives at unit["urges"] (see SimUrges.ensure); touch it directly
			# — DisasterSim owns no SimUrges instance.
			var ud: Dictionary = x.get("urges", {})
			if ud.is_empty():
				ud = {}
				for urge in SimUrges.URGES:
					ud[urge] = 60.0
				x["urges"] = ud
			ud["energy"] = clampf(float(ud.get("energy", 60.0)) \
				- CROSSFIT_ENERGY_TICK, 0.0, 100.0)
			x["swole"] = mini(CROSSFIT_SWOLE_MAX,
				int(x.get("swole", 0)) + 1)
			mood.nudge(x, "tired", CROSSFIT_MOOD_TICK)
			if randf() < 0.3:
				_gs.bus.unit_said.emit(int(x.get("id", 0)),
					_pick_line(CROSSFIT_GRUMBLES,
						"My arms are filing a complaint."))


## Departure/slain: file the fitness outcome for the Gazette.
func _crossfit_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	_crossfit_clear_flags()
	if not alive:
		_announce_once(u, "crossfit_slain_story",
			"CROSSFIT GNOME CANCELLED",
			"Kyle the CrossFit Gnome has been forcibly cancelled. His " \
			+ "shaker bottle has been seized. It contains protein powder " \
			+ "and regret. The town stretches, groans, and gets back to work.")
	# Alive departures (burpee contest, leg day) file their own stories
	# at the moment they happen — nothing more to file here.


## Vicky the Influencer (dedicated-porting 2026-10-08 — original content).
## A chibi gnome girl with a ring light and selfie stick. 0 dmg; the weapon
## is CLOUT: citizens in aura range stop working to gawk and pose for her
## stream (gawking flag, honored by WorkerAI.tick_unit). Every gawker feeds
## her viral meter (+1.0 each per aura tick, cap 100); milestones at 25/50
## file Gazette beats (TRENDING LOCALLY/REGIONALLY) and 100 files GOES
## VIRAL. A soldier who closes in confiscates the ring light and she leaves
## crying; otherwise the visit timer gets her canceled (someone found her
## old posts). Slain = canceled permanently. Singleton (one at a time).
const INFLUENCER_DAILY_CHANCE := 0.035
const INFLUENCER_MIN_DAY := 8
const INFLUENCER_RADIUS := 260.0
const INFLUENCER_AURA_CD := 2.5        # aura application cadence
const INFLUENCER_SHOUT_CD := 14.0
const INFLUENCER_FLEE_RADIUS := 130.0  # military inside this -> ring light confiscated
const INFLUENCER_VISIT_SECONDS := 240.0  # 4 min of content, then canceled
const INFLUENCER_VIRAL_PER_GAWKER := 1.0  # meter gain per gawker per aura tick
const INFLUENCER_VIRAL_MAX := 100.0
const INFLUENCER_VIRAL_LOCAL := 25.0
const INFLUENCER_VIRAL_REGIONAL := 50.0
const INFLUENCER_LINES := [
	"LIKE AND SUBSCRIBE!",
	"SMIZE FOR THE CAM!",
	"POV: you're a peasant in MY vlog.",
	"New ring light, who dis?",
	"This video is sponsored by... me.",
	"Wait, do that again, I wasn't recording.",
	"Say hi to my twelve followers!",
	"Comment 'CLOUT' if you're watching this!",
]
const INFLUENCER_GRUMBLES := [
	"I missed lunch for this.",
	"She said 'smize'. What does that mean?",
	"My crops are dying. But that transition was fire.",
	"She's been filming the same wall for an hour.",
	"I have a family. I have a mortgage. I'm doing finger hearts.",
]


var _influencer_day: int = -1  # last day the influencer roll ran


func _maybe_spawn_influencer() -> void:
	if _gs.day_number == int(_influencer_day):
		return
	_influencer_day = _gs.day_number
	if _gs.day_number < INFLUENCER_MIN_DAY:
		return
	if randf() < INFLUENCER_DAILY_CHANCE:
		spawn("influencer_gnome", _map_edge_point())


## Vicky bee-lines for the nearest town — content needs an audience.
## Falls back to map center when the realm has no towns.
func _influencer_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["influencer_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["influencer_town_name"] = "the realm"
	else:
		u["influencer_center"] = best.get("position", Vector2.ZERO)
		u["influencer_town_name"] = String(
			best.get("name", "a town"))


## A soldier closing in confiscates the ring light. No ring light, no
## content. Vicky leaves crying.
func _influencer_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= INFLUENCER_FLEE_RADIUS:
			return true
	return false


func _influencer_clear_flags() -> void:
	for x: Dictionary in _gs.units:
		if bool(x.get("gawking", false)):
			x["gawking"] = false
			x["work_state"] = "idle"


func _tick_influencer(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("influencer_center"):
		_influencer_pick_town(u)
		_announce_once(u, "influencer_announced",
			"INFLUENCER SPOTTED",
			"Vicky the Influencer has set up her ring light in " \
			+ String(u.get("influencer_town_name", "the realm")) \
			+ ". Your workforce will now stop working to gawk.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(INFLUENCER_LINES, "LIKE AND SUBSCRIBE!"))
		u["influencer_visit_left"] = INFLUENCER_VISIT_SECONDS
		u["viral"] = 0.0
	# Ring light confiscated: a soldier closes in and ends the stream.
	if _influencer_soldier_near(upos):
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"YOU CAN'T TAKE MY RING LIGHT! IT'S MY WHOLE PERSONALITY!")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"...I'm literally shaking right now.")
		_announce_once(u, "influencer_confiscated_story",
			"RING LIGHT CONFISCATED",
			"A soldier confiscated Vicky's ring light. Without it she is " \
			+ "just a gnome holding a stick. She has left, crying, to " \
			+ "tell her twelve followers about this injustice.")
		_influencer_clear_flags()
		_start_leaving(u)
		return
	# Canceled: the visit timer runs out and someone found her old posts.
	u["influencer_visit_left"] = float(u.get("influencer_visit_left",
		INFLUENCER_VISIT_SECONDS)) - delta
	if float(u.get("influencer_visit_left", 0.0)) <= 0.0:
		_announce_once(u, "influencer_canceled_story",
			"VICKY GOT CANCELED",
			"Vicky has been canceled after someone found her old posts. " \
			+ "The ring light is off. The town blinks, stretches, and " \
			+ "remembers it had jobs.")
		_influencer_clear_flags()
		_start_leaving(u)
		return
	var center: Vector2 = u.get("influencer_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "warming_up"
		_walk_to(u, center, speed, delta)
		return
	# In the square: hold position and radiate content.
	u["combat_state"] = "filming"
	_influencer_aura(u, upos, delta)
	u["influencer_shout_cd"] = float(u.get("influencer_shout_cd",
		INFLUENCER_SHOUT_CD)) - delta
	if float(u.get("influencer_shout_cd", 0.0)) <= 0.0:
		u["influencer_shout_cd"] = INFLUENCER_SHOUT_CD
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			_pick_line(INFLUENCER_LINES, "LIKE AND SUBSCRIBE!"))


## The clout aura, applied on a 2.5s cadence: citizens in range stop
## working to gawk and pose (gawking flag, honored by WorkerAI.tick_unit).
## Every gawker feeds the viral meter. Flags self-heal off units outside
## the radius; soldiers never fall for it; units mid-urge keep their urge.
func _influencer_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["influencer_aura_cd"] = float(u.get("influencer_aura_cd", 0.0)) - delta
	if float(u.get("influencer_aura_cd", 0.0)) > 0.0:
		return
	u["influencer_aura_cd"] = INFLUENCER_AURA_CD
	var r2: float = INFLUENCER_RADIUS * INFLUENCER_RADIUS
	var gawkers := 0
	var mood := SimMood.new()
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers have seen this bit before. unimpressed.
		if String(x.get("mind_state", "")).begins_with("satisfying:"):
			continue  # urge in progress — the urge system owns them
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if bool(x.get("gawking", false)):
			if xpos.distance_squared_to(upos) > r2:
				# Self-heal: the content no longer reaches them.
				x["gawking"] = false
				x["work_state"] = "idle"
				continue
		if xpos.distance_squared_to(upos) <= r2:
			x["gawking"] = true
			x["work_state"] = "idle"
			x["work_pose"] = null
			gawkers += 1
			mood.nudge(x, "happy", 1.0)
			if randf() < 0.3:
				_gs.bus.unit_said.emit(int(x.get("id", 0)),
					_pick_line(INFLUENCER_GRUMBLES,
						"I missed lunch for this."))
	if gawkers > 0:
		u["viral"] = minf(INFLUENCER_VIRAL_MAX,
			float(u.get("viral", 0.0)) \
			+ float(gawkers) * INFLUENCER_VIRAL_PER_GAWKER)
	_influencer_viral_milestones(u)


## Viral milestones: local buzz is a shout, regional is Gazette, 100 is
## a full viral moment. Each fires once per visit.
func _influencer_viral_milestones(u: Dictionary) -> void:
	var viral: float = float(u.get("viral", 0.0))
	if viral >= INFLUENCER_VIRAL_LOCAL \
			and not bool(u.get("viral_local_done", false)):
		u["viral_local_done"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"I'M TRENDING LOCALLY, BESTIE!")
	if viral >= INFLUENCER_VIRAL_REGIONAL:
		_announce_once(u, "influencer_regional_story",
			"TRENDING REGIONALLY",
			"Vicky's stream is trending across the region. Three farmers " \
			+ "have quit to become full-time moderators of her chat.")
	if viral >= INFLUENCER_VIRAL_MAX \
			and not bool(u.get("viral_done", false)):
		u["viral_done"] = true
		_announce_once(u, "influencer_viral_story",
			"VICKY GOES VIRAL",
			"Vicky the Influencer has gone fully viral. Bards are already " \
			+ "writing ballads about the ring light. Productivity across " \
			+ "the realm has entered the chat and left immediately.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"WE'RE VIRAL, BESTIE! WE'RE VIRAL!")


## Departure/slain: file the content outcome for the Gazette.
func _influencer_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	_influencer_clear_flags()
	if not alive:
		_announce_once(u, "influencer_slain_story",
			"INFLUENCER CANCELED (PERMANENTLY)",
			"Vicky the Influencer has been permanently canceled. Her " \
			+ "ring light has been seized as evidence. Her twelve " \
			+ "followers have been notified and are devastated. The " \
			+ "town gets back to work and pretends it never gawked.")
	# Alive departures (confiscation, canceled) file their own stories
	# at the moment they happen — nothing more to file here.


## ---- Prince Gnomba (Disaster #26) --------------------------------------
## A Nigerian-prince email scammer in gnome form. 0 dmg; the weapon is
## CONFIDENCE. On arrival he DMs the ruler a 100%-legitimate treasury-
## unlock proposal; the Messenger thread gets inline [Send 500g] /
## [Block & Report] buttons (war-counsel pattern, zero sim changes in
## the UI — the buttons send the same words a typed verdict would).
## While the con is pending, his aura skims "processing fees" off the
## town's treasury (capped). Send the gold and the royal treasury might
## double it — or he rugs and vanishes. Singleton.

const GNOMBA_DAILY_CHANCE := 0.02
const GNOMBA_MIN_DAY := 12
const GNOMBA_VISIT_SECONDS := 240.0
const GNOMBA_FLEE_RADIUS := 130.0
const GNOMBA_AURA_RADIUS := 260.0
const GNOMBA_AURA_CD := 3.0
const GNOMBA_SEND_AMOUNT := 500.0
const GNOMBA_SKIM_PER_CITIZEN := 4.0
const GNOMBA_SKIM_CAP := 150.0

const GNOMBA_DM_PITCH := "GREETINGS DEAR RULER. I am PRINCE GNOMBA of the FARAWAY KINGDOM OF GNOMALIA. I have inherited 10,000 GOLD but the royal treasury is LOCKED by a curse. Send 500 gold as the UNLOCKING FEE and I will DOUBLE IT - 1,000 gold back to you. This is 100% legitimate. My lawyer is a wizard. Tap SEND below, or BLOCK to report this noble prince to the authorities."

const GNOMBA_LINES := [
	"SEND THE GOLD, DEAR RULER!",
	"THIS IS 100% LEGITIMATE!",
	"MY TREASURY IS LOCKED. SO RUDE.",
	"MY LAWYER IS A WIZARD. A WIZARD!",
	"THE FEE IS SMALL. THE PRINCE IS REAL.",
	"DO NOT LISTEN TO THE PEASANTS. SEND.",
]

var _gnomba_day: int = -1  # last day the prince roll ran


func _maybe_spawn_prince_gnomba() -> void:
	if _gs.day_number == int(_gnomba_day):
		return
	_gnomba_day = _gs.day_number
	if _gs.day_number < GNOMBA_MIN_DAY:
		return
	if randf() < GNOMBA_DAILY_CHANCE:
		spawn("prince_gnomba", _map_edge_point())


## The prince bee-lines for the nearest town — cons need a crowd.
## Falls back to map center when the realm has no towns.
func _gnomba_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["gnomba_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["gnomba_town_name"] = "the realm"
		u["gnomba_faction"] = String(_gs.player_faction)
	else:
		u["gnomba_center"] = best.get("position", Vector2.ZERO)
		u["gnomba_town_name"] = String(
			best.get("name", "a town"))
		u["gnomba_faction"] = String(best.get("faction", ""))


## Deportation check: any soldier closing in ends the con.
func _gnomba_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= GNOMBA_FLEE_RADIUS:
			return true
	return false


## The pitch itself, DM'd to the ruler on arrival. Blocked princes stay
## silent (blocking fully silences an NPC — standing rule).
func _gnomba_send_dm(u: Dictionary) -> void:
	var ph = _gs.get("phone_sys")
	if ph == null or not ph.has_method("npc_message"):
		return
	var uid := int(u.get("id", 0))
	if ph.has_method("is_blocked") and bool(ph.call("is_blocked", uid)):
		return
	ph.npc_message(uid, GNOMBA_DM_PITCH)


func _tick_gnomba(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var uid := int(u.get("id", 0))
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("gnomba_center"):
		_gnomba_pick_town(u)
		_announce_once(u, "gnomba_announced",
			"A PRINCE HAS ARRIVED",
			"Prince Gnomba of the FARAWAY KINGDOM OF GNOMALIA has arrived in " \
			+ String(u.get("gnomba_town_name", "the realm")) \
			+ " with a locked treasury and an unlocking fee. He has also " \
			+ "somehow found the ruler's phone number.")
		_gs.bus.unit_said.emit(uid,
			_pick_line(GNOMBA_LINES, "GREETINGS DEAR RULER!"))
		u["gnomba_visit_left"] = GNOMBA_VISIT_SECONDS
		u["gnomba_scam"] = "pending"
		u["gnomba_skimmed"] = 0.0
		_gnomba_send_dm(u)
	var center: Vector2 = u.get("gnomba_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "arriving"
		_walk_to(u, center, speed, delta)
		return
	# In the square: hold position and work the room.
	u["combat_state"] = "pitching"
	# Deported: a soldier closes in and ends the con.
	if _gnomba_soldier_near(upos):
		_gs.bus.unit_said.emit(uid,
			"I AM A DIPLOMAT! YOU CANNOT DEPORT A PRINCE!")
		_announce_once(u, "gnomba_deported_story",
			"PRINCE GNOMBA DEPORTED",
			"A soldier deported Prince Gnomba. He claimed diplomatic " \
			+ "immunity. He had no documents. He has been escorted to " \
			+ "the map edge, still insisting he is a prince.")
		_start_leaving(u)
		return
	# Visa expired: the visit timer runs out.
	u["gnomba_visit_left"] = float(u.get("gnomba_visit_left",
		GNOMBA_VISIT_SECONDS)) - delta
	if float(u.get("gnomba_visit_left", 0.0)) <= 0.0:
		_announce_once(u, "gnomba_visa_story",
			"PRINCE GNOMBA'S VISA EXPIRES",
			"Prince Gnomba's royal visa has expired. He departs for " \
			+ "Gnomalia, which definitely exists, to renew it. He will " \
			+ "return. Probably. Do not wait up.")
		_start_leaving(u)
		return
	_gnomba_aura(u, upos, delta)
	u["gnomba_shout_cd"] = float(u.get("gnomba_shout_cd",
		8.0)) - delta
	if float(u.get("gnomba_shout_cd", 0.0)) <= 0.0:
		u["gnomba_shout_cd"] = 8.0
		_gs.bus.unit_said.emit(uid,
			_pick_line(GNOMBA_LINES, "SEND THE GOLD, DEAR RULER!"))


## The processing-fee aura, on a 3s cadence: every non-military local in
## range pays a small fee into the prince's pocket. Capped per visit so
## an ignored prince can't drain a treasury dry.
func _gnomba_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	if String(u.get("gnomba_scam", "")) != "pending":
		return
	u["gnomba_aura_cd"] = float(u.get("gnomba_aura_cd", 0.0)) - delta
	if float(u.get("gnomba_aura_cd", 0.0)) > 0.0:
		return
	u["gnomba_aura_cd"] = GNOMBA_AURA_CD
	var faction := String(u.get("gnomba_faction", ""))
	if faction == "":
		return
	var skimmed := float(u.get("gnomba_skimmed", 0.0))
	if skimmed >= GNOMBA_SKIM_CAP:
		return
	var r2: float = GNOMBA_AURA_RADIUS * GNOMBA_AURA_RADIUS
	var marks := 0
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if String(x.get("faction", "")) != faction:
			continue  # he only scams the locals
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers don't fall for it
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_squared_to(upos) > r2:
			continue
		marks += 1
	if marks == 0:
		return
	var take: float = minf(float(marks) * GNOMBA_SKIM_PER_CITIZEN,
		GNOMBA_SKIM_CAP - skimmed)
	take = minf(take, float(_gs.resources.get_amount(faction, "gold")))
	if take > 0.0:
		_gs.resources.add_resource(faction, "gold", -take)
		u["gnomba_skimmed"] = skimmed + take
		if float(u.get("gnomba_skimmed", 0.0)) >= GNOMBA_SKIM_CAP:
			_announce_once(u, "gnomba_fees_story",
				"PRINCE COLLECTS HIS FEES",
				"Prince Gnomba has collected " \
				+ str(int(GNOMBA_SKIM_CAP)) \
				+ " gold in 'processing fees' from the locals while the " \
				+ "ruler deliberated. The fees are non-refundable. Obviously.")


## Phone seam: is this unit Prince Gnomba with a live con? Used by the
## Messenger thread view to show the inline Send / Block buttons.
func gnomba_scam_pending(unit_id: int) -> bool:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return false
	return String(u.get("job", "")) == "prince_gnomba" \
		and bool(u.get("alive", false)) \
		and String(u.get("gnomba_scam", "")) == "pending"


## Prince Gnomba's DM thread is a live con. Called from SimPhone._npc_reply
## BEFORE the conversation engine. Returns the prince's reply text, or ""
## when the text isn't a scam verdict (normal chat proceeds untouched).
func gnomba_scam_reply(unit: Dictionary, text: String) -> String:
	if String(unit.get("job", "")) != "prince_gnomba":
		return ""
	if not bool(unit.get("alive", false)):
		return ""
	if String(unit.get("gnomba_scam", "")) != "pending":
		return ""
	var t := text.strip_edges().to_lower()
	var is_send := t in ["send", "yes", "accept", "deal", "send it"] \
		or t.begins_with("send ")
	var is_block := t in ["block", "report", "no", "deny", "scam", "fraud"] \
		or t.begins_with("block ") or t.begins_with("report ")
	if not is_send and not is_block:
		return ""
	return _gnomba_resolve(unit, is_send)


## Resolves the con. Runs on the player's tap — safe to call outside tick
## (only flips flags, moves gold, files stories, starts leaving).
func _gnomba_resolve(u: Dictionary, send: bool) -> String:
	var pf := String(_gs.player_faction)
	if not send:
		u["gnomba_scam"] = "blocked"
		_announce_once(u, "gnomba_blocked_story",
			"WOULD-BE PRINCE BLOCKED",
			"The ruler blocked and reported Prince Gnomba. The 'prince' " \
			+ "called the ruler a peasant, then fled the kingdom before " \
			+ "the authorities arrived. The royal treasury remains " \
			+ "locked. It was never real.")
		_start_leaving(u)
		return "THIS IS AN OUTRAGE! You dare report a PRINCE?! ...Fine. FINE. I am leaving. Enjoy being POOR."
	var have: float = float(_gs.resources.get_amount(pf, "gold"))
	if have < GNOMBA_SEND_AMOUNT:
		return "You INSULT me, dear ruler. Come back when you have REAL gold. The fee is 500. The prince is REAL."
	_gs.resources.spend(pf, {"gold": GNOMBA_SEND_AMOUNT})
	u["gnomba_scam"] = "resolved"
	if randf() < 0.5:
		_gs.resources.add_resource(pf, "gold", GNOMBA_SEND_AMOUNT * 2.0)
		_announce_once(u, "gnomba_payout_story",
			"PRINCE GNOMBA PAYS OUT",
			"Prince Gnomba DOUBLED the ruler's 500 gold unlocking fee. " \
			+ "1,000 gold has been deposited in the treasury. The court " \
			+ "wizard has no explanation. The prince bows and departs " \
			+ "an honest gnome.")
		_start_leaving(u)
		return "YOU SEE? LEGITIMATE! 1,000 gold, as promised. Prince Gnomba ALWAYS delivers. Farewell, dear ruler!"
	_announce_once(u, "gnomba_rugged_story",
		"RUGGED!",
		"Prince Gnomba has vanished with the ruler's 500 gold unlocking " \
		+ "fee. The 'royal treasury' was a painted box of rocks. The " \
		+ "faraway kingdom of Gnomalia does not appear on any map.")
	_start_leaving(u)
	return "THANK YOU FOR YOUR GOLD, DEAR RULER. PRINCE GNOMBA HAS LEFT THE KINGDOM. DO NOT TRY TO FIND GNOMALIA."


## Slain: file the outcome for the Gazette. (Alive departures file their
## own stories at the moment they happen — deported / visa / blocked /
## payout / rugged.)
func _gnomba_departed(u: Dictionary) -> void:
	if not bool(u.get("alive", false)):
		_announce_once(u, "gnomba_slain_story",
			"PRINCE GNOMBA SLAIN",
			"Prince Gnomba has been slain. His 'royal treasury' was a " \
			+ "painted box of rocks. His crown was plastic. Gnomalia does " \
			+ "not exist. The realm mourns the 500 gold it almost sent.")


## ---- DJ Weddington (Disaster #27) ---------------------------------------
## An unbooked wedding DJ. The wedding got canceled but he kept the
## deposit AND the gear, so he rolled into town and turned the square
## into a dance floor. 0 dmg; the weapon is THE DROP — citizens in range
## stop working to dance (dancing flag, honored by WorkerAI.tick_unit).
## Every dancer feeds the hype meter (cap 100): 25 is a shout, 50 files
## Gazette "FLOOR FILLER", 100 files "WEDDINGTON BREAKS THE TOWN RECORD".
## A soldier who closes in confiscates the turntables and the music
## stops; otherwise the visit timer ends when the wedding party finds
## him. He DMs the ruler on arrival and at peak hype (flavor only — no
## buttons). Singleton.

const DJ_DAILY_CHANCE := 0.035
const DJ_MIN_DAY := 8
const DJ_RADIUS := 260.0
const DJ_AURA_CD := 2.5          # aura application cadence
const DJ_FLEE_RADIUS := 130.0    # military inside this -> turntables confiscated
const DJ_VISIT_SECONDS := 240.0  # 4 min of bangers, then the wedding party finds him
const DJ_HYPE_PER_DANCER := 1.0  # meter gain per dancer per aura tick
const DJ_HYPE_MAX := 100.0
const DJ_HYPE_WARM := 25.0
const DJ_HYPE_FILLER := 50.0
const DJ_SHOUT_CD := 20.0

const DJ_DM_ARRIVE := "YO. DJ WEDDINGTON IN THE HOUSE. The wedding got canceled but the VIBES didn't, so your town square is now a DANCE FLOOR. Requests?? (there are no requests)"
const DJ_DM_PEAK := "THAT SET WAS FIRE. Tell the town the encore never ends. DJ WEDDINGTON OUT. (he is still here)"

const DJ_LINES := [
	"MAKE SOME NOISE!",
	"THIS ONE'S FOR THE BRIDE'S MOTHER!",
	"EVERYBODY CLAP YOUR HANDS!",
	"I ONLY PLAY BANGERS!",
	"THE WEDDING WAS CANCELED, NOT THE VIBES!",
	"FEEL THE DROP!",
]

const DJ_GRUMBLES := [
	"I have harvesting to do but the bassline said no.",
	"My knees are 60 years old. My soul is 19.",
	"Just one more song. (It is never one more song.)",
	"The Cha-Cha Slide has claimed another farmer.",
	"I was a respected mason before that key change.",
]

var _dj_day: int = -1  # last day the DJ roll ran


func _maybe_spawn_dj() -> void:
	if _gs.day_number == int(_dj_day):
		return
	_dj_day = _gs.day_number
	if _gs.day_number < DJ_MIN_DAY:
		return
	if randf() < DJ_DAILY_CHANCE:
		spawn("dj_weddington", _map_edge_point())


## Weddington bee-lines for the nearest town — a DJ needs a dance floor.
## Falls back to map center when the realm has no towns.
func _dj_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = td
	if best.is_empty():
		u["dj_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["dj_town_name"] = "the realm"
	else:
		u["dj_center"] = best.get("position", Vector2.ZERO)
		u["dj_town_name"] = String(
			best.get("name", "a town"))


## A soldier closing in confiscates the turntables. No decks, no drop.
func _dj_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= DJ_FLEE_RADIUS:
			return true
	return false


func _dj_clear_flags() -> void:
	for x: Dictionary in _gs.units:
		if bool(x.get("dancing", false)):
			x["dancing"] = false
			x["work_state"] = "idle"


## Flavor DM to the ruler. peak=false on arrival, true at max hype.
func _dj_send_dm(u: Dictionary, peak: bool) -> void:
	var ph = _gs.get("phone_sys")
	if ph == null or not ph.has_method("npc_message"):
		return
	var uid := int(u.get("id", 0))
	if ph.has_method("is_blocked") and bool(ph.call("is_blocked", uid)):
		return
	ph.npc_message(uid, DJ_DM_PEAK if peak else DJ_DM_ARRIVE)


func _tick_dj(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var uid := int(u.get("id", 0))
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("dj_center"):
		_dj_pick_town(u)
		_announce_once(u, "dj_announced",
			"A WEDDING DJ HAS ARRIVED",
			"DJ Weddington has rolled his decks into " \
			+ String(u.get("dj_town_name", "the realm")) \
			+ ". The wedding was canceled. The party was not. " \
			+ "Your workforce will now stop working to dance.")
		_gs.bus.unit_said.emit(uid,
			_pick_line(DJ_LINES, "MAKE SOME NOISE!"))
		u["dj_visit_left"] = DJ_VISIT_SECONDS
		u["hype"] = 0.0
		_dj_send_dm(u, false)
	# Turntables confiscated: a soldier closes in and ends the set.
	if _dj_soldier_near(upos):
		_gs.bus.unit_said.emit(uid,
			"YOU CAN'T TAKE MY DECKS! THEY'RE RENTED!")
		_gs.bus.unit_said.emit(uid,
			"...you just hate FUN. Fine. I'm leaving.")
		_announce_once(u, "dj_confiscated_story",
			"TURNTABLES CONFISCATED",
			"A soldier confiscated DJ Weddington's turntables. Without " \
			+ "them he is just a gnome with headphones and opinions. He " \
			+ "has left, muttering that the town hates fun.")
		_dj_clear_flags()
		_start_leaving(u)
		return
	# Found: the visit timer runs out and the wedding party tracks him down.
	u["dj_visit_left"] = float(u.get("dj_visit_left",
		DJ_VISIT_SECONDS)) - delta
	if float(u.get("dj_visit_left", 0.0)) <= 0.0:
		_gs.bus.unit_said.emit(uid,
			"WAIT — is that the bride's mother?? I GOT REBOOKED! LOVE YOU ALL!")
		_announce_once(u, "dj_found_story",
			"THE WEDDING PARTY FOUND HIM",
			"DJ Weddington has been tracked down by the wedding party " \
			+ "and rebooked for the actual wedding. He leaves a hero. " \
			+ "The town sits down, catches its breath, and remembers " \
			+ "it had jobs.")
		_dj_clear_flags()
		_start_leaving(u)
		return
	var center: Vector2 = u.get("dj_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "warming_up"
		_walk_to(u, center, speed, delta)
		return
	# In the square: hold position and drop the beat.
	u["combat_state"] = "spinning"
	_dj_aura(u, upos, delta)
	u["dj_shout_cd"] = float(u.get("dj_shout_cd",
		DJ_SHOUT_CD)) - delta
	if float(u.get("dj_shout_cd", 0.0)) <= 0.0:
		u["dj_shout_cd"] = DJ_SHOUT_CD
		_gs.bus.unit_said.emit(uid,
			_pick_line(DJ_LINES, "MAKE SOME NOISE!"))


## The drop aura, applied on a 2.5s cadence: citizens in range stop
## working to dance (dancing flag, honored by WorkerAI.tick_unit).
## Every dancer feeds the hype meter. Flags self-heal off units outside
## the radius; soldiers never dance; units mid-urge keep their urge.
func _dj_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["dj_aura_cd"] = float(u.get("dj_aura_cd", 0.0)) - delta
	if float(u.get("dj_aura_cd", 0.0)) > 0.0:
		return
	u["dj_aura_cd"] = DJ_AURA_CD
	var r2: float = DJ_RADIUS * DJ_RADIUS
	var dancers := 0
	var mood := SimMood.new()
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers have heard this set before. unimpressed.
		if String(x.get("mind_state", "")).begins_with("satisfying:"):
			continue  # urge in progress — the urge system owns them
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if bool(x.get("dancing", false)):
			if xpos.distance_squared_to(upos) > r2:
				# Self-heal: the beat no longer reaches them.
				x["dancing"] = false
				x["work_state"] = "idle"
				continue
		if xpos.distance_squared_to(upos) <= r2:
			x["dancing"] = true
			x["work_state"] = "idle"
			x["work_pose"] = null
			dancers += 1
			mood.nudge(x, "happy", 1.0)
			if randf() < 0.3:
				_gs.bus.unit_said.emit(int(x.get("id", 0)),
					_pick_line(DJ_GRUMBLES,
						"I have harvesting to do but the bassline said no."))
	if dancers > 0:
		u["hype"] = minf(DJ_HYPE_MAX,
			float(u.get("hype", 0.0)) \
			+ float(dancers) * DJ_HYPE_PER_DANCER)
	_dj_hype_milestones(u)


## Hype milestones: warming up is a shout, floor filler is Gazette, 100
## is a town record. Each fires once per visit; 100 also DMs the ruler.
func _dj_hype_milestones(u: Dictionary) -> void:
	var hype: float = float(u.get("hype", 0.0))
	if hype >= DJ_HYPE_WARM \
		and not bool(u.get("hype_warm_done", false)):
		u["hype_warm_done"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"THE CROWD IS FEELING IT!")
	if hype >= DJ_HYPE_FILLER:
		_announce_once(u, "dj_filler_story",
			"FLOOR FILLER",
			"DJ Weddington's set is filling the floor. Three farmers " \
			+ "have formed a spontaneous line dance. The harvest can wait. " \
			+ "It has been waiting.")
	if hype >= DJ_HYPE_MAX \
		and not bool(u.get("hype_done", false)):
		u["hype_done"] = true
		_announce_once(u, "dj_record_story",
			"WEDDINGTON BREAKS THE TOWN RECORD",
			"DJ Weddington has broken the town's all-time hype record. " \
			+ "Bards are taking notes. Productivity has left the building, " \
			+ "and it is never coming back.")
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"THAT SET WAS FIRE!")
		_dj_send_dm(u, true)


## Departure/slain: file the set outcome for the Gazette.
func _dj_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	_dj_clear_flags()
	if not alive:
		_announce_once(u, "dj_slain_story",
			"THE BEAT STOPPED (PERMANENTLY)",
			"DJ Weddington has been permanently unplugged. His decks " \
			+ "have been seized as evidence. The mirror ball keeps " \
			+ "spinning for no one. The town dances on in silence, " \
			+ "then quietly gets back to work.")
	# Alive departures (confiscation, found) file their own stories
	# at the moment they happen — nothing more to file here.


## Ricky the Repo Gnome (dedicated-porting 2026-10-08 — original
## content, Disaster #28). A repo man with a tiny tow truck rolls into the
## nearest town, hooks the fanciest non-essential building, and drags it
## to the map edge. 0 dmg; the weapon is REPOSSESSION — if he reaches the
## edge, the building is gone for good (erase_building). A soldier who
## closes in impounds the tow truck and the building is dropped back on
## its foundation. Timer running out = the bank calls it off. Slain =
## the building is recovered and Ricky gets repossessed (irony).
##
## Tow design (safe by construction): the building record NEVER leaves the
## buildings array or the id index — only its position is dragged each
## tick (b["towed"] = true, b["repo_home"] = original pos). All references
## (workers, town lists, zones) stay valid. Erase happens only at the
## terminal success state; every failure path restores the position.
## Save/load sanitation lives in from_dict: stranded towed flags snap
## back to repo_home.
const REPO_MIN_DAY := 10
const REPO_DAILY_CHANCE := 0.03
const REPO_VISIT_SECONDS := 240.0
const REPO_FLEE_RADIUS := 130.0
const REPO_HOOK_DIST := 70.0
const REPO_HOOK_TIME := 3.0
const REPO_TOW_GAP := 110.0
const REPO_EDGE_DIST := 90.0
## Building types Ricky will never touch: seats of power, defenses,
## and anything the game cannot rebuild trivially.
const REPO_NEVER := ["town_hall", "wall", "walls", "barracks",
	"monastery", "gov_office", "gov_treasury", "gov_war_office",
	"gov_justice"]
const REPO_DM_ARRIVE := "RICKY HERE. Official business. You missed a payment — don't ask which one, the paperwork is very long — so I'm taking the %s. Don't make this weird."
const REPO_LINES := [
	"I'M JUST DOING MY JOB!",
	"READ THE FINE PRINT NEXT TIME!",
	"THIS IS COMING WITH ME!",
	"PAYMENTS WERE DUE YESTERDAY!",
	"NO, YOU CAN'T BUY IT BACK. OK, YOU CAN, BUT IT'LL COST YOU.",
]
const REPO_GRUMBLES := [
	"Hey! That's OUR %s!",
	"Somebody stop him! He's taking the %s!",
	"My grandmother built that %s!",
	"Does NOBODY read the loan terms??",
]


var _repo_day: int = -1  # last day the repo roll ran


func _maybe_spawn_repo() -> void:
	if _gs.day_number == int(_repo_day):
		return
	_repo_day = _gs.day_number
	if _gs.day_number < REPO_MIN_DAY:
		return
	if randf() < REPO_DAILY_CHANCE:
		spawn("repo_gnome", _map_edge_point())


## Ricky bee-lines for the nearest town, then picks the fanciest eligible
## building there (highest max_hp = biggest investment). Falls back to the
## realm-wide fanciest; no eligible building anywhere = nothing to repo.
func _repo_pick_target(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best_town := -1
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best_town = int(td.get("id", -1))
	var best: Dictionary = {}
	var best_hp := -1.0
	for b: Dictionary in _gs.buildings:
		if not _repo_eligible(b):
			continue
		if best_town >= 0 and int(b.get("town_id", -2)) != best_town:
			continue
		var hp: float = float(b.get("max_hp", 0.0))
		if hp > best_hp:
			best_hp = hp
			best = b
	if best.is_empty() and best_town >= 0:
		# Nearest town has nothing worth taking — scan the whole realm.
		for b: Dictionary in _gs.buildings:
			if not _repo_eligible(b):
				continue
			var hp: float = float(b.get("max_hp", 0.0))
			if hp > best_hp:
				best_hp = hp
				best = b
	u["repo_town"] = best_town
	if best.is_empty():
		u["repo_bid"] = -1
	else:
		u["repo_bid"] = int(best.get("id", -1))
		u["repo_phase"] = "approach"


## Eligible = complete, alive, not ours-or-theirs-essential, not already
## on Ricky's hook. Blueprints (complete=false) are never towed.
func _repo_eligible(b: Dictionary) -> bool:
	if not b.get("alive", false):
		return false
	if not bool(b.get("complete", true)):
		return false
	if String(b.get("faction", "")) == MONSTER_FACTION:
		return false
	if bool(b.get("towed", false)):
		return false
	if bool(b.get("is_gov", false)):
		return false
	if String(b.get("type", "")) in REPO_NEVER:
		return false
	return true


func _repo_bname(b: Dictionary) -> String:
	return String(b.get("type", "building")).capitalize().replace("_", " ")


## A soldier closing in impounds the tow truck. No truck, no repo.
func _repo_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= REPO_FLEE_RADIUS:
			return true
	return false


## Nearest point on the map edge — Ricky's getaway route.
func _repo_edge_point(upos: Vector2) -> Vector2:
	var r := world_bounds
	var dl: float = upos.x - r.position.x
	var dr: float = r.end.x - upos.x
	var dt: float = upos.y - r.position.y
	var db: float = r.end.y - upos.y
	var m: float = minf(minf(dl, dr), minf(dt, db))
	if m == dl:
		return Vector2(r.position.x, upos.y)
	if m == dr:
		return Vector2(r.end.x, upos.y)
	if m == dt:
		return Vector2(upos.x, r.position.y)
	return Vector2(upos.x, r.end.y)


## Drop the building back on its foundation. Safe no-op if the building
## is gone (destroyed mid-tow) or was never hooked.
func _repo_drop(u: Dictionary) -> void:
	var bid: int = int(u.get("repo_bid", -1))
	u["repo_bid"] = -1
	u["repo_phase"] = "approach"
	if bid < 0:
		return
	var b: Dictionary = _get_building(bid)
	if b.is_empty():
		return
	if bool(b.get("towed", false)):
		var home: Vector2 = b.get("repo_home",
			b.get("position", Vector2.ZERO))
		b["position"] = home
		# Perf R42: buildings move only here (Ricky tows) — the combat
		# building grid is position-keyed, so a moved building must
		# invalidate it (count is unchanged, so the grid can't see it).
		if _combat != null:
			_combat._invalidate_building_grid()
		b["towed"] = false
		b.erase("repo_home")


## Flavor DM to the ruler on arrival.
func _repo_send_dm(u: Dictionary, bname: String) -> void:
	var ph = _gs.get("phone_sys")
	if ph == null or not ph.has_method("npc_message"):
		return
	var uid := int(u.get("id", 0))
	if ph.has_method("is_blocked") and bool(ph.call("is_blocked", uid)):
		return
	ph.npc_message(uid, REPO_DM_ARRIVE % bname)


## A nearby citizen grumbles about the repo (real unit id — never the
## building id, which is not a unit and must not speak).
func _repo_bystander_grumble(b: Dictionary, bname: String) -> void:
	var bpos: Vector2 = b.get("position", Vector2.ZERO)
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(bpos) <= 400.0:
			_gs.bus.unit_said.emit(int(x.get("id", 0)),
				_pick_line(REPO_GRUMBLES, "Hey! That's OURS!") % bname)
			return


func _tick_repo(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var uid := int(u.get("id", 0))
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("repo_phase"):
		_repo_pick_target(u)
		var b: Dictionary = _get_building(int(u.get("repo_bid", -1)))
		if b.is_empty():
			# Nothing worth repoing in the whole realm — wasted trip.
			_gs.bus.unit_said.emit(uid,
				"NOTHING HERE WORTH REPOING. Your credit is safe. FOR NOW.")
			_announce_once(u, "repo_nothing_story",
				"NOTHING WORTH REPOING",
				"Ricky the Repo Gnome surveyed the realm's buildings and " \
				+ "found nothing worth repossessing. The realm takes this " \
				+ "as a compliment. Ricky takes it as a personal insult.")
			_start_leaving(u)
			return
		var bname := _repo_bname(b)
		_announce_once(u, "repo_announced",
			"A REPO GNOME HAS ARRIVED",
			"Ricky the Repo Gnome has rolled his tow truck into town " \
			+ "with foreclosure papers for the " + bname + ". He says " \
			+ "a payment was missed. He will not say which one. " \
			+ "Stop him before he drags it off the map.")
		_gs.bus.unit_said.emit(uid,
			_pick_line(REPO_LINES, "I'M JUST DOING MY JOB!"))
		u["repo_visit_left"] = REPO_VISIT_SECONDS
		_repo_send_dm(u, bname)
	# The bank calls it off: timer out, truck goes home.
	u["repo_visit_left"] = float(u.get("repo_visit_left",
		REPO_VISIT_SECONDS)) - delta
	if float(u.get("repo_visit_left", 0.0)) <= 0.0:
		_gs.bus.unit_said.emit(uid,
			"WAIT — the bank called it off?? FINE. Keep your %s." \
			% _repo_bname(_get_building(int(u.get("repo_bid", -1)))))
		_announce_once(u, "repo_called_off_story",
			"THE BANK CALLED IT OFF",
			"Ricky the Repo Gnome received a call from the bank " \
			+ "mid-tow and stood down. The paperwork was wrong. The " \
			+ "building stays. Ricky keeps the clipboard.")
		_repo_drop(u)
		_start_leaving(u)
		return
	# Tow truck impounded: a soldier closes in.
	if _repo_soldier_near(upos):
		_gs.bus.unit_said.emit(uid,
			"HEY! YOU CAN'T IMPOUND THE TRUCK! IT'S A LEASE!")
		_gs.bus.unit_said.emit(uid,
			"...the lease is also in default. Fine. I'M LEAVING.")
		_announce_once(u, "repo_impounded_story",
			"TOW TRUCK IMPOUNDED",
			"A soldier impounded Ricky the Repo Gnome's tow truck. " \
			+ "Without it he is just a gnome with a clipboard and " \
			+ "delusions of collateral. The building was dropped back " \
			+ "on its foundation.")
		_repo_drop(u)
		_start_leaving(u)
		return
	var phase: String = String(u.get("repo_phase", "approach"))
	var b: Dictionary = _get_building(int(u.get("repo_bid", -1)))
	if b.is_empty():
		# Target destroyed while Ricky worked — nothing left to take.
		_repo_drop(u)
		_start_leaving(u)
		return
	var bpos: Vector2 = b.get("position", Vector2.ZERO)
	if phase == "approach":
		u["combat_state"] = "driving"
		if upos.distance_to(bpos) <= REPO_HOOK_DIST:
			u["repo_phase"] = "hookup"
			u["combat_state"] = "hooking"
			u["repo_hook_left"] = REPO_HOOK_TIME
			_gs.bus.unit_said.emit(uid,
				"HOOKING UP THE %s!" % _repo_bname(b).to_upper())
		else:
			_walk_to(u, bpos, speed, delta)
	elif phase == "hookup":
		u["combat_state"] = "hooking"
		u["repo_hook_left"] = float(u.get("repo_hook_left",
			REPO_HOOK_TIME)) - delta
		if float(u.get("repo_hook_left", 0.0)) <= 0.0:
			u["repo_phase"] = "towing"
			b["towed"] = true
			b["repo_home"] = bpos
			_announce_once(u, "repo_hooked_story",
				"HOOKED UP",
				"Ricky has chained the " + _repo_bname(b) + " to his " \
				+ "tow truck. It is leaving town whether the town " \
				+ "likes it or not. The town does not like it.")
			if randf() < 0.5:
				_repo_bystander_grumble(b, _repo_bname(b))
	elif phase == "towing":
		u["combat_state"] = "driving"
		var edge := _repo_edge_point(upos)
		_walk_to(u, edge, speed, delta)
		upos = u.get("position", Vector2.ZERO)
		# Drag the building behind the truck.
		var dir: Vector2 = (edge - upos).normalized()
		if dir.length() < 0.5:
			dir = Vector2.RIGHT
		b["position"] = upos - dir * REPO_TOW_GAP
		# Perf R42: the building moves every tick during a tow — invalidate
		# the combat building grid (position-keyed). Degrades to the old
		# linear-scan cost for the tow's duration; tows are rare and brief.
		if _combat != null:
			_combat._invalidate_building_grid()
		if upos.distance_to(edge) <= REPO_EDGE_DIST:
			var bname := _repo_bname(b)
			_gs.bus.unit_said.emit(uid, "SOLD! ...I mean. REPOSSESSED.")
			_announce_once(u, "repo_repossessed_story",
				"RICKY REPOSSESSED THE " + bname.to_upper(),
				"Ricky the Repo Gnome has dragged the " + bname + " " \
				+ "clean off the map. It now belongs to the bank. The " \
				+ "bank has no use for it. Nobody wins. That is " \
				+ "repossession, baby.")
			_gs.erase_building(b)
			u["repo_bid"] = -1
			u["repo_phase"] = "approach"
			_start_leaving(u)


## Departure/slain: the building is always restored unless it was already
## repossessed (erased) at the edge. Slain files the ironic headline.
func _repo_departed(u: Dictionary) -> void:
	var alive: bool = bool(u.get("alive", false))
	_repo_drop(u)
	if not alive:
		_announce_once(u, "repo_slain_story",
			"RICKY GOT REPOSSESSED",
			"Ricky the Repo Gnome has been permanently repossessed. An " \
			+ "even smaller gnome arrived with an even smaller tow " \
			+ "truck and took Ricky's truck. The circle of repo is " \
			+ "complete. The building was recovered.")
	# Alive departures (impound, called off, repossessed) file their own
	# stories at the moment they happen — nothing more to file here.


## fishing hut, market). Falls back to the biggest town, then the spawn.
func _gulls_pick_town(u: Dictionary) -> void:
	var food_counts := {}
	var bld_counts := {}
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) == MONSTER_FACTION:
			continue
		if not bool(b.get("complete", true)):
			continue
		var tid: int = int(b.get("town_id", -1))
		bld_counts[tid] = int(bld_counts.get(tid, 0)) + 1
		if String(b.get("type", "")) in ["farm", "farmhouse",
				"fishing_hut", "market"]:
			food_counts[tid] = int(food_counts.get(tid, 0)) + 1
	var best := -1
	var best_n := 0
	for tid in food_counts.keys():
		if int(food_counts[tid]) > best_n:
			best_n = int(food_counts[tid])
			best = int(tid)
	if best < 0:
		for tid in bld_counts.keys():
			if int(bld_counts[tid]) > best_n:
				best_n = int(bld_counts[tid])
				best = int(tid)
	u["gull_town"] = best
	u["gull_orbit_ang"] = randf() * TAU
	u["steal_cd"] = 3.0  # first theft comes fast — they're hungry
	var cx := 0.0
	var cy := 0.0
	var n := 0
	var faction := ""
	for b2: Dictionary in _gs.buildings:
		if not b2.get("alive", false):
			continue
		if int(b2.get("town_id", -2)) != best:
			continue
		var bp: Vector2 = b2.get("position", Vector2.ZERO)
		cx += bp.x
		cy += bp.y
		n += 1
		if faction == "":
			faction = String(b2.get("faction", ""))
	u["gull_faction"] = faction
	if n > 0:
		u["gull_center"] = Vector2(cx / n, cy / n)
	else:
		u["gull_center"] = u.get("position", Vector2.ZERO)


func _tick_seagulls(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if not u.has("gull_center"):
		_gulls_pick_town(u)
		_announce_once(u, "gull_announced",
			"SEAGULLS DECLARE WAR ON LUNCH",
			"A furious flock has descended on the realm, screaming " \
			+ "about chips. Officials advise hiding your fries.")
	var center: Vector2 = u.get("gull_center", upos)
	# Orbit the town, screaming.
	u["combat_state"] = "circling"
	var ang: float = float(u.get("gull_orbit_ang", 0.0)) + delta * 0.9
	u["gull_orbit_ang"] = ang
	var orbit := center + Vector2(cos(ang), sin(ang)) * GULL_ORBIT_RADIUS
	_walk_to(u, orbit, speed, delta)
	# Theft + crap on a timer.
	u["steal_cd"] = float(u.get("steal_cd", 3.0)) - delta
	if float(u.get("steal_cd", 0.0)) <= 0.0:
		u["steal_cd"] = GULL_STEAL_CD
		_gulls_steal(u)
	_crap_aura_tick(u, delta)


## One theft run: steal food from the town's faction, maybe crap on a
## building, always squawk about it.
func _gulls_steal(u: Dictionary) -> void:
	var faction: String = String(u.get("gull_faction", ""))
	if faction != "" and _gs.resources != null:
		var amt: float = snappedf(
			randf_range(GULL_STEAL_MIN, GULL_STEAL_MAX), 1.0)
		# add_resource clamps at 0 — a starving town can't go negative.
		_gs.resources.add_resource(faction, "food", -amt)
		u["gull_stolen"] = float(u.get("gull_stolen", 0.0)) + amt
		var town_id: int = int(u.get("gull_town", -1))
		if randf() < GULL_CRAP_CHANCE:
			var cands: Array = []
			for b: Dictionary in _gs.buildings:
				if not b.get("alive", false):
					continue
				if int(b.get("town_id", -2)) != town_id:
					continue
				cands.append(b)
			if not cands.is_empty():
				var b: Dictionary = cands[randi_range(0, cands.size() - 1)]
				b["seagull_crap_t"] = GULL_CRAP_T
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		SEAGULL_SQUAWKS[randi() % SEAGULL_SQUAWKS.size()])


## Crapped buildings stress nearby citizens until it wears off.
func _crap_aura_tick(u: Dictionary, delta: float) -> void:
	var town_id: int = int(u.get("gull_town", -1))
	for b: Dictionary in _gs.buildings:
		if float(b.get("seagull_crap_t", 0.0)) <= 0.0:
			continue
		b["seagull_crap_t"] = float(b["seagull_crap_t"]) - delta
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		for x: Dictionary in _gs.units:
			if not x.get("alive", false):
				continue
			if String(x.get("faction", "")) == MONSTER_FACTION:
				continue
			if int(x.get("town_id", -2)) != town_id:
				continue
			var xpos: Vector2 = x.get("position", Vector2.ZERO)
			if xpos.distance_to(bpos) > GULL_AURA_RADIUS:
				continue
			x["stress"] = minf(100.0,
				float(x.get("stress", 0.0)) + 6.0 * delta)


## Departure/slain: file the theft total on the ledger for the Gazette.
func _gulls_departed(u: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id >= 0:
		dlog.record_note(log_id, "STOLEN %d food" % int(
			float(u.get("gull_stolen", 0.0))))


## Taxman target: the richest non-monster faction's hall (else its town
## centroid). He walks in from the map edge and plants himself there.
func _taxman_pick_target(u: Dictionary) -> void:
	# Richest non-monster faction with a presence in the world (read the
	# faction set off buildings — every real faction holds buildings).
	var candidates := {}
	for b0: Dictionary in _gs.buildings:
		var f0: String = String(b0.get("faction", ""))
		if f0 != "" and f0 != MONSTER_FACTION:
			candidates[f0] = true
	var best_faction := ""
	var best_gold := -1.0
	if _gs.resources != null:
		for f: String in candidates.keys():
			var g: float = _gs.resources.get_amount(f, "gold")
			if g > best_gold:
				best_gold = g
				best_faction = f
	u["tax_faction"] = best_faction
	u["audit_cd"] = 5.0  # first audit comes fast — he's efficient
	var hall_pos := Vector2.INF
	var cx := 0.0
	var cy := 0.0
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) != best_faction:
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		cx += bp.x
		cy += bp.y
		n += 1
		if hall_pos == Vector2.INF \
				and String(b.get("type", "")) in SimTowns.HALL_TYPES:
			hall_pos = bp
	if hall_pos == Vector2.INF and n > 0:
		hall_pos = Vector2(cx / n, cy / n)
	if hall_pos == Vector2.INF:
		hall_pos = u.get("position", Vector2.ZERO)
	u["tax_hall_pos"] = hall_pos


func _tick_taxman(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if not u.has("tax_hall_pos"):
		_taxman_pick_target(u)
		_announce_once(u, "tax_announced",
			"THE TAXMAN COMETH",
			"A humorless man with a briefcase is auditing the realm's " \
			+ "richest faction. Back taxes will be collected.")
		if not bool(u.get("tax_greeted", false)):
			u["tax_greeted"] = true
			_gs.bus.unit_said.emit(int(u.get("id", 0)),
				TAXMAN_ARRIVE_LINES[randi() % TAXMAN_ARRIVE_LINES.size()])
	var hall_pos: Vector2 = u.get("tax_hall_pos", upos)
	if upos.distance_to(hall_pos) > 80.0:
		u["combat_state"] = "marching"
		_walk_to(u, hall_pos, speed, delta)
		return
	# Planted at the hall, stamping forms.
	u["combat_state"] = "auditing"
	_taxman_dread_aura(u, upos, delta)
	u["audit_cd"] = float(u.get("audit_cd", 5.0)) - delta
	if float(u.get("audit_cd", 0.0)) <= 0.0:
		u["audit_cd"] = TAXMAN_AUDIT_CD
		_taxman_audit(u)


## Audit-dread aura: citizens near a planted taxman build stress and start
## complaining. Mirrors the doom prophet's dread aura; barks use the ooze's
## per-citizen cooldown pattern.
func _taxman_dread_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if int(x.get("inside_building_id", 0)) > 0:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) > TAXMAN_DREAD_RADIUS:
			continue
		x["stress"] = minf(100.0,
			float(x.get("stress", 0.0)) + TAXMAN_DREAD_RATE * delta)
		_taxman_dread_bark(x, delta)


func _taxman_dread_bark(x: Dictionary, delta: float) -> void:
	if float(x.get("stress", 0.0)) < TAXMAN_DREAD_BARK_AT:
		return
	x["tax_bark_cd"] = float(x.get("tax_bark_cd", 0.0)) - delta
	if float(x.get("tax_bark_cd", 0.0)) <= 0.0:
		x["tax_bark_cd"] = TAXMAN_DREAD_BARK_CD
		_gs.bus.unit_said.emit(int(x.get("id", 0)),
			TAXMAN_DREAD_BURSTS[randi() % TAXMAN_DREAD_BURSTS.size()])


## One audit: garnish 8% of the treasury (clamped). A broke faction gets
## a withering tut instead — never a dead end, never negative gold.
func _taxman_audit(u: Dictionary) -> void:
	var faction: String = String(u.get("tax_faction", ""))
	if faction == "" or _gs.resources == null:
		return
	var gold: float = _gs.resources.get_amount(faction, "gold")
	if gold <= 0.0:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"Nothing to garnish. Suspicious. We'll be watching.")
		return
	var garnish: float = snappedf(
		clampf(gold * TAXMAN_RATE, TAXMAN_MIN, TAXMAN_MAX), 1.0)
	_gs.resources.add_resource(faction, "gold", -garnish)
	u["tax_collected"] = float(u.get("tax_collected", 0.0)) + garnish
	u["tax_audits"] = int(u.get("tax_audits", 0)) + 1
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		"%s ($%d back taxes)" % [
			TAXMAN_LINES[randi() % TAXMAN_LINES.size()], int(garnish)])


## Departure (budget spent): he files the paperwork, speaks his piece, and
## leaves with the gold. The Gazette summary headline fires off the ledger.
func _taxman_departed(u: Dictionary) -> void:
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		TAXMAN_DEPART_LINES[randi() % TAXMAN_DEPART_LINES.size()])
	_taxman_close_ledger(u)


## Slain: the realm exhales. Nearby citizens shed their audit dread, then the
## ledger closes like a departure (the summary prints the hero headline).
func _taxman_slain(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) > TAXMAN_RELIEF_RADIUS:
			continue
		x["stress"] = maxf(0.0,
			float(x.get("stress", 0.0)) - TAXMAN_RELIEF_STRESS)
	_taxman_close_ledger(u)


## Shared ledger close for slain + departed: the collection total the Gazette
## summary parses (GARNISHED ...) plus a TALLY beat (Karen/Ooze parity).
func _taxman_close_ledger(u: Dictionary) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return
	dlog.record_note(log_id, "GARNISHED %d gold" % int(
		float(u.get("tax_collected", 0.0))))
	dlog.record_note(log_id,
		("TALLY %d audits, $%d garnished") % [
			int(u.get("tax_audits", 0)),
			int(float(u.get("tax_collected", 0.0)))])


## Ooze target: a random town — it oozes in, parties, and oozes on.
func _ooze_pick_town(u: Dictionary) -> void:
	var town: Dictionary = _random_town()
	if town.is_empty():
		u["ooze_center"] = u.get("position", Vector2.ZERO)
		u["ooze_town"] = -1
		return
	u["ooze_town"] = int(town.get("id", -1))
	var hpos: Vector2 = town.get("position", Vector2.ZERO)
	u["ooze_center"] = hpos


func _tick_ooze(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if not u.has("ooze_center"):
		_ooze_pick_town(u)
		_announce_once(u, "ooze_announced",
			"BARON VON FOAM OOZES INTO TOWN",
			(OOZE_TITLE + " has arrived to throw an involuntary party. " \
			+ "Productivity has left the building."))
	if not bool(u.get("ooze_greeted", false)):
		u["ooze_greeted"] = true
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			OOZE_ARRIVE_LINES[randi() % OOZE_ARRIVE_LINES.size()])
	var center: Vector2 = u.get("ooze_center", upos)
	if upos.distance_to(center) <= 120.0:
		# Partied out here — ooze on to the next town.
		_ooze_pick_town(u)
		center = u.get("ooze_center", upos)
	u["combat_state"] = "oozing"
	_walk_to(u, center, speed, delta)
	# Soaked buildings keep the party going after he oozes on: collect
	# their positions once per tick (timers dry out in _tick_ambient).
	var soaked: Array[Vector2] = []
	for b: Dictionary in _gs.buildings:
		if float(b.get("beer_soak_t", 0.0)) > 0.0:
			soaked.append(b.get("position", Vector2.ZERO))
	# Party aura: bliss wipes stress, drunkenness builds. One pass.
	var drunk_sum := 0.0
	var drunk_n := 0
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if int(x.get("inside_building_id", 0)) > 0:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		var prev: float = float(x.get("drunk", 0.0))
		var drunk := prev
		if xpos.distance_to(upos) <= OOZE_RADIUS:
			drunk = minf(OOZE_DRUNK_MAX, prev + OOZE_DRUNK_RATE * delta)
			x["drunk"] = drunk
			drunk_sum += drunk
			drunk_n += 1
		elif _near_soaked(xpos, soaked):
			# Still wet here — the party lingers at half strength.
			drunk = minf(OOZE_DRUNK_MAX, prev + OOZE_DRUNK_RATE * 0.5 * delta)
			x["drunk"] = drunk
		# else: ambient decay (tick_ambient) handles sobering up.
		if drunk <= 0.0:
			continue
		x["stress"] = maxf(0.0,
			float(x.get("stress", 0.0)) - 40.0 * delta)
		_ooze_drink_tracking(u, prev, drunk)
		_ooze_drunk_bark(x, drunk, delta)
		if drunk >= OOZE_DRUNK_BEAT:
			_announce_once(u, "ooze_drunk_beat",
				"TOWN TOO DRUNK TO WORK",
				("A citizen has hit " + OOZE_NAME + "'s blackout threshold. " \
				+ "The shift is over, folks."))
	# Slurred escalation: when the average aura drunk crosses the line,
	# the Baron's own lines slur with the crowd.
	var slurred: bool = drunk_n > 0 \
		and drunk_sum / float(drunk_n) >= OOZE_SLURRED_AT
	u["shout_cd"] = float(u.get("shout_cd", 2.0)) - delta
	if float(u.get("shout_cd", 0.0)) <= 0.0:
		u["shout_cd"] = OOZE_SHOUT_CD
		var pool: Array = OOZE_SLURRED_LINES if slurred else OOZE_LINES
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			String(pool[randi() % pool.size()]))
	# Beer soak: every so often he christens a nearby building in foam.
	u["soak_cd"] = float(u.get("soak_cd", OOZE_SOAK_CD)) - delta
	if float(u.get("soak_cd", 0.0)) <= 0.0:
		u["soak_cd"] = OOZE_SOAK_CD
		_ooze_soak_building(u, upos)


## True if a position sits inside any soaked building's party aura.
func _near_soaked(xpos: Vector2, soaked: Array[Vector2]) -> bool:
	for sp: Vector2 in soaked:
		if xpos.distance_to(sp) <= OOZE_SOAK_AURA:
			return true
	return false


## Visit tallies: drinks poured (crossing 25 drunk = one round), peak
## drunkenness, and the running count of citizens who hit 50+.
func _ooze_drink_tracking(u: Dictionary, prev: float, drunk: float) -> void:
	if prev < 25.0 and drunk >= 25.0:
		u["ooze_drinks_poured"] = int(u.get("ooze_drinks_poured", 0)) + 1
	if prev < 50.0 and drunk >= 50.0:
		u["ooze_drunkards"] = int(u.get("ooze_drunkards", 0)) + 1
	u["ooze_peak_drunk"] = maxf(float(u.get("ooze_peak_drunk", 0.0)), drunk)


## Drunk citizens bark their own lines (throttled per unit).
func _ooze_drunk_bark(x: Dictionary, drunk: float, delta: float) -> void:
	if drunk < 50.0:
		return
	x["drunk_bark_cd"] = float(x.get("drunk_bark_cd", 0.0)) - delta
	if float(x.get("drunk_bark_cd", 0.0)) <= 0.0:
		x["drunk_bark_cd"] = OOZE_DRUNK_BARK_CD
		_gs.bus.unit_said.emit(int(x.get("id", 0)),
			OOZE_DRUNK_BURSTS[randi() % OOZE_DRUNK_BURSTS.size()])


## Splash a nearby building in foam: it stays soaked (beer_soak_t) and
## keeps the party going after the Baron oozes on.
func _ooze_soak_building(u: Dictionary, upos: Vector2) -> void:
	var cands: Array = []
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if float(b.get("beer_soak_t", 0.0)) > 0.0:
			continue  # already dripping
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		if bpos.distance_to(upos) <= OOZE_SOAK_RADIUS:
			cands.append(b)
	if cands.is_empty():
		return
	var b: Dictionary = cands[randi_range(0, cands.size() - 1)]
	b["beer_soak_t"] = OOZE_SOAK_T
	u["ooze_soaked"] = int(u.get("ooze_soaked", 0)) + 1
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		OOZE_SOAK_LINES[randi() % OOZE_SOAK_LINES.size()])


## Slain: the Baron bursts — everyone nearby gets a final round on him.
func _ooze_slain(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var soaked := 0
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) > OOZE_SLAIN_BURST_RADIUS:
			continue
		x["drunk"] = minf(OOZE_DRUNK_MAX,
			float(x.get("drunk", 0.0)) + OOZE_SLAIN_BURST_DRUNK)
		soaked += 1
	_ooze_file_tally(u, "SPLASHED %d citizens in the burst" % soaked)


## Departed (budget spent): the morning after. Drunkards get hangovers;
## the ledger finally closes (it never did before — dead end).
func _ooze_departed(u: Dictionary) -> void:
	var hangovers := 0
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if float(x.get("drunk", 0.0)) >= 50.0:
			x["hangover_t"] = OOZE_HANGOVER_T
			x["stress"] = minf(100.0,
				float(x.get("stress", 0.0)) + OOZE_HANGOVER_STRESS)
			hangovers += 1
	_ooze_file_tally(u, "%d hangovers filed" % hangovers)


## Shared TALLY ledger note for slain + departed.
func _ooze_file_tally(u: Dictionary, extra: String) -> void:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return
	dlog.record_note(log_id, extra)
	dlog.record_note(log_id,
		("TALLY %d drinks poured, %d drunkards, peak %d drunk, " \
		+ "%d buildings soaked") % [
			int(u.get("ooze_drinks_poured", 0)),
			int(u.get("ooze_drunkards", 0)),
			int(u.get("ooze_peak_drunk", 0.0)),
			int(u.get("ooze_soaked", 0))])


## Ambient per-tick: drunk/hangover decay even with no Baron around.
## Called from tick() so parties always end — sobriety is inevitable.
## Beer-soaked buildings also dry out here.
func _tick_ambient(delta: float) -> void:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		var drunk: float = float(x.get("drunk", 0.0))
		if drunk > 0.0:
			x["drunk"] = maxf(0.0, drunk - OOZE_DRUNK_DECAY * delta)
		var ho: float = float(x.get("hangover_t", 0.0))
		if ho > 0.0:
			x["hangover_t"] = maxf(0.0, ho - delta)
	for b: Dictionary in _gs.buildings:
		var soak: float = float(b.get("beer_soak_t", 0.0))
		if soak > 0.0:
			b["beer_soak_t"] = maxf(0.0, soak - delta)


## A point just off a random map edge for flying arrivals.
func _map_edge_point() -> Vector2:
	var side: int = randi() % 4
	var bx: float = world_bounds.size.x
	var by: float = world_bounds.size.y
	match side:
		0:
			return Vector2(randf() * bx, -120.0)
		1:
			return Vector2(randf() * bx, by + 120.0)
		2:
			return Vector2(-120.0, randf() * by)
	return Vector2(bx + 120.0, randf() * by)


## Jeremy 2026-10-04: attribute a death to an active disaster for the
## Gazette death toll. Called from SimCombat when any unit dies.
## victim: the dead unit record. source_faction: who dealt the blow
## ("monster" for disaster units, "fire" for wildfire). attacker_id: the
## killing unit's id (-1 if unknown).
func attribute_death(victim: Dictionary, source_faction: String,
		attacker_id: int) -> void:
	if victim.is_empty():
		return
	var vname := SimPersonality.display_name(victim)
	var vfaction := String(victim.get("faction", "?"))
	var vjob := String(victim.get("job", "?"))
	# Don't log monster-on-monster deaths.
	if vfaction == MONSTER_FACTION:
		return
	# 1) Killed directly by a disaster unit.
	if attacker_id >= 0:
		for r in dlog.active_records():
			var ids: Array = r.get("unit_ids", [])
			if attacker_id in ids:
				dlog.record_death(int(r.get("id", -1)), vname, vfaction,
					vjob, "slain", _gs.day_number)
				return
	# 2) Died while under orders to attack a disaster.
	var hunt_id: int = int(victim.get("disaster_hunt_id", -1))
	if hunt_id >= 0:
		for r in dlog.active_records():
			var ids2: Array = r.get("unit_ids", [])
			if hunt_id in ids2:
				dlog.record_death(int(r.get("id", -1)), vname, vfaction,
					vjob, "attacking", _gs.day_number)
				return
	# 3) Fire death while a fire/volcano disaster is active.
	if source_faction == "fire":
		var best: Dictionary = {}
		var best_d2 := 1e18
		var vpos: Vector2 = victim.get("position", Vector2.ZERO)
		for r in dlog.active_records():
			var k := String(r.get("kind", ""))
			if k != "volcano" and k != "wildfire":
				continue
			for f in fires:
				var d2: float = vpos.distance_squared_to(
					f.get("position", Vector2.ZERO))
				if d2 < best_d2:
					best_d2 = d2
					best = r
		if not best.is_empty():
			dlog.record_death(int(best.get("id", -1)), vname, vfaction,
				vjob, "burned", _gs.day_number)
			return
	# 4) Civilian panic death near any active disaster monster.
	if not SimCombat.is_fighter(victim):
		var vpos2: Vector2 = victim.get("position", Vector2.ZERO)
		var best2: Dictionary = {}
		var best_d2b := 500.0 * 500.0
		for r in dlog.active_records():
			for uid in r.get("unit_ids", []):
				var mu: Dictionary = _gs.get_unit(int(uid))
				if mu.is_empty() or not mu.get("alive", false):
					continue
				var d2: float = vpos2.distance_squared_to(
					mu.get("position", Vector2.ZERO))
				if d2 < best_d2b:
					best_d2b = d2
					best2 = r
		if not best2.is_empty():
			dlog.record_death(int(best2.get("id", -1)), vname, vfaction,
				vjob, "trampled", _gs.day_number)


## ---- disaster response orders (Jeremy 2026-10-04) --------------------------
## Military: attack | ignore | retreat. Citizens: shelter | free.
## Set from the phone calendar's disaster response panel.


func set_military_order(log_id: int, order: String) -> bool:
	return dlog.set_military_order(log_id, order)


func set_citizen_order(log_id: int, order: String) -> bool:
	return dlog.set_citizen_order(log_id, order)


## Orders for a forecast (future) disaster, stored on the forecast entry
## and carried onto the log record when it spawns.
func set_forecast_orders(day_of_month: int, military: String,
		citizens: String) -> bool:
	var e: Dictionary = forecast.get(day_of_month, {})
	if e.is_empty():
		return false
	if military in ["attack", "ignore", "retreat"]:
		e["military_order"] = military
	if citizens in ["shelter", "free"]:
		e["citizen_order"] = citizens
	return true


func forecast_orders(day_of_month: int) -> Dictionary:
	var e: Dictionary = forecast.get(day_of_month, {})
	return {
		"military": String(e.get("military_order", "ignore")),
		"citizens": String(e.get("citizen_order", "free")),
	}


## Applies active orders every tick: military hunt/retreat, citizen shelter.
func _apply_orders(_delta: float) -> void:
	var active: Array[Dictionary] = dlog.active_records()
	if active.is_empty():
		return
	var player_faction := String(_gs.player_faction)
	if player_faction == "":
		player_faction = "humans"
	for r in active:
		var log_id: int = int(r.get("id", -1))
		var mil := String(r.get("military_order", "ignore"))
		var civ := String(r.get("citizen_order", "free"))
		var unit_ids: Array = r.get("unit_ids", [])
		var hunt_target := -1
		if mil == "attack" and not unit_ids.is_empty():
			# First living disaster unit is the hunt target.
			for uid in unit_ids:
				var mu: Dictionary = _gs.get_unit(int(uid))
				if not mu.is_empty() and mu.get("alive", false):
					hunt_target = int(uid)
					break
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			if String(u.get("faction", "")) != player_faction:
				continue
			var is_f: bool = SimCombat.is_fighter(u)
			if is_f:
				if mil == "attack" and hunt_target >= 0:
					u["disaster_hunt_id"] = hunt_target
					u["defend_mode"] = false
				elif mil == "retreat":
					u["disaster_hunt_id"] = -1
					u["defend_mode"] = true
					u["combat_target"] = -1
				else:  # ignore
					if int(u.get("disaster_hunt_id", -1)) >= 0:
						# Only clear our order; self-defense still works.
						u["disaster_hunt_id"] = -1
			elif civ == "shelter":
				# Civilians take cover: damage reduction + stay put.
				u["in_cover"] = true
			elif not is_f and civ == "free":
				# Release shelter (but don't stomp cover from other systems
				# every tick — only clear if WE set it).
				if bool(u.get("disaster_shelter", false)):
					u["in_cover"] = false
					u["disaster_shelter"] = false
		# Mark sheltered civilians so we can release them cleanly.
		if civ == "shelter":
			for u2: Dictionary in _gs.units:
				if not u2.get("alive", false):
					continue
				if String(u2.get("faction", "")) != player_faction:
					continue
				if not SimCombat.is_fighter(u2):
					u2["disaster_shelter"] = true


## ---- monthly forecast ----------------------------------------------------


## Builds this month's disaster forecast: one of each major disaster on
## distinct days 3-27 (HTML generateDisasterCalendar, verbatim rules).
## The rogue wizard only answers the calendar's call ~3 months in 10.
func generate_disaster_calendar() -> void:
	forecast.clear()
	var events: Array = []
	for e in FORECAST_EVENTS:
		events.append(e)
	if randf() < FORECAST_WIZARD_CHANCE:
		events.append(FORECAST_WIZARD)
	var used := {}
	var days: Array[int] = []
	# Jeremy 2026-10-04: guard against infinite loop if events ever exceed
	# available days (hard-lock fix).
	var _fc_guard := 0
	while days.size() < events.size() and _fc_guard < 1000:
		_fc_guard += 1
		var d: int = randi_range(FORECAST_DAY_MIN, FORECAST_DAY_MAX)
		if not used.has(d):
			used[d] = true
			days.append(d)
	days.sort()
	# Jeremy 2026-10-04 (commando audit): if the guard above tripped there
	# are fewer distinct days than events — pair only what we have. Indexing
	# days[i] past its end would be a hard crash.
	var n := mini(events.size(), days.size())
	for i in n:
		var e: Dictionary = events[i]
		forecast[days[i]] = {
			"type": String(e["type"]),
			"label": String(e["label"]),
			"done": false,
		}
	if _gs.bus.has_signal("disaster_forecast_posted"):
		_gs.bus.disaster_forecast_posted.emit(forecast.duplicate(true))


## Fires today's forecast event around mid-day, once (HTML
## processCalendarDisasters: timeOfDay 10-16, entry.done = true).
func process_calendar_disasters() -> void:
	var dom: int = _day_of_month()
	if dom != _last_day:
		_last_day = dom
		if dom == 1:
			generate_disaster_calendar()
	var entry: Dictionary = forecast.get(dom, {})
	if entry.is_empty() or bool(entry.get("done", false)):
		return
	var hour: float = _hour_of_day()
	if hour < FORECAST_HOUR_MIN or hour > FORECAST_HOUR_MAX:
		return
	entry["done"] = true
	var kind: String = String(entry.get("type", ""))
	if _gs.bus.has_signal("disaster_forecast_fired"):
		_gs.bus.disaster_forecast_fired.emit(String(entry.get("label", "")))
	spawn(kind, _forecast_spawn_pos())


## Random spawn point, biased away from town centers (HTML: 20 tries to
## avoid within 280 px of any hall).
func _forecast_spawn_pos() -> Vector2:
	var p := Vector2(
		randf_range(200.0, world_bounds.size.x - 200.0),
		randf_range(200.0, world_bounds.size.y - 200.0))
	for _i in 20:
		var ok := true
		for t: int in _gs.towns.keys():
			var town: Dictionary = _gs.towns[t]
			if p.distance_to(town.get("position", Vector2.ZERO)) < 280.0:
				ok = false
				break
		if ok:
			return p
		p = Vector2(
			randf_range(200.0, world_bounds.size.x - 200.0),
			randf_range(200.0, world_bounds.size.y - 200.0))
	return p


## Day of the month from GameState (seasons-aware when the hook lands).
func _day_of_month() -> int:
	var seas = _gs.get("seasons")
	if seas != null and seas.has_method("day_of_month"):
		return int(seas.day_of_month())
	return ((_gs.day_number - 1) % 30) + 1


## Hour of day 0-24 from game_time.
func _hour_of_day() -> float:
	var seas = _gs.get("seasons")
	if seas != null and seas.has_method("hour_of_day"):
		return float(seas.hour_of_day())
	var phase: float = fmod(_gs.game_time, Config.DAY_LENGTH_SECONDS) \
		/ Config.DAY_LENGTH_SECONDS
	return phase * 24.0


## Cardboard cat: wanders aimlessly, menaces nothing.
func _tick_wanderer(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var wt: Vector2 = u.get("wander_target", upos)
	if upos.distance_to(wt) < 30.0:
		wt = Vector2(randf_range(200.0, world_bounds.size.x - 200.0),
			randf_range(200.0, world_bounds.size.y - 200.0))
		u["wander_target"] = wt
	_walk_to(u, wt, speed, delta)
	u["combat_state"] = "wandering"


func _start_leaving(u: Dictionary) -> void:
	u["leaving"] = true
	u["combat_state"] = "leaving"
	if String(u.get("job", "")) == "hoa_karen":
		_karen_departed(u)
	elif String(u.get("job", "")) == "seagull_swarm":
		_gulls_departed(u)
	elif String(u.get("job", "")) == "taxman":
		_taxman_departed(u)
	elif String(u.get("job", "")) == "booze_ooze":
		_ooze_departed(u)
	elif String(u.get("job", "")) == "doom_prophet":
		_prophet_departed(u)
	elif String(u.get("job", "")) == "gig_gnome":
		_driver_departed(u)
	elif String(u.get("job", "")) == "borg_crab_bill":
		_borg_crab_departed(u)
	elif String(u.get("job", "")) == "karaoke_barbarian":
		_karaoke_departed(u)
	elif String(u.get("job", "")) == "twister_sister":
		_twister_departed(u)
	elif String(u.get("job", "")) == "count_bastard":
		_bastard_departed(u)
	elif String(u.get("job", "")) == "rogue_wizard":
		_wizard_departed(u)
	elif String(u.get("job", "")) == "doomscroller":
		_doomscroll_departed(u)
	# Jeremy 2026-10-04: close the ledger + file the Gazette story.
	_end_log_record(u, "left")
	# Nearest map edge.
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var cands := [
		Vector2(-150.0, upos.y),
		Vector2(world_bounds.size.x + 150.0, upos.y),
		Vector2(upos.x, -150.0),
		Vector2(upos.x, world_bounds.size.y + 150.0),
	]
	var best: Vector2 = cands[0]
	var best_d2: float = upos.distance_squared_to(best)
	for c: Vector2 in cands:
		var d2: float = upos.distance_squared_to(c)
		if d2 < best_d2:
			best_d2 = d2
			best = c
	u["wander_target"] = best
	_gs.bus.disaster_left.emit(String(u.get("job", "")))


func _tick_leaving(u: Dictionary, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var wt: Vector2 = u.get("wander_target", upos)
	_walk_to(u, wt, float(u.get("speed", 70.0)) * 1.4, delta)
	if upos.distance_to(wt) < 60.0:
		# Off the map: gone. Remove the record directly (no corpse —
		# it left, it didn't die).
		_gs.units.erase(u)
		_gs.bus.unit_purged.emit(int(u.get("id", 0)))


func _walk_to(unit: Dictionary, target_pos: Vector2, speed: float,
		delta: float) -> void:
	var p: Vector2 = unit.get("position", Vector2.ZERO)
	var to: Vector2 = target_pos - p
	var dist: float = to.length()
	if dist < 4.0:
		return
	var step: float = minf(speed * delta, dist)
	# Cliffs: slope-aware — sheer faces block, slide along the edge.
	# Jeremy 2026-10-05: water rules — avoid unless fleeing.
	var np: Vector2 = Cliffs.try_step(_gs.map_data, p, to.normalized() * step)
	if WaterNav.unit_avoids_water(unit):
		np = WaterNav.dry_step(_gs.map_data, p, np - p)
	unit["position"] = np
	unit["swimming"] = WaterNav.is_water_at(_gs.map_data, np)
	# Jeremy 2026-10-10 road wear: firefighters' boots grind roads down too.
	if np != p and not bool(unit.get("swimming", false)):
		var wai = _gs.get("worker_ai")
		if wai != null:
			(wai as WorkerAI).wear_road_at(np,
				WorkerAI.WEAR_PER_SEC * delta)


## ---- save ---------------------------------------------------------------


## Milestone 7: export fires + forecast + volcano for save files.
func to_dict() -> Dictionary:
	var fc := {}
	for d in forecast.keys():
		# Jeremy 2026-10-04 (commando audit): never .duplicate() a
		# non-Dictionary value (corrupt save data must not crash export).
		if forecast[d] is Dictionary:
			fc[str(d)] = (forecast[d] as Dictionary).duplicate()
	var fr: Array = []
	for f: Dictionary in fires:
		fr.append(f.duplicate(true))
	var vs: Array = []
	for v: Dictionary in volcano_sites:
		vs.append(v.duplicate(true))
	return {
		"fires": fr,
		"forecast": fc,
		"next_fire_id": _next_fire_id,
		"last_day": _last_day,
		"volcano_timer": volcano_timer,
		"volcano_sites": vs,
		"disaster_log": dlog.to_dict(),
		"wildfire_log_id": _wildfire_log_id,
	}


## Milestone 7: restore fires + forecast + volcano from a save file.
func from_dict(data: Dictionary) -> void:
	fires.clear()
	for f in data.get("fires", []):
		if f is Dictionary:
			fires.append((f as Dictionary).duplicate(true))
	forecast.clear()
	var fc: Dictionary = data.get("forecast", {})
	for d in fc.keys():
		if fc[d] is Dictionary:
			forecast[int(d)] = (fc[d] as Dictionary).duplicate()
	_next_fire_id = int(data.get("next_fire_id", 1))
	_last_day = int(data.get("last_day", 1))
	volcano_timer = float(data.get("volcano_timer",
		randf_range(VOLCANO_PERIOD_MIN, VOLCANO_PERIOD_MAX)))
	volcano_sites.clear()
	for v in data.get("volcano_sites", []):
		if v is Dictionary:
			var site: Dictionary = (v as Dictionary).duplicate(true)
			var ids: Array[int] = []
			for pid in site.get("peak_ids", []):
				ids.append(int(pid))
			site["peak_ids"] = ids
			volcano_sites.append(site)
	dlog.from_dict(data.get("disaster_log", {}))
	# Re-link the wildfire record after restore: keep the saved id only
	# if the log still has that record active (saves written before the
	# wildfire ledger existed have fires but no record — open one so
	# burn deaths keep reaching the ledger).
	_wildfire_log_id = int(data.get("wildfire_log_id", -1))
	if not fires.is_empty():
		var rec: Dictionary = dlog.active_for_kind("wildfire")
		if rec.is_empty():
			_open_wildfire_record()
		else:
			_wildfire_log_id = int(rec.get("id", -1))
	else:
		_wildfire_log_id = -1
	# Ricky the Repo Gnome (dedicated-porting 2026-10-08): a save written
	# mid-tow leaves a building stranded with towed=true and no repo unit
	# (units may not persist). Snap every towed building back to its
	# foundation so loads can never strand a dragged building.
	_repo_sanitize_towed()


## Stranded-tow sanitation for save/load: any building still flagged towed
## is restored to its recorded foundation and unflagged.
func _repo_sanitize_towed() -> void:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("towed", false)):
			continue
		var home: Vector2 = b.get("repo_home",
			b.get("position", Vector2.ZERO))
		b["position"] = home
		# Perf R42: same invalidation as the tow path (see _repo_drop).
		if _combat != null:
			_combat._invalidate_building_grid()
		b["towed"] = false
		b.erase("repo_home")

## ---- Milo the Podcast Bro (Disaster #29) -----------------------------------
## Rapid-iteration 2026-10-08 — original content. A podcast bro rolls into
## the most populous town with a folding table, two giant mics and a ring
## light, flips the ON AIR sign, and records THE MILO EXPERIENCE live from
## the town square. 0 dmg; the weapon is ENGAGEMENT: citizens in range stop
## working to queue as guests (podcasting flag, honored by WorkerAI), and
## every guest feeds the download counter (cap 10,000 — the 12 listeners
## are very loyal). Interactive like Prince Gnomba (#26): he DMs the ruler
## a sponsor pitch — [Sponsor 300g] hypes the town and he leaves to "edit";
## [Unplug] cancels the podcast and the guests go back to work. A soldier
## who closes in confiscates the mics (deplatformed); the 240s visit timer
## ends the episode ("that's a wrap, gotta edit"). Singleton.

const PODCAST_DAILY_CHANCE := 0.03
const PODCAST_MIN_DAY := 10
const PODCAST_VISIT_SECONDS := 240.0
const PODCAST_FLEE_RADIUS := 130.0
const PODCAST_AURA_RADIUS := 260.0
const PODCAST_AURA_CD := 2.5
const PODCAST_SPONSOR_AMOUNT := 300.0
const PODCAST_DOWNLOAD_CAP := 10000.0

const PODCAST_DM_PITCH := "BROOO. It's MILO. Your town? INSANE stories, I'm not gonna lie. I'm recording THE MILO EXPERIENCE live from your square right now and my 12 listeners are EATING. IT. UP. Sponsor the episode for 300 gold and I'll tell the whole world your town is ALPHA. Or tap UNPLUG and I'll tell them you CENSORED me. Your call, chief. Smash that sponsor button."

const PODCAST_LINES := [
	"WELCOME BACK TO THE MILO EXPERIENCE!",
	"Smash that subscribe, my 12 listeners!",
	"My guest today is a LEVEL 3 TURNIP FARMER. Insane.",
	"We're just asking QUESTIONS here, okay?",
	"This episode is brought to you by ME.",
	"Bro, your aura is literally off the charts.",
	"Clip that. CLIP THAT.",
	"Don't be weird about the ring light.",
]


var _podcast_day: int = -1  # last day the Milo roll ran


func _maybe_spawn_podcast() -> void:
	if _gs.day_number == int(_podcast_day):
		return
	_podcast_day = _gs.day_number
	if _gs.day_number < PODCAST_MIN_DAY:
		return
	if randf() < PODCAST_DAILY_CHANCE:
		spawn("podcast_bro", _map_edge_point())


## Milo needs an audience — he bee-lines for the most populous town.
## Falls back to the nearest town, then map center like the prince.
func _podcast_pick_town(u: Dictionary) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_pop := -1
	var best_d2 := INF
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var pop := int(td.get("population", 0))
		var d2: float = upos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if pop > best_pop or (pop == best_pop and d2 < best_d2):
			best_pop = pop
			best_d2 = d2
			best = td
	if best.is_empty():
		u["podcast_center"] = Vector2(
			world_bounds.size.x * 0.5, world_bounds.size.y * 0.5)
		u["podcast_town_name"] = "the realm"
		u["podcast_faction"] = String(_gs.player_faction)
	else:
		u["podcast_center"] = best.get("position", Vector2.ZERO)
		u["podcast_town_name"] = String(best.get("name", "a town"))
		u["podcast_faction"] = String(best.get("faction", ""))


## Deplatform check: any soldier closing in ends the episode.
func _podcast_soldier_near(upos: Vector2) -> bool:
	for x: Dictionary in _gs.units:
		if not x.get("alive", false):
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if not JobDefs.is_military(String(x.get("job", ""))):
			continue
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_to(upos) <= PODCAST_FLEE_RADIUS:
			return true
	return false


## The pitch itself, DM'd to the ruler on arrival. Blocked Milos stay
## silent (blocking fully silences an NPC — standing rule).
func _podcast_send_dm(u: Dictionary) -> void:
	var ph = _gs.get("phone_sys")
	if ph == null or not ph.has_method("npc_message"):
		return
	var uid := int(u.get("id", 0))
	if ph.has_method("is_blocked") and bool(ph.call("is_blocked", uid)):
		return
	ph.npc_message(uid, PODCAST_DM_PITCH)


func _tick_podcast(u: Dictionary, speed: float, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var uid := int(u.get("id", 0))
	if bool(u.get("leaving", false)):
		_tick_leaving(u, delta)
		return
	if not u.has("podcast_center"):
		_podcast_pick_town(u)
		_announce_once(u, "podcast_announced",
			"A PODCAST HAS STARTED",
			"Milo the Podcast Bro has rolled his folding table into " \
			+ String(u.get("podcast_town_name", "the realm")) \
			+ ", flipped the ON AIR sign, and started recording THE MILO " \
			+ "EXPERIENCE live from the town square. Locals are queuing " \
			+ "up to be guests. Nobody is working.")
		_gs.bus.unit_said.emit(uid,
			_pick_line(PODCAST_LINES, "WELCOME BACK TO THE MILO EXPERIENCE!"))
		u["podcast_visit_left"] = PODCAST_VISIT_SECONDS
		u["podcast_offer"] = "pending"
		u["podcast_downloads"] = 0.0
		_podcast_send_dm(u)
	var center: Vector2 = u.get("podcast_center", upos)
	if upos.distance_to(center) > 120.0:
		u["combat_state"] = "arriving"
		_walk_to(u, center, speed, delta)
		return
	# In the square: hold position and record.
	u["combat_state"] = "recording"
	# Deplatformed: a soldier closes in and confiscates the mics.
	if _podcast_soldier_near(upos):
		_gs.bus.unit_said.emit(uid,
			"WHOA WHOA — you can't just TAKE the mics, that's CENSORSHIP!")
		_podcast_clear_guests(u)
		_announce_once(u, "podcast_deplatformed_story",
			"MILO GOT DEPLATFORMED",
			"A soldier confiscated Milo the Podcast Bro's microphones. " \
			+ "The ring light has been switched off. The 12 listeners " \
			+ "have been notified and are furious.")
		_start_leaving(u)
		return
	# That's a wrap: the visit timer runs out.
	u["podcast_visit_left"] = float(u.get("podcast_visit_left",
		PODCAST_VISIT_SECONDS)) - delta
	if float(u.get("podcast_visit_left", 0.0)) <= 0.0:
		_podcast_clear_guests(u)
		_announce_once(u, "podcast_wrap_story",
			"THAT'S A WRAP",
			"Milo the Podcast Bro has finished recording. \"Gotta go " \
			+ "edit,\" he said, packing the ring light. He will never " \
			+ "edit it. The episode will never air. The guests have " \
			+ "returned to work, spiritually changed.")
		_start_leaving(u)
		return
	_podcast_aura(u, upos, delta)
	u["podcast_shout_cd"] = float(u.get("podcast_shout_cd", 9.0)) - delta
	if float(u.get("podcast_shout_cd", 0.0)) <= 0.0:
		u["podcast_shout_cd"] = 9.0
		_gs.bus.unit_said.emit(uid,
			_pick_line(PODCAST_LINES, "WELCOME BACK TO THE MILO EXPERIENCE!"))


## The engagement aura, on a 2.5s cadence: every non-military local in
## range becomes a podcast guest (podcasting flag — WorkerAI holds them
## out of the task picker). Each guest feeds the download counter; 1k is
## a shout, 5k files a Gazette story, 10k is viral (all 12 listeners).
func _podcast_aura(u: Dictionary, upos: Vector2, delta: float) -> void:
	u["podcast_aura_cd"] = float(u.get("podcast_aura_cd", 0.0)) - delta
	if float(u.get("podcast_aura_cd", 0.0)) > 0.0:
		return
	u["podcast_aura_cd"] = PODCAST_AURA_CD
	var faction := String(u.get("podcast_faction", ""))
	if faction == "":
		return
	var r2: float = PODCAST_AURA_RADIUS * PODCAST_AURA_RADIUS
	var guests := 0
	for x: Dictionary in _gs.units:
		if not x.get("alive", false) or x == u:
			continue
		if String(x.get("faction", "")) == MONSTER_FACTION:
			continue
		if String(x.get("faction", "")) != faction:
			continue  # he only records the locals
		if JobDefs.is_military(String(x.get("job", ""))):
			continue  # soldiers don't go on pods
		var xpos: Vector2 = x.get("position", Vector2.ZERO)
		if xpos.distance_squared_to(upos) > r2:
			if bool(x.get("podcasting", false)):
				x["podcasting"] = false
			continue
		if not bool(x.get("podcasting", false)):
			x["podcasting"] = true
			x["work_state"] = "idle"
		guests += 1
	if guests == 0:
		return
	var before := float(u.get("podcast_downloads", 0.0))
	var after := minf(PODCAST_DOWNLOAD_CAP, before + float(guests) * 12.0)
	u["podcast_downloads"] = after
	if before < 1000.0 and after >= 1000.0:
		_gs.bus.unit_said.emit(int(u.get("id", 0)),
			"1,000 DOWNLOADS! We are SO back!")
	if before < 5000.0 and after >= 5000.0:
		_announce_once(u, "podcast_5k_story",
			"MILO HITS 5K DOWNLOADS",
			"Milo the Podcast Bro's town-square episode has passed 5,000 " \
			+ "downloads. All 12 of his listeners have listened over 400 " \
			+ "times each. The guests remain seated. Nobody is working.")
	if before < PODCAST_DOWNLOAD_CAP and after >= PODCAST_DOWNLOAD_CAP:
		_announce_once(u, "podcast_viral_story",
			"MILO GOES VIRAL",
			"Milo the Podcast Bro has hit 10,000 downloads — every one " \
			+ "of his 12 listeners, hundreds of times. Town criers " \
			+ "confirm this is the biggest thing to ever happen in " \
			+ String(u.get("podcast_town_name", "the realm")) + ".")


## Guests go home when the episode ends (deplatform / wrap / resolve /
## slain). Clears the flag so WorkerAI picks them back up next tick.
func _podcast_clear_guests(u: Dictionary) -> void:
	var faction := String(u.get("podcast_faction", ""))
	for x: Dictionary in _gs.units:
		if String(x.get("faction", "")) != faction:
			continue
		if bool(x.get("podcasting", false)):
			x["podcasting"] = false
			x["work_state"] = "idle"


## Phone seam: is this unit Milo with a live sponsor offer? Used by the
## Messenger thread view to show the inline Sponsor / Unplug buttons.
func podcast_offer_pending(unit_id: int) -> bool:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return false
	return String(u.get("job", "")) == "podcast_bro" \
		and bool(u.get("alive", false)) \
		and String(u.get("podcast_offer", "")) == "pending"


## Milo's DM thread is a live offer. Called from SimPhone._npc_reply
## BEFORE the conversation engine. Returns Milo's reply text, or "" when
## the text isn't an offer verdict (normal chat proceeds untouched).
func podcast_offer_reply(unit: Dictionary, text: String) -> String:
	if String(unit.get("job", "")) != "podcast_bro":
		return ""
	if not bool(unit.get("alive", false)):
		return ""
	if String(unit.get("podcast_offer", "")) != "pending":
		return ""
	var t := text.strip_edges().to_lower()
	var is_sponsor := t in ["sponsor", "yes", "accept", "deal", "sponsor it"] \
		or t.begins_with("sponsor ")
	var is_unplug := t in ["unplug", "cancel", "no", "deny", "stop", "censor"] \
		or t.begins_with("unplug ") or t.begins_with("cancel ")
	if not is_sponsor and not is_unplug:
		return ""
	return _podcast_resolve(unit, is_sponsor)


## Resolves the offer. Runs on the player's tap — safe to call outside tick
## (only flips flags, moves gold, files stories, starts leaving).
func _podcast_resolve(u: Dictionary, sponsor: bool) -> String:
	var pf := String(_gs.player_faction)
	if not sponsor:
		u["podcast_offer"] = "unplugged"
		_podcast_clear_guests(u)
		_announce_once(u, "podcast_unplugged_story",
			"PODCAST CANCELED",
			"The ruler unplugged Milo the Podcast Bro. He called it " \
			+ "censorship, packed the ring light, and muttered something " \
			+ "about the mainstream media all the way to the map edge. " \
			+ "The guests have returned to work.")
		_start_leaving(u)
		return "WOW. Okay. CENSORED. You'll be hearing about this on the pod, chief. ...The pod is over. This is the last episode."
	var have: float = float(_gs.resources.get_amount(pf, "gold"))
	if have < PODCAST_SPONSOR_AMOUNT:
		return "Bro. BRO. The sponsor slot is 300 gold and your treasury is literally empty. Come back when you're serious about engagement."
	_gs.resources.spend(pf, {"gold": PODCAST_SPONSOR_AMOUNT})
	u["podcast_offer"] = "sponsored"
	_podcast_clear_guests(u)
	_announce_once(u, "podcast_sponsored_story",
		"RULER SPONSORS THE MILO EXPERIENCE",
		"The ruler sponsored Milo the Podcast Bro's episode for 300 " \
		+ "gold. Milo declared the town ALPHA to all 12 of his " \
		+ "listeners, then left to \"edit\" the episode. Morale across " \
		+ "the town has never been higher. The episode will never air.")
	_start_leaving(u)
	return "LET'S GOOO! The town is ALPHA, the listeners know it, I know it, the ring light knows it. Gotta go edit — this one's going VIRAL. (It will never air.)"


## Slain: file the outcome for the Gazette. (Alive departures file their
## own stories at the moment they happen — deplatformed / wrap /
## unplugged / sponsored.)
func _podcast_departed(u: Dictionary) -> void:
	if not bool(u.get("alive", false)):
		_podcast_clear_guests(u)
		_announce_once(u, "podcast_slain_story",
			"PODCAST CANCELED (PERMANENTLY)",
			"Milo the Podcast Bro has been slain mid-episode. His final " \
			+ "words were \"clip that.\" There is no clip. The ring light " \
			+ "flickers out. The 12 listeners hold a vigil.")
