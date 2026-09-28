class_name SlimeHousehold
extends Node

signal household_changed
signal selection_changed(slime)

var slime_root: Node3D
var build_system: SlimeBuildSystem
var slimes: Array[SlimeAgent] = []
var selected_id := ""
var next_number := 1
var rng := RandomNumberGenerator.new()

func setup(root: Node3D, build_ref: SlimeBuildSystem) -> void:
    slime_root = root
    build_system = build_ref
    rng.randomize()

func clear() -> void:
    for slime in slimes:
        if is_instance_valid(slime):
            slime.queue_free()
    slimes.clear()
    selected_id = ""
    next_number = 1
    household_changed.emit()
    selection_changed.emit(null)

func add_slime(name_text: String, color: Color, stage := "adult", personality := "Bubbly", habits: Array[String] = []) -> SlimeAgent:
    var clean_name := name_text.strip_edges()
    if clean_name.is_empty():
        clean_name = "Slime %d" % next_number
    var slime := SlimeAgent.new()
    var new_id := "%d_%d" % [Time.get_ticks_msec(), next_number]
    next_number += 1
    slime_root.add_child(slime)
    slime.setup(new_id, clean_name, color, stage, build_system, self, personality, habits)
    var spawn := build_system.find_spawn_cell(Vector2i(4 + (slimes.size() % 3), 5))
    slime.global_position = build_system.cell_to_world(spawn) + Vector3(0, 0.02, 0)
    slimes.append(slime)
    household_changed.emit()
    if selected_id.is_empty():
        select_slime(slime.slime_id)
    return slime

func add_baby(parent_a_id: String, parent_b_id: String, baby_name: String) -> SlimeAgent:
    var a := get_slime(parent_a_id)
    var b := get_slime(parent_b_id)
    if a == null or b == null or a == b or a.age_stage != "adult" or b.age_stage != "adult":
        return null
    var mixed := Color(
        clampf((a.slime_color.r + b.slime_color.r) * 0.5 + rng.randf_range(-0.04, 0.04), 0.0, 1.0),
        clampf((a.slime_color.g + b.slime_color.g) * 0.5 + rng.randf_range(-0.04, 0.04), 0.0, 1.0),
        clampf((a.slime_color.b + b.slime_color.b) * 0.5 + rng.randf_range(-0.04, 0.04), 0.0, 1.0),
        1.0
    )
    var inherited_personality := a.personality if rng.randf() < 0.5 else b.personality
    var inherited_habits: Array[String] = []
    var pool: Array[String] = []
    for habit in a.habits:
        if not pool.has(habit):
            pool.append(habit)
    for habit in b.habits:
        if not pool.has(habit):
            pool.append(habit)
    pool.shuffle()
    for habit in pool:
        if inherited_habits.size() >= 2:
            break
        inherited_habits.append(habit)
    var baby := add_slime(baby_name, mixed, "baby", inherited_personality, inherited_habits)
    baby.parents = [a.slime_id, b.slime_id]
    for key in baby.traits.keys():
        var source = a if rng.randf() < 0.5 else b
        baby.traits[key] = clampf(float(source.traits.get(key, 0.5)) + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
    baby.relationships[a.slime_id] = 80.0
    baby.relationships[b.slime_id] = 80.0
    a.relationships[b.slime_id] = float(a.relationships.get(b.slime_id, 0.0)) + 18.0
    b.relationships[a.slime_id] = float(b.relationships.get(a.slime_id, 0.0)) + 18.0
    baby.global_position = a.global_position + Vector3(0.4, 0, 0.2)
    household_changed.emit()
    return baby

func tick(delta: float) -> void:
    for slime in slimes:
        slime.tick_sim(delta)

func select_slime(id_value: String) -> void:
    selected_id = id_value
    for slime in slimes:
        slime.set_selected(slime.slime_id == selected_id)
    selection_changed.emit(selected_slime())

func selected_slime() -> SlimeAgent:
    return get_slime(selected_id)

func get_slime(id_value: String) -> SlimeAgent:
    for slime in slimes:
        if slime.slime_id == id_value:
            return slime
    return null

func adult_slimes() -> Array[SlimeAgent]:
    var result: Array[SlimeAgent] = []
    for slime in slimes:
        if slime.age_stage == "adult":
            result.append(slime)
    return result

func find_nearest_other(id_value: String, position: Vector3) -> SlimeAgent:
    var best: SlimeAgent = null
    var distance := INF
    for slime in slimes:
        if slime.slime_id == id_value:
            continue
        var d := position.distance_squared_to(slime.global_position)
        if d < distance:
            distance = d
            best = slime
    return best

func serialize() -> Dictionary:
    var items: Array = []
    for slime in slimes:
        items.append(slime.serialize())
    return {"selected_id": selected_id, "next_number": next_number, "slimes": items}

func deserialize(data: Dictionary) -> void:
    clear()
    next_number = int(data.get("next_number", 1))
    for raw in data.get("slimes", []):
        var color := Color.from_string(String(raw.get("color", "68d7ffff")), Color("68d7ff"))
        var restored_habits: Array[String] = []
        for habit in raw.get("habits", []):
            restored_habits.append(String(habit))
        var slime := add_slime(
            String(raw.get("name", "Slime")),
            color,
            String(raw.get("age_stage", "adult")),
            String(raw.get("personality", "Bubbly")),
            restored_habits
        )
        slime.slime_id = String(raw.get("id", slime.slime_id))
        slime.restore(raw)
    var requested := String(data.get("selected_id", ""))
    if get_slime(requested):
        select_slime(requested)
    elif not slimes.is_empty():
        select_slime(slimes[0].slime_id)
    household_changed.emit()
