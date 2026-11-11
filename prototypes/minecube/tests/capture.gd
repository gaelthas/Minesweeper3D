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
			_scene.board_side = 5
			_scene.mine_count = 12
			_scene.new_game()
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
			_scene.board_side = 4
			_scene.mine_count = 6
			_scene.new_game()
		41:
			_seed_flags()
		45:
			_save("05_flags")
		47:
			_boom()
		51:
			_save("06_mines")
		53:
			return true
	return false


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


func _seed_flags() -> void:
	var logic = _scene.logic
	logic.place_mines(0, _rng)
	var done := 0
	for i in logic.cell_count():
		if done >= 8:
			break
		if logic.mines[i] == 0:
			logic.reveal(i)
			done += 1
	var flagged := 0
	for i in logic.cell_count():
		if flagged >= 3:
			break
		if logic.mines[i] == 1:
			logic.toggle_flag(i)
			flagged += 1
	for c in _scene.cells:
		_scene._refresh(c.index)
	_scene._refresh_stats()


func _boom() -> void:
	var logic = _scene.logic
	if not logic.generated:
		logic.place_mines(0, _rng)
	var target := -1
	for i in logic.cell_count():
		if logic.mines[i] == 1 and logic.states[i] != 2:
			target = i
			break
	if target < 0:
		return
	var res: Dictionary = logic.reveal(target)
	_scene._refresh_area(res["opened"])
	_scene._show_all_mines()
	_scene._refresh_stats()


func _save(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_texture().get_image()
	if img == null:
		printerr("no image")
		return
	var path := OUT_DIR + "/" + name + ".png"
	var err := img.save_png(path)
	print("saved %s err=%d" % [path, err])
