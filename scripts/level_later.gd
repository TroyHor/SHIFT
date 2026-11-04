@tool
class_name LevelLater
extends Node2D
## 后来的建造：案发后才出现的砖墙、木板、门锁，现在挡路，在烟雾里可以穿过。
## 过去那一格被东西占着，它就不会出现。
## 如果填了 by（负责的人的 id），再加一个 LevelMarker 子节点（what = at）：那个人走到这一格，它才会出现。

const TILE := 32

@export_enum("brick", "planks", "lock") var kind := "brick":
	set(v):
		kind = v
		queue_redraw()
@export var display_name := ""
## 现在碰到它时的描述
@export_multiline var text := ""
## 谁去建造（人物 id），留空表示一定会建成
@export var by := ""


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var snap := (position / TILE).round() * TILE
	if snap != position:
		position = snap
	queue_redraw()


func to_dict() -> Dictionary:
	var d := {"pos": LevelDef.cell_of(self), "kind": kind, "name": display_name, "text": text}
	if by != "":
		d["by"] = by
		for c in get_children():
			if c is LevelMarker and c.what == "at":
				d["at"] = LevelDef.cell_of(c)
	return d


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var cell := Rect2(Vector2.ZERO, Vector2(TILE, TILE))
	Art.later(self, cell, kind)
	for c in get_children():
		if c is LevelMarker and c.what == "at":
			draw_line(cell.get_center(), to_local(c.global_position) + cell.get_center(), Color(1, 0.4, 0.3, 0.7), 1.5)
