"""대회장 패드 모드용 자체 서명 인증서를 만든다.

사용법: backend/.venv/Scripts/python scripts/make_cert.py [IP]

- backend/.certs/cert.pem, key.pem 을 만든다 (RSA 2048, 365일).
- CN=IP, SAN: IP:<ip>, DNS:localhost, IP:127.0.0.1
- 이미 있고 SAN에 현재 IP가 들어 있으면 건너뛴다.
- IP를 주지 않으면 LAN IP를 추측한다 (192.168.* / 10.* / 172.*), 못 찾으면 127.0.0.1.
"""
from __future__ import annotations

import datetime as _dt
import ipaddress
import socket
import sys
from pathlib import Path

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "cryptography 패키지가 없습니다. 다음을 실행하세요:\n"
        "  backend\\.venv\\Scripts\\python -m pip install cryptography\n"
    )
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
CERT_DIR = ROOT / "backend" / ".certs"
CERT_PATH = CERT_DIR / "cert.pem"
KEY_PATH = CERT_DIR / "key.pem"


def guess_lan_ip() -> str:
    candidates: list[str] = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            candidates.append(info[4][0])
    except OSError:
        pass
    for ip in candidates:
        if ip.startswith(("192.168.", "10.", "172.")):
            return ip
    return "127.0.0.1"


def existing_cert_covers(ip: str) -> bool:
    if not (CERT_PATH.exists() and KEY_PATH.exists()):
        return False
    try:
        cert = x509.load_pem_x509_certificate(CERT_PATH.read_bytes())
        san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
        ips = {str(a) for a in san.get_values_for_type(x509.IPAddress)}
        not_after = cert.not_valid_after_utc if hasattr(cert, "not_valid_after_utc") else cert.not_valid_after
        if not_after.tzinfo is None:
            not_after = not_after.replace(tzinfo=_dt.timezone.utc)
        still_valid = not_after > _dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(days=1)
        return ip in ips and still_valid
    except Exception:  # noqa: BLE001 - 깨진 파일이면 새로 만든다
        return False


def make_cert(ip: str) -> None:
    CERT_DIR.mkdir(parents=True, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, ip),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "undersign-assist (demo)"),
    ])
    san_entries: list[x509.GeneralName] = [
        x509.IPAddress(ipaddress.ip_address(ip)),
        x509.DNSName("localhost"),
    ]
    if ip != "127.0.0.1":
        san_entries.append(x509.IPAddress(ipaddress.ip_address("127.0.0.1")))
    now = _dt.datetime.now(_dt.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - _dt.timedelta(minutes=5))
        .not_valid_after(now + _dt.timedelta(days=365))
        .add_extension(x509.SubjectAlternativeName(san_entries), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    KEY_PATH.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        )
    )
    CERT_PATH.write_bytes(cert.public_bytes(serialization.Encoding.PEM))


def main() -> int:
    ip = sys.argv[1].strip() if len(sys.argv) > 1 and sys.argv[1].strip() else guess_lan_ip()
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        sys.stderr.write(f"IP 주소가 아닙니다: {ip}\n")
        return 1
    if existing_cert_covers(ip):
        print(f"[make_cert] 기존 인증서가 {ip} 를 포함합니다. 건너뜀: {CERT_PATH}")
        return 0
    make_cert(ip)
    print(f"[make_cert] 인증서 생성: {CERT_PATH}")
    print(f"[make_cert] 개인키 생성:   {KEY_PATH}")
    print(f"[make_cert] CN={ip}, SAN=IP:{ip}, DNS:localhost, IP:127.0.0.1, 365일")
    return 0


if __name__ == "__main__":
    sys.exit(main())
