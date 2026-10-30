#!/usr/bin/env python3
"""Reconstruct a runnable Godot scene from a pinned open-source forest base."""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

SOURCE_REPO = "https://github.com/GamesNotDeveloped/godot-forest-demo.git"
SOURCE_COMMIT = "623212ffeb4efbf4c95323a4a6a57e726be4f6e9"
HERE = Path(__file__).resolve().parent.parent


def run(*argv: str) -> None:
    subprocess.run(list(argv), check=True)


def assemble(source: Path, output: Path) -> None:
    source = source.resolve()
    output = output.resolve()
    if not (source / "project.godot").is_file():
        raise ValueError(f"Missing Godot project: {source}")
    if source == output or source in output.parents or output in source.parents:
        raise ValueError("Source and output must be separate directories")
    if output.exists() and any(output.iterdir()):
        raise ValueError(f"Output directory is not empty: {output}")

    shutil.copytree(source, output, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".git", ".godot", ".codex", "*.tmp"))
    # The upstream example plays a separately licensed MP3; leave it out.
    music = output / "music"
    if music.exists():
        shutil.rmtree(music)
    shutil.copytree(HERE / "demo", output / "demo", dirs_exist_ok=True)

    scene = (output / "levels/test_biomes.tscn").read_text(encoding="utf-8")
    scene = scene.replace('res://levels/test_biomes.gd', 'res://demo/ForestRiverController.gd')
    scene = scene.replace('res://scenery/TerrainPatch3D.gd', 'res://demo/RiverTerrain.gd')
    # Resource UIDs from the original scripts otherwise take precedence over
    # the new path and silently reload the old scripts.
    scene = re.sub(r'(\[ext_resource type="Script") uid="uid://[^"]+"(?= path="res://demo/)',
                   r'\1', scene)
    scene = re.sub(r'^\[ext_resource[^\n]*res://music/[^\n]*\n', '', scene, flags=re.M)
    scene = re.sub(r'^\[node name="AudioStreamPlayer"[^\n]*\n(?:(?!\[node ).*\n)*',
                   '', scene, flags=re.M)
    scene = scene.replace('subdivisions_x = 160', 'subdivisions_x = 256')
    scene = scene.replace('subdivisions_z = 160', 'subdivisions_z = 256')
    scene = re.sub(r'^\[gd_scene[^\n]*', '[gd_scene format=3]', scene, count=1, flags=re.M)
    (output / "levels/forest_river_demo.tscn").write_text(scene, encoding="utf-8")
    # This duplicate original scene still refers to the intentionally removed
    # soundtrack; keeping it would break all-resources export.
    (output / "levels/test_biomes.tscn").unlink()

    project_path = output / "project.godot"
    project = project_path.read_text(encoding="utf-8")
    project = re.sub(r'config/name="[^"]+"', 'config/name="Forest & River | Godot Graphics Showcase"', project)
    project = re.sub(r'run/main_scene="[^"]+"', 'run/main_scene="res://levels/forest_river_demo.tscn"', project)
    project = project.replace('rendering_device/driver.windows="d3d12"',
                              'rendering_device/driver.windows="vulkan"')
    # These editor-only plugins are not needed to run or edit the demo and
    # can fail on first scan before icon textures finish importing.
    project = re.sub(r'^enabled=PackedStringArray\([^\n]*\)',
                     'enabled=PackedStringArray()', project, flags=re.M)
    project_path.write_text(project, encoding="utf-8")
    shutil.copy2(HERE / "windows_export_presets.cfg", output / "export_presets.cfg")
    shutil.copy2(HERE / "CREDITS.md", output / "CREDITS.md")
    shutil.copy2(HERE / "README.md", output / "FOREST_RIVER_README.md")
    shutil.copy2(HERE / "LICENSE-DEMO-MIT", output / "LICENSE-DEMO-MIT")
    print(f"Godot project ready: {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Previously downloaded upstream source")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.source:
        assemble(args.source, args.output)
        return
    with tempfile.TemporaryDirectory(prefix="forest-demo-source-") as folder:
        source = Path(folder) / "source"
        run("git", "clone", "--depth", "1", SOURCE_REPO, str(source))
        current = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        if current != SOURCE_COMMIT:
            run("git", "-C", str(source), "fetch", "--depth", "1", "origin", SOURCE_COMMIT)
            run("git", "-C", str(source), "checkout", "--detach", "FETCH_HEAD")
        assemble(source, args.output)


if __name__ == "__main__":
    main()
