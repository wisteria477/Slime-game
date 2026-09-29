extends SceneTree

const MODEL_PATH := "res://assets/models/nim_slime_current.glb"
const OUTPUT_DIR := "res://ci/output/nim_visual_qa"
const CAPTURE_STATES := ["Idle", "Happy", "Sad", "Tired"]

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    failures.append(message)
    push_error("NIM VISUAL QA: " + message)

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found:
            return found
    return null

func _resolve_animation(player: AnimationPlayer, requested: String) -> String:
    if player.has_animation(requested):
        return requested
    var needle := requested.to_lower()
    for candidate in player.get_animation_list():
        var value := String(candidate)
        var lowered := value.to_lower()
        if lowered == needle or lowered.ends_with("/" + needle) or lowered.ends_with("|" + needle):
            return value
    return ""

func _run() -> void:
    var output_absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
    var mkdir_error := DirAccess.make_dir_recursive_absolute(output_absolute)
    if mkdir_error != OK:
        _fail("could not create visual QA output directory")
        _finish()
        return

    var packed := load(MODEL_PATH) as PackedScene
    if packed == null:
        _fail("production Nim model could not be loaded")
        _finish()
        return

    var viewport := SubViewport.new()
    viewport.name = "NimVisualQA"
    viewport.size = Vector2i(900, 900)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.own_world_3d = true
    root.add_child(viewport)

    var environment_node := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("dfeaf3")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("d9edff")
    environment.ambient_light_energy = 0.72
    environment_node.environment = environment
    viewport.add_child(environment_node)

    var floor := MeshInstance3D.new()
    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(6.0, 6.0)
    floor.mesh = floor_mesh
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color("b7c8d3")
    floor_material.roughness = 0.86
    floor.material_override = floor_material
    viewport.add_child(floor)

    var holder := Node3D.new()
    holder.name = "NimHolder"
    holder.rotation_degrees.y = 180.0
    viewport.add_child(holder)

    var model := packed.instantiate()
    holder.add_child(model)

    var key_light := DirectionalLight3D.new()
    key_light.rotation_degrees = Vector3(-34.0, -28.0, 0.0)
    key_light.light_energy = 1.55
    key_light.shadow_enabled = true
    viewport.add_child(key_light)

    var fill_light := OmniLight3D.new()
    fill_light.position = Vector3(-2.4, 2.4, 2.5)
    fill_light.light_color = Color("d9f3ff")
    fill_light.light_energy = 2.6
    fill_light.omni_range = 7.0
    viewport.add_child(fill_light)

    var camera := Camera3D.new()
    camera.position = Vector3(0.0, 1.35, 4.2)
    camera.fov = 34.0
    viewport.add_child(camera)
    camera.look_at(Vector3(0.0, 1.25, 0.0), Vector3.UP)
    viewport.camera_3d = camera

    var player := _find_animation_player(model)
    if player == null:
        _fail("production Nim model has no AnimationPlayer")
        _finish()
        return

    await process_frame
    await process_frame

    for state in CAPTURE_STATES:
        var resolved := _resolve_animation(player, state)
        if resolved.is_empty():
            _fail("missing capture animation " + state)
            continue
        player.play(resolved)
        var animation := player.get_animation(resolved)
        if animation:
            player.seek(animation.length * 0.42, true)
        await process_frame
        await process_frame
        await process_frame

        var image := viewport.get_texture().get_image()
        if image == null or image.is_empty():
            _fail("viewport produced no image for " + state)
            continue

        var output_path := output_absolute.path_join("nim_" + state.to_lower() + ".png")
        var save_error := image.save_png(output_path)
        if save_error != OK:
            _fail("could not save " + output_path)

    _finish()

func _finish() -> void:
    if failures.is_empty():
        print("NIM VISUAL QA CAPTURE PASSED")
        print(ProjectSettings.globalize_path(OUTPUT_DIR))
        quit(0)
        return
    print("NIM VISUAL QA CAPTURE FAILED: %d issue(s)" % failures.size())
    quit(1)
