class_name CellView
extends Node3D

## 单个方块的视图。
##
## 碰撞层分两类：
##   LAYER_SOLID —— 未揭示 / 已标记，左键揭示的目标
##   LAYER_OPEN  —— 已揭示的数字格，和弦的目标
## 揭示与和弦的射线都覆盖这两层：点到数字方块就被吃掉，不会穿过去翻开后面的格子。
## 要挖内层可以从方块间的缝隙瞄，也可以调大「剥离距离」：拉近镜头后外层移出视野。

## 已揭示/已标记方块的边长由选项页的「缝隙」滑块决定，见 AppSettings.revealed_size()
const LABEL_GAP := 0.018
const FLAG_QUAD := 0.34

## 碰撞盒跟着缩放一起变。缩小的方块外面如果还留着一圈原尺寸的碰撞壳，
## 本该穿过去的点击就会被吃掉——标记后内层方块看得见却点不到，就是这个原因。
var _box: BoxShape3D

const LAYER_SOLID := 1
const LAYER_OPEN := 2

const COL_HIDDEN := Color(0.878, 0.898, 0.933)
const COL_FLAG := Color(0.878, 0.804, 0.643)
const COL_QUESTION := Color(0.706, 0.741, 0.804)
const COL_OPEN := Color(0.212, 0.251, 0.314)
const COL_MINE := Color(0.643, 0.157, 0.196)
const COL_HIT := Color(1.0, 0.318, 0.318)
const COL_WRONG := Color(0.561, 0.188, 0.220)

enum Symbol { NONE, NUMBER, QUESTION, FLAG }

static var _cube_mesh: Mesh
static var _cube_shader_res: Shader
static var _cube_loaded := false
static var _flag_quad: QuadMesh
static var _flag_mat: StandardMaterial3D
static var _wrong_mat: StandardMaterial3D
static var _glow_mat: StandardMaterial3D
static var _clear_glow_mat: StandardMaterial3D

var index: int
var body: StaticBody3D
var mesh: MeshInstance3D
var mat: ShaderMaterial
var labels: Array[Label3D] = []
## 截面剥离：剥离层的方块沿视线反方向滑出视野，不参与拾取
var peeled := false
var base_position := Vector3.ZERO
var peel_offset := Vector3.ZERO
var peel_t := 0.0
var wrong_flag := false
var _last_state := -1
var _last_face_mask := 63
var base_visible := true
var mine_base_visible := false
var base_collision_layer: int = LAYER_SOLID

var _faces: Array[Vector3] = []
var _face_rots: Array[Vector3] = []
var _flags: Array[MeshInstance3D] = []
var _mask := 0
var _symbol := Symbol.NONE
var _symbol_color := Color.WHITE
var _face_colors: Array[Color] = []

var _mine: Node3D
var _mine_loaded := false


func _init(p_index: int) -> void:
	index = p_index

	_faces = [
		Vector3(0, 0, 1), Vector3(0, 0, -1),
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
	]
	_face_rots = [
		Vector3(0, 0, 0), Vector3(0, PI, 0),
		Vector3(0, PI * 0.5, 0), Vector3(0, -PI * 0.5, 0),
		Vector3(-PI * 0.5, 0, 0), Vector3(PI * 0.5, 0, 0),
	]

	body = StaticBody3D.new()
	body.name = "Body"
	body.set_meta("cell_index", p_index)
	add_child(body)

	var shape := CollisionShape3D.new()
	_box = BoxShape3D.new()
	_box.size = Vector3.ONE * AppSettings.hidden_size()
	shape.shape = _box
	body.add_child(shape)

	mat = ShaderMaterial.new()
	mat.shader = _cube_shader()
	mat.set_shader_parameter("tint", COL_HIDDEN)

	mesh = MeshInstance3D.new()
	mesh.mesh = _get_cube_mesh()
	mesh.material_override = mat
	body.add_child(mesh)

	for k in _faces.size():
		var l := Label3D.new()
		l.pixel_size = 0.005
		l.font_size = 36
		l.outline_size = 11
		l.outline_modulate = Color(0.05, 0.06, 0.08, 0.85)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.no_depth_test = false
		l.double_sided = false
		l.visible = false
		l.text = ""
		add_child(l)
		labels.append(l)

	apply(BoardLogic.HIDDEN, 0, 0)


func set_base_position(p: Vector3) -> void:
	base_position = p
	if not peeled:
		position = p


## 被剥离的格子关掉碰撞，位置交给 animate_peel 平滑过渡
func set_peeled(value: bool, offset: Vector3) -> void:
	if value != peeled:
		peeled = value
		body.collision_layer = 0 if peeled else base_collision_layer
	peel_offset = offset


func animate_peel(delta: float) -> void:
	if peeled:
		# 起飞：二次缓入，从静止逐渐加速，冲出视野
		peel_t = minf(1.0, peel_t + delta / 0.25)
		position = base_position + peel_offset * (peel_t * peel_t)
	else:
		# 回位：保留原来的指数缓出减速
		peel_t = 0.0
		position = position.lerp(base_position, 1.0 - exp(-9.0 * delta))


func has_visible_content() -> bool:
	return base_visible or mine_base_visible


func _set_collision(layer: int) -> void:
	base_collision_layer = layer
	body.collision_layer = 0 if peeled else layer


func _set_material_color(color: Color) -> void:
	mat.set_shader_parameter("tint", color)


## face_mask 的 6 个位依次对应 +Z -Z +X -X +Y -Y，
## 表示这一面朝盘面外、或朝向已揭示格（即真的能被看到）。
func apply(state: int, count: int, face_mask: int = 63, face_counts: Array = []) -> void:
	_last_state = state
	_last_face_mask = face_mask
	match state:
		BoardLogic.FLAGGED:
			_set_marked(COL_WRONG if wrong_flag else COL_FLAG, Symbol.FLAG, face_mask)
		BoardLogic.QUESTION:
			_set_marked(COL_QUESTION, Symbol.QUESTION, face_mask)
		BoardLogic.REVEALED:
			_set_revealed(count, face_mask, face_counts)
		_:
			_set_solid(COL_HIDDEN)


func mark_wrong_flag() -> void:
	wrong_flag = true
	if _last_state == BoardLogic.FLAGGED:
		_set_marked(COL_WRONG, Symbol.FLAG, _last_face_mask)


func set_mine(is_hit: bool) -> void:
	_set_size(AppSettings.hidden_size())
	base_visible = false
	mine_base_visible = false
	mesh.visible = false
	_hide_symbols()
	_mask = 0
	_symbol = Symbol.NONE
	_set_collision(0)

	_ensure_mine()
	if _mine == null:
		# 模型缺失时退回一个色块，至少还能看出哪格是雷
		base_visible = true
		mesh.visible = true
		_set_material_color(COL_HIT if is_hit else COL_MINE)
		return

	mine_base_visible = true
	_mine.visible = true
	_mine.scale = Vector3.ONE * (1.18 if is_hit else 1.0)
	_apply_glow(is_hit)


## 每帧调用：已经斜到看不清的面淡出。
## 不做这件事的话，掠射角上的「1」会被压成「7」的形状，读成别的数。
func update_symbol_facing(cam_pos: Vector3) -> void:
	if _symbol == Symbol.NONE or _mask == 0:
		return
	var half := AppSettings.revealed_size() * 0.5
	for k in _faces.size():
		if (_mask & (1 << k)) == 0:
			continue
		var n: Vector3 = _faces[k]
		var to_cam := (cam_pos - (global_position + n * half)).normalized()
		# 掠射角仍留一点可见度：从 dot=0.06 起淡入，0.24 起完全不透明
		var alpha := clampf((n.dot(to_cam) - 0.06) / 0.18, 0.0, 1.0)
		if _symbol == Symbol.FLAG:
			if k < _flags.size():
				_flags[k].visible = alpha > 0.01
				_flags[k].transparency = 1.0 - alpha
		else:
			var l := labels[k]
			if l.text == "":
				l.visible = false
				continue
			l.visible = alpha > 0.01
			var c: Color = _face_colors[k] if _face_colors.size() == 6 else _symbol_color
			l.modulate = Color(c.r, c.g, c.b, alpha)


func _set_size(s: float) -> void:
	mesh.scale = Vector3.ONE * s
	if _box != null:
		_box.size = Vector3(s, s, s)


func _set_solid(color: Color) -> void:
	_set_size(AppSettings.hidden_size())
	base_visible = true
	mine_base_visible = false
	mesh.visible = true
	_set_material_color(color)
	_set_collision(LAYER_SOLID)
	_mask = 0
	_symbol = Symbol.NONE
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)
	_hide_symbols()


func _set_marked(color: Color, kind: Symbol, face_mask: int) -> void:
	_set_size(AppSettings.revealed_size())
	base_visible = true
	mine_base_visible = false
	mesh.visible = true
	_set_material_color(color)
	_set_collision(LAYER_SOLID)
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)

	_mask = 63 if face_mask == 0 else face_mask
	_symbol = kind
	_hide_symbols()

	if kind == Symbol.FLAG:
		_ensure_flag_quads()
		for k in _faces.size():
			if (_mask & (1 << k)) != 0:
				_flags[k].material_override = _wrong_material() if wrong_flag else _flag_material()
				_flags[k].visible = true
				_flags[k].transparency = 0.0
	else:
		_symbol_color = Color(0.165, 0.200, 0.259)
		var half := AppSettings.revealed_size() * 0.5 + LABEL_GAP
		for k in _faces.size():
			var l := labels[k]
			l.position = _faces[k] * half
			l.rotation = _face_rots[k]
			var on := (_mask & (1 << k)) != 0
			l.text = "?" if on else ""
			l.modulate = _symbol_color
			l.visible = on


func _set_revealed(count: int, face_mask: int, face_counts: Array = []) -> void:
	_set_size(AppSettings.revealed_size())
	mine_base_visible = false
	_set_material_color(COL_OPEN)
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)

	_mask = 63 if face_mask == 0 else face_mask
	_symbol_color = _number_color(count)

	# 六个面全是 0 的格子没有任何信息可显示——体对角方向的雷不进任何一面。
	# 这类格子和 0 格一样要消失，不能留一颗占位的空方块。
	var has_symbol := count > 0
	if face_counts.size() == 6:
		has_symbol = false
		for v in face_counts:
			if v > 0:
				has_symbol = true
				break

	_symbol = Symbol.NUMBER if has_symbol else Symbol.NONE
	base_visible = has_symbol
	mesh.visible = has_symbol
	_hide_symbols()

	# 数字格只在和弦射线里可命中；无符号的格子彻底让路
	_set_collision(LAYER_OPEN if has_symbol else 0)

	if _face_colors.size() != 6:
		_face_colors.resize(6)

	if has_symbol:
		var half := AppSettings.revealed_size() * 0.5 + LABEL_GAP
		for k in _faces.size():
			var value: int = face_counts[k] if face_counts.size() == 6 else count
			var l := labels[k]
			l.position = _faces[k] * half
			l.rotation = _face_rots[k]
			var on := (_mask & (1 << k)) != 0
			l.text = str(value) if (on and value > 0) else ""
			_face_colors[k] = _number_color(value)
			l.modulate = _face_colors[k]
			l.visible = on


func _hide_symbols() -> void:
	for l in labels:
		l.visible = false
		l.text = ""
	for f in _flags:
		f.visible = false


func _ensure_flag_quads() -> void:
	if not _flags.is_empty():
		return
	var half := AppSettings.revealed_size() * 0.5 + LABEL_GAP
	for k in _faces.size():
		var q := MeshInstance3D.new()
		q.mesh = _get_flag_quad()
		q.material_override = _flag_material()
		q.position = _faces[k] * half
		q.rotation = _face_rots[k]
		q.visible = false
		add_child(q)
		_flags.append(q)


func _ensure_mine() -> void:
	if _mine_loaded:
		return
	_mine_loaded = true
	var packed := load("res://assets/mine.glb") as PackedScene
	if packed == null:
		push_warning("mine.glb 未就绪，退回色块表示")
		return
	_mine = packed.instantiate()
	_mine.visible = false
	for m in _mine_meshes(_mine):
		var src: Material = null
		if m.mesh != null and m.mesh.get_surface_count() > 0:
			src = m.mesh.surface_get_material(0)
		var replacement := _unshaded_material(src)
		if replacement == null:
			replacement = StandardMaterial3D.new()
			replacement.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			replacement.albedo_color = COL_MINE
		m.material_override = replacement
	add_child(_mine)


static func _unshaded_material(src: Material) -> Material:
	if src == null:
		return null
	if src is StandardMaterial3D:
		var copy := src.duplicate() as StandardMaterial3D
		copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		copy.rim_enabled = false
		return copy
	return src


func _apply_glow(on: bool) -> void:
	if _mine == null:
		return
	var material := _glow_material() if on else _clear_glow_material()
	for m in _mine_meshes(_mine):
		m.material_overlay = material


func _mine_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_mine_meshes(c))
	return out


func _number_color(n: int) -> Color:
	match n:
		1:
			return Color(0.473, 0.769, 1.0)
		2:
			return Color(0.521, 0.898, 0.612)
		3:
			return Color(1.0, 0.827, 0.400)
		4:
			return Color(1.0, 0.635, 0.396)
		_:
			return Color(1.0, 0.494, 0.588)


# --- 共享资源 -------------------------------------------------------------

## 无灯光的固定面着色：模拟 Web 版的主光/补光，保留立体感但不产生真实阴影
static func _cube_shader() -> Shader:
	if _cube_shader_res == null:
		var s := Shader.new()
		s.code = """
shader_type spatial;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 v_normal;

void vertex() {
	v_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(v_normal);
	float key = max(dot(n, normalize(vec3(-0.45, 0.82, 0.55))), 0.0);
	float fill = max(dot(n, normalize(vec3(0.65, -0.25, -0.72))), 0.0);
	float shade = 0.62 + 0.38 * key + 0.12 * fill;
	ALBEDO = tint.rgb * shade;
	ALPHA = tint.a;
}
"""
		_cube_shader_res = s
	return _cube_shader_res


static func _get_cube_mesh() -> Mesh:
	if not _cube_loaded:
		_cube_loaded = true
		_cube_mesh = _mesh_from_glb("res://assets/cube_rounded.glb")
		if _cube_mesh == null:
			var fallback := BoxMesh.new()
			fallback.size = Vector3.ONE
			_cube_mesh = fallback
	return _cube_mesh


static func _mesh_from_glb(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var stack: Array[Node] = [root]
	var found: Mesh = null
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found = (n as MeshInstance3D).mesh
			break
		stack.append_array(n.get_children())
	root.free()
	return found


static func _get_flag_quad() -> QuadMesh:
	if _flag_quad == null:
		_flag_quad = QuadMesh.new()
		_flag_quad.size = Vector2(FLAG_QUAD, FLAG_QUAD)
	return _flag_quad


## 系统字体里没有旗帜字形，旗面只能画成纹理。
## 缩到 0.34 单位时细节会糊，所以杆要够粗、旗面要小，两者都用近黑的深色。
static func _flag_texture() -> ImageTexture:
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var ink := Color(0.125, 0.102, 0.078)

	# 旗杆：14/96 宽，贯穿大半个高度
	for y in range(10, 88):
		for x in range(26, 40):
			img.set_pixel(x, y, ink)

	# 旗面：从杆上端向右的三角形，高度只有杆的三分之一
	for y in range(12, 46):
		var t: float = 1.0 - absf(float(y) - 29.0) / 17.0
		var x_end: int = 40 + int(t * 38.0)
		for x in range(40, x_end):
			img.set_pixel(x, y, ink)

	return ImageTexture.create_from_image(img)


static func _flag_material() -> StandardMaterial3D:
	if _flag_mat == null:
		_flag_mat = StandardMaterial3D.new()
		_flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flag_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flag_mat.albedo_texture = _flag_texture()
		_flag_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _flag_mat


## 插错的旗：红色叉，结算时替换旗面
static func _wrong_texture() -> ImageTexture:
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.90, 0.28, 0.30)
	for y in size:
		for x in size:
			if absi(x - y) < 7 or absi(x + y - size + 1) < 7:
				img.set_pixel(x, y, ink)
	return ImageTexture.create_from_image(img)


static func _wrong_material() -> StandardMaterial3D:
	if _wrong_mat == null:
		_wrong_mat = StandardMaterial3D.new()
		_wrong_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wrong_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wrong_mat.albedo_texture = _wrong_texture()
		_wrong_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_wrong_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _wrong_mat


static func _clear_glow_material() -> StandardMaterial3D:
	if _clear_glow_mat == null:
		_clear_glow_mat = StandardMaterial3D.new()
		_clear_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_clear_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_clear_glow_mat.albedo_color = Color(1, 1, 1, 0)
	return _clear_glow_mat


static func _glow_material() -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.albedo_color = Color(1.0, 0.298, 0.161, 0.48)
	return _glow_mat
