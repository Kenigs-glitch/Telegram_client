"""Check proxy liveness by comparing direct IP vs IP through proxy via api.ipify.org."""

import json
import re
import sys
from urllib.parse import quote

import urllib3

TIMEOUT = 10
IPV4_RE = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")
IP_SERVICE_HTTPS = "https://api.ipify.org/"
IP_SERVICE_HTTP = "http://api.ipify.org/"


def parse_ip(text):
    """Extract and validate IP from response text."""
    text = text.strip()
    if IPV4_RE.match(text):
        return text
    # Try JSON {"ip": "..."}
    try:
        data = json.loads(text)
        if isinstance(data, dict) and IPV4_RE.match(data.get("ip", "")):
            return data["ip"]
    except (json.JSONDecodeError, TypeError):
        pass
    raise ValueError(f"Ответ не содержит IP: {text[:80]}")


def get_direct_ip():
    http = urllib3.PoolManager(timeout=TIMEOUT)
    resp = http.request("GET", IP_SERVICE_HTTPS)
    return parse_ip(resp.data.decode())


def get_proxy_ip(proxy):
    host = proxy.get("ip") or proxy.get("host") or ""
    port = int(proxy.get("port", 0))
    user = proxy.get("login") or proxy.get("username") or ""
    password = proxy.get("password", "")
    protocol = proxy.get("protocol", "socks5").lower()

    if protocol == "socks5":
        # socks5 requires PySocks: python3 -m pip install pysocks
        import socks
        import socket
        from urllib.request import urlopen
        orig_socket = socket.socket
        try:
            socks.set_default_proxy(
                socks.SOCKS5, host, port,
                username=user or None, password=password or None,
            )
            socket.socket = socks.socksocket
            resp = urlopen(IP_SERVICE_HTTPS, timeout=TIMEOUT)
            return parse_ip(resp.read().decode())
        finally:
            socket.socket = orig_socket
    else:
        # http proxy — use plain HTTP target to avoid CONNECT tunnel issues
        proxy_url = f"http://{host}:{port}"
        headers = urllib3.make_headers(proxy_basic_auth=f"{user}:{password}") if user else {}
        http = urllib3.ProxyManager(proxy_url, proxy_headers=headers, timeout=TIMEOUT)
        resp = http.request("GET", IP_SERVICE_HTTP)
        return parse_ip(resp.data.decode())


def check_all(proxies_path):
    with open(proxies_path) as f:
        proxies = json.load(f)

    if not proxies:
        print("Нет прокси для проверки.")
        return True

    print(f"Проверка {len(proxies)} прокси через api.ipify.org ...")

    try:
        direct_ip = get_direct_ip()
    except Exception as e:
        print(f"  ✗ Не удалось получить прямой IP: {e}")
        print("  Пропускаю проверку прокси.")
        return True

    print(f"  Прямой IP: {direct_ip}")
    print()

    all_ok = True
    for i, proxy in enumerate(proxies):
        host = proxy.get("ip") or proxy.get("host") or "?"
        port = proxy.get("port", "?")
        protocol = proxy.get("protocol", "socks5")
        label = f"#{i+1} {host}:{port} [{protocol}]"

        try:
            proxy_ip = get_proxy_ip(proxy)
            if proxy_ip == direct_ip:
                print(f"  ✗ {label} — IP не изменился ({proxy_ip}), прокси не работает!")
                all_ok = False
            else:
                print(f"  ✓ {label} — OK (IP: {proxy_ip})")
        except Exception as e:
            err = str(e)
            if len(err) > 120:
                err = err[:120] + "..."
            print(f"  ✗ {label} — ОШИБКА: {err}")
            all_ok = False

    return all_ok


def check_single(proxies_path, idx):
    """Check a single proxy by index. Returns True if alive."""
    with open(proxies_path) as f:
        proxies = json.load(f)

    if idx < 0 or idx >= len(proxies):
        return True  # no proxy / out of range — skip

    proxy = proxies[idx]
    host = proxy.get("ip") or proxy.get("host") or "?"
    port = proxy.get("port", "?")
    protocol = proxy.get("protocol", "socks5")
    label = f"{host}:{port} [{protocol}]"

    print(f"Проверка прокси {label} ...")

    try:
        direct_ip = get_direct_ip()
    except Exception as e:
        print(f"  Не удалось получить прямой IP: {e}. Пропускаю проверку.")
        return True

    try:
        proxy_ip = get_proxy_ip(proxy)
        if proxy_ip == direct_ip:
            print(f"  ✗ {label} — IP не изменился ({proxy_ip}), прокси не работает!")
            return False
        else:
            print(f"  ✓ {label} — OK (IP: {proxy_ip})")
            return True
    except Exception as e:
        err = str(e)
        if len(err) > 120:
            err = err[:120] + "..."
        print(f"  ✗ {label} — МЁРТВ: {err}")
        return False


if __name__ == "__main__":
    if len(sys.argv) == 3:
        # check_proxy.py <proxies.json> <index>
        ok = check_single(sys.argv[1], int(sys.argv[2]))
    else:
        # check_proxy.py <proxies.json>  — check all
        ok = check_all(sys.argv[1])

    sys.exit(0 if ok else 1)
