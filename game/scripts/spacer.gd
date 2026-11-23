## A spacer: someone who lives and works aboard a trading outpost (outpost.gd `folk_plan`; space.gd keeps them in
## `folk`, ticks them while you're near and draws them). They live in the outpost's own cells (`b`: the middle of
## the body, +y toward its floors), walk its decks under its gravity, potter about their room, now and then cross
## through a doorway into the next room of their deck (never up a hatch), stand a while, and talk when you press
## F beside them (space.gd `_folk_talk`: `say` for `say_t` ticks). Their picture is folk_art.gd's, by their seed.
extends RefCounted

const HW := 3.5
const HH := 9.5
const G := 0.17
const SPEED := 0.55

var op                      # the outpost
var fseed := 0
var name := ""
var b := Vector2.ZERO
var v := Vector2.ZERO
var room := -1
var goal := 0.0
var wait := 0
var facing := 1
var anim := 0.0
var on_ground := false
var stuck := 0
var say := ""
var say_t := 0
var talked := 0             # (how often you've talked to them: what they say moves on)
var _frames := {}
var _rng := RandomNumberGenerator.new()

static func make(outpost, plan: Dictionary):
	var f = load("res://scripts/spacer.gd").new()
	f.op = outpost
	f.fseed = int(plan["fseed"])
	f.room = int(plan["room"])
	f.b = plan["b"]
	f.goal = f.b.x
	f.name = load("res://scripts/folk_art.gd").name_for(f.fseed)
	f._rng.seed = f.fseed
	f.wait = f._rng.randi_range(0, 200)
	return f

func world() -> Vector2:
	return op.to_world(b - op.com)

## one tick: walk toward the goal on its deck, wait, choose again
func tick() -> void:
	if say_t > 0:
		say_t -= 1
	anim += absf(v.x) * 0.13
	if wait > 0:
		wait -= 1
		v.x *= 0.6
		if wait == 0:
			_choose()
	else:
		var dx := goal - b.x
		if absf(dx) < 1.5:
			wait = _rng.randi_range(90, 320)
			v.x = 0.0
		else:
			v.x += (signf(dx) * SPEED - v.x) * 0.25
			facing = 1 if dx > 0.0 else -1
	if say_t > 0:
		v.x = 0.0                       # (they stop to talk)
	v.y = minf(v.y + G, 5.0)
	var was := b.x
	var r: Array = op.move_box(b, v, HW, HH, true, 5 if on_ground else 0, false)
	b = r[0]
	v = r[1]
	on_ground = r[2]
	if wait == 0 and absf(b.x - was) < 0.05:
		stuck += 1
		if stuck > 60:
			stuck = 0
			_choose(true)
	else:
		stuck = 0
	var k: int = op.module_at(b)
	if k >= 0:
		room = k

## where next: somewhere else in this room, or (now and then) the next room along its deck
func _choose(stay := false) -> void:
	var md: Dictionary = op.mods[room]
	var to := room
	var links: Array = op.walk_links(room)
	if not stay and not links.is_empty() and _rng.randf() < 0.35:
		to = int(links[_rng.randi_range(0, links.size() - 1)])
	var tm: Dictionary = op.mods[to]
	goal = float(_rng.randi_range(int(tm["x0"]) + 8, int(tm["x1"]) - 8))
	if to == room and absf(goal - b.x) < 6.0:
		goal = clampf(b.x + (12.0 if goal < float(int(md["x0"]) + int(md["x1"])) * 0.5 else -12.0), float(int(md["x0"]) + 6), float(int(md["x1"]) - 6))

## someone stands on top of them: they step aside (a little way along the room, the way `dir` says)
func step_aside(dir: int) -> void:
	var md: Dictionary = op.mods[room]
	goal = clampf(b.x + float(dir) * float(_rng.randi_range(12, 22)), float(int(md["x0"]) + 6), float(int(md["x1"]) - 6))
	wait = 0

func texture() -> ImageTexture:
	var fr := "stand"
	if absf(v.x) > 0.1:
		fr = "walk0" if int(anim * 0.5) % 2 == 0 else "walk1"
	if not _frames.has(fr):
		var imgs: Dictionary = load("res://scripts/folk_art.gd").frames(fseed, "")
		for kf in imgs:
			_frames[kf] = ImageTexture.create_from_image(imgs[kf])
	return _frames[fr]
