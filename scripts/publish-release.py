#!/usr/bin/env python3
"""Stage public release files from local assets and committed source, without GitHub."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

BASE_URL = "https://www.ailyre.com/omniclock"
FILES = (
    "TokenClock-glass-universal.tar.gz", "TokenClock-normal-universal.tar.gz",
    "TokenClock-windows-x86_64.zip", "TokenClock-windows-x86_64.zip.sha256",
    "TokenClock-x86_64.AppImage", "TokenClock-x86_64.AppImage.sha256",
)


def version_key(tag):
    if not re.fullmatch(r"(?:omniclock-)?v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
        raise ValueError("Expected a stable vX.Y.Z version")
    branded = tag.startswith("omniclock-")
    plain = tag.removeprefix("omniclock-")
    return (int(branded),) + tuple(map(int, plain[1:].split(".")))


def digest(path):
    hasher = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def atomic_write(path, body):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(body)
            os.fchmod(stream.fileno(), 0o644)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def publish(version, assets_dir, output, repo, source_refs=(), without_windows=False, only_glass=False):
    version_key(version)
    assets_dir, output, repo = Path(assets_dir), Path(output), Path(repo)
    assets = []
    files = ("TokenClock-glass-universal.tar.gz",) if only_glass else tuple(name for name in FILES if not (without_windows and "windows" in name))
    for name in files:
        source = assets_dir / name
        if not source.is_file() or source.stat().st_size == 0:
            raise ValueError(f"Missing asset: {name}")
        assets.append({"name": name, "size": source.stat().st_size,
                       "digest": "sha256:" + digest(source),
                       "browser_download_url": f"{BASE_URL}/releases/download/{version}/{name}"})
    for name in files:
        if name.endswith(".sha256"):
            if (assets_dir / name).read_text().split()[0].lower() != digest(assets_dir / name[:-7]):
                raise ValueError(f"Checksum mismatch: {name}")
    target = output / "releases" / "download" / version
    # Never silently replace an already-published version with different bytes.
    for asset in assets:
        existing = target / asset["name"]
        if existing.exists() and "sha256:" + digest(existing) != asset["digest"]:
            raise ValueError(f"Published asset differs: {asset['name']}")
    target.mkdir(parents=True, exist_ok=True)
    for asset in assets:
        destination = target / asset["name"]
        if not destination.exists():
            shutil.copyfile(assets_dir / asset["name"], destination)
        destination.chmod(0o644)
    # Keep legacy package names for installed helpers; public downloads use OmniClock.
    visible_assets = assets
    if version.startswith("omniclock-"):
        visible_assets = []
        for original in list(assets):
            canonical = original["name"].replace("TokenClock", "OmniClock", 1)
            payload = (target / original["name"]).read_bytes()
            if canonical.endswith(".sha256"):
                payload = payload.replace(b"TokenClock", b"OmniClock")
            destination = target / canonical
            if destination.exists() and destination.read_bytes() != payload:
                raise ValueError(f"Published asset differs: {canonical}")
            atomic_write(destination, payload)
            visible_assets.append({"name": canonical, "size": len(payload),
                "digest": "sha256:" + digest(destination),
                "browser_download_url": f"{BASE_URL}/releases/download/{version}/{canonical}"})
        assets += visible_assets
    release = {"tag_name": version, "draft": False, "prerelease": False,
               "html_url": f"{BASE_URL}/releases/{version}/", "assets": assets}
    metadata = (json.dumps(release, indent=2) + "\n").encode()
    atomic_write(output / "releases" / f"{version}.json", metadata)
    links = "\n".join(f'<li><a href="{html.escape(a["browser_download_url"])}">'
                      f'{html.escape(a["name"])}</a><br><small>{a["digest"]}</small></li>' for a in visible_assets)
    windows_note = ('<p>Windows build pending. The Windows installer continues to provide '
                    'the previous verified build.</p>' if without_windows else '')
    scope_note = ('<p>This patch updates macOS Glass only. Other editions keep their previous verified releases.</p>' if only_glass else '')
    page = (f'<!doctype html><html lang="en"><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>OmniClock {version.removeprefix("omniclock-")}</title><body><h1>OmniClock {version.removeprefix("omniclock-")}</h1>'
            f'<p>Official downloads · SHA-256 verified packages</p>{scope_note}{windows_note}<ul>{links}</ul>'
            f'<p><a href="{BASE_URL}/install.sh">macOS / Linux installer</a> · '
            f'<a href="{BASE_URL}/install.ps1">Windows installer</a></p></body></html>')
    atomic_write(output / "releases" / version / "index.html", page.encode())
    for channel, ref in source_refs:
        if channel not in {"glass", "normal", "windows", "linux"}:
            raise ValueError(f"Unknown source channel: {channel}")
        source = output / "sources" / f"{channel}.tar.gz"
        source.parent.mkdir(parents=True, exist_ok=True)
        # git archive exports tracked, committed files only, never local WIP or credentials.
        subprocess.run(["git", "-C", str(repo), "archive", "--format=tar.gz",
                        "--prefix=TokenClock/", f"--output={source}", ref], check=True)
        source.chmod(0o644)
        atomic_write(Path(str(source) + ".sha256"), f"{digest(source)}  {source.name}\n".encode())
    for name in ("install.sh", "install.ps1", "omniclock"):
        body = subprocess.check_output(["git", "-C", str(repo), "show", f"HEAD:cli/{name}"])
        atomic_write(output / name, body)
        if name == "omniclock":
            atomic_write(output / "tokenclock", body)
    latest = output / "releases" / "latest.json"
    canonical_latest = output / "releases" / "omniclock-latest.json"
    comparison = canonical_latest if canonical_latest.exists() else latest
    if not comparison.exists() or version_key(json.loads(comparison.read_bytes())["tag_name"]) <= version_key(version):
        atomic_write(latest, metadata)
        if not without_windows and not only_glass:
            atomic_write(output / "releases" / "latest-windows.json", metadata)
        atomic_write(output / "releases" / "index.html", page.encode())
    print(f"Staged {version}: {len(assets)} assets; committed source only")
    return release


def stage_omniclock_feeds(output, release):
    """Keep old numeric-version clients able to discover the renamed product."""
    if not release["tag_name"].startswith("omniclock-"):
        return
    root = Path(output) / "releases"
    existing = root / "omniclock-latest.json"
    if existing.exists() and version_key(json.loads(existing.read_bytes())["tag_name"]) > version_key(release["tag_name"]):
        return
    canonical = (json.dumps(release, indent=2) + "\n").encode()
    legacy = dict(release, tag_name="v1.6.4", name="OmniClock " + release["tag_name"].removeprefix("omniclock-"),
                  product_version=release["tag_name"].removeprefix("omniclock-v"), migration_to=release["tag_name"])
    migration = (json.dumps(legacy, indent=2) + "\n").encode()
    for name in ("latest.json", "latest-windows.json"):
        atomic_write(root / ("omniclock-" + name), canonical)
        atomic_write(root / name, migration)
    page = (root / release["tag_name"] / "index.html").read_text()
    page = page.replace("<ul>", "<p>旧更新器中的 1.6.4 是迁移提示标识；实际安装 OmniClock " + legacy["product_version"] + "，保留已有设置和历史。</p><ul>", 1)
    atomic_write(root / "v1.6.4" / "index.html", page.encode())
    atomic_write(root / "v1.6.4.json", migration)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--assets-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--source-ref", action="append", default=[], metavar="CHANNEL=REF")
    parser.add_argument("--without-windows", action="store_true",
                        help="Publish macOS/Linux only; do not change the Windows latest pointer")
    parser.add_argument("--only-glass", action="store_true", help="Publish only the Glass patch; preserve all other channel artifacts and pointers")
    args = parser.parse_args()
    release = publish(args.version, args.assets_dir, args.output, args.repo,
            [value.split("=", 1) for value in args.source_ref], args.without_windows, args.only_glass)
    stage_omniclock_feeds(args.output, release)


if __name__ == "__main__":
    main()
