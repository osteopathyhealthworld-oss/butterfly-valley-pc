extends SceneTree
## A release-quality probe for the first externally licensed PBR tree.
## Run only after game/prepare_forest_assets.py --fetch and Godot --editor --import.

const WORLD = preload("res://scripts/world_pbr.gd")
const PINE = "res://assets/forest/pine-tree-1/scene.gltf"

func _initialize() -> void:
    call_deferred("_verify")

func _fail(reason: String) -> void:
    push_error("FOREST_ART: " + reason)
    quit(1)

func _verify() -> void:
    if not ResourceLoader.exists(PINE):
        _fail("CC BY pine is missing; run prepare_forest_assets.py --fetch before Godot import")
        return
    var packed := load(PINE) as PackedScene
    if packed == null:
        _fail("Imported CC BY glTF is not a scene")
        return
    var world := WORLD.new()
    root.add_child(world)
    world.set_quality(true)
    if not world._mesh_library.has("pbr-pine"):
        _fail("CC BY pine was not registered in the procedural tree library")
        return
    var mesh: Mesh = world._mesh_library["pbr-pine"]
    if mesh.get_surface_count() < 2:
        _fail("PBR pine lost trunk or leaf geometry during batched import")
        return
    for index in range(mesh.get_surface_count()):
        var material := mesh.surface_get_material(index)
        if not (material is BaseMaterial3D):
            _fail("Source PBR material was replaced or lost on surface " + str(index))
            return
    if world._grass_v2 == null or world._grass_material != world._grass_v2:
        _fail("Detailed desktop terrain did not select Art V2")
        return
    for parameter in ["grass_color", "meadow_color", "forest_color", "soil_color", "rock_color", "grass_normal", "forest_normal", "rock_normal"]:
        if not (world._grass_v2.get_shader_parameter(parameter) is Texture2D):
            _fail("Terrain V2 is missing a CC0 texture: " + parameter)
            return
    var holder := Node3D.new()
    root.add_child(holder)
    world._make_terrain(holder, Vector2i(0, 0))
    var terrain := holder.get_node_or_null("Земля") as MeshInstance3D
    if terrain == null or terrain.mesh == null or terrain.mesh.surface_get_material(0) != world._grass_v2:
        _fail("Streaming terrain is still drawing the legacy shader")
        return
    print("FOREST_ART_SMOKE_PASS: PBR pine + eight terrain maps, preserved materials and streamed terrain Art V2")
    quit(0)
