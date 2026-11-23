## An ancient monolith (user, 23 Nov: space creatures and anomalies, each with a secret): a tall slab of
## warded stone hanging in deep space, its face carved with glyphs. Strike each glyph with the Wisp Cannon,
## or put your staff to it on foot (hold dig), and it burns with void-light; but they wake only from the
## root up (the next one pulses faintly), and a lit glyph slowly dies away. Light them all and the seal on
## its alcove crumbles: inside, a cache (space.gd `_loot` "monolith": void essence, star iron, coins, a
## whisper of lore and the place of a rift pair you haven't found).
##
## It extends wreck.gd for its cache, so space.gd streams it, collides with it and draws it like a wreck;
## every cell is `guarded` (nothing digs or blasts it). Never saved as a rock: grown again by seed, its
## state (opened, looted) in voidlife.gd `mono_state`.
extends "res://scripts/wreck.gd"

const MW := 46                 # the grid (cells)
const MH := 172
const GLYPH_W := 9
const GLYPH_H := 11
const ALCOVE := Rect2i(6, 88, 26, 30)   # the alcove (x, y, w, h); its seal the first SEAL columns
const SEAL := 5
const FADE := 1500             # ticks a lit glyph burns before it dies away
## glyph designs: "#" carved
const RUNES := [
	["....#....", "...###...", "..#.#.#..", ".#..#..#.", "#...#...#", "....#....", "...#.#...", "..#...#..", ".#.....#.", "#.......#", "#########"],
	["#########", "#.......#", "#.#####.#", "#.#...#.#", "#.#.#.#.#", "#.#...#.#", "#.#####.#", "#.......#", "#########", "....#....", "...###..."],
	["....#....", "...#.#...", "..#...#..", ".#.....#.", "#...#...#", ".#.....#.", "..#...#..", "...#.#...", "....#....", "....#....", "..#####.."],
	["#.......#", ".#.....#.", "..#...#..", "...#.#...", "....#....", "#########", "....#....", "...#.#...", "..#...#..", ".#.....#.", "#.......#"],
	["..#####..", ".#.....#.", "#...#...#", "#..###..#", "#...#...#", ".#.....#.", "..#####..", "....#....", "..#.#.#..", "...###...", "....#...."],
	["#...#...#", ".#..#..#.", "..#.#.#..", "...###...", "#########", "...###...", "..#.#.#..", ".#..#..#.", "#...#...#", ".........", "#########"],
	["...###...", "..#...#..", "..#...#..", "...###...", "....#....", ".#######.", "....#....", "...#.#...", "..#...#..", "..#...#..", "..##.##.."],
	["#########", "....#....", "...#.#...", "..#...#..", ".#.....#.", "#########", ".#.....#.", "..#...#..", "...#.#...", "....#....", "#########"],
]
const LORE := ["Before the stars, the Void sang. We carved its song in stone so it would not be forgotten.",
	"The tears in the dark are doors. Those who made them are gone; the doors remain.",
	"Where the light bends and falls inward, our first city sank out of the world.",
	"The mantas are the Void dreaming. Do not wake them in anger.",
	"Each stone points to the next. Follow them, and you will find the way we went.",
	"We were wisps once, as you are. We learned to burn without a body."]

var glyphs := []               # [{"c": Vector2i (top-left cell), "cells": PackedInt32Array, "lit": ticks left (0 dark)}], root first
var opened := false            # the seal has crumbled
var lore := ""
var _hint_at := 0

static func make_monolith(sd: int) -> RefCounted:
	var mo = load("res://scripts/monolith.gd").new()
	mo._grow_mono(sd)
	return mo

func _grow_mono(sd: int) -> void:
	seed_ = sd
	kind = "monolith"
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	wname = "the monolith"
	lore = LORE[rng.randi_range(0, LORE.size() - 1)]
	fate = lore
	setup(MW, MH)
	var noise := FastNoiseLite.new()
	noise.seed = sd
	noise.frequency = 0.21
	# the slab: warded stone, a pyramidion at its top, a stepped plinth at its root
	for j in MH:
		for i in MW:
			var x0 := 6
			var x1 := MW - 6
			if j < 20:
				var f := float(j) / 20.0
				x0 = int(lerpf(float(MW) * 0.5 - 1.0, 6.0, f))
				x1 = MW - x0
			elif j >= MH - 16:
				x0 = 2 if j >= MH - 8 else 4
				x1 = MW - x0
			if i < x0 or i >= x1:
				continue
			var edge := i == x0 or i == x1 - 1 or j == MH - 1 or j == MH - 9 or j == MH - 17
			var v := 0 if edge else (2 if noise.get_noise_2d(i, j) > 0.25 else (1 if (i + j * 3) % 11 == 0 else 3))
			put(i, j, Defs.OBSIDIAN if edge else Defs.RUNESTONE, v)
	# a weathered seam down its face, chips at the edges
	for j in range(24, MH - 18):
		if noise.get_noise_2d(j * 3.0, 9.0) > 0.45:
			var ci := 6 if noise.get_noise_2d(j * 2.0, 1.0) > 0.0 else MW - 7
			put(ci, j, 0, 0)
	# the alcove, behind its seal: a back wall of dark stone, a crate on its floor
	var ax := ALCOVE.position.x
	var ay := ALCOVE.position.y
	for j in range(ay, ay + ALCOVE.size.y):
		for i in range(ax, ax + ALCOVE.size.x):
			var k := j * w + i
			bg[k] = Defs.OBSIDIAN
			bgv[k] = 1 if (i + j) % 7 == 0 else 2
			if i < ax + SEAL:
				put(i, j, Defs.OBSIDIAN, 0 if (j - ay) % 6 == 0 else 2)    # (the seal: courses of black glass)
			else:
				cells[k] = 0
	# runes round the seal, glowing faintly
	for i in range(ax, ax + SEAL + 2, 2):
		put(i, ay - 2, Defs.CRYSTAL, 1)
		put(i, ay + ALCOVE.size.y + 1, Defs.CRYSTAL, 1)
	_crate(ax + SEAL + 7, ay + ALCOVE.size.y, "monolith")
	# the glyphs, root first: two under the alcove, three over it
	var ys := [MH - 16 - GLYPH_H - 6, ay + ALCOVE.size.y + 8, ay - GLYPH_H - 8, ay - 2 * GLYPH_H - 18, 26]
	var order := range(RUNES.size())
	for k2 in order.size():
		var sw: int = rng.randi_range(k2, order.size() - 1)
		var tmp = order[k2]
		order[k2] = order[sw]
		order[sw] = tmp
	for gi in ys.size():
		var gx := (MW - GLYPH_W) / 2
		var gy := int(ys[gi])
		var rune: Array = RUNES[int(order[gi])]
		var cs := PackedInt32Array()
		for j2 in GLYPH_H:
			var row: String = rune[j2]
			for i2 in GLYPH_W:
				if row[i2] == "#":
					var kk := (gy + j2) * w + gx + i2
					if cells[kk] != 0:
						cells[kk] = Defs.OBSIDIAN
						vars[kk] = 3
						cs.append(kk)
		glyphs.append({"c": Vector2i(gx, gy), "cells": cs, "lit": 0})
	rebuild()
	rad = float(MH) * 0.5
	ang = rng.randf() * TAU
	omega = 0.0
	dirty = true
	_bg_dirty = true

## nothing of it is ever dug or blasted away
func guarded(_k: int) -> bool:
	return true

## the next glyph to wake (from the root up), or -1 once all burn
func next_glyph() -> int:
	for k in glyphs.size():
		if int(glyphs[k]["lit"]) <= 0:
			return k
	return -1

## the world point at glyph k's middle
func glyph_pos(k: int) -> Vector2:
	var c: Vector2i = glyphs[k]["c"]
	return to_world(Vector2(float(c.x) + GLYPH_W * 0.5, float(c.y) + GLYPH_H * 0.5) - com)

## the glyph nearest p within `within` cells, or -1
func glyph_at(p: Vector2, within := 16.0) -> int:
	var best := -1
	var bd := within
	for k in glyphs.size():
		var d := glyph_pos(k).distance_to(p)
		if d < bd:
			bd = d
			best = k
	return best

## A glyph struck: "lit" (it wakes), "early" (not its turn: it sputters), "burning" (already lit), "open"
## (it was the last: the seal crumbles), "" (no glyph there, or it's open already).
func strike(k: int) -> String:
	if opened or k < 0:
		return ""
	if int(glyphs[k]["lit"]) > 0:
		return "burning"
	if k != next_glyph():
		return "early"
	glyphs[k]["lit"] = FADE
	_paint_glyph(k, true)
	if next_glyph() < 0:
		open_seal()
		return "open"
	return "lit"

## a tick: lit glyphs burn down, and die away (a while after the last of them was struck)
func tick_glyphs() -> void:
	if opened:
		return
	for k in glyphs.size():
		var t := int(glyphs[k]["lit"])
		if t > 0:
			glyphs[k]["lit"] = t - 1
			if t == 1:
				_paint_glyph(k, false)

func _paint_glyph(k: int, on: bool) -> void:
	for kk in glyphs[k]["cells"]:
		cells[kk] = Defs.VOIDESS if on else Defs.OBSIDIAN
		vars[kk] = (kk % 3) if on else 3
	dirty = true

## the seal crumbles: its cells go (and every glyph burns on for good)
func open_seal() -> Array:
	opened = true
	var gone := []
	for j in range(ALCOVE.position.y, ALCOVE.position.y + ALCOVE.size.y):
		for i in range(ALCOVE.position.x, ALCOVE.position.x + SEAL):
			var k := j * w + i
			if cells[k] != 0:
				gone.append(Vector2i(i, j))
				cells[k] = 0
	for k2 in glyphs.size():
		glyphs[k2]["lit"] = 999999
		for kk in glyphs[k2]["cells"]:
			cells[kk] = Defs.VOIDESS
	# (its cells stay where they were: the middle of its mass moves, so it does)
	var c0 := com
	rebuild()
	pos += axis_x() * (com - c0).x + axis_y() * (com - c0).y
	dirty = true
	return gone

## (its state, kept by voidlife.gd: opened, the cache looted)
func state() -> Dictionary:
	return {"open": opened, "looted": caches.size() > 0 and bool(caches[0]["open"])}

func apply_state(st: Dictionary) -> void:
	if bool(st.get("open", false)) and not opened:
		open_seal()
	if bool(st.get("looted", false)) and not caches.is_empty() and not caches[0]["open"]:
		open_cache(caches[0])
