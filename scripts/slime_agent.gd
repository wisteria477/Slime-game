class_name SlimeAgent
extends CharacterBody3D

signal data_changed

const MODEL_PATH := "res://assets/models/nim_slime_current.glb"
const NEED_MAX := 100.0
const BABY_GROW_SECONDS := 120.0

const PERSONALITY_NEED_BONUS := {
    "Bubbly": {"social": 18.0, "fun": 12.0},
    "Playful": {"fun": 24.0, "social": 6.0},
    "Neat": {"hygiene": 25.0, "comfort": 5.0},
    "Foodie": {"hunger": 25.0, "fun": 4.0},
    "Cozy": {"comfort": 24.0, "energy": 10.0},
    "Independent": {"comfort": 10.0, "energy": 8.0, "social": -10.0},
}

const HABIT_NEED_BONUS := {
    "Snacky": {"hunger": 18.0},
    "Napper": {"energy": 18.0},
    "Tidy Routine": {"hygiene": 18.0},
    "Toy Lover": {"fun": 18.0},
    "Chatty": {"social": 18.0},
    "Cozy Seeker": {"comfort": 18.0},
    "Wanderer": {},
    "Slow Starter": {"energy": 5.0, "comfort": 5.0},
}

var slime_id := ""
var display_name := "Slime"
var is_npc := false
var age_stage := "adult"
var parents: Array[String] = []
var slime_color := Color("68d7ff")
var appearance: Dictionary = {
    "size": "Standard",
    "eyes": "Round",
    "core": "Warm",
    "antenna": "Curl",
}
var personality := "Bubbly"
var habits: Array[String] = []
var traits := {"playful": 0.5, "social": 0.5, "tidy": 0.5, "sleepy": 0.5}
var needs := {"hunger": 88.0, "energy": 90.0, "hygiene": 88.0, "fun": 90.0, "social": 88.0, "comfort": 90.0, "bladder": 92.0}
var relationships: Dictionary = {}
var relationship_flags: Dictionary = {}
var emotion := "Fine"
var moodlets: Array[Dictionary] = []
var skills: Dictionary = SlimeLifeRules.default_skills()
var aspiration := ""
var aspiration_progress: Dictionary = {}
var wants: Array = []
var fears: Array = []
var satisfaction := 0
var career := "None"
var career_level := 1
var career_xp := 0.0
var school_grade := 70.0
var inventory: Array[Dictionary] = []
var action_queue: Array[String] = []
var secondary_activity := ""
var current_activity := "Idle"
var reward_traits: Array[String] = []
var routine_memory: Dictionary = {}
var life_state := "living"
var danger_timer := 0.0
var want_refresh_timer := 0.0
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
var target_object_id := ""
var visual_root: Node3D
var selection_disc: MeshInstance3D
var state_label: Label3D
var base_visual_scale := Vector3.ONE
var idle_phase := 0.0
var face_base_scales: Dictionary = {}
var face_base_rotations: Dictionary = {}

func setup(id_value: String, name_value: String, color_value: Color, stage: String, build_ref: SlimeBuildSystem, household_ref, personality_value := "Bubbly", habits_value: Array[String] = [], appearance_value: Dictionary = {}) -> void:
    slime_id = id_value
    display_name = name_value
    slime_color = color_value
    age_stage = stage
    personality = personality_value
    habits = habits_value.duplicate()
    if not appearance_value.is_empty():
        appearance = appearance_value.duplicate(true)
    build_system = build_ref
    household = household_ref
    rng.seed = hash(slime_id)
    idle_phase = rng.randf_range(0.0, TAU)
    aspiration = SlimeLifeRules.default_aspiration(personality)
    wants = SlimeLifeRules.random_wants(rng, 3)
    fears = [SlimeLifeRules.random_fear(rng)]
    _build_character()
    _capture_face_defaults()
    _apply_age_scale()
    _apply_appearance()
    _update_emotion()

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
    _tick_life_stage()
    _tick_moodlets(delta)
    _tick_wants(delta)
    _decay_needs(delta)
    _update_emotion()
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
    current_activity = "Player directed"
    action_queue.clear()
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
        "is_npc": is_npc,
        "age_stage": age_stage,
        "parents": parents.duplicate(),
        "color": slime_color.to_html(true),
        "appearance": appearance.duplicate(true),
        "personality": personality,
        "habits": habits.duplicate(),
        "traits": traits.duplicate(true),
        "needs": needs.duplicate(true),
        "relationships": relationships.duplicate(true),
        "relationship_flags": relationship_flags.duplicate(true),
        "emotion": emotion,
        "moodlets": moodlets.duplicate(true),
        "skills": skills.duplicate(true),
        "aspiration": aspiration,
        "aspiration_progress": aspiration_progress.duplicate(true),
        "wants": wants.duplicate(true),
        "fears": fears.duplicate(true),
        "satisfaction": satisfaction,
        "career": career,
        "career_level": career_level,
        "career_xp": career_xp,
        "school_grade": school_grade,
        "inventory": inventory.duplicate(true),
        "reward_traits": reward_traits.duplicate(),
        "routine_memory": routine_memory.duplicate(true),
        "life_state": life_state,
        "danger_timer": danger_timer,
        "age_seconds": age_seconds,
        "position": [global_position.x, global_position.y, global_position.z],
    }

func restore(data: Dictionary) -> void:
    is_npc = bool(data.get("is_npc", false))
    parents.clear()
    for p in data.get("parents", []):
        parents.append(String(p))
    appearance = data.get("appearance", appearance).duplicate(true)
    personality = String(data.get("personality", personality))
    habits.clear()
    for habit in data.get("habits", []):
        habits.append(String(habit))
    traits = data.get("traits", traits).duplicate(true)
    needs = data.get("needs", needs).duplicate(true)
    relationships = data.get("relationships", {}).duplicate(true)
    relationship_flags = data.get("relationship_flags", {}).duplicate(true)
    emotion = String(data.get("emotion", "Fine"))
    moodlets = data.get("moodlets", []).duplicate(true)
    skills = data.get("skills", SlimeLifeRules.default_skills()).duplicate(true)
    aspiration = String(data.get("aspiration", SlimeLifeRules.default_aspiration(personality)))
    aspiration_progress = data.get("aspiration_progress", {}).duplicate(true)
    wants = data.get("wants", SlimeLifeRules.random_wants(rng, 3)).duplicate(true)
    fears = data.get("fears", [SlimeLifeRules.random_fear(rng)]).duplicate(true)
    satisfaction = int(data.get("satisfaction", 0))
    career = String(data.get("career", "None"))
    career_level = int(data.get("career_level", 1))
    career_xp = float(data.get("career_xp", 0.0))
    school_grade = float(data.get("school_grade", 70.0))
    inventory = data.get("inventory", []).duplicate(true)
    reward_traits.clear()
    for reward in data.get("reward_traits", []):
        reward_traits.append(String(reward))
    routine_memory = data.get("routine_memory", {}).duplicate(true)
    life_state = String(data.get("life_state", "living"))
    danger_timer = float(data.get("danger_timer", 0.0))
    age_seconds = float(data.get("age_seconds", 0.0))
    var pos: Array = data.get("position", [global_position.x, global_position.y, global_position.z])
    global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
    _apply_age_scale()
    _apply_appearance()
    if life_state == "ghost":
        _set_ghost_visual(true)

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
        var packed: Resource = load(MODEL_PATH)
        if packed is PackedScene:
            var model: Node = (packed as PackedScene).instantiate()
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
    var now := Time.get_ticks_msec() * 0.004 + idle_phase
    var pulse_strength := 0.025
    if action_kind == "fun":
        pulse_strength = 0.075
    elif action_kind == "hygiene":
        pulse_strength = 0.045
    elif action_kind == "energy":
        pulse_strength = 0.012
    elif action_kind == "social":
        pulse_strength = 0.05
    var pulse := sin(now) * pulse_strength
    visual_root.scale = Vector3(
        base_visual_scale.x * (1.0 - pulse * 0.35),
        base_visual_scale.y * (1.0 + pulse),
        base_visual_scale.z * (1.0 - pulse * 0.35)
    )
    var lean := 0.0
    if action_kind == "fun":
        lean = sin(now * 1.7) * 0.11
    elif action_kind == "social":
        lean = sin(now * 1.25) * 0.055
    visual_root.rotation.z = lean
    _update_expression_visual()

func _apply_appearance() -> void:
    if visual_root == null:
        return
    var size_name := String(appearance.get("size", "Standard"))
    var size_mult := 1.0
    if size_name == "Tiny":
        size_mult = 0.82
    elif size_name == "Big":
        size_mult = 1.16
    base_visual_scale *= size_mult

    var eye_l := visual_root.get_node_or_null("EyeL") as Node3D
    var eye_r := visual_root.get_node_or_null("EyeR") as Node3D
    var eye_style := String(appearance.get("eyes", "Round"))
    if eye_l and eye_r:
        if eye_style == "Sleepy":
            eye_l.scale.y *= 0.55
            eye_r.scale.y *= 0.55
        elif eye_style == "Wide":
            eye_l.scale *= 1.18
            eye_r.scale *= 1.18

    var core := visual_root.get_node_or_null("Core") as MeshInstance3D
    if core and core.material_override is StandardMaterial3D:
        var mat := core.material_override as StandardMaterial3D
        var core_style := String(appearance.get("core", "Warm"))
        if core_style == "Cool":
            mat.emission = Color("8be7ff")
            mat.albedo_color = Color(0.52, 0.90, 1.0, 0.55)
        elif core_style == "Bright":
            mat.emission_energy_multiplier = 1.35

    var antenna_tip := visual_root.get_node_or_null("AntennaTip") as Node3D
    if antenna_tip:
        var antenna_style := String(appearance.get("antenna", "Curl"))
        if antenna_style == "Droplet":
            antenna_tip.scale.y *= 1.45
        elif antenna_style == "Bubble":
            antenna_tip.scale *= 1.35

func _capture_face_defaults() -> void:
    if visual_root == null:
        return
    for node_name in ["EyeL", "EyeR", "Mouth", "CheekL", "CheekR"]:
        var node := visual_root.get_node_or_null(node_name) as Node3D
        if node:
            face_base_scales[node_name] = node.scale
            face_base_rotations[node_name] = node.rotation

func _reset_face_node(node_name: String) -> Node3D:
    if visual_root == null:
        return null
    var node := visual_root.get_node_or_null(node_name) as Node3D
    if node == null:
        return null
    if face_base_scales.has(node_name):
        node.scale = face_base_scales[node_name]
    if face_base_rotations.has(node_name):
        node.rotation = face_base_rotations[node_name]
    return node

func _update_expression_visual() -> void:
    if visual_root == null:
        return
    var eye_l := _reset_face_node("EyeL")
    var eye_r := _reset_face_node("EyeR")
    var mouth := _reset_face_node("Mouth")
    var cheek_l := _reset_face_node("CheekL")
    var cheek_r := _reset_face_node("CheekR")
    if eye_l == null or eye_r == null or mouth == null:
        return

    var blink_wave := sin(Time.get_ticks_msec() * 0.0017 + idle_phase * 2.0)
    var blinking := blink_wave > 0.985
    if blinking:
        eye_l.scale.y *= 0.16
        eye_r.scale.y *= 0.16

    match emotion:
        "Happy":
            mouth.scale.x *= 1.42
            mouth.scale.y *= 0.72
            eye_l.rotation.z -= 0.05
            eye_r.rotation.z += 0.05
            if cheek_l:
                cheek_l.scale *= 1.12
            if cheek_r:
                cheek_r.scale *= 1.12
        "Playful":
            mouth.scale.x *= 1.50
            mouth.scale.y *= 0.86
            eye_l.scale *= 1.08
            eye_r.scale.y *= 0.72
            eye_l.rotation.z -= 0.10
            eye_r.rotation.z -= 0.10
        "Inspired", "Focused":
            mouth.scale.x *= 0.84
            mouth.scale.y *= 0.66
            eye_l.scale.y *= 1.10
            eye_r.scale.y *= 1.10
        "Sad":
            mouth.scale.x *= 0.92
            mouth.scale.y *= 0.62
            mouth.rotation.z += PI
            eye_l.rotation.z += 0.13
            eye_r.rotation.z -= 0.13
        "Angry":
            mouth.scale.x *= 0.82
            mouth.scale.y *= 0.50
            eye_l.rotation.z += 0.24
            eye_r.rotation.z -= 0.24
            if cheek_l:
                cheek_l.scale *= 1.18
            if cheek_r:
                cheek_r.scale *= 1.18
        "Embarrassed":
            mouth.scale *= 0.70
            eye_l.scale.y *= 0.82
            eye_r.scale.y *= 0.82
            if cheek_l:
                cheek_l.scale *= 1.35
            if cheek_r:
                cheek_r.scale *= 1.35
        "Uncomfortable":
            mouth.rotation.z += 0.16
            eye_l.rotation.z += 0.10
            eye_r.rotation.z += 0.10
        "Tired":
            eye_l.scale.y *= 0.42
            eye_r.scale.y *= 0.42
            mouth.scale *= 0.72
        "Energized":
            eye_l.scale *= 1.14
            eye_r.scale *= 1.14
            mouth.scale.x *= 1.18
        _:
            pass

func become_ghost() -> void:
    if life_state == "ghost":
        return
    life_state = "ghost"
    action_kind = ""
    path.clear()
    needs["hunger"] = 100.0
    needs["bladder"] = 100.0
    add_moodlet("Became a Spirit", "Fine", 1.0, 999999.0)
    _set_ghost_visual(true)
    current_activity = "Haunting peacefully"

func revive() -> void:
    if life_state != "ghost":
        return
    life_state = "living"
    danger_timer = 0.0
    _set_ghost_visual(false)
    add_moodlet("Back to Life", "Happy", 12.0, 30.0)
    current_activity = "Alive again"

func _set_ghost_visual(enabled: bool) -> void:
    if visual_root == null:
        return
    _set_ghost_visual_recursive(visual_root, enabled)

func _set_ghost_visual_recursive(node: Node, enabled: bool) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        if mesh_node.mesh:
            for surface in range(mesh_node.mesh.get_surface_count()):
                var active := mesh_node.get_active_material(surface)
                if active == null:
                    active = mesh_node.material_override
                if active is StandardMaterial3D:
                    var copy := (active as StandardMaterial3D).duplicate() as StandardMaterial3D
                    if enabled:
                        copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
                        var color := copy.albedo_color
                        copy.albedo_color = Color(
                            clampf(color.r * 0.72 + 0.18, 0.0, 1.0),
                            clampf(color.g * 0.86 + 0.12, 0.0, 1.0),
                            1.0,
                            0.52
                        )
                        copy.emission_enabled = true
                        copy.emission = Color("8bdcff")
                        copy.emission_energy_multiplier = 0.35
                    else:
                        copy.albedo_color.a = 1.0
                    mesh_node.set_surface_override_material(surface, copy)
    for child in node.get_children():
        _set_ghost_visual_recursive(child, enabled)

func _decay_needs(delta: float) -> void:
    var rates := {
        "hunger": 0.34,
        "energy": 0.22,
        "hygiene": 0.17,
        "fun": 0.22,
        "social": 0.20,
        "comfort": 0.15,
        "bladder": 0.26,
    }
    for key in needs.keys():
        var rate := float(rates.get(key, 0.16)) * _decay_multiplier(String(key))
        needs[key] = clampf(float(needs[key]) - rate * delta, 0.0, NEED_MAX)

func _decay_multiplier(key: String) -> float:
    var mult := 1.0
    match personality:
        "Playful":
            if key == "fun":
                mult += 0.28
        "Neat":
            if key == "hygiene":
                mult += 0.24
        "Foodie":
            if key == "hunger":
                mult += 0.26
        "Cozy":
            if key == "comfort":
                mult += 0.24
        "Bubbly":
            if key == "social":
                mult += 0.24
        "Independent":
            if key == "social":
                mult -= 0.28
    if habits.has("Snacky") and key == "hunger":
        mult += 0.18
    if habits.has("Napper") and key == "energy":
        mult += 0.16
    if habits.has("Tidy Routine") and key == "hygiene":
        mult += 0.16
    if habits.has("Toy Lover") and key == "fun":
        mult += 0.16
    if habits.has("Chatty") and key == "social":
        mult += 0.16
    if habits.has("Cozy Seeker") and key == "comfort":
        mult += 0.16
    return maxf(mult, 0.45)

func _priority_score(key: String) -> float:
    var need_value := float(needs.get(key, NEED_MAX))
    var score := (NEED_MAX - need_value)
    var personality_bonuses: Dictionary = PERSONALITY_NEED_BONUS.get(personality, {})
    score += float(personality_bonuses.get(key, 0.0))
    for habit in habits:
        var habit_bonuses: Dictionary = HABIT_NEED_BONUS.get(habit, {})
        score += float(habit_bonuses.get(key, 0.0))
    if need_value < 45.0:
        score += 35.0
    elif need_value < 65.0:
        score += 18.0
    return score

func _choose_next_goal() -> void:
    _plan_action_queue()

    if age_stage in ["young_adult", "adult"]:
        var baby: SlimeAgent = household.find_needy_baby(slime_id)
        if baby != null and (skill_level("parenting") > 0 or rng.randf() < 0.55):
            target_slime_id = baby.slime_id
            target_object_id = ""
            action_kind = "care_baby"
            current_activity = "Caring for %s" % baby.display_name
            _set_path_to(baby.current_cell())
            state_label.text = "Care"
            return

    if personality == "Neat" or habits.has("Tidy Routine"):
        var dirty: Dictionary = build_system.find_problem_object("dirty", current_cell())
        if not dirty.is_empty() and rng.randf() < 0.75:
            var dirty_item: Dictionary = dirty["item"]
            target_object_id = String(dirty_item.get("id", ""))
            target_slime_id = ""
            action_kind = "clean_object"
            current_activity = "Cleaning"
            _set_path_to(dirty["cell"])
            state_label.text = "Clean"
            return

    if skill_level("handiness") >= 1 or personality == "Independent":
        var broken: Dictionary = build_system.find_problem_object("broken", current_cell())
        if not broken.is_empty() and rng.randf() < 0.65:
            var broken_item: Dictionary = broken["item"]
            target_object_id = String(broken_item.get("id", ""))
            target_slime_id = ""
            action_kind = "repair_object"
            current_activity = "Repairing"
            _set_path_to(broken["cell"])
            state_label.text = "Repair"
            return

    var best_key := ""
    var best_score := -INF
    for key in needs.keys():
        var key_string := String(key)
        var score := _priority_score(key_string)
        if score > best_score:
            best_score = score
            best_key = key_string

    var proactive_threshold := 23.0
    if habits.has("Slow Starter"):
        proactive_threshold = 28.0

    if best_score >= proactive_threshold:
        _seek_need(best_key)
        if not action_kind.is_empty() or not path.is_empty():
            return

    if habits.has("Wanderer") or rng.randf() < 0.72:
        var target := build_system.random_walkable_cell(rng)
        current_activity = "Exploring" if habits.has("Wanderer") else "Wandering"
        _set_path_to(target)
        state_label.text = current_activity

func _seek_need(key: String) -> void:
    if key == "social":
        var other: SlimeAgent = household.find_nearest_other(slime_id, global_position)
        if other:
            target_slime_id = other.slime_id
            action_kind = "social"
            current_activity = "Socializing"
            _set_path_to(other.current_cell())
            state_label.text = "Chat"
            return
    var furniture_kind: String = String({
        "hunger": "food",
        "energy": "bed",
        "hygiene": "bath",
        "fun": "toy",
        "comfort": "sofa",
        "bladder": "toilet",
    }.get(key, ""))
    if furniture_kind.is_empty():
        return
    var target: Dictionary = build_system.find_furniture(furniture_kind, current_cell())
    if target.is_empty():
        return
    action_kind = key
    current_activity = _action_label(key)
    target_slime_id = ""
    var target_item: Dictionary = target.get("item", {})
    target_object_id = String(target_item.get("id", ""))
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
    if habits.has("Slow Starter"):
        speed *= 0.88
    var direction := flat_delta.normalized()
    var target_yaw := atan2(direction.x, direction.z) + PI
    rotation.y = lerp_angle(rotation.y, target_yaw, 0.18)
    velocity = direction * speed
    velocity.y = 0.0
    move_and_slide()

func _perform_action(delta: float) -> void:
    action_timer += delta
    if action_kind == "care_baby":
        var baby: SlimeAgent = household.get_slime(target_slime_id)
        if baby == null:
            action_kind = ""
            return
        if global_position.distance_to(baby.global_position) > 2.0:
            _set_path_to(baby.current_cell())
            return
        var lowest_key := "hunger"
        var lowest_value := 101.0
        for need_key in baby.needs.keys():
            var value := float(baby.needs[need_key])
            if value < lowest_value:
                lowest_value = value
                lowest_key = String(need_key)
        baby.needs[lowest_key] = clampf(float(baby.needs[lowest_key]) + 12.0 * delta, 0.0, NEED_MAX)
        baby.needs["social"] = clampf(float(baby.needs["social"]) + 5.0 * delta, 0.0, NEED_MAX)
        needs["social"] = clampf(float(needs["social"]) + 2.0 * delta, 0.0, NEED_MAX)
        gain_skill("parenting", 1.3 * delta)
        if action_timer >= 4.0 or float(baby.needs[lowest_key]) >= 92.0:
            baby.add_moodlet("Cared For", "Happy", 7.0, 18.0)
            add_moodlet("Caring Moment", "Happy", 5.0, 18.0)
    elif action_kind == "clean_object":
        build_system.clean_object(target_object_id, 18.0 * delta)
        gain_skill("cleaning", 1.0 * delta)
        needs["hygiene"] = clampf(float(needs["hygiene"]) - 0.7 * delta, 0.0, NEED_MAX)
    elif action_kind == "repair_object":
        build_system.repair_object(target_object_id, 14.0 * delta)
        gain_skill("handiness", 1.2 * delta)
    elif action_kind == "social":
        var other: SlimeAgent = household.get_slime(target_slime_id)
        if other:
            if global_position.distance_to(other.global_position) > 2.0:
                _set_path_to(other.current_cell())
                return
            var face_delta: Vector3 = other.global_position - global_position
            face_delta.y = 0.0
            if face_delta.length() > 0.05:
                rotation.y = lerp_angle(rotation.y, atan2(face_delta.x, face_delta.z) + PI, 0.15)
            needs["social"] = clampf(float(needs["social"]) + 10.0 * delta, 0.0, NEED_MAX)
            other.needs["social"] = clampf(float(other.needs["social"]) + 6.0 * delta, 0.0, NEED_MAX)
            relationships[other.slime_id] = float(relationships.get(other.slime_id, 0.0)) + 1.2 * delta
            other.relationships[slime_id] = float(other.relationships.get(slime_id, 0.0)) + 1.2 * delta
            gain_skill("social", 1.8 * delta)
            other.gain_skill("social", 1.0 * delta)
            _complete_want("social")
            if float(relationships.get(other.slime_id, 0.0)) >= 35.0:
                relationship_flags[other.slime_id] = "Friend"
                other.relationship_flags[slime_id] = "Friend"
    else:
        var recovery := 13.0
        if (action_kind == "fun" and habits.has("Toy Lover")) or (action_kind == "hygiene" and habits.has("Tidy Routine")):
            recovery = 16.0
        elif (action_kind == "hunger" and habits.has("Snacky")) or (action_kind == "energy" and habits.has("Napper")):
            recovery = 15.0
        elif action_kind == "comfort" and habits.has("Cozy Seeker"):
            recovery = 15.0
        needs[action_kind] = clampf(float(needs.get(action_kind, 0.0)) + recovery * delta, 0.0, NEED_MAX)
        _gain_activity_skill(action_kind, delta)
        _complete_want(_want_id_for_action(action_kind))
        _try_secondary_social(delta)
    var action_finished := action_timer >= 4.0
    if action_kind in ["hunger", "energy", "hygiene", "fun", "social", "comfort", "bladder"]:
        action_finished = action_finished or float(needs.get(action_kind, 0.0)) >= 96.0
    if action_finished:
        if action_kind == "hunger":
            add_inventory_item("Prepared Meal", 1)
            add_moodlet("Ate a Meal", "Happy", 3.0 + float(skill_level("cooking")) * 0.4, 12.0)
        elif action_kind == "bladder":
            add_moodlet("Relieved", "Happy", 3.0, 10.0)
        elif action_kind == "energy" and not target_object_id.is_empty():
            build_system.claim_object(target_object_id, slime_id)
        action_timer = 0.0
        action_kind = ""
        target_slime_id = ""
        target_object_id = ""
        secondary_activity = ""
        current_activity = "Thinking"
        state_label.text = ""
        think_timer = rng.randf_range(1.0, 2.0)
        data_changed.emit()

func _tick_life_stage() -> void:
    if not SlimeLifeRules.AGE_DURATIONS.has(age_stage):
        return
    var duration := float(SlimeLifeRules.AGE_DURATIONS[age_stage])
    if age_seconds < duration:
        return
    var old_stage := age_stage
    age_stage = SlimeLifeRules.next_age(age_stage)
    age_seconds = 0.0
    add_moodlet("Growing Up", "Happy", 18.0, 32.0)
    current_activity = "Grew from %s to %s" % [old_stage, age_stage]
    _apply_age_scale()
    data_changed.emit()

func _tick_moodlets(delta: float) -> void:
    for i in range(moodlets.size() - 1, -1, -1):
        var mood: Dictionary = moodlets[i]
        mood["time"] = float(mood.get("time", 0.0)) - delta
        if float(mood["time"]) <= 0.0:
            moodlets.remove_at(i)
        else:
            moodlets[i] = mood
    if float(needs.get("hunger", 100.0)) < 18.0:
        _ensure_moodlet("Very Hungry", "Uncomfortable", 12.0, 8.0)
    if float(needs.get("energy", 100.0)) < 18.0:
        _ensure_moodlet("Exhausted", "Tired", 12.0, 8.0)
    if float(needs.get("social", 100.0)) < 18.0:
        _ensure_moodlet("Lonely", "Sad", 10.0, 8.0)
    if float(needs.get("fun", 100.0)) > 86.0:
        _ensure_moodlet("Having Fun", "Playful", 6.0, 6.0)

func _tick_wants(delta: float) -> void:
    want_refresh_timer += delta
    if want_refresh_timer >= 55.0:
        want_refresh_timer = 0.0
        if wants.size() < 3:
            for want in SlimeLifeRules.random_wants(rng, 3):
                if wants.size() >= 3:
                    break
                var duplicate := false
                for existing in wants:
                    if String(existing.get("id", "")) == String(want.get("id", "")):
                        duplicate = true
                if not duplicate:
                    wants.append(want)

func add_moodlet(text_value: String, emotion_value: String, strength := 5.0, duration := 20.0) -> void:
    moodlets.append({"text": text_value, "emotion": emotion_value, "strength": strength, "time": duration})
    if moodlets.size() > 8:
        moodlets.pop_front()
    _update_emotion()

func _ensure_moodlet(text_value: String, emotion_value: String, strength: float, duration: float) -> void:
    for mood in moodlets:
        if String(mood.get("text", "")) == text_value:
            return
    add_moodlet(text_value, emotion_value, strength, duration)

func _update_emotion() -> void:
    var scores := {"Fine": 1.0}
    for mood in moodlets:
        var key := String(mood.get("emotion", "Fine"))
        scores[key] = float(scores.get(key, 0.0)) + float(mood.get("strength", 1.0))
    if float(needs.get("comfort", 100.0)) < 20.0:
        scores["Uncomfortable"] = float(scores.get("Uncomfortable", 0.0)) + 12.0
    var best := "Fine"
    var best_value := -INF
    for key in scores.keys():
        var value := float(scores[key])
        if value > best_value:
            best_value = value
            best = String(key)
    emotion = best

func _plan_action_queue() -> void:
    var scored: Array = []
    for key in needs.keys():
        scored.append({"key": String(key), "score": _priority_score(String(key))})
    scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
    action_queue.clear()
    for entry in scored:
        if action_queue.size() >= 3:
            break
        action_queue.append(_action_label(String(entry["key"])))

func queue_text() -> String:
    if action_queue.is_empty():
        return current_activity
    return " → ".join(action_queue)

func gain_skill(skill: String, amount: float) -> void:
    if not skills.has(skill):
        return
    var data: Dictionary = skills[skill]
    var multiplier := 1.0
    if reward_traits.has("Fast Learner"):
        multiplier += 0.35
    data["xp"] = float(data.get("xp", 0.0)) + amount * multiplier
    var level := int(data.get("level", 0))
    var needed := 18.0 + float(level) * 14.0
    while float(data["xp"]) >= needed and level < 10:
        data["xp"] = float(data["xp"]) - needed
        level += 1
        data["level"] = level
        satisfaction += 25
        add_moodlet("Learned %s %d" % [skill.capitalize(), level], "Focused", 7.0, 18.0)
        needed = 18.0 + float(level) * 14.0
    skills[skill] = data

func skill_level(skill: String) -> int:
    if not skills.has(skill):
        return 0
    return int((skills[skill] as Dictionary).get("level", 0))

func _gain_activity_skill(kind: String, delta: float) -> void:
    match kind:
        "hunger":
            gain_skill("cooking", 0.8 * delta)
        "bladder":
            gain_skill("cleaning", 0.15 * delta)
        "hygiene":
            gain_skill("cleaning", 0.7 * delta)
        "fun":
            gain_skill("creativity", 0.8 * delta)
        "comfort":
            gain_skill("logic", 0.35 * delta)
        "social":
            gain_skill("social", 0.8 * delta)

func _want_id_for_action(kind: String) -> String:
    return {
        "hunger": "eat",
        "energy": "sleep",
        "hygiene": "wash",
        "fun": "play",
        "social": "social",
        "comfort": "cozy",
        "bladder": "bathroom",
    }.get(kind, "")

func _complete_want(want_id: String) -> void:
    if want_id.is_empty():
        return
    for i in range(wants.size() - 1, -1, -1):
        if String(wants[i].get("id", "")) == want_id:
            satisfaction += 40
            add_moodlet("Want fulfilled", "Happy", 8.0, 16.0)
            wants.remove_at(i)

func _try_secondary_social(delta: float) -> void:
    if float(needs.get("social", 100.0)) > 72.0:
        secondary_activity = ""
        return
    var other: SlimeAgent = household.find_nearest_other(slime_id, global_position)
    if other == null or global_position.distance_to(other.global_position) > 2.2:
        secondary_activity = ""
        return
    secondary_activity = "Chatting while busy"
    needs["social"] = clampf(float(needs["social"]) + 2.2 * delta, 0.0, NEED_MAX)
    relationships[other.slime_id] = float(relationships.get(other.slime_id, 0.0)) + 0.25 * delta
    gain_skill("social", 0.25 * delta)

func assign_career(career_name: String) -> void:
    if not SlimeLifeRules.CAREERS.has(career_name):
        return
    career = career_name
    career_level = 1
    career_xp = 0.0
    add_moodlet("New Job", "Happy", 8.0, 24.0)

func career_text() -> String:
    if career == "None":
        return "No career"
    return "%s Lv.%d" % [career, career_level]

func add_inventory_item(item_name: String, quantity := 1) -> void:
    for item in inventory:
        if String(item.get("name", "")) == item_name:
            item["quantity"] = int(item.get("quantity", 0)) + quantity
            return
    inventory.append({"name": item_name, "quantity": quantity})

func profile_detail_text() -> String:
    var best_skill := ""
    var best_level := -1
    for skill in skills.keys():
        var level := skill_level(String(skill))
        if level > best_level:
            best_level = level
            best_skill = String(skill)
    var want_text := "No current want"
    if not wants.is_empty():
        want_text = String(wants[0].get("text", ""))
    return "%s • %s • %s %d • %s" % [emotion, aspiration, best_skill.capitalize(), best_level, want_text]

func activity_text() -> String:
    if not secondary_activity.is_empty():
        return "%s + %s" % [current_activity, secondary_activity]
    if not action_kind.is_empty():
        return _action_label(action_kind)
    if not path.is_empty():
        return "Exploring" if habits.has("Wanderer") else "Walking"
    return current_activity

func profile_text() -> String:
    var parts: Array[String] = [personality]
    for habit in habits:
        parts.append(habit)
    return " • ".join(parts)

func _action_label(key: String) -> String:
    return {
        "hunger": "Eat",
        "energy": "Rest",
        "hygiene": "Wash",
        "fun": "Play",
        "social": "Chat",
        "comfort": "Cozy",
        "bladder": "Bathroom",
        "care_baby": "Care",
        "clean_object": "Clean",
        "repair_object": "Repair",
    }.get(key, "")
