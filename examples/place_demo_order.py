#!/usr/bin/env python3
"""Send one market order through the bridge, on a demo account only.

    python examples/place_demo_order.py EURUSD --confirm

This opens a real position. Two guards stand in front of it, and both are
deliberate:

  * the script refuses to run unless the terminal is logged into a *demo*
    account, checked against `account_info().trade_mode` rather than against
    anything you pass on the command line;
  * nothing is sent without `--confirm`, so running it by accident prints a plan
    and exits.

Neither guard makes this safe to point at a live account. The bridge has no
authentication and this script has no risk management — it is here to show the
call shape, not to trade.
"""

import argparse
import sys

import rpyc


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("symbol", nargs="?", default="EURUSD")
    parser.add_argument("--side", choices=["buy", "sell"], default="buy")
    parser.add_argument(
        "--volume",
        type=float,
        default=None,
        help="lots (default: the symbol's minimum)",
    )
    parser.add_argument(
        "--confirm",
        action="store_true",
        help="actually send the order; without it the script only prints the plan",
    )
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=8001)
    return parser.parse_args()


def filling_mode(mt5, symbol_info):
    """Pick a fill policy the broker accepts for this symbol.

    `symbol_info.filling_mode` is a bitmask of what the broker allows, and the
    values in it are not the ORDER_FILLING_* constants you put in the request —
    they are the SYMBOL_FILLING_* ones, numbered differently. Sending a policy
    the symbol does not allow fails with "Unsupported filling mode", which is a
    common first wall when adapting an example to a different broker.
    """
    allowed = symbol_info.filling_mode
    if allowed & 1:                 # SYMBOL_FILLING_FOK
        return mt5.ORDER_FILLING_FOK
    if allowed & 2:                 # SYMBOL_FILLING_IOC
        return mt5.ORDER_FILLING_IOC
    return mt5.ORDER_FILLING_RETURN


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

        if not mt5.initialize():
            sys.exit(f"initialize() failed: {mt5.last_error()} — is the terminal logged in?")

        account = mt5.account_info()
        if account is None:
            sys.exit("account_info() returned nothing — the terminal is not logged in")

        # The guard. Ask the terminal what kind of account it is actually on,
        # rather than trusting a flag or a server name.
        if account.trade_mode != mt5.ACCOUNT_TRADE_MODE_DEMO:
            sys.exit(
                f"account {account.login} on {account.server!r} is not a demo account "
                f"(trade_mode={account.trade_mode}). Refusing to send an order."
            )

        if not mt5.symbol_select(args.symbol, True):
            sys.exit(f"symbol {args.symbol!r} is not available on this account")

        info = mt5.symbol_info(args.symbol)
        tick = mt5.symbol_info_tick(args.symbol)
        if info is None or tick is None:
            sys.exit(f"no market data for {args.symbol!r}: {mt5.last_error()}")

        volume = args.volume if args.volume is not None else info.volume_min
        is_buy = args.side == "buy"
        price = tick.ask if is_buy else tick.bid

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": args.symbol,
            "volume": volume,
            "type": mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL,
            "price": price,
            # In points, not price units. It bounds the requote the server may
            # fill you at; without it a fast market rejects the order instead.
            "deviation": 20,
            "magic": 0,
            "comment": "mt5-docker-python example",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": filling_mode(mt5, info),
        }

        print(
            f"demo account {account.login} on {account.server}\n"
            f"  {args.side} {volume} {args.symbol} @ {price} "
            f"(bid {tick.bid} / ask {tick.ask})"
        )

        if not args.confirm:
            print("\nDry run. Re-run with --confirm to send it.")
            return

        result = mt5.order_send(request)
        if result is None:
            sys.exit(f"order_send() returned nothing: {mt5.last_error()}")

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            sys.exit(f"order rejected: retcode={result.retcode} {result.comment!r}")

        print(
            f"\nfilled: deal {result.deal}, order {result.order}, "
            f"{result.volume} @ {result.price}"
        )
        print("Close it from the terminal over the web UI when you're done.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
