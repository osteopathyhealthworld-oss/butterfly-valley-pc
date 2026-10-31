# Forest & River — clean Godot 4.6 prototype

This is a **new project**, not another revision of the imported forest demo.
The existing `forest-river-demo` (R6) is not changed.

## What it contains

- One generated, opaque, properly UV-mapped terrain with visible green/brown texture.
- The same height function forms rolling hills, curved riverbanks and a recessed riverbed.
- A separately meshed **winding** opaque river, never a rectangular translucent plane.
- Three genuine open-source tree models. Imported from plain glTF with native
  `StandardMaterial3D`: no wind shaders or custom biome engine.
- 330 trees and 4,600 fixed grass tufts: **no reconstruction while flying**.
- 3D MSAA 4× and alpha-to-coverage on cutout foliage in Forward+.
- Fixed daytime lighting, no autoexposure, animated sky or fog compositor.
- Gravity-free WASD camera. Surface-clearance clamp avoids falling below ground.
- Optional render probes F1–F5. Shadows are off by default to isolate foliage
  aliasing from moving camera-shadow cascades.

## Windows controls

| Key | Action |
| --- | --- |
| WASD + mouse | Fly and look |
| Space / C | Up / down |
| Shift | Speed up |
| R | Reset view |
| Esc / mouse click | Release / capture mouse |
| F1 | Swap real ground texture for unmistakable red diagnostic material |
| F2 / F3 | Show or hide trees / grass |
| F4 | Show or hide river |
| F5 | Toggle sun shadows, normally disabled |

First launch `Start-Vulkan.cmd` (Forward+). `Start-OpenGL.cmd` is a compatibility
comparison; OpenGL lacks Forward+'s alpha-to-coverage foliage treatment.

## Reproducible build

```bash
python3 forest-river-clean/scripts/assemble.py --output /tmp/ForestRiverClean
godot --headless --editor --path /tmp/ForestRiverClean --import --quit
godot --headless --path /tmp/ForestRiverClean --script res://SmokeTest.gd
```

The assemble step copies **only licensed glTF tree assets**, from pinned
[`GamesNotDeveloped/godot-forest-demo`](https://github.com/GamesNotDeveloped/godot-forest-demo/commit/623212ffeb4efbf4c95323a4a6a57e726be4f6e9).
The code, biome system, original ground JPG, environment, fog, water and wind
shader are *not* copied.

Tree models are CC BY 4.0; credits and licenses are included under `objects/`.
The new scene and build scripts are original additions for this prototype.

## Known limitations and acceptance test

The CI environment verifies script loading, terrain topology, visible materials,
camera controls and Windows export. It cannot reproduce the exact GTX 1060 driver,
monitor or Windows renderer. Successful CI is not proof of flicker-free animation
on that device. Please check **continuous flight**, not just screenshots.

Test Vulkan with F2 (forest off), then F2 again (forest on), and compare with
OpenGL. Record FPS and whether distant foliage flickers while moving the mouse.
