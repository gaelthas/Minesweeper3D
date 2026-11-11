class_name SettingsPage
extends Control

## 应用级设置页面：显示模式、分辨率、缝隙、音量、垂直同步、帧率显示、版本号。
## 和开局设置（SettingsPanel）分开——那个改的是盘面，这个改的是应用本身。
## 所有改动即时生效并落盘，没有「确定」按钮。

signal closed
## 鼠标映射改动：HUD 的提示行要跟着重写
signal mouse_changed

const GAP_MIN := 12
const GAP_MAX := 55

var _mode_buttons: Array[Button] = []
var _res_dropdown: OptionButton
var _res_options: Array[Vector2i] = []
var _vol_slider: HSlider
var _vol_label: Label
var _mute_button: Button
var _mouse_dropdowns: Array[OptionButton] = []
var _vsync_button: Button
var _fps_button: Button


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open() -> void:
	_sync()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


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
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(440, 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	col.add_child(UiKit.label(UiKit.t("选项", "OPTIONS"), 22, UiKit.INK))
	col.add_child(UiKit.label(
		UiKit.t("改动即时生效，自动保存", "changes apply and save immediately"),
		13, UiKit.INK_SOFT))

	col.add_child(_build_mode_row())
	col.add_child(_build_resolution_row())
	col.add_child(_build_volume_row())
	col.add_child(_build_mouse_row(0, UiKit.t("左键", "LEFT")))
	col.add_child(_build_mouse_row(1, UiKit.t("中键", "MIDDLE")))
	col.add_child(_build_mouse_row(2, UiKit.t("右键", "RIGHT")))
	col.add_child(_build_toggles_row())
	col.add_child(_build_footer())
	_sync()


func _build_mode_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("显示", "DISPLAY"))
	var group := ButtonGroup.new()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var labels := [
		UiKit.t("窗口", "WINDOW"),
		UiKit.t("全屏", "FULLSCREEN"),
	]
	for i in labels.size():
		var b := UiKit.toggle(labels[i], 14, 6)
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		b.pressed.connect(func() -> void: _on_mode(i))
		box.add_child(b)
		_mode_buttons.append(b)

	row.add_child(box)
	return row


func _build_resolution_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("分辨率", "SIZE"))

	_res_dropdown = _make_dropdown()
	_res_dropdown.item_selected.connect(_on_resolution_selected)
	row.add_child(_res_dropdown)

	return row


func _build_volume_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("音量", "VOLUME"))

	_vol_slider = _make_slider(0, 100)
	_vol_slider.value_changed.connect(_on_volume)
	row.add_child(_vol_slider)

	_vol_label = UiKit.label("70", 15, UiKit.INK)
	_vol_label.custom_minimum_size = Vector2(44, 0)
	_vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_vol_label)

	_mute_button = UiKit.toggle(UiKit.t("静音", "MUTE"), 13, 8)
	_mute_button.custom_minimum_size = Vector2(60, 30)
	_mute_button.toggled.connect(_on_mute)
	row.add_child(_mute_button)

	return row


## 鼠标三键的功能分配。选项顺序与 AppSettings.MouseAction 一致。
func _build_mouse_row(slot: int, title: String) -> HBoxContainer:
	var row := _row_label(title)
	var ob := _make_dropdown()
	var labels := [
		UiKit.t("无", "NONE"),
		UiKit.t("揭示", "REVEAL"),
		UiKit.t("插旗", "FLAG"),
		UiKit.t("和弦", "CHORD"),
		UiKit.t("平移", "PAN"),
	]
	for i in labels.size():
		ob.add_item(labels[i], i)
	ob.item_selected.connect(func(idx: int) -> void: _on_mouse_changed(slot, idx))
	row.add_child(ob)
	_mouse_dropdowns.append(ob)
	return row


func _build_toggles_row() -> HBoxContainer:
	var row := _row_label(UiKit.t("其他", "MISC"))

	_vsync_button = UiKit.toggle(UiKit.t("垂直同步", "VSYNC"), 13, 8)
	_vsync_button.custom_minimum_size = Vector2(0, 30)
	_vsync_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vsync_button.toggled.connect(_on_vsync)
	row.add_child(_vsync_button)

	_fps_button = UiKit.toggle(UiKit.t("显示帧率", "FPS"), 13, 8)
	_fps_button.custom_minimum_size = Vector2(0, 30)
	_fps_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_button.toggled.connect(_on_fps)
	row.add_child(_fps_button)

	return row


func _build_footer() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	var l := UiKit.label("MineCube 3D  v%s" % version, 12, UiKit.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)

	var close_btn := UiKit.button(UiKit.t("关闭", "CLOSE"), 14)
	close_btn.pressed.connect(close)
	row.add_child(close_btn)

	return row


## 下拉列表。分辨率由屏幕可用尺寸决定，每一项自带宽高比，没有单独的比例开关。
func _make_dropdown() -> OptionButton:
	var ob := OptionButton.new()
	for slot in ["normal", "hover", "pressed", "focus"]:
		ob.add_theme_stylebox_override(slot, UiKit.field_style())
	ob.add_theme_font_override("font", UiKit.font())
	ob.add_theme_font_size_override("font_size", 15)
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ob.add_theme_color_override(slot, UiKit.INK)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(0, 34)
	ob.focus_mode = Control.FOCUS_NONE

	var pop := ob.get_popup()
	pop.add_theme_stylebox_override("panel", UiKit.panel_style())
	pop.add_theme_stylebox_override("hover", UiKit.slider_fill())
	pop.add_theme_color_override("font_color", UiKit.INK)
	pop.add_theme_color_override("font_hover_color", UiKit.PAPER)
	pop.add_theme_font_override("font", UiKit.font())
	pop.add_theme_font_size_override("font_size", 15)
	pop.add_theme_constant_override("v_separation", 8)
	return ob


static func _ratio_text(size: Vector2i) -> String:
	var a := size.x
	var b := size.y
	while b != 0:
		var t := b
		b = a % b
		a = t
	if a == 0:
		return ""
	return "%d:%d" % [size.x / a, size.y / a]


func _make_slider(lo: int, hi: int) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = maxi(hi, lo + 1)
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


func _row_label(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 15, UiKit.INK)
	l.custom_minimum_size = Vector2(60, 0)
	row.add_child(l)
	return row


func _sync() -> void:
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = (i == int(AppSettings.mode))

	_res_options = AppSettings.available_resolutions()
	_res_dropdown.clear()
	var selected := 0
	for i in _res_options.size():
		var size := _res_options[i]
		_res_dropdown.add_item("%s · %s" % [AppSettings.label_of(size), _ratio_text(size)], i)
		if size == AppSettings.window_size:
			selected = i
	_res_dropdown.select(selected)

	_vol_slider.set_value_no_signal(float(AppSettings.volume))
	_vol_label.text = str(AppSettings.volume)
	_mute_button.set_pressed_no_signal(AppSettings.muted)

	for i in _mouse_dropdowns.size():
		_mouse_dropdowns[i].select(clampi(int(AppSettings.mouse_map[i]), 0, 4))

	_vsync_button.set_pressed_no_signal(AppSettings.vsync)
	_fps_button.set_pressed_no_signal(AppSettings.show_fps)


func _on_mode(index: int) -> void:
	AppSettings.mode = index as AppSettings.Mode
	AppSettings.apply()
	AppSettings.save()


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _res_options.size():
		return
	AppSettings.window_size = _res_options[index]
	AppSettings.apply()
	AppSettings.save()


func _on_volume(value: float) -> void:
	AppSettings.volume = int(value)
	_vol_label.text = str(AppSettings.volume)
	AppSettings.apply()
	AppSettings.save()


func _on_mute(pressed: bool) -> void:
	AppSettings.muted = pressed
	AppSettings.apply()
	AppSettings.save()


func _on_mouse_changed(slot: int, index: int) -> void:
	AppSettings.mouse_map[slot] = clampi(index, 0, 4)
	AppSettings.save()
	mouse_changed.emit()


func _on_vsync(pressed: bool) -> void:
	AppSettings.vsync = pressed
	AppSettings.apply()
	AppSettings.save()


func _on_fps(pressed: bool) -> void:
	AppSettings.show_fps = pressed
	AppSettings.save()
