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
		10:
			_scene.settings.open(5, 12)
			_scene.settings._on_apply()
		14:
			_check(_scene.board_side == 5, "设置应用后阶数应为 5，实际 %d" % _scene.board_side)
			_check(_scene.cells.size() == 125, "5 阶应有 125 个方块，实际 %d" % _scene.cells.size())
			_check(_scene.logic.mine_total == 12, "雷数应为 12，实际 %d" % _scene.logic.mine_total)
			_check(_scene.settings.visible == false, "应用后设置浮层应关闭")
			_check_zero_hidden()
			_prepare_chord_scene()
		18:
			_test_chord_pick()
		20:
			_scene._timing = true
		24:
			_check(_scene._elapsed > 0.0, "计时应在 _timing 为真时累加，实际 %.3f" % _scene._elapsed)
			_scene._timing = false
		28:
			print("")
			print("PASS" if _fails == 0 else "FAIL %d" % _fails)
			return true
	return false


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


## 3 阶、一颗雷在体心。揭开朝向相机那个角 (2,2,2)，它的数字是 1。
func _prepare_chord_scene() -> void:
	_scene.board_side = 3
	_scene.mine_count = 1
	_scene.new_game()

	var logic = _scene.logic
	var center: int = logic.index_of(Vector3i(1, 1, 1))
	logic.mines[center] = 1
	logic.recompute_counts()
	logic.generated = true

	var corner: int = logic.index_of(Vector3i(2, 2, 2))
	logic.reveal(corner)
	logic.toggle_flag(center)
	for c in _scene.cells:
		_scene._refresh(c.index)

	_check(logic.counts[corner] == 1, "角格数字应为 1，实际 %d" % logic.counts[corner])


func _test_chord_pick() -> void:
	var logic = _scene.logic
	var corner: int = logic.index_of(Vector3i(2, 2, 2))
	var before: int = logic.revealed_count

	# 从方块的世界坐标反推屏幕坐标，走一遍真实的射线拾取
	var cam: Camera3D = _scene.camera_rig.camera
	var screen := cam.unproject_position(_scene.cells[corner].global_position)
	_scene._on_chord(screen)

	_check(logic.revealed_count > before,
		"和弦应通过射线命中数字格并揭开邻格（%d → %d）" % [before, logic.revealed_count])
	var center: int = logic.index_of(Vector3i(1, 1, 1))
	_check(logic.states[center] == 2, "已插旗的雷位不应被和弦翻掉")
	_check(not logic.game_over or logic.won, "和弦不应引爆已插旗的雷")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  " + msg)
	else:
		_fails += 1
		printerr("  x   " + msg)
