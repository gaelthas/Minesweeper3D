extends SceneTree

## UI 冒烟测试：设置应用、计时累加、0 格隐藏、和弦的射线拾取链路。
## godot --headless --path . -s res://tests/ui_smoke.gd

var _scene: Node
var _f := 0
var _fails := 0


func _initialize() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_f += 1
	match _f:
		6:
			_test_pre_click_flag()
		10:
			_scene.settings.open(5, 12)
			_scene.settings._on_apply()
		14:
			_check(_scene.board_side == 5, "设置应用后阶数应为 5，实际 %d" % _scene.board_side)
			_check(_scene.cells.size() == 125, "5 阶应有 125 个方块，实际 %d" % _scene.cells.size())
			_check(_scene.logic.mine_total == 12, "雷数应为 12，实际 %d" % _scene.logic.mine_total)
			_check(_scene.settings.visible == false, "应用后设置浮层应关闭")
			_check_audio()
			_check_zero_hidden()
			_prepare_chord_scene()
		16:
			_test_no_pass_through()
		18:
			_test_chord_pick()
		20:
			_scene._timing = true
		26:
			_test_settings_page()
		22:
			_test_middle_pan()
		24:
			_check(_scene._elapsed > 0.0, "计时应在 _timing 为真时累加，实际 %.3f" % _scene._elapsed)
			_scene._timing = false
		28:
			print("")
			# 测试脚本直接退出，引擎会报 ObjectDB 泄漏；主场景正常退出时是干净的
			print("PASS" if _fails == 0 else "FAIL %d" % _fails)
			return true
	return false


## 首击之前右键就应该生效：雷还没放下去，但标记是记在格子上的
func _test_pre_click_flag() -> void:
	var logic = _scene.logic
	_check(not logic.generated, "开局时盘面尚未布雷")

	var hi: int = _scene.board_side - 1
	var idx: int = logic.index_of(Vector3i(hi, hi, hi))
	var cam: Camera3D = _scene.camera_rig.camera
	var screen := cam.unproject_position(_scene.cells[idx].global_position)
	_scene._on_flag(screen)

	_check(logic.states[idx] == 2, "首击之前右键应能插旗，实际状态 %d" % logic.states[idx])
	_check(logic.flag_count == 1, "旗数应为 1，实际 %d" % logic.flag_count)


func _check_audio() -> void:
	var streams := {
		"reveal": Sfx.STREAM_REVEAL,
		"flood": Sfx.STREAM_FLOOD,
		"flag": Sfx.STREAM_FLAG,
		"boom": Sfx.STREAM_BOOM,
		"win": Sfx.STREAM_WIN,
		"ui_click": Sfx.STREAM_UI,
	}
	for name in streams:
		var s: AudioStream = streams[name]
		_check(s != null and s.get_length() > 0.0,
			"%s.mp3 应已导入且时长大于 0" % name)
	_check(_scene.sfx != null, "音效池应已创建")


func _check_zero_hidden() -> void:
	var logic = _scene.logic
	logic.place_mines(0, _scene.rng)
	var opened: Array = []
	for i in logic.cell_count():
		if logic.mines[i] == 0:
			var r: Dictionary = logic.reveal(i)
			opened.append_array(r["opened"])
			break
	_scene._refresh_area(opened)

	var visible_zeros := 0
	var zeros := 0
	for c in _scene.cells:
		if logic.states[c.index] == 1 and logic.counts[c.index] == 0:
			zeros += 1
			if c.mesh.visible:
				visible_zeros += 1
	_check(zeros > 0, "测试盘面应至少有一个 0 格")
	_check(visible_zeros == 0, "数字为 0 的 %d 个方块都不应留下网格" % zeros)

	# 六个面全为 0 的格子同样没有信息可显示，也必须消失
	var blank := 0
	var visible_blank := 0
	for c in _scene.cells:
		if logic.states[c.index] != 1:
			continue
		var fc: Array = logic.face_counts_of(c.index)
		var mx := 0
		for v in fc:
			mx = maxi(mx, int(v))
		if mx == 0:
			blank += 1
			if c.mesh.visible:
				visible_blank += 1
	_check(blank > 0, "该盘面应出现六面全 0 的格子（体对角雷），实际 %d 个" % blank)
	_check(visible_blank == 0, "六面全 0 的 %d 个方块也不应留下网格" % blank)


## 3 阶、一颗雷在体心。揭开朝向相机那个角 (2,2,2)，它的数字是 1。
func _prepare_chord_scene() -> void:
	_scene.board_side = 3
	_scene.mine_count = 1
	_scene.new_game()

	var logic = _scene.logic
	# 三颗雷分居角格的三个平面，角格六面都非 0：揭示它不会连锁展开，
	# 和弦的效果才可观测。雷放在三条轴的邻格上，正好把角格的三个面各撑到 1。
	var mines := [Vector3i(1, 1, 2), Vector3i(1, 2, 1), Vector3i(2, 1, 1)]
	for m in mines:
		logic.mines[logic.index_of(m)] = 1
	logic.recompute_counts()
	logic.generated = true

	var corner: int = logic.index_of(Vector3i(2, 2, 2))
	logic.reveal(corner)
	for c in _scene.cells:
		_scene._refresh(c.index)

	_check(logic.counts[corner] == 3, "角格 26 计数应为 3，实际 %d" % logic.counts[corner])
	_check(logic.face_counts_of(corner) == [1, 1, 1, 1, 1, 1],
		"角格六面都应为 1，实际 %s" % str(logic.face_counts_of(corner)))
	_check(logic.revealed_count == 1, "六面非 0 时不应连锁展开，实际开了 %d 格" % logic.revealed_count)

	# 碰撞盒必须跟着缩小的方块一起缩，否则外面会留一圈看不见的碰撞壳，
	# 把本该穿过去的点击吃掉——标记后内层方块看得见却点不到就是这个原因。
	_check(is_equal_approx(_scene.cells[corner]._box.size.x, AppSettings.revealed_size()),
		"已揭示格子的碰撞盒应缩到 %.2f，实际 %.2f" % [
			AppSettings.revealed_size(), _scene.cells[corner]._box.size.x])

	# 未揭示的邻居仍是原尺寸
	var hidden: int = logic.index_of(Vector3i(2, 2, 1))
	_check(is_equal_approx(_scene.cells[hidden]._box.size.x, AppSettings.hidden_size()),
		"未揭示格子的碰撞盒应保持 %.2f，实际 %.2f" % [
			AppSettings.hidden_size(), _scene.cells[hidden]._box.size.x])


## 点已揭示的数字方块应当被吃掉，不能穿过去翻开后面的格子
func _test_no_pass_through() -> void:
	var logic = _scene.logic
	var corner: int = logic.index_of(Vector3i(2, 2, 2))
	_check(logic.states[corner] == BoardLogic.REVEALED, "角格应已揭示")

	var cam: Camera3D = _scene.camera_rig.camera
	var screen := cam.unproject_position(_scene.cells[corner].global_position)
	var before: int = logic.revealed_count
	_scene._on_reveal(screen)
	_check(logic.revealed_count == before,
		"点数字方块不应穿透，实际从 %d 变成 %d" % [before, logic.revealed_count])
	_check(not logic.game_over, "穿透不应导致引爆")


## 左右键同按 = 和弦。这条走完整的事件链路：按下、移动、再按下、松开。
## 中间夹一次 5px 位移——真实鼠标按下时几乎不可能纹丝不动，
## 早期按 4px 判拖拽，和弦会被误判成转相机，永远触发不了。
func _test_chord_pick() -> void:
	var logic = _scene.logic
	var corner: int = logic.index_of(Vector3i(2, 2, 2))

	# 角格六面都是 1（三颗雷分居三个平面），只把 +Z 平面那颗插上旗
	var z_mine: int = logic.index_of(Vector3i(1, 1, 2))
	logic.cycle_mark(z_mine)

	var before: int = logic.revealed_count

	# 瞄准 +Z 面：从方块中心往 +Z 偏到面心，射线必定命中这一面
	var cam: Camera3D = _scene.camera_rig.camera
	var face_point: Vector3 = _scene.cells[corner].global_position + Vector3(0, 0, 0.30)
	var screen := cam.unproject_position(face_point)

	_press(MOUSE_BUTTON_LEFT, screen)
	_move(screen + Vector2(5, 0))
	_press(MOUSE_BUTTON_RIGHT, screen + Vector2(5, 0))
	_release(MOUSE_BUTTON_LEFT, screen + Vector2(5, 0))
	_release(MOUSE_BUTTON_RIGHT, screen + Vector2(5, 0))

	# +Z 面只有 3 个邻格，其中一颗是雷，插旗后应揭开另外 2 个
	_check(logic.states[logic.index_of(Vector3i(1, 2, 2))] == BoardLogic.REVEALED,
		"+Z 平面内的 (1,2,2) 应被和弦揭开")
	_check(logic.states[logic.index_of(Vector3i(2, 1, 2))] == BoardLogic.REVEALED,
		"+Z 平面内的 (2,1,2) 应被和弦揭开")
	_check(logic.revealed_count > before,
		"和弦应揭开新的格子（%d → %d）" % [before, logic.revealed_count])
	_check(logic.states[z_mine] == BoardLogic.FLAGGED, "已插旗的雷位不应被和弦翻掉")
	_check(not logic.game_over, "和弦不应引爆已插旗的雷")
	_check(not _scene._down.has(MOUSE_BUTTON_LEFT) and not _scene._down.has(MOUSE_BUTTON_RIGHT),
		"松开后按键状态应清空")


## 中键拖拽平移视角（默认映射：中键 = 平移）
func _test_middle_pan() -> void:
	var before: Vector3 = _scene.camera_rig.pivot
	var screen := Vector2(640, 360)
	_press(MOUSE_BUTTON_MIDDLE, screen)
	_drag(screen, Vector2(80, 0))
	_release(MOUSE_BUTTON_MIDDLE, screen + Vector2(80, 0))
	_check(not _scene.camera_rig.pivot.is_equal_approx(before),
		"中键拖拽应平移视角，pivot 仍在 %s" % str(_scene.camera_rig.pivot))
	_check(not _scene.logic.game_over, "平移不应触发任何棋盘动作")


func _drag(pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos + relative
	ev.relative = relative
	_scene._unhandled_input(ev)


func _press(button: MouseButton, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = pos
	_scene._unhandled_input(ev)


func _release(button: MouseButton, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = false
	ev.position = pos
	_scene._unhandled_input(ev)


func _move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.relative = Vector2(5, 0)
	_scene._unhandled_input(ev)


## 选项页：改动即时生效并落盘
func _test_settings_page() -> void:
	var page: SettingsPage = _scene.settings_page
	page.open()
	_check(page.visible, "选项页应能打开")

	page._on_volume(35.0)
	_check(AppSettings.volume == 35, "音量应更新为 35，实际 %d" % AppSettings.volume)

	var cfg := ConfigFile.new()
	_check(cfg.load(AppSettings.PATH) == OK, "设置应已写入 user://settings.cfg")
	_check(int(cfg.get_value("audio", "volume", -1)) == 35,
		"落盘音量应为 35，实际 %s" % str(cfg.get_value("audio", "volume", -1)))

	# 右下角的间距滑块：只平移方块中心，不改方块尺寸
	var corner: int = _scene.logic.index_of(Vector3i(2, 2, 2))
	var neighbor: int = _scene.logic.index_of(Vector3i(1, 2, 2))
	var before_pos: Vector3 = _scene.cells[corner].position
	_scene._on_spacing_changed(150.0)
	_check(AppSettings.spacing == 150, "间距应为 150，实际 %d" % AppSettings.spacing)
	_check(is_equal_approx(AppSettings.pitch(), 1.5), "倍率应为 1.5，实际 %.2f" % AppSettings.pitch())
	_check(is_equal_approx(AppSettings.revealed_size(), 0.70),
		"间距不应改变方块尺寸，实际 %.2f" % AppSettings.revealed_size())
	_check(is_equal_approx(_scene.cells[corner]._box.size.x, 0.70),
		"碰撞盒也不该变，实际 %.2f" % _scene.cells[corner]._box.size.x)
	var gap: float = (_scene.cells[corner].position - _scene.cells[neighbor].position).length()
	_check(is_equal_approx(gap, 1.5), "相邻方块中心距应为 1.5，实际 %.2f" % gap)
	_check(not before_pos.is_equal_approx(_scene.cells[corner].position), "方块位置应随间距变化")
	_scene._on_spacing_changed(100.0)
	_check(is_equal_approx(AppSettings.pitch(), 1.0), "回到 100%% 时倍率应为 1.0")

	page._on_volume(70.0)
	page.close()
	_check(not page.visible, "选项页应能关闭")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  " + msg)
	else:
		_fails += 1
		printerr("  x   " + msg)
