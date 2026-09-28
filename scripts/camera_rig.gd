class_name SlimeCameraRig
extends Node3D

var camera: Camera3D
var yaw := -45.0
var pitch := -48.0
var ortho_size := 13.8
var target := Vector3(6.7, 0.0, 5.4)
var home_target := Vector3(6.7, 0.0, 5.4)
var home_yaw := -45.0
var home_pitch := -48.0
var home_size := 13.8

func _ready() -> void:
    camera = Camera3D.new()
    camera.name = "Camera3D"
    camera.current = true
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = ortho_size
    add_child(camera)
    _update_camera()

func set_phone_view(portrait: bool) -> void:
    home_pitch = -46.0 if portrait else -48.0
    home_size = 11.8 if portrait else 13.2
    pitch = home_pitch
    ortho_size = home_size
    home_target = Vector3(6.7, 0.0, 5.4)
    target = home_target
    _update_camera()

func focus_on(world_position: Vector3, zoom_size := -1.0) -> void:
    target.x = clampf(world_position.x, -1.0, 15.0)
    target.z = clampf(world_position.z, -1.0, 13.0)
    if zoom_size > 0.0:
        ortho_size = clampf(zoom_size, 7.0, 26.0)
    _update_camera()

func reset_view() -> void:
    yaw = home_yaw
    pitch = home_pitch
    ortho_size = home_size
    target = home_target
    _update_camera()

func snap_quarter_turn(direction: int) -> void:
    var quarter := roundf(yaw / 45.0)
    yaw = fmod((quarter + float(direction)) * 45.0, 360.0)
    _update_camera()

func rotate_by(degrees: float) -> void:
    yaw = fmod(yaw + degrees, 360.0)
    _update_camera()

func zoom_by(amount: float) -> void:
    ortho_size = clampf(ortho_size + amount, 7.0, 26.0)
    if camera:
        camera.size = ortho_size

func pan_local(x_amount: float, z_amount: float) -> void:
    var yaw_rad := deg_to_rad(yaw)
    var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
    var forward := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
    target += right * x_amount + forward * z_amount
    target.x = clampf(target.x, -1.0, 15.0)
    target.z = clampf(target.z, -1.0, 13.0)
    _update_camera()

func pan_from_screen_delta(delta: Vector2) -> void:
    var scale := ortho_size * 0.0014
    pan_local(-delta.x * scale, -delta.y * scale)

func screen_to_ground(screen_pos: Vector2) -> Variant:
    if camera == null:
        return null
    var origin := camera.project_ray_origin(screen_pos)
    var direction := camera.project_ray_normal(screen_pos)
    if absf(direction.y) < 0.0001:
        return null
    var distance_to_plane := -origin.y / direction.y
    if distance_to_plane < 0.0:
        return null
    return origin + direction * distance_to_plane

func _update_camera() -> void:
    if camera == null:
        return
    var yaw_rad := deg_to_rad(yaw)
    var pitch_rad := deg_to_rad(pitch)
    var distance := 22.0
    var offset := Vector3(
        cos(pitch_rad) * sin(yaw_rad),
        -sin(pitch_rad),
        cos(pitch_rad) * cos(yaw_rad)
    ) * distance
    camera.global_position = target + offset
    camera.look_at(target, Vector3.UP)
    camera.size = ortho_size
