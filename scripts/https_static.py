"""정적 파일을 HTTPS로 서빙한다 (대회장 패드 모드용).

사용법: python scripts/https_static.py <dir> <port> <cert.pem> <key.pem>

- 0.0.0.0 에 묶는다. 같은 와이파이의 다른 기기도 볼 수 있으니 시연 중에만 띄운다.
- 모든 응답에 Cache-Control: no-store 를 붙여 빌드를 다시 해도 패드가 옛 화면을 보지 않게 한다.
"""
from __future__ import annotations

import os
import ssl
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class NoStoreHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "application/javascript",
        ".mjs": "application/javascript",
        ".wasm": "application/wasm",
        ".json": "application/json",
        ".svg": "image/svg+xml",
    }

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        super().end_headers()


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        sys.stderr.write(__doc__ or "")
        return 2
    directory, port_text, cert, key = argv[1:]
    if not os.path.isdir(directory):
        sys.stderr.write(f"폴더가 없습니다: {directory}\n")
        return 1
    for p in (cert, key):
        if not os.path.isfile(p):
            sys.stderr.write(f"파일이 없습니다: {p}\n")
            return 1
    port = int(port_text)

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=cert, keyfile=key)

    handler = partial(NoStoreHandler, directory=directory)
    httpd = ThreadingHTTPServer(("0.0.0.0", port), handler)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    print(f"[https_static] https://0.0.0.0:{port}/  <-  {os.path.abspath(directory)}", flush=True)
    print("[https_static] Ctrl+C 로 끝냅니다.", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
