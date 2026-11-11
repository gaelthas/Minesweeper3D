extends Node3D

## 入口：装配环境、相机、HUD、设置浮层，并串联逻辑层与视图层。

const SPACING := 1.0
const DRAG_THRESHOLD := 4.0

var board_side := 4
var mine_count := 6

var logic: BoardLogic
var cells: Array[CellView] = []
var camera_rig: CameraRig
var hud: Hud
var settings: SettingsPanel
var result_panel: ResultPanel
var sfx: Sfx

var rng := RandomNumberGenerator.new()

var _board_root: Node3D
var _press_pos := Vector2.ZERO
var _dragging := false
var _framed_side := 0

var _down := {}
var _chord_armed := false
var _action_done := false

var _elapsed := 0.0
var _timing := false
var _paused_for_settings := false


func _ready() -> void:
	rng.randomize()
	_build_environment()

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.restart_pressed.connect(_on_restart)
	hud.settings_pressed.connect(_open_settings)
	hud.quit_pressed.connect(_quit)

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 2
	add_child(overlay)

	settings = SettingsPanel.new()
	settings.name = "Settings"
	settings.setup()
	settings.applied.connect(_on_settings_applied)
	overlay.add_child(settings)

	result_panel = ResultPanel.new()
	result_panel.name = "Result"
	result_panel.setup()
	result_panel.restart_pressed.connect(_on_restart)
	overlay.add_child(result_panel)

	new_game()


func _process(delta: float) -> void:
	if _ui_blocking():
		return
	_update_label_facing()
	if _paused_for_settings:
		_paused_for_settings = false
		if logic != null and not logic.game_over and logic.generated:
			_timing = true
	if _timing and logic != null and not logic.game_over:
		_elapsed += delta
		hud.set_time(_elapsed)


func _ui_blocking() -> bool:
	return (settings != null and settings.visible) or (result_panel != null and result_panel.visible)


func _update_label_facing() -> void:
	if camera_rig == null or camera_rig.camera == null or cells.is_empty():
		return
	var cam_pos := camera_rig.camera.global_position
	for c in cells:
		c.update_symbol_facing(cam_pos)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.784, 0.812, 0.867)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.718, 0.761, 0.867)
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34, -40, 0)
	key.light_energy = 1.35
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 60.0
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16, 148, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.78, 0.85, 1.0)
	add_child(fill)


func new_game() -> void:
	var board_size := Vector3i(board_side, board_side, board_side)

	if is_instance_valid(_board_root):
		_board_root.queue_free()

	_board_root = Node3D.new()
	_board_root.name = "Board"
	add_child(_board_root)

	cells.clear()
	logic = BoardLogic.new(board_size, mine_count)

	var origin := Vector3(
		-(board_size.x - 1) * 0.5 * SPACING,
		-(board_size.y - 1) * 0.5 * SPACING,
		-(board_size.z - 1) * 0.5 * SPACING
	)

	for z in board_size.z:
		for y in board_size.y:
			for x in board_size.x:
				var idx := logic.index_of(Vector3i(x, y, z))
				var cell := CellView.new(idx)
				cell.name = "Cell_%d" % idx
				cell.position = origin + Vector3(x, y, z) * SPACING
				_board_root.add_child(cell)
				cells.append(cell)

	if _framed_side != board_side:
		camera_rig.frame(board_size)
		_framed_side = board_side

	_elapsed = 0.0
	_timing = false
	_paused_for_settings = false
	if result_panel != null:
		result_panel.close()

	hud.set_time(0.0)
	_update_level_text()
	hud.update_stats(logic.mine_total, 0, 0, logic.cell_count() - logic.mine_total)
	hud.set_status(hud.t("点击任意方块开始", "click any cube to begin"))


func _update_level_text() -> void:
	var suffix := ""
	if sfx != null and sfx.muted:
		suffix = " · " + hud.t("静音", "muted")
	hud.set_level("%d × %d × %d · %d %s%s" % [
		board_side, board_side, board_side, mine_count, hud.t("雷", "mines"), suffix])


func _finish_lose() -> void:
	_timing = false
	_show_all_mines()
	hud.set_time(_elapsed)
	sfx.boom()
	hud.set_status(hud.t("踩到雷了 · 按 R 重开", "BOOM · press R to restart"))
	result_panel.open(_elapsed, board_side, mine_count, false)


func _finish_win() -> void:
	_timing = false
	hud.set_time(_elapsed)
	sfx.win()
	hud.set_status(hud.t("清空了 · 按 R 再来一局", "CLEARED · press R for another"))
	result_panel.open(_elapsed, board_side, mine_count, true)


func _on_restart() -> void:
	sfx.ui()
	new_game()


func _open_settings() -> void:
	sfx.ui()
	if _timing:
		_paused_for_settings = true
		_timing = false
	settings.open(board_side, mine_count)


func _on_settings_applied(side: int, mines: int) -> void:
	sfx.ui()
	board_side = side
	mine_count = mines
	new_game()


func _quit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _ui_blocking():
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_rig.zoom(-0.55)
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom(0.55)
			return

		var btn := mb.button_index
		if btn != MOUSE_BUTTON_LEFT and btn != MOUSE_BUTTON_RIGHT and btn != MOUSE_BUTTON_MIDDLE:
			return

		if mb.pressed:
			if _down.is_empty():
				_press_pos = mb.position
				_dragging = false
				_chord_armed = false
				_action_done = false
			_down[btn] = true
			# 左右同按或中键 = 和弦
			if (_down.has(MOUSE_BUTTON_LEFT) and _down.has(MOUSE_BUTTON_RIGHT)) \
					or btn == MOUSE_BUTTON_MIDDLE:
				_chord_armed = true
		else:
			_down.erase(btn)
			if not _action_done and not _dragging:
				var pos := get_viewport().get_mouse_position()
				if _chord_armed:
					_on_chord(pos)
					_action_done = true
				elif btn == MOUSE_BUTTON_LEFT:
					_on_reveal(pos)
					_action_done = true
				elif btn == MOUSE_BUTTON_RIGHT:
					_on_flag(pos)
					_action_done = true
			if _down.is_empty():
				_chord_armed = false
				_action_done = false
				_dragging = false

	elif event is InputEventMouseMotion and not _down.is_empty():
		var mm := event as InputEventMouseMotion
		if not _dragging and (mm.position - _press_pos).length() > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			camera_rig.orbit(mm.relative)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return

	if k.keycode == KEY_ESCAPE:
		if settings != null and settings.visible:
			settings.close()
		elif result_panel != null and result_panel.visible:
			result_panel.close()
		return

	if _ui_blocking():
		return

	if k.keycode == KEY_R:
		_on_restart()
	elif k.keycode == KEY_M:
		sfx.toggle_mute()
		_update_level_text()


func _pick(screen_pos: Vector2, mask: int = CellView.LAYER_SOLID) -> int:
	if camera_rig == null or camera_rig.camera == null:
		return -1
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	var collider = hit.get("collider")
	if collider != null and collider.has_meta("cell_index"):
		return int(collider.get_meta("cell_index"))
	return -1


func _on_reveal(screen_pos: Vector2) -> void:
	if logic.game_over:
		return
	var idx := _pick(screen_pos)
	if idx < 0:
		return
	if logic.states[idx] == BoardLogic.FLAGGED:
		return

	if not logic.generated:
		logic.place_mines(idx, rng)
		_elapsed = 0.0
		_timing = true

	var result := logic.reveal(idx)
	var opened: Array = result["opened"]
	_refresh_area(opened)
	_refresh_stats()

	if result["boom"]:
		_finish_lose()
	else:
		if opened.size() >= 3:
			sfx.flood(opened.size())
		elif not opened.is_empty():
			sfx.reveal()
		if logic.won:
			_finish_win()


func _on_flag(screen_pos: Vector2) -> void:
	if logic.game_over:
		return
	var idx := _pick(screen_pos, CellView.LAYER_SOLID | CellView.LAYER_OPEN)
	if idx < 0:
		return
	var prev := logic.states[idx]
	if prev == BoardLogic.REVEALED:
		return
	logic.cycle_mark(idx)
	_refresh(idx)
	_refresh_stats()
	match prev:
		BoardLogic.HIDDEN:
			sfx.flag()
		BoardLogic.FLAGGED:
			sfx.question()
		_:
			sfx.unflag()


## 和弦：在已揭示的数字格上，旗数与数字相等时一次揭开周围所有未插旗的格。
func _on_chord(screen_pos: Vector2) -> void:
	if logic.game_over:
		return
	var idx := _pick(screen_pos, CellView.LAYER_SOLID | CellView.LAYER_OPEN)
	if idx < 0:
		return

	var result := logic.chord(idx)
	var opened: Array = result["opened"]
	if opened.is_empty() and not result["boom"]:
		return

	_refresh_area(opened)
	_refresh_stats()

	if result["boom"]:
		_finish_lose()
	else:
		sfx.chord()
		if logic.won:
			_finish_win()


func _refresh(i: int) -> void:
	if i < 0 or i >= cells.size():
		return
	cells[i].apply(logic.states[i], logic.counts[i], _face_mask(i))


## 一个格子被揭示后，邻格的可见面也会变化，需要一起刷新。
func _refresh_area(indices: Array) -> void:
	var seen := {}
	for i in indices:
		var idx := int(i)
		seen[idx] = true
		for n in logic.neighbors(idx):
			seen[n] = true
	for i in seen.keys():
		_refresh(int(i))


## 只有朝盘面外、或朝向已揭示格的面才印数字。
func _face_mask(idx: int) -> int:
	var c := logic.coord_of(idx)
	var mask := 0
	var dirs := [
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	]
	for k in dirs.size():
		var q: Vector3i = c + dirs[k]
		if not logic.in_bounds(q):
			mask |= 1 << k
		elif logic.states[logic.index_of(q)] == BoardLogic.REVEALED:
			mask |= 1 << k
	return mask


func _refresh_stats() -> void:
	hud.update_stats(
		logic.mine_total,
		logic.flag_count,
		logic.revealed_count,
		logic.cell_count() - logic.mine_total
	)


func _show_all_mines() -> void:
	for i in logic.cell_count():
		if i >= cells.size():
			continue
		if logic.mines[i] == 1:
			# 已经正确插旗的雷位保留旗面，不被雷模型盖掉
			if logic.states[i] == BoardLogic.FLAGGED:
				continue
			cells[i].set_mine(i == logic.hit_index)
		elif logic.states[i] == BoardLogic.FLAGGED or logic.states[i] == BoardLogic.QUESTION:
			# 插错或标了问号的格子：直接翻出底下的数字，让玩家看见自己错在哪
			cells[i].apply(BoardLogic.REVEALED, logic.counts[i], _face_mask(i))
