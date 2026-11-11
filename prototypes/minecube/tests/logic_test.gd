extends SceneTree

## 逻辑层自检：godot --headless --path prototypes/minecube -s res://tests/logic_test.gd

const BL := preload("res://scripts/board_logic.gd")

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_test_neighborhood()
	_test_counts_many_boards()
	_test_first_click_safety()
	_test_flood_fill()
	_test_win()
	_test_boom()
	_test_flags()
	_test_chord()
	_test_face_expansion()
	_test_center_degeneracy_3cubed()
	_test_face_counts()
	_test_face_invariants()

	print("")
	if _fails == 0:
		print("PASS  %d checks" % _checks)
		quit(0)
	else:
		print("FAIL  %d / %d checks failed" % [_fails, _checks])
		quit(1)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("  x " + msg)


func _test_neighborhood() -> void:
	var b := BL.new(Vector3i(3, 3, 3), 3)
	_check(b.cell_count() == 27, "3^3 应有 27 格")
	_check(b.neighbors(b.index_of(Vector3i(0, 0, 0))).size() == 7, "角块应有 7 个邻格")
	_check(b.neighbors(b.index_of(Vector3i(0, 1, 0))).size() == 11, "棱块应有 11 个邻格")
	_check(b.neighbors(b.index_of(Vector3i(1, 1, 0))).size() == 17, "面心应有 17 个邻格")
	_check(b.neighbors(b.index_of(Vector3i(1, 1, 1))).size() == 26, "体心应有 26 个邻格")

	var b4 := BL.new(Vector3i(4, 4, 4), 6)
	_check(b4.neighbors(b4.index_of(Vector3i(1, 1, 1))).size() == 26, "4^3 内部格应有 26 个邻格")
	_check(b4.neighbors(b4.index_of(Vector3i(0, 0, 0))).size() == 7, "4^3 角块应有 7 个邻格")

	# 索引可逆
	var ok := true
	for i in b.cell_count():
		if b.index_of(b.coord_of(i)) != i:
			ok = false
	_check(ok, "index_of / coord_of 应互为逆运算")


func _test_counts_many_boards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var bad := 0
	var checked_boards := 0
	for cfg in [[Vector3i(3, 3, 3), 3], [Vector3i(4, 4, 4), 6], [Vector3i(5, 5, 5), 12], [Vector3i(3, 4, 5), 8]]:
		var sz: Vector3i = cfg[0]
		var m: int = cfg[1]
		for trial in 40:
			var b := BL.new(sz, m)
			b.place_mines(rng.randi_range(0, b.cell_count() - 1), rng)
			checked_boards += 1

			var placed := 0
			for i in b.cell_count():
				if b.mines[i] == 1:
					placed += 1
			if placed != m:
				bad += 1

			# 用独立的暴力计算复核 counts
			for i in b.cell_count():
				if b.mines[i] == 1:
					continue
				var expect := 0
				for n in b.neighbors(i):
					if b.mines[n] == 1:
						expect += 1
				if b.counts[i] != expect:
					bad += 1
					break

	_check(bad == 0, "counts 应与暴力复核一致（%d 个盘面）" % checked_boards)


func _test_first_click_safety() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var violations := 0
	for trial in 60:
		var b := BL.new(Vector3i(4, 4, 4), 6)
		var first := rng.randi_range(0, b.cell_count() - 1)
		b.place_mines(first, rng)
		if b.mines[first] == 1:
			violations += 1
		for n in b.neighbors(first):
			if b.mines[n] == 1:
				violations += 1
		if b.counts[first] != 0:
			violations += 1
	_check(violations == 0, "首击格与其闭邻域不应有雷，首击数字应为 0")

	# 3^3 点体心时闭邻域覆盖全盘，应退化为只排除首击格而不崩
	var b3 := BL.new(Vector3i(3, 3, 3), 3)
	var center := b3.index_of(Vector3i(1, 1, 1))
	b3.place_mines(center, rng)
	var placed := 0
	for i in b3.cell_count():
		if b3.mines[i] == 1:
			placed += 1
	_check(placed == 3, "3^3 体心首击仍应布下 3 颗雷")
	_check(b3.mines[center] == 0, "3^3 体心首击不应踩雷")


func _test_flood_fill() -> void:
	# 3x3x3，只在 (2,2,2) 放一颗雷，点角上应几乎全开
	var b := BL.new(Vector3i(3, 3, 3), 1)
	b.mines[b.index_of(Vector3i(2, 2, 2))] = 1
	b.recompute_counts()
	b.generated = true

	var res := b.reveal(b.index_of(Vector3i(0, 0, 0)))
	var opened: Array = res["opened"]
	_check(not res["boom"], "点空格不应踩雷")
	_check(opened.size() == 26, "单雷盘面从角上点开应揭示全部 26 个非雷格，实际 %d" % opened.size())

	# 连通性与 0 边界：被打开的格子要么是 0，要么与某个 0 相邻
	var all_zero_adjacent := true
	for i in opened:
		if b.counts[i] == 0:
			continue
		var touches_zero := false
		for n in b.neighbors(i):
			if b.states[n] == BL.REVEALED and b.counts[n] == 0:
				touches_zero = true
				break
		if not touches_zero:
			all_zero_adjacent = false
	_check(all_zero_adjacent, "洪泛展开的每个数字格都应与某个已开放的 0 格相邻")


func _test_win() -> void:
	var b := BL.new(Vector3i(3, 3, 3), 2)
	b.mines[b.index_of(Vector3i(0, 0, 0))] = 1
	b.mines[b.index_of(Vector3i(2, 2, 2))] = 1
	b.recompute_counts()
	b.generated = true

	for i in b.cell_count():
		if b.mines[i] == 0 and not b.won:
			b.reveal(i)
	_check(b.won, "揭示全部非雷格后应判定胜利")
	_check(b.game_over, "胜利后应进入终态")

	var before := b.revealed_count
	b.reveal(b.index_of(Vector3i(1, 1, 1)))
	_check(b.revealed_count == before, "终态后不应再改变盘面")


func _test_boom() -> void:
	var b := BL.new(Vector3i(3, 3, 3), 1)
	b.mines[b.index_of(Vector3i(0, 0, 0))] = 1
	b.recompute_counts()
	b.generated = true

	var res := b.reveal(b.index_of(Vector3i(0, 0, 0)))
	_check(res["boom"], "点雷应返回 boom")
	_check(b.game_over and not b.won, "踩雷应进入失败终态")
	_check(b.hit_index == b.index_of(Vector3i(0, 0, 0)), "hit_index 应记录踩中的雷")
	_check(b.reveal_all_mines().size() == 1, "reveal_all_mines 应返回全部雷位")


func _test_flags() -> void:
	var b := BL.new(Vector3i(3, 3, 3), 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	b.place_mines(0, rng)

	var target := -1
	for i in b.cell_count():
		if b.mines[i] == 0:
			target = i
			break

	b.cycle_mark(target)
	_check(b.states[target] == BL.FLAGGED and b.flag_count == 1, "第一次右键应插旗并计入 flag_count")
	_check(b.remaining_mines() == 2, "剩余雷数应为 总数 - 旗数")

	var res := b.reveal(target)
	_check((res["opened"] as Array).is_empty(), "已插旗的格子不应被揭示")

	b.cycle_mark(target)
	_check(b.states[target] == BL.QUESTION, "第二次右键应变成问号")
	_check(b.flag_count == 0, "问号不应计入 flag_count")

	b.cycle_mark(target)
	_check(b.states[target] == BL.HIDDEN and b.flag_count == 0, "第三次右键应回到未标记")

	# 问号格不挡揭示，揭示后标记消失
	var b2 := BL.new(Vector3i(3, 3, 3), 3)
	b2.place_mines(0, rng)
	var target2 := -1
	for i in b2.cell_count():
		if b2.mines[i] == 0:
			target2 = i
			break
	b2.cycle_mark(target2)
	b2.cycle_mark(target2)
	_check(b2.states[target2] == BL.QUESTION, "先标成问号")
	var res2 := b2.reveal(target2)
	_check(not (res2["opened"] as Array).is_empty(), "问号格应可以被揭示")
	_check(b2.states[target2] == BL.REVEALED, "揭示后问号应被清掉")

	# 布雷之前就能插旗，布雷之后标记保留
	var b3 := BL.new(Vector3i(3, 3, 3), 3)
	b3.cycle_mark(0)
	_check(b3.states[0] == BL.FLAGGED and b3.flag_count == 1, "布雷前应允许插旗")
	b3.cycle_mark(1)
	b3.cycle_mark(1)
	_check(b3.states[1] == BL.QUESTION, "布雷前也应允许标问号")
	b3.place_mines(13, rng)
	_check(b3.states[0] == BL.FLAGGED, "布雷后先前的旗应保留")
	_check(b3.states[1] == BL.QUESTION, "布雷后先前的问号应保留")


func _test_chord() -> void:
	# 3^3，三颗雷分居体心所在的三条轴上：三个平面各有一颗以上，
	# 体心六个面都非 0，揭示时不会连锁展开，和弦的判定才可观测。
	var b := BL.new(Vector3i(3, 3, 3), 3)
	var mines := [Vector3i(0, 1, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 0)]
	for m in mines:
		b.mines[b.index_of(m)] = 1
	b.recompute_counts()
	b.generated = true

	var center := b.index_of(Vector3i(1, 1, 1))
	var fc := b.face_counts_of(center)
	_check(fc == [2, 2, 2, 2, 2, 2], "体心六面都应为 2，实际 %s" % str(fc))

	var first := b.reveal(center)
	_check((first["opened"] as Array).size() == 1, "六面非 0 时揭示不应连锁，实际开了 %d 格"
		% (first["opened"] as Array).size())

	# 未插旗：旗数 0 不等于 2，什么都不发生
	var unsatisfied := b.chord_face(center, 0)
	_check((unsatisfied["opened"] as Array).is_empty(), "旗数不足时和弦不应揭开任何格")
	_check(not b.game_over, "旗数不足时不应结束")

	# 只把 +Z 平面里的两颗雷插上旗
	var z_mines := [Vector3i(1, 0, 1), Vector3i(0, 1, 1)]
	for m in z_mines:
		b.cycle_mark(b.index_of(m))

	# 别的平面旗数仍是 0，不该被 +Z 的两面旗带动
	var other := b.chord_face(center, 4)
	_check((other["opened"] as Array).is_empty(), "旗插在 +Z 平面，+Y 平面不应触发和弦")

	# +Z 面旗数对上数字，揭开该平面内其余 6 格
	var ok := b.chord_face(center, 0)
	_check(not ok["boom"], "旗插对了和弦不应该引爆")
	# 打开的格数会带上连锁展开，所以只断言该平面内的 6 格都开了
	_check((ok["opened"] as Array).size() >= 6, "和弦至少应揭开 +Z 平面内其余 6 格，实际 %d"
		% (ok["opened"] as Array).size())
	for m in [Vector3i(0, 0, 1), Vector3i(2, 0, 1), Vector3i(2, 1, 1),
			Vector3i(0, 2, 1), Vector3i(1, 2, 1), Vector3i(2, 2, 1)]:
		_check(b.states[b.index_of(m)] == BL.REVEALED, "+Z 平面内 %s 应被揭开" % str(m))

	# 平面外的那颗雷不受影响
	_check(b.states[b.index_of(Vector3i(1, 1, 0))] == BL.HIDDEN, "平面外的雷不应被揭开")

	# 旗插错：把平面外的雷当旗插上，+Y 面数字被满足但会踩雷
	var b2 := BL.new(Vector3i(3, 3, 3), 3)
	for m in mines:
		b2.mines[b2.index_of(m)] = 1
	b2.recompute_counts()
	b2.generated = true
	var c2 := b2.index_of(Vector3i(1, 1, 1))
	b2.reveal(c2)
	# +Y 平面（y=1）里的两颗雷是 (1,1,0) 与 (0,1,1)，插上就满足 y 面的 2
	b2.cycle_mark(b2.index_of(Vector3i(1, 1, 0)))
	b2.cycle_mark(b2.index_of(Vector3i(0, 1, 1)))
	var bad := b2.chord_face(c2, 4)
	_check(not bad["boom"], "旗插对了 +Y 面不应引爆")

	# 把旗全撤掉、改插一颗错的，则触发但踩雷
	var b3 := BL.new(Vector3i(3, 3, 3), 3)
	for m in mines:
		b3.mines[b3.index_of(m)] = 1
	b3.recompute_counts()
	b3.generated = true
	var c3 := b3.index_of(Vector3i(1, 1, 1))
	b3.reveal(c3)
	# 一颗插对（真雷）、一颗插错（空位），旗数凑够 2 就会揭开剩下的雷
	b3.cycle_mark(b3.index_of(Vector3i(1, 0, 1)))
	b3.cycle_mark(b3.index_of(Vector3i(2, 2, 1)))
	var wrong := b3.chord_face(c3, 0)
	_check(wrong["boom"], "旗数对上但位置错了，和弦应引爆")
	_check(b3.game_over and not b3.won, "引爆后应进入失败终态")


## 展开按面判定：某一面为 0 就整片打开该平面内的 8 格
func _test_face_expansion() -> void:
	var b := BL.new(Vector3i(3, 3, 3), 1)
	b.mines[b.index_of(Vector3i(0, 1, 1))] = 1
	b.recompute_counts()
	b.generated = true

	var center := b.index_of(Vector3i(1, 1, 1))
	var fc := b.face_counts_of(center)
	_check(fc[2] == 0 and fc[3] == 0, "雷在 x=0 层，体心的 ±X 两面应为 0，实际 %s" % str(fc))

	b.reveal(center)
	_check(b.states[b.index_of(Vector3i(1, 0, 1))] == BL.REVEALED,
		"±X 面为 0，该平面内的格子应被自动打开")
	_check(b.states[b.index_of(Vector3i(0, 1, 1))] == BL.HIDDEN, "雷本身不能被展开")


func _test_center_degeneracy_3cubed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var b := BL.new(Vector3i(3, 3, 3), 3)
	b.place_mines(0, rng)
	var center := b.index_of(Vector3i(1, 1, 1))
	var mine_count := 0
	for i in b.cell_count():
		if b.mines[i] == 1:
			mine_count += 1
	if b.mines[center] == 0:
		_check(b.counts[center] == mine_count, "3^3 体心的数字应等于总雷数（已知退化）")

	# 4^3 不应出现这种覆盖全盘的情况
	var b4 := BL.new(Vector3i(4, 4, 4), 6)
	_check(b4.neighbors(b4.index_of(Vector3i(1, 1, 1))).size() < b4.cell_count() - 1,
		"4^3 单格邻域不应覆盖全盘")


## 每面统计该面所在平面内的 8 邻格。
## 推论：一颗雷会被 6 个面里的 4 个统计到（包含它的那两个平面各两面），
## 所以六面之和 = 4 × 26 邻域计数；同一轴的两面数值必然相同。
func _test_face_counts() -> void:
	var b := BL.new(Vector3i(3, 3, 3), 1)
	b.mines.fill(0)
	b.mines[b.index_of(Vector3i(1, 1, 1))] = 1
	b.recompute_counts()

	# (0,0,1) 与雷同在 z=1 平面 → ±Z 两面都是 1，其余为 0
	var diag := b.index_of(Vector3i(0, 0, 1))
	var dc := b.face_counts_of(diag)
	_check(dc == [1, 1, 0, 0, 0, 0], "z 平面内的雷只应出现在 ±Z 两面，实际 %s" % str(dc))

	# (1,0,1) 的雷在 z=1 与 x=1 两个平面里 → 四个面为 1
	var orth := b.index_of(Vector3i(1, 0, 1))
	var oc := b.face_counts_of(orth)
	_check(oc == [1, 1, 1, 1, 0, 0], "两个平面各两面应为 1，实际 %s" % str(oc))

	# 不变量：六面之和 = 4 × 26 邻域计数
	var sum := 0
	for v in oc:
		sum += v
	_check(sum == 4 * b.counts[orth], "六面之和应为 26 计数的 4 倍，实际 %d vs %d" % [
		sum, b.counts[orth]])

	# 同一轴的两面必然相同
	_check(oc[0] == oc[1] and oc[2] == oc[3] and oc[4] == oc[5], "同一轴的两面数值应相同")

	# 面邻域是平面内的 3×3 去心，最多 8 格
	_check(b.face_neighbors(b.index_of(Vector3i(1, 1, 1)), 0).size() == 8, "体心的面邻域应有 8 格")
	_check(BL.FACE_AXIS == [2, 2, 0, 0, 1, 1], "面法线轴顺序应与 CellView._faces 一致")

## 随机盘面上锁死几条不变量。
## 六面之和不是 4×26 计数：每颗雷按"与格子共享几个坐标平面"加权，
## 轴向邻格共享 2 个平面（4 面）、棱对角共享 1 个（2 面）、体对角 0 个（0 面）。
func _test_face_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261111
	var checked := 0
	var bad_range := 0
	var bad_sum := 0
	var bad_axis := 0
	for trial in 40:
		var side := 3 + trial % 5
		var total := side * side * side
		var b := BL.new(Vector3i(side, side, side), maxi(2, int(total * 0.3)))
		b.place_mines(rng.randi_range(0, total - 1), rng)
		for i in total:
			if b.mines[i] == 1:
				continue
			checked += 1
			var fc := b.face_counts_of(i)
			for v in fc:
				if v < 0 or v > 8:
					bad_range += 1

			# 按邻格类型算应有的加权和
			var c := b.coord_of(i)
			var expect := 0
			for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
					Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
					Vector3i(1, 1, 0), Vector3i(1, -1, 0), Vector3i(-1, 1, 0), Vector3i(-1, -1, 0),
					Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1),
					Vector3i(0, 1, 1), Vector3i(0, 1, -1), Vector3i(0, -1, 1), Vector3i(0, -1, -1)]:
				var o: Vector3i = off
				var q: Vector3i = c + o
				if b.in_bounds(q) and b.mines[b.index_of(q)] == 1:
					# 只有一个分量为 1 → 轴向邻格，共享两个平面 → 4 面
					var nz := absi(o.x) + absi(o.y) + absi(o.z)
					expect += 4 if nz == 1 else 2
			# 体对角邻格不进任何面，权重 0，不参与
			var sum := 0
			for v in fc:
				sum += v
			if sum != expect:
				bad_sum += 1

			if fc[0] != fc[1] or fc[2] != fc[3] or fc[4] != fc[5]:
				bad_axis += 1

	_check(checked > 1000, "应覆盖足够多的非雷格，实际 %d" % checked)
	_check(bad_range == 0, "面计数越界，共 %d 处" % bad_range)
	_check(bad_sum == 0, "六面之和与类型加权和不等，共 %d 处" % bad_sum)
	_check(bad_axis == 0, "同一轴两面数值应相同，共 %d 处不一致" % bad_axis)
