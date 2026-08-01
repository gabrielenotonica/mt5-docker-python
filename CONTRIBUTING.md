# Contributing

Issues and pull requests are welcome. This is a small project; there is no process
to speak of beyond what is below.

## Before you open an issue

Container problems here are usually one of a handful of known things. The
[Troubleshooting](README.md#troubleshooting) section covers them, and checking it
first will often be faster than waiting for a reply.

If it isn't covered, please include:

- your host (Apple Silicon or x86_64, macOS or Linux) and whether you're on Colima
- `docker compose logs mt5` from a fresh start — the entrypoint prefixes its lines
  with `[mt5]` and says which provisioning step it reached
- the image tag you're running, or the commit if you built it yourself

## Development

Build and run from source with the build overlay:

```bash
docker compose -f docker-compose.yaml -f docker-compose.build.yaml up -d --build
```

The first boot downloads MetaTrader, a Windows Python and the pinned wheels into
`./config`. That takes a few minutes and only happens once — delete `./config` to
force it again, which is also how you test a change to provisioning.

Before pushing:

```bash
shellcheck mt5/entrypoint.sh
docker compose config -q
```

CI runs those plus a Hadolint pass and a build with a boot smoke test.

## Changing a version pin

The pins in [mt5/entrypoint.sh](mt5/entrypoint.sh) are the point of this project, so
they get a little more care than a normal dependency bump:

- Bump them as a set, not one at a time. `MetaTrader5`, `numpy` and the Windows
  Python interact through a C ABI, and only some combinations load.
- Test against an **empty** `./config`. A pin change that works on your existing
  prefix may still fail a fresh install.
- Say in the PR what you actually ran, and paste the `imports ok:` line from the
  boot log.

Wine is pinned in the [Dockerfile](Dockerfile) and has its own trap: version 11
makes the MetaTrader installer abort with a false-positive anti-debug error. If you
raise it, install from scratch and confirm the installer completes.

## Pull requests

Keep them focused, explain the reasoning in the description rather than only the
diff, and note how you tested. Comments in this codebase explain *why* something is
the way it is — please match that; several of the odd-looking lines here exist
because of a specific failure, and a future reader needs to know which.

## Security

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).
