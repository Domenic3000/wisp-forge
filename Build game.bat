@echo off
rem Builds Wisp Forge into a game anyone can play: build\Wisp Forge\Wisp Forge.exe (with its music
rem folder beside it) and build\Wisp Forge.zip to share. Saves go to %APPDATA%\Wisp Forge\saves.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
if not exist build mkdir build
set "LOG=%~dp0build\build_log.txt"
echo Wisp Forge build %DATE% %TIME% > "%LOG%"

rem ---- the engine (the console build, so the export's messages go to the log) ----
set "GODOT="
for %%f in ("engine\Godot_v4*_win64_console.exe") do set "GODOT=%%~ff"
if not defined GODOT (
  echo Could not find Godot's console .exe in the "engine" folder.>> "%LOG%"
  echo Could not find Godot's console .exe in the "engine" folder.
  echo Unzip both Godot .exe files into: %~dp0engine
  pause
  exit /b 1
)

rem ---- its version, e.g. 4.7.2.stable.official.ed1daf0bf -> templates 4.7.2.stable, release 4.7.2-stable ----
for /f "delims=" %%v in ('"%GODOT%" --version 2^>nul') do set "GVER=%%v"
for /f "tokens=1-4 delims=." %%a in ("%GVER%") do (
  set "A=%%a" & set "B=%%b" & set "C=%%c" & set "D=%%d"
)
set "TVER=%A%.%B%.%C%.%D%"
set "REL=%A%.%B%.%C%-%D%"
echo %C%| findstr /r "^[0-9][0-9]*$" >nul || (
  set "TVER=%A%.%B%.%C%"
  set "REL=%A%.%B%-%C%"
)
echo Engine %GVER%: templates %TVER%>> "%LOG%"
echo Godot %GVER%

rem ---- Godot's export templates (once per engine version, about 1 GB to download) ----
set "TDIR=%APPDATA%\Godot\export_templates\%TVER%"
if not exist "%TDIR%\windows_release_x86_64.exe" (
  echo.
  echo Godot's export templates for %TVER% aren't installed yet. They are what a game is built from:
  echo   https://github.com/godotengine/godot/releases/download/%REL%/Godot_v%REL%_export_templates.tpz
  echo about 1 GB, downloaded once into %TDIR%
  echo.
  rem (a file build\get_templates.txt says yes ahead of time, for a build started unattended)
  set "ANSWER=2"
  if exist "%~dp0build\get_templates.txt" (
    set "ANSWER=1"
    del "%~dp0build\get_templates.txt"
  ) else (
    choice /c YN /t 30 /d N /m "Download them now"
    set "ANSWER=!errorlevel!"
  )
  if "!ANSWER!"=="2" (
    echo Templates missing and not downloaded: nothing built.>> "%LOG%"
    echo Nothing built. Run this again and press Y to download the templates.
    pause
    exit /b 1
  )
  echo Downloading the templates...>> "%LOG%"
  curl -L --fail -o "%TEMP%\wf_templates.tpz" "https://github.com/godotengine/godot/releases/download/%REL%/Godot_v%REL%_export_templates.tpz"
  if errorlevel 1 (
    echo The download failed.>> "%LOG%"
    echo The download failed. Check the connection and try again.
    pause
    exit /b 1
  )
  if exist "%TEMP%\wf_templates" rmdir /s /q "%TEMP%\wf_templates"
  mkdir "%TEMP%\wf_templates"
  tar -xf "%TEMP%\wf_templates.tpz" -C "%TEMP%\wf_templates"
  if not exist "%TDIR%" mkdir "%TDIR%"
  xcopy /e /i /y /q "%TEMP%\wf_templates\templates\*" "%TDIR%\" >nul
  rmdir /s /q "%TEMP%\wf_templates"
  del "%TEMP%\wf_templates.tpz"
  if not exist "%TDIR%\windows_release_x86_64.exe" (
    echo The templates didn't unpack where they should.>> "%LOG%"
    echo The templates didn't unpack where they should: %TDIR%
    pause
    exit /b 1
  )
  echo Templates installed.>> "%LOG%"
)

rem ---- the Windows template with the audio fix (game\export_presets.cfg uses it): Godot's own, with its
rem low-latency WASAPI mode turned off, which crackled on USB audio interfaces (docs\release.md, tools\wasapi_patch.py) ----
if not exist "%~dp0engine\windows_release_x86_64_wasapi.exe" (
  echo engine\windows_release_x86_64_wasapi.exe is missing: nothing built.>> "%LOG%"
  echo engine\windows_release_x86_64_wasapi.exe is missing. It is Godot's windows_release_x86_64.exe with the audio fix:
  echo   python tools\wasapi_patch.py "%TDIR%\windows_release_x86_64.exe" engine\windows_release_x86_64_wasapi.exe 0
  pause
  exit /b 1
)
echo Template: engine\windows_release_x86_64_wasapi.exe (the audio fix)>> "%LOG%"

rem ---- export: one .exe with the game packed inside it ----
set "OUT=%~dp0build\Wisp Forge"
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
echo Building the game (the first time Godot also imports the project, a minute or so)...
echo Exporting...>> "%LOG%"
"%GODOT%" --headless --path "%~dp0game" --export-release "Windows Desktop" "%OUT%\Wisp Forge.exe" >> "%LOG%" 2>&1
if not exist "%OUT%\Wisp Forge.exe" (
  echo The export failed: see build\build_log.txt>> "%LOG%"
  echo The export failed: see build\build_log.txt
  pause
  exit /b 1
)

rem ---- the music, as plain files beside the .exe (swap a track by replacing its file) ----
mkdir "%OUT%\music"
robocopy "%~dp0game\audio\music" "%OUT%\music" *.mp3 *.ogg /NFL /NDL /NJH /NJS /NP >nul
(
  echo Wisp Forge
  echo.
  echo Double-click "Wisp Forge.exe" to play. Keep the "music" folder beside it.
  echo Your journeys are saved in %%APPDATA%%\Wisp Forge\saves
) > "%OUT%\README.txt"

rem ---- a zip to share ----
if exist "%~dp0build\Wisp Forge.zip" del "%~dp0build\Wisp Forge.zip"
tar -a -c -f "%~dp0build\Wisp Forge.zip" -C "%~dp0build" "Wisp Forge"
for %%z in ("%~dp0build\Wisp Forge.zip") do set "ZSIZE=%%~zz"
echo Built: build\Wisp Forge\Wisp Forge.exe and build\Wisp Forge.zip (!ZSIZE! bytes)>> "%LOG%"
echo.
echo Done. The game is in build\Wisp Forge, and build\Wisp Forge.zip is ready to share.
echo BUILD OK>> "%LOG%"
timeout /t 8 >nul
exit /b 0
