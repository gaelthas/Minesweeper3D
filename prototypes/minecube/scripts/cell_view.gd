class_name CellView
extends Node3D

## 单个方块的视图。
##
## 碰撞层分两类，这是三维可达性的支点：
##   LAYER_SOLID —— 未揭示/已插旗，左键揭示命中的目标
##   LAYER_OPEN  —— 已揭示的数字格，只给和弦用
## 数字格不在揭示射线的掩码里，射线会穿过去命中内层，
## 否则 3×3×3 的体心被 26 个方块包住就永远点不到了。

const BASE_SIZE := 0.84
const SMALL_SIZE := 0.52
const LABEL_GAP := 0.006

const LAYER_SOLID := 1
const LAYER_OPEN := 2

const COL_HIDDEN := Color(0.878, 0.898, 0.933)
const COL_FLAG := Color(0.780, 0.667, 0.478)
const COL_OPEN := Color(0.212, 0.251, 0.314)
const COL_MINE := Color(0.643, 0.157, 0.196)
const COL_HIT := Color(1.0, 0.318, 0.318)

const POLE_HEIGHT := 0.30

static var _pole_mat: StandardMaterial3D
static var _pennant_mat: StandardMaterial3D
static var _glow_mat: StandardMaterial3D

var index: int
var body: StaticBody3D
var mesh: MeshInstance3D
var box: BoxMesh
var mat: StandardMaterial3D
var labels: Array[Label3D] = []

var _faces: Array[Vector3] = []
var _face_rots: Array[Vector3] = []
var _mask := 0
var _show_number := false
var _num_color := Color.WHITE

var _pole: MeshInstance3D
var _pennant: MeshInstance3D
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
	mat.rim = 0.22
	mat.rim_tint = 0.55

	box = BoxMesh.new()
	box.size = Vector3(BASE_SIZE, BASE_SIZE, BASE_SIZE)
	box.material = mat

	mesh = MeshInstance3D.new()
	mesh.mesh = box
	body.add_child(mesh)

	for k in _faces.size():
		var l := Label3D.new()
		l.pixel_size = 0.005
		l.font_size = 44
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

	_build_flag_marker()
	apply(BoardLogic.HIDDEN, 0, 0)


func apply(state: int, count: int, face_mask: int = 63) -> void:
	match state:
		BoardLogic.FLAGGED:
			_set_flagged()
		BoardLogic.REVEALED:
			_set_revealed(count, face_mask)
		_:
			_set_solid(COL_HIDDEN)


func set_mine(is_hit: bool) -> void:
	mesh.visible = false
	_pole.visible = false
	_pennant.visible = false
	_mask = 0
	_show_number = false
	_hide_labels()
	body.collision_layer = 0

	_ensure_mine()
	if _mine == null:
		# 模型缺失时退回一个色块，至少还能看出哪格是雷
		mesh.visible = true
		box.size = Vector3(BASE_SIZE, BASE_SIZE, BASE_SIZE)
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
func update_label_facing(cam_pos: Vector3) -> void:
	if not _show_number or _mask == 0:
		return
	var half := SMALL_SIZE * 0.5
	for k in labels.size():
		if (_mask & (1 << k)) == 0:
			continue
		var n: Vector3 = _faces[k]
		var to_cam := (cam_pos - (global_position + n * half)).normalized()
		var alpha := clampf((n.dot(to_cam) - 0.26) / 0.14, 0.0, 1.0)
		var l := labels[k]
		l.visible = alpha > 0.01
		l.modulate = Color(_num_color.r, _num_color.g, _num_color.b, alpha)


func _build_flag_marker() -> void:
	var top := SMALL_SIZE * 0.5

	_pole = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.019
	cyl.bottom_radius = 0.019
	cyl.height = POLE_HEIGHT
	cyl.radial_segments = 8
	cyl.rings = 1
	_pole.mesh = cyl
	_pole.material_override = _pole_material()
	_pole.position = Vector3(0, top + POLE_HEIGHT * 0.5, 0)
	_pole.visible = false
	add_child(_pole)

	_pennant = MeshInstance3D.new()
	var pr := BoxMesh.new()
	pr.size = Vector3(0.22, 0.13, 0.016)
	_pennant.mesh = pr
	_pennant.material_override = _pennant_material()
	_pennant.position = Vector3(0.11, top + POLE_HEIGHT - 0.065, 0)
	_pennant.visible = false
	add_child(_pennant)


func _set_solid(color: Color) -> void:
	mesh.visible = true
	box.size = Vector3(BASE_SIZE, BASE_SIZE, BASE_SIZE)
	mat.albedo_color = color
	mat.roughness = 0.50
	mat.rim_enabled = true
	mat.rim = 0.22
	mat.emission_enabled = false
	body.collision_layer = LAYER_SOLID
	_mask = 0
	_show_number = false
	_pole.visible = false
	_pennant.visible = false
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)
	_hide_labels()


func _set_flagged() -> void:
	mesh.visible = true
	box.size = Vector3(SMALL_SIZE, SMALL_SIZE, SMALL_SIZE)
	mat.albedo_color = COL_FLAG
	mat.roughness = 0.78
	mat.rim_enabled = true
	mat.rim = 0.40
	mat.emission_enabled = false
	body.collision_layer = LAYER_SOLID
	_mask = 0
	_show_number = false
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)
	_hide_labels()
	_pole.visible = true
	_pennant.visible = true


func _set_revealed(count: int, face_mask: int) -> void:
	box.size = Vector3(SMALL_SIZE, SMALL_SIZE, SMALL_SIZE)
	mat.albedo_color = COL_OPEN
	mat.roughness = 0.90
	mat.rim_enabled = true
	mat.rim = 0.60
	mat.emission_enabled = false

	_pole.visible = false
	_pennant.visible = false
	if _mine != null:
		_mine.visible = false
	_apply_glow(false)

	_mask = 63 if face_mask == 0 else face_mask
	_show_number = count > 0
	_num_color = _number_color(count)
	mesh.visible = _show_number

	# 数字格只在和弦射线里可命中；0 格彻底让路
	body.collision_layer = LAYER_OPEN if _show_number else 0

	var half := SMALL_SIZE * 0.5 + LABEL_GAP
	for k in labels.size():
		var l := labels[k]
		var on := _show_number and (_mask & (1 << k)) != 0
		l.position = _faces[k] * half
		l.rotation = _face_rots[k]
		l.text = str(count) if on else ""
		l.modulate = _num_color
		l.visible = on


func _hide_labels() -> void:
	for l in labels:
		l.visible = false
		l.text = ""


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


static func _pole_material() -> StandardMaterial3D:
	if _pole_mat == null:
		_pole_mat = StandardMaterial3D.new()
		_pole_mat.albedo_color = Color(0.267, 0.216, 0.149)
		_pole_mat.roughness = 0.7
	return _pole_mat


static func _pennant_material() -> StandardMaterial3D:
	if _pennant_mat == null:
		_pennant_mat = StandardMaterial3D.new()
		_pennant_mat.albedo_color = Color(0.941, 0.639, 0.239)
		_pennant_mat.roughness = 0.55
		_pennant_mat.emission_enabled = true
		_pennant_mat.emission = Color(0.941, 0.639, 0.239)
		_pennant_mat.emission_energy_multiplier = 0.22
	return _pennant_mat


static func _glow_material() -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.albedo_color = Color(1.0, 0.298, 0.161, 0.48)
	return _glow_mat
