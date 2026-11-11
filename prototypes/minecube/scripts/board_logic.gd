class_name BoardLogic
extends RefCounted

## 纯逻辑层，不引用任何场景节点，可以直接在 --headless 下测试。
## 索引约定：i = x + size.x * (y + size.y * z)

const HIDDEN := 0
const REVEALED := 1
const FLAGGED := 2

var size: Vector3i
var mine_total: int
var generated := false

var mines := PackedByteArray()
var counts := PackedByteArray()
var states := PackedByteArray()

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
	if i < 0 or i >= states.size() or states[i] != HIDDEN:
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
		if states[cur] != HIDDEN or mines[cur] == 1:
			continue
		states[cur] = REVEALED
		revealed_count += 1
		opened.append(cur)
		if counts[cur] != 0:
			continue
		for n in neighbors(cur):
			if states[n] == HIDDEN and mines[n] == 0:
				stack.append(n)

	won = revealed_count == cell_count() - mine_total
	if won:
		game_over = true
	return {"opened": opened, "boom": false}


func toggle_flag(i: int) -> void:
	if game_over or not generated:
		return
	if i < 0 or i >= states.size() or states[i] == REVEALED:
		return
	if states[i] == HIDDEN:
		states[i] = FLAGGED
		flag_count += 1
	else:
		states[i] = HIDDEN
		flag_count -= 1


## 和弦：在已揭示的数字格上，若周围旗数恰好等于该数字，
## 一次揭开所有未插旗的相邻未揭示格。旗插错了照样会炸。
func chord(i: int) -> Dictionary:
	var opened: Array[int] = []
	if game_over or not generated:
		return {"opened": opened, "boom": false}
	if i < 0 or i >= states.size():
		return {"opened": opened, "boom": false}
	if states[i] != REVEALED or counts[i] == 0:
		return {"opened": opened, "boom": false}

	var flagged := 0
	for n in neighbors(i):
		if states[n] == FLAGGED:
			flagged += 1
	if flagged != counts[i]:
		return {"opened": opened, "boom": false}

	var boom := false
	for n in neighbors(i):
		if states[n] != HIDDEN:
			continue
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
