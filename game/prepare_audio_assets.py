#!/usr/bin/env python3
"""Reproducible CC0 soundtrack download for the Godot desktop release.

The public repository keeps a complete catalogue and a small playable sample.
Only the curated subset is fetched during Windows packaging. Every downloaded
byte is checked against the original Git blob SHA and recorded file size.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
AUDIO = ROOT / "assets" / "audio"
CATALOG = AUDIO / "catalog.json"
SELECTION = ROOT / "audio-selection.json"
PINNED = {
    "https://github.com/newrare/gamedustry": (
        "newrare/gamedustry", "a498ee88245e60843f555318b25d78846d173837"
    ),
    "https://github.com/euuuuuuan/moonshard-warden-public": (
        "euuuuuuan/moonshard-warden-public",
        "897d26af64aab4003b057b3910a7118279b927d8",
    ),
}


def git_blob_sha(data: bytes) -> str:
    header = b"blob " + str(len(data)).encode("ascii") + b"\0"
    return hashlib.sha1(header + data).hexdigest()


def checked_items() -> list[dict]:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    selection = json.loads(SELECTION.read_text(encoding="utf-8"))
    indexed = {
        entry["path"]: entry
        for entry in catalog["audio"] + catalog["music"]
    }
    requested = selection["sfx"] + selection["music"]
    if len(requested) != len(set(requested)) or not requested:
        raise ValueError("Audio selection contains duplicates or is empty")
    items = []
    for name in requested:
        path = Path(name)
        if (path.is_absolute() or ".." in path.parts or len(path.parts) != 2
                or path.parts[0] not in {"sfx", "music"}
                or path.suffix.lower() not in {".ogg", ".mp3"}):
            raise ValueError("Unsafe audio path: " + name)
        entry = indexed.get(name)
        if entry is None:
            raise ValueError("Missing audio catalogue entry: " + name)
        if entry["license"] != "CC0 1.0":
            raise ValueError("Unapproved audio licence: " + name)
        if entry["upstreamRepository"] not in PINNED:
            raise ValueError("Unpinned audio source: " + name)
        if not isinstance(entry["bytes"], int) or entry["bytes"] <= 0:
            raise ValueError("Invalid source byte count: " + name)
        sha = entry["gitBlobSha"]
        if len(sha) != 40 or any(c not in "0123456789abcdef" for c in sha):
            raise ValueError("Invalid Git blob hash: " + name)
        upstream = Path(entry["upstreamPath"])
        if upstream.is_absolute() or ".." in upstream.parts:
            raise ValueError("Unsafe upstream audio path: " + name)
        items.append(entry)
    return items


def validate_bytes(entry: dict, data: bytes) -> None:
    if len(data) != entry["bytes"]:
        raise ValueError(f"Audio size mismatch: {entry['path']}")
    if git_blob_sha(data) != entry["gitBlobSha"]:
        raise ValueError(f"Audio Git blob mismatch: {entry['path']}")


def fetch_one(entry: dict) -> str:
    target = AUDIO / entry["path"]
    if target.exists():
        validate_bytes(entry, target.read_bytes())
        return "kept"
    repo, revision = PINNED[entry["upstreamRepository"]]
    path = quote(entry["upstreamPath"], safe="/")
    url = f"https://raw.githubusercontent.com/{repo}/{revision}/{path}"
    request = Request(url, headers={"User-Agent": "ButterflyValley-CC0-Asset-Builder"})
    failure = None
    for attempt in range(3):
        try:
            with urlopen(request, timeout=45) as response:
                raw = response.read(entry["bytes"] + 1)
            validate_bytes(entry, raw)
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(target.name + ".download")
            temporary.write_bytes(raw)
            temporary.replace(target)
            return "downloaded"
        except (HTTPError, URLError, TimeoutError, ValueError) as exc:
            failure = exc
            if attempt < 2:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Unable to fetch {entry['path']}: {failure}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="Offline integrity and licence check (default)")
    parser.add_argument("--fetch", action="store_true",
                        help="Download the curated CC0 selection")
    args = parser.parse_args()
    entries = checked_items()
    total = sum(entry["bytes"] for entry in entries)
    if args.fetch:
        with ThreadPoolExecutor(max_workers=6) as pool:
            futures = [pool.submit(fetch_one, entry) for entry in entries]
            results = [future.result() for future in as_completed(futures)]
        print(f"AUDIO READY: {len(entries)} files; "
              f"{results.count('downloaded')} downloaded, "
              f"{results.count('kept')} verified; {total} bytes")
    else:
        present = 0
        for entry in entries:
            file_path = AUDIO / entry["path"]
            if file_path.is_file():
                validate_bytes(entry, file_path.read_bytes())
                present += 1
        print(f"AUDIO CATALOGUE PASS: {len(entries)} selected CC0 assets, "
              f"{present} already present, {total} total bytes")


if __name__ == "__main__":
    main()
