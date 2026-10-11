class_name Config
extends RefCounted
## Cursing Gnomes — every tunable number in one place.
## Jeremy's laws live here so no spawner can "forget" them.
## (Ports the spirit of the HTML build's scattered caps into one contract.)

# --- Identity ---------------------------------------------------------------
const GAME_NAME := "Cursing Gnomes"
const GAME_VERSION := "0.0.1-godot"

# --- Factions ---------------------------------------------------------------
# Keys are faction ids used everywhere (save files, netcode, UI).
const FACTIONS := {
	"humans": {"name": "Humans", "color": Color(0.3, 0.5, 0.9)},
	"ogres": {"name": "Ogres", "color": Color(0.5, 0.7, 0.3)},
	"elves": {"name": "Elves", "color": Color(0.3, 0.8, 0.5)},
	"gnomes": {"name": "Gnomes", "color": Color(0.9, 0.6, 0.2)},
	"undead": {"name": "Undead", "color": Color(0.6, 0.4, 0.8)},
}

# --- Population law (Jeremy's hard caps) ------------------------------------
# Updated 2026-10-02: Jeremy wants "more units, less limits"
# Doubled from HTML caps (8/24/96) — Godot handles more efficiently
const POP_CAP_TOWN := 16       # hard limit per town, all unit types
const POP_CAP_FACTION := 48    # hard limit per faction
const POP_CAP_GLOBAL := 240    # hard limit across the whole map (5 × 48)
const TOWNS_PER_FACTION := 3   # worldgen target

# --- Essential services (exempt from the per-town cap, per 2026-10-02) -------
const FIREFIGHTERS_PER_STATION := 2
const DOCTORS_PER_CLINIC := 1
## Jobs that bypass the per-town population cap (still bound by faction/global).
## Guild halls and guard houses auto-staff like clinics/fire stations
## (SERVICE_BUILDINGS), so their service jobs bypass the town cap too —
## otherwise a full town silently blocked the guild master forever
## (Jeremy 2026-10-03: "Nothing spawns. It doesn't even function").
const ESSENTIAL_JOBS := ["firefighter", "doctor", "guild_master", "guard"]

## Service-building staffing targets (mirrors the HTML auto-staff rules).
const GUARDS_PER_HOUSE := 2       # guard houses auto-staff 2 guards
const GUILDMASTERS_PER_HALL := 1  # one guild master per faction (job cap)
const BARRACKS_BEDS := 25       # Jeremy's law: 25 beds per barracks (MISS 16)

# --- Resources --------------------------------------------------------------
const RESOURCES := ["gold", "wood", "food", "seeds", "oil", "soul_essence"]

# --- Sim --------------------------------------------------------------------
const TICKS_PER_SECOND := 60          # logic rate (physics ticks)
const DAY_LENGTH_SECONDS := 14400.0     # full day/night cycle (Jeremy 2026-10-04: 10 irl sec = 1 game min, was 960)
const AUTOSPAWN_RETRY_SECONDS := 10.0 # clinic / fire-station retry throttle

# --- Mobile -----------------------------------------------------------------
# Godot targets 60 fps on mobile. The HTML build's 30 fps cap was a Safari
# emergency fix for overheating — NOT the Godot plan. If heat becomes an
# issue here, optimize the game logic; never cap the frame rate.
const MOBILE_TARGET_FPS := 60

# --- Minds (Milestone 5) ----------------------------------------------------
const MIND_MEMORY_CAP := 24      # max memories per NPC (weakest forgotten)
const MIND_CHATTER_MIN_CD := 45.0  # fastest idle-chatter interval (s)
const MIND_CHATTER_MAX_CD := 120.0  # slowest idle-chatter interval (s)

## Named regions + cities — HTML REGION_NAME_POOL/CITY_NAME_POOL parity.
## (Jeremy 2026-10-02 audit: towns were "Humans Town" placeholders.)
const REGION_NAMES: Array[String] = [
	"Embermeadow",
	"Stonehollow",
	"Thornfell",
	"Mistmoor",
	"Cinderfen",
	"Foxglove Downs",
	"The Barrows",
	"Gallows Hill",
	"Wrenmoor",
	"Alderwash",
	"Birchmere",
	"Cragspire",
	"Dunmarsh",
	"Eelwater",
	"Frostbite Pass",
	"Grimshaw",
	"Hawthorn Reach",
	"Ironbough",
	"Jademire",
	"Kingsfall",
	"Larkspur Fields",
	"Mossglen",
	"Nettlewood",
	"Oakhaven March",
	"Pike Hollow",
	"Quillpen Crags",
	"Ravenroost",
	"Saltmarsh",
	"Tanglebriar",
	"Umberdell",
	"Vexmoor",
	"Willowshade",
	"Yewbarrow",
	"Zephyr Steppe",
	"Duskvale",
	"Copper Flats",
	"Sablewood",
	"Thornwick",
	"Palefen",
	"Bramblecombe",
	"The Howling Wastes",
	"Sunspire Mesa",
	"Gravelight Downs",
	"Murkmire",
]
const CITY_NAMES: Array[String] = [
	"Aldergate",
	"Barrowfield",
	"Cinderhold",
	"Duskhaven",
	"Emberford",
	"Falconstead",
	"Gravelmark",
	"Hollowmere",
	"Ironfen",
	"Jorvik",
	"Kelpwick",
	"Lantern Hill",
	"Marrowgate",
	"Nettleby",
	"Ostreach",
	"Pyreholme",
	"Quarrydeep",
	"Rivenscar",
	"Saltspire",
	"Thistledown",
	"Underbough",
	"Vellwick",
	"Wraystone",
	"Yarrowmere",
	"Zirren",
	"Bellows",
	"Corvane",
	"Drenholm",
	"Eska",
	"Frostmelt",
	"Glimmerdeep",
	"Harrowgate",
	"Inkwell",
	"Kestrel's Rest",
	"Juttmark",
	", ",
	", ",
	", ",
	", ",
	", ",
	", ",
	", ",
	", ",
	", ",
	", ",
]
