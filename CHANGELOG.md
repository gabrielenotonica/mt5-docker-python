# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) — where "the API" means
the bridge protocol, the compose contract and the ports, not the pinned versions of
MetaTrader or Wine.

## [Unreleased]

## [0.1.0] - 2026-07-30

First public release.

### Added

- MetaTrader 5 running headless under Wine, reachable over KasmVNC on port 3000.
- An rpyc bridge on port 8001 that exposes the Windows `MetaTrader5` module to a
  client on any host OS.
- Every runtime dependency pinned — MetaTrader5, numpy, rpyc, the Windows Python,
  Wine Mono and Wine itself — with a boot-time import check that fails loudly
  rather than leaving a broken container running.
- Wine held at 10.0: on 11.0 the MetaTrader installer aborts with a false-positive
  "a debugger has been found running in your system".
- Idempotent provisioning into the `/config` volume, so restarts keep the Wine
  prefix, the MetaTrader install and the logged-in account.
- A supervisor that restarts the terminal if it dies, with a settle window so it
  cannot race a slow start under emulation and launch a second one.
- A single-instance lock, so a replayed desktop autostart cannot start a competing
  supervisor.
- Apple Silicon support via an x86_64 QEMU VM (Colima), documented with the reason
  it is required: Wine's x86 memory manager needs 4 KB pages and the arm64 macOS
  VM uses 16 KB.
- CI on every push and pull request (ShellCheck, Hadolint, compose validation,
  image build, boot smoke test), and tagged releases published to GHCR and
  Docker Hub.

### Security

- Both published ports bind to `127.0.0.1` by default. The bridge is an
  unauthenticated remote code execution primitive by design; see
  [SECURITY.md](SECURITY.md).

[Unreleased]: https://github.com/gabrielenotonica/mt5-docker-python/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gabrielenotonica/mt5-docker-python/releases/tag/v0.1.0
