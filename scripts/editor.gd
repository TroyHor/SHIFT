class_name LevelEditor
extends Control
## 游戏内编辑器：在游戏里直接画地图、摆人物和物件、改剧情文字，然后马上试玩。
## 改的是关卡场景本身（见 level_doc.gd），存下来就是 levels/ 里的 .tscn。

signal play_requested(level: Dictionary)
signal closed

const FONT := preload("res://assets/fonts/NotoSansSC-Subset.ttf")
const GameLogic := preload("res://scripts/game.gd")

const BOARD := Rect2(8, 76, 636, 556)
const PANEL := Rect2(652, 76, 300, 556)

const PEOPLE := ["", "detective", "inspector", "butler", "maid", "cook", "clerk", "conductor", "passenger", "porter"]
const THINGS := ["", "desk", "table", "chair", "crates", "plant", "horse", "snowman", "barrel", "cache", "cart",
	"bookshelf", "wardrobe", "safe", "rack", "candle", "logs", "book", "paper", "bed", "toolbox", "ice", "ashtray",
	"glove", "bottle"]

## 属性的中文名
const LABELS := {
	"kind": "类型", "era": "时代", "display_name": "名字", "label": "方块上的字", "sprite": "画法",
	"text": "碰到时的描述", "past_text": "烟雾里碰到时", "now_text": "留到现在后碰到时", "say": "说的话",
	"hint": "没有烟灰时的描述", "ask": "拿走之前的询问", "empty": "拿空以后",
	"amount": "给几撮烟丝", "clue": "证据 id", "pair": "对照配对名", "push": "能在过去推动",
	"persist": "从过去留到现在", "flammable": "会被蜡烛烧掉", "erases": "拿走后现在消失的东西（id）",
	"model": "模型（tin = 烟丝罐）", "small": "小物件，不挡路",
	"smoker": "烟民（会被烟灰缸引走）", "delay": "晚几步出发", "gift_flag": "送烟丝后立的标记",
	"gift_ask": "送烟丝前问", "gift_done": "送烟丝后说",
	"lie_vs": "对质：过去的自己（id）", "lie_clue": "对质得到的证据", "lie_text": "对质时说",
	"flag_name": "某标记成立后", "flag_clue": "改口得到的证据", "flag_text": "改口说",
	"now_say": "走完这一夜后说", "witness_of": "这一夜看见了谁（id）", "witness_clue": "作证得到的证据",
	"witness_text": "作证时说",
	"title": "标题", "theme": "选关界面的一句话", "intro": "开场白", "past_label": "烟雾里是什么时刻",
	"present_label": "现在是什么时刻", "tobacco": "开局烟丝", "style": "画风",
	"presence_clues": "在场证据（id）", "weapon_clues": "凶器证据（id）", "motive_clues": "动机证据（id）",
	"clue_names": "证据名字（每行 id=名字）", "suspects": "嫌疑人", "culprit": "凶手是第几个（从 0 数）",
	"win_text": "指认对了", "lose_text": "指认错了", "by": "谁去建造（人物 id）",
}
const ENUM_NAMES := {
	"npc": "人物", "inspector": "警长", "source": "烟丝源", "prints": "指纹", "cache": "暗格", "clue": "证物",
	"container": "容器", "crate": "家具", "candle": "蜡烛", "ice": "冰块", "compare": "对照物",
	"ashtray": "烟灰缸", "static": "摆设", "past": "只在过去", "present": "只在现在", "both": "过去现在都有",
	"brick": "砖墙", "planks": "木板", "lock": "门锁",
}
## 剧情页里列出的文字
const STORY_FIELDS := ["say", "text", "past_text", "now_text", "hint", "ask", "empty", "gift_ask", "gift_done",
	"lie_text", "flag_text", "now_say", "witness_text"]

const SCRIPT_GROUPS := ["文字", "物件", "人物：过去", "人物：现在", "人物：走完这一夜之后", "证据", "指认"]

enum Tool { SELECT, FLOOR, WALL, OUTDOOR, COLD, PLACE, LATER, START, MARK }

var world: Board3D
var doc: LevelDoc
var pv = GameLogic.new(0)  # 预览用的游戏状态
var tool := Tool.SELECT
var view_past := false
var selected: Node = null
var _sel_path := NodePath("")
var _drag_from = null
var _painting := false
var _hover = null
var _preview_dirty := false
var _preview_t := 0.0
var _confirm_leave := false
var _snap_field := ""  # 正在打字的字段：同一个字段连续打字只存一次撤销

var level_pick: OptionButton
var status: Label
var tool_btns := {}
var place_pick: OptionButton
var later_pick: OptionButton
var view_btn: Button
var tabs: TabContainer
var sel_box: VBoxContainer
var level_box: VBoxContainer
var story_box: VBoxContainer
var overlay: Control


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(960, 640)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = FONT
	th.default_font_size = 13
	theme = th


func _ready() -> void:
	_build_ui()


# ================================================================ 打开、存档

func open_level(path: String) -> void:
	if doc != null:
		doc.close()
	doc = LevelDoc.open(path)
	_after_open()


func new_level() -> void:
	if doc != null:
		doc.close()
	var n := 50
	var used := {}
	for p in Levels.paths():
		used[String(p).get_file().get_slice("_", 0)] = true
	while used.has(str(n)):
		n += 1
	doc = LevelDoc.blank("%d_new.tscn" % n)
	doc.dirty = true
	_after_open()
	_say("新建了一关。改好名字、画好地图后按 保存。")


func _after_open() -> void:
	selected = null
	_sel_path = NodePath("")
	_confirm_leave = false
	_refresh_level_pick()
	_build_level_tab()
	_build_story_tab()
	_build_sel_tab()
	_rebuild_preview()
	if Levels.saves_to_project():
		_say("存档会直接写进项目的 levels/ 文件夹。")
	else:
		_say("网页版：存档只留在这个浏览器里。要进项目请用 Mac 版编辑。")


func _save() -> void:
	var p := doc.save()
	if p == "":
		_say("存档失败。")
		return
	_refresh_level_pick()
	_say("已保存：" + p.get_file() + ("（项目 levels/）" if Levels.saves_to_project() else "（本机）"))


func _refresh_level_pick() -> void:
	level_pick.clear()
	var cur := -1
	for i in Levels.count():
		var f := String(Levels.paths()[i]).get_file()
		level_pick.add_item("%s  %s" % [f.get_basename(), Levels.info(i).title])
		if doc != null and f == doc.file_name:
			cur = i
	if cur < 0 and doc != null:
		level_pick.add_item("%s（未保存）" % doc.file_name.get_basename())
		cur = level_pick.item_count - 1
	level_pick.select(cur)


# ================================================================ 预览

func _rebuild_preview() -> void:
	_preview_dirty = false
	var L := doc.to_level()
	if L.map.is_empty():
		return
	pv.load_data(L)
	pv.reveal_all = view_past
	pv.s.cloud = view_past
	pv.s.msg = ""
	world.game = pv
	world.board = BOARD
	world.refresh()
	world.set_hover(Vector2i.ZERO, false, false)
	overlay.queue_redraw()


func _changed(struct := false) -> void:
	_confirm_leave = false
	if struct:
		_rebuild_preview()
		_build_story_tab()
	else:
		_preview_dirty = true
		_preview_t = 0.3


func _process(delta: float) -> void:
	if not visible or doc == null:
		return
	if _preview_dirty:
		_preview_t -= delta
		if _preview_t <= 0:
			_rebuild_preview()
	overlay.queue_redraw()


# ================================================================ 界面

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b0c10")
	bg.position = Vector2.ZERO
	bg.size = Vector2(960, 70)
	add_child(bg)
	var side := ColorRect.new()
	side.color = Color("#101218")
	side.position = PANEL.position - Vector2(4, 4)
	side.size = PANEL.size + Vector2(12, 12)
	add_child(side)

	var top := HBoxContainer.new()
	top.position = Vector2(8, 6)
	top.size = Vector2(944, 28)
	add_child(top)
	level_pick = OptionButton.new()
	level_pick.custom_minimum_size = Vector2(260, 0)
	level_pick.item_selected.connect(_on_level_picked)
	top.add_child(level_pick)
	_btn(top, "新建", new_level)
	_btn(top, "保存", _save, "Ctrl+S")
	_btn(top, "撤销", _undo, "Ctrl+Z")
	_btn(top, "试玩", _play, "F5：从起点试玩，Esc 回到编辑器")
	_btn(top, "返回", _leave, "回到选关界面")
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_theme_color_override("font_color", Color("#e0b46a"))
	status.clip_text = true
	top.add_child(status)

	var bar := HBoxContainer.new()
	bar.position = Vector2(8, 38)
	bar.size = Vector2(944, 28)
	add_child(bar)
	var group := ButtonGroup.new()
	for t in [[Tool.SELECT, "选择/拖动"], [Tool.FLOOR, "地面"], [Tool.WALL, "墙"], [Tool.OUTDOOR, "室外"],
			[Tool.COLD, "冷地"], [Tool.START, "起点"], [Tool.MARK, "路线点"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_set_tool.bind(t[0]))
		bar.add_child(b)
		tool_btns[t[0]] = b
	tool_btns[Tool.SELECT].button_pressed = true
	tool_btns[Tool.MARK].tooltip_text = "先选中过去的人物（加路线）、烟灰缸（座位）或有建造者的建造（走到哪），再点格子；右键删掉最后一个"
	var pb := Button.new()
	pb.text = "放："
	pb.toggle_mode = true
	pb.button_group = group
	pb.pressed.connect(_set_tool.bind(Tool.PLACE))
	bar.add_child(pb)
	tool_btns[Tool.PLACE] = pb
	place_pick = OptionButton.new()
	for tp in LevelDoc.TEMPLATES:
		place_pick.add_item(tp[0])
	place_pick.item_selected.connect(func(_i): _set_tool(Tool.PLACE); pb.button_pressed = true)
	bar.add_child(place_pick)
	var lb := Button.new()
	lb.text = "建造："
	lb.toggle_mode = true
	lb.button_group = group
	lb.pressed.connect(_set_tool.bind(Tool.LATER))
	bar.add_child(lb)
	tool_btns[Tool.LATER] = lb
	later_pick = OptionButton.new()
	for k in ["brick", "planks", "lock"]:
		later_pick.add_item(ENUM_NAMES[k])
	later_pick.item_selected.connect(func(_i): _set_tool(Tool.LATER); lb.button_pressed = true)
	bar.add_child(later_pick)
	view_btn = Button.new()
	view_btn.text = "看：现在"
	view_btn.tooltip_text = "切换看现在的样子 / 烟雾里过去的样子"
	view_btn.pressed.connect(_toggle_view)
	bar.add_child(view_btn)

	overlay = Control.new()
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(960, 640)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	var board := Control.new()
	board.position = BOARD.position
	board.size = BOARD.size
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.gui_input.connect(_board_input)
	board.mouse_exited.connect(func(): _hover = null)
	add_child(board)

	tabs = TabContainer.new()
	tabs.position = PANEL.position
	tabs.size = PANEL.size
	add_child(tabs)
	sel_box = _tab("选中")
	level_box = _tab("关卡")
	story_box = _tab("剧情")


func _tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	return box


func _btn(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _say(msg: String) -> void:
	if status != null:
		status.text = msg


func _set_tool(t: int) -> void:
	tool = t
	match t:
		Tool.FLOOR, Tool.WALL, Tool.OUTDOOR, Tool.COLD:
			_say("左键拖动来画格子。")
		Tool.PLACE:
			_say("点一个格子放下：" + LevelDoc.TEMPLATES[place_pick.selected][0])
		Tool.LATER:
			_say("点一个格子放下后来的建造：现在挡路，烟雾里能穿过。")
		Tool.START:
			_say("点一个格子，侦探从那里开局。")
		Tool.MARK:
			var k := LevelDoc.marker_kind(selected) if selected != null else ""
			_say({"route": "点格子给这个人加路线，右键删掉最后一站。", "seat": "点格子定烟灰缸的座位。",
				"at": "点格子定建造者要走到哪里。"}.get(k, "先在 选择 里选中一个过去的人物、烟灰缸或有建造者的建造。"))
		_:
			_say("点格子选中东西，按住拖到别的格子。同一格再点一下换下一个。Delete 删除。")


func _toggle_view() -> void:
	view_past = not view_past
	view_btn.text = "看：烟雾里" if view_past else "看：现在"
	_rebuild_preview()


func _on_level_picked(i: int) -> void:
	if i >= Levels.count():
		return
	if doc != null and doc.dirty and not _confirm_leave:
		_confirm_leave = true
		_refresh_level_pick()
		_say("这一关还没保存。再选一次就放弃改动。")
		return
	open_level(Levels.paths()[i])


func _undo() -> void:
	if not doc.undo():
		_say("没有可以撤销的了。")
		return
	selected = doc.root.get_node_or_null(_sel_path) if _sel_path != NodePath("") else null
	_snap_field = ""
	_build_level_tab()
	_build_sel_tab()
	_changed(true)
	_say("撤销了一步。")


func _play() -> void:
	var L := doc.to_level()
	if L.ents.is_empty() and L.map.is_empty():
		return
	play_requested.emit(L)


func _leave() -> void:
	if doc != null and doc.dirty and not _confirm_leave:
		_confirm_leave = true
		_say("还没保存。再按一次 返回 就放弃改动。")
		return
	if doc != null:
		doc.close()
		doc = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or doc == null or not (event is InputEventKey and event.pressed):
		return
	var k: int = event.keycode
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	if ctrl and k == KEY_S:
		_save()
	elif ctrl and k == KEY_Z:
		_undo()
	elif k == KEY_F5:
		_play()
	elif k in [KEY_DELETE, KEY_BACKSPACE] and selected != null and selected != doc.start():
		doc.snapshot()
		doc.remove(selected)
		selected = null
		_sel_path = NodePath("")
		_build_sel_tab()
		_changed(true)
	elif k == KEY_ESCAPE:
		_leave()
	else:
		return
	get_viewport().set_input_as_handled()


# ================================================================ 在地图上点

func _cell_at(local: Vector2):
	return world.ground_cell(local + BOARD.position)


func _in_map(p) -> bool:
	if p == null:
		return false
	var sz := doc.size()
	return p.x >= 0 and p.y >= 0 and p.x < sz.x and p.y < sz.y


func _board_input(ev: InputEvent) -> void:
	if doc == null:
		return
	if ev is InputEventMouseMotion:
		var p = _cell_at(ev.position)
		_hover = p if _in_map(p) else null
		if _painting and _hover != null:
			_paint(_hover)
		return
	if not (ev is InputEventMouseButton):
		return
	var p = _cell_at(ev.position)
	if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		if tool == Tool.MARK and selected != null:
			var k := LevelDoc.marker_kind(selected)
			if k != "":
				doc.snapshot()
				if doc.pop_marker(selected, k):
					_changed(true)
		return
	if ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if not ev.pressed:
		_painting = false
		if _drag_from != null and selected != null and _in_map(p) and p != _drag_from:
			doc.snapshot()
			doc.move_to(selected, p)
			_changed(true)
			_build_sel_tab()
		_drag_from = null
		return
	if not _in_map(p):
		return
	match tool:
		Tool.SELECT:
			_select_at(p)
			_drag_from = p if selected != null else null
		Tool.FLOOR, Tool.WALL, Tool.OUTDOOR, Tool.COLD:
			doc.snapshot()
			_painting = true
			_paint(p)
		Tool.PLACE:
			doc.snapshot()
			var e := doc.add_ent(LevelDoc.TEMPLATES[place_pick.selected][1], p)
			_select(e)
			_changed(true)
		Tool.LATER:
			doc.snapshot()
			var l := doc.add_later(["brick", "planks", "lock"][later_pick.selected], p)
			doc.paint(p, LevelDoc.T_FLOOR)  # 建造立在地面上
			_select(l)
			_changed(true)
		Tool.START:
			doc.snapshot()
			doc.move_to(doc.start(), p)
			_changed(true)
		Tool.MARK:
			var k := LevelDoc.marker_kind(selected) if selected != null else ""
			if k == "":
				_set_tool(Tool.MARK)
				return
			doc.snapshot()
			doc.add_marker(selected, k, p)
			_changed(true)


func _paint(p: Vector2i) -> void:
	var code: int = {Tool.FLOOR: LevelDoc.T_FLOOR, Tool.WALL: LevelDoc.T_WALL, Tool.OUTDOOR: LevelDoc.T_OUTDOOR,
		Tool.COLD: LevelDoc.T_COLD}[tool]
	if doc.tile(p) == code:
		return
	doc.paint(p, code)
	_rebuild_preview()


## 同一格有几样东西时，再点一下换下一个；先选当前视图里看得到的那个时代
func _select_at(p: Vector2i) -> void:
	var list := doc.things_at(p)
	if list.is_empty():
		_select(null)
		return
	var era := "past" if view_past else "present"
	list.sort_custom(func(a, b): return _era_rank(a, era) < _era_rank(b, era))
	var i := list.find(selected)
	_select(list[(i + 1) % list.size()] if i >= 0 else list[0])


func _era_rank(n: Node, era: String) -> int:
	if n is LevelEnt:
		return 0 if n.era == era or n.era == "both" else 1
	return 2


func _select(n: Node) -> void:
	selected = n
	_sel_path = doc.root.get_path_to(n) if n != null else NodePath("")
	_snap_field = ""
	_build_sel_tab()
	tabs.current_tab = 0
	if tool == Tool.MARK:
		_set_tool(Tool.MARK)


# ================================================================ 地图上的标注

func _corners(p: Vector2i, inset := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for o in [Vector2(inset, inset), Vector2(1 - inset, inset), Vector2(1 - inset, 1 - inset), Vector2(inset, 1 - inset)]:
		pts.append(world.screen_v(Vector3(p.x + o.x, 0.02, p.y + o.y)))
	return pts


func _outline(p: Vector2i, col: Color, w := 2.0, inset := 0.04) -> void:
	var c := _corners(p, inset)
	c.append(c[0])
	overlay.draw_polyline(c, col, w)


func _ctext(s: String, at: Vector2, col: Color, size := 12) -> void:
	var w := FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	overlay.draw_rect(Rect2(at - Vector2(w / 2 + 3, 9), Vector2(w + 6, 17)), Color(0, 0, 0, 0.7))
	overlay.draw_string(FONT, at + Vector2(-w / 2, 5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_overlay() -> void:
	if doc == null or not visible:
		return
	overlay.draw_rect(Rect2(BOARD.position, BOARD.size), Color(0.88, 0.71, 0.42, 0.25), false, 1.0)
	var gold := Color("#e0b46a")
	# 起点
	var sp := doc.cell(doc.start())
	_outline(sp, gold, 2.0, 0.1)
	_ctext("起点", world.screen(sp, 0.05) + Vector2(0, 14), gold, 11)
	# 后来的建造：烟雾里看不到，用红框标出来
	for l in doc.laters():
		var lp := doc.cell(l)
		_outline(lp, Color(1, 0.45, 0.35, 0.9), 2.0, 0.08)
		if view_past:
			_ctext("后来" + String(l.display_name), world.screen(lp, 0.3), Color(1, 0.6, 0.5), 11)
		for m in doc.markers(l, "at"):
			overlay.draw_line(world.screen(lp, 0.1), world.screen(doc.cell(m), 0.1), Color(1, 0.45, 0.35, 0.8), 1.5)
			_ctext("到", world.screen(doc.cell(m), 0.1), Color(1, 0.6, 0.5), 11)
	# 另一个时代的东西：只标个名字
	for e in doc.ents():
		if e.era == "both" or (e.era == "past") == view_past:
			continue
		var nm: String = e.display_name if e.display_name != "" else String(e.name)
		_ctext(("过去：" if e.era == "past" else "现在：") + nm, world.screen(doc.cell(e), 0.2),
			Color(gold, 0.7) if e.era == "past" else Color(0.55, 0.7, 0.95, 0.8), 10)
	# 选中的东西、它的路线和座位
	if selected != null and is_instance_valid(selected):
		var p := doc.cell(selected)
		_outline(p, Color.WHITE, 3.0, 0.02)
		var prev := world.screen(p, 0.1)
		var i := 1
		for m in doc.markers(selected, "route"):
			var q := world.screen(doc.cell(m), 0.1)
			overlay.draw_line(prev, q, gold, 2.0)
			overlay.draw_circle(q, 9, gold)
			overlay.draw_string(FONT, q + Vector2(-4 if i < 10 else -7, 5), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#2a2018"))
			prev = q
			i += 1
		for m in doc.markers(selected, "seat"):
			overlay.draw_line(prev, world.screen(doc.cell(m), 0.1), Color(gold, 0.6), 1.5)
			_ctext("座", world.screen(doc.cell(m), 0.1), gold, 11)
	if _hover != null:
		_outline(_hover, Color(1, 1, 1, 0.45), 1.5, 0.0)
		_ctext("%d, %d" % [_hover.x, _hover.y], Vector2(BOARD.end.x - 30, BOARD.position.y + 12), Color(1, 1, 1, 0.6), 11)


# ================================================================ 属性面板

func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _header(box: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#e0b46a"))
	box.add_child(l)


func _note(box: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(270, 0)
	l.add_theme_color_override("font_color", Color("#8a8f9e"))
	l.add_theme_font_size_override("font_size", 12)
	box.add_child(l)


## 节点上所有在检查器里能改的属性，按组分好
func _props(n: Object) -> Array:
	var out: Array = []
	var group := ""
	for pr in n.get_property_list():
		if pr.usage & PROPERTY_USAGE_GROUP:
			group = pr.name
			continue
		if pr.usage & PROPERTY_USAGE_CATEGORY:
			group = ""
			continue
		if not (pr.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (pr.usage & PROPERTY_USAGE_EDITOR):
			continue
		# 只认关卡脚本自己的分组；Node2D 的 Transform 之类不算
		pr["group"] = group if group in SCRIPT_GROUPS else ""
		out.append(pr)
	return out


func _field(box: Control, n: Object, pr: Dictionary, struct_change := false) -> void:
	var key: String = pr.name
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	box.add_child(row)
	var lab := Label.new()
	lab.text = LABELS.get(key, key)
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color("#b8bcc8"))
	var v = n.get(key)
	var on_set := func(val):
		if _snap_field != "%s:%s" % [n.get_instance_id(), key]:
			doc.snapshot()
			_snap_field = "%s:%s" % [n.get_instance_id(), key]
		n.set(key, val)
		_changed(struct_change)
	match pr.type:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.text = LABELS.get(key, key)
			cb.button_pressed = v
			cb.toggled.connect(func(b): _snap_field = ""; on_set.call(b); _snap_field = "")
			row.add_child(cb)
			return
		TYPE_INT:
			row.add_child(lab)
			if pr.hint == PROPERTY_HINT_ENUM:
				var ob := OptionButton.new()
				for s in String(pr.hint_string).split(","):
					ob.add_item(s.get_slice(":", 0))
				ob.select(v)
				ob.item_selected.connect(func(i): _snap_field = ""; on_set.call(i); _snap_field = "")
				row.add_child(ob)
			else:
				var sb := SpinBox.new()
				sb.min_value = 0
				sb.max_value = 99
				sb.value = v
				sb.value_changed.connect(func(x): on_set.call(int(x)))
				row.add_child(sb)
		TYPE_STRING:
			row.add_child(lab)
			if pr.hint == PROPERTY_HINT_ENUM:
				var opts := String(pr.hint_string).split(",")
				var ob := OptionButton.new()
				for s in opts:
					ob.add_item("%s %s" % [ENUM_NAMES.get(s, ""), s])
				ob.select(maxi(0, opts.find(v)))
				ob.item_selected.connect(func(i):
					_snap_field = ""
					on_set.call(opts[i])
					_snap_field = ""
					_build_sel_tab())
				row.add_child(ob)
			elif key == "sprite":
				var opts: Array = PEOPLE if (n is LevelEnt and n.kind in ["npc", "inspector"]) else THINGS
				var ob := OptionButton.new()
				for s in opts:
					ob.add_item(s if s != "" else "（按 id 猜）")
				if not opts.has(v):
					ob.add_item(v)
					opts = opts + [v]
				ob.select(opts.find(v))
				ob.item_selected.connect(func(i): _snap_field = ""; on_set.call(opts[i]); _snap_field = "")
				row.add_child(ob)
			elif pr.hint == PROPERTY_HINT_MULTILINE_TEXT:
				var te := TextEdit.new()
				te.text = v
				te.custom_minimum_size = Vector2(270, 54)
				te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				te.text_changed.connect(func(): on_set.call(te.text))
				row.add_child(te)
			else:
				var le := LineEdit.new()
				le.text = v
				le.text_changed.connect(func(s): on_set.call(s))
				row.add_child(le)
		TYPE_PACKED_STRING_ARRAY:
			row.add_child(lab)
			var le := LineEdit.new()
			le.text = "，".join(v)
			le.placeholder_text = "用逗号隔开"
			le.text_changed.connect(func(s): on_set.call(_split(s)))
			row.add_child(le)
		TYPE_DICTIONARY:
			row.add_child(lab)
			var te := TextEdit.new()
			var lines: Array = []
			for k in v:
				lines.append("%s=%s" % [k, v[k]])
			te.text = "\n".join(lines)
			te.custom_minimum_size = Vector2(270, 70)
			te.text_changed.connect(func():
				var d := {}
				for line in te.text.split("\n"):
					if line.contains("="):
						d[line.get_slice("=", 0).strip_edges()] = line.substr(line.find("=") + 1).strip_edges()
				on_set.call(d))
			row.add_child(te)
		_:
			lab.text += "（这里改不了）"
			row.add_child(lab)


static func _split(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in s.replace("，", ",").replace("、", ",").split(","):
		if part.strip_edges() != "":
			out.append(part.strip_edges())
	return out


func _id_field(box: Control, n: Node) -> void:
	var lab := Label.new()
	lab.text = "id（别的东西用它指向这个）"
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color("#b8bcc8"))
	box.add_child(lab)
	var le := LineEdit.new()
	le.text = String(n.name)
	le.text_submitted.connect(func(s): _rename(n, le))
	le.focus_exited.connect(func(): _rename(n, le))
	box.add_child(le)


func _rename(n: Node, le: LineEdit) -> void:
	if le.text == String(n.name):
		return
	doc.snapshot()
	le.text = doc.rename(n, le.text)
	_sel_path = doc.root.get_path_to(n)
	_changed(true)


## 这一组属性对这种东西有没有用
static func _group_fits(n: Object, group: String) -> bool:
	if not (n is LevelEnt):
		return true
	var person: bool = n.kind in ["npc", "inspector"]
	if group.begins_with("人物"):
		return n.kind == "npc"
	if group == "物件":
		return not person
	return true


func _build_sel_tab() -> void:
	_clear(sel_box)
	var n := selected
	if n == null or not is_instance_valid(n):
		_note(sel_box, "在地图上点一个人、物件、建造或起点。\n\n工具栏：\n· 地面 / 墙 / 室外 / 冷地：拖动画格子\n· 放：选一种东西，点格子放下\n· 建造：后来才砌的墙、钉的木板、上的锁\n· 路线点：给过去的人物加路线\n· 看：现在 / 烟雾里，切换两个时代\n\nCtrl+Z 撤销  Ctrl+S 保存  F5 试玩")
		return
	if n == doc.start():
		_header(sel_box, "起点")
		_note(sel_box, "侦探从这一格开局。用 选择 拖动，或用 起点 工具点格子。")
		return
	var title := "后来的建造" if n is LevelLater else "%s · %s" % [ENUM_NAMES.get(n.kind, n.kind), ENUM_NAMES.get(n.era, n.era)]
	_header(sel_box, title)
	_note(sel_box, "在第 %d, %d 格。" % [doc.cell(n).x, doc.cell(n).y])
	_id_field(sel_box, n)
	var group := ""
	for pr in _props(n):
		if not _group_fits(n, pr.group):
			continue
		if pr.group != group:
			group = pr.group
			if group != "":
				_header(sel_box, "— " + group + " —")
		_field(sel_box, n, pr, pr.name in ["kind", "era", "push", "persist", "small", "model", "sprite", "smoker", "by"])
	var mk := LevelDoc.marker_kind(n)
	if mk != "":
		_note(sel_box, {"route": "路线：%d 站。用 路线点 工具在地图上点。", "seat": "座位：用 路线点 工具点一格。",
			"at": "建造者要走到的格子：用 路线点 工具点一格。"}[mk] % ([doc.markers(n, "route").size()] if mk == "route" else []))
	var del := Button.new()
	del.text = "删除这个"
	del.pressed.connect(func():
		doc.snapshot()
		doc.remove(n)
		selected = null
		_sel_path = NodePath("")
		_build_sel_tab()
		_changed(true))
	sel_box.add_child(del)


func _build_level_tab() -> void:
	_clear(level_box)
	_header(level_box, "文件名（开头的数字决定顺序）")
	var fn := LineEdit.new()
	fn.text = doc.file_name.get_basename()
	fn.text_changed.connect(func(s):
		doc.file_name = s.strip_edges().replace("/", "_") + ".tscn"
		doc.dirty = true)
	level_box.add_child(fn)
	_header(level_box, "地图大小（宽 × 高）")
	var row := HBoxContainer.new()
	level_box.add_child(row)
	var sz := doc.size()
	var w := SpinBox.new()
	w.min_value = 3
	w.max_value = 40
	w.value = sz.x
	var h := SpinBox.new()
	h.min_value = 3
	h.max_value = 30
	h.value = sz.y
	row.add_child(w)
	row.add_child(h)
	var apply := Button.new()
	apply.text = "改大小"
	apply.pressed.connect(func():
		doc.snapshot()
		doc.resize(Vector2i(int(w.value), int(h.value)))
		_changed(true))
	row.add_child(apply)
	var group := ""
	for pr in _props(doc.root):
		if pr.group != group:
			group = pr.group
			if group != "":
				_header(level_box, "— " + group + " —")
		_field(level_box, doc.root, pr)


## 剧情页：这一关所有的文字放在一起，从上往下就是一份剧本
func _build_story_tab() -> void:
	_clear(story_box)
	var r: LevelDef = doc.root
	_header(story_box, "开场")
	for k in ["intro"]:
		_field(story_box, r, _prop(r, k))
	for e in doc.ents():
		var fields: Array = []
		for k in STORY_FIELDS:
			var v = e.get(k)
			if v != "" or (k == "say" and e.kind == "npc"):
				fields.append(k)
		if fields.is_empty():
			continue
		var nm: String = e.display_name if e.display_name != "" else String(e.name)
		_header(story_box, "%s（%s · %s）" % [nm, ENUM_NAMES.get(e.kind, e.kind), ENUM_NAMES.get(e.era, e.era)])
		for k in fields:
			_field(story_box, e, _prop(e, k))
	for l in doc.laters():
		_header(story_box, "%s（后来的建造）" % l.display_name)
		_field(story_box, l, _prop(l, "text"))
	_header(story_box, "结局")
	for k in ["win_text", "lose_text"]:
		_field(story_box, r, _prop(r, k))
	_note(story_box, "这里只列出已经有文字的地方。要给别的东西加文字，在 选中 页里填。")


func _prop(n: Object, key: String) -> Dictionary:
	for pr in n.get_property_list():
		if pr.name == key:
			return pr
	return {"name": key, "type": TYPE_STRING, "hint": 0, "hint_string": ""}
