extends Node3D

const SAVE_PATH := "user://slime_life_save.json"
const SAVE_SLOT_PATTERN := "user://slime_life_save_%d.json"
const SAVE_BACKUP_PATTERN := "user://slime_life_save_%d.backup.json"
const SAVE_VERSION := 2
const COLORS := [
    ["Sky", Color("65ccff")],
    ["Rose", Color("f39ac0")],
    ["Sun", Color("f6cd59")],
    ["Mint", Color("74ddb0")],
    ["Lilac", Color("ae9cf2")],
    ["Pearl", Color("b9d7ff")],
]
const NEEDS := ["hunger", "energy", "hygiene", "fun", "social", "comfort", "bladder"]
const PERSONALITIES := ["Bubbly", "Playful", "Neat", "Foodie", "Cozy", "Independent"]
const HABITS := ["Snacky", "Napper", "Tidy Routine", "Toy Lover", "Chatty", "Cozy Seeker", "Wanderer", "Slow Starter"]
const TAP_SLOP := 16.0

var build_system: SlimeBuildSystem
var audio_manager: SlimeAudio
var household: SlimeHousehold
var camera_rig: SlimeCameraRig
var slime_root: Node3D
var ui_layer: CanvasLayer
var root_ui: Control
var day_button: Button
var family_panel: PanelContainer
var family_row: HBoxContainer
var needs_panel: PanelContainer
var needs_row: GridContainer
var needs_title: Label
var needs_profile: Label
var needs_toggle_button: Button
var needs_expanded := false
var urgent_label: Label
var action_progress_bar: ProgressBar
var action_queue_row: HBoxContainer
var last_action_signature := ""
var context_panel: PanelContainer
var context_title: Label
var context_box: VBoxContainer
var object_marker: MeshInstance3D
var build_button: Button
var baby_button: Button
var build_tray: PanelContainer
var build_row: GridContainer
var status_label: Label
var money_label: Label
var life_button: Button
var camera_button: Button
var settings_button: Button
var settings_overlay: ColorRect
var settings_panel: PanelContainer
var life_overlay: ColorRect
var life_panel: PanelContainer
var life_text: RichTextLabel
var life_section := "Overview"
var career_cycle_button: Button
var social_target: OptionButton
var social_action: OptionButton
var share_line: LineEdit
var cheat_line: LineEdit
var save_slot_option: OptionButton
var creator_overlay: ColorRect
var creator_panel: PanelContainer
var creator_name: LineEdit
var creator_color: OptionButton
var creator_personality: OptionButton
var creator_size: OptionButton
var creator_eyes: OptionButton
var creator_core: OptionButton
var creator_antenna: OptionButton
var creator_habit_a: OptionButton
var creator_habit_b: OptionButton
var baby_overlay: ColorRect
var baby_panel: PanelContainer
var parent_a: OptionButton
var parent_b: OptionButton
var baby_name: LineEdit
var start_overlay: ColorRect
var build_mode := false
var selected_tool := "floor"
var wall_orientation := "N"
var sim_speed := 1.0
var world_minutes := 8.0 * 60.0
var world_day := 1
var autosave_timer := 0.0
var status_timer := 0.0
var toast_history: Array[String] = []
var current_save_slot := 1
var sun: DirectionalLight3D
var touches: Dictionary = {}
var touch_starts: Dictionary = {}
var touch_moved: Dictionary = {}
var pinch_distance := 0.0
var pinch_centroid := Vector2.ZERO
var pinch_angle := 0.0
var last_viewport_size := Vector2.ZERO

func _ready() -> void:
    Engine.max_fps = 60
    _make_environment()
    _make_object_marker()
    audio_manager = SlimeAudio.new()
    audio_manager.name = "Audio"
    add_child(audio_manager)
    build_system = SlimeBuildSystem.new()
    build_system.name = "BuildSystem"
    add_child(build_system)
    slime_root = Node3D.new()
    slime_root.name = "Slimes"
    add_child(slime_root)
    household = SlimeHousehold.new()
    household.name = "Household"
    add_child(household)
    household.setup(slime_root, build_system)
    household.household_changed.connect(_refresh_family)
    household.selection_changed.connect(_selection_changed)
    household.notification.connect(_status)
    camera_rig = SlimeCameraRig.new()
    camera_rig.name = "CameraRig"
    add_child(camera_rig)
    _build_ui()
    _build_life_panel()
    _build_settings_panel()
    _build_creator_dialog()
    _build_baby_dialog()
    _apply_platform_profile()
    _apply_responsive_layout()
    _show_start_screen()

func _process(delta: float) -> void:
    var viewport_size := get_viewport().get_visible_rect().size
    if viewport_size != last_viewport_size:
        last_viewport_size = viewport_size
        _apply_responsive_layout()
    _desktop_camera(delta)
    if not build_mode and sim_speed > 0.0:
        var sim_delta := delta * sim_speed
        household.tick(sim_delta)
        world_minutes += sim_delta * 4.0
        while world_minutes >= 24.0 * 60.0:
            world_minutes -= 24.0 * 60.0
            world_day += 1
        var clock_total := int(world_minutes)
        household.tick_world(world_day, (clock_total / 60) % 24, clock_total % 60, sim_delta)
        autosave_timer += delta
        if autosave_timer >= 12.0:
            autosave_timer = 0.0
            save_game(false)
    _refresh_clock()
    _refresh_needs_values()
    _refresh_money()
    _refresh_life_panel()
    _refresh_action_strip()
    _tick_status(delta)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        save_game(false)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        _mouse_button(event)
    elif event is InputEventMouseMotion:
        _mouse_motion(event)
    elif event is InputEventScreenTouch:
        _screen_touch(event)
    elif event is InputEventScreenDrag:
        _screen_drag(event)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.is_action("camera_rotate_left"):
            camera_rig.rotate_by(-45.0)
        elif event.is_action("camera_rotate_right"):
            camera_rig.rotate_by(45.0)
        elif event.is_action("camera_zoom_in"):
            camera_rig.zoom_by(-1.0)
        elif event.is_action("camera_zoom_out"):
            camera_rig.zoom_by(1.0)

func _desktop_camera(delta: float) -> void:
    var amount := 5.0 * delta
    if Input.is_action_pressed("camera_pan_left"):
        camera_rig.pan_local(-amount, 0)
    if Input.is_action_pressed("camera_pan_right"):
        camera_rig.pan_local(amount, 0)
    if Input.is_action_pressed("camera_pan_up"):
        camera_rig.pan_local(0, -amount)
    if Input.is_action_pressed("camera_pan_down"):
        camera_rig.pan_local(0, amount)

func _mouse_button(event: InputEventMouseButton) -> void:
    if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
        camera_rig.zoom_by(-0.8)
    elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
        camera_rig.zoom_by(0.8)
    elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _world_tap(event.position)

func _mouse_motion(event: InputEventMouseMotion) -> void:
    if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
        camera_rig.rotate_by(event.relative.x * 0.20)
    elif (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
        camera_rig.pan_from_screen_delta(event.relative)

func _screen_touch(event: InputEventScreenTouch) -> void:
    if event.pressed:
        touches[event.index] = event.position
        touch_starts[event.index] = event.position
        touch_moved[event.index] = false
        if touches.size() == 2:
            _reset_pinch()
        return
    var start: Vector2 = touch_starts.get(event.index, event.position)
    var moved := bool(touch_moved.get(event.index, false))
    touches.erase(event.index)
    touch_starts.erase(event.index)
    touch_moved.erase(event.index)
    if touches.size() < 2:
        pinch_distance = 0.0
    if not moved and start.distance_to(event.position) <= TAP_SLOP:
        _world_tap(event.position)

func _screen_drag(event: InputEventScreenDrag) -> void:
    touches[event.index] = event.position
    touch_moved[event.index] = true
    if touches.size() == 1:
        camera_rig.pan_from_screen_delta(event.relative)
        return
    if touches.size() >= 2:
        var values := touches.values()
        var a: Vector2 = values[0]
        var b: Vector2 = values[1]
        var center := (a + b) * 0.5
        var distance_now := a.distance_to(b)
        var angle_now := a.angle_to_point(b)
        if pinch_distance > 0.0:
            camera_rig.zoom_by((pinch_distance - distance_now) * 0.012)
            camera_rig.pan_from_screen_delta(center - pinch_centroid)
            var angle_delta := wrapf(angle_now - pinch_angle, -PI, PI)
            if absf(angle_delta) > 0.01:
                camera_rig.rotate_by(rad_to_deg(angle_delta) * 0.55)
        pinch_distance = distance_now
        pinch_centroid = center
        pinch_angle = angle_now

func _reset_pinch() -> void:
    if touches.size() < 2:
        return
    var values := touches.values()
    var a: Vector2 = values[0]
    var b: Vector2 = values[1]
    pinch_distance = a.distance_to(b)
    pinch_centroid = (a + b) * 0.5
    pinch_angle = a.angle_to_point(b)

func _world_tap(screen_pos: Vector2) -> void:
    if build_mode:
        var world = camera_rig.screen_to_ground(screen_pos)
        if world != null:
            var cell := build_system.world_to_cell(world)
            var price := build_system.tool_cost(selected_tool)
            if price > 0 and not household.spend(price):
                _status("Not enough puddle coins — need %d" % price)
                return
            if build_system.place(cell, selected_tool, wall_orientation):
                audio_manager.build_place()
                _status("Placed %s · -%d" % [selected_tool, price])
                save_game(false)
            elif price > 0:
                household.earn(price)
        return
    _hide_context()
    if _select_slime_from_screen(screen_pos):
        return
    var selected := household.selected_slime()
    if selected:
        var world = camera_rig.screen_to_ground(screen_pos)
        if world != null:
            var cell := build_system.world_to_cell(world)
            var item := build_system.furniture_at_cell(cell)
            if not item.is_empty():
                _show_object_context(item, screen_pos)
                return
            if build_system.is_walkable(cell):
                selected.command_move(cell)
                _status("%s is going there" % selected.display_name)

func _select_slime_from_screen(screen_pos: Vector2) -> bool:
    var camera := camera_rig.camera
    if camera == null:
        return false
    var origin := camera.project_ray_origin(screen_pos)
    var end := origin + camera.project_ray_normal(screen_pos) * 100.0
    var query := PhysicsRayQueryParameters3D.create(origin, end)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return false
    var collider = hit.get("collider")
    if collider is SlimeAgent:
        var tapped := collider as SlimeAgent
        var selected := household.selected_slime()
        if selected != null and tapped != selected:
            _show_slime_context(tapped, screen_pos)
        else:
            household.select_slime(tapped.slime_id)
            camera_rig.focus_on(tapped.global_position)
            _show_slime_context(tapped, screen_pos)
        return true
    return false

func _make_environment() -> void:
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("819da5")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("b6c8ca")
    env.ambient_light_energy = 0.34
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world_env.environment = env
    add_child(world_env)
    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52, -38, 0)
    sun.light_color = Color("fff0d6")
    sun.light_energy = 0.72
    sun.shadow_enabled = true
    add_child(sun)

func _make_object_marker() -> void:
    object_marker = MeshInstance3D.new()
    object_marker.name = "ObjectSelectionMarker"
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.70
    mesh.bottom_radius = 0.70
    mesh.height = 0.025
    object_marker.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.42, 0.94, 0.90, 0.38)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    object_marker.material_override = material
    object_marker.visible = false
    add_child(object_marker)

func _apply_platform_profile() -> void:
    var mobile := OS.get_name() == "Android" or OS.get_name() == "iOS" or OS.has_feature("web")
    if mobile:
        RenderingServer.viewport_set_scaling_3d_scale(get_viewport().get_viewport_rid(), 0.90)
        if sun:
            sun.shadow_enabled = false

func _apply_responsive_layout() -> void:
    if camera_rig == null or root_ui == null:
        return
    var size := get_viewport().get_visible_rect().size
    if size.x <= 0.0 or size.y <= 0.0:
        return
    var phone_like := OS.get_name() == "Android" or OS.get_name() == "iOS" or OS.has_feature("web")
    if not phone_like:
        return
    var portrait := size.y > size.x
    camera_rig.set_phone_view(portrait)

    if root_ui.theme == null:
        root_ui.theme = Theme.new()
    root_ui.theme.default_font_size = 24 if portrait else 20

    day_button.custom_minimum_size = Vector2(220, 64) if portrait else Vector2(210, 62)
    day_button.position = Vector2(18, 18)
    settings_button.custom_minimum_size = Vector2(52, 52)
    settings_button.position = Vector2(248 if portrait else 238, 24)

    family_panel.offset_left = -360 if portrait else -390
    family_panel.offset_right = -18
    family_panel.offset_top = 18
    family_panel.offset_bottom = 82 if portrait else 84

    money_label.offset_left = -250 if portrait else -220
    money_label.offset_right = 250 if portrait else 220
    money_label.offset_top = 88 if portrait else 24
    money_label.offset_bottom = 126 if portrait else 64
    money_label.add_theme_font_size_override("font_size", 18 if portrait else 20)

    needs_panel.offset_left = 24 if portrait else 180
    needs_panel.offset_right = -24 if portrait else -180
    needs_panel.offset_top = (-250 if needs_expanded else -122) if portrait else (-168 if needs_expanded else -98)
    needs_panel.offset_bottom = -18
    needs_title.add_theme_font_size_override("font_size", 24 if portrait else 22)
    if needs_profile:
        needs_profile.add_theme_font_size_override("font_size", 16 if portrait else 15)
    if needs_row:
        needs_row.visible = needs_expanded

    build_button.custom_minimum_size = Vector2(132, 62)
    build_button.offset_left = -150
    build_button.offset_right = -18
    life_button.custom_minimum_size = Vector2(118, 62)
    life_button.offset_left = 18
    life_button.offset_right = 136
    camera_button.custom_minimum_size = Vector2(118, 62)
    camera_button.offset_left = 146
    camera_button.offset_right = 264
    needs_toggle_button.custom_minimum_size = Vector2(118, 62)
    needs_toggle_button.offset_left = 274
    needs_toggle_button.offset_right = 392
    if portrait:
        var control_top := -198 if not needs_expanded else -326
        var control_bottom := control_top + 62
        build_button.offset_top = control_top
        build_button.offset_bottom = control_bottom
        life_button.offset_top = control_top
        life_button.offset_bottom = control_bottom
        camera_button.offset_top = control_top
        camera_button.offset_bottom = control_bottom
        needs_toggle_button.offset_top = control_top
        needs_toggle_button.offset_bottom = control_bottom
    else:
        build_button.offset_top = -94
        build_button.offset_bottom = -32
        life_button.offset_top = -94
        life_button.offset_bottom = -32
        camera_button.offset_top = -94
        camera_button.offset_bottom = -32
        needs_toggle_button.offset_top = -94
        needs_toggle_button.offset_bottom = -32

    build_tray.offset_left = 24
    build_tray.offset_right = -24
    build_tray.offset_top = -310 if portrait else -250
    build_tray.offset_bottom = -24

    status_label.offset_top = 142 if portrait else 24
    status_label.add_theme_font_size_override("font_size", 24 if portrait else 20)

func _build_ui() -> void:
    ui_layer = CanvasLayer.new()
    add_child(ui_layer)
    root_ui = Control.new()
    root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui_layer.add_child(root_ui)

    day_button = _button("Day 1 · 8:00 AM", _cycle_speed, Vector2(180, 60))
    day_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
    day_button.position = Vector2(18, 18)
    day_button.add_theme_stylebox_override("normal", _panel_style(Color(0.62, 0.80, 0.82, 0.96), 28))
    day_button.add_theme_stylebox_override("hover", _panel_style(Color(0.72, 0.88, 0.88, 0.98), 28))
    day_button.add_theme_color_override("font_color", Color("193239"))
    root_ui.add_child(day_button)

    settings_button = _button("⚙", _open_settings, Vector2(54, 54))
    settings_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
    settings_button.position = Vector2(250, 22)
    settings_button.add_theme_font_size_override("font_size", 22)
    root_ui.add_child(settings_button)

    family_panel = PanelContainer.new()
    family_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    family_panel.offset_left = -420
    family_panel.offset_right = -18
    family_panel.offset_top = 18
    family_panel.offset_bottom = 86
    family_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.40, 0.66, 0.68, 0.96), 32))
    family_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    root_ui.add_child(family_panel)

    money_label = Label.new()
    money_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
    money_label.offset_left = -180
    money_label.offset_right = 180
    money_label.offset_top = 28
    money_label.offset_bottom = 68
    money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    money_label.add_theme_font_size_override("font_size", 20)
    money_label.add_theme_color_override("font_color", Color("173039"))
    money_label.add_theme_color_override("font_outline_color", Color(0.92, 0.98, 0.98, 0.85))
    money_label.add_theme_constant_override("outline_size", 5)
    money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root_ui.add_child(money_label)
    family_row = HBoxContainer.new()
    family_row.add_theme_constant_override("separation", 6)
    family_panel.add_child(family_row)

    life_button = _button("LIFE", _open_life_panel, Vector2(104, 54))
    camera_button = _button("VIEW", _reset_camera, Vector2(104, 54))
    needs_toggle_button = _button("NEEDS", _toggle_needs, Vector2(104, 54))
    needs_toggle_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    needs_toggle_button.offset_left = 246
    needs_toggle_button.offset_right = 350
    needs_toggle_button.offset_top = -72
    needs_toggle_button.offset_bottom = -18
    root_ui.add_child(needs_toggle_button)
    camera_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    camera_button.offset_left = 132
    camera_button.offset_right = 236
    camera_button.offset_top = -72
    camera_button.offset_bottom = -18
    root_ui.add_child(camera_button)
    life_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    life_button.offset_left = 18
    life_button.offset_right = 122
    life_button.offset_top = -72
    life_button.offset_bottom = -18
    root_ui.add_child(life_button)

    build_button = _button("BUILD", _toggle_build, Vector2(104, 54))
    build_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    build_button.offset_left = -122
    build_button.offset_right = -18
    build_button.offset_top = -72
    build_button.offset_bottom = -18
    root_ui.add_child(build_button)

    needs_panel = PanelContainer.new()
    needs_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    needs_panel.offset_left = 180
    needs_panel.offset_right = -180
    needs_panel.offset_top = -96
    needs_panel.offset_bottom = -18
    needs_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.55, 0.76, 0.77, 0.97), 30))
    needs_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    root_ui.add_child(needs_panel)
    var needs_box := VBoxContainer.new()
    needs_panel.add_child(needs_box)
    needs_title = Label.new()
    needs_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    needs_title.add_theme_font_size_override("font_size", 22)
    needs_title.add_theme_color_override("font_color", Color("183238"))
    needs_box.add_child(needs_title)
    needs_profile = Label.new()
    needs_profile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    needs_profile.add_theme_font_size_override("font_size", 15)
    needs_profile.add_theme_color_override("font_color", Color("24474c"))
    needs_box.add_child(needs_profile)

    urgent_label = Label.new()
    urgent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    urgent_label.add_theme_font_size_override("font_size", 15)
    urgent_label.add_theme_color_override("font_color", Color("7a2c35"))
    urgent_label.visible = false
    needs_box.add_child(urgent_label)

    action_progress_bar = ProgressBar.new()
    action_progress_bar.min_value = 0
    action_progress_bar.max_value = 100
    action_progress_bar.show_percentage = false
    action_progress_bar.custom_minimum_size = Vector2(0, 8)
    needs_box.add_child(action_progress_bar)

    action_queue_row = HBoxContainer.new()
    action_queue_row.alignment = BoxContainer.ALIGNMENT_CENTER
    action_queue_row.add_theme_constant_override("separation", 5)
    needs_box.add_child(action_queue_row)

    var speed_row := HBoxContainer.new()
    speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
    speed_row.add_theme_constant_override("separation", 5)
    needs_box.add_child(speed_row)
    for speed_data in [["Ⅱ", 0.0], ["▶", 1.0], ["▶▶", 2.0], ["▶▶▶", 3.0]]:
        var speed_button := _button(String(speed_data[0]), _set_speed.bind(float(speed_data[1])), Vector2(72, 38))
        speed_button.add_theme_font_size_override("font_size", 15)
        speed_row.add_child(speed_button)

    needs_row = GridContainer.new()
    needs_row.columns = 4
    needs_row.visible = false
    needs_row.add_theme_constant_override("h_separation", 12)
    needs_row.add_theme_constant_override("v_separation", 7)
    needs_box.add_child(needs_row)

    build_tray = PanelContainer.new()
    build_tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    build_tray.offset_left = 40
    build_tray.offset_right = -40
    build_tray.offset_top = -100
    build_tray.offset_bottom = -18
    build_tray.add_theme_stylebox_override("panel", _panel_style(Color(0.43, 0.66, 0.61, 0.98), 26))
    build_tray.mouse_filter = Control.MOUSE_FILTER_STOP
    root_ui.add_child(build_tray)
    var build_box := VBoxContainer.new()
    build_box.add_theme_constant_override("separation", 6)
    build_tray.add_child(build_box)
    var build_header := HBoxContainer.new()
    build_box.add_child(build_header)
    var build_title := _label("BUILD / BUY")
    build_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    build_title.add_theme_font_size_override("font_size", 20)
    build_header.add_child(build_title)
    build_header.add_child(_button("Rotate", _rotate_wall, Vector2(88, 46)))
    build_header.add_child(_button("Level", _cycle_build_level, Vector2(88, 46)))
    build_header.add_child(_button("Done", _toggle_build, Vector2(88, 46)))

    var build_scroll := ScrollContainer.new()
    build_scroll.custom_minimum_size = Vector2(0, 210)
    build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    build_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    build_box.add_child(build_scroll)

    build_row = GridContainer.new()
    build_row.columns = 4
    build_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    build_row.add_theme_constant_override("h_separation", 6)
    build_row.add_theme_constant_override("v_separation", 6)
    build_scroll.add_child(build_row)
    for tool in ["floor", "wall", "door", "window", "bed", "food", "bath", "toy", "sofa", "toilet", "sink", "stove", "fridge", "table", "lamp", "bookshelf", "desk", "plant", "rug", "dresser", "workbench", "stairs", "platform", "roof", "erase"]:
        var tool_button := _button(tool.capitalize(), _choose_tool.bind(tool), Vector2(112, 48))
        build_row.add_child(tool_button)
    build_tray.visible = false

    status_label = Label.new()
    status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
    status_label.offset_left = -240
    status_label.offset_right = 240
    status_label.offset_top = 18
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status_label.add_theme_color_override("font_color", Color("173039"))
    status_label.add_theme_color_override("font_outline_color", Color(0.92, 0.98, 0.98, 0.75))
    status_label.add_theme_constant_override("outline_size", 5)
    status_label.add_theme_font_size_override("font_size", 20)
    status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root_ui.add_child(status_label)

    context_panel = PanelContainer.new()
    context_panel.custom_minimum_size = Vector2(250, 0)
    context_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.88, 0.96, 0.94, 0.985), 24))
    context_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    context_panel.visible = false
    root_ui.add_child(context_panel)
    context_box = VBoxContainer.new()
    context_box.add_theme_constant_override("separation", 5)
    context_panel.add_child(context_box)
    context_title = _label("Interact")
    context_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    context_title.add_theme_font_size_override("font_size", 20)
    context_box.add_child(context_title)

    _refresh_family()
    _refresh_needs_panel()

func _toggle_needs() -> void:
    needs_expanded = not needs_expanded
    needs_toggle_button.text = "HIDE" if needs_expanded else "NEEDS"
    if needs_row:
        needs_row.visible = needs_expanded
    _apply_responsive_layout()

func _build_life_panel() -> void:
    life_overlay = ColorRect.new()
    life_overlay.name = "LifeOverlay"
    life_overlay.color = Color(0.03, 0.08, 0.10, 0.78)
    life_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    life_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    life_overlay.visible = false
    ui_layer.add_child(life_overlay)

    life_panel = PanelContainer.new()
    life_panel.set_anchors_preset(Control.PRESET_CENTER)
    life_panel.position = Vector2(-360, -310)
    life_panel.custom_minimum_size = Vector2(720, 620)
    life_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.80, 0.93, 0.92, 0.995), 32))
    life_overlay.add_child(life_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    life_panel.add_child(box)

    var header := HBoxContainer.new()
    box.add_child(header)
    var title := _label("SLIME LIFE")
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 30)
    header.add_child(title)
    header.add_child(_button("✕", _close_life_panel, Vector2(58, 50)))

    var section_row := HBoxContainer.new()
    section_row.alignment = BoxContainer.ALIGNMENT_CENTER
    section_row.add_theme_constant_override("separation", 6)
    box.add_child(section_row)
    for section_name in ["Overview", "Social", "Growth", "Household"]:
        section_row.add_child(_button(section_name, _set_life_section.bind(section_name), Vector2(132, 46)))

    life_text = RichTextLabel.new()
    life_text.bbcode_enabled = true
    life_text.fit_content = false
    life_text.scroll_active = true
    life_text.custom_minimum_size = Vector2(0, 350)
    life_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    life_text.add_theme_font_size_override("normal_font_size", 17)
    life_text.add_theme_color_override("default_color", Color("173039"))
    box.add_child(life_text)

    var controls := GridContainer.new()
    controls.columns = 2
    controls.add_theme_constant_override("h_separation", 10)
    controls.add_theme_constant_override("v_separation", 8)
    box.add_child(controls)

    career_cycle_button = _button("CHANGE CAREER", _cycle_career, Vector2(240, 54))
    controls.add_child(career_cycle_button)
    controls.add_child(_button("PAY BILLS", _pay_bills, Vector2(240, 54)))
    controls.add_child(_button("BUY FAST LEARNER", _buy_fast_learner, Vector2(240, 54)))
    controls.add_child(_button("TRAVEL", _travel_next, Vector2(240, 54)))

    social_target = OptionButton.new()
    social_target.custom_minimum_size = Vector2(240, 52)
    _style_option(social_target)
    controls.add_child(social_target)

    social_action = OptionButton.new()
    social_action.custom_minimum_size = Vector2(240, 52)
    _style_option(social_action)
    for interaction in SlimeLifeRules.SOCIALS:
        social_action.add_item(interaction)
    controls.add_child(social_action)

    controls.add_child(_button("DO SOCIAL", _do_social, Vector2(240, 54)))
    controls.add_child(_button("PUDDLE PARTY", _start_party, Vector2(240, 54)))
    controls.add_child(_button("MOVE OUT", _move_out_selected, Vector2(240, 54)))
    controls.add_child(_button("MOVE IN LAST", _move_in_last, Vector2(240, 54)))

    controls.add_child(_button("CLOSE", _close_life_panel, Vector2(240, 54)))

func _open_life_panel() -> void:
    _populate_social_targets()
    life_overlay.visible = true
    _refresh_life_panel()

func _close_life_panel() -> void:
    life_overlay.visible = false

func _populate_social_targets() -> void:
    if social_target == null:
        return
    social_target.clear()
    var selected := household.selected_slime()
    if selected == null:
        return
    for slime in household.all_present_slimes():
        if slime == selected:
            continue
        social_target.add_item(slime.display_name)
        social_target.set_item_metadata(social_target.item_count - 1, slime.slime_id)

func _set_life_section(section_name: String) -> void:
    life_section = section_name
    _refresh_life_panel()

func _refresh_life_panel() -> void:
    if life_text == null or not life_overlay.visible:
        return
    var slime := household.selected_slime()
    if slime == null:
        life_text.text = "No slime selected."
        return

    match life_section:
        "Social":
            life_text.text = _social_panel_text(slime)
        "Growth":
            life_text.text = _growth_panel_text(slime)
        "Household":
            life_text.text = _household_panel_text(slime)
        _:
            life_text.text = _overview_panel_text(slime)

func _overview_panel_text(slime: SlimeAgent) -> String:
    var want_parts: Array[String] = []
    for want in slime.wants:
        want_parts.append("• " + String(want.get("text", "")))
    if want_parts.is_empty():
        want_parts.append("• No active wants")
    var fear_parts: Array[String] = []
    for fear in slime.fears:
        fear_parts.append("• " + String(fear.get("text", "")))
    if fear_parts.is_empty():
        fear_parts.append("• No active fears")
    var mood_parts: Array[String] = []
    for mood in slime.moodlets:
        mood_parts.append("• %s — %s" % [String(mood.get("text", "")), String(mood.get("emotion", ""))])
    if mood_parts.is_empty():
        mood_parts.append("• No strong moodlets")
    return "[b]%s[/b] · %s · %s\n%s\n\n[b]Emotion[/b]  %s\n[b]Doing[/b]  %s\n[b]Queue[/b]  %s\n[b]Life state[/b]  %s\n\n[b]Aspiration[/b]  %s\n[b]Wants[/b]\n%s\n\n[b]Fears[/b]\n%s\n\n[b]Moodlets[/b]\n%s" % [
        slime.display_name,
        slime.age_stage.capitalize(),
        slime.profile_text(),
        slime.profile_detail_text(),
        slime.emotion,
        slime.activity_text(),
        slime.queue_text(),
        slime.life_state.capitalize(),
        slime.aspiration,
        "\n".join(want_parts),
        "\n".join(fear_parts),
        "\n".join(mood_parts),
    ]

func _social_panel_text(slime: SlimeAgent) -> String:
    var relation_parts: Array[String] = []
    for other in household.all_present_slimes():
        if other == slime:
            continue
        relation_parts.append("• %s — %s · Friendship %d" % [
            other.display_name,
            household.relationship_label(slime, other),
            int(slime.relationships.get(other.slime_id, 0.0))
        ])
    if relation_parts.is_empty():
        relation_parts.append("• No relationships yet")
    var text := "[b]Family[/b]\n%s\n\n[b]Relationships[/b]\n%s" % [
        household.family_tree_text(slime),
        "\n".join(relation_parts),
    ]
    if not household.event_name.is_empty():
        text += "\n\n[b]Current event[/b]  %s · %ds left · score %d" % [
            household.event_name,
            int(household.event_timer),
            int(household.event_score),
        ]
    return text

func _growth_panel_text(slime: SlimeAgent) -> String:
    var skill_parts: Array[String] = []
    for skill in SlimeLifeRules.SKILLS:
        skill_parts.append("• %s — Level %d" % [skill.capitalize(), slime.skill_level(skill)])
    var reward_text := "None" if slime.reward_traits.is_empty() else ", ".join(slime.reward_traits)
    var school_text := "Not in school"
    if slime.age_stage in ["child", "teen"]:
        school_text = "Grade %d" % int(slime.school_grade)
    return "[b]Career[/b]  %s\n[b]School[/b]  %s\n[b]Satisfaction[/b]  %d\n[b]Rewards[/b]  %s\n\n[b]Skills[/b]\n%s\n\n[b]Achievements unlocked[/b]  %d" % [
        slime.career_text(),
        school_text,
        slime.satisfaction,
        reward_text,
        "\n".join(skill_parts),
        household.achievements.size(),
    ]

func _household_panel_text(slime: SlimeAgent) -> String:
    var inventory_text := "Empty"
    if not slime.inventory.is_empty():
        var item_parts: Array[String] = []
        for item in slime.inventory:
            item_parts.append("%s ×%d" % [String(item.get("name", "Item")), int(item.get("quantity", 1))])
        inventory_text = ", ".join(item_parts)
    return "[b]Puddle coins[/b]  %d\n[b]Bills due[/b]  %d\n[b]Current lot[/b]  %s\n[b]Home value[/b]  %d\n[b]Detected rooms[/b]  %d\n[b]Mortality[/b]  %s\n[b]Inactive households[/b]  %d\n\n[b]%s's inventory[/b]\n%s\n\nBuild/Buy, travel, sharing, cheats, bills and household controls are below." % [
        household.funds,
        household.bills_due,
        household.current_lot,
        build_system.home_value(),
        build_system.room_count(),
        "ON" if household.mortality_enabled else "OFF",
        household.inactive_households.size(),
        slime.display_name,
        inventory_text,
    ]

func _cycle_career() -> void:
    var slime := household.selected_slime()
    if slime == null:
        return
    var careers: Array = SlimeLifeRules.CAREERS.keys()
    var index := careers.find(slime.career)
    index = (index + 1) % careers.size()
    household.assign_career(slime.slime_id, String(careers[index]))
    _status("%s became a %s" % [slime.display_name, slime.career])
    _refresh_life_panel()
    save_game(false)

func _pay_bills() -> void:
    if household.pay_bills():
        _status("Bills paid")
    else:
        _status("Not enough puddle coins")
    _refresh_life_panel()
    save_game(false)

func _buy_fast_learner() -> void:
    var slime := household.selected_slime()
    if slime == null:
        return
    if slime.reward_traits.has("Fast Learner"):
        _status("Already owns Fast Learner")
        return
    var cost := int((SlimeLifeRules.REWARDS["Fast Learner"] as Dictionary).get("cost", 450))
    if slime.satisfaction < cost:
        _status("Need %d satisfaction" % cost)
        return
    slime.satisfaction -= cost
    slime.reward_traits.append("Fast Learner")
    slime.add_moodlet("Reward unlocked", "Happy", 8.0, 20.0)
    _status("Fast Learner unlocked")
    _refresh_life_panel()
    save_game(false)

func _travel_next() -> void:
    var lots: Array[String] = ["Home", "Puddle Park", "Mossy Cafe", "Community Workshop"]
    household.lot_builds[household.current_lot] = build_system.serialize()
    var index := lots.find(household.current_lot)
    var next_lot: String = lots[(index + 1) % lots.size()]
    household.current_lot = next_lot

    if household.lot_builds.has(next_lot):
        build_system.deserialize(household.lot_builds[next_lot])
    else:
        match next_lot:
            "Puddle Park":
                build_system.make_park()
            "Mossy Cafe":
                build_system.make_cafe()
            "Community Workshop":
                build_system.make_workshop()
            _:
                build_system.make_starter_home()
        household.lot_builds[next_lot] = build_system.serialize()

    if next_lot == "Home":
        household.clear_npcs()
    else:
        household.spawn_npcs(3)

    for i in range(household.slimes.size()):
        var slime := household.slimes[i]
        var spawn := build_system.find_spawn_cell(Vector2i(4 + (i % 3), 5))
        slime.global_position = build_system.cell_to_world(spawn) + Vector3(0, 0.02, 0)
        slime.path.clear()
        slime.add_moodlet("Visited %s" % household.current_lot, "Happy", 4.0, 16.0)
    _status("Travelled to %s" % household.current_lot)
    _refresh_life_panel()
    save_game(false)

func _do_social() -> void:
    var selected := household.selected_slime()
    if selected == null or social_target.item_count == 0 or social_target.selected < 0:
        _status("Add another slime first")
        return
    var target_id := String(social_target.get_item_metadata(social_target.selected))
    var interaction := social_action.get_item_text(maxi(social_action.selected, 0))
    if household.social_interact(selected.slime_id, target_id, interaction):
        audio_manager.social()
        var target := household.get_any_slime(target_id)
        _status("%s: %s with %s" % [selected.display_name, interaction, target.display_name if target else "slime"])
    _refresh_life_panel()
    save_game(false)

func _start_party() -> void:
    if household.start_event("Puddle Party", 90.0):
        _status("Puddle Party started")
    else:
        _status("An event is already running")
    _refresh_life_panel()

func _toggle_music() -> void:
    if audio_manager == null:
        return
    audio_manager.set_music_enabled(not audio_manager.music_enabled)
    _status("Music %s" % ("on" if audio_manager.music_enabled else "off"))

func _toggle_sfx() -> void:
    if audio_manager == null:
        return
    audio_manager.set_sfx_enabled(not audio_manager.sfx_enabled)
    _status("Sound effects %s" % ("on" if audio_manager.sfx_enabled else "off"))

func _toggle_mortality() -> void:
    household.mortality_enabled = not household.mortality_enabled
    _status("Mortality %s" % ("enabled" if household.mortality_enabled else "disabled"))
    _refresh_life_panel()
    save_game(false)

func _move_out_selected() -> void:
    var slime := household.selected_slime()
    if slime == null:
        return
    if household.move_out(slime.slime_id):
        _status("%s moved into a new household" % slime.display_name)
        _populate_social_targets()
    else:
        _status("You need at least one slime in this household")
    _refresh_life_panel()
    save_game(false)

func _move_in_last() -> void:
    if household.move_in_last():
        _status("A slime moved back in")
        _populate_social_targets()
    else:
        _status("No inactive household to move in")
    _refresh_life_panel()
    save_game(false)

func _copy_share_code() -> void:
    var payload := {
        "version": 1,
        "house": build_system.serialize(),
        "household": household.serialize(),
        "day": world_day,
        "minutes": world_minutes,
    }
    var raw := JSON.stringify(payload).to_utf8_buffer()
    var code := Marshalls.raw_to_base64(raw)
    share_line.text = code
    DisplayServer.clipboard_set(code)
    _status("Share code copied")

func _import_share_code() -> void:
    var code := share_line.text.strip_edges()
    if code.is_empty():
        _status("Paste a share code first")
        return
    var raw := Marshalls.base64_to_raw(code)
    var parsed = JSON.parse_string(raw.get_string_from_utf8())
    if not (parsed is Dictionary):
        _status("That share code is invalid")
        return
    var data := parsed as Dictionary
    if not data.has("house") or not data.has("household"):
        _status("That share code is incomplete")
        return
    build_system.deserialize(data["house"])
    household.deserialize(data["household"])
    world_day = int(data.get("day", 1))
    world_minutes = float(data.get("minutes", 480.0))
    _populate_social_targets()
    _refresh_family()
    _refresh_needs_panel()
    _refresh_life_panel()
    _status("Shared household imported")
    save_game(false)

func _run_cheat() -> void:
    var command := cheat_line.text.strip_edges().to_lower()
    var slime := household.selected_slime()
    match command:
        "motherlode":
            household.earn(5000)
            _status("+5000 puddle coins")
        "fill":
            if slime:
                for key in slime.needs.keys():
                    slime.needs[key] = 100.0
                _status("Needs filled")
        "ageup":
            if slime and SlimeLifeRules.AGE_DURATIONS.has(slime.age_stage):
                slime.age_seconds = float(SlimeLifeRules.AGE_DURATIONS[slime.age_stage])
                _status("Age-up queued")
        "skill":
            if slime:
                for skill in slime.skills.keys():
                    var data: Dictionary = slime.skills[skill]
                    data["level"] = mini(10, int(data.get("level", 0)) + 1)
                    slime.skills[skill] = data
                _status("All skills +1")
        "ghost":
            if slime:
                slime.become_ghost()
                _status("Spirit mode")
        "revive":
            if slime:
                slime.revive()
                _status("Revived")
        "cash":
            household.earn(1000)
            _status("+1000 puddle coins")
        "party":
            _start_party()
        _:
            _status("Unknown cheat")
    cheat_line.text = ""
    _refresh_life_panel()
    save_game(false)

func _selected_save_slot() -> int:
    if save_slot_option == null or save_slot_option.selected < 0:
        return current_save_slot
    return int(save_slot_option.get_item_metadata(save_slot_option.selected))

func _save_selected_slot() -> void:
    current_save_slot = _selected_save_slot()
    save_game(true)

func _load_selected_slot() -> void:
    var slot := _selected_save_slot()
    if load_game(slot):
        current_save_slot = slot
        _close_life_panel()
        _status("Loaded save slot %d" % slot)
    else:
        _status("Save slot %d is empty or invalid" % slot)

func _save_path_for_slot(slot: int) -> String:
    if slot == 1:
        return SAVE_PATH
    return SAVE_SLOT_PATTERN % slot

func _backup_path_for_slot(slot: int) -> String:
    return SAVE_BACKUP_PATTERN % slot

func _any_save_exists() -> bool:
    for slot in range(1, 4):
        if FileAccess.file_exists(_save_path_for_slot(slot)):
            return true
    return false

func _build_settings_panel() -> void:
    settings_overlay = ColorRect.new()
    settings_overlay.name = "SettingsOverlay"
    settings_overlay.color = Color(0.03, 0.08, 0.10, 0.82)
    settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    settings_overlay.visible = false
    ui_layer.add_child(settings_overlay)

    settings_panel = PanelContainer.new()
    settings_panel.set_anchors_preset(Control.PRESET_CENTER)
    settings_panel.position = Vector2(-330, -320)
    settings_panel.custom_minimum_size = Vector2(660, 640)
    settings_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.84, 0.94, 0.92, 0.995), 30))
    settings_overlay.add_child(settings_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    settings_panel.add_child(box)

    var header := HBoxContainer.new()
    box.add_child(header)
    var title := _label("SETTINGS & HOUSEHOLD")
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 28)
    header.add_child(title)
    header.add_child(_button("✕", _close_settings, Vector2(58, 50)))

    var section := GridContainer.new()
    section.columns = 2
    section.add_theme_constant_override("h_separation", 10)
    section.add_theme_constant_override("v_separation", 8)
    box.add_child(section)

    section.add_child(_button("MUSIC", _toggle_music, Vector2(250, 52)))
    section.add_child(_button("SFX", _toggle_sfx, Vector2(250, 52)))
    section.add_child(_button("MORTALITY", _toggle_mortality, Vector2(250, 52)))
    section.add_child(_button("PAY BILLS", _pay_bills, Vector2(250, 52)))

    save_slot_option = OptionButton.new()
    save_slot_option.custom_minimum_size = Vector2(250, 52)
    _style_option(save_slot_option)
    for slot in range(1, 4):
        save_slot_option.add_item("Save Slot %d" % slot)
        save_slot_option.set_item_metadata(save_slot_option.item_count - 1, slot)
    save_slot_option.select(0)
    section.add_child(save_slot_option)

    var save_row := HBoxContainer.new()
    save_row.add_theme_constant_override("separation", 6)
    save_row.add_child(_button("SAVE", _save_selected_slot, Vector2(118, 52)))
    save_row.add_child(_button("LOAD", _load_selected_slot, Vector2(118, 52)))
    section.add_child(save_row)

    var share_title := _label("Household sharing")
    share_title.add_theme_font_size_override("font_size", 18)
    box.add_child(share_title)
    share_line = LineEdit.new()
    share_line.placeholder_text = "Paste Slime Life share code"
    share_line.custom_minimum_size = Vector2(0, 52)
    _style_text_field(share_line)
    box.add_child(share_line)
    var share_buttons := HBoxContainer.new()
    share_buttons.add_theme_constant_override("separation", 8)
    share_buttons.add_child(_button("COPY SHARE", _copy_share_code, Vector2(200, 52)))
    share_buttons.add_child(_button("IMPORT", _import_share_code, Vector2(160, 52)))
    box.add_child(share_buttons)

    var advanced_title := _label("Advanced")
    advanced_title.add_theme_font_size_override("font_size", 18)
    box.add_child(advanced_title)
    cheat_line = LineEdit.new()
    cheat_line.placeholder_text = "Cheat command"
    cheat_line.custom_minimum_size = Vector2(0, 52)
    _style_text_field(cheat_line)
    box.add_child(cheat_line)
    box.add_child(_button("RUN CHEAT", _run_cheat, Vector2(200, 52)))

func _open_settings() -> void:
    settings_overlay.visible = true

func _close_settings() -> void:
    settings_overlay.visible = false

func _build_creator_dialog() -> void:
    creator_overlay = ColorRect.new()
    creator_overlay.name = "CreatorOverlay"
    creator_overlay.color = Color(0.03, 0.08, 0.10, 0.78)
    creator_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    creator_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    creator_overlay.visible = false
    ui_layer.add_child(creator_overlay)

    creator_panel = PanelContainer.new()
    creator_panel.set_anchors_preset(Control.PRESET_CENTER)
    creator_panel.position = Vector2(-330, -350)
    creator_panel.custom_minimum_size = Vector2(660, 700)
    creator_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.80, 0.93, 0.92, 0.99), 32))
    creator_overlay.add_child(creator_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    creator_panel.add_child(box)

    var header := HBoxContainer.new()
    box.add_child(header)
    var title := _label("MAKE A SLIME")
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 30)
    header.add_child(title)
    header.add_child(_button("✕", _cancel_creator, Vector2(58, 50)))

    var subtitle := _label("Choose who they are. Personality and habits change what they do on their own.")
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    subtitle.add_theme_font_size_override("font_size", 16)
    box.add_child(subtitle)

    box.add_child(_label("Name"))
    creator_name = LineEdit.new()
    creator_name.placeholder_text = "Nim"
    creator_name.custom_minimum_size = Vector2(0, 50)
    _style_text_field(creator_name)
    box.add_child(creator_name)

    var row_one := HBoxContainer.new()
    row_one.add_theme_constant_override("separation", 10)
    box.add_child(row_one)

    var color_box := VBoxContainer.new()
    color_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    color_box.add_child(_label("Color"))
    creator_color = OptionButton.new()
    creator_color.custom_minimum_size = Vector2(0, 50)
    _style_option(creator_color)
    for option in COLORS:
        creator_color.add_item(String(option[0]))
    color_box.add_child(creator_color)
    row_one.add_child(color_box)

    var personality_box := VBoxContainer.new()
    personality_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    personality_box.add_child(_label("Personality"))
    creator_personality = OptionButton.new()
    creator_personality.custom_minimum_size = Vector2(0, 50)
    _style_option(creator_personality)
    for personality_name in PERSONALITIES:
        creator_personality.add_item(personality_name)
    personality_box.add_child(creator_personality)
    row_one.add_child(personality_box)

    var appearance_label := _label("Appearance")
    appearance_label.add_theme_font_size_override("font_size", 18)
    box.add_child(appearance_label)

    var appearance_row_a := HBoxContainer.new()
    appearance_row_a.add_theme_constant_override("separation", 10)
    box.add_child(appearance_row_a)

    creator_size = OptionButton.new()
    creator_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    creator_size.custom_minimum_size = Vector2(0, 48)
    _style_option(creator_size)
    for value in ["Tiny", "Standard", "Big"]:
        creator_size.add_item("Size: " + value)
    appearance_row_a.add_child(creator_size)

    creator_eyes = OptionButton.new()
    creator_eyes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    creator_eyes.custom_minimum_size = Vector2(0, 48)
    _style_option(creator_eyes)
    for value in ["Round", "Sleepy", "Wide"]:
        creator_eyes.add_item("Eyes: " + value)
    appearance_row_a.add_child(creator_eyes)

    var appearance_row_b := HBoxContainer.new()
    appearance_row_b.add_theme_constant_override("separation", 10)
    box.add_child(appearance_row_b)

    creator_core = OptionButton.new()
    creator_core.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    creator_core.custom_minimum_size = Vector2(0, 48)
    _style_option(creator_core)
    for value in ["Warm", "Cool", "Bright"]:
        creator_core.add_item("Core: " + value)
    appearance_row_b.add_child(creator_core)

    creator_antenna = OptionButton.new()
    creator_antenna.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    creator_antenna.custom_minimum_size = Vector2(0, 48)
    _style_option(creator_antenna)
    for value in ["Curl", "Droplet", "Bubble"]:
        creator_antenna.add_item("Antenna: " + value)
    appearance_row_b.add_child(creator_antenna)

    var habits_label := _label("Habits")
    habits_label.add_theme_font_size_override("font_size", 18)
    box.add_child(habits_label)

    var habits_row := HBoxContainer.new()
    habits_row.add_theme_constant_override("separation", 10)
    box.add_child(habits_row)

    creator_habit_a = OptionButton.new()
    creator_habit_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    creator_habit_a.custom_minimum_size = Vector2(0, 50)
    _style_option(creator_habit_a)
    creator_habit_b = OptionButton.new()
    creator_habit_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    creator_habit_b.custom_minimum_size = Vector2(0, 50)
    _style_option(creator_habit_b)
    for habit_name in HABITS:
        creator_habit_a.add_item(habit_name)
        creator_habit_b.add_item(habit_name)
    habits_row.add_child(creator_habit_a)
    habits_row.add_child(creator_habit_b)

    var hint := _label("Foodie seeks meals sooner. Playful chooses toys. Neat cleans sooner. Bubbly socializes. Wanderer explores. Habits stack with personality.")
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint.add_theme_font_size_override("font_size", 14)
    box.add_child(hint)

    var actions := HBoxContainer.new()
    actions.alignment = BoxContainer.ALIGNMENT_END
    actions.add_theme_constant_override("separation", 10)
    box.add_child(actions)
    actions.add_child(_button("CANCEL", _cancel_creator, Vector2(140, 58)))
    actions.add_child(_button("CREATE", _confirm_creator, Vector2(190, 58)))

func _build_baby_dialog() -> void:
    baby_overlay = ColorRect.new()
    baby_overlay.name = "BabyOverlay"
    baby_overlay.color = Color(0.03, 0.08, 0.10, 0.78)
    baby_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    baby_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    baby_overlay.visible = false
    ui_layer.add_child(baby_overlay)

    baby_panel = PanelContainer.new()
    baby_panel.set_anchors_preset(Control.PRESET_CENTER)
    baby_panel.position = Vector2(-280, -210)
    baby_panel.custom_minimum_size = Vector2(560, 420)
    baby_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.84, 0.93, 0.90, 0.99), 32))
    baby_overlay.add_child(baby_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    baby_panel.add_child(box)

    var header := HBoxContainer.new()
    box.add_child(header)
    var title := _label("HAVE A BABY SLIME")
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 28)
    header.add_child(title)
    header.add_child(_button("✕", _cancel_baby, Vector2(58, 50)))

    var parents_row := HBoxContainer.new()
    parents_row.add_theme_constant_override("separation", 10)
    box.add_child(parents_row)

    var a_box := VBoxContainer.new()
    a_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    a_box.add_child(_label("Parent 1"))
    parent_a = OptionButton.new()
    parent_a.custom_minimum_size = Vector2(0, 52)
    _style_option(parent_a)
    a_box.add_child(parent_a)
    parents_row.add_child(a_box)

    var b_box := VBoxContainer.new()
    b_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b_box.add_child(_label("Parent 2"))
    parent_b = OptionButton.new()
    parent_b.custom_minimum_size = Vector2(0, 52)
    _style_option(parent_b)
    b_box.add_child(parent_b)
    parents_row.add_child(b_box)

    box.add_child(_label("Baby name"))
    baby_name = LineEdit.new()
    baby_name.placeholder_text = "Bubble"
    baby_name.custom_minimum_size = Vector2(0, 52)
    _style_text_field(baby_name)
    box.add_child(baby_name)

    var note := _label("The baby inherits a mix of the parents' color, personality, habits, and tendencies.")
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.add_theme_font_size_override("font_size", 15)
    box.add_child(note)

    var actions := HBoxContainer.new()
    actions.alignment = BoxContainer.ALIGNMENT_END
    actions.add_theme_constant_override("separation", 10)
    box.add_child(actions)
    actions.add_child(_button("CANCEL", _cancel_baby, Vector2(140, 58)))
    actions.add_child(_button("HAVE BABY", _confirm_baby, Vector2(190, 58)))

func _show_start_screen() -> void:
    if root_ui:
        root_ui.visible = false
    start_overlay = ColorRect.new()
    start_overlay.color = Color(0.04, 0.09, 0.11, 1.0)
    start_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    start_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    ui_layer.add_child(start_overlay)
    var card := PanelContainer.new()
    card.set_anchors_preset(Control.PRESET_CENTER)
    card.position = Vector2(-320, -230)
    card.custom_minimum_size = Vector2(640, 460)
    card.add_theme_stylebox_override("panel", _panel_style(Color(0.84, 0.96, 0.98, 0.98), 34))
    start_overlay.add_child(card)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 14)
    card.add_child(box)
    var title := _label("SLIME LIFE")
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 52)
    box.add_child(title)
    var subtitle := _label("One home. One family. They keep living forever.")
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 22)
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(subtitle)
    box.add_child(_button("START HOUSE", _new_game, Vector2(340, 76)))
    if _any_save_exists():
        box.add_child(_button("CONTINUE", _continue_game, Vector2(340, 76)))

func _new_game() -> void:
    build_system.make_starter_home()
    household.clear()
    world_minutes = 8.0 * 60.0
    world_day = 1
    sim_speed = 1.0
    build_mode = false
    _close_start_overlay()
    _status("Make your first slime")
    _open_creator()

func _continue_game() -> void:
    if load_game(1):
        _close_start_overlay()
        _status("Welcome back")
    else:
        _status("Save could not be loaded")

func _close_start_overlay() -> void:
    if is_instance_valid(start_overlay):
        start_overlay.queue_free()
    if root_ui:
        root_ui.visible = true

func _open_creator() -> void:
    creator_name.text = ""
    var index := household.slimes.size()
    creator_color.select(index % COLORS.size())
    creator_personality.select(index % PERSONALITIES.size())
    creator_size.select(index % 3)
    creator_eyes.select((index + 1) % 3)
    creator_core.select((index + 2) % 3)
    creator_antenna.select(index % 3)
    creator_habit_a.select(index % HABITS.size())
    creator_habit_b.select((index + 3) % HABITS.size())
    creator_overlay.visible = true

func _cancel_creator() -> void:
    creator_overlay.visible = false

func _confirm_creator() -> void:
    var idx := maxi(creator_color.selected, 0)
    var personality_idx := maxi(creator_personality.selected, 0)
    var habit_a_idx := maxi(creator_habit_a.selected, 0)
    var habit_b_idx := maxi(creator_habit_b.selected, 0)
    if habit_a_idx == habit_b_idx:
        habit_b_idx = (habit_b_idx + 1) % HABITS.size()
    var chosen_habits: Array[String] = [
        HABITS[habit_a_idx],
        HABITS[habit_b_idx],
    ]
    var chosen_appearance := {
        "size": ["Tiny", "Standard", "Big"][maxi(creator_size.selected, 0)],
        "eyes": ["Round", "Sleepy", "Wide"][maxi(creator_eyes.selected, 0)],
        "core": ["Warm", "Cool", "Bright"][maxi(creator_core.selected, 0)],
        "antenna": ["Curl", "Droplet", "Bubble"][maxi(creator_antenna.selected, 0)],
    }
    var slime := household.add_slime(
        creator_name.text,
        COLORS[idx][1],
        "adult",
        PERSONALITIES[personality_idx],
        chosen_habits,
        chosen_appearance
    )
    household.select_slime(slime.slime_id)
    audio_manager.positive()
    creator_overlay.visible = false
    _status("%s joined the house — %s" % [slime.display_name, slime.profile_text()])
    save_game(false)

func _open_baby() -> void:
    var adults := household.adult_slimes()
    if adults.size() < 2:
        _status("Two adult slimes are needed")
        return
    parent_a.clear()
    parent_b.clear()
    for slime in adults:
        parent_a.add_item(slime.display_name)
        parent_a.set_item_metadata(parent_a.item_count - 1, slime.slime_id)
        parent_b.add_item(slime.display_name)
        parent_b.set_item_metadata(parent_b.item_count - 1, slime.slime_id)
    parent_a.select(0)
    parent_b.select(1)
    baby_name.text = ""
    baby_overlay.visible = true

func _cancel_baby() -> void:
    baby_overlay.visible = false

func _confirm_baby() -> void:
    if parent_a.selected < 0 or parent_b.selected < 0:
        return
    var a_id := String(parent_a.get_item_metadata(parent_a.selected))
    var b_id := String(parent_b.get_item_metadata(parent_b.selected))
    if a_id == b_id:
        _status("Choose two different parents")
        return
    var baby := household.add_baby(a_id, b_id, baby_name.text)
    if baby:
        household.select_slime(baby.slime_id)
        audio_manager.baby()
        baby_overlay.visible = false
        _status("%s was born" % baby.display_name)
        save_game(false)

func _toggle_build() -> void:
    build_mode = not build_mode
    build_tray.visible = build_mode
    needs_panel.visible = not build_mode and household.selected_slime() != null
    build_button.visible = not build_mode
    life_button.visible = not build_mode
    camera_button.visible = not build_mode
    needs_toggle_button.visible = not build_mode
    settings_button.visible = not build_mode
    day_button.visible = not build_mode
    family_panel.visible = not build_mode
    money_label.visible = not build_mode
    build_system.set_cutaway_visible(not build_mode)
    for slime in household.slimes:
        slime.sim_enabled = not build_mode
    _status("Build mode" if build_mode else "Live mode")

func _choose_tool(tool: String) -> void:
    selected_tool = tool
    _status("%s tool" % tool.capitalize())

func _rotate_wall() -> void:
    wall_orientation = "W" if wall_orientation == "N" else "N"
    _status("Placement direction: %s" % ("vertical" if wall_orientation == "W" else "horizontal"))

func _cycle_build_level() -> void:
    var level := build_system.cycle_build_level()
    var label := "Ground"
    if level == -1:
        label = "Basement"
    elif level == 1:
        label = "Upper 1"
    elif level == 2:
        label = "Upper 2"
    _status("Build level: %s" % label)

func _cycle_speed() -> void:
    if sim_speed == 0.0:
        sim_speed = 1.0
    elif sim_speed == 1.0:
        sim_speed = 2.0
    elif sim_speed == 2.0:
        sim_speed = 3.0
    else:
        sim_speed = 0.0
    _status("Paused" if sim_speed == 0.0 else "%dx speed" % int(sim_speed))

func _set_speed(value: float) -> void:
    sim_speed = value
    _status("Paused" if sim_speed == 0.0 else "%dx speed" % int(sim_speed))

func _refresh_money() -> void:
    if money_label == null:
        return
    money_label.text = "◉ %d" % household.funds
    if household.bills_due > 0:
        money_label.text += "   •   Bills %d" % household.bills_due

func _refresh_clock() -> void:
    if day_button == null:
        return
    var total := int(world_minutes)
    var hour := (total / 60) % 24
    var minute := total % 60
    var suffix := "AM" if hour < 12 else "PM"
    var display_hour := hour % 12
    if display_hour == 0:
        display_hour = 12
    var symbol := "☀" if hour >= 6 and hour < 18 else "☾"
    var speed_text := " · PAUSED" if sim_speed == 0.0 else " · %dx" % int(sim_speed)
    day_button.text = "%s Day %d · %d:%02d %s%s" % [symbol, world_day, display_hour, minute, suffix, speed_text]
    if sun:
        var daylight := clampf(sin((world_minutes / (24.0 * 60.0)) * TAU - PI * 0.5) * 0.55 + 0.65, 0.18, 1.0)
        sun.light_energy = 0.30 + daylight * 0.58

func _refresh_family() -> void:
    if family_row == null:
        return
    for child in family_row.get_children():
        child.queue_free()
    var title := _label("FAMILY")
    title.custom_minimum_size = Vector2(66, 44)
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 14)
    family_row.add_child(title)
    for slime in household.slimes:
        var id_value := slime.slime_id
        var selected := id_value == household.selected_id
        var symbol := "◉" if selected else "●"
        if slime.age_stage == "baby":
            symbol = "◌" if not selected else "◎"
        var button := _button(symbol, _select_and_focus.bind(id_value), Vector2(50, 44))
        button.tooltip_text = slime.display_name
        button.add_theme_font_size_override("font_size", 27)
        button.add_theme_color_override("font_color", slime.slime_color.lightened(0.08))
        if selected:
            button.add_theme_stylebox_override("normal", _panel_style(Color(0.92, 0.98, 0.95, 1.0), 18))
        family_row.add_child(button)
    var add_button := _button("+", _open_creator, Vector2(48, 44))
    add_button.tooltip_text = "Add slime"
    family_row.add_child(add_button)
    baby_button = _button("♥", _open_baby, Vector2(48, 44))
    baby_button.tooltip_text = "Have a baby slime"
    baby_button.disabled = household.adult_slimes().size() < 2
    family_row.add_child(baby_button)

func _select_and_focus(id_value: String) -> void:
    household.select_slime(id_value)
    var slime := household.get_slime(id_value)
    if slime:
        camera_rig.focus_on(slime.global_position)

func _reset_camera() -> void:
    camera_rig.reset_view()
    _status("Camera reset")

func _selection_changed(_slime) -> void:
    _refresh_family()
    _refresh_needs_panel()

func _emotion_color(emotion: String) -> Color:
    return {
        "Happy": Color("8fd6b2"),
        "Playful": Color("f2b5d5"),
        "Inspired": Color("b8a9ee"),
        "Focused": Color("8fb8d8"),
        "Energized": Color("f0c873"),
        "Sad": Color("8da7c9"),
        "Angry": Color("dc8c82"),
        "Embarrassed": Color("d9a2b2"),
        "Uncomfortable": Color("c4aa82"),
        "Tired": Color("9da3b0"),
    }.get(emotion, Color("9bc8c7"))

func _next_obligation_text(slime: SlimeAgent) -> String:
    if slime.age_stage in ["child", "teen"]:
        return "School • 7:00 AM"
    if slime.career != "None":
        var info: Dictionary = SlimeLifeRules.CAREERS.get(slime.career, {})
        if not info.is_empty():
            var start_hour := int(info.get("start", 0))
            var suffix := "AM" if start_hour < 12 else "PM"
            var display_hour := start_hour % 12
            if display_hour == 0:
                display_hour = 12
            return "%s • %d %s" % [slime.career, display_hour, suffix]
    return ""

func _refresh_needs_panel() -> void:
    if needs_row == null:
        return
    for child in needs_row.get_children():
        child.queue_free()
    var slime := household.selected_slime()
    needs_panel.visible = slime != null and not build_mode
    if slime == null:
        return
    needs_title.text = "%s · %s" % [slime.display_name, slime.age_stage]
    needs_profile.text = "%s\n%s" % [slime.profile_text(), slime.activity_text()]
    for key in NEEDS:
        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(118, 48)
        var label := _label(key.capitalize())
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", 12)
        box.add_child(label)
        var bar := ProgressBar.new()
        bar.name = "Need_%s" % key
        bar.min_value = 0
        bar.max_value = 100
        bar.value = float(slime.needs.get(key, 0.0))
        bar.show_percentage = false
        bar.custom_minimum_size = Vector2(112, 12)
        box.add_child(bar)
        needs_row.add_child(box)

func _refresh_needs_values() -> void:
    if needs_row == null or not needs_panel.visible:
        return
    var slime := household.selected_slime()
    if slime == null:
        return
    needs_title.text = "● %s · %s · %s" % [slime.display_name, slime.age_stage.capitalize(), slime.emotion]
    needs_title.add_theme_color_override("font_color", slime.slime_color.darkened(0.45))
    var obligation := _next_obligation_text(slime)
    needs_profile.text = slime.activity_text()
    if not obligation.is_empty():
        needs_profile.text += "   •   " + obligation
    if needs_expanded:
        needs_profile.text += "\n" + slime.profile_text()
    needs_panel.add_theme_stylebox_override("panel", _panel_style(_emotion_color(slime.emotion).darkened(0.05), 26))
    for key in NEEDS:
        var bar := needs_row.find_child("Need_%s" % key, true, false)
        if bar is ProgressBar:
            bar.value = float(slime.needs.get(key, 0.0))

func _urgent_need_text(slime: SlimeAgent) -> String:
    var labels := {
        "hunger": "Hungry",
        "energy": "Exhausted",
        "hygiene": "Needs a bath",
        "fun": "Needs fun",
        "social": "Lonely",
        "comfort": "Uncomfortable",
        "bladder": "Needs bathroom",
    }
    var urgent: Array[String] = []
    for key in NEEDS:
        var value := float(slime.needs.get(key, 100.0))
        if value <= 22.0:
            urgent.append(String(labels.get(key, key.capitalize())))
    return " • ".join(urgent)

func _refresh_action_strip() -> void:
    if action_queue_row == null or action_progress_bar == null:
        return
    var slime := household.selected_slime()
    if slime == null:
        return

    var urgent := _urgent_need_text(slime)
    urgent_label.visible = not urgent.is_empty()
    urgent_label.text = "⚠ " + urgent if not urgent.is_empty() else ""

    action_progress_bar.value = slime.action_progress() * 100.0
    action_progress_bar.visible = not slime.action_kind.is_empty()

    var queue := slime.player_queue_text()
    var signature := "%s|%s|%s|%s" % [slime.action_kind, JSON.stringify(queue), slime.emotion, urgent]
    if signature == last_action_signature:
        return
    last_action_signature = signature
    for child in action_queue_row.get_children():
        child.queue_free()

    if not slime.action_kind.is_empty():
        var current_button := _button("✕ " + slime._action_label(slime.action_kind), _cancel_selected_action, Vector2(150, 36))
        current_button.add_theme_font_size_override("font_size", 13)
        action_queue_row.add_child(current_button)
    var queued_index := 0
    for entry in slime.player_queue:
        if queued_index >= 3:
            break
        var label := slime._action_label(String(entry.get("action", "")))
        var queue_button := _button("%d %s" % [queued_index + 1, label], _remove_selected_queue.bind(queued_index), Vector2(128, 36))
        queue_button.add_theme_font_size_override("font_size", 12)
        action_queue_row.add_child(queue_button)
        queued_index += 1

func _cancel_selected_action() -> void:
    var slime := household.selected_slime()
    if slime:
        slime.cancel_current_action(false)
        last_action_signature = ""
        _status("Cancelled current action")

func _remove_selected_queue(index: int) -> void:
    var slime := household.selected_slime()
    if slime:
        slime.remove_queued_action(index)
        last_action_signature = ""
        _status("Removed queued action")

func _hide_context() -> void:
    if context_panel:
        context_panel.visible = false
    if object_marker:
        object_marker.visible = false

func _place_context(screen_pos: Vector2) -> void:
    var viewport := get_viewport().get_visible_rect().size
    var width := 270.0
    var estimated_height := maxf(140.0, float(context_box.get_child_count()) * 48.0)
    context_panel.position = Vector2(
        clampf(screen_pos.x - width * 0.5, 12.0, maxf(12.0, viewport.x - width - 12.0)),
        clampf(screen_pos.y - 35.0, 92.0, maxf(92.0, viewport.y - estimated_height - 24.0))
    )

func _clear_context_buttons() -> void:
    if context_box == null:
        return
    for i in range(context_box.get_child_count() - 1, 0, -1):
        context_box.get_child(i).queue_free()

func _show_object_context(item: Dictionary, screen_pos: Vector2) -> void:
    var selected := household.selected_slime()
    if selected == null:
        return
    _clear_context_buttons()
    var kind := String(item.get("type", "object"))
    context_title.text = kind.capitalize()
    var raw_cell: Array = item.get("cell", [0, 0])
    if object_marker:
        object_marker.position = build_system.cell_to_world(Vector2i(int(raw_cell[0]), int(raw_cell[1]))) + Vector3(0, 0.045, 0)
        object_marker.visible = true
    var options := build_system.interaction_options_for_type(kind)
    for option in options:
        var label := String(option.get("label", "Use"))
        var action := String(option.get("action", ""))
        context_box.add_child(_button(label, _queue_object_interaction.bind(action, item), Vector2(230, 44)))
    if options.is_empty():
        context_box.add_child(_button("Go Here", _go_near_object.bind(item), Vector2(230, 44)))
    context_panel.visible = true
    _place_context(screen_pos)

func _queue_object_interaction(action: String, item: Dictionary) -> void:
    var slime := household.selected_slime()
    if slime == null:
        return
    var target_cell := build_system.interaction_target_for_item(item, slime.current_cell())
    var kind := String(item.get("type", ""))
    if action == "hobby":
        match kind:
            "workbench":
                slime.favorite_hobby = "Tinkering"
            "bookshelf":
                slime.favorite_hobby = "Reading"
            "desk":
                slime.favorite_hobby = "Creative Project"
            "toy":
                slime.favorite_hobby = "Toy Design"
    slime.queue_interaction(action, String(item.get("id", "")), target_cell)
    _hide_context()
    last_action_signature = ""
    _status("Queued: %s" % slime._action_label(action))

func _go_near_object(item: Dictionary) -> void:
    var slime := household.selected_slime()
    if slime:
        slime.command_move(build_system.interaction_target_for_item(item, slime.current_cell()))
    _hide_context()

func _show_slime_context(target: SlimeAgent, screen_pos: Vector2) -> void:
    _clear_context_buttons()
    context_title.text = "%s • %s" % [target.display_name, target.emotion]
    var selected := household.selected_slime()
    if target in household.slimes and target != selected:
        context_box.add_child(_button("Control %s" % target.display_name, _context_select_slime.bind(target.slime_id), Vector2(230, 44)))
    if selected != null and target != selected:
        for interaction in ["Chat", "Joke", "Compliment", "Hug", "Flirt", "Argue"]:
            context_box.add_child(_button(interaction, _queue_social_interaction.bind(target.slime_id, interaction), Vector2(230, 42)))
    elif selected == target:
        context_box.add_child(_button("Open Profile", _open_life_panel, Vector2(230, 44)))
        if not selected.action_kind.is_empty():
            context_box.add_child(_button("Cancel Current Action", _cancel_selected_action, Vector2(230, 44)))
    context_panel.visible = true
    _place_context(screen_pos)

func _context_select_slime(id_value: String) -> void:
    _select_and_focus(id_value)
    _hide_context()

func _queue_social_interaction(target_id: String, interaction: String) -> void:
    var selected := household.selected_slime()
    var target := household.get_any_slime(target_id)
    if selected == null or target == null:
        return
    household.social_interact(selected.slime_id, target_id, interaction)
    selected.queue_interaction("social", "", target.current_cell(), target_id)
    _hide_context()
    last_action_signature = ""
    _status("%s queued with %s" % [interaction, target.display_name])

func save_game(show_message := true) -> void:
    if build_system == null or household == null:
        return
    var data := {
        "version": SAVE_VERSION,
        "slot": current_save_slot,
        "saved_unix_time": Time.get_unix_time_from_system(),
        "day": world_day,
        "minutes": world_minutes,
        "house": build_system.serialize(),
        "household": household.serialize(),
        "settings": {
            "music": audio_manager.music_enabled if audio_manager else true,
            "sfx": audio_manager.sfx_enabled if audio_manager else true,
        },
    }
    var path := _save_path_for_slot(current_save_slot)
    if FileAccess.file_exists(path):
        var previous := FileAccess.open(path, FileAccess.READ)
        if previous:
            var backup := FileAccess.open(_backup_path_for_slot(current_save_slot), FileAccess.WRITE)
            if backup:
                backup.store_string(previous.get_as_text())
                backup.close()
            previous.close()
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))
        file.close()
        if show_message:
            _status("Saved slot %d" % current_save_slot)

func load_game(slot := -1) -> bool:
    if slot < 1:
        slot = current_save_slot
    var path := _save_path_for_slot(slot)
    var data := _read_save_dictionary(path)
    if data.is_empty():
        data = _read_save_dictionary(_backup_path_for_slot(slot))
        if data.is_empty():
            return false
        _status("Recovered backup for slot %d" % slot)
    if not data.has("house") or not data.has("household"):
        return false
    build_system.deserialize(data.get("house", {}))
    household.deserialize(data.get("household", {}))
    world_day = int(data.get("day", 1))
    world_minutes = float(data.get("minutes", 480.0))
    current_save_slot = slot
    var settings: Dictionary = data.get("settings", {})
    if audio_manager:
        audio_manager.set_music_enabled(bool(settings.get("music", true)))
        audio_manager.set_sfx_enabled(bool(settings.get("sfx", true)))
    build_mode = false
    build_tray.visible = false
    build_button.visible = true
    life_button.visible = true
    camera_button.visible = true
    needs_toggle_button.visible = true
    settings_button.visible = true
    day_button.visible = true
    family_panel.visible = true
    money_label.visible = true
    _refresh_family()
    _refresh_needs_panel()
    _refresh_money()
    return true

func _read_save_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var raw_text := file.get_as_text()
    file.close()
    var parsed = JSON.parse_string(raw_text)
    if parsed is Dictionary:
        return parsed as Dictionary
    return {}

func _button(text_value: String, callback: Callable, size := Vector2(90, 48)) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = size
    button.focus_mode = Control.FOCUS_ALL
    button.add_theme_font_size_override("font_size", 20)
    button.add_theme_color_override("font_color", Color("173039"))
    button.add_theme_color_override("font_hover_color", Color("0f252d"))
    button.add_theme_color_override("font_pressed_color", Color("10262c"))
    button.add_theme_stylebox_override("normal", _panel_style(Color(0.78, 0.90, 0.89, 0.98), 16))
    button.add_theme_stylebox_override("hover", _panel_style(Color(0.86, 0.95, 0.93, 1.0), 16))
    button.add_theme_stylebox_override("pressed", _panel_style(Color(0.58, 0.78, 0.75, 1.0), 16))
    button.pressed.connect(callback)
    if audio_manager:
        button.pressed.connect(audio_manager.ui_click)
    return button

func _label(text_value: String) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_color_override("font_color", Color("173039"))
    return label

func _style_option(option: OptionButton) -> void:
    option.add_theme_font_size_override("font_size", 18)
    option.add_theme_color_override("font_color", Color("173039"))
    option.add_theme_color_override("font_hover_color", Color("0f252d"))
    option.add_theme_stylebox_override("normal", _panel_style(Color(0.91, 0.97, 0.96, 1.0), 14))
    option.add_theme_stylebox_override("hover", _panel_style(Color(0.97, 1.0, 0.99, 1.0), 14))
    option.add_theme_stylebox_override("pressed", _panel_style(Color(0.75, 0.88, 0.85, 1.0), 14))

func _style_text_field(field: LineEdit) -> void:
    field.add_theme_font_size_override("font_size", 19)
    field.add_theme_color_override("font_color", Color("173039"))
    field.add_theme_color_override("font_placeholder_color", Color(0.24, 0.38, 0.40, 0.65))
    field.add_theme_stylebox_override("normal", _panel_style(Color(0.94, 0.98, 0.97, 1.0), 14))
    field.add_theme_stylebox_override("focus", _panel_style(Color(1.0, 1.0, 1.0, 1.0), 14))

func _panel_style(color: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    style.border_width_left = 2
    style.border_width_top = 2
    style.border_width_right = 2
    style.border_width_bottom = 2
    style.border_color = Color(0.14, 0.27, 0.29, 0.35)
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.content_margin_top = 7
    style.content_margin_bottom = 7
    return style

func _tick_status(delta: float) -> void:
    if status_label == null:
        return
    if status_timer > 0.0:
        status_timer = maxf(0.0, status_timer - delta)
        var alpha := 1.0
        if status_timer < 1.0:
            alpha = status_timer
        status_label.modulate.a = alpha
    elif not status_label.text.is_empty():
        status_label.text = ""
        toast_history.clear()
        status_label.modulate.a = 1.0

func _status(text_value: String) -> void:
    if status_label:
        if text_value.strip_edges().is_empty():
            return
        toast_history.append(text_value)
        while toast_history.size() > 3:
            toast_history.pop_front()
        status_label.text = "\n".join(toast_history)
        status_label.modulate.a = 1.0
        status_timer = 4.5
