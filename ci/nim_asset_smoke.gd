extends SceneTree

var failures: Array[String] = []

const REQUIRED_ANIMATIONS := ["Idle", "Happy", "Sad", "Angry", "Scared", "Tired", "Flirty"]
const REQUIRED_MORPHS := [
    "Squash",
    "Stretch",
    "Puddle",
    "Happy",
    "SadDroop",
    "AngryTense",
    "ScaredTall",
    "EmbarrassedShrink",
    "TiredMelt",
    "FlirtySway",
]

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error("NIM ASSET TEST: " + message)

func _find_named(node: Node, target: String) -> Node:
    if String(node.name) == target:
        return node
    for child in node.get_children():
        var found := _find_named(child, target)
        if found:
            return found
    return null

func _collect_animation_players(node: Node, output: Array[AnimationPlayer]) -> void:
    if node is AnimationPlayer:
        output.append(node as AnimationPlayer)
    for child in node.get_children():
        _collect_animation_players(child, output)

func _count_named_prefix(node: Node, prefix: String) -> int:
    var count := 1 if String(node.name).begins_with(prefix) else 0
    for child in node.get_children():
        count += _count_named_prefix(child, prefix)
    return count

func _has_animation(players: Array[AnimationPlayer], requested: String) -> bool:
    var needle := requested.to_lower()
    for player in players:
        for candidate in player.get_animation_list():
            var value := String(candidate).to_lower()
            if value == needle or value.ends_with("/" + needle) or value.ends_with("|" + needle):
                return true
    return false

func _run() -> void:
    var model_path := SlimeAgent.MODEL_PATH
    _check(ResourceLoader.exists(model_path), "production Nim GLB must exist at " + model_path)

    var packed := load(model_path) as PackedScene
    _check(packed != null, "production Nim GLB must import as a PackedScene")
    if packed == null:
        _finish()
        return

    var model := packed.instantiate()
    root.add_child(model)
    await process_frame

    var body := _find_named(model, "SK_Nim_Body") as MeshInstance3D
    _check(body != null, "V12.1 body mesh SK_Nim_Body must be present")
    if body and body.mesh:
        var morphs: Array[String] = []
        for index in range(body.mesh.get_blend_shape_count()):
            morphs.append(String(body.mesh.get_blend_shape_name(index)))
        for required in REQUIRED_MORPHS:
            _check(morphs.has(required), "missing required Nim morph: " + required)
    else:
        _check(false, "V12.1 body must expose a mesh for morph validation")

    _check(_find_named(model, "Nim_Eye_L") != null, "left authored eye must be present")
    _check(_find_named(model, "Nim_Eye_R") != null, "right authored eye must be present")
    _check(_find_named(model, "Nim_Mouth") != null, "authored mouth must be present")
    _check(_find_named(model, "Nim_Antenna") != null, "authored antenna must be present")
    _check(_find_named(model, "Nim_FloatingBubble") != null, "signature floating bubble must be present")
    _check(_count_named_prefix(model, "Nim_InnerCore_") >= 4, "warm inner core must retain all four cloud pieces")

    var players: Array[AnimationPlayer] = []
    _collect_animation_players(model, players)
    _check(not players.is_empty(), "production Nim must contain an AnimationPlayer")
    for required in REQUIRED_ANIMATIONS:
        _check(_has_animation(players, required), "missing required Nim animation: " + required)

    model.queue_free()
    await process_frame
    _finish()

func _finish() -> void:
    if failures.is_empty():
        print("NIM V12.1 ASSET SMOKE PASSED")
        quit(0)
        return
    print("NIM V12.1 ASSET SMOKE FAILED: %d issue(s)" % failures.size())
    quit(1)
