import argparse
import os
import secrets
from pathlib import Path

import uvicorn

from .app import create_app


def main():
    parser = argparse.ArgumentParser(description="OpenListen personal audio companion")
    parser.add_argument("--host", default="127.0.0.1", help="Use 0.0.0.0 only on a trusted LAN")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--data-dir", type=Path, default=Path.home() / ".local/share/openlisten")
    args = parser.parse_args()
    token = os.environ.get("OPENLISTEN_TOKEN") or secrets.token_urlsafe(32)
    print("OpenListen — enter your computer's address and this pairing token in the iPhone app.")
    print(f"Pairing token (keep private): {token}", flush=True)
    print("A new token is generated on restart unless OPENLISTEN_TOKEN is set.", flush=True)
    uvicorn.run(create_app(args.data_dir.expanduser(), token), host=args.host,
                port=args.port, access_log=False)


if __name__ == "__main__":
    main()
