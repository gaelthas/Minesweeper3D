class_name AppSettings
extends RefCounted

## 应用级设置：显示模式、分辨率、音量、垂直同步、帧率显示。
## 存到 user://settings.cfg，启动时读回来并立即应用。

const PATH := "user://settings.cfg"

enum Mode { WINDOWED, FULLSCREEN }

const DEFAULT_SIZE := Vector2i(1280, 720)

## 候选分辨率。实际可选的列表还要按当前屏幕过滤——见 available_resolutions()。
## 横向排布按面积从小到大，比例各不相同（16:9 / 16:10 / 4:3），由用户挑。
const CANDIDATES := [
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1280, 960),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1440, 1080),
	Vector2i(1600, 900),
	Vector2i(1600, 1200),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(1920, 1440),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(3840, 2160),
]

static var mode: Mode = Mode.WINDOWED
static var window_size: Vector2i = DEFAULT_SIZE
static var volume: int = 70
static var muted: bool = false
static var vsync: bool = true
static var show_fps: bool = false
## 已揭示方块相对未揭示格的收缩量：30 表示缩到 0.70。
## 界面上不暴露它——想看清内层靠拉大间距，而不是把方块缩小。
const PEEK_GAP := 30

## 未揭示方块的标称边长。间距只挪位置，不改尺寸。
const NOMINAL_SIZE := 0.88

## 三个鼠标键各自的功能，顺序 左 / 中 / 右
enum MouseAction { NONE, REVEAL, FLAG, CHORD, PAN }
static var mouse_map: Array[int] = [MouseAction.REVEAL, MouseAction.PAN, MouseAction.FLAG]

## 方块中心距的倍率：100% 是原始格距 1.0，最大 200%。
## 只动位置，不动方块尺寸。
static var spacing: int = 100


static func pitch() -> float:
	return float(spacing) / 100.0


## 已揭示方块相对格距的边长（未乘间距系数）
static func revealed_ratio() -> float:
	return minf(1.0 - float(PEEK_GAP) / 100.0, NOMINAL_SIZE)


static func hidden_size() -> float:
	return NOMINAL_SIZE


static func revealed_size() -> float:
	return revealed_ratio()


static func action_for(button: int) -> int:
	match button:
		MOUSE_BUTTON_LEFT:
			return mouse_map[0]
		MOUSE_BUTTON_MIDDLE:
			return mouse_map[1]
		MOUSE_BUTTON_RIGHT:
			return mouse_map[2]
	return MouseAction.NONE


static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mode = clampi(int(cfg.get_value("display", "mode", int(mode))), 0, 1) as Mode
	window_size = Vector2i(
		int(cfg.get_value("display", "size_w", window_size.x)),
		int(cfg.get_value("display", "size_h", window_size.y)))
	volume = clampi(int(cfg.get_value("audio", "volume", volume)), 0, 100)
	muted = bool(cfg.get_value("audio", "muted", muted))
	mouse_map[0] = clampi(int(cfg.get_value("input", "left", mouse_map[0])), 0, 4)
	mouse_map[1] = clampi(int(cfg.get_value("input", "middle", mouse_map[1])), 0, 4)
	mouse_map[2] = clampi(int(cfg.get_value("input", "right", mouse_map[2])), 0, 4)
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	show_fps = bool(cfg.get_value("display", "show_fps", show_fps))
	spacing = clampi(int(cfg.get_value("view", "spacing", spacing)), 100, 200)

	# 换了显示器之后存档里的尺寸可能不再可用，退回默认值
	var avail := available_resolutions()
	if avail.size() > 0 and not avail.has(window_size):
		window_size = DEFAULT_SIZE if avail.has(DEFAULT_SIZE) else avail[0]


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "mode", int(mode))
	cfg.set_value("display", "size_w", window_size.x)
	cfg.set_value("display", "size_h", window_size.y)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "show_fps", show_fps)
	cfg.set_value("view", "spacing", spacing)
	cfg.set_value("input", "left", mouse_map[0])
	cfg.set_value("input", "middle", mouse_map[1])
	cfg.set_value("input", "right", mouse_map[2])
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(PATH)


static func apply() -> void:
	# 先摆窗口模式，再定尺寸：全屏下改尺寸没有意义
	if mode == Mode.FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
		_center_window(window_size)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, muted)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(volume) / 100.0, 0.0001)))


static func label_of(size: Vector2i) -> String:
	return "%d × %d" % [size.x, size.y]


## 当前屏幕装得下的分辨率，按面积从小到大。屏幕尺寸拿不到时退回全部候选。
static func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()).size
	var out: Array[Vector2i] = []
	for size in CANDIDATES:
		if screen.x <= 0 or screen.y <= 0 or (size.x <= screen.x and size.y <= screen.y):
			out.append(size)
	if out.is_empty():
		out.append(DEFAULT_SIZE)
	return out


static func _center_window(size: Vector2i) -> void:
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
