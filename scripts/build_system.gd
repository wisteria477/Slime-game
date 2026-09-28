class_name SlimeBuildSystem
extends Node3D

signal changed

const GRID_SIZE := Vector2i(12, 10)
const CELL_SIZE := 1.35
const WALL_HEIGHT := 1.75
const FURNITURE_TYPES := ["bed", "food", "bath", "toy", "sofa"]

var floors: Dictionary = {}
var walls: Dictionary = {}
var doors: Dictionary = {}
var furniture: Array[Dictionary] = []
var floor_root: Node3D
var wall_root: Node3D
var furniture_root: Node3D
var lot_root: Node3D

func _ready() -> void:
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
    changed.emit()

func clear_house() -> void:
    floors.clear()
    walls.clear()
    doors.clear()
    furniture.clear()
    for root in [floor_root, wall_root, furniture_root]:
        if root:
            for child in root.get_children():
                child.free()
    changed.emit()

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
                best = {"type": kind, "cell": candidate, "furniture_cell": furniture_cell}
    return best

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
        _place_furniture(Vector2i(int(raw_cell[0]), int(raw_cell[1])), String(item.get("type", "sofa")))
    changed.emit()

func _make_lot_ground() -> void:
    var ground := MeshInstance3D.new()
    ground.name = "LotGround"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(GRID_SIZE.x * CELL_SIZE + 2.4, 0.12, GRID_SIZE.y * CELL_SIZE + 2.4)
    ground.mesh = mesh
    ground.position = Vector3((GRID_SIZE.x - 1) * CELL_SIZE * 0.5, -0.08, (GRID_SIZE.y - 1) * CELL_SIZE * 0.5)
    ground.material_override = _material(Color("8dbb73"), 0.95)
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
    obj.material_override = _material(Color("d8c5a8"), 0.82)
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
        body.material_override = _material(Color("e8e1d7"), 0.88)
        root.add_child(body)

func _make_door_visual(root: Node3D, center: Vector3, orientation: String) -> void:
    var frame_mat := _material(Color("806247"), 0.82)
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

func _place_furniture(cell: Vector2i, kind: String) -> void:
    if not floors.has(_cell_key(cell)):
        return
    _remove_furniture_at(cell)
    var node := Node3D.new()
    node.name = _furniture_node_name(cell)
    node.position = cell_to_world(cell)
    furniture_root.add_child(node)
    _make_furniture_visual(node, kind)
    furniture.append({"type": kind, "cell": [cell.x, cell.y]})

func _make_furniture_visual(root: Node3D, kind: String) -> void:
    match kind:
        "bed":
            _box(root, Vector3(1.05, 0.28, 1.15), Vector3(0, 0.19, 0), Color("c9b5db"))
            _box(root, Vector3(1.0, 0.12, 0.30), Vector3(0, 0.39, -0.37), Color("f5efe8"))
        "food":
            _box(root, Vector3(0.86, 1.05, 0.86), Vector3(0, 0.53, 0), Color("8ba88e"))
            _box(root, Vector3(0.72, 0.07, 0.72), Vector3(0, 1.08, 0), Color("dde6da"))
        "bath":
            _box(root, Vector3(1.08, 0.48, 0.92), Vector3(0, 0.25, 0), Color("d4e9ee"))
        "toy":
            _sphere(root, 0.34, Vector3(-0.18, 0.34, 0), Color("ef9aaa"))
            _sphere(root, 0.28, Vector3(0.22, 0.28, 0.12), Color("f0c36d"))
        "sofa":
            _box(root, Vector3(1.12, 0.44, 0.82), Vector3(0, 0.24, 0), Color("7ea27d"))
            _box(root, Vector3(1.10, 0.52, 0.20), Vector3(0, 0.64, 0.30), Color("729471"))

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
