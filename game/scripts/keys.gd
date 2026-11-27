extends RefCounted
## The keys you can rebind (27 Nov; user: "ok do you want to create a real setting menu now", chose rebindable keys
## among the rest). Every action has up to two keys; main.gd keeps the map (`keymap`, saved in settings.json as
## "keys") and asks `key_is(keycode, action)` for a key pressed and `key_held(action)` for one held. The arrow keys
## always move as well (left, right, up = jump, down), unless you bind one of them to something else. Esc, F11, the
## spell keys 1-9 and the developer keys (F3, F7-F9) are fixed. The mouse buttons are fixed.

## [id, what it does, group, default keys]
const ACTIONS := [
	["left", "Walk left", "Moving", [KEY_A]],
	["right", "Walk right", "Moving", [KEY_D]],
	["jump", "Jump, levitate, fly up", "Moving", [KEY_SPACE, KEY_W]],
	["down", "Drop through, fly down", "Moving", [KEY_S]],
	["starsail", "Starsail (hold, in space)", "Moving", [KEY_SHIFT]],
	["interact", "Use, talk, open, board", "Doing", [KEY_F]],
	["f_next", "Next thing in reach for F", "Doing", [KEY_Z]],
	["drink", "Drink a Healing Draught", "Doing", [KEY_H]],
	["mend", "Mend the hull (hold)", "Doing", [KEY_R]],
	["call_ship", "Call your ship", "Doing", [KEY_K]],
	["below", "Below decks, out by your ship", "Doing", [KEY_G]],
	["belt_prev", "Item belt back (space: turn left)", "Hand and building", [KEY_Q]],
	["belt_next", "Item belt on (space: turn right)", "Hand and building", [KEY_E]],
	["shape", "Shape: line, rectangle, frame", "Hand and building", [KEY_G]],
	["layer", "Front or back wall; what Unmake takes", "Hand and building", [KEY_V]],
	["thinner", "Thinner (stairs: lower)", "Hand and building", [KEY_BRACKETLEFT]],
	["thicker", "Thicker (stairs: higher)", "Hand and building", [KEY_BRACKETRIGHT]],
	["next_design", "Next design; level the ground", "Hand and building", [KEY_R]],
	["mirror", "Mirror, turn", "Hand and building", [KEY_T]],
	["plans", "Plans", "Hand and building", [KEY_B]],
	["zoom_out", "Zoom out (space, the map)", "Hand and building", [KEY_MINUS, KEY_KP_SUBTRACT]],
	["zoom_in", "Zoom in (space, the map)", "Hand and building", [KEY_EQUAL, KEY_KP_ADD]],
	["satchel", "Satchel", "Menus", [KEY_I, KEY_TAB]],
	["map", "Map", "Menus", [KEY_M]],
	["forge", "The Wisp Forge", "Menus", [KEY_C]],
	["book", "Recipe book", "Menus", [KEY_J]],
	["journal", "Journal", "Menus", [KEY_L]],
	["minimap", "Minimap on or off", "Menus", [KEY_N]],
]

## keys that can't be bound (they do one thing everywhere)
const FIXED := [KEY_ESCAPE, KEY_F11, KEY_F3, KEY_F7, KEY_F8, KEY_F9, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7,
	KEY_8, KEY_9, KEY_BACKSPACE, KEY_DELETE]

## the arrow key that also does each moving action
const ARROWS := {"left": KEY_LEFT, "right": KEY_RIGHT, "jump": KEY_UP, "down": KEY_DOWN}

static func defaults() -> Dictionary:
	var d := {}
	for a in ACTIONS:
		d[a[0]] = (a[3] as Array).duplicate()
	return d

## a key map read back from settings.json (numbers come back as floats; unknown actions dropped, new ones default)
static func from_saved(v) -> Dictionary:
	var d := defaults()
	if typeof(v) != TYPE_DICTIONARY:
		return d
	for id in d:
		if (v as Dictionary).has(id) and typeof(v[id]) == TYPE_ARRAY:
			var ks := []
			for kc in v[id]:
				if int(kc) > 0 and ks.size() < 2:
					ks.append(int(kc))
			d[id] = ks
	return d

static func label_of(id: String) -> String:
	for a in ACTIONS:
		if a[0] == id:
			return String(a[1])
	return id

## a key's name as the menus show it
const NAMES := {KEY_SPACE: "Space", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_MINUS: "-", KEY_EQUAL: "=",
	KEY_KP_SUBTRACT: "Num -", KEY_KP_ADD: "Num +", KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_TAB: "Tab",
	KEY_ENTER: "Enter", KEY_LEFT: "Left", KEY_RIGHT: "Right", KEY_UP: "Up", KEY_DOWN: "Down"}

static func key_name(kc: int) -> String:
	if NAMES.has(kc):
		return String(NAMES[kc])
	var s := OS.get_keycode_string(kc)
	return s if s != "" else "?"
