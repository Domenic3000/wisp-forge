@echo off
cd /d "%~dp0"
set "GODOT="
for %%f in ("engine\Godot_v4*_win64.exe") do set "GODOT=%%~ff"
if not defined GODOT (
  echo Could not find Godot in the "engine" folder.
  echo Download Godot 4 for Windows from https://godotengine.org/download/windows
  echo and unzip both .exe files into: %~dp0engine
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0game"
