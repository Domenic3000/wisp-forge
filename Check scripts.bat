@echo off
cd /d "%~dp0"
for %%E in (engine\Godot_v4*_console.exe) do set GODOT=%%E
echo checking > saves\check.txt
for %%S in (defs gpu_world buildings tests main ui overlay title_screen audio mage_rig props build foe_ai chunks pixel_body skiff asteroid space boss_art boss_ai) do (
  echo ==== %%S >> saves\check.txt
  "%GODOT%" --headless --path game --check-only --script res://scripts/%%S.gd >> saves\check.txt 2>&1
)
