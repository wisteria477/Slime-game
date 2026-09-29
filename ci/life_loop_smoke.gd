extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error("LIFE LOOP TEST: " + message)

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)

    var build := SlimeBuildSystem.new()
    world.add_child(build)
    await process_frame
    build.make_starter_home()

    var slime_root := Node3D.new()
    world.add_child(slime_root)

    var household := SlimeHousehold.new()
    world.add_child(household)
    household.setup(slime_root, build)

    var a := household.add_slime(
        "Nim",
        Color("65ccff"),
        "adult",
        "Foodie",
        ["Snacky", "Toy Lover"],
        {"size":"Standard", "eyes":"Round", "core":"Warm", "antenna":"Curl"}
    )
    var b := household.add_slime(
        "Pip",
        Color("f39ac0"),
        "adult",
        "Bubbly",
        ["Chatty", "Cozy Seeker"],
        {"size":"Standard", "eyes":"Wide", "core":"Warm", "antenna":"Bubble"}
    )
    await process_frame

    _check(household.slimes.size() == 2, "two adults should exist")
    _check(a.visual_root != null and b.visual_root != null, "slimes should build a visual root")
    # Appearance-specific face nodes are optional for a future authored GLB. When
    # the procedural face is active, Wide eyes must remain part of the animation
    # reset baseline instead of being erased on the next expression update.
    if a.face_base_scales.has("EyeL") and b.face_base_scales.has("EyeL"):
        var round_eye_scale: Vector3 = a.face_base_scales.get("EyeL", Vector3.ZERO)
        var wide_eye_scale: Vector3 = b.face_base_scales.get("EyeL", Vector3.ZERO)
        _check(wide_eye_scale.y > round_eye_scale.y * 1.10, "Wide eye appearance should survive facial animation baselining")
        var wide_eye_before_restore := wide_eye_scale
        var b_snapshot := b.serialize()
        b.restore(b_snapshot)
        var wide_eye_after_restore: Vector3 = b.face_base_scales.get("EyeL", Vector3.ZERO)
        _check(wide_eye_after_restore.distance_to(wide_eye_before_restore) < 0.0001, "restoring a save should not compound slime appearance scale")
    _check(build.find_furniture("bed", a.current_cell()).size() > 0, "starter home needs a reachable bed")
    _check(build.find_furniture("stove", a.current_cell()).size() > 0, "starter home needs a reachable stove")
    _check(build.find_furniture("toilet", a.current_cell()).size() > 0, "starter home needs a reachable toilet")
    _check(build.find_furniture("bath", a.current_cell()).size() > 0 or build.find_furniture("shower", a.current_cell()).size() > 0, "starter home needs bathing")
    _check(build.find_furniture("workbench", a.current_cell()).size() > 0, "starter home needs a hobby object")

    var stove := build.find_furniture("stove", a.current_cell())
    if not stove.is_empty():
        var stove_item: Dictionary = stove.get("item", {})
        a.queue_interaction("cook", String(stove_item.get("id", "")), stove.get("cell", a.current_cell()), "", "Cook Meal")
        _check(not a.player_queue.is_empty() or a.action_kind == "cook", "manual cooking should enter action flow")

    var before_relation := float(a.relationships.get(b.slime_id, 0.0))
    _check(household.social_interact(a.slime_id, b.slime_id, "Chat"), "chat should execute")
    _check(float(a.relationships.get(b.slime_id, 0.0)) > before_relation, "chat should improve relationship")

    var baby := household.add_baby(a.slime_id, b.slime_id, "Bubble")
    _check(baby != null, "two adults should be able to have a baby")
    _check(household.slimes.size() == 3, "baby should join household")
    if baby:
        _check(baby.parents.has(a.slime_id) and baby.parents.has(b.slime_id), "baby should store both parents")

    var house_save := build.serialize()
    var household_save := household.serialize()
    _check(not house_save.is_empty(), "house should serialize")
    _check(not household_save.is_empty(), "household should serialize")
    _check(build.room_count() >= 1, "starter home should detect at least one room")
    _check(build.home_value() > 0, "starter home should have value")

    household.tick(1.0)
    household.tick_world(1, 9, 0, 1.0)

    if failures.is_empty():
        print("SLIME LIFE LIFE-LOOP SMOKE PASSED")
        quit(0)
    else:
        print("SLIME LIFE LIFE-LOOP SMOKE FAILED: %d issue(s)" % failures.size())
        quit(1)
