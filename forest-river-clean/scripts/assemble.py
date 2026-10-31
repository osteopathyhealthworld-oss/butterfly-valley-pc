#!/usr/bin/env python3
"""Assemble a clean Godot project with licensed glTF assets only."""
from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

SOURCE_URL = "https://github.com/GamesNotDeveloped/godot-forest-demo.git"
SOURCE_COMMIT = "623212ffeb4efbf4c95323a4a6a57e726be4f6e9"
HERE = Path(__file__).resolve().parents[1]
ASSET_FOLDERS = ("pine-tree-1", "pine-tree-3", "birch-tree-1")


def prepare(source: Path, destination: Path) -> None:
    if destination.exists() and any(destination.iterdir()):
        raise ValueError(f"Destination must be empty: {destination}")
    shutil.copytree(HERE / "godot", destination, dirs_exist_ok=True)
    for tree in ASSET_FOLDERS:
        original = source / "objects" / tree
        target = destination / "objects" / tree
        if not (original / "scene.gltf").is_file():
            raise ValueError(f"Missing tree scene {original}")
        # Exclude original import presets, external shader materials and game logic.
        for file in original.rglob("*"):
            if file.is_file() and file.suffix.lower() in (".gltf", ".bin", ".png", ".jpg", ".jpeg", ".txt"):
                dest_file = target / file.relative_to(original)
                dest_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(file, dest_file)
    shutil.copy2(HERE / "README.md", destination / "README.md")
    shutil.copy2(HERE / "export_presets.cfg", destination / "export_presets.cfg")
    print("Prepared independent clean Godot project:", destination)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, help="Downloaded upstream source directory")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.source:
        prepare(args.source.resolve(), args.output.resolve())
        return
    with tempfile.TemporaryDirectory(prefix="forest-assets-") as tmp:
        source = Path(tmp) / "source"
        subprocess.run(["git", "clone", "--depth", "1", SOURCE_URL, str(source)], check=True)
        head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        if head != SOURCE_COMMIT:
            subprocess.run(["git", "-C", str(source), "fetch", "--depth", "1", "origin", SOURCE_COMMIT], check=True)
            subprocess.run(["git", "-C", str(source), "checkout", "--detach", "FETCH_HEAD"], check=True)
        prepare(source, args.output.resolve())


if __name__ == "__main__":
    main()
