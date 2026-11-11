class_name CellView
extends Node3D

## 单个方块的视图。
##
## 碰撞层分两类，这是三维可达性的支点：
##   LAYER_SOLID —— 未揭示 / 已标记，左键揭示命中的目标
##   LAYER_OPEN  —— 已揭示的数字格，只给和弦用
## 数字格不在揭示射线的掩码里，射线会穿过去命中内层，
## 否则 3×3×3 的体心被 26 个方块包住就永远点不到了。

const BASE_SIZE := 0.88
const SMALL_SIZE := 0.70
const LABEL_GAP := 0.018
const FLAG_QUAD := 0.34

const LAYER_SOLID := 1
const LAYER_OPEN := 2

const COL_HIDDEN := Color(0.878, 0.898, 0.933)
const COL_FLAG := Color(0.878, 0.804, 0.643)
const COL_QUESTION := Color(0.706, 0.741, 0.804)
const COL_OPEN := Color(0.212, 0.251, 0.314)
const COL_MINE := Color(0.643, 0.157, 0.196)
const COL_HIT := Color(1.0, 0.318, 0.318)

enum Symbol { NONE, NUMBER, QUESTION, FLAG }

static var _cube_mesh: Mesh
static var _cube_loaded := false
static var _flag_quad: QuadMesh
static var _flag_mat: StandardMaterial3D
static var _glow_mat: StandardMaterial3D

var index: int
var body: StaticBody3D
var mesh: MeshInstance3D
var mat: StandardMaterial3D
var labels: Array[Label3D] = []

var _faces: Array[Vector3] = []
var _face_rots: Array[Vector3] = []
var _flags: Array[MeshInstance3D] = []
var _mask := 0
var _symbol := Symbol.NONE
var _symbol_color := Color.WHITE

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
	var bs := BoxShape3D.new()
	bs.size = Vector3(BASE_SIZE, BASE_SIZE, BASE_SIZE)
	shape.shape = bs
	body.add_child(shape)

	mat = StandardMaterial3D.new()
	mat.albedo_color = COL_HIDDEN
	mat.roughness = 0.50
	mat.metallic = 0.0
	mat.rim_enabled = true
	mat.rim = 0.10

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


## face_mask 的 6 个位依次对应 +Z -Z +X -X +Y -Y，
## 表示这一面朝盘面外、或朝向已揭示格（即真的能被看到）。
func apply(state: int, count: int, face_mask: int = 63) -> void:
	match state:
		BoardLogic.FLAGGED:
			_set_marked(COL_FLAG, Symbol.FLAG, face_mask)
		BoardLogic.QUESTION:
			_set_marked(COL_QUESTION, Symbol.QUESTION, face_mask)
		BoardLogic.REVEALED:
			_set_revealed(count, face_mask)
		_:
			_set_solid(COL_HIDDEN)


func set_mine(is_hit: bool) -> void:
	_set_size(BASE_SIZE)
	mesh.visible = false
	_hide_symbols()
	_mask = 0
	_symbol = Symbol.NONE
	body.collision_layer = 0

	_ensure_mine()
	if _mine == null:
		# 模型缺失时退回一个色块，至少还能看出哪格是雷
		mesh.visible = true
		mat.albedo_color = COL_HIT if is_hit else COL_MINE
		mat.rim_enabled = true
		mat.emission_enabled = is_hit
		mat.emission = COL_HIT
		return

	_mine.visible = true
	_mine.scale = Vector3.ONE * (1.18 if is_hit else 1.0)
	_apply_glow(is_hit)


## 每帧调用：已经斜到看不清的面淡出。
## 不做这件事的话，掠射角上的「1」会被压成「7」的形状，读成别的数。
func update_symbol_facing(cam_pos: Vector3) -> void:
	if _symbol == Symbol.NONE or _mask == 0:
		return
	var half := SMALL_SIZE * 0.5
	for k in _faces.size():
		if (_mask & (1 << k)) == 0:
			continue
		var n: Vector3 = _faces[k]
		var to_cam := (cam_pos - (global_position + n * half)).normalized()
		var alpha := clampf((n.dot(to_cam) - 0.26) / 0.14, 0.0, 1.0)
		if _symbol == Symbol.FLAG:
			if k < _flags.size():
				_flags[k].visible = alpha > 0.01
				_flags[k].transparency = 1.0 - alpha
		else:
			var l := labels[k]
			l.visible = alpha > 0.01
			l.modulate = Color(_symbol_color.r, _symbol_color.g, _symbol_color.b, alpha)


func _set_size(s: float) -> void:
	mesh.scale = Vector3.ONE * s


func _set_solid(color: Color) -> void:
	_set_size(BASE_SIZE)
	mesh.visible = true
	mat.albedo_color = color
	mat.roughness = 0.50
	mat.rim_enabled = true
	mat.rim = 0.10
	mat.emission_enabled = false
	body.collision_layer = LAYER_SOLID
	_mask = 0
	_symbol = Symbol.NONE
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)
	_hide_symbols()


func _set_marked(color: Color, kind: Symbol, face_mask: int) -> void:
	_set_size(SMALL_SIZE)
	mesh.visible = true
	mat.albedo_color = color
	mat.roughness = 0.76
	mat.rim_enabled = true
	mat.rim = 0.10
	mat.emission_enabled = false
	body.collision_layer = LAYER_SOLID
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
				_flags[k].visible = true
				_flags[k].transparency = 0.0
	else:
		_symbol_color = Color(0.165, 0.200, 0.259)
		var half := SMALL_SIZE * 0.5 + LABEL_GAP
		for k in _faces.size():
			var l := labels[k]
			l.position = _faces[k] * half
			l.rotation = _face_rots[k]
			var on := (_mask & (1 << k)) != 0
			l.text = "?" if on else ""
			l.modulate = _symbol_color
			l.visible = on


func _set_revealed(count: int, face_mask: int) -> void:
	_set_size(SMALL_SIZE)
	mat.albedo_color = COL_OPEN
	mat.roughness = 0.90
	mat.rim_enabled = true
	mat.rim = 0.10
	mat.emission_enabled = false
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)

	_mask = 63 if face_mask == 0 else face_mask
	_symbol = Symbol.NUMBER if count > 0 else Symbol.NONE
	_symbol_color = _number_color(count)
	mesh.visible = count > 0
	_hide_symbols()

	# 数字格只在和弦射线里可命中；0 格彻底让路
	body.collision_layer = LAYER_OPEN if count > 0 else 0

	if count > 0:
		var half := SMALL_SIZE * 0.5 + LABEL_GAP
		for k in _faces.size():
			var l := labels[k]
			l.position = _faces[k] * half
			l.rotation = _face_rots[k]
			var on := (_mask & (1 << k)) != 0
			l.text = str(count) if on else ""
			l.modulate = _symbol_color
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
	var half := SMALL_SIZE * 0.5 + LABEL_GAP
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
	add_child(_mine)


func _apply_glow(on: bool) -> void:
	if _mine == null:
		return
	var material := _glow_material() if on else null
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
## 缩到 0.34 单位时细节会糊，所以杆要够粗（10/96）、旗面要够大。
static func _flag_texture() -> ImageTexture:
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var pole := Color(0.098, 0.075, 0.055)
	var cloth := Color(0.514, 0.290, 0.043)

	# 旗杆，略偏左以让整体重心居中
	for y in range(10, 88):
		for x in range(26, 38):
			img.set_pixel(x, y, pole)

	# 三角旗面：底边贴杆，尖端朝右
	for y in range(10, 56):
		var t: float = 1.0 - absf(float(y) - 33.0) / 23.0
		var x_end: int = 38 + int(t * 52.0)
		for x in range(38, x_end):
			img.set_pixel(x, y, cloth)

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


static func _glow_material() -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.albedo_color = Color(1.0, 0.298, 0.161, 0.48)
	return _glow_mat
