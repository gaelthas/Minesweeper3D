extends SceneTree

## 平衡探针：统计首击展开的规模，用来判断盘面/雷数组合是否还有推理空间。
## godot --headless --path . -s res://tests/balance_probe.gd

const BL := preload("res://scripts/board_logic.gd")


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	var presets := [
		[Vector3i(3, 3, 3), 3],
		[Vector3i(4, 4, 4), 6],
		[Vector3i(5, 5, 5), 12],
		[Vector3i(4, 4, 4), 9],
		[Vector3i(5, 5, 5), 16],
	]

	print("盘面      雷  首击平均开  中位   p90   0格占比  一击通关")
	for p in presets:
		var sz: Vector3i = p[0]
		var m: int = p[1]
		var trials := 400
		var ratio_sum := 0.0
		var zero_sum := 0.0
		var clears := 0
		var opened: Array[int] = []
		var need := sz.x * sz.y * sz.z - m

		for t in trials:
			var b = BL.new(sz, m)
			var first := rng.randi_range(0, b.cell_count() - 1)
			b.place_mines(first, rng)
			var res: Dictionary = b.reveal(first)
			var n: int = (res["opened"] as Array).size()
			opened.append(n)
			ratio_sum += float(n) / float(need)
			if n >= need:
				clears += 1
			var zeros := 0
			for i in b.cell_count():
				if b.mines[i] == 0 and b.counts[i] == 0:
					zeros += 1
			zero_sum += float(zeros) / float(b.cell_count())

		opened.sort()
		var mean_pct := 100.0 * ratio_sum / trials
		var med: int = opened[trials / 2]
		var p90: int = opened[int(trials * 0.9)]
		var zero_pct := 100.0 * zero_sum / trials
		var clear_pct := 100.0 * float(clears) / trials

		print("%d^3      %2d   %5.1f%%      %2d/%-2d  %2d/%d   %5.1f%%   %5.1f%%" % [
			sz.x, m, mean_pct, med, need, p90, need, zero_pct, clear_pct])

	quit(0)
