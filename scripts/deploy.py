#!/usr/bin/env python3
# Deploy Mihomo/Clash core persistently on the known 5GCPE OpenWrt target.

from __future__ import annotations

import argparse
import gzip
import hashlib
import getpass
import json
import os
import re
import shutil
import sys
import time
import urllib.request
from pathlib import Path
from typing import Tuple

try:
    import paramiko
except ImportError:
    print("ERROR: paramiko is required. Install with: python -m pip install paramiko", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parents[1]
ROUTER = ROOT / "router"
RULESET = ROOT / "ruleset"
CACHE = ROOT / ".cache"
RESOURCES = ROOT / "resources"
BUNDLED_MANIFEST = RESOURCES / "manifest.json"
REMOTE_DIR = "/data/clash"
DEFAULT_HOST = os.environ.get("SSH_IP", "192.168.8.1")
DEFAULT_USER = os.environ.get("SSH_USER", "root")
DEFAULT_PASSWORD = os.environ.get("SSH_PASSWORD", "")
DEFAULT_RELEASE = "v1.19.28"
GITHUB_API = "https://api.github.com/repos/MetaCubeX/mihomo/releases"


def info(msg: str) -> None:
    print(f"[+] {msg}")


def warn(msg: str) -> None:
    print(f"[!] {msg}")


def die(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def connect(args):
    if not args.password:
        args.password = getpass.getpass(f"SSH password for {args.user}@{args.host}: ")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    info(f"connecting {args.user}@{args.host}:{args.port}")
    client.connect(
        hostname=args.host,
        port=args.port,
        username=args.user,
        password=args.password,
        timeout=args.timeout,
        banner_timeout=args.timeout,
        auth_timeout=args.timeout,
        look_for_keys=False,
        allow_agent=False,
    )
    return client


def run(client, cmd: str, check: bool = True, timeout: int = 60, show: bool = True) -> Tuple[int, str, str]:
    if show:
        info(f"remote$ {cmd}")
    stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    rc = stdout.channel.recv_exit_status()
    if out.strip():
        print(out.rstrip())
    if err.strip():
        print(err.rstrip(), file=sys.stderr)
    if check and rc != 0:
        die(f"remote command failed rc={rc}: {cmd}")
    return rc, out, err


def sh_quote(s: str) -> str:
    return "'" + s.replace("'", "'\"'\"'") + "'"


def remote_upload_bytes(client, remote_path: str, data: bytes, mode: int = 0o755) -> None:
    # Dropbear on this device has no SFTP subsystem, so upload over plain SSH stdin.
    tmp = f"{remote_path}.tmp.{int(time.time())}"
    q_tmp = sh_quote(tmp)
    q_dst = sh_quote(remote_path)
    cmd = f"cat > {q_tmp} && chmod {mode:o} {q_tmp} && rm -f {q_dst} && mv {q_tmp} {q_dst} && chmod {mode:o} {q_dst}"
    stdin, stdout, stderr = client.exec_command(cmd, timeout=180)
    chan = stdin.channel
    for off in range(0, len(data), 32768):
        chan.sendall(data[off:off + 32768])
    chan.shutdown_write()
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    rc = stdout.channel.recv_exit_status()
    if out.strip():
        print(out.rstrip())
    if err.strip():
        print(err.rstrip(), file=sys.stderr)
    if rc != 0:
        die(f"upload failed rc={rc}: {remote_path}")


def remote_write_text(client, remote_path: str, text: str, mode: int = 0o755) -> None:
    remote_upload_bytes(client, remote_path, text.encode("utf-8"), mode)


def remote_upload_file(client, local_path: Path, remote_path: str, mode: int = 0o755) -> None:
    with local_path.open("rb") as f:
        data = f.read()
    remote_upload_bytes(client, remote_path, data, mode)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "codex-5gcpe-mihomo-persist"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def select_asset(release: dict) -> dict:
    assets = release.get("assets") or []
    candidates = []
    for a in assets:
        name = a.get("name", "")
        if re.fullmatch(r"mihomo-linux-arm64-v[0-9].*\.gz", name):
            candidates.append(a)
    if not candidates:
        names = "\n".join(a.get("name", "") for a in assets[:80])
        die("no linux-arm64 .gz asset found in release. First assets:\n" + names)
    candidates.sort(key=lambda a: a.get("name", ""))
    return candidates[0]


def download_mihomo(release_arg: str) -> Tuple[Path, str, str]:
    CACHE.mkdir(exist_ok=True)
    if release_arg == "latest":
        rel = http_json(GITHUB_API + "/latest")
    else:
        rel = http_json(GITHUB_API + "/tags/" + release_arg)
    tag = rel.get("tag_name", release_arg)
    asset = select_asset(rel)
    name = asset["name"]
    url = asset["browser_download_url"]
    digest = asset.get("digest") or ""
    gz_path = CACHE / name
    bin_path = CACHE / name[:-3]
    info(f"selected mihomo {tag}: {name}")
    if not gz_path.exists() or gz_path.stat().st_size != int(asset.get("size", 0) or 0):
        info(f"downloading {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "codex-5gcpe-mihomo-persist"})
        with urllib.request.urlopen(req, timeout=180) as r, gz_path.open("wb") as f:
            shutil.copyfileobj(r, f)
    else:
        info(f"using cached {gz_path}")
    if digest.startswith("sha256:"):
        got = sha256_file(gz_path)
        want = digest.split(":", 1)[1].lower()
        if got.lower() != want:
            gz_path.unlink(missing_ok=True)
            die(f"download sha256 mismatch for {name}: got {got}, want {want}")
        info(f"download sha256 ok: {got}")
    if not bin_path.exists() or bin_path.stat().st_mtime < gz_path.stat().st_mtime:
        info(f"decompressing {gz_path.name}")
        tmp = bin_path.with_suffix(bin_path.suffix + ".tmp")
        with gzip.open(gz_path, "rb") as src, tmp.open("wb") as dst:
            shutil.copyfileobj(src, dst)
        tmp.replace(bin_path)
    os.chmod(bin_path, 0o755)
    return bin_path, tag, name


def bundled_mihomo() -> Tuple[Path, str, str]:
    if not BUNDLED_MANIFEST.exists():
        die(f"bundled manifest not found: {BUNDLED_MANIFEST}")
    manifest = json.loads(BUNDLED_MANIFEST.read_text(encoding="utf-8"))
    asset = manifest["asset"]
    tag = manifest.get("version", DEFAULT_RELEASE)
    want_sha = str(manifest.get("sha256", "")).lower()
    gz_path = RESOURCES / asset
    if not gz_path.exists():
        die(f"bundled mihomo asset not found: {gz_path}")
    got_sha = sha256_file(gz_path).lower()
    if want_sha and got_sha != want_sha:
        die(f"bundled asset sha256 mismatch: got {got_sha}, want {want_sha}")
    CACHE.mkdir(exist_ok=True)
    bin_path = CACHE / asset[:-3]
    if not bin_path.exists() or bin_path.stat().st_mtime < gz_path.stat().st_mtime:
        info(f"decompressing bundled {gz_path.name}")
        tmp = bin_path.with_suffix(bin_path.suffix + ".tmp")
        with gzip.open(gz_path, "rb") as src, tmp.open("wb") as dst:
            shutil.copyfileobj(src, dst)
        tmp.replace(bin_path)
    os.chmod(bin_path, 0o755)
    info(f"using bundled mihomo {tag}: {asset}")
    info(f"bundled sha256 ok: {got_sha}")
    return bin_path, tag, asset


def get_mihomo_file(args) -> Tuple[Path, str, str]:
    if args.mihomo_file:
        p = Path(args.mihomo_file).expanduser().resolve()
        if not p.exists():
            die(f"mihomo file not found: {p}")
        return p, "local", p.name
    if not args.download:
        return bundled_mihomo()
    return download_mihomo(args.release)


def preflight(client, no_autostart: bool = False) -> None:
    info("preflight check")
    run(client, "uname -a; echo arch=$(uname -m); df -h /data 2>/dev/null || df /data", timeout=30)
    rc, out, _ = run(client, "uname -m", show=False)
    arch = out.strip()
    if arch != "aarch64":
        die(f"target arch is {arch!r}, expected aarch64")
    run(client, "test -d /data && touch /data/.codex_mihomo_rw && rm -f /data/.codex_mihomo_rw", timeout=30)
    if not no_autostart:
        rc, _, _ = run(client, "test -x /data/ssh_persist.sh", check=False, show=False)
        if rc != 0:
            die("/data/ssh_persist.sh not found/executable; cannot attach autostart chain")
        rc, _, _ = run(client, "test -f /data/config/collectd -a -f /data/collectd/uptime.so", check=False, show=False)
        if rc != 0:
            warn("collectd persistence files not found; /data/ssh_persist.sh hook may not run at boot")


def patch_ssh_persist(client) -> None:
    script = r'''#!/bin/sh
set -u
FILE=/data/ssh_persist.sh
BEGIN='# BEGIN CODEX_MIHOMO_PERSIST'
END='# END CODEX_MIHOMO_PERSIST'
[ -f "$FILE" ] || { echo "missing $FILE" >&2; exit 1; }
TS=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
[ -f /data/ssh_persist.sh.codex_mihomo.orig ] || cp "$FILE" /data/ssh_persist.sh.codex_mihomo.orig
cp "$FILE" "/data/ssh_persist.sh.codex_mihomo.bak.$TS"
awk -v b="$BEGIN" -v e="$END" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  !skip {print}
' "$FILE" > /tmp/ssh_persist.nohook
cat > /tmp/codex_mihomo_hook <<'EOF'
# BEGIN CODEX_MIHOMO_PERSIST
if [ -x /data/service_persist.sh ]; then
  /bin/sh /data/service_persist.sh >> /tmp/codex_service_persist.log 2>&1 &
fi
# END CODEX_MIHOMO_PERSIST
EOF
awk -v hookfile=/tmp/codex_mihomo_hook '
function print_hook() {
  while ((getline l < hookfile) > 0) print l
  close(hookfile)
}
{
  if (!done && $0 ~ /^exit[ \t]+0[ \t]*$/) { print_hook(); done=1 }
  print
}
END { if (!done) print_hook() }
' /tmp/ssh_persist.nohook > /tmp/ssh_persist.new
cat /tmp/ssh_persist.new > "$FILE"
chmod +x "$FILE"
rm -f /tmp/ssh_persist.nohook /tmp/ssh_persist.new /tmp/codex_mihomo_hook
if grep -q "CODEX_MIHOMO_PERSIST" "$FILE"; then
  echo "ssh_persist hook installed"
else
  echo "hook install failed" >&2
  exit 1
fi
'''
    remote_write_text(client, "/tmp/codex_patch_ssh_persist.sh", script, 0o755)
    run(client, "/bin/sh /tmp/codex_patch_ssh_persist.sh && rm -f /tmp/codex_patch_ssh_persist.sh", timeout=30)


def unpatch_ssh_persist(client, purge_backups: bool = False) -> None:
    purge = "1" if purge_backups else "0"
    script = rf'''#!/bin/sh
set -u
FILE=/data/ssh_persist.sh
BEGIN='# BEGIN CODEX_MIHOMO_PERSIST'
END='# END CODEX_MIHOMO_PERSIST'
if [ -f "$FILE" ]; then
  TS=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
  cp "$FILE" "/data/ssh_persist.sh.codex_mihomo.uninstall.bak.$TS" 2>/dev/null || true
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {{skip=1; next}}
    $0==e {{skip=0; next}}
    !skip {{print}}
  ' "$FILE" > /tmp/ssh_persist.unhook
  cat /tmp/ssh_persist.unhook > "$FILE"
  chmod +x "$FILE"
  rm -f /tmp/ssh_persist.unhook
fi
if [ -f /data/service_persist.sh ] && grep -q 'CODEX_MIHOMO_SERVICE' /data/service_persist.sh 2>/dev/null; then
  rm -f /data/service_persist.sh
fi
if [ "{purge}" = "1" ]; then
  rm -f /data/ssh_persist.sh.codex_mihomo.orig /data/ssh_persist.sh.codex_mihomo.bak.* /data/ssh_persist.sh.codex_mihomo.uninstall.bak.* 2>/dev/null || true
fi
rm -f /tmp/codex_service_persist.log /tmp/codex_mihomo_watchdog.pid /tmp/codex_mihomo_watchdog.out 2>/dev/null || true
echo "ssh_persist hook removed"
'''
    remote_write_text(client, "/tmp/codex_unpatch_ssh_persist.sh", script, 0o755)
    run(client, "/bin/sh /tmp/codex_unpatch_ssh_persist.sh && rm -f /tmp/codex_unpatch_ssh_persist.sh", timeout=30)



def upload_ruleset_files(client) -> None:
    if not RULESET.exists():
        return
    files = [p for p in RULESET.rglob("*") if p.is_file() and p.name.lower() != "readme.md"]
    if not files:
        return
    info(f"uploading rule-provider files: {len(files)}")
    run(client, f"mkdir -p {REMOTE_DIR}/ruleset", timeout=30)
    for path in files:
        rel = path.relative_to(RULESET).as_posix()
        remote = f"{REMOTE_DIR}/ruleset/{rel}"
        parent = remote.rsplit("/", 1)[0]
        run(client, f"mkdir -p {sh_quote(parent)}", timeout=30, show=False)
        remote_upload_file(client, path, remote, 0o644)

def upload_router_files(client, mihomo_bin: Path, config_path: Path, overwrite_config: bool = False) -> None:
    run(client, f"mkdir -p {REMOTE_DIR}/logs {REMOTE_DIR}/run {REMOTE_DIR}/ui {REMOTE_DIR}/ruleset", timeout=30)
    info("uploading router scripts")
    for name in ["start_clash.sh", "stop_clash.sh", "watchdog_clash.sh", "operator_policy_dns.sh", "operator_policy_dns_watchdog.sh"]:
        remote_upload_file(client, ROUTER / name, f"{REMOTE_DIR}/{name}", 0o755)
    remote_upload_file(client, ROUTER / "service_persist.sh", "/data/service_persist.sh", 0o755)

    info(f"uploading mihomo binary: {mihomo_bin.name}")
    remote_upload_file(client, mihomo_bin, f"{REMOTE_DIR}/mihomo", 0o755)

    upload_ruleset_files(client)

    rc, _, _ = run(client, f"test -f {REMOTE_DIR}/config.yaml", check=False, show=False)
    exists = (rc == 0)
    if exists and not overwrite_config:
        info("remote config.yaml exists; preserving it (use --overwrite-config to replace)")
    else:
        if exists and overwrite_config:
            run(client, f"cp {REMOTE_DIR}/config.yaml {REMOTE_DIR}/config.yaml.bak.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)", check=False, timeout=30)
        info(f"uploading config: {config_path}")
        remote_upload_file(client, config_path, f"{REMOTE_DIR}/config.yaml", 0o644)
    remote_write_text(client, f"{REMOTE_DIR}/enabled", "enabled\n", 0o644)
    manifest = {
        "installed_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "repo": str(ROOT),
        "remote_dir": REMOTE_DIR,
        "mihomo_sha256": sha256_file(mihomo_bin),
    }
    remote_write_text(client, f"{REMOTE_DIR}/install_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", 0o644)


def cleanup_tun_state(client) -> None:
    cmd = r'''for i in 1 2 3 4 5; do
  ip rule del pref 9000 2>/dev/null || true
  ip rule del pref 9001 2>/dev/null || true
  ip rule del pref 9002 2>/dev/null || true
  ip rule del pref 9010 2>/dev/null || true
done
ip route flush table 2022 2>/dev/null || true
ip link set mihomo down 2>/dev/null || true
ip link del mihomo 2>/dev/null || true
'''
    run(client, cmd, check=False, timeout=30, show=False)



def upload_operator_policy_dns_scripts(client) -> None:
    run(client, f"mkdir -p {REMOTE_DIR}/logs {REMOTE_DIR}/operator_policy_dns", timeout=30)
    for name in ["operator_policy_dns.sh", "operator_policy_dns_watchdog.sh"]:
        remote_upload_file(client, ROUTER / name, f"{REMOTE_DIR}/{name}", 0o755)
    remote_upload_file(client, ROUTER / "service_persist.sh", "/data/service_persist.sh", 0o755)


def operator_policy_dns(args, action: str) -> None:
    client = connect(args)
    try:
        upload_operator_policy_dns_scripts(client)
        if action == "disable":
            run(client, f"/bin/sh {REMOTE_DIR}/operator_policy_dns.sh disable", timeout=60)
            run(client, "/bin/sh /data/service_persist.sh", timeout=30)
        elif action == "restore":
            run(client, "[ -f /tmp/codex_operator_policy_dns_watchdog.pid ] && kill $(cat /tmp/codex_operator_policy_dns_watchdog.pid 2>/dev/null) 2>/dev/null || true; rm -f /tmp/codex_operator_policy_dns_watchdog.pid /tmp/codex_operator_policy_dns_watchdog.out", check=False, timeout=30)
            run(client, f"/bin/sh {REMOTE_DIR}/operator_policy_dns.sh restore", timeout=60)
        elif action == "status":
            run(client, f"/bin/sh {REMOTE_DIR}/operator_policy_dns.sh status", timeout=60)
        else:
            die(f"unknown operator policy dns action: {action}")
    finally:
        client.close()

def wait_ready(client, timeout: int = 90) -> None:
    info(f"waiting for mihomo/controller ready (timeout={timeout}s)")
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        rc, out, _ = run(
            client,
            r'''pid=$(pidof mihomo 2>/dev/null | awk '{print $1}')
ports=$(netstat -lntp 2>/dev/null | grep -E '(:7890|:9090|:7874)' || true)
ver=$(wget -qO- http://127.0.0.1:9090/version 2>/dev/null || true)
echo "pid=$pid"
echo "$ports"
echo "version=$ver"
test -n "$pid" && echo "$ports" | grep -q ':7890' && echo "$ports" | grep -q ':9090' && echo "$ver" | grep -q '"version"' ''',
            check=False,
            timeout=15,
            show=False,
        )
        last = out.strip()
        if rc == 0:
            print(last)
            info("mihomo is ready")
            return
        time.sleep(3)
    print(last)
    die("mihomo did not become ready before timeout")


def install(args) -> None:
    client = connect(args)
    try:
        preflight(client, no_autostart=args.no_autostart)
        mihomo_bin, tag, asset_name = get_mihomo_file(args)
        if args.config:
            config_path = Path(args.config).expanduser().resolve()
        else:
            local_config = ROOT / "config.yaml"
            config_path = local_config if local_config.exists() else ROOT / "config.example.yaml"
        if not config_path.exists():
            die(f"config not found: {config_path}")
        run(client, f"[ -x {REMOTE_DIR}/stop_clash.sh ] && /bin/sh {REMOTE_DIR}/stop_clash.sh || true", check=False, timeout=30)
        upload_router_files(client, mihomo_bin, config_path, overwrite_config=args.overwrite_config)
        if not args.no_autostart:
            patch_ssh_persist(client)
        cleanup_tun_state(client)
        run(client, "/bin/sh /data/service_persist.sh", timeout=30)
        if not args.no_wait:
            wait_ready(client, timeout=args.wait_timeout)
        else:
            time.sleep(2)
        status(args, existing_client=client)
        info("install completed")
    finally:
        client.close()


def uninstall(args) -> None:
    client = connect(args)
    try:
        run(client, f"[ -x {REMOTE_DIR}/stop_clash.sh ] && /bin/sh {REMOTE_DIR}/stop_clash.sh || true", check=False, timeout=30)
        cleanup_tun_state(client)
        unpatch_ssh_persist(client, purge_backups=args.purge_backups)
        run(client, f"rm -rf {REMOTE_DIR}", timeout=60)
        run(client, "rm -f /tmp/codex_mihomo* /tmp/codex_service_persist.log 2>/dev/null || true", check=False)
        status(args, existing_client=client, check=False)
        info("uninstall completed")
    finally:
        client.close()


def restart(args) -> None:
    client = connect(args)
    try:
        run(client, f"[ -x {REMOTE_DIR}/stop_clash.sh ] && /bin/sh {REMOTE_DIR}/stop_clash.sh || true", check=False, timeout=30)
        cleanup_tun_state(client)
        run(client, "/bin/sh /data/service_persist.sh", timeout=30)
        if not args.no_wait:
            wait_ready(client, timeout=args.wait_timeout)
        else:
            time.sleep(2)
        status(args, existing_client=client)
    finally:
        client.close()


def status(args, existing_client=None, check: bool = True) -> None:
    client = existing_client or connect(args)
    try:
        cmd = r'''echo '--- system ---'
uname -a 2>/dev/null || true
cat /etc/openwrt_release 2>/dev/null | sed -n '1,12p' || true
echo '--- files ---'
ls -ld /data /data/clash /data/clash/logs /data/clash/run 2>/dev/null || true
ls -l /data/clash/mihomo /data/clash/config.yaml /data/clash/enabled /data/service_persist.sh 2>/dev/null || true
echo '--- hook ---'
if [ -f /data/ssh_persist.sh ]; then grep -n 'CODEX_MIHOMO_PERSIST' /data/ssh_persist.sh 2>/dev/null || echo 'no hook'; else echo 'no /data/ssh_persist.sh'; fi
echo '--- version ---'
/data/clash/mihomo -v 2>/dev/null || true
echo '--- tun/dns capability ---'
ls -l /dev/net /dev/net/tun 2>/dev/null || true
[ -c /dev/net/tun ] && echo 'TUN_DEVICE=YES' || echo 'TUN_DEVICE=NO'
ip link show mihomo 2>/dev/null || true
ip rule show 2>/dev/null | sed -n '1,20p' || true
ip route show 2>/dev/null | sed -n '1,25p' || true
echo '--- config mode ---'
awk 'BEGIN{s=0} /^(tun|dns|rule-providers|rules):/{s=1;print;next} /^[^ #].*:/{if(s){s=0}} s{print}' /data/clash/config.yaml 2>/dev/null | sed -n '1,140p' || true
echo '--- process ---'
ps 2>/dev/null | grep -E '[m]ihomo|[w]atchdog_clash' || true
echo '--- ports ---'
netstat -lntp 2>/dev/null | grep -E '(:7890|:9090|:7874)' || true
echo '--- iptables ---'
iptables -S CODEX_MIHOMO_INPUT 2>/dev/null || true
echo '--- recent clash log ---'
tail -n 40 /data/clash/logs/clash.log 2>/dev/null || true
echo '--- recent watchdog log ---'
tail -n 20 /data/clash/logs/watchdog.log 2>/dev/null || true
'''
        run(client, cmd, check=False, timeout=60)
    finally:
        if existing_client is None:
            client.close()


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Deploy persistent Mihomo core to 5GCPE OpenWrt /data")
    p.add_argument("action", choices=["install", "uninstall", "status", "restart", "operator-disable", "operator-restore", "operator-status"])
    p.add_argument("--host", default=DEFAULT_HOST)
    p.add_argument("--port", type=int, default=int(os.environ.get("SSH_PORT", "22")))
    p.add_argument("--user", default=DEFAULT_USER)
    p.add_argument("--password", default=DEFAULT_PASSWORD)
    p.add_argument("--timeout", type=int, default=15)
    p.add_argument("--release", default=DEFAULT_RELEASE, help="mihomo release tag used only with --download")
    p.add_argument("--download", action="store_true", help="download mihomo from MetaCubeX instead of using bundled resources")
    p.add_argument("--mihomo-file", default="", help="local decompressed mihomo binary to upload")
    p.add_argument("--config", default="", help="local config.yaml to upload on first install")
    p.add_argument("--overwrite-config", action="store_true", help="overwrite remote /data/clash/config.yaml")
    p.add_argument("--no-autostart", action="store_true", help="do not patch /data/ssh_persist.sh")
    p.add_argument("--no-wait", action="store_true", help="do not wait for ports/controller after install/restart")
    p.add_argument("--wait-timeout", type=int, default=90, help="seconds to wait for mihomo readiness")
    p.add_argument("--purge-backups", action="store_true", help="remove ssh_persist backup files during uninstall")
    return p


def main(argv=None) -> None:
    args = build_parser().parse_args(argv)
    if args.action == "install":
        install(args)
    elif args.action == "uninstall":
        uninstall(args)
    elif args.action == "restart":
        restart(args)
    elif args.action == "status":
        status(args)
    elif args.action == "operator-disable":
        operator_policy_dns(args, "disable")
    elif args.action == "operator-restore":
        operator_policy_dns(args, "restore")
    elif args.action == "operator-status":
        operator_policy_dns(args, "status")
    else:
        die("unknown action")


if __name__ == "__main__":
    main()
