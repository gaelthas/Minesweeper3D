class_name SettingsPanel
extends Control

## 开局设置：阶数（N×N×N）与雷数。居中浮层，打开时挡住 3D 输入。
## 控件全部自绘，避免默认主题的深色控件落在浅色面板上。

signal applied(side: int, mines: int)

const SIDES := [3, 4, 5, 6, 7, 8, 9]
const TARGET_DENSITY := 0.14

var _side := 4
var _mines := 6

var _size_buttons: Array[Button] = []
var _mine_label: Label
var _minus: Button
var _plus: Button
var _hint: Label


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open(side: int, mines: int) -> void:
	_side = side if SIDES.has(side) else 4
	_mines = clampi(mines, 1, _max_mines())
	_sync_toggles()
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

	_sync_toggles()
	_refresh()


func _build_size_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("阶数", "SIZE"))
	var group := ButtonGroup.new()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for s in SIDES:
		var b := UiKit.toggle(str(s), 15, 4)
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func() -> void: _on_size(s))
		box.add_child(b)
		_size_buttons.append(b)

	row.add_child(box)
	return row


func _build_mine_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("雷数", "MINES"))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_minus = UiKit.button("−", 18)
	_minus.custom_minimum_size = Vector2(44, 34)
	_minus.pressed.connect(func() -> void: _bump(-1))
	box.add_child(_minus)

	var field := PanelContainer.new()
	field.add_theme_stylebox_override("panel", UiKit.field_style())
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mine_label = UiKit.label("6", 17, UiKit.INK)
	_mine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_child(_mine_label)
	box.add_child(field)

	_plus = UiKit.button("+", 18)
	_plus.custom_minimum_size = Vector2(44, 34)
	_plus.pressed.connect(func() -> void: _bump(1))
	box.add_child(_plus)

	row.add_child(box)
	return row


func _row_label(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 15, UiKit.INK)
	l.custom_minimum_size = Vector2(52, 0)
	row.add_child(l)
	return row


func _on_size(side: int) -> void:
	_side = side
	_mines = _recommended(_total())
	_refresh()


func _bump(delta: int) -> void:
	_mines = clampi(_mines + delta, 1, _max_mines())
	_refresh()


func _total() -> int:
	return _side * _side * _side


func _max_mines() -> int:
	return maxi(1, _total() - 1)


func _recommended(total: int) -> int:
	return clampi(int(round(total * TARGET_DENSITY)), 1, maxi(1, total - 1))


func _sync_toggles() -> void:
	for i in _size_buttons.size():
		_size_buttons[i].button_pressed = (SIDES[i] == _side)


func _refresh() -> void:
	if _mine_label == null:
		return
	_mine_label.text = str(_mines)
	_minus.disabled = _mines <= 1
	_plus.disabled = _mines >= _max_mines()
	var total := _total()
	_hint.text = UiKit.t("%d × %d × %d · 共 %d 格 · 密度 %.1f%% · 推荐 %d 颗",
		"%d × %d × %d · %d cells · %.1f%% · suggest %d") % [
		_side, _side, _side, total, 100.0 * float(_mines) / float(total), _recommended(total)]


func _on_apply() -> void:
	close()
	applied.emit(_side, _mines)
