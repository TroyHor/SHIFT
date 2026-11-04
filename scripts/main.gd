extends Node2D
## 画面与输入。全部程序化绘制（见 art.gd），不依赖贴图。
## 图层：0 世界（地面、物件、人物）→ 1 光影（台灯光圈、暗角、胶片颗粒）→ 2 界面。

const GameLogic := preload("res://scripts/game.gd")
const FONT := preload("res://assets/fonts/NotoSansSC-Subset.ttf")
const SERIF := preload("res://assets/fonts/NotoSerifSC-Subset.ttf")

## 棋盘区域：地图按大小缩放后居中放在这里
const BOARD := Rect2(48, 76, 864, 470)
var TS := 48
var ORIGIN := Vector2(48, 76)

const C_BG := Color("#08090d")
const C_TEXT := Color("#e8e4da")
const C_DIM := Color("#8a8f9e")
const C_ACCENT := Color("#e0b46a")
const C_RED := Color("#c9533b")
const C_INK := Color("#2a2018")
const C_PAPER := Color("#e9dfc8")

const LIGHT_SHADER := """
shader_type canvas_item;
uniform vec2 view = vec2(960.0, 640.0);
uniform vec4 board = vec4(48.0, 76.0, 864.0, 470.0);
uniform vec2 lamp = vec2(480.0, 320.0);
uniform float lamp_r = 240.0;
uniform vec4 smoke = vec4(0.0);
uniform float density = 0.0;
uniform float time_s = 0.0;
uniform float title = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 p = UV * view;
	vec3 col = vec3(0.01, 0.02, 0.05);
	float a = 0.0;
	bool inb = p.x > board.x && p.y > board.y && p.x < board.x + board.z && p.y < board.y + board.w;
	if (inb && title < 0.5) {
		float l = 1.0 - smoothstep(lamp_r * 0.2, lamp_r, distance(p, lamp));
		a = mix(0.62, 0.0, l);
	}
	bool ins = smoke.z > 0.0 && p.x > smoke.x && p.y > smoke.y && p.x < smoke.x + smoke.z && p.y < smoke.y + smoke.w;
	if (ins) {
		vec2 sp = (p - smoke.xy) / smoke.zw;
		float g = hash(floor(p / 2.0) + floor(time_s * 18.0)) - 0.5;
		float scratch = step(0.993, hash(vec2(floor(p.x / 2.0), floor(time_s * 9.0))));
		float wv = smoothstep(0.25, 0.75, length(sp - 0.5));
		col = mix(vec3(0.22, 0.12, 0.04), vec3(0.95, 0.88, 0.7), scratch);
		a = 0.04 + abs(g) * 0.16 * (0.4 + density) + wv * 0.32 + scratch * 0.35;
	}
	vec2 q = UV - 0.5;
	float vig = smoothstep(0.42, 0.9, length(q * vec2(1.0, 1.3)));
	if (!ins) { a = max(a, vig * 0.8); }
	float gr = hash(floor(p / 2.0) + floor(time_s * 24.0)) - 0.5;
	a = clamp(a + gr * 0.05, 0.0, 1.0);
	COLOR = vec4(col, a);
}
"""

var game = GameLogic.new(0)
var t := 0.0
var title := true
var title_pick := 0


var ui: Node2D
var light: ColorRect
var light_mat: ShaderMaterial


func _ready() -> void:
	RenderingServer.set_default_clear_color(C_BG)
	var l1 := CanvasLayer.new()
	l1.layer = 1
	add_child(l1)
	light = ColorRect.new()
	light.size = Vector2(960, 640)
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = LIGHT_SHADER
	light_mat = ShaderMaterial.new()
	light_mat.shader = sh
	light.material = light_mat
	l1.add_child(light)
	var l2 := CanvasLayer.new()
	l2.layer = 2
	add_child(l2)
	ui = Node2D.new()
	l2.add_child(ui)
	ui.draw.connect(_draw_ui)
	# 在 Godot 里按 F6 试玩某一关：关卡场景把自己的路径留在 Levels.test_path，跳到这里直接开始
	if Levels.test_path != "":
		var idx := Levels.index_of(Levels.test_path)
		Levels.test_path = ""
		if idx >= 0:
			_start(idx)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()
	ui.queue_redraw()
	_update_light()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k: int = event.keycode
	if event.echo and k in [KEY_SHIFT, KEY_Z, KEY_BACKSPACE, KEY_ENTER, KEY_ESCAPE]:
		return
	if title:
		match k:
			KEY_UP, KEY_W:
				title_pick = (title_pick + Levels.count() - 1) % Levels.count()
			KEY_DOWN, KEY_S:
				title_pick = (title_pick + 1) % Levels.count()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				if k - KEY_1 < Levels.count():
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
				if game.s.outcome == "win" and game.level_idx < Levels.count() - 1:
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


func _layout() -> void:
	TS = int(floor(minf(BOARD.size.x / game.W, BOARD.size.y / game.H)))
	ORIGIN = BOARD.position + (BOARD.size - Vector2(game.W, game.H) * TS) / 2


## 当前画在哪一层（世界或界面），文字等辅助函数都画到这里
var cv: CanvasItem


func _draw() -> void:
	cv = self
	if title:
		_draw_title()
		return
	_layout()
	_draw_frame()
	_draw_board()
	_draw_later()
	_draw_routes()
	var ents: Array = game.visible_ents()
	for e in ents:
		_draw_ent(e)
	_draw_anchors()
	_draw_player()
	_draw_tags(ents)
	_draw_smoke()


func _draw_ui() -> void:
	cv = ui
	if title:
		return
	_draw_hud()
	_draw_message()
	if game.s.mode == "end":
		_draw_end()


func _update_light() -> void:
	light_mat.set_shader_parameter("time_s", t)
	if title:
		light_mat.set_shader_parameter("title", 1.0)
		light_mat.set_shader_parameter("smoke", Vector4.ZERO)
		return
	light_mat.set_shader_parameter("title", 0.0)
	var bw := Vector2(game.W, game.H) * TS
	light_mat.set_shader_parameter("board", Vector4(ORIGIN.x, ORIGIN.y, bw.x, bw.y))
	light_mat.set_shader_parameter("lamp", _cell(game.s.pos).get_center())
	light_mat.set_shader_parameter("lamp_r", TS * 7.5)
	if game.s.cloud:
		var c: Vector2i = game.s.center
		var o := ORIGIN + Vector2(c - Vector2i.ONE) * TS
		light_mat.set_shader_parameter("smoke", Vector4(o.x, o.y, TS * 3, TS * 3))
		light_mat.set_shader_parameter("density", float(game.s.turns) / Game.SMOKE_TURNS)
	else:
		light_mat.set_shader_parameter("smoke", Vector4.ZERO)


# ---------------------------------------------------------------- 标题

func _draw_title() -> void:
	var vp := Vector2(960, 640)
	Art.vgrad(self, Rect2(Vector2.ZERO, vp), Color("#06070b"), Color("#161822"))
	# 路灯和光锥
	var lamp := Vector2(210, 150)
	draw_line(Vector2(lamp.x - 30, 560), Vector2(lamp.x - 30, lamp.y - 10), Color("#1a1c22"), 6)
	draw_line(Vector2(lamp.x - 30, lamp.y - 10), lamp + Vector2(0, -10), Color("#1a1c22"), 4)
	draw_colored_polygon(PackedVector2Array([lamp + Vector2(-10, 0), lamp + Vector2(10, 0), Vector2(lamp.x + 120, 560), Vector2(lamp.x - 120, 560)]), Color(1.0, 0.82, 0.5, 0.09))
	Art.ellipse(self, Vector2(lamp.x, 560), 130, 18, Color(1.0, 0.82, 0.5, 0.10))
	draw_circle(lamp, 9, Color("#ffe0a0"))
	draw_circle(lamp, 26, Color(1.0, 0.85, 0.5, 0.15))
	draw_rect(Rect2(0, 560, 960, 80), Color("#0b0c10"))
	draw_line(Vector2(0, 560), Vector2(960, 560), Color(C_ACCENT, 0.15), 1)
	# 侦探剪影
	var d := Vector2(lamp.x + 10, 552)
	var sil := Color("#050507")
	draw_colored_polygon(PackedVector2Array([d + Vector2(-24, 0), d + Vector2(24, 0), d + Vector2(16, -92), d + Vector2(-16, -92)]), sil)
	draw_colored_polygon(PackedVector2Array([d + Vector2(-20, -84), d + Vector2(20, -84), d + Vector2(14, -100), d + Vector2(-14, -100)]), sil)
	draw_circle(d + Vector2(0, -110), 11, sil)
	Art.ellipse(self, d + Vector2(0, -117), 22, 4, sil)
	draw_rect(Rect2(d + Vector2(-11, -134), Vector2(22, 17)), sil)
	draw_line(d + Vector2(8, -106), d + Vector2(24, -102), sil, 3)
	draw_circle(d + Vector2(26, -104), 4, sil)
	var ember := 0.6 + 0.4 * sin(t * 4.0)
	draw_circle(d + Vector2(26, -107), 2, Color(1.0, 0.55, 0.2, ember))
	for i in 7:
		var k := fposmod(t * 0.15 + i / 7.0, 1.0)
		var sp := d + Vector2(26 + sin(k * 6.0 + i) * 14 * k, -110 - k * 160)
		draw_circle(sp, 4 + k * 18, Color(0.85, 0.82, 0.75, 0.16 * (1.0 - k)))
	# 雨
	for i in 140:
		var x := fposmod(Art.h(i, 1) * 960 + t * 60, 960)
		var y := fposmod(Art.h(1, i) * 640 + t * (420 + Art.h(i, i) * 200), 640)
		draw_line(Vector2(x, y), Vector2(x - 3, y + 14), Color(0.7, 0.75, 0.85, 0.18), 1)
	# 标题
	_text_c("SHIFT", Vector2(650, 110), 64, C_ACCENT, SERIF)
	_text_c("烟 斗 侦 探", Vector2(650, 168), 30, Color("#efe6d2"), SERIF)
	_text_c("按 Shift 吐一口烟，烟雾里是案发当晚。", Vector2(650, 206), 14, C_DIM)
	# 档案夹
	var n := Levels.count()
	var step := minf(96.0, 330.0 / maxf(1.0, n))
	for i in n:
		var lv: Dictionary = Levels.info(i)
		var sel := i == title_pick
		var r := Rect2(Vector2(430 if sel else 446, 250 + i * step), Vector2(460, minf(80.0, step - 14)))
		draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.5))
		var folder := Color("#d8c08a") if sel else Color("#7a6a4c")
		draw_rect(Rect2(r.position + Vector2(16, -10), Vector2(110, 12)), folder.darkened(0.08))
		draw_rect(r, folder)
		draw_rect(r.grow(-4), Color(C_INK, 0.25), false, 1)
		_text("案卷 %d" % (i + 1), r.position + Vector2(24, 0), 11, Color(C_INK, 0.8))
		_text(String(lv.title), r.position + Vector2(24, 34), 21, C_INK, SERIF)
		_text(String(lv.theme), r.position + Vector2(24, 62), 13, Color(C_INK, 0.75))
		if sel:
			cv.draw_set_transform(r.position + Vector2(400, 42), -0.2, Vector2.ONE)
			cv.draw_rect(Rect2(-34, -16, 68, 32), Color("#a8322a"), false, 2)
			_text_c("调查", Vector2.ZERO, 16, Color("#a8322a"), SERIF)
			cv.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_text_c("↑↓ 选择   Enter 开始   数字键直接进入", Vector2(650, 600), 13, C_DIM)


# ---------------------------------------------------------------- 世界

func _draw_frame() -> void:
	var r := Rect2(ORIGIN, Vector2(game.W, game.H) * TS)
	draw_rect(r.grow(10), Color("#120f0b"))
	draw_rect(r.grow(10), Color(C_ACCENT, 0.35), false, 1.0)
	draw_rect(r.grow(5), Color(C_ACCENT, 0.18), false, 1.0)


func _wall(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= game.W or p.y >= game.H:
		return true
	return game.tile_at(p) == Game.Tile.WALL


func _draw_board() -> void:
	var th: Dictionary = Art.THEMES[clampi(int(game.L.get("style", 0)), 0, Art.THEMES.size() - 1)]
	var cold: Array = game.L.cold
	for y in game.H:
		for x in game.W:
			var p := Vector2i(x, y)
			var past: bool = game.in_window(p)
			var r := _cell(p)
			if _wall(p):
				Art.wall_tile(self, r, th, past, not _wall(p + Vector2i.DOWN), not _wall(p + Vector2i.LEFT), not _wall(p + Vector2i.RIGHT))
				continue
			# 地图里 "," 是室外地面，"." 是室内地面
			var kind: String = th.ring if String(game.L.map[y])[x] == "," else th.core
			Art.floor_tile(self, r, p, kind, past, cold.has(p))
			if _wall(p + Vector2i.UP):
				Art.wall_shadow(self, r)
			# 门洞：墙线上的单格缺口（排除一格宽的走廊）
			var L := p + Vector2i.LEFT
			var R := p + Vector2i.RIGHT
			var U := p + Vector2i.UP
			var D := p + Vector2i.DOWN
			if _wall(L) and _wall(R) and not _wall(U) and not _wall(D) and not _wall(L + Vector2i.UP) and not _wall(L + Vector2i.DOWN):
				Art.doorway(self, r, false, past)
			elif _wall(U) and _wall(D) and not _wall(L) and not _wall(R) and not _wall(U + Vector2i.LEFT) and not _wall(U + Vector2i.RIGHT):
				Art.doorway(self, r, true, past)


func _draw_later() -> void:
	for lt in game.d.later_active:
		if game.in_window(lt.pos):
			continue
		Art.later(self, _cell(lt.pos), lt.kind)


func _draw_ent(e: Dictionary) -> void:
	var done: bool = (e.kind in ["cache", "clue"] and game.s.clues.has(e.get("clue", ""))) \
		or (e.kind == "container" and e.get("taken", false))
	Art.entity(self, _cell(e.pos), e, game.in_window(e.pos), t, done)


## 烟丝锚点：所有烟丝来源用同一个模型（烟丝罐）。
## 当前时代拿得到的画实体；另一个时代的画成虚影，让玩家提前规划路线。
## 同一格两个时代都有东西时，先画现在的，现在的没了才露出过去的虚影。
func _draw_anchors() -> void:
	for e in game.anchors():
		var shown: bool = game.in_window(e.pos) == (e.era == "past")
		if shown:
			continue  # 实体已经由 _draw_ent 画出
		var other: Array = game.present_ents() if e.era == "past" else game.past_ents()
		var covered := false
		for o in other:
			if o.pos == e.pos and o.id != e.id:
				covered = true
				break
		if covered:
			continue
		var pulse := 0.5 + 0.5 * sin(t * 2.0)
		Art.tin(self, _cell(e.pos), 0.3 + 0.15 * pulse, false, t)


## 烟雾里能看到的人，画出他们接下来要走的路（一串脚印）
func _draw_routes() -> void:
	for e in game.past_ents():
		if e.kind != "npc" or not e.has("route") or not game.in_window(e.pos):
			continue
		var path: Array = game.route_of(e.id)
		var steps := 0
		for i in range(1, path.size()):
			var a: Vector2i = path[i - 1]
			var b: Vector2i = path[i]
			if a == b:
				continue
			steps += 1
			var ca := _cell(a).get_center()
			var cb := _cell(b).get_center()
			var dir := (cb - ca).normalized()
			var side := Vector2(-dir.y, dir.x) * TS * 0.13 * (1.0 if steps % 2 == 0 else -1.0)
			var k := fposmod(t * 1.2 - steps * 0.1, 1.0)
			var col := Color(C_ACCENT, 0.35 + 0.55 * k)
			for f in [0.25, 0.75]:
				draw_set_transform(ca.lerp(cb, f) + side * (1.0 if f < 0.5 else -1.0), dir.angle(), Vector2.ONE)
				Art.ellipse(self, Vector2.ZERO, TS * 0.11, TS * 0.06, col)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var end := _cell(path[path.size() - 1]).get_center()
		var s := TS * 0.18
		draw_line(end - Vector2(s, s), end + Vector2(s, s), C_ACCENT, 2.0)
		draw_line(end - Vector2(s, -s), end + Vector2(s, -s), C_ACCENT, 2.0)


func _draw_player() -> void:
	var s: Dictionary = game.s
	var r := _cell(s.pos)
	var past: bool = game.in_window(s.pos)
	var u := TS / 32.0
	# 脚下一圈金色光晕，让玩家一眼找到侦探
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	Art.ellipse(self, r.get_center() + Vector2(0, 9) * u, 14 * u, 6 * u, Color(C_ACCENT, 0.18 + 0.12 * pulse))
	draw_arc(r.get_center() + Vector2(0, 2) * u, 15 * u, 0, TAU, 28, Color(C_ACCENT, 0.35 + 0.3 * pulse), maxf(1.0, u * 1.2))
	Art.person(self, r, "detective", past, t, s.tobacco > 0)
	var bowl := r.get_center() + Vector2(10, -2) * u
	if s.tobacco > 0:
		for i in 4:
			var k := fposmod(t * 0.6 + i * 0.25, 1.0)
			var p := bowl + Vector2(sin(t * 2.0 + i * 1.7) * 3 * u * k, -k * TS * 0.9)
			draw_circle(p, (1.5 + k * 4.0) * u, Color(0.9, 0.88, 0.82, 0.45 * (1.0 - k)))


func _draw_tags(ents: Array) -> void:
	var me: Vector2i = game.s.pos
	for e in ents:
		if e.kind not in ["npc", "inspector"]:
			continue
		var dp: Vector2i = e.pos - me
		if maxi(absi(dp.x), absi(dp.y)) > 2:
			continue
		Art.name_tag(self, _cell(e.pos), String(e.get("name", "警探")))


func _draw_smoke() -> void:
	var s: Dictionary = game.s
	if not s.cloud:
		return
	var c: Vector2i = s.center
	var rect := Rect2(ORIGIN + Vector2(c - Vector2i.ONE) * TS, Vector2(TS * 3, TS * 3))
	var density := float(s.turns) / Game.SMOKE_TURNS
	draw_rect(rect, Color(1.0, 0.85, 0.6, 0.05))
	# 烟雾边缘：沿四边翻滚的烟团，越淡烟团越小
	var per := 9
	for side in 4:
		for i in per:
			var k := (i + 0.5) / per
			var a := t * 0.7 + i * 1.3 + side * 2.1
			var pos: Vector2
			match side:
				0:
					pos = rect.position + Vector2(rect.size.x * k, 0)
				1:
					pos = Vector2(rect.end.x, rect.position.y + rect.size.y * k)
				2:
					pos = Vector2(rect.end.x - rect.size.x * k, rect.end.y)
				_:
					pos = Vector2(rect.position.x, rect.end.y - rect.size.y * k)
			pos += Vector2(sin(a), cos(a * 1.3)) * TS * 0.08
			var rad := TS * (0.17 + 0.06 * sin(a * 0.8)) * (0.55 + 0.45 * density)
			draw_circle(pos, rad * 1.6, Color(0.9, 0.87, 0.8, 0.08 * (0.5 + density)))
			draw_circle(pos, rad, Color(0.96, 0.93, 0.86, 0.2 * (0.4 + density)))
	# 浓度：上沿一排小点，每个行动用掉一个
	for i in Game.SMOKE_TURNS:
		var dp := rect.position + Vector2(rect.size.x * (i + 0.5) / Game.SMOKE_TURNS, -TS * 0.3)
		var rr := maxf(2.0, TS * 0.07)
		if i < s.turns:
			draw_circle(dp, rr, Color(0.97, 0.93, 0.85, 0.95))
		else:
			draw_arc(dp, rr, 0, TAU, 10, Color(1, 1, 1, 0.3), 1.0)


# ---------------------------------------------------------------- 界面

func _draw_hud() -> void:
	var s: Dictionary = game.s
	cv.draw_rect(Rect2(0, 0, 960, 62), Color("#0b0c10"))
	cv.draw_line(Vector2(0, 62), Vector2(960, 62), Color(C_ACCENT, 0.6), 1)
	cv.draw_line(Vector2(0, 65), Vector2(960, 65), Color(C_ACCENT, 0.22), 1)
	# 左：案件名和时代
	_text(game.L.title, Vector2(48, 30), 20, C_ACCENT, SERIF)
	var era_txt: String = ("烟雾里 · " + game.L.past_label) if s.cloud else ("现在 · " + game.L.present_label)
	_text(era_txt, Vector2(48, 53), 13, Color("#e8b070") if s.cloud else Color("#8fa4c8"))
	# 中：烟丝和烟灰
	_text("烟丝", Vector2(330, 28), 14, C_DIM)
	var n := maxi(s.tobacco, 1)
	for i in n:
		Art.tin(cv, Rect2(Vector2(364 + i * 22, 8), Vector2(24, 24)), 1.0 if i < s.tobacco else 0.25, false, t)
	_text("×%d" % s.tobacco, Vector2(364 + n * 22 + 4, 28), 14, C_TEXT)
	var ax := 364.0 + n * 22 + 44
	_text("烟灰", Vector2(ax, 28), 14, C_DIM)
	for i in mini(s.ash, 6):
		Art.ellipse(cv, Vector2(ax + 42 + i * 12, 22), 5, 3, Color("#8a8680"))
	_text("×%d" % s.ash, Vector2(ax + 44 + mini(s.ash, 6) * 12, 28), 14, C_TEXT)
	var now_n := 0
	var now_amt := 0
	var past_n := 0
	var past_amt := 0
	for a in game.anchors():
		if a.era == "past":
			past_n += 1
			past_amt += a.amount
		else:
			now_n += 1
			now_amt += a.amount
	_text("烟丝锚点：现在 %d 处 +%d · 过去 %d 处 +%d" % [now_n, now_amt, past_n, past_amt], Vector2(330, 53), 12, Color(C_ACCENT, 0.8))
	# 右：三类证据的档案标签
	var x := 612.0
	for i in game.L.categories.size():
		var ok: bool = game.has_category(i)
		var r := Rect2(Vector2(x, 10), Vector2(94, 26))
		if ok:
			cv.draw_rect(r, Color("#d8c08a"))
			_text_c(game.L.categories[i][1], r.get_center() + Vector2(-8, 0), 14, C_INK, SERIF)
			_text_c("✓", r.get_center() + Vector2(30, 0), 16, Color("#a8322a"))
		else:
			cv.draw_rect(r, Color(1, 1, 1, 0.04))
			cv.draw_rect(r, Color(C_DIM, 0.6), false, 1)
			_text_c(game.L.categories[i][1], r.get_center(), 14, C_DIM, SERIF)
		x += 100
	var clue_txt := ""
	for c in s.clues:
		clue_txt += game.clue_name(c) + "  "
	if clue_txt != "":
		_text("证据：" + clue_txt, Vector2(612, 53), 12, C_DIM)


func _draw_message() -> void:
	var s: Dictionary = game.s
	var r := Rect2(48, 558, 864, 62)
	cv.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.55))
	cv.draw_rect(r, C_PAPER)
	cv.draw_line(Vector2(r.position.x + 30, r.position.y), Vector2(r.position.x + 30, r.end.y), Color("#c0504a", 0.55), 1)
	if s.mode == "choice":
		cv.draw_rect(r.grow(1), C_ACCENT, false, 2.0)
	var lines: PackedStringArray = String(s.msg).split("\n")
	for i in mini(lines.size(), 3):
		_text(lines[i], Vector2(r.position.x + 42, r.position.y + 19 + i * 19), 15, C_INK)
	_text("方向键 移动/互动   Shift 吐烟   1/2 选择   Esc 取消/回选关   Z 撤销   Backspace 重来",
		Vector2(48, 634), 12, C_DIM)


func _draw_end() -> void:
	var s: Dictionary = game.s
	var vp := Vector2(960, 640)
	cv.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.75))
	var card := Rect2(vp / 2 - Vector2(300, 150), Vector2(600, 300))
	cv.draw_rect(Rect2(card.position + Vector2(6, 8), card.size), Color(0, 0, 0, 0.6))
	cv.draw_rect(card, C_PAPER)
	cv.draw_rect(card.grow(-8), Color(C_INK, 0.3), false, 1)
	var win: bool = s.outcome == "win"
	var stamp := "结 案" if win else "指认失败"
	cv.draw_set_transform(card.position + Vector2(470, 70), -0.18, Vector2.ONE)
	cv.draw_rect(Rect2(-70, -28, 140, 56), Color("#a8322a"), false, 3)
	_text_c(stamp, Vector2.ZERO, 28 if win else 22, Color("#a8322a"), SERIF)
	cv.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_text(game.L.title, card.position + Vector2(36, 60), 22, C_INK, SERIF)
	var y := card.position.y + 120
	if win:
		var used: Array = []
		for c in s.clues:
			used.append(game.clue_name(c))
		_text("证据：" + "、".join(used), Vector2(card.position.x + 36, y), 15, C_INK)
		y += 28
	for line in String(s.msg).split("\n"):
		_text(line, Vector2(card.position.x + 36, y), 14, Color(C_INK, 0.8))
		y += 22
	var next := ""
	if win:
		next = "按 Enter 进入下一个案件" if game.level_idx < Levels.count() - 1 else "全部案件结案。按 Enter 回到选关"
	else:
		next = "按 Backspace 重来，Enter 回到选关"
	_text_c(next, Vector2(vp.x / 2, card.end.y - 28), 15, Color("#8a5a20"))


func _text(str: String, pos: Vector2, size: int, col: Color, font: Font = FONT) -> void:
	cv.draw_string(font, pos, str, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_c(str: String, center: Vector2, size: int, col: Color, font: Font = FONT) -> void:
	Art.text_center(cv, font, str, center, size, col)
