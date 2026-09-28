class_name SlimeHousehold
extends Node

signal household_changed
signal selection_changed(slime)

var slime_root: Node3D
var build_system: SlimeBuildSystem
var slimes: Array[SlimeAgent] = []
var selected_id := ""
var next_number := 1
var funds := 2500
var bills_due := 0
var last_billed_day := 0
var household_inventory: Array[Dictionary] = []
var achievements: Array[String] = []
var unlocks: Array[String] = []
var current_lot := "Home"
var lot_builds: Dictionary = {}
var relationship_events: Array[Dictionary] = []
var last_schedule_key := ""
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
    funds = 2500
    bills_due = 0
    last_billed_day = 0
    household_inventory.clear()
    achievements.clear()
    unlocks.clear()
    lot_builds.clear()
    relationship_events.clear()
    current_lot = "Home"
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
    var inherited_personality: String = a.personality if rng.randf() < 0.5 else b.personality
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
    a.gain_skill("parenting", 3.0)
    b.gain_skill("parenting", 3.0)
    _unlock_achievement("first_baby")
    household_changed.emit()
    return baby

func tick(delta: float) -> void:
    for slime in slimes:
        slime.tick_sim(delta)

func tick_world(day: int, hour: int, minute: int, delta: float) -> void:
    build_system.tick_environment(delta)
    var schedule_key := "%d-%02d-%02d" % [day, hour, minute]
    if schedule_key == last_schedule_key:
        return
    last_schedule_key = schedule_key

    if day > last_billed_day and day % 3 == 0 and hour == 8 and minute == 0:
        last_billed_day = day
        bills_due += 90 + int(float(build_system.home_value()) * 0.025)

    if hour == 7 and minute == 0:
        for slime in slimes:
            if slime.age_stage in ["child", "teen"]:
                slime.current_activity = "School"
                slime.school_grade = clampf(slime.school_grade + 1.5, 0.0, 100.0)
                slime.gain_skill("logic", 1.2)
                slime.gain_skill("social", 0.6)

    for slime in slimes:
        if slime.career == "None":
            continue
        var info: Dictionary = SlimeLifeRules.CAREERS.get(slime.career, {})
        if info.is_empty():
            continue
        var end_hour := int(info.get("end", -1))
        if hour == end_hour and minute == 0:
            var pay: int = int(info.get("pay", 0)) + maxi(0, slime.career_level - 1) * 18
            funds += pay
            slime.career_xp += 22.0
            slime.add_moodlet("Payday", "Happy", 6.0, 18.0)
            var career_skill := String(info.get("skill", ""))
            if not career_skill.is_empty():
                slime.gain_skill(career_skill, 4.0)
            if slime.career_xp >= 100.0 and slime.career_level < 10:
                slime.career_xp -= 100.0
                slime.career_level += 1
                funds += 100
                slime.add_moodlet("Promotion", "Happy", 12.0, 30.0)
                _unlock_achievement("career_two")

    if slimes.size() >= 5:
        _unlock_achievement("five_slimes")
    if build_system.home_value() >= 2500:
        _unlock_achievement("home_value")

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

func find_needy_baby(caregiver_id: String) -> SlimeAgent:
    var best: SlimeAgent = null
    var lowest := 101.0
    for slime in slimes:
        if slime.slime_id == caregiver_id or slime.age_stage != "baby":
            continue
        for value in slime.needs.values():
            var need_value := float(value)
            if need_value < lowest:
                lowest = need_value
                best = slime
    if lowest >= 58.0:
        return null
    return best

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

func can_afford(amount: int) -> bool:
    return funds >= amount

func spend(amount: int) -> bool:
    if amount <= 0:
        return true
    if funds < amount:
        return false
    funds -= amount
    household_changed.emit()
    return true

func earn(amount: int) -> void:
    funds += maxi(amount, 0)
    household_changed.emit()

func pay_bills() -> bool:
    if bills_due <= 0:
        return true
    if not spend(bills_due):
        return false
    bills_due = 0
    for slime in slimes:
        slime.add_moodlet("Bills Paid", "Happy", 4.0, 12.0)
    return true

func relationship_label(a: SlimeAgent, b: SlimeAgent) -> String:
    if a == null or b == null:
        return "Stranger"
    if String(a.relationship_flags.get(b.slime_id, "")) == "Spouse":
        return "Spouse"
    if String(a.relationship_flags.get(b.slime_id, "")) == "Partner":
        return "Partner"
    if String(a.relationship_flags.get(b.slime_id, "")) == "Crush":
        return "Crush"
    var score := float(a.relationships.get(b.slime_id, 0.0))
    if score <= -35.0:
        return "Enemy"
    if score >= 75.0:
        return "Best Friend"
    if score >= 35.0:
        return "Friend"
    if score >= 8.0:
        return "Acquaintance"
    return "Stranger"

func social_interact(a_id: String, b_id: String, interaction: String) -> bool:
    var a := get_slime(a_id)
    var b := get_slime(b_id)
    if a == null or b == null or a == b:
        return false
    var friendship_delta := 0.0
    var romance_delta := 0.0
    match interaction:
        "Chat":
            friendship_delta = 4.0
        "Joke":
            friendship_delta = 5.0
            a.add_moodlet("Shared a Laugh", "Playful", 5.0, 15.0)
            b.add_moodlet("Shared a Laugh", "Playful", 5.0, 15.0)
        "Compliment":
            friendship_delta = 6.0
            b.add_moodlet("Complimented", "Happy", 5.0, 16.0)
        "Hug":
            friendship_delta = 7.0
        "Argue":
            friendship_delta = -12.0
            a.add_moodlet("Argument", "Angry", 8.0, 20.0)
            b.add_moodlet("Argument", "Angry", 8.0, 20.0)
        "Apologize":
            friendship_delta = 10.0
        "Flirt":
            friendship_delta = 2.0
            romance_delta = 8.0
        "Kiss":
            romance_delta = 14.0
        "Propose":
            romance_delta = 20.0
    a.relationships[b.slime_id] = clampf(float(a.relationships.get(b.slime_id, 0.0)) + friendship_delta, -100.0, 100.0)
    b.relationships[a.slime_id] = clampf(float(b.relationships.get(a.slime_id, 0.0)) + friendship_delta, -100.0, 100.0)
    if romance_delta > 0.0:
        var romance_a := float(a.routine_memory.get("romance_%s" % b.slime_id, 0.0)) + romance_delta
        var romance_b := float(b.routine_memory.get("romance_%s" % a.slime_id, 0.0)) + romance_delta
        a.routine_memory["romance_%s" % b.slime_id] = clampf(romance_a, 0.0, 100.0)
        b.routine_memory["romance_%s" % a.slime_id] = clampf(romance_b, 0.0, 100.0)
        if romance_a >= 30.0:
            a.relationship_flags[b.slime_id] = "Crush"
            b.relationship_flags[a.slime_id] = "Crush"
        if romance_a >= 60.0:
            a.relationship_flags[b.slime_id] = "Partner"
            b.relationship_flags[a.slime_id] = "Partner"
        if interaction == "Propose" and romance_a >= 60.0:
            a.relationship_flags[b.slime_id] = "Spouse"
            b.relationship_flags[a.slime_id] = "Spouse"
    a.gain_skill("social", 2.0)
    b.gain_skill("social", 1.2)
    relationship_events.append({
        "a": a.slime_id,
        "b": b.slime_id,
        "interaction": interaction,
        "label": relationship_label(a, b),
    })
    if relationship_label(a, b) in ["Friend", "Best Friend"]:
        _unlock_achievement("first_friend")
    household_changed.emit()
    return true

func assign_career(slime_id: String, career_name: String) -> bool:
    var slime := get_slime(slime_id)
    if slime == null or not SlimeLifeRules.CAREERS.has(career_name):
        return false
    slime.assign_career(career_name)
    household_changed.emit()
    return true

func add_household_item(item_name: String, quantity := 1) -> void:
    for item in household_inventory:
        if String(item.get("name", "")) == item_name:
            item["quantity"] = int(item.get("quantity", 0)) + quantity
            return
    household_inventory.append({"name": item_name, "quantity": quantity})

func _unlock_achievement(id_value: String) -> void:
    if achievements.has(id_value):
        return
    achievements.append(id_value)
    var label := String(SlimeLifeRules.ACHIEVEMENTS.get(id_value, id_value))
    unlocks.append(label)
    for slime in slimes:
        slime.satisfaction += 50
        slime.add_moodlet("Achievement: %s" % label, "Happy", 8.0, 24.0)

func serialize() -> Dictionary:
    var items: Array = []
    for slime in slimes:
        items.append(slime.serialize())
    return {
        "selected_id": selected_id,
        "next_number": next_number,
        "slimes": items,
        "funds": funds,
        "bills_due": bills_due,
        "last_billed_day": last_billed_day,
        "household_inventory": household_inventory.duplicate(true),
        "achievements": achievements.duplicate(),
        "unlocks": unlocks.duplicate(),
        "current_lot": current_lot,
        "lot_builds": lot_builds.duplicate(true),
        "relationship_events": relationship_events.duplicate(true),
    }

func deserialize(data: Dictionary) -> void:
    clear()
    next_number = int(data.get("next_number", 1))
    funds = int(data.get("funds", 2500))
    bills_due = int(data.get("bills_due", 0))
    last_billed_day = int(data.get("last_billed_day", 0))
    household_inventory = data.get("household_inventory", []).duplicate(true)
    achievements.clear()
    for achievement in data.get("achievements", []):
        achievements.append(String(achievement))
    unlocks.clear()
    for unlock in data.get("unlocks", []):
        unlocks.append(String(unlock))
    current_lot = String(data.get("current_lot", "Home"))
    lot_builds = data.get("lot_builds", {}).duplicate(true)
    relationship_events = data.get("relationship_events", []).duplicate(true)
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
