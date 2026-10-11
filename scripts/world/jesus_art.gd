class_name JesusArt
extends RefCounted
## Cursing Gnomes — Jesus disaster sprite.
##
## Jeremy 2026-10-04: real chibi pixel-art for the Jesus disaster, replacing
## the flat procedural polygons. Hand-authored 32x46 pixels (AI image
## generation declined the request, so the pixels were drawn by hand):
## long brown hair, beard, off-white robe with sash, sawn-off shotgun held
## across the body, cigarette with ember + drifting smoke wisp, gold halo.
## Two frames = walk cycle (1px bob, swapped feet, hem sway, smoke drift,
## ember flicker). Embedded as base64 PNG so no asset-import pipeline is
## needed — decodes at runtime into an hframes=2 strip for the UnitNode.

const FRAME_W := 32
const FRAME_H := 46
const FRAME_COUNT := 2

const _FRAME_A := "iVBORw0KGgoAAAANSUhEUgAAACAAAAAuCAYAAABJcBuEAAACoUlEQVR4nO2YPWhTURiG34QOUkpxCKEkS0wRrJQOzdjBLLWVpqWDWHExg4sOBixdrKsuBcUKnTpkCrW0UIo/TesQheJ0r0GCKGKaDr1IyCCliINYB3su9+aen+809zaCvtPJOd/9znO/vOcnCUFDsWjkkBJn1Rshak5lYPOke6Ub0vh4elELhgSQ6P6lCuOqth9WAnRQEiV7urn91a/7ZBjDMBZSqdSt5v4wOUOL4k0OECug86Y8id4eUHiAGbAVDwByIyor4Jx8a+kxaeLhqzn7WQbx13rgWAB9mWn0ZaY9n63aLqzarifeMIwFUa4TqcD4pZGbojGlCZ0e6DrVgejpTldM/dt3z3MHP37a7e3FUcSvbAqN6HsFVt9+stvFd1+AF2+k8doVoMhZAdVSPBEPtLQPOFWp/6lGf5TPzcYT/KODK60KVMwiKmZROr7+lLZZMSkr8Ky0hUx62NW3tPFSaxKZAvUAM6BMylVQMYtYy88BAJJn4hi4cE2asPr5o92emMr5cyGZzM4AwBFIQQmhI62vYDI7g+rOHt6/LrQHIAgILkAsGjmUXcF1IFguUb5QczBry9Y701p+jmRMAOgfHLHbTmN6AC6nIp6Hw71p3M8OAQBm89vSiVRxy8srLgDSKjDNMnCU2DTL8mBqnAhgxWgAgGtLLc8+ISU7jribBPMCzwebG89xcXSMm4x5ois2aPdNTOU8ccqvwKo3QtQfok519pxHdecDkoALQrYb+n4WsCV6YJmk+EAOo4GhcReErJqBnYYMovDouhRCuBMGAUEGAGg7oUjJs+c8ENoAfure/Kv2AgBtvpbL9B/g3wEg3YicwQ8f3PYV4M7dee5KkB7HzcqmE3Y7X6qRx5h4AMLjmALF4mRjKpH/VA4K4DfPOCh7K1k0GQAAAABJRU5ErkJggg=="
const _FRAME_B := "iVBORw0KGgoAAAANSUhEUgAAACAAAAAuCAYAAABJcBuEAAACi0lEQVR4nO1YP0gbURz+EhwkiHQ4DrksaUqhFclgxoBmaGtpa5FSqHRphk4dFFpcdK1dxJZacbHDTcGKBSktNS0FO0inXIOE/qE0ZlEkOEiQ4iBeB33n3eX9u/OSW/wg8N697/3ed9/93u9dLgIBNFUx7f3N1Ydcfjz72tHfqu1EeHzuIBGQ6DwU0aio1qNCAW0ygZJdndTrle26D1lORE8dQQLFYnGONRb6I+A64E5APyAxWC5w1bnv/vPCS6lFrw6PWm2RC6HngNQucOPyrScAgJ/vpx39L7MjVH46nX7EitUSBzRVMQPJgY72NqjnYg5Obfdfw7y9/QOrvXYnhri+z8yDwB14++231S58/wvc6OPyPTsgA7sD1frRPbbMARp429DTLijXjtzoUem6yXiCfnRQ4cmBslFA2ShIj8/MvxLG9FUHFlY++plGhdABkkTNgtRp+HTkCgAgeT6OVP99YdDKn19W+/a90dMn4VBuDACwrE8ByEuJkIUnf4dyY6hsbGL9az4cAc0QQRWgqYpJfkGI4MWKuImkzdvvBMv6lHRi9vQOWG17UjYIuJtWGiZHL2QxmcsAACb0Ne5CIt7i4pJDgNQuMIwScBzYMEp8siyPJWCpuAMAePfm5P2vNCEuqX5BLRC8XPi08gHXrt+kBrPnhLsY2SF8BITg9bU81tWNysYPAHl0aL3MRe0IvNCTLbq3ZUjxm3LSeBHRtKMulRl0iGA9TqaAIP6WERH5Fw+YHK4DMtWQheTFSw4RvgQEhVRmMFwBPJwJOBPQUgG02sJ8XdZUxXz+jP7BwS8ej880HEpcAYGufgxpATRoqmLmsgmrr69WAQDua6JPc3aEnoSeHZDheXHgP4yJEDcj+uwQAAAAAElFTkSuQmCC"


## Decoded 64x46 strip (frames side by side), nearest-filtered by the
## project's default canvas texture filter (project.godot:
## default_texture_filter=0) so pixels stay crisp.
static func make_texture() -> Texture2D:
	var strip := Image.create(FRAME_W * FRAME_COUNT, FRAME_H, false,
		Image.FORMAT_RGBA8)
	var blobs := [_FRAME_A, _FRAME_B]
	for i in FRAME_COUNT:
		var raw: PackedByteArray = Marshalls.base64_to_raw(blobs[i])
		var img := Image.new()
		var err: Error = img.load_png_from_buffer(raw)
		if err != OK or img == null:
			push_error("JesusArt: failed to decode frame %d" % i)
			return null
		img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, Rect2i(0, 0, FRAME_W, FRAME_H),
			Vector2i(i * FRAME_W, 0))
	return ImageTexture.create_from_image(strip)
