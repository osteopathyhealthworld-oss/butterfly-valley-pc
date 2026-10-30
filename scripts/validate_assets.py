"""Reject missing external textures/buffers before running Godot import."""
import json
from pathlib import Path
import struct
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"


def dependencies(path):
    if path.suffix == ".gltf":
        document = json.loads(path.read_text())
    else:
        data = path.read_bytes()
        if len(data) < 20 or data[:4] != b"glTF":
            raise ValueError("Invalid GLB: " + str(path))
        version, length, json_size, chunk_type = struct.unpack_from("<4I", data, 4)
        if version != 2 or length != len(data) or chunk_type != 0x4E4F534A:
            raise ValueError("Invalid GLB header: " + str(path))
        document = json.loads(data[20:20+json_size].rstrip(b"\x00 "))
    for item in document.get("buffers", []) + document.get("images", []):
        uri = item.get("uri", "")
        if not uri or uri.startswith("data:"):
            continue
        candidate = (path.parent / unquote(uri)).resolve()
        if not candidate.is_relative_to(GAME.resolve()) or not candidate.is_file():
            raise ValueError("Missing or unsafe dependency: {} -> {}".format(path, uri))


def main():
    count = 0
    for path in GAME.rglob("*"):
        if ".godot" in path.parts or path.suffix not in {".glb", ".gltf"}:
            continue
        dependencies(path)
        count += 1
    for name in ("paki-hero.glb", "bruno-builder.glb", "paki-farming.glb", "paki-shared.glb"):
        if not (GAME / "assets" / name).is_file():
            raise SystemExit("Не подготовлен персонаж: " + name)
    print("ASSET DEPENDENCIES PASS: {} models".format(count))


if __name__ == "__main__":
    main()
