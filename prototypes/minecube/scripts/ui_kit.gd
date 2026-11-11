class_name UiKit
extends RefCounted

## 共用的 UI 样式与字体。中文字形依赖系统字体，取不到就退回英文文案。

const INK := Color(0.145, 0.176, 0.227)
const INK_SOFT := Color(0.361, 0.400, 0.463)
const LINE := Color(0.792, 0.820, 0.867)
const PAPER := Color(0.988, 0.992, 1.0)

const FONT_PATHS := [
	"/System/Library/Fonts/PingFang.ttc",
	"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
	"/System/Library/Fonts/Hiragino Sans GB.ttc",
	"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
	"C:/Windows/Fonts/msyh.ttc",
]

static var _font: Font = null
static var _cjk := false
static var _done := false


static func font() -> Font:
	_ensure()
	return _font


static func has_cjk() -> bool:
	_ensure()
	return _cjk


static func t(zh: String, en: String) -> String:
	return zh if has_cjk() else en


static func _ensure() -> void:
	if _done:
		return
	_done = true
	var probe := "雷".unicode_at(0)
	for p in FONT_PATHS:
		if not FileAccess.file_exists(p):
			continue
		var f := FontFile.new()
		if f.load_dynamic_font(p) != OK:
			continue
		if f.has_char(probe):
			_font = f
			_cjk = true
			return
	_font = ThemeDB.fallback_font


static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, font_size: int = 14, h_padding: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", INK)

	var normal := StyleBoxFlat.new()
	normal.bg_color = PAPER
	normal.border_color = LINE
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = h_padding
	normal.content_margin_right = h_padding
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.929, 0.949, 0.988)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.859, 0.890, 0.949)

	var off := normal.duplicate() as StyleBoxFlat
	off.bg_color = Color(0.949, 0.957, 0.973)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_stylebox_override("focus", normal.duplicate())
	b.add_theme_color_override("font_disabled_color", Color(0.639, 0.678, 0.741))
	return b


## 分段选择用：选中态用蓝底蓝边，普通按钮没有这个状态
static func toggle(text: String, font_size: int = 15, h_padding: int = 8) -> Button:
	var b := button(text, font_size, h_padding)
	b.toggle_mode = true
	var on := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
	on.bg_color = Color(0.851, 0.894, 0.984)
	on.border_color = Color(0.478, 0.600, 0.855)
	on.set_border_width_all(2)
	var accent := Color(0.129, 0.267, 0.518)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", accent)
	return b


static func field_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.961, 0.973, 0.988)
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	sb.shadow_color = Color(0.10, 0.12, 0.16, 0.18)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	return sb
