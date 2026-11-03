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
const C_COLD := Color("#2c3a4c")
const C_PAST_FLOOR := Color("#c8a676")
const C_PAST_FLOOR2 := Color("#bf9d6c")
const C_PAST_WALL := Color("#6a4c31")
const C_TEXT := Color("#e8e4da")
const C_DIM := Color("#8a8f9e")
const C_ACCENT := Color("#e0b46a")
const C_RED := Color("#c9533b")

const KIND_COLOR := {
	"inspector": Color("#4a6fa5"),
	"npc": Color("#5f7f5a"),
	"source": Color("#a0763a"),
	"prints": Color("#9a6b3c"),
	"cache": Color("#3a2e28"),
	"crate": Color("#7a5a3a"),
	"container": Color("#5b6470"),
	"candle": Color("#d8c9a0"),
	"ice": Color("#9fd0e8"),
	"compare": Color("#5b6470"),
	"ashtray": Color("#4a4a52"),
	"clue": Color("#8a7a5a"),
	"static": Color("#6b5440"),
}

var game = GameLogic.new(0)
var t := 0.0
var title := true
var title_pick := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(C_BG)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k: int = event.keycode
	if event.echo and k in [KEY_SHIFT, KEY_Z, KEY_BACKSPACE, KEY_ENTER, KEY_ESCAPE]:
		return
	if title:
		match k:
			KEY_UP, KEY_W:
				title_pick = (title_pick + Levels.COUNT - 1) % Levels.COUNT
			KEY_DOWN, KEY_S:
				title_pick = (title_pick + 1) % Levels.COUNT
			KEY_1, KEY_2, KEY_3:
				title_pick = k - KEY_1
				_start(title_pick)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_start(title_pick)
		get_viewport().set_input_as_handled()
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
		KEY_1, KEY_2, KEY_3, KEY_4:
			game.choose(k - KEY_0)
		KEY_ESCAPE:
			if game.s.mode == "choice":
				game.cancel()
			else:
				title = true
		KEY_ENTER, KEY_KP_ENTER:
			if game.s.mode == "end":
				if game.s.outcome == "win" and game.level_idx < Levels.COUNT - 1:
					_start(game.level_idx + 1)
				else:
					title = true
		_:
			return
	get_viewport().set_input_as_handled()


func _start(idx: int) -> void:
	game.load_level(idx)
	title_pick = idx
	title = false


func _cell(p: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(p) * TS, Vector2(TS, TS))


func _draw() -> void:
	if title:
		_draw_title()
		return
	_draw_board()
	_draw_later()
	_draw_smoke()
	for e in game.visible_ents():
		_draw_ent(e)
	_draw_routes()
	_draw_player()
	_draw_hud()
	_draw_message()
	if game.s.mode == "end":
		_draw_end()


func _draw_title() -> void:
	var vp := get_viewport_rect().size
	_text_center("SHIFT · 烟斗侦探", Vector2(vp.x / 2, 120), 40, C_ACCENT)
	_text_center("按 Shift 吐一口烟，烟雾里是案发当晚。", Vector2(vp.x / 2, 170), 16, C_DIM)
	for i in Levels.COUNT:
		var lv: Dictionary = Levels.get_level(i)
		var y := 250.0 + i * 100
		var sel := i == title_pick
		var r := Rect2(Vector2(vp.x / 2 - 300, y - 34), Vector2(600, 80))
		draw_rect(r, Color(1, 1, 1, 0.06 if sel else 0.02))
		if sel:
			draw_rect(r, C_ACCENT, false, 2.0)
		_text("[%d]  %s" % [i + 1, lv.title], Vector2(r.position.x + 24, y), 22, C_TEXT if sel else C_DIM)
		_text(lv.theme, Vector2(r.position.x + 24, y + 30), 14, C_DIM)
	_text_center("↑↓ 选择   Enter 开始   1/2/3 直接进入", Vector2(vp.x / 2, 600), 14, C_DIM)


func _draw_board() -> void:
	var cold: Array = game.L.cold
	for y in Game.H:
		for x in Game.W:
			var p := Vector2i(x, y)
			var past: bool = game.in_window(p)
			var r := _cell(p)
			var checker := (x + y) % 2 == 0
			if game.tile_at(p) == Game.Tile.WALL:
				draw_rect(r, C_PAST_WALL if past else C_NOW_WALL)
			elif past:
				draw_rect(r, C_PAST_FLOOR if checker else C_PAST_FLOOR2)
			else:
				var base := C_NOW_FLOOR if checker else C_NOW_FLOOR2
				if cold.has(p):
					base = base.lerp(C_COLD, 0.6)
				draw_rect(r, base)


func _draw_later() -> void:
	for lt in game.d.later_active:
		if game.in_window(lt.pos):
			continue
		var r := _cell(lt.pos)
		match lt.kind:
			"brick":
				draw_rect(r, Color("#5c3a2c"))
				for i in 4:
					var yy := r.position.y + 6 + i * 12
					draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), C_NOW_WALL, 2)
					var off := 12.0 if i % 2 == 0 else 24.0
					draw_line(Vector2(r.position.x + off, yy), Vector2(r.position.x + off, yy + 12), C_NOW_WALL, 2)
			"planks":
				draw_rect(r, Color("#3a2c22"))
				for i in 3:
					var yy := r.position.y + 8 + i * 14
					draw_rect(Rect2(Vector2(r.position.x + 2, yy), Vector2(TS - 4, 9)), Color("#8a6440"))
			"lock":
				draw_rect(r, Color("#3b4250"))
				draw_rect(Rect2(r.get_center() - Vector2(8, 4), Vector2(16, 14)), C_ACCENT)
				draw_arc(r.get_center() - Vector2(0, 4), 6, PI, TAU, 12, C_ACCENT, 2.5)


func _draw_smoke() -> void:
	var s: Dictionary = game.s
	if not s.cloud:
		return
	var c: Vector2i = s.center
	var rect := Rect2(ORIGIN + Vector2(c - Vector2i.ONE) * TS, Vector2(TS * 3, TS * 3))
	var density := float(s.turns) / Game.SMOKE_TURNS
	draw_rect(rect, Color(0.95, 0.92, 0.85, 0.10 * density))
	for i in 18:
		var a := t * 0.4 + i * 1.7
		var px := rect.position.x + fposmod(i * 37.0 + sin(a) * 20.0, rect.size.x)
		var py := rect.position.y + fposmod(i * 53.0 + t * 8.0 + cos(a) * 10.0, rect.size.y)
		var rad := 10.0 + 8.0 * sin(a * 0.7 + i)
		draw_circle(Vector2(px, py), absf(rad), Color(1, 1, 1, 0.05 + 0.05 * density))
	var edge := Color(0.92, 0.9, 0.85, 0.35 + 0.35 * density)
	draw_rect(rect.grow(2), edge, false, 3.0)
	_text_center("%d" % s.turns, rect.position + Vector2(rect.size.x - 10, 12), 14, Color(1, 1, 1, 0.9))


## 烟雾里能看到的人，画出他们接下来要走的路
func _draw_routes() -> void:
	for e in game.past_ents():
		if e.kind != "npc" or not e.has("route") or not game.in_window(e.pos):
			continue
		var path: Array = game.route_of(e.id)
		var prev: Vector2i = e.pos
		for i in range(1, path.size()):
			var p: Vector2i = path[i]
			if p == prev:
				continue
			var a := _cell(prev).get_center()
			var b := _cell(p).get_center()
			var k := fposmod(t * 2.0 - i * 0.15, 1.0)
			draw_line(a, b, Color(C_ACCENT, 0.25 + 0.35 * k), 3.0)
			prev = p
		var end := _cell(path[path.size() - 1]).get_center()
		draw_circle(end, 6, Color(C_ACCENT, 0.8))


func _draw_ent(e: Dictionary) -> void:
	var r := _cell(e.pos).grow(-5)
	var col: Color = KIND_COLOR.get(e.kind, Color("#6b5440"))
	var past: bool = game.in_window(e.pos)
	if e.kind == "candle" and e.get("lit", false):
		col = Color("#f2c46a")
	if e.get("burnt", false):
		col = Color("#3a3434")
	if past:
		col = col.lerp(Color("#a07848"), 0.4)
	var done: bool = (e.kind in ["cache", "clue"] and game.s.clues.has(e.get("clue", ""))) \
		or (e.kind == "container" and e.get("taken", false))
	if done:
		col = col.darkened(0.45)
	if e.kind in ["inspector", "npc"]:
		draw_circle(r.get_center(), r.size.x * 0.5, col)
	elif e.get("burnt", false):
		draw_circle(r.get_center(), r.size.x * 0.3, col)
	else:
		draw_rect(r, col)
		draw_rect(r, col.darkened(0.35), false, 2.0)
	var text_col := C_TEXT if e.kind not in ["ice", "candle"] or e.get("burnt", false) else Color("#2a2a2a")
	_text_center(e.label, r.get_center() + Vector2(0, 1), 22, text_col)
	if e.kind == "candle" and e.get("lit", false) and past:
		var flick := 3.0 + sin(t * 12.0) * 1.5
		draw_circle(r.get_center() - Vector2(0, r.size.y * 0.5 + 2), flick, Color("#ff9a3c"))
	if e.kind == "ashtray" and e.get("baited", false):
		draw_circle(r.end - Vector2(8, 8), 4, C_ACCENT)


func _draw_player() -> void:
	var s: Dictionary = game.s
	var r := _cell(s.pos).grow(-4)
	var past: bool = game.in_window(s.pos)
	var col := C_RED if not past else Color("#a8563c")
	draw_circle(r.get_center(), r.size.x * 0.5, col)
	draw_arc(r.get_center(), r.size.x * 0.5, 0, TAU, 32, C_ACCENT, 2.0)
	_text_center("探", r.get_center() + Vector2(0, 1), 22, C_TEXT)
	if s.tobacco > 0:
		for i in 3:
			var k := fposmod(t * 0.8 + i * 0.33, 1.0)
			var p := r.position + Vector2(r.size.x - 2 + sin(t * 3 + i) * 3, -k * 18)
			draw_circle(p, 2.0 + k * 3.0, Color(1, 1, 1, 0.5 * (1.0 - k)))


func _draw_hud() -> void:
	var s: Dictionary = game.s
	var y := 26.0
	_text("烟丝", Vector2(48, y), 16, C_DIM)
	var n := maxi(s.tobacco, 1)
	for i in n:
		var cpos := Vector2(98 + i * 18, y - 6)
		if i < s.tobacco:
			draw_circle(cpos, 6, C_ACCENT)
		else:
			draw_arc(cpos, 6, 0, TAU, 20, C_DIM, 1.5)
	var after := 98.0 + n * 18 + 8
	_text("×%d" % s.tobacco, Vector2(after, y), 16, C_TEXT)
	_text("烟灰 ×%d" % s.ash, Vector2(after + 50, y), 16, C_TEXT)
	var x := 420.0
	for i in game.L.categories.size():
		var ok: bool = game.has_category(i)
		_text(("✓ " if ok else "□ ") + game.L.categories[i][1], Vector2(x, y), 16, C_ACCENT if ok else C_DIM)
		x += 80
	_text(game.L.title, Vector2(700, y), 14, C_DIM)
	var clue_txt := ""
	for c in s.clues:
		clue_txt += game.clue_name(c) + "  "
	_text(("证据：" + clue_txt) if clue_txt != "" else "", Vector2(48, y + 26), 14, C_DIM)
	var era_txt: String = ("烟雾里：" + game.L.past_label) if s.cloud else ("现在：" + game.L.present_label)
	_text(era_txt, Vector2(730, y + 26), 14, C_ACCENT if s.cloud else C_DIM)


func _draw_message() -> void:
	var s: Dictionary = game.s
	var y := ORIGIN.y + Game.H * TS + 22
	var lines: PackedStringArray = String(s.msg).split("\n")
	for i in mini(lines.size(), 3):
		_text(lines[i], Vector2(48, y + i * 20), 15, C_TEXT)
	_text("方向键 移动/互动   Shift 吐烟   1/2 选择   Esc 取消/回选关   Z 撤销   Backspace 重来",
		Vector2(48, 628), 13, C_DIM)


func _draw_end() -> void:
	var s: Dictionary = game.s
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.72))
	if s.outcome == "win":
		_text_center("结案", vp / 2 - Vector2(0, 70), 40, C_ACCENT)
		var used: Array = []
		for c in s.clues:
			used.append(game.clue_name(c))
		_text_center("你找到的证据：" + "、".join(used), vp / 2 - Vector2(0, 10), 18, C_TEXT)
		_text_center(s.msg, vp / 2 + Vector2(0, 24), 16, C_DIM)
		var next := "按 Enter 进入下一个案件" if game.level_idx < Levels.COUNT - 1 else "三个案件全部结案。按 Enter 回到选关"
		_text_center(next, vp / 2 + Vector2(0, 80), 16, C_ACCENT)
	else:
		_text_center("指认失败", vp / 2 - Vector2(0, 30), 40, C_RED)
		_text_center(s.msg, vp / 2 + Vector2(0, 20), 16, C_DIM)
		_text_center("按 Backspace 重来，Enter 回到选关", vp / 2 + Vector2(0, 80), 16, C_DIM)


func _text(str: String, pos: Vector2, size: int, col: Color) -> void:
	draw_string(FONT, pos, str, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_center(str: String, center: Vector2, size: int, col: Color) -> void:
	var w := FONT.get_string_size(str, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := FONT.get_ascent(size)
	var desc := FONT.get_descent(size)
	draw_string(FONT, center + Vector2(-w / 2, (asc - desc) / 2), str, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
