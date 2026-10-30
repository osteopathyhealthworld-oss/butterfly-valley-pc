#!/usr/bin/env python3
"""Install the small, pinned CC BY 4.0 forest-art prototype.

The source game uses Godot 4.6, but only its original glTF art is downloaded.
No addons, scripts, music, or other third-party assets are copied.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "game/forest-art-manifest.json"
ASSET_ROOT = (ROOT / "game/assets/forest").resolve()


def _verified(data: bytes, entry: dict) -> bool:
    digest = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    return len(data) == entry["bytes"] and digest == entry["git_sha1"]


def _target(entry: dict) -> Path:
    name = entry["destination"]
    parts = PurePosixPath(name)
    if parts.is_absolute() or ".." in parts.parts or "\\" in name:
        raise ValueError("Unsafe asset destination: " + name)
    target = (ROOT / name).resolve()
    if not target.is_relative_to(ASSET_ROOT):
        raise ValueError("Asset outside forest directory: " + name)
    return target


def load_manifest() -> dict:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if manifest.get("schema") != 1:
        raise ValueError("Unknown forest asset manifest format")
    repository = manifest["repository"]
    revision = manifest["revision"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Unsafe repository")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Forest art must be pinned to a commit")
    if manifest["license"] != "CC-BY-4.0":
        raise ValueError("Unexpected forest art license")
    seen = set()
    for entry in manifest["files"]:
        source = entry["source"]
        parts = PurePosixPath(source)
        if parts.is_absolute() or ".." in parts.parts or "\\" in source:
            raise ValueError("Unsafe source path: " + source)
        if not source.startswith("objects/pine-tree-1/"):
            raise ValueError("Unexpected source asset")
        target = _target(entry)
        if target in seen:
            raise ValueError("Duplicate asset path")
        seen.add(target)
        if type(entry["bytes"]) is not int or not 0 < entry["bytes"] < 10_000_000:
            raise ValueError("Invalid asset size")
        if not re.fullmatch(r"[0-9a-f]{40}", entry["git_sha1"]):
            raise ValueError("Invalid Git blob digest")
    if len(seen) != 9:
        raise ValueError("Pine model must include glTF, binary, six PBR textures and license")
    return manifest


def fetch_one(manifest: dict, entry: dict) -> bool:
    target = _target(entry)
    if target.is_file() and _verified(target.read_bytes(), entry):
        return False
    url = (
        "https://raw.githubusercontent.com/"
        + manifest["repository"] + "/" + manifest["revision"] + "/" + entry["source"]
    )
    request = Request(url, headers={"User-Agent": "ButterflyValley-CCBY-Forest-Art"})
    try:
        with urlopen(request, timeout=90) as response:
            data = response.read(entry["bytes"] + 1)
    except (HTTPError, URLError, TimeoutError) as error:
        raise RuntimeError("Cannot download licensed forest asset " + entry["source"]) from error
    if not _verified(data, entry):
        raise RuntimeError("Size/hash mismatch for " + entry["source"])
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".download")
    try:
        temporary.write_bytes(data)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="Download missing or changed files")
    parser.add_argument("--check", action="store_true", help="Check downloaded art without network")
    options = parser.parse_args()
    manifest = load_manifest()
    if options.fetch:
        downloaded = sum(fetch_one(manifest, item) for item in manifest["files"])
        print(f"FOREST ART READY: {len(manifest['files'])} verified files, {downloaded} fetched")
        return 0
    if options.check:
        missing = [item["source"] for item in manifest["files"]
                   if not _target(item).is_file() or not _verified(_target(item).read_bytes(), item)]
        if missing:
            raise SystemExit("FOREST ART MISSING / CORRUPT: " + ", ".join(missing))
        print("FOREST ART VERIFIED")
        return 0
    print(f"FOREST MANIFEST OK: {len(manifest['files'])} pinned CC BY 4.0 files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
