class_name SpriteNormals
extends RefCounted
## Cursing Gnomes — procedural normal maps for 2D sprite lighting.
##
## Technique from "2D Game Art, Animation, and Lighting for Artists": derive
## a heightmap from the sprite (alpha silhouette + a whisper of luminance
## detail), then Sobel it into a tangent-space normal map. Godot 4 removed
## Sprite2D.normal_map (it lived on the sprite in Godot 3) — the Godot 4
## path is a CanvasTexture resource: sprite.texture = CanvasTexture with
## diffuse_texture + normal_texture set. The existing PointLight2D rig
## (lighting.gd — public API untouched) then shades sprites directionally
## instead of hitting them flat.
##
## Load-time only: wrap_texture()/generate() are cached per Texture2D and never run
## per-frame. Sprites larger than MAX_SIZE on a side return null (the caller
## leaves the texture unwrapped) to bound load-time hitches. Fully
## transparent pixels are forced flat so lights never draw halos around
## silhouettes.


## Skip sprites bigger than this (px on a side) — bounds load-time cost.
const MAX_SIZE := 256
## Sobel gradient scale: bevel-like relief, not lumps. Tune to taste.
const BUMP_STRENGTH := 0.32
## Luminance detail contribution to height (kept small so pixel-art
## dithering doesn't turn into lumps).
const DETAIL_AMOUNT := 0.25
## Silhouette soft-edge band over the alpha channel.
const EDGE_LO := 0.12
const EDGE_HI := 0.88
## Alpha at or below this (of 255) counts as transparent -> forced flat.
const ALPHA_FLAT := 8

## Cache: diffuse Texture2D -> CanvasTexture wrap (null = skipped/oversize).
static var _cache: Dictionary = {}


## Wrap sprite.texture in a CanvasTexture carrying a procedural normal map.
## No-op when the texture is null, oversize, or already wrapped by us
## (texture swaps are picked up; steady state costs one meta lookup).
static func apply_to(sprite: Sprite2D) -> void:
	if sprite == null:
		return
	var tex: Texture2D = sprite.texture
	if tex == null:
		return
	if tex is CanvasTexture:
		if tex.has_meta("sn_wrapped"):
			return  # our wrap already in place
		# Foreign CanvasTexture: wrap its diffuse instead of nesting.
		var d: Texture2D = (tex as CanvasTexture).diffuse_texture
		if d == null:
			return
		tex = d
	var wrapped := wrap_texture(tex)
	if wrapped != null:
		sprite.texture = wrapped


## The raw albedo texture behind a (possibly wrapped) texture.
static func diffuse_of(tex: Texture2D) -> Texture2D:
	if tex is CanvasTexture:
		var d: Texture2D = (tex as CanvasTexture).diffuse_texture
		if d != null:
			return d
	return tex


## Build (or fetch from cache) a CanvasTexture carrying a procedural
## normal map for tex. Returns null for null/degenerate/oversize textures.
static func wrap_texture(tex: Texture2D) -> CanvasTexture:
	if tex == null:
		return null
	if _cache.has(tex):
		return _cache[tex]
	var ct: CanvasTexture = null
	var w := tex.get_width()
	var h := tex.get_height()
	if w >= 2 and h >= 2 and w <= MAX_SIZE and h <= MAX_SIZE:
		var nm := _build(tex, w, h)
		if nm != null:
			ct = CanvasTexture.new()
			ct.diffuse_texture = tex
			ct.normal_texture = nm
			ct.set_meta("sn_wrapped", true)
	_cache[tex] = ct
	return ct


## Build just the normal-map Texture2D (no CanvasTexture). Cached.
## Returns null for null/degenerate/oversize textures.
static func generate(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if tex is CanvasTexture:
		tex = diffuse_of(tex)
	var w := tex.get_width()
	var h := tex.get_height()
	if w < 2 or h < 2 or w > MAX_SIZE or h > MAX_SIZE:
		return null
	var wrapped := wrap_texture(tex)
	if wrapped == null:
		return null
	return wrapped.normal_texture


## Clear the cache (tests / art reload). Gameplay never calls this.
static func clear_cache() -> void:
	_cache.clear()


static func _build(tex: Texture2D, w: int, h: int) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var n := w * h
	if data.size() < n * 4:
		return null
	# Work at half resolution (bevel normals are smooth; bilinear upscale
	# loses nothing visible) — ~4x faster, then force transparent pixels
	# flat at full resolution so lights never draw halos.
	var hw := maxi(w / 2, 2)
	var hh := maxi(h / 2, 2)
	var hn := hw * hh
	# Pass 1: heightmap — alpha silhouette (soft edge) plus a whisper of
	# luminance detail, masked by the silhouette so transparent regions
	# stay perfectly flat.
	var height := PackedFloat32Array()
	height.resize(hn)
	var edge_span := maxf(EDGE_HI - EDGE_LO, 0.001)
	var hi := 0
	for hy in range(hh):
		var sy := mini(hy * 2, h - 1)
		for hx in range(hw):
			var sx := mini(hx * 2, w - 1)
			var i4 := (sy * w + sx) * 4
			var a := float(data[i4 + 3]) / 255.0
			var sil := clampf((a - EDGE_LO) / edge_span, 0.0, 1.0)
			sil = sil * sil * (3.0 - 2.0 * sil)  # smoothstep the edge
			var lum := (float(data[i4]) + float(data[i4 + 1]) \
				+ float(data[i4 + 2])) / 765.0
			height[hi] = sil * (1.0 + (lum - 0.5) * DETAIL_AMOUNT)
			hi += 1
	# Pass 2: Sobel gradients -> tangent-space normals. Flat = (128,128,255).
	var out := PackedByteArray()
	out.resize(hn * 4)
	var s := BUMP_STRENGTH
	var o4 := 0
	for y in range(hh):
		var ym := maxi(y - 1, 0) * hw
		var yp := mini(y + 1, hh - 1) * hw
		var yc := y * hw
		for x in range(hw):
			var xm := maxi(x - 1, 0)
			var xp := mini(x + 1, hw - 1)
			var oi := yc + x
			if height[oi] <= 0.0 and _half_alpha(data, w, h, x, y) <= ALPHA_FLAT:
				# Fully transparent: forced flat, no light halos.
				out[o4] = 128
				out[o4 + 1] = 128
				out[o4 + 2] = 255
				out[o4 + 3] = 255
			else:
				var tl := height[ym + xm]
				var tc := height[ym + x]
				var tr := height[ym + xp]
				var ml := height[yc + xm]
				var mr := height[yc + xp]
				var bl := height[yp + xm]
				var bc := height[yp + x]
				var br := height[yp + xp]
				var dx := (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl)
				var dy := (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr)
				var gx := -dx * s
				var gy := -dy * s
				var inv := 1.0 / sqrt(gx * gx + gy * gy + 1.0)
				out[o4] = int(clampf((gx * inv * 0.5 + 0.5) * 255.0, 0.0, 255.0))
				out[o4 + 1] = int(clampf((gy * inv * 0.5 + 0.5) * 255.0, 0.0, 255.0))
				out[o4 + 2] = int(clampf((inv * 0.5 + 0.5) * 255.0, 0.0, 255.0))
				out[o4 + 3] = 255
			o4 += 4
	var small := Image.create_from_data(hw, hh, false, Image.FORMAT_RGBA8, out)
	if small == null or small.is_empty():
		return null
	if hw != w or hh != h:
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
	# Pass 3: exact transparent flatten at full resolution (the upscale
	# bleeds edge normals into neighboring transparent pixels).
	var full := small.get_data()
	var f4 := 3
	for i in range(n):
		if data[f4] <= ALPHA_FLAT:
			full[f4 - 3] = 128
			full[f4 - 2] = 128
			full[f4 - 1] = 255
		f4 += 4
	var nm_img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, full)
	if nm_img == null or nm_img.is_empty():
		return null
	return ImageTexture.create_from_image(nm_img)


## Alpha of the source pixel feeding half-res cell (x, y).
static func _half_alpha(data: PackedByteArray, w: int, h: int, x: int, y: int) -> int:
	var sx := mini(x * 2, w - 1)
	var sy := mini(y * 2, h - 1)
	return data[(sy * w + sx) * 4 + 3]
