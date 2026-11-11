class_name Hud
extends CanvasLayer

## 顶栏：状态 / 正计时 / 重开 · 设置 · 关闭。

signal restart_pressed
signal settings_pressed
signal options_pressed
signal quit_pressed
## 右下角间距滑块
signal spacing_changed(value: float)

var _stats: Label
var _status: Label
var _hint: Label
var _level: Label
var _timer: Label
var _fps: Label
var _spacing: HSlider
var _spacing_label: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)


	# 间距滑块单独贴右下角：VBox 的 alignment=END 会把内容顶到底部
	var bottom := MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.add_theme_constant_override("margin_left", 28)
	bottom.add_theme_constant_override("margin_right", 28)
	bottom.add_theme_constant_override("margin_bottom", 18)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	var bottom_col := VBoxContainer.new()
	bottom_col.alignment = BoxContainer.ALIGNMENT_END
	bottom_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bottom_col)
	bottom_col.add_child(_build_spacing_row())

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)

	_stats = UiKit.label("", 20, UiKit.INK)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_stats)

	_fps = UiKit.label("", 13, UiKit.INK_SOFT)
	_fps.visible = false
	top.add_child(_fps)

	_timer = UiKit.label("00:00", 24, UiKit.INK)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer.custom_minimum_size = Vector2(88, 0)
	top.add_child(_timer)

	var restart := UiKit.button(t("重开", "RESTART"))
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	top.add_child(restart)

	var settings := UiKit.button(t("开局", "BOARD"))
	settings.pressed.connect(func() -> void: settings_pressed.emit())
	top.add_child(settings)

	var options := UiKit.button(t("选项", "OPTIONS"))
	options.pressed.connect(func() -> void: options_pressed.emit())
	top.add_child(options)

	var quit_btn := UiKit.button(t("关闭", "QUIT"))
	quit_btn.pressed.connect(func() -> void: quit_pressed.emit())
	top.add_child(quit_btn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	_status = UiKit.label("", 17, UiKit.INK_SOFT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)

	_level = UiKit.label("", 15, UiKit.INK_SOFT)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_level)


	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	_hint = UiKit.label(
		t("左键揭示 · 右键插旗 · 中键拖拽平移 · 左右键同按和弦 · 拖拽旋转 · 滚轮缩放 · R 重开 · M 静音",
			"LMB reveal · RMB flag · LMB+RMB chord · drag orbit · wheel zoom · R restart · M mute"),
		14, UiKit.INK_SOFT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)

	set_status(t("点击任意方块开始", "click any cube to begin"))


func t(zh: String, en: String) -> String:
	return UiKit.t(zh, en)


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func set_level(text: String) -> void:
	if _level:
		_level.text = text


## 传负数即隐藏
func set_fps(value: int) -> void:
	if _fps == null:
		return
	if value < 0:
		_fps.visible = false
		return
	_fps.visible = true
	_fps.text = "%d FPS" % value


## 右下角的间距滑块：同时缩放所有方块，改变方块之间的距离
func _build_spacing_row() -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.alignment = BoxContainer.ALIGNMENT_END
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var l := UiKit.label(t("间距", "SPACING"), 13, UiKit.INK_SOFT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(l)

	_spacing = HSlider.new()
	_spacing.min_value = 100
	_spacing.max_value = 200
	_spacing.step = 1
	_spacing.value = 100
	_spacing.custom_minimum_size = Vector2(160, 24)
	_spacing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacing.focus_mode = Control.FOCUS_NONE

	var grabber := UiKit.slider_grabber()
	for slot in ["grabber", "grabber_highlight", "grabber_disabled"]:
		_spacing.add_theme_icon_override(slot, grabber)
	_spacing.add_theme_stylebox_override("slider", UiKit.slider_track())
	_spacing.add_theme_stylebox_override("grabber_area", UiKit.slider_fill())
	_spacing.add_theme_stylebox_override("grabber_area_highlight", UiKit.slider_fill())
	_spacing.value_changed.connect(func(v: float) -> void: spacing_changed.emit(v))
	line.add_child(_spacing)

	_spacing_label = UiKit.label("100%", 13, UiKit.INK_SOFT)
	_spacing_label.custom_minimum_size = Vector2(44, 0)
	_spacing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_spacing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_spacing_label)

	return line


func set_spacing(value: int) -> void:
	if _spacing == null:
		return
	_spacing.set_value_no_signal(float(value))
	_spacing_label.text = "%d%%" % value


func set_time(seconds: float) -> void:
	if _timer == null:
		return
	var total := int(floor(maxf(seconds, 0.0)))
	_timer.text = "%02d:%02d" % [total / 60, total % 60]


func update_stats(mine_total: int, flags: int, opened: int, need: int) -> void:
	if _stats == null:
		return
	_stats.text = "%s %d   %s %d   %s %d/%d" % [
		t("雷", "MINES"), mine_total,
		t("旗", "FLAGS"), flags,
		t("已开", "OPEN"), opened, need,
	]
