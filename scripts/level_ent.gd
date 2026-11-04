@tool
class_name LevelEnt
extends Node2D
## 关卡里的一个人物或物件。节点名就是它的 id（别的物件用这个名字指向它）。
## 拖到哪一格就在哪一格；属性在右边的检查器里填，没用到的留空即可。
## 人物的路线：加 LevelMarker 子节点（what = route），按顺序走；烟灰缸的座位：LevelMarker（what = seat）。

const TILE := 32

## 类型，见机制手册"物件类型一览"
@export_enum("npc", "inspector", "source", "prints", "cache", "clue", "container", "crate", "candle", "ice", "compare", "ashtray", "static") var kind := "static":
	set(v):
		kind = v
		queue_redraw()
## past：只在烟雾里；present：只在现在；both：两边都有
@export_enum("past", "present", "both") var era := "both":
	set(v):
		era = v
		queue_redraw()
## 名字（人物名牌、推动时的提示）
@export var display_name := ""
## 没有专门画法时，方块上显示的字
@export var label := ""
## 画法。留空则按 id 猜。人物：detective inspector butler maid cook clerk conductor passenger porter；
## 物件：desk table chair crates plant horse snowman barrel cache cart bookshelf wardrobe safe rack candle logs book paper bed toolbox ice ashtray
@export var sprite := "":
	set(v):
		sprite = v
		queue_redraw()

@export_group("文字")
## 碰到时的描述（拿到证据、拿到烟丝时也显示这句）
@export_multiline var text := ""
## 在烟雾里碰到时的描述（摆设用）
@export_multiline var past_text := ""
## 从过去留到现在后，碰到时的描述
@export_multiline var now_text := ""
## 人物说的话
@export_multiline var say := ""
## 指纹：没有烟灰时的描述
@export_multiline var hint := ""
## 过去的烟丝源有 erases 时，拿之前的询问
@export_multiline var ask := ""
## 容器：拿空以后的描述
@export_multiline var empty := ""

@export_group("物件")
## 烟丝源：给几撮
@export var amount := 0
## 证据 id（指纹、暗格、证物、容器）
@export var clue := ""
## 对照物：两件配成一对，填同一个名字
@export var pair := ""
## 能在过去推动
@export var push := false
## 从过去留到现在
@export var persist := false
## 会被点燃的蜡烛烧掉
@export var flammable := false
## 过去的烟丝源：拿走以后，现在哪些东西（填 id）会消失
@export var erases: PackedStringArray
## 填 tin 就画成烟丝罐
@export var model := ""

@export_group("人物：过去")
## 烟民：会被放了烟丝的烟灰缸引走
@export var smoker := false
## 晚几步才出发
@export var delay := 0
## 送他一撮烟丝后立起的标记名（留空则不能送）
@export var gift_flag := ""
@export_multiline var gift_ask := ""
@export_multiline var gift_done := ""

@export_group("人物：现在")
## 对质：过去的自己（填 id）出现在烟雾里时，碰现在的他就拿到证据
@export var lie_vs := ""
@export var lie_clue := ""
@export_multiline var lie_text := ""
## 过去某个标记成立后的新证词
@export var flag_name := ""
@export var flag_clue := ""
@export_multiline var flag_text := ""

@export_group("人物：走完这一夜之后")
## 有路线（或是烟民）的过去人物，现在会在路线终点，说这句话
@export_multiline var now_say := ""
## 这一夜看见了谁（填 id），就能作证
@export var witness_of := ""
@export var witness_clue := ""
@export_multiline var witness_text := ""


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var snap := (position / TILE).round() * TILE
	if snap != position:
		position = snap
	queue_redraw()


func _markers(what: String) -> Array:
	var out: Array = []
	for c in get_children():
		if c is LevelMarker and c.what == what:
			out.append(c)
	return out


func walks() -> bool:
	return kind == "npc" and era == "past" and (smoker or not _markers("route").is_empty())


func to_dict() -> Dictionary:
	var d := {"id": String(name), "kind": kind, "era": era, "pos": LevelDef.cell_of(self), "label": label}
	var strings := {"name": display_name, "sprite": sprite, "text": text, "past_text": past_text,
		"now_text": now_text, "say": say, "hint": hint, "ask": ask, "empty": empty,
		"clue": clue, "pair": pair, "model": model}
	for k in strings:
		if strings[k] != "":
			d[k] = strings[k]
	if amount != 0:
		d["amount"] = amount
	for k in ["push", "persist", "flammable", "smoker"]:
		if get(k):
			d[k] = true
	if not erases.is_empty():
		d["erases"] = Array(erases)
	if gift_flag != "":
		d["gift"] = {"flag": gift_flag, "ask": gift_ask, "done": gift_done}
	if lie_vs != "":
		d["lie"] = {"vs": lie_vs, "clue": lie_clue, "text": lie_text}
	if flag_name != "":
		d["flag"] = {"name": flag_name, "clue": flag_clue, "text": flag_text}
	var seats := _markers("seat")
	if not seats.is_empty():
		d["seat"] = LevelDef.cell_of(seats[0])
	if walks():
		var route: Array = []
		for m in _markers("route"):
			route.append(LevelDef.cell_of(m))
		d["route"] = route
		d["delay"] = delay
	if walks() or now_say != "":
		var now := {"say": now_say}
		if witness_of != "":
			now["witness"] = {"of": witness_of, "clue": witness_clue, "text": witness_text}
		d["now"] = now
	return d


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var cell := Rect2(Vector2.ZERO, Vector2(TILE, TILE))
	var e := to_dict()
	Art.entity(self, cell, e, era == "past", 0.0, false)
	# 时代标记：金色 = 过去，蓝色 = 现在
	if era != "both":
		var col := Color("#e0b46a") if era == "past" else Color("#6a9ad8")
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(0, 10)]), col)
	# 路线：从人物连到每一站
	var prev := cell.get_center()
	for m in _markers("route"):
		var p: Vector2 = to_local(m.global_position) + cell.get_center()
		draw_line(prev, p, Color(Art.GOLD, 0.7), 2.0)
		prev = p
	for m in _markers("seat"):
		draw_line(cell.get_center(), to_local(m.global_position) + cell.get_center(), Color(Art.GOLD, 0.5), 1.0)
