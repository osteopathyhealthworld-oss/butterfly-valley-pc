extends SceneTree
## Offscreen CI audit with a real GPU-backed viewport (Xvfb/Mesa).
## Emits two small screenshots and checks that orange terrain covers pixels.

func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    root.size = Vector2i(960, 540)
    var packed := load("res://levels/forest_river_demo.tscn") as PackedScene
    if packed == null:
        push_error("Visual QA: main scene failed to load")
        quit(1)
        return
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)
    for i in range(12):
        await process_frame
    await RenderingServer.frame_post_draw
    var first: Image = root.get_texture().get_image()
    if first.is_empty():
        push_error("Visual QA: viewport returned no image")
        quit(2)
        return
    var cam := scene.get_node("FlyCamera") as Camera3D
    var ground := scene.get_node("Terrain") as Node3D
    print("VISUAL_QA_CAMERA_HEIGHT=", cam.global_position.y)
    print("VISUAL_QA_GROUND_HEIGHT=", ground.call("_sample_height", cam.global_position.x, cam.global_position.z))
    _emit_image("RENDER_DEFAULT", first)

    (scene.get_node("AnimatedRiver") as MeshInstance3D).visible = false
    for biome in ["Trees", "Plants", "Plants2"]:
        (scene.get_node(biome) as Node3D).visible = false
    scene.call("_toggle_diagnostic_ground")
    for i in range(6):
        await process_frame
    await RenderingServer.frame_post_draw
    var diagnostic: Image = root.get_texture().get_image()
    _emit_image("RENDER_DIAGNOSTIC", diagnostic)
    var orange_count := 0
    var pixel_count := 0
    for y in range(90, diagnostic.get_height(), 4):
        for x in range(0, diagnostic.get_width(), 4):
            var color: Color = diagnostic.get_pixel(x, y)
            pixel_count += 1
            if color.r > 0.65 and color.r > color.g * 1.65 and color.g > color.b * 1.3:
                orange_count += 1
    print("VISUAL_QA_ORANGE_PIXELS=", orange_count, "/", pixel_count)
    if orange_count < 100:
        push_error("Visual QA: diagnostic ground did not appear on-screen")
        quit(3)
        return
    print("VISUAL_QA_PASS: actual terrain pixels rendered")
    quit(0)


func _emit_image(tag: String, source: Image) -> void:
    var preview := source.duplicate()
    preview.resize(480, 270, Image.INTERPOLATE_BILINEAR)
    var encoded := Marshalls.raw_to_base64(preview.save_jpg_to_buffer(0.67))
    print(tag + "_BEGIN")
    for start in range(0, encoded.length(), 6000):
        print(encoded.substr(start, 6000))
    print(tag + "_END")
