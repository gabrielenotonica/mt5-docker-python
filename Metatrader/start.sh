#!/bin/bash
# mt5-docker-silicon first-boot + run script. Launched by the KasmVNC autostart
# (root/defaults/autostart) inside the display session, so $DISPLAY is set and
# the MT5 window is visible over VNC (:3000) for the manual demo login.
#
# Everything installed into the /config-volume wineprefix is PINNED below. That
# is the whole fix vs upstream: no floating mt5linux (whose CLI dropped `-w`) and
# no floating numpy (numpy 2.x breaks the MetaTrader5 wheel's C-extension ABI).
set -u

# ── Pinned versions (bump deliberately, together; the build/boot import-check is
#    the gate) ───────────────────────────────────────────────────────────────
PYTHON_WINE_VER="3.11.9"       # Windows Python for the MetaTrader5 wheel
MONO_VER="10.3.0"
MT5_PY_PKG="MetaTrader5==5.0.6070"
NUMPY_PKG="numpy==1.26.4"      # <2: the MT5 wheel is numpy-1.x ABI
RPYC_PKG="rpyc==6.0.2"         # MUST match the host client's rpyc

WINE="wine"
WINEPREFIX="/config/.wine"; export WINEPREFIX
export WINEDEBUG="${WINEDEBUG:--all}"
PORT="${MT5SERVER_PORT:-8001}"

mono_url="https://dl.winehq.org/wine/wine-mono/${MONO_VER}/wine-mono-${MONO_VER}-x86.msi"
python_url="https://www.python.org/ftp/python/${PYTHON_WINE_VER}/python-${PYTHON_WINE_VER}-amd64.exe"
mt5setup_url="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
mt5file="${WINEPREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe"

log() { echo "[start] $*"; }

# ── [1/5] Wine Mono ───────────────────────────────────────────────────────────
if [ ! -e "${WINEPREFIX}/drive_c/windows/mono" ]; then
    log "[1/5] installing Wine Mono ${MONO_VER}"
    curl -L -o "${WINEPREFIX}/drive_c/mono.msi" "$mono_url"
    WINEDLLOVERRIDES=mscoree=d $WINE msiexec /i "${WINEPREFIX}/drive_c/mono.msi" /qn
    rm -f "${WINEPREFIX}/drive_c/mono.msi"
else
    log "[1/5] Wine Mono present"
fi

# ── [2/5] MetaTrader 5 terminal (latest build from MetaQuotes) ──────────────────
if [ ! -e "$mt5file" ]; then
    log "[2/5] installing MetaTrader 5 (latest build)"
    $WINE reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f
    curl -L -o "${WINEPREFIX}/drive_c/mt5setup.exe" "$mt5setup_url"
    $WINE "${WINEPREFIX}/drive_c/mt5setup.exe" /auto & wait
    rm -f "${WINEPREFIX}/drive_c/mt5setup.exe"
else
    log "[2/5] MetaTrader 5 present"
fi

# ── [3/5] Windows Python (pinned) ───────────────────────────────────────────────
if ! $WINE python --version 2>/dev/null | grep -q "$PYTHON_WINE_VER"; then
    log "[3/5] installing Windows Python ${PYTHON_WINE_VER} in Wine"
    curl -L "$python_url" -o /tmp/py-installer.exe
    $WINE /tmp/py-installer.exe /quiet InstallAllUsers=1 PrependPath=1
    rm -f /tmp/py-installer.exe
else
    log "[3/5] Windows Python ${PYTHON_WINE_VER} present"
fi

# ── [4/5] Pinned Python deps + hard import check ────────────────────────────────
log "[4/5] installing pinned deps: ${MT5_PY_PKG} ${NUMPY_PKG} ${RPYC_PKG}"
$WINE python -m pip install --no-cache-dir --upgrade pip
$WINE python -m pip install --no-cache-dir "$NUMPY_PKG" "$RPYC_PKG" "$MT5_PY_PKG"
if ! $WINE python -c "import numpy, rpyc, MetaTrader5; print('[4/5] deps OK numpy', numpy.__version__, 'rpyc', rpyc.__version__)"; then
    log "[4/5] FATAL: dependency import failed (likely numpy/MetaTrader5 ABI). Adjust the pins above."
    exit 1
fi

# ── [5/5] Run terminal + our rpyc bridge, then keep the terminal alive ──────────
log "[5/5] launching MT5 terminal (/portable) + rpyc bridge on ${PORT}"
[ -e "$mt5file" ] && $WINE "$mt5file" /portable &
sleep 10
$WINE python /Metatrader/server.py --host 0.0.0.0 --port "$PORT" &
sleep 5
if ss -tuln 2>/dev/null | grep -q ":${PORT}"; then
    log "bridge listening on ${PORT}"
else
    log "WARNING: bridge not yet listening on ${PORT} (check above for import/wine errors)"
fi

# Terminal watchdog (a crashed terminal64 is relaunched; the bridge attaches to it).
while true; do
    if [ -e "$mt5file" ] && ! pgrep -f "terminal64.exe" > /dev/null; then
        log "terminal64 not running — relaunching"
        $WINE "$mt5file" /portable &
    fi
    sleep 10
done
