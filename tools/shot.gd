extends SceneTree
## 截图工具（开发用）：godot --path . --script res://tools/shot.gd -- <关卡序号> <输出.png> [动作...]
## 动作：u d l r 走一步，p 吐烟，wN 等 N 帧，sNAME 中途另存一张 NAME.png，title 停在标题画面

var main: Node
var acts: Array = []
var out := ""
var frame := 0
var wait := 2


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var idx := int(args[0]) if args.size() > 0 else 0
	out = args[1] if args.size() > 1 else "shot.png"
	acts = args.slice(2)
	if not acts.has("title"):
		acts.push_front("start%d" % idx)


func _process(_d: float) -> bool:
	frame += 1
	if wait > 0:
		wait -= 1
		return false
	if acts.is_empty():
		_save(out)
		return true
	var a: String = acts.pop_front()
	var g = main.game
	match a:
		"u": g.move(Vector2i.UP)
		"d": g.move(Vector2i.DOWN)
		"l": g.move(Vector2i.LEFT)
		"r": g.move(Vector2i.RIGHT)
		"p": g.puff()
		"title": pass
		"z": g.undo()
		"edit": main._open_editor(int(OS.get_cmdline_user_args()[0]))
		_:
			if a.begins_with("start"):
				main._start(int(a.substr(5)))
			elif a.begins_with("w"):
				wait = int(a.substr(1))
			elif a.begins_with("s"):
				_save(out.get_base_dir().path_join(a.substr(1) + ".png"))
	if not main.title and not main.editing:
		main.world.refresh()
	return false


func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
