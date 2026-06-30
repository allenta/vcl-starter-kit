#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import http.server
import logging

logger = logging.getLogger(__name__)


class Handler(http.server.BaseHTTPRequestHandler):
    # BaseHTTPRequestHandler dispatches each request to a `do_<METHOD>`
    # attribute; resolving all of them to the same echo handler accepts ANY
    # HTTP method without enumerating them.
    def __getattr__(self, name):
        if name.startswith("do_"):
            return self._echo
        raise AttributeError(name)

    def _echo(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
        except (TypeError, ValueError):
            length = 0
        body = self.rfile.read(length) if length > 0 else b""

        text = f"{self.command} {self.path} {self.request_version}\n{self.headers}\n"
        payload = text.encode("utf-8") + body
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        if self.command in ("GET", "QUERY"):
            if self.path.startswith("/foo/"):
                self.send_header(
                    "Cache-Control", "private, no-cache, no-store, must-revalidate"
                )
            else:
                self.send_header(
                    "Cache-Control",
                    "s-maxage=30, stale-while-revalidate=5, stale-if-error=300",
                )
        self.end_headers()
        self.wfile.write(payload)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--loglevel",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)

    options = parser.parse_args()

    logging.basicConfig(
        format="%(asctime)s - %(levelname)s - %(message)s",
        level=getattr(logging, options.loglevel),
    )

    httpd = http.server.ThreadingHTTPServer((options.host, options.port), Handler)
    logger.info("Listening on http://%s:%s", options.host, options.port)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
