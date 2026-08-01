# mt5-docker-python

**MetaTrader 5, headless in Docker, driven from Python — including on an Apple
Silicon Mac, with no Windows and no Parallels.**

[![CI](https://github.com/gabrielenotonica/mt5-docker-python/actions/workflows/ci.yml/badge.svg)](https://github.com/gabrielenotonica/mt5-docker-python/actions/workflows/ci.yml)
[![GHCR](https://img.shields.io/badge/ghcr.io-mt5--docker--python-blue?logo=github)](https://github.com/gabrielenotonica/mt5-docker-python/pkgs/container/mt5-docker-python)
[![Docker Hub](https://img.shields.io/docker/pulls/gabrielenotonica/mt5-docker-python?logo=docker)](https://hub.docker.com/r/gabrielenotonica/mt5-docker-python)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

MetaTrader 5 is a Windows program. This runs it under Wine in a container and gives
you two ways in:

- **A browser** at `http://localhost:3000` — the real terminal, over KasmVNC. This
  is where you log into your broker account.
- **The Python API** at `localhost:8001` — `import MetaTrader5` from macOS or Linux
  and talk to the live terminal, over an rpyc bridge.

```python
import rpyc
conn = rpyc.classic.connect("localhost", 8001)
mt5 = conn.modules.MetaTrader5          # the live Windows MetaTrader5 module

mt5.initialize()
print(mt5.account_info())
print(mt5.copy_rates_from_pos("EURUSD", mt5.TIMEFRAME_M5, 0, 10))
```

That's the real `MetaTrader5` package, not a reimplementation — same functions,
same return types, running against a terminal connected to your broker.

## Why this one

Containers that put MetaTrader in Wine are not new. Two things here are deliberate:

**Every version is pinned, and the container proves it at boot.** MetaTrader5,
numpy, rpyc, the Windows Python, Wine Mono and Wine itself. Left to float, this
stack breaks on someone else's schedule — numpy 2.x alone is enough to break it,
because the MetaTrader5 wheel is built against the numpy 1.x C ABI. Provisioning
ends with an import check, so a bad combination fails loudly at startup instead of
becoming a confusing error in your code an hour later.

**The bridge is thirty lines, and depends on nothing.** It's a plain rpyc
`SlaveService` ([mt5/bridge.py](mt5/bridge.py)). Wrapper libraries exist for this
job, but they add a command-line interface whose flags shift between releases and
take the container down with them. There is nothing here to drift.

Plus the Apple Silicon path is documented rather than left as an exercise — see
below, it needs one non-obvious step.

## Quickstart

**On Apple Silicon**, first bring up an x86_64 Docker (once — [why](#why-apple-silicon-needs-an-x86_64-vm)):

```bash
brew install colima docker qemu lima lima-additional-guestagents
colima start --arch x86_64 --vm-type=qemu --cpu 4 --memory 8 --disk 60
```

On x86_64 Linux, use your normal Docker and skip that.

Then:

```bash
curl -O https://raw.githubusercontent.com/gabrielenotonica/mt5-docker-python/main/docker-compose.yaml
curl -o .env https://raw.githubusercontent.com/gabrielenotonica/mt5-docker-python/main/.env.example
docker compose up -d
```

Edit `.env` first if you want a password other than the placeholder — it gates the
local web UI.

The first boot downloads and installs MetaTrader, a Windows Python and the pinned
wheels into `./config`. It takes a few minutes and happens once. Watch it with
`docker compose logs -f mt5`.

Then:

1. Open **http://localhost:3000** and wait for the terminal window.
2. Log into your account — *File → Login to Trade Account*, or open a demo. Do this
   by hand, once; it persists.
3. Talk to it from Python. Your host needs a matching rpyc:

   ```bash
   pip install "rpyc==6.0.2"
   ```

To build the image yourself instead of pulling it:

```bash
git clone https://github.com/gabrielenotonica/mt5-docker-python
cd mt5-docker-python
cp .env.example .env
docker compose -f docker-compose.yaml -f docker-compose.build.yaml up -d --build
```

## Why Apple Silicon needs an x86_64 VM

MetaTrader is x86 and runs under Wine, and Wine's x86 memory manager requires
**4 KB memory pages**. Apple Silicon — and therefore the Linux VM inside Docker
Desktop — uses **16 KB pages**. Wine aborts:

```
wine: Assertion failed: anon_mmap_fixed(...)
```

Emulating the x86 binary is not enough; the page size belongs to the VM, not the
process. So you need a real x86_64 VM, which is what
[Colima](https://github.com/abiosoft/colima) with `--vm-type=qemu` gives you. The
container is `linux/amd64` and runs natively inside it.

It is emulated, so it is not fast. It is fast enough to run a terminal and pull
history.

## Pinned versions

| Component | Pin | Why |
|---|---|---|
| `MetaTrader5` (Windows) | `5.0.6070` | latest at time of pinning |
| `numpy` (Windows) | `1.26.4` | must be `<2` — the MetaTrader5 wheel targets the numpy 1.x C ABI |
| `rpyc` | `6.0.2` | must match the rpyc on your host |
| Windows Python | `3.11.9` | has a MetaTrader5 wheel |
| Wine Mono | `10.3.0` | |
| Wine | `10.0.0.0~bookworm-1` | **not 11** — see below |
| MetaTrader terminal | latest MetaQuotes build | |
| base image | `ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm` | |

Wine 11 makes the MetaTrader installer abort with *"A debugger has been found
running in your system"* — an anti-debug false positive that 10.0 doesn't trigger.

The Python-side pins live in [mt5/entrypoint.sh](mt5/entrypoint.sh), Wine's in the
[Dockerfile](Dockerfile). Bump them as a set; the boot import check is what tells
you whether a combination actually works.

## Persistence

The Wine prefix, the MetaTrader install and your logged-in account all live in
`./config`, a bind mount. Restarts keep you logged in. Delete the directory to
start completely fresh.

`./config` holds your account session. It is gitignored — keep it that way.

## A second account

MetaTrader keeps one account per terminal, so a second account means a second
container. [docker-compose.second.yaml](docker-compose.second.yaml) is that, on
its own ports:

```bash
cp -r config config2      # MT5 is already installed in there, so this boots fast
docker compose -f docker-compose.second.yaml -p mt5-second up -d
```

VNC on `http://localhost:3010`, bridge on `localhost:8011`. Log the new terminal
into the second account by hand, once, the same way.

## Troubleshooting

**`anon_mmap_fixed` assertion, or Wine dies immediately on a Mac.** You're on the
arm64 Docker VM with 16 KB pages. Use Colima with `--arch x86_64 --vm-type=qemu`.

**"A debugger has been found running in your system".** Either Wine got upgraded
past 10.0, or the container is missing `SYS_PTRACE` / `seccomp=unconfined`. Both
are set in the supplied compose file.

**Nothing listening on 8001.** Read the boot log — `docker compose logs mt5`. If
provisioning failed, the reason is there and prefixed with `[mt5]`. A `FATAL:` line
about imports means the pins are incompatible.

**The terminal window opens and closes repeatedly.** That pattern means two
terminals are fighting over the same portable data directory. The entrypoint has a
single-instance lock and a settle window to prevent it; if you see it anyway,
please open an issue with the log.

**First boot seems stuck.** It's downloading MetaTrader and a Windows Python
through Wine, under emulation. Give it ten minutes before assuming it's wedged,
and watch `docker compose logs -f mt5` rather than the VNC window.

**`initialize()` returns `False`.** The terminal is running but not logged in. Open
the web UI and log in by hand.

## Security

The rpyc bridge is unauthenticated by design: anyone who can reach port 8001 can run
arbitrary code inside the container, against a terminal logged into a real trading
account. Treat that port as equivalent to a shell on the machine.

The compose file binds both ports to `127.0.0.1`. **That binding is the security
control** — do not change it to `0.0.0.0` or to a bare `8001:8001`. If you need
access from another machine, tunnel it:

```bash
ssh -L 8001:localhost:8001 user@host
```

`CUSTOM_USER` / `PASSWORD` gate the local web UI only. They are not broker
credentials — those you type into MetaTrader over VNC, and they stay in `./config`.

Full threat model in [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports are most useful with the boot
log attached.

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with MetaQuotes. MetaTrader 5 is their software, downloaded from
their servers at first boot and subject to their terms. Trading carries risk; test
against a demo account.
