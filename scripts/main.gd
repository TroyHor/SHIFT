extends Node2D
## 画面与输入。原型阶段全部用 _draw() 画色块和文字，不依赖美术资源。

const GameLogic := preload("res://scripts/game.gd")
const FONT := preload("res://assets/fonts/NotoSansSC-Subset.ttf")

const TS := 48
const ORIGIN := Vector2(48, 72)

const C_BG := Color("#0e1016")
const C_NOW_FLOOR := Color("#2a3040")
const C_NOW_FLOOR2 := Color("#262b3a")
const C_NOW_WALL := Color("#12151d")
const C_BRICK := Color("#5c3a2c")
const C_PAST_FLOOR := Color("#c8a676")
const C_PAST_FLOOR2 := Color("#bf9d6c")
const C_PAST_WALL := Color("#6a4c31")
const C_TEXT := Color("#e8e4da")
const C_DIM := Color("#8a8f9e")
const C_ACCENT := Color("#e0b46a")

const ENT_STYLE := {
	"inspector": ["警", Color("#4a6fa5")],
	"maid": ["仆", Color("#8a6aa8")],
	"butler": ["管", Color("#5f7f5a")],
	"desk": ["桌", Color("#6b5440")],
	"shelf": ["柜", Color("#7a5a3a")],
	"safe": ["箱", Color("#5b6470")],
	"cache": ["格", Color("#3a2e28")],
	"tin": ["烟", Color("#a0763a")],
	"jar": ["罐", Color("#9a6b3c")],
	"ashtray": ["缸", Color("#4a4a52")],
}

var game = GameLogic.new()
var t := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(C_BG)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k: int = event.keycode
	if event.echo and k in [KEY_SHIFT, KEY_Z, KEY_BACKSPACE]:
		return
	match k:
		KEY_UP, KEY_W:
			game.move(Vector2i.UP)
		KEY_DOWN, KEY_S:
			game.move(Vector2i.DOWN)
		KEY_LEFT, KEY_A:
			game.move(Vector2i.LEFT)
		KEY_RIGHT, KEY_D:
			game.move(Vector2i.RIGHT)
		KEY_SHIFT:
			game.puff()
		KEY_Z:
			game.undo()
		KEY_BACKSPACE:
			game.reset()
		KEY_1:
			game.choose(1)
		KEY_2:
			game.choose(2)
		KEY_ESCAPE:
			game.cancel()
		_:
			return
	get_viewport().set_input_as_handled()


func _cell(p: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(p) * TS, Vector2(TS, TS))


func _draw() -> void:
	var s: Dictionary = game.s
	_draw_board()
	_draw_smoke()
	for e in game.visible_ents():
		_draw_ent(e)
	_draw_player()
	_draw_hud()
	_draw_message()
	if s.mode == "end":
		_draw_end()


func _draw_board() -> void:
	for y in Game.H:
		for x in Game.W:
			var p := Vector2i(x, y)
			var era: String = game.era_at(p)
			var tile: int = game.tile_at(era, p)
			var r := _cell(p)
			var past := era == "past"
			var checker := (x + y) % 2 == 0
			match tile:
				Game.Tile.FLOOR:
					if past:
						draw_rect(r, C_PAST_FLOOR if checker else C_PAST_FLOOR2)
					else:
						draw_rect(r, C_NOW_FLOOR if checker else C_NOW_FLOOR2)
				Game.Tile.WALL:
					draw_rect(r, C_PAST_WALL if past else C_NOW_WALL)
				Game.Tile.BRICK:
					draw_rect(r, C_BRICK)
					for i in 4:
						var yy := r.position.y + 6 + i * 12
						draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), C_NOW_WALL, 2)
						var off := 12.0 if i % 2 == 0 else 24.0
						draw_line(Vector2(r.position.x + off, yy), Vector2(r.position.x + off, yy + 12), C_NOW_WALL, 2)


func _draw_smoke() -> void:
	var s: Dictionary = game.s
	if not s.cloud:
		return
	var c: Vector2i = s.center
	var rect := Rect2(ORIGIN + Vector2(c - Vector2i.ONE) * TS, Vector2(TS * 3, TS * 3))
	# 浓度越低，烟越淡
	var density := float(s.turns) / Game.SMOKE_TURNS
	draw_rect(rect, Color(0.95, 0.92, 0.85, 0.10 * density))
	for i in 18:
		var a := t * 0.4 + i * 1.7
		var px := rect.position.x + fposmod(i * 37.0 + sin(a) * 20.0, rect.size.x)
		var py := rect.position.y + fposmod(i * 53.0 + t * 8.0 + cos(a) * 10.0, rect.size.y)
		var rad := 10.0 + 8.0 * sin(a * 0.7 + i)
		draw_circle(Vector2(px, py), absf(rad), Color(1, 1, 1, 0.05 + 0.05 * density))
	# 烟雾边缘
	var edge := Color(0.92, 0.9, 0.85, 0.35 + 0.35 * density)
	draw_rect(rect.grow(2), edge, false, 3.0)
	_text_center("%d" % s.turns, rect.position + Vector2(rect.size.x - 10, 12), 14, Color(1, 1, 1, 0.9))


func _draw_ent(e: Dictionary) -> void:
	var st: Array = ENT_STYLE[e.kind]
	var r := _cell(e.pos).grow(-5)
	var col: Color = st[1]
	if e.era == "past":
		col = col.lerp(Color("#a07848"), 0.45)
	if (e.kind == "cache" and e.get("open", false)) or (e.kind == "ashtray" and e.used):
		col = col.darkened(0.4)
	if e.kind in ["inspector", "maid", "butler"]:
		draw_circle(r.get_center(), r.size.x * 0.5, col)
	else:
		draw_rect(r, col)
		draw_rect(r, col.darkened(0.35), false, 2.0)
	_text_center(st[0], r.get_center() + Vector2(0, 1), 22, C_TEXT)
	if e.kind == "desk" and e.get("note", false):
		draw_rect(Rect2(r.end - Vector2(14, 14), Vector2(10, 8)), Color("#f4eedd"))


func _draw_player() -> void:
	var s: Dictionary = game.s
	var r := _cell(s.pos).grow(-4)
	var past: bool = game.era_at(s.pos) == "past"
	var col := Color("#c9533b") if not past else Color("#a8563c")
	draw_circle(r.get_center(), r.size.x * 0.5, col)
	draw_arc(r.get_center(), r.size.x * 0.5, 0, TAU, 32, C_ACCENT, 2.0)
	_text_center("探", r.get_center() + Vector2(0, 1), 22, C_TEXT)
	# 烟斗冒的小烟
	if s.tobacco > 0:
		for i in 3:
			var k := fposmod(t * 0.8 + i * 0.33, 1.0)
			var p := r.position + Vector2(r.size.x - 2 + sin(t * 3 + i) * 3, -k * 18)
			draw_circle(p, 2.0 + k * 3.0, Color(1, 1, 1, 0.5 * (1.0 - k)))


func _draw_hud() -> void:
	var s: Dictionary = game.s
	var y := 26.0
	_text("烟丝", Vector2(48, y), 16, C_DIM)
	for i in maxi(s.tobacco, 1):
		var cpos := Vector2(98 + i * 18, y - 6)
		if i < s.tobacco:
			draw_circle(cpos, 6, C_ACCENT)
		else:
			draw_arc(cpos, 6, 0, TAU, 20, C_DIM, 1.5)
	var after := 98.0 + maxi(s.tobacco, 1) * 18 + 8
	_text("×%d" % s.tobacco, Vector2(after, y), 16, C_TEXT)
	_text("烟灰 ×%d" % s.ash, Vector2(after + 50, y), 16, C_TEXT)
	var x := 420.0
	for cat in Game.CATEGORIES:
		var ok: bool = game.has_category(cat)
		var label: String = Game.CATEGORIES[cat][0]
		_text(("✓ " if ok else "□ ") + label, Vector2(x, y), 16, C_ACCENT if ok else C_DIM)
		x += 80
	var clue_txt := ""
	for c in s.clues:
		clue_txt += Game.CLUE_NAMES[c] + "  "
	var inv_txt := ""
	for it in s.inv:
		inv_txt += Game.ITEM_NAMES[it] + "  "
	var line2 := ("证据：" + clue_txt if clue_txt != "" else "") + ("物品：" + inv_txt if inv_txt != "" else "")
	_text(line2, Vector2(48, y + 26), 14, C_DIM)
	var era_txt := "烟雾里：案发当晚 22:50" if s.cloud else "现在：次日清晨 9:00"
	_text(era_txt, Vector2(730, y + 26), 14, C_ACCENT if s.cloud else C_DIM)


func _draw_message() -> void:
	var s: Dictionary = game.s
	var y := ORIGIN.y + Game.H * TS + 22
	var lines: PackedStringArray = String(s.msg).split("\n")
	for i in lines.size():
		_text(lines[i], Vector2(48, y + i * 20), 15, C_TEXT)
	_text("方向键/WASD 移动（撞上去即互动）  Shift 吐烟（花 1 撮烟丝）  1/2 选择  Esc 取消  Z 撤销  Backspace 重来",
		Vector2(48, 628), 13, C_DIM)


func _draw_end() -> void:
	var s: Dictionary = game.s
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.7))
	if s.outcome == "win":
		_text_center("结案", vp / 2 - Vector2(0, 60), 40, C_ACCENT)
		var used: Array = []
		for c in s.clues:
			used.append(Game.CLUE_NAMES[c])
		_text_center("你找到的证据：" + "、".join(used), vp / 2 + Vector2(0, 0), 18, C_TEXT)
		_text_center("在场证据一共有三条路，你走了其中 %d 条。" % _presence_count(), vp / 2 + Vector2(0, 32), 16, C_DIM)
	else:
		_text_center("指认失败", vp / 2 - Vector2(0, 30), 40, Color("#c9533b"))
	_text_center("按 Backspace 再玩一次", vp / 2 + Vector2(0, 90), 16, C_DIM)


func _presence_count() -> int:
	var n := 0
	for c in Game.CATEGORIES["presence"][1]:
		if game.s.clues.has(c):
			n += 1
	return n


func _text(str: String, pos: Vector2, size: int, col: Color) -> void:
	draw_string(FONT, pos, str, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_center(str: String, center: Vector2, size: int, col: Color) -> void:
	var w := FONT.get_string_size(str, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := FONT.get_ascent(size)
	var desc := FONT.get_descent(size)
	draw_string(FONT, center + Vector2(-w / 2, (asc - desc) / 2), str, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
