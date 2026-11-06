extends SceneTree
## 截图工具（云端调画面用）：
## godot --path . --rendering-driver opengl3 --fixed-fps 60 --script res://tools/shot.gd -- <关卡序号> <动作> <等几帧> <输出.png>
## 动作：w/a/s/d 移动，p 吐烟，z 撤销；"-" 表示不做动作。动作之间隔 40 帧，最后一个动作后再等 <等几帧>。
## 关卡序号写 title 就截标题画面。

var main: Node
var frame := 0
var plan: Array = []
var out := "shot.png"
var wait := 30


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lvl: String = args[0] if args.size() > 0 else "0"
	var acts: String = args[1] if args.size() > 1 else "-"
	wait = int(args[2]) if args.size() > 2 else 30
	out = args[3] if args.size() > 3 else "shot.png"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var f := 5
	if lvl != "title":
		plan.append([f, "start", int(lvl)])
	if acts != "-":
		for ch in acts:
			f += 40
			plan.append([f, ch, 0])
	plan.append([f + wait, "save", 0])


func _process(_delta: float) -> bool:
	frame += 1
	while not plan.is_empty() and plan[0][0] <= frame:
		var step: Array = plan.pop_front()
		match step[1]:
			"start":
				main._start(step[2])
			"w":
				main.game.move(Vector2i.UP)
			"s":
				main.game.move(Vector2i.DOWN)
			"a":
				main.game.move(Vector2i.LEFT)
			"d":
				main.game.move(Vector2i.RIGHT)
			"p":
				main.game.puff()
			"z":
				main.game.undo()
			"save":
				root.get_texture().get_image().save_png(out)
				return true
		if step[1] != "start" and step[1] != "save":
			main.world.refresh()
	return false
