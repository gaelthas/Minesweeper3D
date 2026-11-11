class_name SettingsPanel
extends Control

## 开局设置：阶数（N×N×N）与雷数。居中浮层，打开时挡住 3D 输入。
## 控件全部自绘，避免默认主题的深色控件落在浅色面板上。

signal applied(side: int, mines: int)

const MIN_SIDE := 3
## 上限由性能定：12 阶 1728 格、1.7 万节点、全开 54.8 FPS；
## 14 阶 2744 格掉到 23.8 FPS，已经不能玩。
const MAX_SIDE := 13
const TARGET_DENSITY := 0.30

var _side := 5
var _mines := 38

var _size_slider: HSlider
var _size_label: Label
var _mine_label: Label
var _slider: HSlider
var _hint: Label


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open(side: int, mines: int) -> void:
	_side = clampi(side, MIN_SIDE, MAX_SIDE)
	_mines = clampi(mines, 1, _max_mines())
	_refresh()
	visible = true


func close() -> void:
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.094, 0.114, 0.153, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(404, 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	col.add_child(UiKit.label(UiKit.t("设置", "SETTINGS"), 22, UiKit.INK))
	col.add_child(UiKit.label(
		UiKit.t("阶数决定盘面大小，雷数决定密度", "size sets the board, mines set the density"),
		13, UiKit.INK_SOFT))

	col.add_child(_build_size_row())
	col.add_child(_build_mine_row())

	_hint = UiKit.label("", 13, UiKit.INK_SOFT)
	col.add_child(_hint)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(actions)

	var cancel := UiKit.button(UiKit.t("取消", "CANCEL"))
	cancel.pressed.connect(close)
	actions.add_child(cancel)

	var start := UiKit.button(UiKit.t("开始", "START"))
	start.pressed.connect(_on_apply)
	actions.add_child(start)

	_refresh()


func _build_size_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("阶数", "SIZE"))

	_size_slider = _make_slider(MIN_SIDE, MAX_SIDE)
	_size_slider.value_changed.connect(_on_size_changed)
	row.add_child(_size_slider)

	_size_label = UiKit.label("5", 17, UiKit.INK)
	_size_label.custom_minimum_size = Vector2(46, 0)
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_size_label)

	return row


## 两条滑块共用同一套自绘样式：默认主题的抓点是深色方块，落在浅色面板上很突兀
func _make_slider(lo: int, hi: int) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 1
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 26)
	sl.focus_mode = Control.FOCUS_NONE

	var grabber := UiKit.slider_grabber()
	sl.add_theme_icon_override("grabber", grabber)
	sl.add_theme_icon_override("grabber_highlight", grabber)
	sl.add_theme_icon_override("grabber_disabled", grabber)
	sl.add_theme_stylebox_override("slider", UiKit.slider_track())
	sl.add_theme_stylebox_override("grabber_area", UiKit.slider_fill())
	sl.add_theme_stylebox_override("grabber_area_highlight", UiKit.slider_fill())
	return sl


func _build_mine_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("雷数", "MINES"))

	_slider = _make_slider(1, 63)
	_slider.value_changed.connect(_on_mines_changed)
	row.add_child(_slider)

	_mine_label = UiKit.label("38", 17, UiKit.INK)
	_mine_label.custom_minimum_size = Vector2(46, 0)
	_mine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_mine_label)

	return row


func _row_label(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 15, UiKit.INK)
	l.custom_minimum_size = Vector2(52, 0)
	row.add_child(l)
	return row


func _on_size_changed(value: float) -> void:
	_side = clampi(int(value), MIN_SIDE, MAX_SIDE)
	_mines = _recommended(_total())
	_refresh()


func _on_mines_changed(value: float) -> void:
	_mines = clampi(int(value), 1, _max_mines())
	_refresh()


func _total() -> int:
	return _side * _side * _side


func _max_mines() -> int:
	return maxi(1, _total() - 1)


func _recommended(total: int) -> int:
	return clampi(int(round(total * TARGET_DENSITY)), 1, maxi(1, total - 1))


func _refresh() -> void:
	if _mine_label == null:
		return
	_size_label.text = str(_side)
	if not is_equal_approx(float(_side), _size_slider.value):
		_size_slider.set_value_no_signal(float(_side))

	_size_label.text = str(_side)
	if not is_equal_approx(float(_side), _size_slider.value):
		_size_slider.set_value_no_signal(float(_side))

	_mine_label.text = str(_mines)
	_slider.max_value = _max_mines()
	if not is_equal_approx(float(_mines), _slider.value):
		_slider.set_value_no_signal(float(_mines))
	var total := _total()
	_hint.text = UiKit.t("%d × %d × %d · 共 %d 格 · 密度 %.1f%% · 推荐 %d 颗",
		"%d × %d × %d · %d cells · %.1f%% · suggest %d") % [
		_side, _side, _side, total, 100.0 * float(_mines) / float(total), _recommended(total)]


func _on_apply() -> void:
	close()
	applied.emit(_side, _mines)
