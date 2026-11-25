## Loaded before everything else (an autoload), and kept tiny so it never breaks: in the test mode
## (`--test`) it quits the game if the main scene never comes up (a parse error in main.gd would
## otherwise leave a blank window open for good) or if the whole run goes on past 23 minutes.
extends Node

var _t0 := 0
var _on := false

func _ready() -> void:
	_on = OS.get_cmdline_user_args().has("--test")
	_t0 = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not _on:
		return
	var t := float(Time.get_ticks_msec() - _t0) / 1000.0
	var cs := get_tree().current_scene
	if t > 8.0 and (cs == null or cs.get_script() == null or not cs.has_method("_make_world")):
		printerr("SCRIPT ERROR: the main scene didn't load (a script failed to parse?); the test run stops")
		get_tree().quit(1)
		_on = false
	elif t > 25.0 and not bool(cs.get("booted")):
		# (main.gd came up but its _ready stopped short: a script it preloads failed to compile)
		printerr("SCRIPT ERROR: the main scene stopped while starting (a preloaded script failed?); the test run stops")
		get_tree().quit(1)
		_on = false
	elif t > 1380.0:
		printerr("SCRIPT ERROR: the test run went on past 23 minutes; stopped")
		get_tree().quit(1)
		_on = false
