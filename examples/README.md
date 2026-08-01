# Examples

Run these on your **host**, not in the container. They talk to the bridge on
`localhost:8001`, so the container needs to be up and the terminal logged into an
account.

```bash
pip install "rpyc==6.0.2" pandas
```

The rpyc version has to match the one pinned in
[mt5/entrypoint.sh](../mt5/entrypoint.sh) — the protocol is not stable across
major versions, and a mismatch fails at connection time rather than later.

| Script | What it does |
|---|---|
| [fetch_candles.py](fetch_candles.py) | Pulls OHLC candles into a pandas DataFrame. Read-only. |
| [place_demo_order.py](place_demo_order.py) | Sends one market order. Refuses to run on anything but a demo account, and needs `--confirm`. |

```bash
python examples/fetch_candles.py EURUSD --timeframe H1 --count 500
python examples/place_demo_order.py EURUSD              # prints the plan, sends nothing
python examples/place_demo_order.py EURUSD --confirm    # sends it
```

Both take `--host` and `--port` if you tunnelled the bridge from somewhere else.

## Two things worth stealing

**`obtain()` before pandas.** Every value coming back over an rpyc classic
connection is a netref — a proxy that round-trips to the container on each
attribute access. Passing one to pandas works and is painfully slow, because
building the frame touches every element individually. `rpyc.utils.classic.obtain`
transfers the array once and hands you a local one.

**Pick the fill policy from the symbol.** `symbol_info().filling_mode` is a bitmask
of what your broker allows, and its values are numbered differently from the
`ORDER_FILLING_*` constants that go into the request. Hardcoding `ORDER_FILLING_IOC`
is the usual reason an example that worked for someone else fails with *Unsupported
filling mode* on your account. `place_demo_order.py` derives it.
