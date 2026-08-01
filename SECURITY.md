# Security Policy

## The threat model, stated plainly

This project runs a trading terminal and exposes a Python bridge to it. Two things
follow from that, and they are properties of the design rather than bugs:

**The rpyc bridge on port 8001 is a remote code execution primitive.** It is a
classic rpyc `SlaveService`, which is what makes `conn.modules.MetaTrader5` work at
all — the client drives the container's interpreter. Anyone who can open a TCP
connection to that port can run arbitrary code inside the container, as the user
running the terminal, against whatever account that terminal is logged into. There
is no authentication on it.

**The VNC UI on port 3000 guards the terminal's session.** `CUSTOM_USER` and
`PASSWORD` gate it, and the shipped `.env.example` uses `changeme`.

The supplied `docker-compose.yaml` therefore binds both ports to `127.0.0.1`. That
binding is a security control, not a default to tidy up. If you need access from
another machine, tunnel it:

```bash
ssh -L 8001:localhost:8001 user@host
```

Do not put the bridge on a public interface, a cloud VM with an open security
group, or a network you share with anything you don't control — not even behind a
password prompt, since it has none to check.

Two further notes on the container itself: it runs with `SYS_PTRACE` and
`seccomp=unconfined`, which Wine needs and which weaken container isolation, so
treat a compromise of the container as a compromise of a fairly privileged process
on the host. And your broker credentials are typed into MetaTrader over VNC and
live in the `./config` volume — that directory is as sensitive as the account.
Never commit it, and note that it is gitignored for that reason.

## Reporting a vulnerability

Report privately via GitHub's
[security advisory form](https://github.com/gabrielenotonica/mt5-docker-python/security/advisories/new).
Please do not open a public issue.

Include what you were running, what you observed, and how to reproduce it. Expect a
first response within a week. This is a single-maintainer hobby project, so there is
no formal SLA beyond that and no bounty.

Findings that describe the documented behaviour above — that an exposed port 8001
allows code execution, or that the example password is weak — are already known and
documented; a report showing a way to reach that port or the account *without*
someone having widened the binding is very much of interest.

## Supported versions

The latest release. Fixes go to `main` and the next tag; older tags are not
backported.
