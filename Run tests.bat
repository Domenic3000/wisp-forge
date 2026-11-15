@echo off
rem Runs the automated checks on a fresh test planet (your saves are not touched)
rem and writes the results to saves\test_report.txt
cd /d "%~dp0"
for %%E in (engine\Godot_v4*_console.exe) do set GODOT=%%E
if not exist saves mkdir saves
"%GODOT%" --path game -- --test > saves\test_log.txt 2>&1
if errorlevel 1 (echo Some checks FAILED. See saves\test_report.txt) else (echo All checks passed.)
type saves\test_report.txt
