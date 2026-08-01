"""MetaTrader 5 bridge: an rpyc classic SlaveService running under Wine's Python.

A classic SlaveService exposes this interpreter to a client, which is all that is
needed to drive MetaTrader 5 from a non-Windows host:

    import rpyc
    conn = rpyc.classic.connect("localhost", 8001)
    mt5 = conn.modules.MetaTrader5      # the live Windows MetaTrader5 module
    mt5.initialize(); mt5.account_info(); ...

Running it under Wine is what makes `import MetaTrader5` bind to the terminal in
the same prefix. Wrapper libraries exist for this, but they add a CLI whose flags
drift between releases and take the container down with them — thirty lines of
rpyc have no such failure mode.

SECURITY: a SlaveService client gets arbitrary code execution in this container,
with access to the logged-in terminal. Bind it to localhost and keep it there.
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
