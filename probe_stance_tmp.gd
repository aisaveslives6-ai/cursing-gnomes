extends SceneTree

func _initialize() -> void:
	var gs = load("res://scripts/core/game_state.gd").new()
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	var snoop: Dictionary = gs.add_unit({"faction": "ogres", "alive": true})
	var lo := 99.0
	var hi := -99.0
	var under := 0
	for i in 200:
		var cand: Dictionary = gs.add_unit({"faction": "elves", "alive": true})
		var s: float = likes.npc_stance(cand, snoop, gs)
		lo = minf(lo, s)
		hi = maxf(hi, s)
		if s <= -0.3:
			under += 1
	print("min=", lo, " max=", hi, " count<=-0.3: ", under, " of 200")
	print("relation elves-ogres: ", gs.diplomacy.relation_state("elves", "ogres"))
	quit(0)
