@echo off
rem Opens the project in the Godot editor.
cd /d "%~dp0"
set "GODOT="
for %%f in ("engine\Godot_v4*_win64.exe") do set "GODOT=%%~ff"
if not defined GODOT (
  echo Could not find Godot in the "engine" folder.
  pause
  exit /b 1
)
start "" "%GODOT%" -e --path "%~dp0game"
