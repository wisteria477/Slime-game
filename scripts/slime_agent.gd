class_name SlimeAgent
extends CharacterBody3D

signal data_changed

const MODEL_PATH := "res://assets/models/nim_slime_current.glb"
const NEED_MAX := 100.0
const BABY_GROW_SECONDS := 120.0

var slime_id := ""
var display_name := "Slime"
var age_stage := "adult"
var parents: Array[String] = []
var slime_color := Color("68d7ff")
var traits := {"playful": 0.5, "social": 0.5, "tidy": 0.5, "sleepy": 0.5}
var needs := {"hunger": 88.0, "energy": 90.0, "hygiene": 88.0, "fun": 90.0, "social": 88.0, "comfort": 90.0}
var relationships: Dictionary = {}
var age_seconds := 0.0
var sim_enabled := true

var build_system: SlimeBuildSystem
var household
var rng := RandomNumberGenerator.new()
var path: Array[Vector2i] = []
var path_index := 0
var action_kind := ""
var action_timer := 0.0
var think_timer := 0.0
var target_slime_id := ""
var visual_root: Node3D
var selection_disc: MeshInstance3D
var state_label: Label3D
var base_visual_scale := Vector3.ONE
var idle_phase := 0.0

func setup(id_value: String, name_value: String, color_value: Color, stage: String, build_ref: SlimeBuildSystem, household_ref) -> void:
    slime_id = id_value
    display_name = name_value
    slime_color = color_value
    age_stage = stage
    build_system = build_ref
    household = household_ref
    rng.seed = hash(slime_id)
    idle_phase = rng.randf_range(0.0, TAU)
    _build_character()
    _apply_age_scale()

func _physics_process(_delta: float) -> void:
    _animate_idle()
    if not sim_enabled or build_system == null:
        velocity = Vector3.ZERO
        return
    _move_along_path()

func tick_sim(delta: float) -> void:
    if not sim_enabled:
        return
    age_seconds += delta
    if age_stage == "baby" and age_seconds >= BABY_GROW_SECONDS:
        age_stage = "adult"
        _apply_age_scale()
        data_changed.emit()
    _decay_needs(delta)
    if not action_kind.is_empty() and path.is_empty():
        _perform_action(delta)
        return
    think_timer -= delta
    if think_timer <= 0.0 and path.is_empty():
        think_timer = rng.randf_range(1.0, 2.0)
        _choose_next_goal()

func command_move(cell: Vector2i) -> void:
    action_kind = ""
    target_slime_id = ""
    state_label.text = ""
    _set_path_to(cell)

func set_selected(selected: bool) -> void:
    if selection_disc:
        selection_disc.visible = selected

func current_cell() -> Vector2i:
    if build_system == null:
        return Vector2i.ZERO
    return build_system.world_to_cell(global_position)

func serialize() -> Dictionary:
    return {
        "id": slime_id,
        "name": display_name,
        "age_stage": age_stage,
        "parents": parents.duplicate(),
        "color": slime_color.to_html(true),
        "traits": traits.duplicate(true),
        "needs": needs.duplicate(true),
        "relationships": relationships.duplicate(true),
        "age_seconds": age_seconds,
        "position": [global_position.x, global_position.y, global_position.z],
    }

func restore(data: Dictionary) -> void:
    parents.clear()
    for p in data.get("parents", []):
        parents.append(String(p))
    traits = data.get("traits", traits).duplicate(true)
    needs = data.get("needs", needs).duplicate(true)
    relationships = data.get("relationships", {}).duplicate(true)
    age_seconds = float(data.get("age_seconds", 0.0))
    var pos: Array = data.get("position", [global_position.x, global_position.y, global_position.z])
    global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
    _apply_age_scale()

func _build_character() -> void:
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.36
    capsule.height = 0.95
    shape.shape = capsule
    shape.position.y = 0.48
    add_child(shape)

    visual_root = Node3D.new()
    visual_root.name = "Visual"
    add_child(visual_root)

    if ResourceLoader.exists(MODEL_PATH):
        var packed = load(MODEL_PATH)
        if packed is PackedScene:
            var model := packed.instantiate()
            model.name = "NimModel"
            model.scale = Vector3.ONE * 0.43
            model.rotation_degrees.y = 180.0
            visual_root.add_child(model)
            _tint_recursive(model)
        else:
            _make_fallback_slime()
    else:
        _make_fallback_slime()

    selection_disc = MeshInstance3D.new()
    selection_disc.name = "Selection"
    var disc_mesh := CylinderMesh.new()
    disc_mesh.top_radius = 0.62
    disc_mesh.bottom_radius = 0.62
    disc_mesh.height = 0.025
    selection_disc.mesh = disc_mesh
    selection_disc.position.y = 0.02
    var disc_mat := StandardMaterial3D.new()
    disc_mat.albedo_color = Color(0.35, 0.92, 0.98, 0.35)
    disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    selection_disc.material_override = disc_mat
    selection_disc.visible = false
    add_child(selection_disc)

    state_label = Label3D.new()
    state_label.text = ""
    state_label.font_size = 30
    state_label.outline_size = 5
    state_label.position = Vector3(0, 1.55, 0)
    state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(state_label)

func _make_fallback_slime() -> void:
    var jelly := StandardMaterial3D.new()
    jelly.albedo_color = Color(slime_color.r, slime_color.g, slime_color.b, 0.90)
    jelly.roughness = 0.14
    jelly.metallic = 0.0
    jelly.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    _blob("Torso", Vector3(0, 0.62, 0), Vector3(0.58, 0.70, 0.50), jelly)
    _blob("Head", Vector3(0, 1.28, 0), Vector3(0.84, 0.73, 0.72), jelly)
    _blob("ArmL", Vector3(-0.63, 0.74, -0.02), Vector3(0.22, 0.34, 0.22), jelly)
    _blob("ArmR", Vector3(0.63, 0.74, -0.02), Vector3(0.22, 0.34, 0.22), jelly)
    _blob("FootL", Vector3(-0.28, 0.18, -0.03), Vector3(0.36, 0.18, 0.34), jelly)
    _blob("FootR", Vector3(0.28, 0.18, -0.03), Vector3(0.36, 0.18, 0.34), jelly)
    _blob("AntennaBase", Vector3(0.09, 1.93, 0.01), Vector3(0.18, 0.28, 0.17), jelly, Vector3(0, 0, -18))
    _blob("AntennaTip", Vector3(0.23, 2.11, 0.01), Vector3(0.15, 0.17, 0.15), jelly)

    var eye_mat := StandardMaterial3D.new()
    eye_mat.albedo_color = Color("172437")
    eye_mat.roughness = 0.12
    _blob("EyeL", Vector3(-0.28, 1.34, -0.62), Vector3(0.12, 0.19, 0.08), eye_mat)
    _blob("EyeR", Vector3(0.28, 1.34, -0.62), Vector3(0.12, 0.19, 0.08), eye_mat)

    var white := StandardMaterial3D.new()
    white.albedo_color = Color.WHITE
    white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _blob("EyeHighlightL", Vector3(-0.32, 1.40, -0.70), Vector3(0.035, 0.05, 0.025), white)
    _blob("EyeHighlightR", Vector3(0.24, 1.40, -0.70), Vector3(0.035, 0.05, 0.025), white)

    var mouth_mat := StandardMaterial3D.new()
    mouth_mat.albedo_color = Color("263247")
    mouth_mat.roughness = 0.2
    _blob("Mouth", Vector3(0, 1.08, -0.66), Vector3(0.14, 0.07, 0.045), mouth_mat)

    var cheek := StandardMaterial3D.new()
    cheek.albedo_color = Color(1.0, 0.58, 0.68, 0.68)
    cheek.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    cheek.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _blob("CheekL", Vector3(-0.46, 1.10, -0.61), Vector3(0.12, 0.06, 0.035), cheek)
    _blob("CheekR", Vector3(0.46, 1.10, -0.61), Vector3(0.12, 0.06, 0.035), cheek)

    var core_mat := StandardMaterial3D.new()
    core_mat.albedo_color = Color(1.0, 0.83, 0.42, 0.52)
    core_mat.emission_enabled = true
    core_mat.emission = Color(1.0, 0.72, 0.24)
    core_mat.emission_energy_multiplier = 0.65
    core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _blob("Core", Vector3(0, 0.69, -0.12), Vector3(0.18, 0.25, 0.14), core_mat)

func _blob(name_value: String, position_value: Vector3, scale_value: Vector3, material: Material, rotation_value := Vector3.ZERO) -> void:
    var part := MeshInstance3D.new()
    part.name = name_value
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 24
    mesh.rings = 12
    part.mesh = mesh
    part.position = position_value
    part.scale = scale_value
    part.rotation_degrees = rotation_value
    part.material_override = material
    visual_root.add_child(part)

func _tint_recursive(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        if mesh_node.mesh:
            for surface in range(mesh_node.mesh.get_surface_count()):
                var active := mesh_node.get_active_material(surface)
                if active == null:
                    continue
                var copy := active.duplicate()
                var material_name := String(active.resource_name)
                if copy is StandardMaterial3D and (material_name.contains("Slime") or mesh_node.name.contains("Body") or mesh_node.name.contains("Bubble")):
                    copy.albedo_color = slime_color
                mesh_node.set_surface_override_material(surface, copy)
    for child in node.get_children():
        _tint_recursive(child)

func _apply_age_scale() -> void:
    if visual_root == null:
        return
    base_visual_scale = Vector3.ONE * (0.64 if age_stage == "baby" else 1.0)
    visual_root.scale = base_visual_scale
    if state_label:
        state_label.position.y = 1.12 if age_stage == "baby" else 1.55

func _animate_idle() -> void:
    if visual_root == null:
        return
    var pulse := sin(Time.get_ticks_msec() * 0.004 + idle_phase) * 0.025
    visual_root.scale = Vector3(base_visual_scale.x * (1.0 - pulse * 0.35), base_visual_scale.y * (1.0 + pulse), base_visual_scale.z * (1.0 - pulse * 0.35))

func _decay_needs(delta: float) -> void:
    var rates := {
        "hunger": 0.20,
        "energy": 0.12,
        "hygiene": 0.09,
        "fun": 0.11,
        "social": 0.10,
        "comfort": 0.07,
    }
    for key in needs.keys():
        needs[key] = clampf(float(needs[key]) - float(rates.get(key, 0.08)) * delta, 0.0, NEED_MAX)

func _choose_next_goal() -> void:
    var lowest_key := ""
    var lowest_value := NEED_MAX + 1.0
    for key in needs.keys():
        var value := float(needs[key])
        if value < lowest_value:
            lowest_value = value
            lowest_key = String(key)
    if lowest_value < 72.0:
        _seek_need(lowest_key)
    elif rng.randf() < 0.55:
        var target := build_system.random_walkable_cell(rng)
        _set_path_to(target)
        state_label.text = ""

func _seek_need(key: String) -> void:
    if key == "social":
        var other = household.find_nearest_other(slime_id, global_position)
        if other:
            target_slime_id = other.slime_id
            action_kind = "social"
            _set_path_to(other.current_cell())
            state_label.text = "Chat"
            return
    var furniture_kind := {
        "hunger": "food",
        "energy": "bed",
        "hygiene": "bath",
        "fun": "toy",
        "comfort": "sofa",
    }.get(key, "")
    if String(furniture_kind).is_empty():
        return
    var target: Dictionary = build_system.find_furniture(furniture_kind, current_cell())
    if target.is_empty():
        return
    action_kind = key
    target_slime_id = ""
    _set_path_to(target["cell"])
    state_label.text = _action_label(key)

func _set_path_to(cell: Vector2i) -> void:
    path = build_system.path_between(current_cell(), cell)
    if not path.is_empty() and path[0] == current_cell():
        path.remove_at(0)
    path_index = 0

func _move_along_path() -> void:
    if path.is_empty() or path_index >= path.size():
        velocity = Vector3.ZERO
        return
    var target_cell := path[path_index]
    var target_pos := build_system.cell_to_world(target_cell) + Vector3(0, 0.02, 0)
    var flat_delta := target_pos - global_position
    flat_delta.y = 0.0
    if flat_delta.length() < 0.08:
        global_position.x = target_pos.x
        global_position.z = target_pos.z
        path_index += 1
        if path_index >= path.size():
            path.clear()
            velocity = Vector3.ZERO
        return
    var speed := 1.10 if age_stage == "baby" else 1.65
    velocity = flat_delta.normalized() * speed
    velocity.y = 0.0
    move_and_slide()

func _perform_action(delta: float) -> void:
    action_timer += delta
    if action_kind == "social":
        var other = household.get_slime(target_slime_id)
        if other:
            if global_position.distance_to(other.global_position) > 2.0:
                _set_path_to(other.current_cell())
                return
            needs["social"] = clampf(float(needs["social"]) + 10.0 * delta, 0.0, NEED_MAX)
            other.needs["social"] = clampf(float(other.needs["social"]) + 6.0 * delta, 0.0, NEED_MAX)
            relationships[other.slime_id] = float(relationships.get(other.slime_id, 0.0)) + 1.2 * delta
            other.relationships[slime_id] = float(other.relationships.get(slime_id, 0.0)) + 1.2 * delta
    else:
        needs[action_kind] = clampf(float(needs.get(action_kind, 0.0)) + 13.0 * delta, 0.0, NEED_MAX)
    if action_timer >= 4.0 or float(needs.get(action_kind, 0.0)) >= 96.0:
        action_timer = 0.0
        action_kind = ""
        target_slime_id = ""
        state_label.text = ""
        think_timer = rng.randf_range(1.5, 3.0)
        data_changed.emit()

func _action_label(key: String) -> String:
    return {
        "hunger": "Eat",
        "energy": "Rest",
        "hygiene": "Wash",
        "fun": "Play",
        "social": "Chat",
        "comfort": "Cozy",
    }.get(key, "")
