# SHIFT · 烟斗侦探

GitHub Game Off 2026（主题 **SHIFT**）参赛作品。

一位侦探能用烟斗吐出的烟穿越时间：按下 **Shift**，身边 3x3 的格子变回案发当晚。他同时和过去、现在互动，以此破案。

共三个案件：反锁的书房（空间）、雪夜旅馆（时间流逝）、末班列车（人的去向）。每关是 `levels/` 里的一个场景，通用规则在 `scripts/game.gd`。

设计文档见 [docs/design.md](docs/design.md)。

## 操作

| 按键 | 作用 |
|---|---|
| 方向键 / WASD | 移动。墙、后来的建造和家具挡路；人和小物件不挡路。吐烟时脚下过去有东西，会被挤到旁边 |
| 鼠标左键 | 走到旁边（周围一圈或脚下）点击人或物来互动：对话、拿取、推动（推要站在正侧面） |
| Shift | 花一撮烟丝吐一口烟，打开通往过去的 3x3 窗口 |
| Z | 撤销 |
| Backspace | 重来 |
| 1 / 2 | 出现选项时选择；选关界面直接进入案件 |
| Esc | 取消选项；不在选项里时回到选关 |
| Enter | 结案后进入下一个案件 |

## 编辑关卡

在 Godot 里打开 `levels/10_case1.tscn`（或别的关卡），场景里有四部分：

| 节点 | 作用 | 怎么改 |
|---|---|---|
| 根节点（Case1） | 标题、开场白、时刻、开局烟丝、证据分类、嫌疑人和凶手 | 选中后在右边的检查器里填 |
| Map | 墙和地面 | 选中后在下方的瓦片面板里选格子画：室内地面、墙、室外地面、冷地面（冰块在这里不化） |
| Start | 侦探的开局位置 | 拖动 |
| Later | 后来的建造（砖墙、木板、门锁） | 复制一个改属性；填了 by 的，再拖它的 At 子节点到那个人要走到的格子 |
| Ents | 人物和物件，节点名就是 id | 拖到哪一格就在哪一格；属性在检查器里填。人物的路线是 Route 子节点，按顺序走；烟灰缸的座位是 Seat 子节点 |

- 编辑器里是 2D 平面图（画法和旧版游戏一样），游戏里会自动搭成 3D；左上角金色三角是"只在过去"，蓝色是"只在现在"。
- 按 **F6** 直接试玩当前打开的关卡。
- 新建一关：复制一个关卡场景、改名（例如 `40_case4.tscn`）。`levels/` 里的场景按文件名排序，前面的数字决定顺序（`01`–`04` 是引导关，`10`/`20`/`30` 是三个案件，中间留了空位可以插关），自动出现在选关界面；文件名以 `_` 开头的不会出现，可以当草稿。
- 引导关只需要一类证据：根节点里另外两类留空就行。
- 关卡里写了新的中文字，桌面版和编辑器会先借用系统字体显示；网页版要重新运行下面的 `tools/subset_font.py`（它会扫描 `scripts/` 和 `levels/` 里用到的字）。
- 每种类型和属性的含义见机制手册。

## 开发

需要 [Godot 4.7](https://godotengine.org/download)（标准版，非 .NET）。

```sh
# 打开编辑器
godot -e --path .

# 运行逻辑测试（无界面）
godot --headless --path . --script res://tests/test_game.gd

# 导出（需要先安装 4.7.2 导出模板）
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . --export-release "macOS" build/mac/SHIFT-PipeDetective.zip
```

`assets/fonts/` 里是 Noto Sans SC（正文）和 Noto Serif SC（标题）的子集，只包含代码里用到的字。改了文字后要重新生成，否则新字会显示成方块：

```sh
pip install fonttools
python3 tools/subset_font.py <NotoSansSC 完整字体路径> <NotoSerifSC 完整字体路径>
```

字体以 SIL Open Font License 授权，见 `assets/fonts/OFL.txt`。
