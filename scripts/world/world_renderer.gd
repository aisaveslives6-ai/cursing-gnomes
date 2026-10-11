class_name WorldRenderer
extends Node2D
## Cursing Gnomes — turns MapGen data into visible nodes (Milestone 2).
##
## The terrain Image bakes into ONE texture (one draw call for the whole map).
## Trees and resource nodes become y-sorted MapProp children of props_parent
## so units walk behind canopies. GL Compatibility safe: no shaders here.


## Tree MapProps in creation order (world applies the graphics-tier draw
## budget by toggling visibility — HTML maxTreesDraw parity).
var tree_props: Array = []


## Builds the terrain sprite and all prop nodes. Returns the terrain Sprite2D.
func render_map(map_data: Dictionary, props_parent: Node2D) -> Sprite2D:
	var img: Image = map_data["terrain_image"]
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = Vector2.ZERO
	var world_size: Vector2 = map_data["world_size"]
	var s: float = world_size.x / float(img.get_width())
	sprite.scale = Vector2(s, s)
	# z_index -100 keeps the terrain behind every y-sorted sibling
	# (y-sort orders by y first, z_index breaks ties globally).
	sprite.z_index = -100
	add_child(sprite)

	var trees: PackedVector2Array = map_data["trees"]
	tree_props.clear()
	for tp in trees:
		var prop := MapProp.new()
		prop.setup("tree", tp)
		props_parent.add_child(prop)
		tree_props.append(prop)

	var resources: Array = map_data["resources"]
	for r in resources:
		# Jeremy 2026-10-05: NO wood piles, NO oil piles — trees are the
		# wood source, oil pumps are the oil source. Skip both for old
		# map data that may still list them.
		if String(r["type"]) == "wood" or String(r["type"]) == "oil":
			continue
		var prop2 := MapProp.new()
		prop2.setup("res_" + String(r["type"]), r["position"])
		props_parent.add_child(prop2)

	return sprite
