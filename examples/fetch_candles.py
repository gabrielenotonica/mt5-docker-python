#!/usr/bin/env python3
"""Pull candles from the containerised terminal into a pandas DataFrame.

    python examples/fetch_candles.py EURUSD --timeframe M5 --count 200

Read-only: it opens no positions and changes nothing in the terminal.

The one non-obvious thing here is `obtain`. Over an rpyc classic connection every
remote value arrives as a netref — a proxy that looks like the object but performs
a round trip on each attribute access. Handing a netref array to pandas works, and
is agonisingly slow, because building the frame touches every element one at a
time across the socket. `obtain` pulls the whole array over in one transfer and
gives you a genuinely local numpy array; do that before pandas sees it.
"""

import argparse
import sys

import rpyc
from rpyc.utils.classic import obtain


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("symbol", nargs="?", default="EURUSD")
    parser.add_argument(
        "--timeframe",
        default="M5",
        help="M1, M5, M15, M30, H1, H4, D1, W1, MN1 (default: M5)",
    )
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=8001)
    return parser.parse_args()


def connect(host, port):
    """Connect, and turn the first-run failure into something actionable.

    A refused connection here means the container is down or still provisioning,
    which on a first boot takes minutes — not that anything is misconfigured.
    """
    try:
        return rpyc.classic.connect(host, port)
    except ConnectionRefusedError:
        sys.exit(
            f"nothing listening on {host}:{port}. Is the container up?\n"
            "  docker compose ps\n"
            "  docker compose logs -f mt5     # first boot provisions Wine, give it minutes"
        )


def main():
    args = parse_args()

    conn = connect(args.host, args.port)
    try:
        mt5 = conn.modules.MetaTrader5

        # initialize() attaches to the terminal already running in the container;
        # it does not start one. False here almost always means nobody has logged
        # the terminal into an account yet — do that once over the web UI.
        if not mt5.initialize():
            sys.exit(f"initialize() failed: {mt5.last_error()} — is the terminal logged in?")

        try:
            timeframe = getattr(mt5, f"TIMEFRAME_{args.timeframe.upper()}")
        except AttributeError:
            sys.exit(f"unknown timeframe {args.timeframe!r}")

        # A symbol the terminal has never shown in Market Watch returns no rates,
        # with no error to explain why. Selecting it first removes that trap.
        if not mt5.symbol_select(args.symbol, True):
            sys.exit(f"symbol {args.symbol!r} is not available on this account")

        rates = mt5.copy_rates_from_pos(args.symbol, timeframe, 0, args.count)
        if rates is None or len(rates) == 0:
            sys.exit(f"no rates returned: {mt5.last_error()}")

        # One transfer, then everything below is local. See the module docstring.
        rates = obtain(rates)
    finally:
        conn.close()

    # Imported late so the script still reports a connection problem clearly on a
    # host that has rpyc but not pandas.
    import pandas as pd

    frame = pd.DataFrame(rates)
    frame["time"] = pd.to_datetime(frame["time"], unit="s")
    frame = frame.set_index("time")

    print(frame.tail(10))
    print(f"\n{len(frame)} candles, {frame.index[0]} → {frame.index[-1]}")


if __name__ == "__main__":
    main()
