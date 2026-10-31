# Technical verification and remaining risks

This is a graphics prototype and a Windows test package, not a finished game.

## Automated checks performed

Tested with Godot 4.6 stable (Linux, headless):

- Import of all project assets and scripts.
- Instantiation of the complete main scene.
- River mesh generated (11,520 vertices) and shoreline stones (440 instances).
- Explicitly verify a visible terrain MeshInstance3D, an opaque terrain shader, a meaningful height range and riverbank heights above the water along five cross sections.
- Disable adaptive exposure, the temporal compositor, volumetric fog, SDFGI and bloom; verify stable tree meshes without density/billboard swaps.
- Riverbed height strictly below the water surface.
- The old cottage and well relocated outside the riverbank footprint.
- Tree masks exclude the river, cottage and well areas.
- Forest scatter actually populates the scene (4,839 tree-related mesh
  instances in the test run, counting mesh parts and LOD variants rather
  than unique trees); the player area generated 6,657 grass blades.
- Grass generation performed on a background thread, with every checked
  blade matching the modified terrain height within 1 millimeter.
- Free-fly camera is the sole player viewpoint; it starts above the terrain,
  remains stationary without input, and responds to simulated forward, upward
  and downward movement. Its lower bound follows land or water height.
- Game data exported as a `.pck`, and that `.pck` started independently from
  the original Godot project using an identical-version engine executable.
- Both downloadable ZIP archives tested for compressed-file integrity.

## Still needs human verification

- **Actual Windows graphics:** Vulkan rendering and the perceived appearance
  of water, foliage, shadows and volumetric fog cannot be judged by headless
  tests. Compare screenshots from the user's PC to the intended art direction.
- **Performance:** record FPS and frametimes on the target PC at the starting
  point, riverside and deep forest. Headless results are not a GPU benchmark.
- **Movement and collisions:** fly at different heights in all directions, inspect any
  floating/penetrating props or plants, and verify cursor capture/unlock.
- **Water realism:** there is no true planar reflection or physical fluid
  simulation. Water shading is a stylistic first pass.
- **GitHub Actions:** Windows CI workflow is provided, but no successful CI
  artifact has been independently confirmed yet.

## Known upstream warnings

Some imported glTF models use specular/glossiness materials that Godot
converts to metallic/roughness with a warning. Godot/Jolt also reports
resource allocations remaining when the headless test process exits. The
tests return code 0 and no missing-resource or GDScript parse errors after
including all runtime dependencies. Neither warning is proof that the scene
renders correctly on a GPU.

## Windows executable format

The downloadable local Windows test archive packages an official Godot 4.6
Windows executable and a same-basename `.pck` file. This is an official
supported way to start a Godot pack, but the executable is the larger editor
binary. The CI recipe uses optimized export templates when GitHub Actions
is available. Do not separate the `ForestRiver.exe` and `ForestRiver.pck` files.
