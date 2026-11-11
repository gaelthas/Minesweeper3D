extends SceneTree

## 截图用：加载主场景，按帧序摆放几个状态并存 PNG。
## godot --path . -s res://tests/capture.gd

const OUT_DIR := "/Users/galois/workspace/Minesweeper3D/doc/shots"

var _scene: Node
var _frame := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 20261110
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		20:
			_save("01_start")
		22:
			_reveal_some(10)
		25:
			_save("02_revealed")
		27:
			_set_board(5, 12)
		29:
			_reveal_some(18)
		32:
			_save("03_5x5x5")
		34:
			_scene._open_settings()
		37:
			_save("04_settings")
		39:
			_scene.settings.close()
			_set_board(4, 6)
		41:
			_seed_marks()
		45:
			_save("05_marks")
		47:
			_boom()
		51:
			_save("06_mines")
		53:
			_scene._elapsed = 46.3
			_scene._finish_lose()
		56:
			_save("09_lose")
		58:
			_scene.result_panel.close()
			_set_board(4, 6)
			_win()
		61:
			_save("07_result")
		63:
			_scene.result_panel.close()
			_set_board(9, 38)
		65:
			_reveal_some(24)
		68:
			_save("08_9x9x9")
		70:
			_scene._open_options()
		73:
			_save("10_options")
		75:
			_scene.settings_page.close()
			return true
	return false


func _set_board(side: int, mines: int) -> void:
	_scene.board_side = side
	_scene.mine_count = mines
	_scene.new_game()


func _reveal_some(limit: int) -> void:
	var logic = _scene.logic
	logic.place_mines(0, _rng)
	var opened: Array = []
	var done := 0
	for i in logic.cell_count():
		if done >= limit:
			break
		if logic.mines[i] == 0:
			var res: Dictionary = logic.reveal(i)
			opened.append_array(res["opened"])
			done += 1
	_scene._refresh_area(opened)
	_scene._refresh_stats()


## 标记三种状态各摆几个：旗、旗、问号、问号
func _seed_marks() -> void:
	var logic = _scene.logic
	logic.place_mines(0, _rng)
	var done := 0
	for i in logic.cell_count():
		if done >= 6:
			break
		if logic.mines[i] == 0:
			logic.reveal(i)
			done += 1

	var marked := 0
	for i in logic.cell_count():
		if marked >= 4:
			break
		if logic.mines[i] == 1:
			logic.cycle_mark(i)
			if marked >= 2:
				logic.cycle_mark(i)
			marked += 1

	for c in _scene.cells:
		_scene._refresh(c.index)
	_scene._refresh_stats()


func _boom() -> void:
	var logic = _scene.logic
	var target := -1
	for i in logic.cell_count():
		if logic.mines[i] == 1 and logic.states[i] == 0:
			target = i
			break
	if target < 0:
		return
	var res: Dictionary = logic.reveal(target)
	_scene._refresh_area(res["opened"])
	_scene._show_all_mines()
	_scene._refresh_stats()


func _win() -> void:
	var logic = _scene.logic
	logic.place_mines(0, _rng)
	var opened: Array = []
	for i in logic.cell_count():
		if logic.mines[i] == 0:
			var res: Dictionary = logic.reveal(i)
			opened.append_array(res["opened"])
	_scene._elapsed = 83.7
	_scene._refresh_area(opened)
	_scene._refresh_stats()
	if logic.won:
		_scene._finish_win()


func _save(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_texture().get_image()
	if img == null:
		printerr("no image")
		return
	var path := OUT_DIR + "/" + name + ".png"
	var err := img.save_png(path)
	print("saved %s err=%d" % [path, err])
