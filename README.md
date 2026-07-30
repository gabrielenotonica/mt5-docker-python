# mt5-docker-silicon

**MetaTrader 5, headless in Docker, with a Python bridge — that actually runs on Apple Silicon.**

MT5 (a Windows app) runs under Wine in a Linux container, reachable two ways:

- **KasmVNC** on `http://localhost:3000` — see the terminal, log into your account by hand.
- **rpyc bridge** on `localhost:8001` — drive the real `MetaTrader5` Python API from your host (any OS), no Windows, no VM of your own.

It's built for **Apple Silicon / arm64** Macs (see below), and works on x86 Linux too.

> Inspired by [gmag11/MetaTrader5-Docker](https://github.com/gmag11/MetaTrader5-Docker) (MIT). This is a hardened fork: **every runtime dependency is pinned** — the upstream image currently fails to start because `mt5linux` floated to a release whose CLI dropped the `-w` switch its script still passes, and `numpy` floated to 2.x which breaks the MetaTrader5 wheel's C-extension — and the flaky `mt5linux` server is replaced by a **tiny self-contained rpyc bridge** (`Metatrader/server.py`), so nothing depends on an unstable third-party CLI.

## Why Apple Silicon needs one extra step

MT5 is x86 and runs under Wine. Wine's x86 memory manager needs **4 KB memory pages**, but Apple Silicon (and therefore Docker Desktop's VM) uses **16 KB pages** — Wine aborts with `anon_mmap_fixed ... assertion failed`. The fix is a real **x86_64 QEMU VM** (4 KB pages), which [Colima](https://github.com/abiosoft/colima) provides:

```bash
brew install colima docker qemu lima lima-additional-guestagents
colima start --arch x86_64 --vm-type=qemu --cpu 4 --memory 8 --disk 60
```

On x86_64 Linux hosts you can skip Colima and use Docker directly.

## Quickstart

```bash
cp .env.example .env          # edit CUSTOM_USER/PASSWORD (local VNC gate only)
docker compose up --build -d  # first boot installs MT5 in Wine — a few minutes
```

Then:

1. Open **http://localhost:3000**, wait for the MT5 window, and **log into your DEMO account** (File → Login to Trade Account, or open a new demo).
2. Drive it from your host:

```python
import rpyc
conn = rpyc.classic.connect("localhost", 8001)
mt5 = conn.modules.MetaTrader5          # the live Windows MetaTrader5 module
mt5.initialize()
print(mt5.account_info())
print(mt5.copy_rates_from_pos("EURUSD", mt5.TIMEFRAME_M5, 0, 10))
```

Your host only needs a matching rpyc: `pip install "rpyc==6.0.2"`.

## Pinned versions

| Component | Pin | Why |
|---|---|---|
| `MetaTrader5` (Windows) | `5.0.6070` | latest at build |
| `numpy` (Windows) | `1.26.4` | `<2` — the MT5 wheel is numpy-1.x ABI |
| `rpyc` | `6.0.2` | must match the host client |
| Windows Python | `3.11.9` | has a MetaTrader5 wheel |
| Wine Mono | `10.3.0` | |
| MT5 terminal | latest MetaQuotes build | |
| base image | `ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm` + `winehq-stable` | |

Bump them together in `Metatrader/start.sh`; the boot-time import check fails loudly if a combination is ABI-incompatible.

## Persistence

The wineprefix, the MT5 install and your demo login all live in `./config` (a bind mount), so a restart keeps you logged in.

## Security

The rpyc bridge is a classic `SlaveService`: a client on `:8001` gets full access to the container's Python. Keep it on `localhost` — **never expose port 8001** to a network. `CUSTOM_USER`/`PASSWORD` gate the local VNC UI only; they are not broker credentials, which you type into MT5 over VNC and which never leave the container.

## License

MIT. See [LICENSE](LICENSE). Not affiliated with MetaQuotes.
