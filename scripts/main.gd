extends Node3D

const SAVE_PATH := "user://slime_life_save.json"
const COLORS := [
    ["Sky", Color("65ccff")],
    ["Rose", Color("f39ac0")],
    ["Sun", Color("f6cd59")],
    ["Mint", Color("74ddb0")],
    ["Lilac", Color("ae9cf2")],
    ["Pearl", Color("b9d7ff")],
]
const NEEDS := ["hunger", "energy", "hygiene", "fun", "social", "comfort"]
const TAP_SLOP := 16.0

var build_system: SlimeBuildSystem
var household: SlimeHousehold
var camera_rig: SlimeCameraRig
var slime_root: Node3D
var ui_layer: CanvasLayer
var root_ui: Control
var day_button: Button
var family_panel: PanelContainer
var family_row: HBoxContainer
var needs_panel: PanelContainer
var needs_row: HBoxContainer
var needs_title: Label
var build_button: Button
var baby_button: Button
var build_tray: PanelContainer
var build_row: HBoxContainer
var status_label: Label
var creator_dialog: AcceptDialog
var creator_name: LineEdit
var creator_color: OptionButton
var baby_dialog: AcceptDialog
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
var sun: DirectionalLight3D
var touches: Dictionary = {}
var touch_starts: Dictionary = {}
var touch_moved: Dictionary = {}
var pinch_distance := 0.0
var pinch_centroid := Vector2.ZERO
var last_viewport_size := Vector2.ZERO

func _ready() -> void:
    Engine.max_fps = 60
    _make_environment()
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
    camera_rig = SlimeCameraRig.new()
    camera_rig.name = "CameraRig"
    add_child(camera_rig)
    _build_ui()
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
        autosave_timer += delta
        if autosave_timer >= 12.0:
            autosave_timer = 0.0
            save_game(false)
    _refresh_clock()
    _refresh_needs_values()

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
        if pinch_distance > 0.0:
            camera_rig.zoom_by((pinch_distance - distance_now) * 0.012)
            camera_rig.pan_from_screen_delta(center - pinch_centroid)
        pinch_distance = distance_now
        pinch_centroid = center

func _reset_pinch() -> void:
    if touches.size() < 2:
        return
    var values := touches.values()
    var a: Vector2 = values[0]
    var b: Vector2 = values[1]
    pinch_distance = a.distance_to(b)
    pinch_centroid = (a + b) * 0.5

func _world_tap(screen_pos: Vector2) -> void:
    if build_mode:
        var world = camera_rig.screen_to_ground(screen_pos)
        if world != null:
            var cell := build_system.world_to_cell(world)
            if build_system.place(cell, selected_tool, wall_orientation):
                _status("Placed %s" % selected_tool)
                save_game(false)
        return
    if _select_slime_from_screen(screen_pos):
        return
    var selected := household.selected_slime()
    if selected:
        var world = camera_rig.screen_to_ground(screen_pos)
        if world != null:
            var cell := build_system.world_to_cell(world)
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
        household.select_slime(collider.slime_id)
        _status(collider.display_name)
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

    day_button.custom_minimum_size = Vector2(250, 72) if portrait else Vector2(210, 62)
    day_button.position = Vector2(22, 22)

    family_panel.offset_left = -590 if portrait else -500
    family_panel.offset_right = -22
    family_panel.offset_top = 22
    family_panel.offset_bottom = 98 if portrait else 88

    needs_panel.offset_left = 70 if portrait else 150
    needs_panel.offset_right = -70 if portrait else -150
    needs_panel.offset_top = -138 if portrait else -106
    needs_panel.offset_bottom = -26
    needs_title.add_theme_font_size_override("font_size", 26 if portrait else 22)

    build_button.custom_minimum_size = Vector2(138, 68)
    build_button.offset_left = -160
    build_button.offset_right = -22
    build_button.offset_top = -94
    build_button.offset_bottom = -26

    build_tray.offset_left = 24
    build_tray.offset_right = -24
    build_tray.offset_top = -132 if portrait else -108
    build_tray.offset_bottom = -24

    status_label.offset_top = 116 if portrait else 24
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

    family_panel = PanelContainer.new()
    family_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    family_panel.offset_left = -420
    family_panel.offset_right = -18
    family_panel.offset_top = 18
    family_panel.offset_bottom = 86
    family_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.40, 0.66, 0.68, 0.96), 32))
    family_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    root_ui.add_child(family_panel)
    family_row = HBoxContainer.new()
    family_row.add_theme_constant_override("separation", 6)
    family_panel.add_child(family_row)

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
    needs_row = HBoxContainer.new()
    needs_row.alignment = BoxContainer.ALIGNMENT_CENTER
    needs_row.add_theme_constant_override("separation", 8)
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
    build_row = HBoxContainer.new()
    build_row.alignment = BoxContainer.ALIGNMENT_CENTER
    build_row.add_theme_constant_override("separation", 5)
    build_tray.add_child(build_row)
    for tool in ["floor", "wall", "door", "bed", "food", "bath", "toy", "sofa", "erase"]:
        build_row.add_child(_button(tool.capitalize(), _choose_tool.bind(tool), Vector2(74, 50)))
    build_row.add_child(_button("Rotate", _rotate_wall, Vector2(74, 50)))
    build_row.add_child(_button("Done", _toggle_build, Vector2(74, 50)))
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
    _refresh_family()
    _refresh_needs_panel()

func _build_creator_dialog() -> void:
    creator_dialog = AcceptDialog.new()
    creator_dialog.title = "Make a Slime"
    creator_dialog.ok_button_text = "Create"
    ui_layer.add_child(creator_dialog)
    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(360, 170)
    creator_dialog.add_child(box)
    box.add_child(_label("Name"))
    creator_name = LineEdit.new()
    creator_name.placeholder_text = "Nim"
    box.add_child(creator_name)
    box.add_child(_label("Color"))
    creator_color = OptionButton.new()
    for option in COLORS:
        creator_color.add_item(String(option[0]))
    box.add_child(creator_color)
    creator_dialog.confirmed.connect(_confirm_creator)

func _build_baby_dialog() -> void:
    baby_dialog = AcceptDialog.new()
    baby_dialog.title = "Have a Baby Slime"
    baby_dialog.ok_button_text = "Have Baby"
    ui_layer.add_child(baby_dialog)
    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(360, 220)
    baby_dialog.add_child(box)
    box.add_child(_label("Parent 1"))
    parent_a = OptionButton.new()
    box.add_child(parent_a)
    box.add_child(_label("Parent 2"))
    parent_b = OptionButton.new()
    box.add_child(parent_b)
    box.add_child(_label("Baby name"))
    baby_name = LineEdit.new()
    baby_name.placeholder_text = "Bubble"
    box.add_child(baby_name)
    baby_dialog.confirmed.connect(_confirm_baby)

func _show_start_screen() -> void:
    start_overlay = ColorRect.new()
    start_overlay.color = Color(0.04, 0.09, 0.11, 0.96)
    start_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    start_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    ui_layer.add_child(start_overlay)
    var card := PanelContainer.new()
    card.set_anchors_preset(Control.PRESET_CENTER)
    card.position = Vector2(-220, -150)
    card.custom_minimum_size = Vector2(440, 300)
    card.add_theme_stylebox_override("panel", _panel_style(Color(0.84, 0.96, 0.98, 0.98), 34))
    start_overlay.add_child(card)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 14)
    card.add_child(box)
    var title := _label("SLIME LIFE")
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 36)
    box.add_child(title)
    var subtitle := _label("One home. One family. They keep living forever.")
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(subtitle)
    box.add_child(_button("START HOUSE", _new_game, Vector2(220, 58)))
    if FileAccess.file_exists(SAVE_PATH):
        box.add_child(_button("CONTINUE", _continue_game, Vector2(220, 58)))

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
    if load_game():
        _close_start_overlay()
        _status("Welcome back")
    else:
        _status("Save could not be loaded")

func _close_start_overlay() -> void:
    if is_instance_valid(start_overlay):
        start_overlay.queue_free()

func _open_creator() -> void:
    creator_name.text = ""
    creator_color.select(household.slimes.size() % COLORS.size())
    creator_dialog.popup_centered()

func _confirm_creator() -> void:
    var idx := creator_color.selected
    if idx < 0:
        idx = 0
    var slime := household.add_slime(creator_name.text, COLORS[idx][1], "adult")
    household.select_slime(slime.slime_id)
    _status("%s joined the house" % slime.display_name)
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
    baby_dialog.popup_centered()

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
        _status("%s was born" % baby.display_name)
        save_game(false)

func _toggle_build() -> void:
    build_mode = not build_mode
    build_tray.visible = build_mode
    needs_panel.visible = not build_mode and household.selected_slime() != null
    build_button.visible = not build_mode
    for slime in household.slimes:
        slime.sim_enabled = not build_mode
    _status("Build mode" if build_mode else "Live mode")

func _choose_tool(tool: String) -> void:
    selected_tool = tool
    _status("%s tool" % tool.capitalize())

func _rotate_wall() -> void:
    wall_orientation = "W" if wall_orientation == "N" else "N"
    _status("Wall direction: %s" % ("vertical" if wall_orientation == "W" else "horizontal"))

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
    var title := _label("MY SLIMES")
    title.custom_minimum_size = Vector2(88, 44)
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    family_row.add_child(title)
    for slime in household.slimes:
        var id_value := slime.slime_id
        var prefix := "• " if slime.age_stage == "baby" else ""
        var button := _button(prefix + slime.display_name, household.select_slime.bind(id_value), Vector2(76, 44))
        button.modulate = slime.slime_color.lightened(0.22)
        family_row.add_child(button)
    family_row.add_child(_button("+", _open_creator, Vector2(48, 44)))
    baby_button = _button("BABY", _open_baby, Vector2(70, 44))
    baby_button.disabled = household.adult_slimes().size() < 2
    family_row.add_child(baby_button)

func _selection_changed(_slime) -> void:
    _refresh_family()
    _refresh_needs_panel()

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
    for key in NEEDS:
        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(86, 42)
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
        bar.custom_minimum_size = Vector2(82, 10)
        box.add_child(bar)
        needs_row.add_child(box)

func _refresh_needs_values() -> void:
    if needs_row == null or not needs_panel.visible:
        return
    var slime := household.selected_slime()
    if slime == null:
        return
    needs_title.text = "%s · %s" % [slime.display_name, slime.age_stage]
    for key in NEEDS:
        var bar := needs_row.find_child("Need_%s" % key, true, false)
        if bar is ProgressBar:
            bar.value = float(slime.needs.get(key, 0.0))

func save_game(show_message := true) -> void:
    if build_system == null or household == null:
        return
    var data := {
        "version": 1,
        "day": world_day,
        "minutes": world_minutes,
        "house": build_system.serialize(),
        "household": household.serialize(),
    }
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))
        file.close()
        if show_message:
            _status("Saved")

func load_game() -> bool:
    if not FileAccess.file_exists(SAVE_PATH):
        return false
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Dictionary):
        return false
    build_system.deserialize(parsed.get("house", {}))
    household.deserialize(parsed.get("household", {}))
    world_day = int(parsed.get("day", 1))
    world_minutes = float(parsed.get("minutes", 480.0))
    build_mode = false
    build_tray.visible = false
    build_button.visible = true
    _refresh_family()
    _refresh_needs_panel()
    return true

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
    return button

func _label(text_value: String) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_color_override("font_color", Color("173039"))
    return label

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

func _status(text_value: String) -> void:
    if status_label:
        status_label.text = text_value
