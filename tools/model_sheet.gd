extends SceneTree
## 模型对照图：程序拼的样子和 Dify 工作流做的模型并排，白天、夜里各看一遍。
## godot --path . --rendering-driver opengl3 --script res://tools/model_sheet.gd -- <输出.png> [画法名,画法名…]
## 不写画法名就列出 assets/generated 里所有有模型的。人物写 person_<造型>，烟丝罐写 tin。
## 三行：程序拼的（白天）、模型（白天）、模型（夜里，烟雾里的样子）。

const GAP := 1.25

var b: Board3D
var out := "models.png"
var frame := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	var keys: Array = []
	if args.size() > 1:
		keys = Array(args[1].split(","))
	else:
		for d in DirAccess.get_directories_at(Board3D.MODEL_DIR):
			if ResourceLoader.exists("%s/%s/%s.tscn" % [Board3D.MODEL_DIR, d, d]):
				keys.append(d)
	keys.sort()
	root.size = Vector2i(maxi(640, keys.size() * 150 + 120), 560)
	b = Board3D.new()
	root.add_child(b)
	b.setup(null, Rect2(0, 0, root.size.x, root.size.y))
	b.player.visible = false
	RenderingServer.global_shader_parameter_set("era_night", Vector2(0, 1))
	RenderingServer.global_shader_parameter_set("smoke_a", Vector4(0, 0, 0, 0))
	RenderingServer.global_shader_parameter_set("smoke_b", Vector4(0, 0, 0, 0))
	# 夜里那一行在一块很大的"烟"里：smoke_a 盖住 z >= 2 的地方
	RenderingServer.global_shader_parameter_set("smoke_a", Vector4(keys.size() * GAP * 0.5, 52.0, 50.0, 0))
	var w := keys.size() * GAP
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + 2.0, 5.0)
	fl.mesh = pm
	fl.material_override = b._m(Color("#b8a888"))
	fl.position = Vector3(w * 0.5, 0, 1.6)
	b.add_child(fl)
	for i in keys.size():
		var k: String = keys[i]
		var x := (i + 0.5) * GAP
		for row in 3:
			b._past = row == 2
			var n := Node3D.new()
			n.position = Vector3(x, 0, row * 1.3)
			b.add_child(n)
			_build(n, k, row > 0)
		var lb := Label3D.new()
		lb.text = k
		lb.font_size = 40
		lb.pixel_size = 0.006
		lb.modulate = Color("#1c1816")
		lb.rotation = Vector3(-PI / 2, 0, 0)
		lb.position = Vector3(x, 0.01, -0.62)
		b.add_child(lb)
	b.cam.fov = 30.0
	b.cam.rotation_degrees = Vector3(-50, 0, 0)
	var dist := maxf(w, 4.6) / (2.0 * tan(deg_to_rad(15.0))) * 0.75
	b.cam.position = Vector3(w * 0.5, dist * sin(deg_to_rad(50.0)), 1.3 + dist * cos(deg_to_rad(50.0)))


func _build(n: Node3D, k: String, model: bool) -> void:
	var e := {"era": "present", "pos": Vector2i.ZERO, "lit": true}
	if k == "tin":
		# 烟丝罐自己会换模型；程序拼的那一行先把模型藏起来
		var keep: PackedScene = b.model_scene(k)
		if not model:
			b._scenes[k] = null
		b._tin(n, false, false)
		b._scenes[k] = keep
	elif k.begins_with("later_"):
		# 门洞里的东西：_later 自己会换模型；程序拼的那一行先把模型藏起来（左右各一段墙，看填得满不满）
		var keep: PackedScene = b.model_scene(k)
		if not model:
			b._scenes[k] = null
		var l: Node3D = b._later({"kind": k.trim_prefix("later_"), "pos": Vector2i.ZERO, "past": "door"})
		b._scenes[k] = keep
		l.get_parent().remove_child(l)
		l.position = Vector3.ZERO
		n.add_child(l)
		for sx in [-0.75, 0.75]:
			b._part(n, b._box(Vector3(0.5, Board3D.WALL_H, 0.9)), b._m(Color("#6a5a4a")), Vector3(sx, Board3D.WALL_H / 2.0, 0))
	elif k.begins_with("person_"):
		var body := Node3D.new()
		n.add_child(body)
		b._person(body, k.trim_prefix("person_"), k == "person_detective")
		if model:
			b._use_model(body, k, false)
		body.scale = Vector3.ONE * Board3D.PERSON_SCALE
	else:
		b._thing(n, k, e, false)
		if model:
			b._use_model(n, k, false)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 20:
		root.get_texture().get_image().save_png(out)
		return true
	return false
