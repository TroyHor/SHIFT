@tool
class_name LevelArea
extends Node2D
## 一个地点：地图上的一块长方形区域（房间、走廊、院子）和它的名字。
## 放在关卡的 Areas 节点下。节点的位置是左上角那一格，size 是宽和高（格子数）。
## 游戏里：名牌挂在这块区域靠里的那面墙上；侦探走进来，顶栏显示地点；对话里提到这个名字会高亮，名牌跟着亮一下。
## 不是长方形的地点（比如绕一圈的院子），用几块同名的区域拼起来，只给其中一块勾"挂名牌"。
## 区域可以叠在一起：一格同时在几块里，算最小的那一块（比如大店面里隔出来的里屋）。

const TILE := 32

## 名牌上写的名字
@export var display_name := "":
	set(v):
		display_name = v
		queue_redraw()
## 区域多大（格子数，宽 × 高）
@export var size := Vector2i(3, 3):
	set(v):
		size = Vector2i(maxi(v.x, 1), maxi(v.y, 1))
		queue_redraw()
## 对话里的别的叫法，也会高亮（比如"行李车厢"指的就是 C 车厢）
@export var aliases: PackedStringArray
## 这一块挂不挂名牌（同名的几块拼成一个地点时，只挂一块）
@export var show_sign := true:
	set(v):
		show_sign = v
		queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		Art.add_font_fallback()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var snap := (position / TILE).round() * TILE
	if snap != position:
		position = snap


func rect() -> Rect2i:
	return Rect2i(LevelDef.cell_of(self), size)


func to_dict() -> Dictionary:
	return {"name": display_name, "rect": rect(), "aliases": Array(aliases), "sign": show_sign}


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var r := Rect2(Vector2.ZERO, Vector2(size) * TILE)
	var col := Color("#7ec8a0")
	draw_rect(r, Color(col, 0.08))
	# 虚线边框，和墙、物件区分开
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], Color(col, 0.85), 2.0, 6.0)
	if display_name != "":
		var s := display_name + ("" if show_sign else "（不挂名牌）")
		var w := Art.SANS.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_rect(Rect2(Vector2(4, 4), Vector2(w + 8, 18)), Color(0.05, 0.08, 0.06, 0.8))
		draw_string(Art.SANS, Vector2(8, 18), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
