@tool
class_name LevelDef
extends Node2D
## 一关的根节点。子节点：
##   Map    —— 瓦片层：画墙和地面（室内地面 / 墙 / 室外地面 / 冷地面）
##   Start  —— 侦探的开局位置
##   Later  —— 后来的建造（砖墙、木板、门锁），每个是一个 LevelLater
##   Ents   —— 人物和物件，每个是一个 LevelEnt；节点名就是它的 id
##   Areas  —— 地点（房间、院子……），每个是一个 LevelArea：名牌挂在墙上，对话里提到会高亮（可以没有）
## 在 Godot 里打开这个场景按 F6，就会直接试玩这一关。

const TILE := 32
## 瓦片图集里每种格子的位置
const T_FLOOR := Vector2i(0, 0)
const T_WALL := Vector2i(1, 0)
const T_OUTDOOR := Vector2i(2, 0)
const T_COLD := Vector2i(3, 0)

@export var title := ""
## 选关界面上的一句话
@export_multiline var theme := ""
## 开局时的第一句话
@export_multiline var intro := ""
## 烟雾里是什么时刻
@export var past_label := ""
## 现在是什么时刻
@export var present_label := ""
## 开局有几撮烟丝
@export var tobacco := 1
## 地面、墙的画法
@export_enum("书房", "旅馆", "列车") var style := 0

@export_group("证据")
## 每类填若干个证据 id，拿到其中一个就算这一类齐了；留空的类别这一关不需要
@export var presence_clues: PackedStringArray
@export var weapon_clues: PackedStringArray
@export var motive_clues: PackedStringArray
## 证据 id → 显示的名字
@export var clue_names: Dictionary

@export_group("指认")
@export var suspects: PackedStringArray
## 凶手是 suspects 里的第几个（从 0 数）
@export var culprit := 0
@export_multiline var win_text := ""
@export_multiline var lose_text := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# 在 Godot 里直接运行这个场景（F6）：跳到游戏里试玩这一关
	if get_tree().current_scene == self:
		Levels.test_path = scene_file_path
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


static func cell_of(node: Node2D) -> Vector2i:
	## 节点所在的格子。节点不一定在场景树里，所以自己沿父节点累加位置。
	var p := node.position
	var n: Node = node.get_parent()
	if not node.top_level:
		while n != null and n is Node2D and not (n is LevelDef):
			p += (n as Node2D).position
			if (n as Node2D).top_level:
				break
			n = n.get_parent()
	return Vector2i(floori(p.x / TILE + 0.001), floori(p.y / TILE + 0.001))


func to_level() -> Dictionary:
	var map_layer: TileMapLayer = get_node("Map")
	var used := map_layer.get_used_rect()
	var w := used.end.x
	var h := used.end.y
	var rows: Array = []
	var cold: Array = []
	for y in h:
		var row := ""
		for x in w:
			var c := map_layer.get_cell_atlas_coords(Vector2i(x, y))
			if c == T_FLOOR:
				row += "."
			elif c == T_OUTDOOR:
				row += ","
			elif c == T_COLD:
				row += "."
				cold.append(Vector2i(x, y))
			else:
				row += "#"
		rows.append(row)
	var later: Array = []
	for n in get_node("Later").get_children():
		if n is LevelLater:
			later.append(n.to_dict())
	var ents: Array = []
	_collect_ents(get_node("Ents"), ents)
	var areas: Array = []
	var an := get_node_or_null("Areas")
	if an != null:
		for n in an.get_children():
			if n is LevelArea and n.display_name != "":
				areas.append(n.to_dict())
	return {
		"title": title,
		"theme": theme,
		"intro": intro,
		"past_label": past_label,
		"present_label": present_label,
		"start": cell_of(get_node("Start")),
		"tobacco": tobacco,
		"style": style,
		"map": rows,
		"cold": cold,
		"later": later,
		"categories": _categories(),
		"clue_names": clue_names.duplicate(),
		"accuse": {"options": Array(suspects), "answer": culprit, "win": win_text, "lose": lose_text},
		"ents": ents,
		"areas": areas,
	}


## 只列出填了证据的类别：引导关可以只要一类
func _categories() -> Array:
	var out: Array = []
	for c in [["presence", "在场", presence_clues], ["weapon", "凶器", weapon_clues], ["motive", "动机", motive_clues]]:
		if not c[2].is_empty():
			out.append([c[0], c[1], Array(c[2])])
	return out


func _collect_ents(node: Node, out: Array) -> void:
	for n in node.get_children():
		if n is LevelEnt:
			out.append(n.to_dict())
		elif n is Node2D and not (n is LevelMarker):
			_collect_ents(n, out)
