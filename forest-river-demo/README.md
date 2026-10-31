# Forest & River — Godot 4.6 graphics showcase

Standalone, explorable 3D forest with a meandering low-lying river, visible rolling terrain and sandy banks,
animated water, realistic trees, PBR terrain, grass, sunlight shafts, fog,
shadows and forest vegetation.

This is an **independent demo project**, not a modification of Butterfly Valley.
For attribution, see [CREDITS.md](CREDITS.md).

## Play it on Windows

1. Download `ForestRiverDemo-Windows.zip` from the `Forest river demo - Windows` GitHub Actions run in this repository.
2. Unzip it and run `ForestRiver.exe`.
3. Fly with **WASD**, rise with **Space**, descend with **C**, hold **Shift** for faster travel.
4. Look around with the mouse. Press **Esc** to release the cursor, click to recapture it.
5. Press **R** to return to the aerial starting viewpoint.
6. Confirm **FR-2026-10-31-R4** in the overlay. If absent, you launched an older copy.
7. If terrain looks wrong, press **F1** to hide/show water, **F2** to hide/show vegetation, and **F3** to switch terrain to a bright orange unlit diagnostic material. Take screenshots before and after toggling; press the same key again to restore the normal view.

The upstream layered sky was replaced with the built-in procedural daytime sky, avoiding OpenGL shader compilation errors.

The scene starts above the riverbank with the landscape in view; the inspection
camera has no gravity. Flight is limited to the terrain area and stays above
land or water. This is an exploration camera, not a walking character.

Requires Windows with a Vulkan-capable GPU. The demo uses Godot 4.6 Forward+.

## Open and edit in Godot

The project is reconstructed from the open-source [Godot Procedural Forest Demo](https://github.com/GamesNotDeveloped/godot-forest-demo), pinned to a specific commit for reproducibility. This keeps the Git repository lightweight and retains all original asset licences.

```bash
python scripts/assemble.py --output /path/to/ForestRiverDemo
```

Open `ForestRiverDemo/project.godot` in Godot 4.6 or later. For offline assembly using an existing downloaded source:

```bash
python scripts/assemble.py --source /path/to/godot-forest-demo --output /path/to/ForestRiverDemo
```

## Files to edit

- `demo/RiverTerrain.gd` — unified upland/riverbed height function for mesh, collision and grass.
- `demo/ground_stable.gdshader` — solid textured earth with sandy riverbanks.
- `demo/ForestRiverController.gd` — water mesh, shore stones, vegetation masking and spawn.
- `demo/river_water.gdshader` — animated flow, ripples, shallows and specular highlights.
- `demo/FreeFlyCamera.gd` — independent free-flight controls and safe altitude.
- `scripts/assemble.py` — pinned, reproducible demo assembly.

## Limitations

- The showcase defaults to stable daylight: no automatic exposure, heavy volumetric fog, SDFGI, bloom or custom sunlight shafts. This reduces visual fluctuations and GPU load.
- This is a graphics showcase, not a river physics simulation. No buoyancy or true planar reflection yet.
