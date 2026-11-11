class_name BoardLogic
extends RefCounted

## 纯逻辑层，不引用任何场景节点，可以直接在 --headless 下测试。
## 索引约定：i = x + size.x * (y + size.y * z)

const HIDDEN := 0
const REVEALED := 1
const FLAGGED := 2
const QUESTION := 3

var size: Vector3i
var mine_total: int
var generated := false

var mines := PackedByteArray()
var counts := PackedByteArray()
var states := PackedByteArray()

## 每格 6 个面的雷数，顺序 +Z -Z +X -X +Y -Y，与 CellView._faces 一致。
## 每个数只统计该面所在平面内的 8 个邻格，不含法线方向的邻格。
var face_counts := PackedByteArray()

var revealed_count := 0
var flag_count := 0
var hit_index := -1
var game_over := false
var won := false

var _offsets: Array[Vector3i] = []


func _init(p_size: Vector3i, p_mines: int) -> void:
	size = p_size
	var total := cell_count()
	mine_total = clampi(p_mines, 1, maxi(1, total - 1))

	mines.resize(total)
	mines.fill(0)
	counts.resize(total)
	counts.fill(0)
	states.resize(total)
	states.fill(HIDDEN)
	face_counts.resize(total * 6)
	face_counts.fill(0)

	for z in range(-1, 2):
		for y in range(-1, 2):
			for x in range(-1, 2):
				if x == 0 and y == 0 and z == 0:
					continue
				_offsets.append(Vector3i(x, y, z))


func cell_count() -> int:
	return size.x * size.y * size.z


func index_of(p: Vector3i) -> int:
	return p.x + size.x * (p.y + size.y * p.z)


func coord_of(i: int) -> Vector3i:
	var plane := size.x * size.y
	var x := i % size.x
	var y := (i % plane) / size.x
	var z := i / plane
	return Vector3i(x, y, z)


func in_bounds(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 \
		and p.x < size.x and p.y < size.y and p.z < size.z


func neighbors(i: int) -> Array[int]:
	var out: Array[int] = []
	var c := coord_of(i)
	for off in _offsets:
		var q := c + off
		if in_bounds(q):
			out.append(index_of(q))
	return out


func closed_neighborhood(i: int) -> Array[int]:
	var out := neighbors(i)
	out.append(i)
	return out


## 在首击之后再布雷，首击格的闭邻域为空，保证第一次揭示必然展开。
func place_mines(first_index: int, rng: RandomNumberGenerator) -> void:
	var total := cell_count()

	var excluded := {}
	for i in closed_neighborhood(first_index):
		excluded[i] = true

	var candidates: Array[int] = []
	for i in total:
		if not excluded.has(i):
			candidates.append(i)

	# 盘面太小，剔除闭邻域后装不下雷，退化为只剔除首击格。
	if candidates.size() < mine_total:
		candidates.clear()
		for i in total:
			if i != first_index:
				candidates.append(i)

	_shuffle(candidates, rng)
	for k in mine_total:
		mines[candidates[k]] = 1

	recompute_counts()
	generated = true


## 根据 mines 重算 counts。place_mines 会调用；测试里手工布雷时也用它。
func recompute_counts() -> void:
	for i in cell_count():
		if mines[i] == 1:
			counts[i] = 0
			continue
		var c := 0
		for n in neighbors(i):
			if mines[n] == 1:
				c += 1
		counts[i] = c
	recompute_face_counts()


## 面的法线轴：+Z -Z 是 z 轴、+X -X 是 x 轴、+Y -Y 是 y 轴
const FACE_AXIS := [2, 2, 0, 0, 1, 1]


## 某一面所在平面内的 8 个邻格：固定法线轴，另外两轴各偏移 ±1
func face_neighbors(i: int, face: int) -> Array[int]:
	var out: Array[int] = []
	var axis: int = FACE_AXIS[face]
	var c := coord_of(i)
	for a in range(-1, 2):
		for b in range(-1, 2):
			if a == 0 and b == 0:
				continue
			var off := Vector3i.ZERO
			match axis:
				0:
					off = Vector3i(0, a, b)
				1:
					off = Vector3i(a, 0, b)
				_:
					off = Vector3i(a, b, 0)
			var q := c + off
			if in_bounds(q):
				out.append(index_of(q))
	return out


## 每面 8 邻域的雷数。注意法线方向的邻格不在任何一面里——
## 正上方有雷的格子，六个面可能全是 0。
func recompute_face_counts() -> void:
	face_counts.resize(cell_count() * 6)
	for i in cell_count():
		for f in 6:
			if mines[i] == 1:
				face_counts[i * 6 + f] = 0
				continue
			var n := 0
			for j in face_neighbors(i, f):
				n += mines[j]
			face_counts[i * 6 + f] = n


func face_counts_of(i: int) -> Array[int]:
	var out: Array[int] = []
	for f in 6:
		out.append(face_counts[i * 6 + f])
	return out


func _shuffle(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := arr[i]
		arr[i] = arr[j]
		arr[j] = t


## 返回 { opened: Array[int], boom: bool }
func reveal(i: int) -> Dictionary:
	var opened: Array[int] = []
	if game_over or not generated:
		return {"opened": opened, "boom": false}
	if i < 0 or i >= states.size() or states[i] == REVEALED:
		return {"opened": opened, "boom": false}
	if states[i] == FLAGGED:
		return {"opened": opened, "boom": false}

	if mines[i] == 1:
		states[i] = REVEALED
		hit_index = i
		game_over = true
		opened.append(i)
		return {"opened": opened, "boom": true}

	var stack: Array[int] = [i]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		if states[cur] == REVEALED or states[cur] == FLAGGED or mines[cur] == 1:
			continue
		states[cur] = REVEALED
		revealed_count += 1
		opened.append(cur)

		# 展开按面判定：某一面为 0，说明该平面内的 8 格必无雷，可以整片打开。
		# 六个面都为 0 时就等于把 26 邻域全开，和原来的整格判定一致。
		for f in 6:
			if face_counts[cur * 6 + f] != 0:
				continue
			for n in face_neighbors(cur, f):
				if states[n] == HIDDEN or states[n] == QUESTION:
					stack.append(n)

	won = revealed_count == cell_count() - mine_total
	if won:
		game_over = true
	return {"opened": opened, "boom": false}


## 右键循环：未标记 → 旗 → 问号 → 未标记。
## 只有旗计入 flag_count；问号不挡揭示，只是备忘。
## 布雷前也可以标记——雷是在首击后才放下去的，标记跟着格子走。
func cycle_mark(i: int) -> void:
	if game_over:
		return
	if i < 0 or i >= states.size() or states[i] == REVEALED:
		return
	match states[i]:
		HIDDEN:
			states[i] = FLAGGED
			flag_count += 1
		FLAGGED:
			states[i] = QUESTION
			flag_count -= 1
		_:
			states[i] = HIDDEN


## 和弦按平面判定：只在被点的那一面所属的平面里比旗数。
## 这一面显示几，就要求这 8 个邻格里有几面旗；对上了才揭开该平面内其余未标记的格子。
## 不同平面各算各的，互不影响——这正是每面独立计数后的自然玩法。
func chord_face(i: int, face: int) -> Dictionary:
	var opened: Array[int] = []
	if game_over or not generated:
		return {"opened": opened, "boom": false}
	if i < 0 or i >= states.size() or face < 0 or face > 5:
		return {"opened": opened, "boom": false}
	if states[i] != REVEALED:
		return {"opened": opened, "boom": false}

	var need: int = face_counts[i * 6 + face]
	if need == 0:
		return {"opened": opened, "boom": false}

	var flagged := 0
	var targets: Array[int] = []
	for n in face_neighbors(i, face):
		if states[n] == FLAGGED:
			flagged += 1
		elif states[n] == HIDDEN or states[n] == QUESTION:
			targets.append(n)

	if flagged != need:
		return {"opened": opened, "boom": false}

	var boom := false
	for n in targets:
		var res := reveal(n)
		opened.append_array(res["opened"])
		if res["boom"]:
			boom = true
			break
	return {"opened": opened, "boom": boom}


func remaining_mines() -> int:
	return mine_total - flag_count


## 失败后用于显示全部雷位
func reveal_all_mines() -> Array[int]:
	var out: Array[int] = []
	for i in cell_count():
		if mines[i] == 1:
			out.append(i)
	return out
