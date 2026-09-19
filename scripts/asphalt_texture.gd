class_name AsphaltTexture
extends RefCounted
## Procedural asphalt: one small tileable greyscale-ish image, generated from
## hash noise. The same seed always gives the same pixels; nothing is random
## at run time and nothing is imported.
##
## The image is a brightness map around ~0.8 that the ground material
## multiplies with its albedo colour. Layers, coarse to fine:
##   * blotches: a few octaves of tileable value noise (worn / fresh areas),
##   * a faint warm / cool tint drifting across the tile,
##   * grain: per-pixel noise (the aggregate),
##   * specks: sparse pale stones and dark pits (the "mini dots"),
##   * cracks: a few dark wandering hairlines (the "wrinkles").

const BASE_BRIGHTNESS := 0.78
const BLOTCH_STRENGTH := 0.2  # Peak-to-peak brightness swing of the blotches.
const BLOTCH_OCTAVES: Array[int] = [3, 6, 12]  # Noise cells across the tile.
const BLOTCH_WEIGHTS: Array[float] = [0.5, 0.3, 0.2]
const TINT_STRENGTH := 0.035  # Blue channel drift, warm <-> cool.
const GRAIN_STRENGTH := 0.16  # Peak-to-peak per-pixel noise.
const PALE_SPECK_CHANCE := 0.012
const PALE_SPECK_BOOST := 0.2
const DARK_SPECK_CHANCE := 0.01
const DARK_SPECK_DROP := 0.18
const CRACK_COUNT := 6
const CRACK_STEPS := 140  # Length of each crack [px].
const CRACK_DARKEN := 0.72  # Brightness multiplier on a crack pixel.


## Builds the `size` x `size` RGB8 image (with mipmaps) for `noise_seed`.
static func build_image(size: int, noise_seed: int) -> Image:
	var blotch_tables: Array[PackedFloat32Array] = []
	for octave in BLOTCH_OCTAVES.size():
		blotch_tables.append(_lattice(BLOTCH_OCTAVES[octave], noise_seed + 11 * (octave + 1)))
	var tint_cells := 4
	var tint_table := _lattice(tint_cells, noise_seed + 97)

	# Cracks first, as a mask, so they can wrap around the tile edges.
	var crack_mask := PackedByteArray()
	crack_mask.resize(size * size)
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	for crack in CRACK_COUNT:
		var x := rng.randf() * size
		var y := rng.randf() * size
		var heading := rng.randf() * TAU
		for step in CRACK_STEPS:
			crack_mask[posmod(int(y), size) * size + posmod(int(x), size)] = 1
			heading += rng.randf_range(-0.28, 0.28)
			x += cos(heading)
			y += sin(heading)

	var data := PackedByteArray()
	data.resize(size * size * 3)
	for py in size:
		var v := float(py) / size
		for px in size:
			var u := float(px) / size
			var blotch := 0.0
			for octave in BLOTCH_OCTAVES.size():
				blotch += BLOTCH_WEIGHTS[octave] * _sample(blotch_tables[octave], BLOTCH_OCTAVES[octave], u, v)
			var brightness := BASE_BRIGHTNESS + BLOTCH_STRENGTH * (blotch - 0.5)
			brightness += GRAIN_STRENGTH * (_hash(px, py, noise_seed) - 0.5)
			var speck := _hash(px, py, noise_seed + 1)
			if speck < PALE_SPECK_CHANCE:
				brightness += PALE_SPECK_BOOST
			elif speck > 1.0 - DARK_SPECK_CHANCE:
				brightness -= DARK_SPECK_DROP
			if crack_mask[py * size + px] == 1:
				brightness *= CRACK_DARKEN
			var tint := TINT_STRENGTH * (_sample(tint_table, tint_cells, u, v) - 0.5) * 2.0
			var offset := (py * size + px) * 3
			data[offset] = int(clampf(brightness - tint, 0.0, 1.0) * 255.0)
			data[offset + 1] = int(clampf(brightness, 0.0, 1.0) * 255.0)
			data[offset + 2] = int(clampf(brightness + tint, 0.0, 1.0) * 255.0)

	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)
	image.generate_mipmaps()
	return image


## `cells` x `cells` table of random values, 0..1.
static func _lattice(cells: int, table_seed: int) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(cells * cells)
	for y in cells:
		for x in cells:
			table[y * cells + x] = _hash(x, y, table_seed)
	return table


## Smoothly interpolated, wrapping lookup into a lattice at tile coords 0..1.
static func _sample(table: PackedFloat32Array, cells: int, u: float, v: float) -> float:
	var fx := u * cells
	var fy := v * cells
	var x0 := int(fx) % cells
	var y0 := int(fy) % cells
	var x1 := (x0 + 1) % cells
	var y1 := (y0 + 1) % cells
	var tx := smoothstep(0.0, 1.0, fx - floorf(fx))
	var ty := smoothstep(0.0, 1.0, fy - floorf(fy))
	var top := lerpf(table[y0 * cells + x0], table[y0 * cells + x1], tx)
	var bottom := lerpf(table[y1 * cells + x0], table[y1 * cells + x1], tx)
	return lerpf(top, bottom, ty)


## Integer hash of a pixel / cell coordinate, 0..1.
static func _hash(x: int, y: int, hash_seed: int) -> float:
	var h := (x * 374761393 + y * 668265263 + hash_seed * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967295.0
