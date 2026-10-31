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
    # The stock FPS character has gravity, respawning, head bob and kill
    # volumes. Replace it with a genuinely gravity-free showcase camera.
    for obsolete_node in ("UP_FPSController_Prefab", "MouseCapture"):
        pattern = r'^\[node name="' + obsolete_node + r'"[^\n]*\n(?:[^\[]*\n)*'
        scene, count = re.subn(pattern, '', scene, flags=re.M)
        if count != 1:
            raise ValueError(f"Expected exactly one {obsolete_node} scene node, got {count}")
    scene = re.sub(
        r'^\[ext_resource[^\n]*(?:UP_FPSController_Prefab.tscn|UP_MouseCapture.gd)[^\n]*\n',
        '', scene, flags=re.M)
    old_target = 'sample_target_path = NodePath("../UP_FPSController_Prefab")'
    if old_target not in scene:
        raise ValueError("Could not locate fog's old player target")
    scene = scene.replace(old_target, 'sample_target_path = NodePath("../FlyCamera")')
    camera_resource = '[ext_resource type="Script" path="res://demo/FreeFlyCamera.gd" id="99_freefly"]\n'
    scene = scene.replace('[sub_resource', camera_resource + '[sub_resource', 1)
    scene += ('\n[node name="FlyCamera" type="Camera3D" parent="."]\n'
              'current = true\nfov = 70.0\nfar = 600.0\n'
              'script = ExtResource("99_freefly")\n')
    # Resource UIDs from the original scripts otherwise take precedence over
    # the new path and silently reload the old scripts.
    scene = re.sub(r'(\[ext_resource type="Script") uid="uid://[^"]+"(?= path="res://demo/)',
                   r'\1', scene)
    scene = re.sub(r'^\[ext_resource[^\n]*res://music/[^\n]*\n', '', scene, flags=re.M)
    scene = re.sub(r'^\[ext_resource[^\n]*res://addons/debug_menu/debug_menu.tscn[^\n]*\n',
                   '', scene, flags=re.M)
    scene = re.sub(r'^\[node name="AudioStreamPlayer"[^\n]*\n(?:(?!\[node ).*\n)*',
                   '', scene, flags=re.M)
    scene = re.sub(r'^\[node name="CanvasLayer"[^\n]*\n', '', scene, flags=re.M)
    scene = scene.replace('subdivisions_x = 160', 'subdivisions_x = 256')
    scene = scene.replace('subdivisions_z = 160', 'subdivisions_z = 256')
    # Eliminate billboard swaps and rapidly varying density LOD that popped
    # between frames; spread fewer full tree meshes over more terrain.
    scene, removed = re.subn(r'^billboard_scene = ExtResource\("[^"]+"\)\n', '', scene, flags=re.M)
    if removed < 4:
        raise ValueError("Expected forest and plant billboard references")
    scene = scene.replace('density_lod_enabled = true', 'density_lod_enabled = false')
    original_trees = 'seed = 7\narea_size = Vector2(100, 100)\naverage_spacing = 1.9'
    replacement_trees = 'seed = 7\narea_size = Vector2(155, 155)\naverage_spacing = 3.4'
    if original_trees not in scene:
        raise ValueError("Could not locate tree density settings")
    scene = scene.replace(original_trees, replacement_trees)
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
    # DebugMenu is an editor-oriented upstream autoload, irrelevant to this
    # playable showcase. Its UID triggered startup warnings and its overlay
    # competed with our own discreet performance display.
    project = re.sub(r'^DebugMenu="\*uid://[^"]+"\n', '', project, flags=re.M)
    # These editor-only plugins are not needed to run or edit the demo and
    # can fail on first scan before icon textures finish importing.
    project = re.sub(r'^enabled=PackedStringArray\([^\n]*\)',
                     'enabled=PackedStringArray()', project, flags=re.M)
    project_path.write_text(project, encoding="utf-8")
    shutil.copy2(HERE / "windows_export_presets.cfg", output / "export_presets.cfg")
    shutil.copy2(HERE / "CREDITS.md", output / "CREDITS.md")
    shutil.copy2(HERE / "README.md", output / "FOREST_RIVER_README.md")
    shutil.copy2(HERE / "QA.md", output / "QA.md")
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
