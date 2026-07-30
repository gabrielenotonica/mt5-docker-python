"""Tiny MetaTrader5 bridge: an rpyc classic SlaveService, run under Wine's Python.

The whole point of this project's fork: upstream (gmag11) shells out to the
`mt5linux` package whose CLI drifts between releases (0.x had `-w`, 1.x removed
it → the published image fails to start the server). We don't need it. A classic
rpyc SlaveService exposes the remote interpreter, so a host client does:

    import rpyc
    conn = rpyc.classic.connect("localhost", 8001)
    mt5 = conn.modules.MetaTrader5      # the Windows MetaTrader5, live
    mt5.initialize(); mt5.account_info(); ...

That is exactly what mt5linux generated internally, minus the fragile wrapper.
Runs under Wine so `import MetaTrader5` binds to the terminal in the same prefix.
Localhost/dev tool: SlaveService grants full remote access — do not expose :8001.
"""

import argparse

from rpyc.core import SlaveService
from rpyc.utils.server import ThreadedServer

parser = argparse.ArgumentParser(description="MetaTrader5 rpyc bridge")
parser.add_argument("--host", default="0.0.0.0")
parser.add_argument("--port", type=int, default=8001)
args = parser.parse_args()

print(f"[bridge] rpyc SlaveService starting on {args.host}:{args.port}", flush=True)
ThreadedServer(
    SlaveService,
    hostname=args.host,
    port=args.port,
    protocol_config={
        "allow_all_attrs": True,
        "allow_public_attrs": True,
        "allow_setattr": True,
        "allow_pickle": True,
        # MT5 history/deal reads over Wine+QEMU can be slow; don't time out a call.
        "sync_request_timeout": 120,
    },
).start()
