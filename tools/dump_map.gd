extends SceneTree
## 把每一关的地图连同物件打印成文字（检查地点标注用）：
## godot --headless --path . --script res://tools/dump_map.gd
func _init() -> void:
	for p in Levels.paths():
		var L: Dictionary = (load(p) as PackedScene).instantiate().to_level()
		print("=== ", p, "  ", L.title)
		var rows: Array = []
		for r in L.map:
			rows.append(r)
		var legend := []
		var marks := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
		var i := 0
		for lt in L.later:
			var p2: Vector2i = lt.pos
			var row: String = rows[p2.y]
			rows[p2.y] = row.substr(0, p2.x) + "+" + row.substr(p2.x + 1)
			legend.append("+ later %s %s %s" % [lt.get("kind", ""), p2, lt.get("name", "")])
		for e in L.ents:
			var p2: Vector2i = e.pos
			var m := marks[i % marks.length()]
			i += 1
			var row: String = rows[p2.y]
			rows[p2.y] = row.substr(0, p2.x) + m + row.substr(p2.x + 1)
			legend.append("%s %s %s %s %s %s" % [m, e.id, e.kind, e.era, p2, e.get("name", e.get("sprite", ""))])
		var hdr := "   "
		for x in rows[0].length():
			hdr += str(x % 10)
		print(hdr)
		for y in rows.size():
			print("%2d %s" % [y, rows[y]])
		print("start ", L.start)
		for l in legend:
			print("  ", l)
	quit()
