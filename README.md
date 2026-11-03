# SHIFT · 烟斗侦探

GitHub Game Off 2026（主题 **SHIFT**）参赛作品。

一位侦探能用烟斗吐出的烟穿越时间：按下 **Shift**，身边 3x3 的格子变回案发当晚。他同时和过去、现在互动，以此破案。

共三个案件：反锁的书房（空间）、雪夜旅馆（时间流逝）、末班列车（人的去向）。关卡数据在 `scripts/levels.gd`，通用规则在 `scripts/game.gd`。

设计文档见 [docs/design.md](docs/design.md)。

## 操作

| 按键 | 作用 |
|---|---|
| 方向键 / WASD | 移动；撞上人或物即互动（对话、拿取、推动） |
| Shift | 花一撮烟丝吐一口烟，打开通往过去的 3x3 窗口 |
| Z | 撤销 |
| Backspace | 重来 |
| 1 / 2 | 出现选项时选择；选关界面直接进入案件 |
| Esc | 取消选项；不在选项里时回到选关 |
| Enter | 结案后进入下一个案件 |

## 开发

需要 [Godot 4.4](https://godotengine.org/download)（标准版，非 .NET）。

```sh
# 打开编辑器
godot -e --path .

# 运行逻辑测试（无界面）
godot --headless --path . --script res://tests/test_game.gd

# 导出（需要先安装 4.4.1 导出模板）
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . --export-release "macOS" build/mac/SHIFT-PipeDetective.zip
```

`assets/fonts/` 里是 Noto Sans SC（正文）和 Noto Serif SC（标题）的子集，只包含代码里用到的字。改了文字后要重新生成，否则新字会显示成方块：

```sh
pip install fonttools
python3 tools/subset_font.py <NotoSansSC 完整字体路径> <NotoSerifSC 完整字体路径>
```

字体以 SIL Open Font License 授权，见 `assets/fonts/OFL.txt`。
