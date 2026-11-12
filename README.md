# MineCube 3D

把扫雷搬进一个可旋转的三维立方体。规则针对三维重写过，不是把 2D 棋盘贴到六个面上。

Godot 4.7.2 · 当前版本 0.5.0 · 原型阶段

## 它和 2D 扫雷的差别

难点在数字的意义。三维里一颗格子有 26 个邻格，把 26 个邻格的雷数压成一个数字，剥离一层之后就无法继续推理——数字既不是"这一层的信息"，也不是"某一面的信息"。

这个原型改成**每个面独立计数**：某一面显示几，就是该面所在平面内 8 个邻格里的雷数。

| | 2D 扫雷 | MineCube 3D |
| --- | --- | --- |
| 数字含义 | 周围 8 格的雷数 | 每个面各数一套：该面所在平面的 8 格 |
| 六面全为 0 | — | 方块直接消失，露出后面的格子 |
| 自动展开 | 从 0 格扩散到周围 8 格 | 某一面为 0，就打开该平面内的 8 格，可连锁 |
| 和弦 | 周围旗数等于数字 | 该平面内旗数等于该面数字 |

由此带来一个反直觉的推论：**一颗雷只被六个面里的两到四个统计到**。轴向邻格落在两个坐标平面里（被 4 个面看到），棱对角邻格落在一个平面里（2 个面），体对角邻格三个分量都不为零、不落在任何坐标平面里——**没有任何一面看得到它**。

实测 5.86% 的非雷格属于"周围有雷但六面全 0"，它们和真正的空区一样消失，不留占位方块。

## 操作

默认映射，可在「选项」里逐键改。

| 输入 | 动作 |
| --- | --- |
| 左键 | 揭示 |
| 右键 | 插旗：未标记 → 旗 → 问号 → 未标记 |
| 中键拖拽 | 平移视角 |
| 拖拽（非平移键） | 旋转视角 |
| 左右键同按 | 和弦（按被点的那一面判定） |
| 滚轮 | 缩放 |
| `R` | 重开 |
| `M` | 静音 |
| `Esc` | 关闭最上层浮层 |

已揭示的数字方块会吃掉点击，不穿透。要挖内层，从方块之间的缝隙瞄——右下角的「间距」滑块可以拉开方块距离（100%–200%）。

## 运行

需要 Godot 4.7.2（其他 4.x 未验证）。

```sh
godot --path prototypes/minecube
```

也可以直接用编辑器打开 `prototypes/minecube/project.godot`。

默认盘面 5×5×5、38 颗雷（30% 密度）。阶数可在「开局」里调到 3–13；13 阶全开实测 34.6 FPS，是当前节点数下的实际上限。

选项页管应用本身：显示模式、分辨率、音量与静音、垂直同步、帧率显示、鼠标三键功能。改动即时生效并写入 `user://settings.cfg`。

## 测试

两条命令都在仓库根执行：

```sh
godot --headless --path prototypes/minecube -s res://tests/logic_test.gd
godot --headless --path prototypes/minecube -s res://tests/ui_smoke.gd
```

`logic_test.gd` 是纯逻辑层自检，不依赖场景，共 67 项断言：邻域、计数、首击安全、按面展开、按平面和弦、胜负、随机盘面的计数不变量。

`ui_smoke.gd` 覆盖需要场景树的部分：射线拾取、碰撞盒尺寸、和弦的事件链路、中键平移、浮层阻挡、设置持久化。headless 可跑。

## 目录

```
doc/
  design.md              设计决策与踩过的坑（比 README 长得多）
  shots/                 截图，由 tests/capture.gd 生成
prototypes/
  index.md               原型索引
  minecube/
    assets/
      build_cube.py      用 Blender 生成削角方块模型
      cube_rounded.glb   产物，已入库
      sfx/               6 个 CC0 音效，来源见 CREDITS.md
    scenes/main.tscn
    scripts/             逻辑层、视图层、UI 各自独立
    tests/               逻辑自检、UI 冒烟、截图、平衡探针
    REPORT.md            概念原型报告（记录的是早期规则下的数据）
```

方块模型不手改：改 `assets/build_cube.py` 里的参数后用 Blender 重新导出，再让 Godot 重导。

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -noaudio \
  -P prototypes/minecube/assets/build_cube.py
```

## 已知状态

- 原型阶段，建成了但还没有人完整试玩过，因此没有 PROCEED / PIVOT / KILL 结论。
- `REPORT.md` 里的平衡数据出自 26 邻域时代，和现在每面计数的规则不一致，只作历史记录看。当前规则的说明以 `doc/design.md` 为准。
- 只在 macOS 上构建和测试过。字体走系统字体回退（macOS / Linux / Windows 各留了路径），未在其他平台实跑。

## 许可

代码与文档采用 [MIT 许可](LICENSE)。

`prototypes/minecube/assets/sfx/` 下的音效全部来自 Freesound 的 CC0 素材，按 CC0 分发，署名与来源见该目录的 `CREDITS.md`。
