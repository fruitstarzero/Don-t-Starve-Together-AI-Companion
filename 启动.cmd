@echo off
cd /d "%~dp0"
node tools/start.mjs --game
if errorlevel 1 pause
