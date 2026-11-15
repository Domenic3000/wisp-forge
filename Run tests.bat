@echo off
rem Runs the automated checks on a fresh test planet (your saves are not touched)
rem and writes the results to saves\test_report.txt
cd /d "%~dp0"
for %%E in (engine\Godot_v4*_console.exe) do set GODOT=%%E
if not exist saves mkdir saves
"%GODOT%" --path game -- --test > saves\test_log.txt 2>&1
set RESULT=%ERRORLEVEL%
rem any script error during the run is a failure too
findstr /C:"SCRIPT ERROR" saves\test_log.txt >NUL && (echo FAIL  script errors during the run, see saves\test_log.txt>> saves\test_report.txt) && set RESULT=1
if "%RESULT%"=="0" (echo All checks passed.) else (echo Some checks FAILED. See saves\test_report.txt)
type saves\test_report.txt
