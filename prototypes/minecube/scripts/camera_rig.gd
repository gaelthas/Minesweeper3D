class_name CameraRig
extends Node3D

## 环绕相机：拖拽改 yaw/pitch，滚轮改距离。始终看向原点（盘面中心）。

var yaw := 38.0
var pitch := 34.0
var distance := 8.0
var min_distance := 4.0
var max_distance := 22.0
var orbit_speed := 0.32
var pan_speed := 0.0016

## 平移时相机看向的点，也绕它旋转
var pivot := Vector3.ZERO

var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.1
	camera.far = 300.0
	camera.current = true
	add_child(camera)
	_apply()


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * orbit_speed
	pitch = clampf(pitch + relative.y * orbit_speed, -86.0, 86.0)
	_apply()


## 中键平移：沿相机自身的右/上方向挪动观察中心
func pan(relative: Vector2) -> void:
	if camera == null:
		return
	var scale := distance * pan_speed
	var basis := camera.global_transform.basis
	pivot += (-basis.x * relative.x + basis.y * relative.y) * scale
	_apply()


func zoom(amount: float) -> void:
	distance = clampf(distance + amount, min_distance, max_distance)
	_apply()


## 依据盘面尺寸选一个能装下整盘的初始距离
func frame(board_size: Vector3i) -> void:
	# 只按阶数取景。间距不参与——否则间距一大画面整体缩小，看着像方块变小了
	pivot = Vector3.ZERO
	var extent := float(maxi(board_size.x, maxi(board_size.y, board_size.z)))
	distance = clampf(extent * 2.7, 6.0, 38.0)
	min_distance = maxf(3.0, extent * 1.2)
	max_distance = extent * 4.0
	_apply()


func _apply() -> void:
	if camera == null:
		return
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var dir := Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y))
	camera.position = pivot + dir * distance
	camera.look_at(pivot, Vector3.UP)
