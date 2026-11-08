extends SceneTree
## 统一模型的配色：算出每个模型颜色贴图的平均色，和程序拼的那一份（按美术文档配色）的平均色比一比，
## 写一个校色系数进 scripts/model_tints.gd。游戏里模型的颜色乘上这个系数，整体色调就回到文档的配色，
## 贴图里的细节（木纹、书脊）还在。新模型放进来以后运行一次：
## godot --headless --path . --script res://tools/model_tints.gd

const OUT := "res://scripts/model_tints.gd"
## 拉回去多少：1 = 平均色完全等于程序拼的，0 = 不校色
const STRENGTH := 0.85

var b: Board3D


func _initialize() -> void:
	b = Board3D.new()
	root.add_child(b)
	b.setup(null, Rect2(0, 0, 64, 64))
	var lines: Array = []
	var keys: Array = Array(DirAccess.get_directories_at(Board3D.MODEL_DIR))
	keys.sort()
	for k: String in keys:
		var dir := "%s/%s" % [Board3D.MODEL_DIR, k]
		var img_path := ""
		for f in DirAccess.get_files_at(dir):
			if f.get_extension().to_lower() in ["jpg", "jpeg", "png"]:
				img_path = dir + "/" + f
		if img_path == "" or k == "hud_icons":
			continue
		var want := _proc_mean(k)
		var got := _img_mean(img_path)
		if want.a <= 0.0 or got.a <= 0.0:
			continue
		var t := Color(
			clampf(lerpf(1.0, want.r / maxf(got.r, 0.02), STRENGTH), 0.35, 2.6),
			clampf(lerpf(1.0, want.g / maxf(got.g, 0.02), STRENGTH), 0.35, 2.6),
			clampf(lerpf(1.0, want.b / maxf(got.b, 0.02), STRENGTH), 0.35, 2.6))
		lines.append('\t"%s": Color(%.3f, %.3f, %.3f),' % [k, t.r, t.g, t.b])
		print("%s  程序拼的 %s  模型 %s  校色 %s" % [k, want.to_html(false), got.to_html(false), t])
	var src := "## 自动生成（tools/model_tints.gd）：每个模型的校色系数，让模型的平均色回到美术文档的配色\nconst TINTS := {\n%s\n}\n" % "\n".join(lines)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(src)
	f.close()
	quit()


## 程序拼的那一份的平均色（按部件表面积加权），只算会被模型换掉的"身体"
func _proc_mean(k: String) -> Color:
	var n := Node3D.new()
	b.add_child(n)
	if k == "tin":
		var keep: PackedScene = b.model_scene(k)
		b._scenes[k] = null
		b._tin(n, false, false)
		b._scenes[k] = keep
	elif k.begins_with("person_"):
		b._person(n, k.trim_prefix("person_"), k == "person_detective")
	elif k.begins_with("later_"):
		return Color(0, 0, 0, 0)  # 门洞里的东西按材质本色，不校
	else:
		b._thing(n, k, {"era": "present", "pos": Vector2i.ZERO, "lit": true}, false)
	var cut: int = n.get_meta("body", n.get_child_count())
	var start: int = n.get_meta("body_from", 0)
	var sum := Vector3.ZERO
	var w := 0.0
	for i in range(start, cut):
		var c := n.get_child(i)
		if not (c is MeshInstance3D) or c.mesh == null:
			continue
		var mat = c.material_override
		var col := Color.WHITE
		if mat is ShaderMaterial:
			col = mat.get_shader_parameter("albedo")
		elif mat is BaseMaterial3D:
			col = mat.albedo_color
		var s: Vector3 = (c.mesh.get_aabb().size * c.scale).abs()
		var area := s.x * s.z + s.x * s.y + s.y * s.z
		sum += Vector3(col.r, col.g, col.b) * area
		w += area
	n.free()
	if w <= 0.0:
		return Color(0, 0, 0, 0)
	sum /= w
	return Color(sum.x, sum.y, sum.z, 1.0)


## 颜色贴图的平均色（忽略纯白的空白处：Tripo 的贴图边角常有白底）
func _img_mean(path: String) -> Color:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return Color(0, 0, 0, 0)
	img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var sum := Vector3.ZERO
	var n := 0
	for y in 64:
		for x in 64:
			var c := img.get_pixel(x, y)
			if c.r > 0.97 and c.g > 0.97 and c.b > 0.97:
				continue
			if c.r < 0.02 and c.g < 0.02 and c.b < 0.02:
				continue
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return Color(0, 0, 0, 0)
	sum /= n
	return Color(sum.x, sum.y, sum.z, 1.0)
