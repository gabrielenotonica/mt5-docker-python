#!/bin/bash
#
# Container entrypoint: provision the Wine prefix on first boot, then run the
# MetaTrader 5 terminal and the rpyc bridge for the life of the container.
#
# The KasmVNC session autostart calls this (see root/defaults/autostart), so we
# inherit a live $DISPLAY and the terminal window is reachable over VNC — that is
# how the user performs the interactive broker login.
#
# Provisioning is idempotent and lives entirely in the /config volume, which is
# empty at image build time. Everything installed here is version-pinned: an
# unpinned MetaTrader5 / numpy pair is an ABI coin flip, and a failed import at
# runtime is far more expensive to diagnose than a loud failure at boot.

set -u

readonly LOCK_FILE=/tmp/mt5-entrypoint.lock
readonly WORKDIR=/tmp/mt5-provision

# ── Version pins ──────────────────────────────────────────────────────────────
# Treat these as one unit. The import gate at the end of provisioning is what
# proves a given combination actually loads; bump and re-run rather than guess.
readonly PIN_PYTHON=3.11.9        # Windows CPython — must have a MetaTrader5 wheel
readonly PIN_MONO=10.3.0
readonly PIN_MT5=5.0.6070
readonly PIN_NUMPY=1.26.4         # <2 — the MetaTrader5 wheel targets the numpy 1.x C ABI
readonly PIN_RPYC=6.0.2           # must equal the rpyc the host client imports

# ── Environment ───────────────────────────────────────────────────────────────
WINEPREFIX=${WINEPREFIX:-/config/.wine}
WINEDEBUG=${WINEDEBUG:--all}
export WINEPREFIX WINEDEBUG

readonly TERMINAL="${WINEPREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe"
readonly BRIDGE_PORT=${MT5SERVER_PORT:-8001}
readonly BRIDGE_SCRIPT=/mt5/bridge.py

# Seconds to leave a freshly launched terminal alone before the supervisor is
# allowed to judge it dead. Under x86 emulation Wine can take far longer than one
# poll interval to make terminal64.exe visible to pgrep; without this window the
# supervisor races the boot launch and starts a second terminal, and the two
# fight over the /portable data directory (the window flickers open and closed).
readonly SETTLE_SECONDS=30
readonly POLL_SECONDS=10

say() { printf '[mt5] %s\n' "$*"; }
die() { printf '[mt5] FATAL: %s\n' "$*" >&2; exit 1; }

wine_py() { wine python "$@"; }

# Download to a scratch dir rather than into the prefix: installers are build
# inputs, not part of the persisted Windows filesystem, and a half-finished
# download inside /config would survive a restart and confuse the guards below.
#
# Retries are not optional here. These are large files — the Mono installer alone
# is ~85 MB — pulled on first boot, and on Apple Silicon they cross the NAT of an
# emulated VM. A dropped connection partway through (`curl: (18)`) is a routine
# event there, and without a retry it aborts the whole provisioning run. `-C -`
# resumes rather than restarting, so a drop at 80 MB doesn't cost the 80 MB.
fetch() {
    local url=$1 dest=$2
    curl --fail --location --silent --show-error \
        --retry 5 --retry-delay 3 --retry-all-errors \
        --continue-at - \
        --output "${dest}" "${url}" \
        || die "download failed after retries: ${url}"
}

# ── Single instance ───────────────────────────────────────────────────────────
# The desktop session can replay its autostart list (VNC reconnect, session
# restart). Two live copies of this script means two supervisors, each convinced
# the other's terminal is its own to restart. Whoever takes the lock owns the
# container; the rest leave without touching anything.
exec 9>"${LOCK_FILE}"
if ! flock --nonblock 9; then
    say "another instance holds ${LOCK_FILE} — nothing to do"
    exit 0
fi

mkdir -p "${WORKDIR}"
trap 'rm -rf "$WORKDIR"' EXIT

# ── Provisioning ──────────────────────────────────────────────────────────────

# The prefix has to exist before anything can be installed into it, and on a
# fresh /config volume it does not. wineboot is idempotent, so this is also a
# no-op on every subsequent boot.
#
# `wineboot --init` returns as soon as it has handed the work to wineserver, not
# when the prefix is ready — it leaves wineboot.exe and a setupapi rundll32 still
# populating C:. Installing into a prefix in that state fails with
# `could not load kernel32.dll, status c0000135`, and msiexec fails quietly enough
# that the first visible symptom is a missing terminal64.exe several steps later.
# `wineserver --wait` blocks until every Wine process has exited, which is the
# only reliable "the prefix is finished" signal.
say "initialising Wine prefix at ${WINEPREFIX}"
wineboot --init >/dev/null 2>&1
wineserver --wait

provision_mono() {
    if [[ -d "${WINEPREFIX}/drive_c/windows/mono" ]]; then
        say "Wine Mono already present"
        return
    fi
    say "installing Wine Mono ${PIN_MONO}"
    local msi="${WORKDIR}/mono.msi"
    fetch "https://dl.winehq.org/wine/wine-mono/${PIN_MONO}/wine-mono-${PIN_MONO}-x86.msi" "${msi}"
    # mscoree disabled for the duration, otherwise Wine offers to fetch its own.
    WINEDLLOVERRIDES=mscoree=d wine msiexec /i "${msi}" /qn
    # msiexec is not reliably loud about failing — check the result rather than
    # the exit code, and stop here instead of failing three steps downstream.
    [[ -d "${WINEPREFIX}/drive_c/windows/mono" ]] \
        || die "Wine Mono did not install — see the Wine errors above"
}

provision_terminal() {
    if [[ -e "${TERMINAL}" ]]; then
        say "MetaTrader 5 already installed"
        return
    fi
    say "installing MetaTrader 5"
    # The installer refuses to run in Wine's default Windows version.
    wine reg add 'HKEY_CURRENT_USER\Software\Wine' /v Version /t REG_SZ /d win10 /f
    local setup="${WORKDIR}/mt5setup.exe"
    fetch https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe "${setup}"
    # /auto runs unattended; the installer detaches, so wait for the whole job.
    wine "${setup}" /auto &
    wait
    [[ -e "${TERMINAL}" ]] || die "installer finished but ${TERMINAL} is missing"
}

provision_python() {
    if wine_py --version 2>/dev/null | grep -qF "${PIN_PYTHON}"; then
        say "Windows Python ${PIN_PYTHON} already present"
        return
    fi
    say "installing Windows Python ${PIN_PYTHON}"
    local exe="${WORKDIR}/python-setup.exe"
    fetch "https://www.python.org/ftp/python/${PIN_PYTHON}/python-${PIN_PYTHON}-amd64.exe" "${exe}"
    wine "${exe}" /quiet InstallAllUsers=1 PrependPath=1
}

provision_packages() {
    say "installing pinned packages"
    wine_py -m pip install --no-cache-dir --upgrade pip
    wine_py -m pip install --no-cache-dir \
        "numpy==${PIN_NUMPY}" \
        "rpyc==${PIN_RPYC}" \
        "MetaTrader5==${PIN_MT5}"
}

# The gate. A pinned set that cannot be imported together is a broken container,
# and it is worth failing here — visibly, at boot — instead of at the first call
# a client makes over the bridge an hour later.
verify_imports() {
    wine_py -c 'import numpy, rpyc, MetaTrader5; print("[mt5] imports ok: numpy", numpy.__version__, "/ rpyc", rpyc.__version__)' \
        || die "pinned packages do not import together — revisit the pins in this file"
}

provision_mono
provision_terminal
provision_python
provision_packages
verify_imports

# ── Runtime ───────────────────────────────────────────────────────────────────

# /portable keeps the terminal's data (profiles, the logged-in account) beside the
# executable inside the prefix, so it persists with the /config volume.
launch_terminal() { wine "${TERMINAL}" /portable & }

start_bridge() {
    say "starting rpyc bridge on port ${BRIDGE_PORT}"
    wine_py "${BRIDGE_SCRIPT}" --host 0.0.0.0 --port "${BRIDGE_PORT}" &
    # Purely diagnostic: a missing listener here is almost always a Wine or import
    # error scrolled past above, and saying so now saves a confused client later.
    sleep 5
    if ss -tuln 2>/dev/null | grep -qF ":${BRIDGE_PORT}"; then
        say "bridge listening on ${BRIDGE_PORT}"
    else
        say "WARNING: nothing listening on ${BRIDGE_PORT} yet — check the log above"
    fi
}

# Keep the terminal running for as long as the container lives. The bridge talks
# to whichever terminal is up, so a restart here is transparent to it; the user
# stays logged in because the account lives in the portable data directory.
supervise_terminal() {
    local last_launch=${SECONDS}
    while true; do
        sleep "${POLL_SECONDS}"
        pgrep -f terminal64.exe >/dev/null && continue
        if (( SECONDS - last_launch < SETTLE_SECONDS )); then
            say "terminal not visible yet — inside the ${SETTLE_SECONDS}s settle window"
            continue
        fi
        say "terminal is gone — restarting it"
        launch_terminal
        last_launch=${SECONDS}
    done
}

say "starting MetaTrader 5"
launch_terminal
sleep 10          # let the terminal claim its data directory before anything imports it
start_bridge
supervise_terminal
