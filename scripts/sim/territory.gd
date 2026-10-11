class_name SimTerritory
extends RefCounted
## Cursing Gnomes — territory claims + named regions (Milestone 3b).
##
## Ported from the HTML build (not its code):
##   - TERRITORY_R = 520: each COMPLETED hall claims a 520px radius circle.
##     claimOwnerAt() returns the race of the nearest claiming hall, or null
##     when unclaimed. isInEnemyTerritory() blocks FOREIGN builds on claimed
##     land (walls are exempt — they may go anywhere).
##   - Named regions (44-name pool): completed halls of the same race within
##     TERRITORY_R*2.2 join one region; unclaimed land is split into 4x3
##     geographic sectors with their own names (HTML getRegions, verbatim).
##     Names are dealt deterministically (sorted centroid order for faction
##     clusters, then sectors in gx/gy order, dealt round-robin from the
##     pool) so regions are stable within a game.
##
## Pure logic — no rendering, no input, no audio.


## Completed-hall claim radius, in world px (HTML TERRITORY_R).
const TERRITORY_R := 520.0

## Building types that found a territory claim.
const CLAIM_TYPES := ["hall", "town_hall", "townhall"]

## HTML's 44-name region pool (FEATURE 5), verbatim.
const REGION_NAME_POOL: Array[String] = [
	"Embermeadow", "Stonehollow", "Thornfell", "Mistmoor", "Cinderfen",
	"Foxglove Downs", "The Barrows", "Gallows Hill", "Wrenmoor", "Alderwash",
	"Birchmere", "Cragspire", "Dunmarsh", "Eelwater", "Frostbite Pass",
	"Grimshaw", "Hawthorn Reach", "Ironbough", "Jademire", "Kingsfall",
	"Larkspur Fields", "Mossglen", "Nettlewood", "Oakhaven March", "Pike Hollow",
	"Quillpen Crags", "Ravenroost", "Saltmarsh", "Tanglebriar", "Umberdell",
	"Vexmoor", "Willowshade", "Yewbarrow", "Zephyr Steppe", "Duskvale",
	"Copper Flats", "Sablewood", "Thornwick", "Palefen", "Bramblecombe",
	"The Howling Wastes", "Sunspire Mesa", "Gravelight Downs", "Murkmire",
]


## Race of the nearest COMPLETED hall within TERRITORY_R of pos, or ""
## when the ground is unclaimed.
static func claim_owner_at(buildings: Array, pos: Vector2) -> String:
	var best := ""
	var best_d := TERRITORY_R
	for b: Dictionary in buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if not String(b.get("type", "")) in CLAIM_TYPES:
			continue
		var d: float = pos.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = String(b.get("faction", ""))
	return best


## True when pos is inside ANOTHER faction's claimed territory.
static func is_enemy_territory(buildings: Array, faction: String,
		pos: Vector2) -> bool:
	var owner: String = claim_owner_at(buildings, pos)
	return owner != "" and owner != faction


## All completed, alive halls of a faction.
static func halls_of(buildings: Array, faction: String) -> Array:
	var out: Array = []
	for b: Dictionary in buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if not String(b.get("type", "")) in CLAIM_TYPES:
			continue
		if String(b.get("faction", "")) == faction:
			out.append(b)
	return out


## Named regions (44-name pool): completed halls of the same race within
## TERRITORY_R*2.2 join one region (HTML getRegions clustering). Unclaimed
## land is split into 4x3 geographic sectors (HTML getRegions, verbatim):
## a sector whose center is claimed, or within TERRITORY_R*1.2 of a faction
## cluster centroid, gets no label. Returns Array of
## {id, name, race, cx, cy, hall_ids: Array[int]}.
## Sectors have race == "" and ids "u_<gx>_<gy>".
static func compute_regions(buildings: Array,
		world_size := Vector2(4096.0, 4096.0)) -> Array:
	var join_dist: float = TERRITORY_R * 2.2
	var halls: Array = []
	for b: Dictionary in buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if not String(b.get("type", "")) in CLAIM_TYPES:
			continue
		halls.append(b)
	# Cluster: nearest-cluster merge until stable (same-race only).
	var clusters: Array = []
	for h: Dictionary in halls:
		var placed := false
		for c: Dictionary in clusters:
			if String(c["race"]) != String(h.get("faction", "")):
				continue
			var cp := Vector2(c["cx"], c["cy"])
			if cp.distance_to(h.get("position", Vector2.ZERO)) <= join_dist:
				(c["members"] as Array).append(h)
				placed = true
				break
		if not placed:
			clusters.append({
				"race": String(h.get("faction", "")),
				"members": [h],
				"cx": (h.get("position", Vector2.ZERO) as Vector2).x,
				"cy": (h.get("position", Vector2.ZERO) as Vector2).y,
			})
	var merged := true
	while merged:
		merged = false
		for i: int in range(clusters.size()):
			for j: int in range(i + 1, clusters.size()):
				var a: Dictionary = clusters[i]
				var b: Dictionary = clusters[j]
				if String(a["race"]) != String(b["race"]):
					continue
				if Vector2(a["cx"], a["cy"]).distance_to(Vector2(b["cx"], b["cy"])) <= join_dist:
					(a["members"] as Array).append_array(b["members"] as Array)
					clusters.remove_at(j)
					merged = true
					break
			if merged:
				break
	# Centroids, sorted for deterministic name dealing.
	var regions: Array = []
	for c: Dictionary in clusters:
		var sx := 0.0
		var sy := 0.0
		var ids: Array[int] = []
		for m: Dictionary in c["members"]:
			var mp: Vector2 = m.get("position", Vector2.ZERO)
			sx += mp.x
			sy += mp.y
			ids.append(int(m.get("id", 0)))
		var n: int = maxf(1.0, float((c["members"] as Array).size()))
		regions.append({
			"id": "",
			"name": "",
			"race": String(c["race"]),
			"cx": sx / n,
			"cy": sy / n,
			"hall_ids": ids,
		})
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Vector2(a["cx"], a["cy"]).x < Vector2(b["cx"], b["cy"]).x)
	# Unclaimed 4x3 geographic sectors (HTML getRegions, verbatim).
	var close_dist: float = TERRITORY_R * 1.2
	for gx: int in range(4):
		for gy: int in range(3):
			var spos := Vector2(
				world_size.x * (float(gx) + 0.5) / 4.0,
				world_size.y * (float(gy) + 0.5) / 3.0)
			if claim_owner_at(buildings, spos) != "":
				continue
			var near := false
			for r: Dictionary in regions:
				if Vector2(float(r["cx"]), float(r["cy"])).distance_to(
						spos) <= close_dist:
					near = true
					break
			if near:
				continue
			regions.append({
				"id": "u_%d_%d" % [gx, gy],
				"name": "",
				"race": "",
				"cx": spos.x,
				"cy": spos.y,
				"hall_ids": [],
			})
	for i: int in range(regions.size()):
		var r: Dictionary = regions[i]
		r["name"] = REGION_NAME_POOL[i % REGION_NAME_POOL.size()]
		if String(r.get("race", "")) != "":
			r["id"] = "region_%d" % i
	return regions
