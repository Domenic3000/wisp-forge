@echo off
rem Runs the game with a console window that shows any errors.
cd /d "%~dp0"
set "GODOT="
for %%f in ("engine\Godot_v4*_console.exe") do set "GODOT=%%~ff"
if not defined GODOT (
  echo Could not find the Godot console exe in the "engine" folder.
  pause
  exit /b 1
)
"%GODOT%" --path "%~dp0game"
echo.
echo Game closed.
pause
