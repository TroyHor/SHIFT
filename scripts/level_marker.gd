@tool
class_name LevelMarker
extends Node2D
## 关卡里的一个格子标记：开局位置、人物路线上的一站、烟灰缸的座位、建造者要走到的位置。
## 拖到哪一格就是哪一格。路线、座位和"走到哪"的标记不跟着父节点移动（top_level）。

const TILE := 32

@export_enum("start", "route", "seat", "at") var what := "route":
	set(v):
		what = v
		queue_redraw()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var snap := (position / TILE).round() * TILE
	if snap != position:
		position = snap
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var cell := Rect2(Vector2.ZERO, Vector2(TILE, TILE))
	var c := cell.get_center()
	match what:
		"start":
			Art.person(self, cell, "detective", false, 0.0, true)
			draw_rect(cell, Color(Art.GOLD, 0.9), false, 2.0)
		"route":
			draw_circle(c, 9, Color(Art.GOLD, 0.85))
			Art.text_center(self, Art.SANS, str(get_index() + 1), c, 12, Color("#2a2018"))
		"seat":
			draw_rect(cell.grow(-6), Color(Art.GOLD, 0.25))
			draw_rect(cell.grow(-6), Art.GOLD, false, 2.0)
			Art.text_center(self, Art.SANS, "座", c, 13, Art.GOLD)
		"at":
			draw_rect(cell.grow(-4), Color(1, 0.4, 0.3, 0.9), false, 2.0)
			Art.text_center(self, Art.SANS, "到", c, 13, Color(1, 0.5, 0.4))
