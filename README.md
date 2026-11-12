# MineCube 3D

把扫雷搬进一个可旋转的三维立方体。规则针对三维重写过，没有直接沿用 2D 的邻域。

同一套玩法有两个实现：**Godot 桌面版**（原型，`prototypes/minecube`）和 **Web 版**（Three.js，打包成单个 HTML，`web/`）。

Web 版 · v0.1.0 · Godot 版 · v0.5.0

在线试玩：[gaelthas.github.io/gaelthas/minecube](https://gaelthas.github.io/gaelthas/minecube/)

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

两个版本的默认映射一致，都可以改。

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

已揭示的数字方块会吃掉点击，不穿透。要挖内层，从方块之间的缝隙瞄——界面右下角的「间距」滑块可以拉开方块中心距（100%–200%），方块尺寸不变。

## Web 版

单个 HTML 文件，双击即玩，不需要服务器、不联网。Three.js、样式、六段音效、方块模型全部内联，约 780 KB。

```sh
cd web
npm install
npm run dev      # 开发，带热更新
npm run build    # 产出 dist/index.html（单文件）
```

构建产物 `web/dist/index.html` 已入库，也可以直接下载 [Releases](https://github.com/gaelthas/Minesweeper3D/releases) 里的附件。

调试用 `?seed=123` 固定局面，`window.minecube` 暴露了 `world`、`state`、`settings`、`ui`。

方块模型不用代码现搓：Web 版直接内联 Godot 版那份 Blender 产物（`assets/cube_rounded.glb`），
运行时用一个 40 行的 GLB 读取器取出顶点，不引 GLTFLoader。两个版本的模型因此完全一致。

## 微应用版（Discourse mapp）

同一份源码也能打成 [Discourse 微应用](https://github.com/linux-do/mapp-developer-guide) 要求的包。平台不是加载一个 HTML，而是把正文片段、脚本、样式分开注入，能力通过 SDK 提供。

```sh
cd web
MINI_APP_ID=<平台分配的应用 ID> MINI_APP_VERSION=1.0.0 npm run build:app
# 产物：build/package/app.zip
```

ZIP 里就是规范要求的五个基础文件加声明的资源：

```
manifest.json
index.html            正文片段，不含脚本/样式标签
app.js                IIFE
app.css
strings.json          zh_CN / en
assets/sfx/*.mp3      六个 CC0 音效
assets/models/cube.glb
```

两份产物共用一套源码，靠 `vite.config.js` / `vite.config.app.js` 里的 alias 切换实现：

| | 单文件版 | 微应用版 |
| --- | --- | --- |
| 资源 | `?url` 内联成 data URI | `sdk.assets.readBytes('assets/…')` |
| 设置存储 | 浏览器 `localStorage` | `sdk.localStorage`（需 `storage.read/write`） |
| 主题 | 固定浅色 | `sdk.theme`（需 `theme.read`），跟随社区深浅色 |
| 音效 | 内联字节直接解码 | 同上，需 `audio.webAudio` 权限 |
| 生命周期 | 无 | 首屏后调 `sdk.lifecycle.ready()` |

权限只申请实际用到的四项：`theme.read`、`storage.read`、`storage.write`、`audio.webAudio`。任一能力缺失都只降级，游戏照常可玩。

`sdk/` 是官方指南仓库的 SDK 副本（未发布到 npm，只能 `file:` 引用）。追踪上游更新时整体替换这个目录即可。

## Godot 版

需要 Godot 4.7.2（其他 4.x 未验证）。

```sh
godot --path prototypes/minecube
```

也可以直接用编辑器打开 `prototypes/minecube/project.godot`。默认盘面 5×5×5、38 颗雷（30% 密度），阶数可调到 3–13；13 阶全开实测 34.6 FPS，是当前节点数下的实际上限。

选项页管显示模式、分辨率、音量、垂直同步、帧率显示、鼠标三键功能，改动即时生效并写入 `user://settings.cfg`。

## 测试

两套实现各自有测试，都在仓库根执行。

```sh
# Web：逻辑层（node:test，纯函数，不依赖浏览器）
cd web && npm test

# Web：端到端（需要本机 Chromium 内核浏览器，macOS 默认找系统 Chrome）
cd web && npm run build && node scripts/e2e.mjs

# Godot：逻辑层与界面冒烟
godot --headless --path prototypes/minecube -s res://tests/logic_test.gd
godot --headless --path prototypes/minecube -s res://tests/ui_smoke.gd
```

Web 端的 e2e 用真实浏览器派发鼠标事件，覆盖揭示、三态标记、左右同按和弦、间距滑块、浮层开关、结算弹窗和控制台报错。

## 目录

```
doc/
  design.md              设计决策与踩过的坑（比 README 长得多）
  shots/                 Godot 版截图，由 tests/capture.gd 生成
prototypes/
  index.md               原型索引
  minecube/              Godot 实现
    assets/
      build_cube.py      用 Blender 生成削角方块模型
      cube_rounded.glb   产物，已入库
      sfx/               6 个 CC0 音效，来源见 CREDITS.md
    scenes/main.tscn
    scripts/             逻辑层、视图层、UI 各自独立
    tests/               逻辑自检、UI 冒烟、截图、平衡探针
    REPORT.md            概念原型报告（记录的是早期规则下的数据）
web/                     Three.js 实现
  src/
    logic.js             棋盘逻辑，不碰 DOM，可被 node 直接测
    cube-model.js        解析内联的 GLB，取出方块几何
    geometry.js          数字与标记的贴图
    scene.js             场景、相机、格子视图、拾取
    ui.js / style.css    DOM 界面
    main.js              流程与输入
  test/logic.test.js     逻辑层测试
  scripts/e2e.mjs        端到端测试
  dist/index.html        单文件产物
.github/workflows/
  ci.yml                 推送到 master 时跑测试与构建
  release.yml            推 v* 标签时构建并发布
```

## 发布

推一个 `v*` 标签，release workflow 会自动跑测试、构建单文件、把 `minecube3d-<tag>.html` 挂到 GitHub Release 上。

```sh
git tag v0.1.0 && git push origin v0.1.0
```

版本号只在 `web/package.json` 里改一次，构建时注入到界面；Godot 版的版本在 `prototypes/minecube/project.godot` 的 `config/version`。

## 已知状态

- 两套实现都还没做过完整的人工试玩评估，因此没有 PROCEED / PIVOT / KILL 结论。
- `REPORT.md` 里的平衡数据出自 26 邻域时代，和现在每面计数的规则不一致，只作历史记录看。当前规则的说明以 `doc/design.md` 为准。
- Godot 版只在 macOS 上构建和测试过。Web 版的 e2e 也只在本机 Chrome 跑过，CI 里只跑逻辑测试与构建。

## 许可

代码与文档采用 [MIT 许可](LICENSE)。

`prototypes/minecube/assets/sfx/` 下的音效全部来自 Freesound 的 CC0 素材，按 CC0 分发，署名与来源见该目录的 `CREDITS.md`。Web 版构建时把同一批文件内联进 HTML。

## 致谢

[LINUX DO Community](https://linux.do/)

Thanks to the Linux.do community for its support and contributions.
