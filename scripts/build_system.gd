class_name SlimeBuildSystem
extends Node3D

signal changed

const GRID_SIZE := Vector2i(12, 10)
const CELL_SIZE := 1.35
const WALL_HEIGHT := 1.75
const FURNITURE_TYPES := ["bed", "food", "bath", "toy", "sofa", "toilet", "sink", "stove", "fridge", "table", "lamp", "bookshelf", "desk", "plant", "rug", "dresser", "workbench", "counter", "chair", "shower", "mirror", "wall_art"]
const TOOL_COSTS := {
    "floor": 8,
    "wall": 12,
    "door": 35,
    "window": 45,
    "stairs": 180,
    "platform": 40,
    "roof": 220,
    "erase": 0,
    "bed": 120,
    "food": 140,
    "bath": 180,
    "toy": 55,
    "sofa": 160,
    "toilet": 120,
    "sink": 90,
    "stove": 240,
    "fridge": 260,
    "table": 110,
    "lamp": 45,
    "bookshelf": 130,
    "desk": 150,
    "plant": 35,
    "rug": 40,
    "dresser": 120,
    "workbench": 260,
    "counter": 95,
    "chair": 55,
    "shower": 175,
    "mirror": 45,
    "wall_art": 35,
}
const TOOL_REFUNDS := {
    "floor": 4,
    "wall": 6,
    "door": 18,
}
const STRUCTURE_PALETTES := [
    {"name":"Warm Oak", "floor_a":Color("9a7e62"), "floor_b":Color("a8896b"), "wall":Color("c7b9a5"), "trim":Color("66584c")},
    {"name":"Sea Glass", "floor_a":Color("789a98"), "floor_b":Color("86aaa7"), "wall":Color("c8d8d2"), "trim":Color("4e6865")},
    {"name":"Berry Cream", "floor_a":Color("a88391"), "floor_b":Color("b78f9d"), "wall":Color("e1d1d4"), "trim":Color("71515c")},
    {"name":"Stone Moss", "floor_a":Color("858574"), "floor_b":Color("949482"), "wall":Color("c9c6b3"), "trim":Color("5e6252")},
]

var floors: Dictionary = {}
var walls: Dictionary = {}
var doors: Dictionary = {}
var furniture: Array[Dictionary] = []
var floor_root: Node3D
var wall_root: Node3D
var furniture_root: Node3D
var lot_root: Node3D
var context_root: Node3D
var roof_root: Node3D
var roof_enabled := false
var windows: Array[Dictionary] = []
var stairs: Array[Dictionary] = []
var platforms: Array[Dictionary] = []
var current_build_level := 0
var palette_index := 0

func _ready() -> void:
    context_root = Node3D.new()
    context_root.name = "NeighborhoodContext"
    add_child(context_root)
    _make_lot_context()

    lot_root = Node3D.new()
    lot_root.name = "House"
    add_child(lot_root)
    floor_root = Node3D.new()
    floor_root.name = "Floors"
    lot_root.add_child(floor_root)
    wall_root = Node3D.new()
    wall_root.name = "Walls"
    lot_root.add_child(wall_root)
    furniture_root = Node3D.new()
    furniture_root.name = "Furniture"
    lot_root.add_child(furniture_root)
    roof_root = Node3D.new()
    roof_root.name = "Roof"
    lot_root.add_child(roof_root)
    _make_lot_ground()

func make_starter_home() -> void:
    clear_house()
    for x in range(1, 10):
        for z in range(1, 8):
            _place_floor(Vector2i(x, z))
    for x in range(1, 10):
        _place_wall(Vector2i(x, 1), "N", false)
        _place_wall(Vector2i(x, 8), "N", false)
    for z in range(1, 8):
        _place_wall(Vector2i(1, z), "W", false)
        _place_wall(Vector2i(10, z), "W", false)
    _place_wall(Vector2i(5, 1), "N", true)
    _place_wall(Vector2i(5, 8), "N", true)
    for x in range(6, 10):
        _place_wall(Vector2i(x, 4), "N", false)
    _place_wall(Vector2i(8, 4), "N", true)
    for z in range(1, 4):
        _place_wall(Vector2i(6, z), "W", false)
    _place_wall(Vector2i(6, 3), "W", true)
    _place_furniture(Vector2i(8, 2), "bed")
    _place_furniture(Vector2i(2, 2), "food")
    _place_furniture(Vector2i(7, 2), "bath")
    _place_furniture(Vector2i(5, 6), "toy")
    _place_furniture(Vector2i(6, 5), "sofa")
    _place_furniture(Vector2i(3, 2), "fridge")
    _place_furniture(Vector2i(4, 2), "stove")
    _place_furniture(Vector2i(8, 3), "toilet")
    _place_furniture(Vector2i(7, 3), "sink")
    _place_furniture(Vector2i(4, 6), "bookshelf")
    _place_furniture(Vector2i(3, 6), "desk")
    _place_furniture(Vector2i(3, 5), "workbench")
    _place_furniture(Vector2i(5, 2), "counter")
    _place_furniture(Vector2i(5, 5), "table")
    _place_furniture(Vector2i(5, 4), "chair")
    _place_furniture(Vector2i(9, 3), "shower")
    _place_furniture(Vector2i(7, 4), "mirror")
    _place_furniture(Vector2i(8, 6), "plant")
    _place_furniture(Vector2i(7, 6), "lamp")
    _place_furniture(Vector2i(8, 5), "rug")
    set_cutaway_visible(true)
    changed.emit()

func clear_house() -> void:
    floors.clear()
    walls.clear()
    doors.clear()
    furniture.clear()
    windows.clear()
    stairs.clear()
    platforms.clear()
    roof_enabled = false
    current_build_level = 0
    for root in [floor_root, wall_root, furniture_root, roof_root]:
        if root:
            for child in root.get_children():
                child.free()
    changed.emit()

func tool_cost(tool: String) -> int:
    return int(TOOL_COSTS.get(tool, 0))

func place(cell: Vector2i, tool: String, orientation: String = "N") -> bool:
    if not cell_in_bounds(cell):
        return false
    match tool:
        "floor":
            _place_floor(cell)
        "wall":
            _place_wall(cell, orientation, false)
        "door":
            _place_wall(cell, orientation, true)
        "window":
            _place_window(cell, orientation)
        "stairs":
            _place_stairs(cell)
        "platform":
            _place_platform(cell)
        "roof":
            toggle_roof()
        "erase":
            _erase_cell(cell)
        _:
            if tool in FURNITURE_TYPES:
                _place_furniture(cell, tool)
            else:
                return false
    changed.emit()
    return true

func cell_in_bounds(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y

func cell_to_world(cell: Vector2i) -> Vector3:
    return Vector3(float(cell.x) * CELL_SIZE, 0.0, float(cell.y) * CELL_SIZE)

func world_to_cell(world: Vector3) -> Vector2i:
    return Vector2i(roundi(world.x / CELL_SIZE), roundi(world.z / CELL_SIZE))

func is_walkable(cell: Vector2i) -> bool:
    if not cell_in_bounds(cell):
        return false
    if not floors.has(_cell_key(cell)):
        return false
    return not _furniture_blocks_cell(cell)

func find_spawn_cell(preferred := Vector2i(4, 5)) -> Vector2i:
    if is_walkable(preferred):
        return preferred
    for z in range(GRID_SIZE.y):
        for x in range(GRID_SIZE.x):
            var c := Vector2i(x, z)
            if is_walkable(c):
                return c
    return Vector2i(0, 0)

func random_walkable_cell(rng: RandomNumberGenerator) -> Vector2i:
    var candidates: Array[Vector2i] = []
    for z in range(GRID_SIZE.y):
        for x in range(GRID_SIZE.x):
            var c := Vector2i(x, z)
            if is_walkable(c):
                candidates.append(c)
    if candidates.is_empty():
        return Vector2i.ZERO
    return candidates[rng.randi_range(0, candidates.size() - 1)]

func path_between(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    if not is_walkable(from_cell) or not is_walkable(to_cell):
        return result
    if from_cell == to_cell:
        return [from_cell]
    var frontier: Array[Vector2i] = [from_cell]
    var came_from: Dictionary = {_cell_key(from_cell): from_cell}
    var head := 0
    while head < frontier.size():
        var current := frontier[head]
        head += 1
        if current == to_cell:
            break
        for next_cell in _neighbors(current):
            var key := _cell_key(next_cell)
            if came_from.has(key):
                continue
            if not is_walkable(next_cell):
                continue
            if _edge_blocked(current, next_cell):
                continue
            came_from[key] = current
            frontier.append(next_cell)
    if not came_from.has(_cell_key(to_cell)):
        return result
    var cursor := to_cell
    result.push_front(cursor)
    while cursor != from_cell:
        cursor = came_from[_cell_key(cursor)]
        result.push_front(cursor)
    return result

func find_furniture(kind: String, from_cell: Vector2i) -> Dictionary:
    var best: Dictionary = {}
    var best_length := 999999
    for item in furniture:
        if String(item.get("type", "")) != kind:
            continue
        var raw: Array = item.get("cell", [0, 0])
        var furniture_cell := Vector2i(int(raw[0]), int(raw[1]))
        for candidate in _neighbors(furniture_cell):
            if not is_walkable(candidate):
                continue
            var path := path_between(from_cell, candidate)
            if not path.is_empty() and path.size() < best_length:
                best_length = path.size()
                best = {
                    "type": kind,
                    "cell": candidate,
                    "furniture_cell": furniture_cell,
                    "item": item,
                    "path_length": path.size(),
                }
    return best

func find_first_furniture(kinds: Array[String], from_cell: Vector2i) -> Dictionary:
    var best: Dictionary = {}
    var best_length := 999999
    for kind in kinds:
        var result := find_furniture(kind, from_cell)
        if result.is_empty():
            continue
        var length := int(result.get("path_length", 999999))
        if length < best_length:
            best_length = length
            best = result
    return best


func furniture_at_cell(cell: Vector2i) -> Dictionary:
    for item in furniture:
        var raw: Array = item.get("cell", [999, 999])
        if Vector2i(int(raw[0]), int(raw[1])) == cell:
            return item
    return {}

func interaction_target_for_item(item: Dictionary, from_cell: Vector2i) -> Vector2i:
    if item.is_empty():
        return from_cell
    var raw: Array = item.get("cell", [from_cell.x, from_cell.y])
    var item_cell := Vector2i(int(raw[0]), int(raw[1]))
    var best := from_cell
    var best_length := 999999
    for candidate in _neighbors(item_cell):
        if not is_walkable(candidate):
            continue
        var route := path_between(from_cell, candidate)
        if route.is_empty() and candidate != from_cell:
            continue
        if route.size() < best_length:
            best_length = route.size()
            best = candidate
    return best

func interaction_options_for_type(kind: String) -> Array[Dictionary]:
    match kind:
        "bed":
            return [
                {"label":"Sleep", "action":"sleep"},
                {"label":"Nap", "action":"sleep"},
                {"label":"Relax", "action":"relax"},
            ]
        "stove":
            return [{"label":"Cook Meal", "action":"cook"}]
        "fridge", "food":
            return [{"label":"Grab Food", "action":"eat"}]
        "toilet":
            return [{"label":"Use Bathroom", "action":"bathroom"}]
        "bath", "shower":
            return [{"label":"Bathe", "action":"bathe"}]
        "sink", "mirror":
            return [
                {"label":"Wash Up", "action":"wash_up"},
                {"label":"Clean Sink", "action":"clean_object"},
            ]
        "sofa", "chair":
            return [{"label":"Relax", "action":"relax"}]
        "toy":
            return [{"label":"Play / Hobby", "action":"hobby"}]
        "bookshelf":
            return [{"label":"Read", "action":"hobby"}]
        "desk":
            return [{"label":"Creative Project", "action":"hobby"}]
        "workbench":
            return [
                {"label":"Tinker", "action":"hobby"},
                {"label":"Repair", "action":"repair_object"},
            ]
        "table":
            return [{"label":"Sit & Relax", "action":"relax"}]
        _:
            return []

func serialize() -> Dictionary:
    var floor_data: Array = []
    var wall_data: Array = []
    var door_data: Array = []
    for key in floors.keys():
        var c := _key_to_cell(String(key))
        floor_data.append([c.x, c.y])
    for key in walls.keys():
        var info := _wall_from_key(String(key))
        wall_data.append([info[0].x, info[0].y, info[1]])
    for key in doors.keys():
        var info := _wall_from_key(String(key))
        door_data.append([info[0].x, info[0].y, info[1]])
    return {
        "floors": floor_data,
        "walls": wall_data,
        "doors": door_data,
        "furniture": furniture.duplicate(true),
        "windows": windows.duplicate(true),
        "stairs": stairs.duplicate(true),
        "platforms": platforms.duplicate(true),
        "roof_enabled": roof_enabled,
        "current_build_level": current_build_level,
        "palette_index": palette_index,
    }

func deserialize(data: Dictionary) -> void:
    clear_house()
    for raw in data.get("floors", []):
        _place_floor(Vector2i(int(raw[0]), int(raw[1])))
    for raw in data.get("walls", []):
        _place_wall(Vector2i(int(raw[0]), int(raw[1])), String(raw[2]), false)
    for raw in data.get("doors", []):
        _place_wall(Vector2i(int(raw[0]), int(raw[1])), String(raw[2]), true)
    for item in data.get("furniture", []):
        var raw_cell: Array = item.get("cell", [0, 0])
        var restored_cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
        _place_furniture(restored_cell, String(item.get("type", "sofa")))
        for i in range(furniture.size() - 1, -1, -1):
            var created_raw: Array = furniture[i].get("cell", [0, 0])
            if Vector2i(int(created_raw[0]), int(created_raw[1])) == restored_cell:
                furniture[i]["id"] = String(item.get("id", furniture[i].get("id", "")))
                furniture[i]["condition"] = float(item.get("condition", 100.0))
                furniture[i]["cleanliness"] = float(item.get("cleanliness", 100.0))
                furniture[i]["quality"] = int(item.get("quality", 1))
                furniture[i]["owner_id"] = String(item.get("owner_id", ""))
                furniture[i]["rotation"] = int(item.get("rotation", 0))
                break
    for item in data.get("windows", []):
        var raw_window: Array = item.get("cell", [0, 0])
        _place_window(Vector2i(int(raw_window[0]), int(raw_window[1])), String(item.get("orientation", "N")))
    for item in data.get("stairs", []):
        var raw_stair: Array = item.get("cell", [0, 0])
        _place_stairs(Vector2i(int(raw_stair[0]), int(raw_stair[1])))
    for item in data.get("platforms", []):
        var raw_platform: Array = item.get("cell", [0, 0])
        _place_platform(Vector2i(int(raw_platform[0]), int(raw_platform[1])))
    current_build_level = int(data.get("current_build_level", 0))
    palette_index = clampi(int(data.get("palette_index", 0)), 0, STRUCTURE_PALETTES.size() - 1)
    _apply_structure_palette()
    if bool(data.get("roof_enabled", false)):
        toggle_roof()
    set_cutaway_visible(true)
    changed.emit()

func _make_lot_context() -> void:
    var world_ground := MeshInstance3D.new()
    world_ground.name = "WorldGround"
    var world_mesh := BoxMesh.new()
    world_mesh.size = Vector3(46.0, 0.12, 42.0)
    world_ground.mesh = world_mesh
    world_ground.position = Vector3((GRID_SIZE.x - 1) * CELL_SIZE * 0.5, -0.24, (GRID_SIZE.y - 1) * CELL_SIZE * 0.5)
    world_ground.material_override = _material(Color("6f8a72"), 0.98)
    context_root.add_child(world_ground)

    var road := MeshInstance3D.new()
    road.name = "Road"
    var road_mesh := BoxMesh.new()
    road_mesh.size = Vector3(38.0, 0.06, 4.6)
    road.mesh = road_mesh
    road.position = Vector3((GRID_SIZE.x - 1) * CELL_SIZE * 0.5, -0.14, GRID_SIZE.y * CELL_SIZE + 5.0)
    road.material_override = _material(Color("4d5456"), 0.98)
    context_root.add_child(road)

    var sidewalk := MeshInstance3D.new()
    sidewalk.name = "Sidewalk"
    var sidewalk_mesh := BoxMesh.new()
    sidewalk_mesh.size = Vector3(38.0, 0.08, 1.25)
    sidewalk.mesh = sidewalk_mesh
    sidewalk.position = Vector3((GRID_SIZE.x - 1) * CELL_SIZE * 0.5, -0.08, GRID_SIZE.y * CELL_SIZE + 2.25)
    sidewalk.material_override = _material(Color("b5b0a5"), 0.94)
    context_root.add_child(sidewalk)

    var path := MeshInstance3D.new()
    path.name = "FrontPath"
    var path_mesh := BoxMesh.new()
    path_mesh.size = Vector3(1.4, 0.06, 5.2)
    path.mesh = path_mesh
    path.position = Vector3(5.0 * CELL_SIZE, -0.035, GRID_SIZE.y * CELL_SIZE - 0.35)
    path.material_override = _material(Color("b9a78d"), 0.92)
    context_root.add_child(path)

    var tree_positions := [
        Vector3(-3.0, 0.0, 2.0),
        Vector3(19.0, 0.0, 3.0),
        Vector3(-2.5, 0.0, 13.5),
        Vector3(19.5, 0.0, 14.0),
        Vector3(1.0, 0.0, -3.0),
        Vector3(16.5, 0.0, -2.5),
    ]
    for position_value in tree_positions:
        _make_context_tree(position_value)

func _make_context_tree(position_value: Vector3) -> void:
    var root := Node3D.new()
    root.position = position_value
    context_root.add_child(root)
    _box(root, Vector3(0.34, 1.4, 0.34), Vector3(0, 0.70, 0), Color("6b513f"))
    _sphere(root, 0.95, Vector3(0, 1.75, 0), Color("4f7754"))
    _sphere(root, 0.68, Vector3(0.52, 1.62, 0.18), Color("5e865e"))
    _sphere(root, 0.62, Vector3(-0.48, 1.58, -0.12), Color("5a8059"))

func _make_lot_ground() -> void:
    var ground := MeshInstance3D.new()
    ground.name = "LotGround"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(GRID_SIZE.x * CELL_SIZE + 2.4, 0.07, GRID_SIZE.y * CELL_SIZE + 2.4)
    ground.mesh = mesh
    ground.position = Vector3((GRID_SIZE.x - 1) * CELL_SIZE * 0.5, -0.10, (GRID_SIZE.y - 1) * CELL_SIZE * 0.5)
    ground.material_override = _material(Color("718d70"), 0.96)
    add_child(ground)

func _place_floor(cell: Vector2i) -> void:
    var key := _cell_key(cell)
    if floors.has(key):
        return
    floors[key] = true
    var obj := MeshInstance3D.new()
    obj.name = "Floor_%s" % key
    var mesh := BoxMesh.new()
    mesh.size = Vector3(CELL_SIZE * 0.985, 0.08, CELL_SIZE * 0.985)
    obj.mesh = mesh
    obj.position = cell_to_world(cell) + Vector3(0, 0.015, 0)
    var palette: Dictionary = STRUCTURE_PALETTES[palette_index]
    var floor_color: Color = palette["floor_a"] if (cell.x + cell.y) % 2 == 0 else palette["floor_b"]
    obj.material_override = _material(floor_color, 0.88)
    floor_root.add_child(obj)

func _place_wall(cell: Vector2i, orientation: String, is_door: bool) -> void:
    var o := "W" if orientation == "W" else "N"
    var key := _wall_key(cell, o)
    walls[key] = true
    if is_door:
        doors[key] = true
    else:
        doors.erase(key)
    var old := wall_root.get_node_or_null(_wall_node_name(key))
    if old:
        old.free()
    var root := Node3D.new()
    root.name = _wall_node_name(key)
    wall_root.add_child(root)
    var center := cell_to_world(cell)
    if o == "N":
        center += Vector3(0, WALL_HEIGHT * 0.5, -CELL_SIZE * 0.5)
    else:
        center += Vector3(-CELL_SIZE * 0.5, WALL_HEIGHT * 0.5, 0)
    if is_door:
        _make_door_visual(root, center, o)
    else:
        var body := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = Vector3(CELL_SIZE, WALL_HEIGHT, 0.10) if o == "N" else Vector3(0.10, WALL_HEIGHT, CELL_SIZE)
        body.mesh = mesh
        body.position = center
        var palette: Dictionary = STRUCTURE_PALETTES[palette_index]
        body.material_override = _material(palette["wall"], 0.92)
        var base_trim := MeshInstance3D.new()
        var trim_mesh := BoxMesh.new()
        trim_mesh.size = Vector3(CELL_SIZE, 0.16, 0.14) if o == "N" else Vector3(0.14, 0.16, CELL_SIZE)
        base_trim.mesh = trim_mesh
        base_trim.position = center - Vector3(0, WALL_HEIGHT * 0.5 - 0.08, 0)
        base_trim.material_override = _material(palette["trim"], 0.94)
        root.add_child(base_trim)
        root.add_child(body)

func cycle_palette() -> String:
    palette_index = (palette_index + 1) % STRUCTURE_PALETTES.size()
    _apply_structure_palette()
    changed.emit()
    return String((STRUCTURE_PALETTES[palette_index] as Dictionary).get("name", "Palette"))

func _apply_structure_palette() -> void:
    if floor_root == null or wall_root == null:
        return
    var palette: Dictionary = STRUCTURE_PALETTES[palette_index]
    for child in floor_root.get_children():
        if child is MeshInstance3D:
            var key := String(child.name).trim_prefix("Floor_")
            var parts := key.split("_")
            var checker := 0
            if parts.size() >= 2:
                checker = int(parts[0]) + int(parts[1])
            var floor_color: Color = palette["floor_a"] if checker % 2 == 0 else palette["floor_b"]
            (child as MeshInstance3D).material_override = _material(floor_color, 0.88)
    for root in wall_root.get_children():
        for child in root.get_children():
            if child is MeshInstance3D:
                var mesh_child := child as MeshInstance3D
                if child.name == "":
                    continue
                var size_y := 0.0
                if mesh_child.mesh is BoxMesh:
                    size_y = (mesh_child.mesh as BoxMesh).size.y
                if size_y > WALL_HEIGHT * 0.7:
                    mesh_child.material_override = _material(palette["wall"], 0.92)
                elif size_y < 0.25:
                    mesh_child.material_override = _material(palette["trim"], 0.94)

func _make_door_visual(root: Node3D, center: Vector3, orientation: String) -> void:
    var frame_mat := _material(Color("5a4a3d"), 0.92)
    var width := CELL_SIZE
    var post_h := WALL_HEIGHT
    for side in [-1.0, 1.0]:
        var post := MeshInstance3D.new()
        var post_mesh := BoxMesh.new()
        post_mesh.size = Vector3(0.12, post_h, 0.12)
        post.mesh = post_mesh
        if orientation == "N":
            post.position = center + Vector3(side * width * 0.43, 0, 0)
        else:
            post.position = center + Vector3(0, 0, side * width * 0.43)
        post.material_override = frame_mat
        root.add_child(post)
    var header := MeshInstance3D.new()
    var header_mesh := BoxMesh.new()
    header_mesh.size = Vector3(width * 0.92, 0.14, 0.12) if orientation == "N" else Vector3(0.12, 0.14, width * 0.92)
    header.mesh = header_mesh
    header.position = center + Vector3(0, WALL_HEIGHT * 0.46, 0)
    header.material_override = frame_mat
    root.add_child(header)

    var threshold := MeshInstance3D.new()
    var threshold_mesh := BoxMesh.new()
    threshold_mesh.size = Vector3(width * 0.9, 0.06, 0.18) if orientation == "N" else Vector3(0.18, 0.06, width * 0.9)
    threshold.mesh = threshold_mesh
    threshold.position = center - Vector3(0, WALL_HEIGHT * 0.5 - 0.03, 0)
    threshold.material_override = _material(Color("3e342d"), 0.96)
    root.add_child(threshold)

    var door_panel := MeshInstance3D.new()
    var door_mesh := BoxMesh.new()
    door_mesh.size = Vector3(width * 0.72, WALL_HEIGHT * 0.82, 0.07) if orientation == "N" else Vector3(0.07, WALL_HEIGHT * 0.82, width * 0.72)
    door_panel.mesh = door_mesh
    door_panel.position = center - Vector3(0, WALL_HEIGHT * 0.08, 0)
    door_panel.material_override = _material(Color("8b6b52"), 0.86)
    root.add_child(door_panel)

    var knob := MeshInstance3D.new()
    var knob_mesh := SphereMesh.new()
    knob_mesh.radius = 0.055
    knob_mesh.height = 0.11
    knob.mesh = knob_mesh
    if orientation == "N":
        knob.position = door_panel.position + Vector3(width * 0.24, 0, -0.06)
    else:
        knob.position = door_panel.position + Vector3(-0.06, 0, width * 0.24)
    var knob_mat := StandardMaterial3D.new()
    knob_mat.albedo_color = Color("c9a45f")
    knob_mat.metallic = 0.7
    knob_mat.roughness = 0.28
    knob.material_override = knob_mat
    root.add_child(knob)

func _place_furniture(cell: Vector2i, kind: String) -> void:
    if not floors.has(_cell_key(cell)):
        return
    _remove_furniture_at(cell)
    var node := Node3D.new()
    node.name = _furniture_node_name(cell)
    node.position = cell_to_world(cell)
    furniture_root.add_child(node)
    _make_furniture_visual(node, kind)
    furniture.append({
        "id": "%s_%d_%d_%d" % [kind, cell.x, cell.y, Time.get_ticks_msec()],
        "type": kind,
        "cell": [cell.x, cell.y],
        "condition": 100.0,
        "cleanliness": 100.0,
        "quality": 1,
        "owner_id": "",
        "rotation": 0,
    })

func _make_furniture_visual(root: Node3D, kind: String) -> void:
    match kind:
        "bed":
            _box(root, Vector3(1.12, 0.22, 1.18), Vector3(0, 0.15, 0), Color("675244"))
            _box(root, Vector3(1.04, 0.24, 1.08), Vector3(0, 0.31, 0), Color("e7dfd5"))
            _box(root, Vector3(1.00, 0.10, 0.52), Vector3(0, 0.46, 0.25), Color("8f76ad"))
            _box(root, Vector3(0.42, 0.12, 0.28), Vector3(0, 0.51, -0.34), Color("f3eee7"))
            _box(root, Vector3(1.08, 0.72, 0.10), Vector3(0, 0.56, 0.54), Color("66503f"))
        "food":
            _box(root, Vector3(0.86, 1.05, 0.86), Vector3(0, 0.53, 0), Color("547a62"))
            _box(root, Vector3(0.72, 0.07, 0.72), Vector3(0, 1.08, 0), Color("b8ccb8"))
            _sphere(root, 0.12, Vector3(-0.18, 1.19, -0.04), Color("e7b354"))
            _sphere(root, 0.11, Vector3(0.12, 1.18, 0.08), Color("cf6f68"))
        "bath":
            _box(root, Vector3(1.16, 0.48, 0.96), Vector3(0, 0.25, 0), Color("d5e2df"))
            _box(root, Vector3(0.94, 0.18, 0.74), Vector3(0, 0.42, 0), Color("76b9c6"))
            _box(root, Vector3(0.08, 0.38, 0.08), Vector3(0.42, 0.67, 0.26), Color("76898a"))
        "toy":
            _sphere(root, 0.34, Vector3(-0.18, 0.34, 0), Color("d75f82"))
            _sphere(root, 0.28, Vector3(0.22, 0.28, 0.12), Color("d69b43"))
            _box(root, Vector3(0.38, 0.14, 0.38), Vector3(0.08, 0.12, -0.24), Color("72a8b0"))
        "sofa":
            _box(root, Vector3(1.22, 0.36, 0.78), Vector3(0, 0.23, 0), Color("527754"))
            _box(root, Vector3(1.18, 0.56, 0.18), Vector3(0, 0.60, 0.30), Color("456846"))
            _box(root, Vector3(0.18, 0.48, 0.78), Vector3(-0.58, 0.40, 0), Color("456846"))
            _box(root, Vector3(0.18, 0.48, 0.78), Vector3(0.58, 0.40, 0), Color("456846"))
            _box(root, Vector3(0.48, 0.12, 0.48), Vector3(-0.27, 0.45, -0.05), Color("5f865f"))
            _box(root, Vector3(0.48, 0.12, 0.48), Vector3(0.27, 0.45, -0.05), Color("5f865f"))
        "toilet":
            _box(root, Vector3(0.56, 0.42, 0.66), Vector3(0, 0.22, 0.05), Color("e1e9e7"))
            _box(root, Vector3(0.58, 0.60, 0.22), Vector3(0, 0.56, 0.30), Color("c9d9d8"))
            _box(root, Vector3(0.52, 0.08, 0.52), Vector3(0, 0.47, -0.02), Color("f4f7f6"))
        "sink":
            _box(root, Vector3(0.82, 0.70, 0.56), Vector3(0, 0.36, 0), Color("8fa9a5"))
            _box(root, Vector3(0.76, 0.12, 0.58), Vector3(0, 0.78, 0), Color("e3ecea"))
            _box(root, Vector3(0.08, 0.28, 0.08), Vector3(0, 0.97, 0.10), Color("6c7a7b"))
            _box(root, Vector3(0.28, 0.06, 0.08), Vector3(0, 1.08, 0.10), Color("6c7a7b"))
        "stove":
            _box(root, Vector3(0.90, 0.86, 0.76), Vector3(0, 0.45, 0), Color("5f686c"))
            _box(root, Vector3(0.78, 0.06, 0.66), Vector3(0, 0.91, 0), Color("272c2f"))
            for x in [-0.22, 0.22]:
                for z in [-0.17, 0.17]:
                    _sphere(root, 0.10, Vector3(x, 0.96, z), Color("1f2426"))
            for x in [-0.23, 0.0, 0.23]:
                _sphere(root, 0.045, Vector3(x, 0.72, -0.39), Color("b8b8b2"))
        "fridge":
            _box(root, Vector3(0.84, 1.44, 0.80), Vector3(0, 0.72, 0), Color("b8c8c6"))
            _box(root, Vector3(0.76, 0.04, 0.82), Vector3(0, 0.87, -0.405), Color("91a5a4"))
            _box(root, Vector3(0.04, 0.38, 0.04), Vector3(0.29, 1.05, -0.43), Color("4d595a"))
            _box(root, Vector3(0.04, 0.28, 0.04), Vector3(0.29, 0.46, -0.43), Color("4d595a"))
        "table":
            _box(root, Vector3(1.10, 0.12, 0.90), Vector3(0, 0.66, 0), Color("8a6a50"))
            for x in [-0.42, 0.42]:
                for z in [-0.32, 0.32]:
                    _box(root, Vector3(0.10, 0.62, 0.10), Vector3(x, 0.32, z), Color("6b513f"))
        "chair":
            _box(root, Vector3(0.55, 0.10, 0.55), Vector3(0, 0.48, 0), Color("8a6a50"))
            _box(root, Vector3(0.55, 0.60, 0.10), Vector3(0, 0.76, 0.24), Color("725744"))
            for x in [-0.20, 0.20]:
                _box(root, Vector3(0.08, 0.46, 0.08), Vector3(x, 0.24, 0), Color("654c3b"))
        "lamp":
            _box(root, Vector3(0.16, 0.86, 0.16), Vector3(0, 0.44, 0), Color("5a4d42"))
            _sphere(root, 0.31, Vector3(0, 0.98, 0), Color("ffd98a"))
            var light := OmniLight3D.new()
            light.position = Vector3(0, 1.0, 0)
            light.light_color = Color("ffdca0")
            light.light_energy = 0.75
            light.omni_range = 3.6
            light.shadow_enabled = false
            root.add_child(light)
        "bookshelf":
            _box(root, Vector3(1.04, 1.20, 0.32), Vector3(0, 0.60, 0), Color("66503f"))
            for y in [0.28, 0.56, 0.84]:
                _box(root, Vector3(0.90, 0.07, 0.36), Vector3(0, y, -0.02), Color("4f3e32"))
            for x in [-0.30, -0.10, 0.12, 0.31]:
                _box(root, Vector3(0.10, 0.26, 0.20), Vector3(x, 0.44, -0.18), Color("7894b4") if x < 0 else Color("d39b66"))
        "desk":
            _box(root, Vector3(1.10, 0.12, 0.62), Vector3(0, 0.70, 0), Color("81624a"))
            _box(root, Vector3(0.14, 0.66, 0.14), Vector3(-0.43, 0.34, 0.20), Color("66503f"))
            _box(root, Vector3(0.14, 0.66, 0.14), Vector3(0.43, 0.34, 0.20), Color("66503f"))
            _box(root, Vector3(0.34, 0.20, 0.42), Vector3(0.32, 0.56, 0), Color("6b513f"))
        "counter":
            _box(root, Vector3(1.05, 0.84, 0.66), Vector3(0, 0.43, 0), Color("7f8d85"))
            _box(root, Vector3(1.10, 0.10, 0.72), Vector3(0, 0.90, 0), Color("d7d0c3"))
            _box(root, Vector3(0.03, 0.46, 0.03), Vector3(0, 0.48, -0.35), Color("4e5854"))
        "shower":
            _box(root, Vector3(0.92, 0.08, 0.92), Vector3(0, 0.05, 0), Color("d9e7e5"))
            _box(root, Vector3(0.06, 1.54, 0.92), Vector3(0.43, 0.80, 0), Color("73aab2"))
            _box(root, Vector3(0.92, 1.54, 0.05), Vector3(0, 0.80, 0.43), Color("8cc3ca"))
            _sphere(root, 0.10, Vector3(0.25, 1.40, 0.28), Color("697b7c"))
        "mirror":
            _box(root, Vector3(0.72, 0.92, 0.06), Vector3(0, 0.92, 0.28), Color("9cc7cb"))
            _box(root, Vector3(0.82, 1.02, 0.04), Vector3(0, 0.92, 0.31), Color("66503f"))
        "plant":
            _box(root, Vector3(0.42, 0.30, 0.42), Vector3(0, 0.16, 0), Color("9c6c4f"))
            _sphere(root, 0.34, Vector3(0, 0.62, 0), Color("4f8059"))
            _sphere(root, 0.24, Vector3(0.20, 0.78, 0.06), Color("629763"))
            _sphere(root, 0.22, Vector3(-0.20, 0.76, -0.04), Color("5b8e5d"))
        "rug":
            _box(root, Vector3(1.18, 0.035, 1.02), Vector3(0, 0.04, 0), Color("a86d80"))
            _box(root, Vector3(0.88, 0.038, 0.72), Vector3(0, 0.044, 0), Color("c08b9e"))
        "dresser":
            _box(root, Vector3(1.02, 0.88, 0.48), Vector3(0, 0.45, 0), Color("795a43"))
            for y in [0.25, 0.48, 0.71]:
                _box(root, Vector3(0.88, 0.05, 0.05), Vector3(0, y, -0.25), Color("5d4535"))
        "workbench":
            _box(root, Vector3(1.16, 0.14, 0.66), Vector3(0, 0.72, 0), Color("72563f"))
            _box(root, Vector3(0.18, 0.70, 0.18), Vector3(-0.42, 0.36, 0.20), Color("55504a"))
            _box(root, Vector3(0.18, 0.70, 0.18), Vector3(0.42, 0.36, 0.20), Color("55504a"))
            _box(root, Vector3(0.50, 0.08, 0.20), Vector3(0.16, 0.84, 0), Color("87969a"))
        "wall_art":
            _box(root, Vector3(0.74, 0.62, 0.05), Vector3(0, 1.02, 0.30), Color("725744"))
            _box(root, Vector3(0.62, 0.50, 0.03), Vector3(0, 1.02, 0.27), Color("d9a66f"))

func _box(root: Node3D, size: Vector3, position: Vector3, color: Color) -> void:
    var m := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    m.mesh = mesh
    m.position = position
    m.material_override = _material(color, 0.8)
    root.add_child(m)

func _sphere(root: Node3D, radius: float, position: Vector3, color: Color) -> void:
    var m := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    m.mesh = mesh
    m.position = position
    m.material_override = _material(color, 0.72)
    root.add_child(m)

func make_park() -> void:
    clear_house()
    for x in range(1, 10):
        for z in range(1, 8):
            _place_floor(Vector2i(x, z))
    _place_furniture(Vector2i(3, 3), "sofa")
    _place_furniture(Vector2i(7, 3), "sofa")
    _place_furniture(Vector2i(5, 5), "toy")
    _place_furniture(Vector2i(3, 6), "plant")
    _place_furniture(Vector2i(7, 6), "plant")
    changed.emit()

func make_cafe() -> void:
    clear_house()
    for x in range(1, 10):
        for z in range(1, 8):
            _place_floor(Vector2i(x, z))
    for x in range(1, 10):
        _place_wall(Vector2i(x, 1), "N", false)
    for z in range(1, 8):
        _place_wall(Vector2i(1, z), "W", false)
    _place_wall(Vector2i(5, 1), "N", true)
    _place_furniture(Vector2i(3, 3), "table")
    _place_furniture(Vector2i(6, 3), "table")
    _place_furniture(Vector2i(8, 2), "food")
    _place_furniture(Vector2i(7, 2), "stove")
    _place_furniture(Vector2i(6, 2), "fridge")
    _place_furniture(Vector2i(2, 6), "sofa")
    changed.emit()

func make_workshop() -> void:
    clear_house()
    for x in range(1, 10):
        for z in range(1, 8):
            _place_floor(Vector2i(x, z))
    for x in range(1, 10):
        _place_wall(Vector2i(x, 1), "N", false)
    _place_wall(Vector2i(5, 1), "N", true)
    _place_furniture(Vector2i(3, 3), "workbench")
    _place_furniture(Vector2i(6, 3), "workbench")
    _place_furniture(Vector2i(3, 5), "desk")
    _place_furniture(Vector2i(6, 5), "bookshelf")
    changed.emit()

func _place_window(cell: Vector2i, orientation: String) -> void:
    var o := "W" if orientation == "W" else "N"
    var root := Node3D.new()
    root.name = "Window_%d_%d_%s_%d" % [cell.x, cell.y, o, windows.size()]
    var center := cell_to_world(cell) + Vector3(0, 1.05, 0)
    if o == "N":
        center.z -= CELL_SIZE * 0.5 - 0.02
    else:
        center.x -= CELL_SIZE * 0.5 - 0.02

    var glass_node := MeshInstance3D.new()
    var glass_mesh := BoxMesh.new()
    glass_mesh.size = Vector3(CELL_SIZE * 0.70, 0.72, 0.035) if o == "N" else Vector3(0.035, 0.72, CELL_SIZE * 0.70)
    glass_node.mesh = glass_mesh
    glass_node.position = center
    var glass := StandardMaterial3D.new()
    glass.albedo_color = Color(0.52, 0.80, 0.86, 0.38)
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.metallic = 0.04
    glass.roughness = 0.08
    glass_node.material_override = glass
    root.add_child(glass_node)

    var frame_color := Color("5a4a3d")
    for side in [-1.0, 1.0]:
        var vertical := MeshInstance3D.new()
        var vmesh := BoxMesh.new()
        vmesh.size = Vector3(0.08, 0.86, 0.08)
        vertical.mesh = vmesh
        vertical.position = center + (Vector3(side * CELL_SIZE * 0.37, 0, 0) if o == "N" else Vector3(0, 0, side * CELL_SIZE * 0.37))
        vertical.material_override = _material(frame_color, 0.90)
        root.add_child(vertical)
    for vertical_side in [-1.0, 1.0]:
        var horizontal := MeshInstance3D.new()
        var hmesh := BoxMesh.new()
        hmesh.size = Vector3(CELL_SIZE * 0.82, 0.08, 0.08) if o == "N" else Vector3(0.08, 0.08, CELL_SIZE * 0.82)
        horizontal.mesh = hmesh
        horizontal.position = center + Vector3(0, vertical_side * 0.40, 0)
        horizontal.material_override = _material(frame_color, 0.90)
        root.add_child(horizontal)

    var cross := MeshInstance3D.new()
    var cross_mesh := BoxMesh.new()
    cross_mesh.size = Vector3(0.06, 0.72, 0.06)
    cross.mesh = cross_mesh
    cross.position = center
    cross.material_override = _material(frame_color, 0.90)
    root.add_child(cross)

    wall_root.add_child(root)
    windows.append({"cell":[cell.x, cell.y], "orientation":o})

func _place_stairs(cell: Vector2i) -> void:
    var root := Node3D.new()
    root.name = "Stairs_%d_%d_%d" % [cell.x, cell.y, stairs.size()]
    root.position = cell_to_world(cell)
    for step in range(5):
        _box(root, Vector3(1.0, 0.16, 0.28), Vector3(0, 0.08 + step * 0.16, -0.48 + step * 0.22), Color("8b6c52"))
    furniture_root.add_child(root)
    stairs.append({"cell":[cell.x, cell.y], "to_level": current_build_level + 1})

func _place_platform(cell: Vector2i) -> void:
    var root := Node3D.new()
    root.name = "Platform_%d_%d_%d" % [cell.x, cell.y, platforms.size()]
    root.position = cell_to_world(cell)
    _box(root, Vector3(CELL_SIZE * 0.94, 0.28, CELL_SIZE * 0.94), Vector3(0, 0.15, 0), Color("92785f"))
    furniture_root.add_child(root)
    platforms.append({"cell":[cell.x, cell.y], "height":0.28})

func toggle_roof() -> void:
    roof_enabled = not roof_enabled
    for child in roof_root.get_children():
        child.free()
    if not roof_enabled or floors.is_empty():
        return
    var min_x := 999
    var max_x := -999
    var min_z := 999
    var max_z := -999
    for key in floors.keys():
        var cell := _key_to_cell(String(key))
        min_x = mini(min_x, cell.x)
        max_x = maxi(max_x, cell.x)
        min_z = mini(min_z, cell.y)
        max_z = maxi(max_z, cell.y)
    var roof := MeshInstance3D.new()
    var mesh := PrismMesh.new()
    mesh.size = Vector3((max_x - min_x + 1) * CELL_SIZE + 0.3, 1.3, (max_z - min_z + 1) * CELL_SIZE + 0.3)
    roof.mesh = mesh
    roof.position = Vector3((min_x + max_x) * CELL_SIZE * 0.5, WALL_HEIGHT + 0.68, (min_z + max_z) * CELL_SIZE * 0.5)
    roof.material_override = _material(Color("6e5147"), 0.96)
    roof_root.add_child(roof)

func cycle_build_level() -> int:
    current_build_level += 1
    if current_build_level > 2:
        current_build_level = -1
    return current_build_level

func tick_environment(delta: float) -> void:
    for i in range(furniture.size()):
        var item: Dictionary = furniture[i]
        var item_type := String(item.get("type", ""))
        var condition_loss := delta * (0.003 if item_type in ["bed", "sofa", "bookshelf", "rug", "plant"] else 0.008)
        var dirt_loss := delta * (0.020 if item_type in ["bath", "toilet", "sink", "stove", "food", "fridge"] else 0.006)
        item["condition"] = maxf(0.0, float(item.get("condition", 100.0)) - condition_loss)
        item["cleanliness"] = maxf(0.0, float(item.get("cleanliness", 100.0)) - dirt_loss)
        furniture[i] = item

func home_value() -> int:
    var total := floors.size() * int(TOOL_COSTS["floor"])
    total += walls.size() * int(TOOL_COSTS["wall"])
    total += doors.size() * int(TOOL_COSTS["door"])
    for item in furniture:
        total += int(TOOL_COSTS.get(String(item.get("type", "")), 0))
    return total

func find_problem_object(problem: String, from_cell: Vector2i) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := 999999
    for item in furniture:
        var qualifies := false
        if problem == "dirty":
            qualifies = float(item.get("cleanliness", 100.0)) < 78.0
        elif problem == "broken":
            qualifies = float(item.get("condition", 100.0)) < 35.0
        if not qualifies:
            continue
        var raw: Array = item.get("cell", [0, 0])
        var item_cell := Vector2i(int(raw[0]), int(raw[1]))
        for candidate in _neighbors(item_cell):
            if not is_walkable(candidate):
                continue
            var path := path_between(from_cell, candidate)
            if not path.is_empty() and path.size() < best_distance:
                best_distance = path.size()
                best = {"item": item, "cell": candidate}
    return best

func clean_object(item_id: String, amount: float) -> void:
    for i in range(furniture.size()):
        if String(furniture[i].get("id", "")) == item_id:
            var item: Dictionary = furniture[i]
            item["cleanliness"] = clampf(float(item.get("cleanliness", 100.0)) + amount, 0.0, 100.0)
            furniture[i] = item
            return

func repair_object(item_id: String, amount: float) -> void:
    for i in range(furniture.size()):
        if String(furniture[i].get("id", "")) == item_id:
            var item: Dictionary = furniture[i]
            item["condition"] = clampf(float(item.get("condition", 100.0)) + amount, 0.0, 100.0)
            furniture[i] = item
            return

func soil_object(item_id: String, amount: float) -> void:
    if item_id.is_empty():
        return
    for i in range(furniture.size()):
        if String(furniture[i].get("id", "")) == item_id:
            var item: Dictionary = furniture[i]
            item["cleanliness"] = clampf(float(item.get("cleanliness", 100.0)) - amount, 0.0, 100.0)
            furniture[i] = item
            return

func wear_object(item_id: String, amount: float) -> void:
    if item_id.is_empty():
        return
    for i in range(furniture.size()):
        if String(furniture[i].get("id", "")) == item_id:
            var item: Dictionary = furniture[i]
            item["condition"] = clampf(float(item.get("condition", 100.0)) - amount, 0.0, 100.0)
            furniture[i] = item
            return

func claim_object(item_id: String, owner_id: String) -> void:
    for i in range(furniture.size()):
        if String(furniture[i].get("id", "")) == item_id:
            var item: Dictionary = furniture[i]
            item["owner_id"] = owner_id
            furniture[i] = item
            return

func room_count() -> int:
    var remaining: Dictionary = {}
    for key in floors.keys():
        remaining[key] = true
    var count := 0
    while not remaining.is_empty():
        count += 1
        var start_key := String(remaining.keys()[0])
        var start := _key_to_cell(start_key)
        var frontier: Array[Vector2i] = [start]
        remaining.erase(start_key)
        var head := 0
        while head < frontier.size():
            var current := frontier[head]
            head += 1
            for next_cell in _neighbors(current):
                var next_key := _cell_key(next_cell)
                if not remaining.has(next_key):
                    continue
                if _edge_blocked(current, next_cell):
                    continue
                remaining.erase(next_key)
                frontier.append(next_cell)
    return count

func _erase_cell(cell: Vector2i) -> void:
    var floor_key := _cell_key(cell)
    floors.erase(floor_key)
    var floor_node := floor_root.get_node_or_null("Floor_%s" % floor_key)
    if floor_node:
        floor_node.free()
    _remove_furniture_at(cell)
    for o in ["N", "W"]:
        var key := _wall_key(cell, o)
        walls.erase(key)
        doors.erase(key)
        var wall_node := wall_root.get_node_or_null(_wall_node_name(key))
        if wall_node:
            wall_node.free()

func _remove_furniture_at(cell: Vector2i) -> void:
    for i in range(furniture.size() - 1, -1, -1):
        var raw: Array = furniture[i].get("cell", [0, 0])
        if Vector2i(int(raw[0]), int(raw[1])) == cell:
            furniture.remove_at(i)
    var node := furniture_root.get_node_or_null(_furniture_node_name(cell))
    if node:
        node.free()

func _furniture_blocks_cell(cell: Vector2i) -> bool:
    for item in furniture:
        var raw: Array = item.get("cell", [0, 0])
        if Vector2i(int(raw[0]), int(raw[1])) == cell:
            return true
    return false

func _neighbors(cell: Vector2i) -> Array[Vector2i]:
    return [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]

func _edge_blocked(a: Vector2i, b: Vector2i) -> bool:
    var key := ""
    if b == a + Vector2i.UP:
        key = _wall_key(a, "N")
    elif b == a + Vector2i.DOWN:
        key = _wall_key(b, "N")
    elif b == a + Vector2i.LEFT:
        key = _wall_key(a, "W")
    elif b == a + Vector2i.RIGHT:
        key = _wall_key(b, "W")
    if key.is_empty():
        return true
    return walls.has(key) and not doors.has(key)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    return mat

func _cell_key(cell: Vector2i) -> String:
    return "%d,%d" % [cell.x, cell.y]

func _key_to_cell(key: String) -> Vector2i:
    var p := key.split(",")
    return Vector2i(int(p[0]), int(p[1]))

func _wall_key(cell: Vector2i, orientation: String) -> String:
    return "%d,%d,%s" % [cell.x, cell.y, orientation]

func _wall_from_key(key: String) -> Array:
    var p := key.split(",")
    return [Vector2i(int(p[0]), int(p[1])), String(p[2])]

func _wall_node_name(key: String) -> String:
    return "Wall_%s" % key.replace(",", "_")

func _furniture_node_name(cell: Vector2i) -> String:
    return "Furniture_%d_%d" % [cell.x, cell.y]


func set_cutaway_visible(enabled: bool) -> void:
    update_cutaway_for_yaw(-45.0, enabled)

func update_cutaway_for_yaw(yaw_degrees: float, enabled: bool) -> void:
    # Restore all four exterior edges first.
    for x in range(1, 10):
        var north := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(x, 1), "N")))
        var south := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(x, 8), "N")))
        if north:
            north.visible = true
        if south:
            south.visible = true
    for z in range(1, 8):
        var west := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(1, z), "W")))
        var east := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(10, z), "W")))
        if west:
            west.visible = true
        if east:
            east.visible = true

    if not enabled:
        return

    var normalized := wrapf(yaw_degrees, -180.0, 180.0)
    var hide_north := false
    var hide_south := false
    var hide_west := false
    var hide_east := false

    if normalized >= -135.0 and normalized < -45.0:
        hide_south = true
        hide_west = true
    elif normalized >= -45.0 and normalized < 45.0:
        hide_south = true
        hide_east = true
    elif normalized >= 45.0 and normalized < 135.0:
        hide_north = true
        hide_east = true
    else:
        hide_north = true
        hide_west = true

    for x in range(1, 10):
        if hide_north:
            var north := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(x, 1), "N")))
            if north:
                north.visible = false
        if hide_south:
            var south := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(x, 8), "N")))
            if south:
                south.visible = false
    for z in range(1, 8):
        if hide_west:
            var west := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(1, z), "W")))
            if west:
                west.visible = false
        if hide_east:
            var east := wall_root.get_node_or_null(_wall_node_name(_wall_key(Vector2i(10, z), "W")))
            if east:
                east.visible = false

