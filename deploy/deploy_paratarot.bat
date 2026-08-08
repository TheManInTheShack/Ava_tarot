@echo off
setlocal

:: Deploys Paratarot to avareads.com. Mirrors Grant/scripts/deploy.bat's
:: shape, but this is a bespoke satellite-only app (own repo, per the
:: Hub/Satellite rule in Grant/docz/infrastructure/new-site-guide.md) — it
:: does not touch grantdickerson.net at all.
::
:: This script only handles the Godot export + upload. Shared platform
:: changes (auth-service role, nginx locations, grant-api WebSocket) live in
:: the Grant repo and reach avareads.com via its own update.sh — run that
:: separately (or via this script's last step) after pushing those changes.

:: ── Edit these paths ──────────────────────────────────────────────
set GODOT="C:\Users\thman\Desktop\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
set PROJECT="C:\Users\thman\dev\projects\ava_tarot"
set OUT_DIR="C:\Users\thman\dev\projects\ava_tarot\export"
set SERVER=root@avareads.com
set PARATAROT_REMOTE=/var/www/grant/apps/paratarot
:: ──────────────────────────────────────────────────────────────────

echo [git] Pulling latest...
git -C "C:\Users\thman\dev\projects\ava_tarot" pull origin main
if errorlevel 1 (
    echo Git pull failed.
    exit /b 1
)

echo [export] Clearing old export files...
del /q %OUT_DIR%\* 2>nul

echo [export] Building Godot project...
%GODOT% --headless --path %PROJECT% --export-release "Web" %OUT_DIR%\index.html
if errorlevel 1 (
    echo Godot export failed.
    exit /b 1
)

echo [upload] Uploading Paratarot...
scp %OUT_DIR%\index.html %SERVER%:%PARATAROT_REMOTE%/index.html
scp %OUT_DIR%\index.js   %SERVER%:%PARATAROT_REMOTE%/index.js
scp %OUT_DIR%\index.pck  %SERVER%:%PARATAROT_REMOTE%/index.pck
scp %OUT_DIR%\index.wasm %SERVER%:%PARATAROT_REMOTE%/index.wasm
if exist %OUT_DIR%\index.worker.js        scp %OUT_DIR%\index.worker.js        %SERVER%:%PARATAROT_REMOTE%/index.worker.js
if exist %OUT_DIR%\index.audio.worklet.js scp %OUT_DIR%\index.audio.worklet.js %SERVER%:%PARATAROT_REMOTE%/index.audio.worklet.js
if errorlevel 1 (
    echo Upload failed.
    exit /b 1
)

echo.
echo Reminder: if this is the first deploy after the Grant repo's auth-service /
echo nginx / grant-api changes for Paratarot, also run on avareads.com:
echo   bash /opt/grant/server/scripts/update.sh
echo and confirm /etc/grant-site.env's SITE_APPS includes "paratarot".
echo.
echo Done. https://avareads.com/paratarot/
endlocal
