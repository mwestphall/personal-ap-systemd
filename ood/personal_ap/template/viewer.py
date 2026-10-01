#!/usr/bin/env python3
"""Thin web viewer for a personal HTCondor AP.

Serves a single page with login-node instructions and the live output of
condor_q and condor_status against the AP. Meant to be run on the AP's node
(see script.sh.erb) and reached through Open OnDemand's reverse proxy.
"""

import argparse
import html
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

COMMANDS = [
    "condor_q",
    "condor_status -pool localhost:9618?sock=ap_collector -any",
]

PAGE = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="30">
<title>Personal HTCondor AP</title>
</head>
<body>
<h2>Personal HTCondor AP</h2>
<p>To interact with this AP from the login node, run:</p>
<pre>. {condor_sh}</pre>
{sections}
</body>
</html>
"""


def run(condor_dir, command):
    """Run `command` with the AP's condor environment, returning its output."""
    try:
        proc = subprocess.run(
            ["bash", "-c", '. "$1/condor.sh" && eval "$2"', "_", condor_dir, command],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        return "(timed out)"
    return proc.stdout + proc.stderr


def make_handler(base_dir, condor_dir):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            sections = "\n".join(
                "<h3><code>{}</code></h3>\n<pre>{}</pre>".format(
                    html.escape(cmd), html.escape(run(condor_dir, cmd))
                )
                for cmd in COMMANDS
            )
            body = PAGE.format(
                condor_sh=html.escape(f"{base_dir}/current-ap/condor.sh"),
                sections=sections,
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-dir", required=True)
    parser.add_argument("--condor-dir", required=True)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(
        ("0.0.0.0", args.port), make_handler(args.base_dir, args.condor_dir)
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
