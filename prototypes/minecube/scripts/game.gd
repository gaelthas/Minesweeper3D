extends Node3D

## 入口：装配环境、相机、HUD、设置浮层，并串联逻辑层与视图层。

const DRAG_THRESHOLD := 4.0
## 和弦手势的位移容差：按下第二个键时若还在这个范围内，撤销之前的拖拽判定
const CHORD_SLOP := 14.0

var board_side := 5
var mine_count := 38

var logic: BoardLogic
var cells: Array[CellView] = []
var camera_rig: CameraRig
var hud: Hud
var settings: SettingsPanel
var settings_page: SettingsPage
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

	AppSettings.load_from_disk()
	AppSettings.apply()

	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.restart_pressed.connect(_on_restart)
	hud.settings_pressed.connect(_open_settings)
	hud.options_pressed.connect(_open_options)
	hud.spacing_changed.connect(_on_spacing_changed)
	hud.set_spacing(AppSettings.spacing)
	hud.spacing_changed.connect(_on_spacing_changed)
	hud.set_spacing(AppSettings.spacing)
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

	settings_page = SettingsPage.new()
	settings_page.name = "SettingsPage"
	settings_page.setup()
	overlay.add_child(settings_page)

	result_panel = ResultPanel.new()
	result_panel.name = "Result"
	result_panel.setup()
	result_panel.restart_pressed.connect(_on_restart)
	overlay.add_child(result_panel)

	new_game()


func _process(delta: float) -> void:
	if hud != null:
		hud.set_fps(Engine.get_frames_per_second() if AppSettings.show_fps else -1)
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
	return (settings != null and settings.visible) \
		or (settings_page != null and settings_page.visible) \
		or (result_panel != null and result_panel.visible)


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
		-(board_size.x - 1) * 0.5 * AppSettings.pitch(),
		-(board_size.y - 1) * 0.5 * AppSettings.pitch(),
		-(board_size.z - 1) * 0.5 * AppSettings.pitch()
	)

	for z in board_size.z:
		for y in board_size.y:
			for x in board_size.x:
				var idx := logic.index_of(Vector3i(x, y, z))
				var cell := CellView.new(idx)
				cell.name = "Cell_%d" % idx
				cell.position = origin + Vector3(x, y, z) * AppSettings.pitch()
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
	if AppSettings.muted:
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


func _open_options() -> void:
	sfx.ui()
	settings_page.open()


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


func _is_click_action(button: int) -> bool:
	var a: int = AppSettings.action_for(button)
	return a == AppSettings.MouseAction.REVEAL or a == AppSettings.MouseAction.FLAG \
		or a == AppSettings.MouseAction.CHORD


func _panning_held() -> bool:
	for b in _down.keys():
		if AppSettings.action_for(b) == AppSettings.MouseAction.PAN:
			return true
	return false


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
			# 左右两个"点击类"键同时按下 = 和弦。平移键不参与。
			if _down.has(MOUSE_BUTTON_LEFT) and _down.has(MOUSE_BUTTON_RIGHT) \
					and _is_click_action(MOUSE_BUTTON_LEFT) and _is_click_action(MOUSE_BUTTON_RIGHT):
				_chord_armed = true
				# 按下第二个键时手可能已经抖了几像素，之前若已判成拖拽，撤回
				if (mb.position - _press_pos).length() <= CHORD_SLOP:
					_dragging = false
		else:
			_down.erase(btn)
			var action: int = AppSettings.action_for(btn)
			if not _action_done and not _dragging and action != AppSettings.MouseAction.PAN \
					and action != AppSettings.MouseAction.NONE:
				var pos := mb.position
				if _chord_armed or action == AppSettings.MouseAction.CHORD:
					_on_chord(pos)
					_action_done = true
				elif action == AppSettings.MouseAction.REVEAL:
					_on_reveal(pos)
					_action_done = true
				elif action == AppSettings.MouseAction.FLAG:
					_on_flag(pos)
					_action_done = true
			if _down.is_empty():
				_chord_armed = false
				_action_done = false
				_dragging = false

	elif event is InputEventMouseMotion and not _down.is_empty():
		var mm := event as InputEventMouseMotion
		# 和弦手势不转相机：左右键都按下时手必然会动，
		# 一旦按普通阈值（4px）判成拖拽，和弦就永远触发不了。
		if _chord_armed:
			return
		if not _dragging and (mm.position - _press_pos).length() > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			# 按住平移键时拖拽是平移，其余情况是转视角
			if _panning_held():
				camera_rig.pan(mm.relative)
			else:
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
		elif settings_page != null and settings_page.visible:
			settings_page.close()
		return

	if _ui_blocking():
		return

	if k.keycode == KEY_R:
		_on_restart()
	elif k.keycode == KEY_M:
		AppSettings.muted = not AppSettings.muted
		AppSettings.apply()
		AppSettings.save()
		_update_level_text()
		if settings_page != null and settings_page.visible:
			settings_page._sync()


## 返回 { index, normal }：normal 用来判断点中的是哪一面
func _raycast(screen_pos: Vector2, mask: int) -> Dictionary:
	if camera_rig == null or camera_rig.camera == null:
		return {}
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider = hit.get("collider")
	if collider != null and collider.has_meta("cell_index"):
		var idx := int(collider.get_meta("cell_index"))
		# 重开是 queue_free，上一局的方块会在同一帧里还活着。
		# 只认当前这一局真正挂在 cells 里的碰撞体，否则点击会被幽灵格子吞掉。
		if idx >= 0 and idx < cells.size() and cells[idx].body == collider:
			return {"index": idx, "normal": hit.get("normal", Vector3.UP)}
	return {}


func _pick(screen_pos: Vector2, mask: int = CellView.LAYER_SOLID) -> int:
	return int(_raycast(screen_pos, mask).get("index", -1))


## 碰撞盒是轴对齐的，法线落在某条轴上，直接映射到 CellView._faces 的序号
## 顺序是 +Z -Z +X -X +Y -Y
static func _face_from_normal(n: Vector3) -> int:
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	if az >= ax and az >= ay:
		return 0 if n.z > 0.0 else 1
	if ax >= ay:
		return 2 if n.x > 0.0 else 3
	return 4 if n.y > 0.0 else 5


func _on_reveal(screen_pos: Vector2) -> void:
	if logic.game_over:
		return
	# 已揭示的数字方块也进拾取范围：点到它就吃掉这一下，不能穿过去翻开后面的格子。
	# 要挖内层得从方块之间的缝里瞄——那本来就是三维可玩性的一部分。
	var idx := _pick(screen_pos, CellView.LAYER_SOLID | CellView.LAYER_OPEN)
	if idx < 0:
		return
	if logic.states[idx] == BoardLogic.FLAGGED:
		return
	if logic.states[idx] == BoardLogic.REVEALED:
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
	var hit := _raycast(screen_pos, CellView.LAYER_SOLID | CellView.LAYER_OPEN)
	if hit.is_empty():
		return
	var idx := int(hit["index"])
	# 按平面和弦：点哪一面就只在这一面的平面里判定
	var face := _face_from_normal(hit["normal"] as Vector3)

	var result := logic.chord_face(idx, face)
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


func _on_spacing_changed(value: float) -> void:
	AppSettings.spacing = clampi(int(value), 100, 200)
	AppSettings.save()
	hud.set_spacing(AppSettings.spacing)
	_relayout_cells()


## 按当前间距重新摆放所有方块——只动位置，方块尺寸不变
func _relayout_cells() -> void:
	if logic == null:
		return
	var pitch := AppSettings.pitch()
	var size := Vector3i(board_side, board_side, board_side)
	var origin := Vector3(
		-(size.x - 1) * 0.5 * pitch,
		-(size.y - 1) * 0.5 * pitch,
		-(size.z - 1) * 0.5 * pitch)
	for c in cells:
		var p := logic.coord_of(c.index)
		c.position = origin + Vector3(p) * pitch


## 间距或缝隙改了之后，所有方块都要按新尺寸重画一遍
func _refresh_all_cells() -> void:
	if logic == null:
		return
	for c in cells:
		_refresh(c.index)


func _refresh(i: int) -> void:
	if i < 0 or i >= cells.size():
		return
	cells[i].apply(logic.states[i], logic.counts[i], _face_mask(i), logic.face_counts_of(i))


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
			cells[i].apply(BoardLogic.REVEALED, logic.counts[i], _face_mask(i), logic.face_counts_of(i))
