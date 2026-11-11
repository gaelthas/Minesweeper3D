class_name ResultPanel
extends Control

## 一局结束时的弹窗。清空和踩雷共用，标题与配色不同。
## 显示用时和盘面配置，可以立刻再来一局。

signal restart_pressed

const COL_WIN := Color(0.129, 0.157, 0.196)
const COL_LOSE := Color(0.769, 0.176, 0.196)

var _title: Label
var _time: Label
var _detail: Label


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open(seconds: float, side: int, mines: int, won: bool) -> void:
	_title.text = UiKit.t("清空", "CLEARED") if won else UiKit.t("踩雷了", "BOOM")
	_title.add_theme_color_override("font_color", COL_WIN if won else COL_LOSE)
	_time.text = format_time(seconds)
	_time.add_theme_color_override("font_color", COL_WIN if won else COL_LOSE)
	_detail.text = UiKit.t("%d × %d × %d · %d 颗雷", "%d × %d × %d · %d mines") % [
		side, side, side, mines]
	visible = true


func close() -> void:
	visible = false


static func format_time(seconds: float) -> String:
	var total := int(floor(maxf(seconds, 0.0)))
	return "%02d:%02d" % [total / 60, total % 60]


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
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(296, 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	_title = UiKit.label(UiKit.t("清空", "CLEARED"), 24, UiKit.INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_time = UiKit.label("00:00", 56, UiKit.INK)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_time)

	_detail = UiKit.label("", 14, UiKit.INK_SOFT)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_detail)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(actions)

	var again := UiKit.button(UiKit.t("再来一局", "PLAY AGAIN"), 15)
	again.pressed.connect(_on_restart)
	actions.add_child(again)

	var close_btn := UiKit.button(UiKit.t("关闭", "CLOSE"), 15)
	close_btn.pressed.connect(close)
	actions.add_child(close_btn)


func _on_restart() -> void:
	close()
	restart_pressed.emit()
