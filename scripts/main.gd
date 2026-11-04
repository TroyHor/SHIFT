extends Node2D
## 画面与输入。世界是 3D 俯视角（见 board3d.gd），界面仍是 2D，全部程序化绘制，不依赖贴图。
## 图层：3D 世界 → 0 名牌等跟着世界走的标注 → 1 烟雾颗粒、暗角、胶片颗粒 → 2 界面。

const GameLogic := preload("res://scripts/game.gd")
const FONT := preload("res://assets/fonts/NotoSansSC-Subset.ttf")
const SERIF := preload("res://assets/fonts/NotoSerifSC-Subset.ttf")

## 棋盘区域：3D 镜头把整张地图放进这里
const BOARD := Rect2(48, 76, 864, 470)

const C_BG := Color("#08090d")
const C_TEXT := Color("#e8e4da")
const C_DIM := Color("#8a8f9e")
const C_ACCENT := Color("#e0b46a")
const C_RED := Color("#c9533b")
const C_INK := Color("#2a2018")
const C_PAPER := Color("#e9dfc8")

## 全屏：暗角和胶片颗粒
const LIGHT_SHADER := """
shader_type canvas_item;
uniform vec2 view = vec2(960.0, 640.0);
uniform float time_s = 0.0;
uniform float title = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 p = UV * view;
	vec2 q = UV - 0.5;
	float vig = smoothstep(0.38, 0.9, length(q * vec2(1.0, 1.3)));
	float a = vig * (0.85 - title * 0.15);
	float gr = hash(floor(p / 2.0) + floor(time_s * 24.0)) - 0.5;
	a = clamp(a + gr * 0.05, 0.0, 1.0);
	COLOR = vec4(0.01, 0.02, 0.05, a);
}
"""

## 烟雾窗口：老胶片的颗粒和划痕，只盖在 3x3 上
const SMOKE_SHADER := """
shader_type canvas_item;
uniform float density = 0.0;
uniform float time_s = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 p = FRAGCOORD.xy;
	float g = hash(floor(p / 2.0) + floor(time_s * 18.0)) - 0.5;
	float scratch = step(0.993, hash(vec2(floor(p.x / 2.0), floor(time_s * 9.0))));
	float wv = smoothstep(0.3, 0.75, length(UV - 0.5));
	vec3 col = mix(vec3(0.22, 0.12, 0.04), vec3(0.95, 0.88, 0.7), scratch);
	COLOR = vec4(col, 0.02 + abs(g) * 0.1 * (0.4 + density) + wv * 0.25 + scratch * 0.3);
}
"""

var game = GameLogic.new(0)
var t := 0.0
var title := true
var title_pick := 0


var ui: Node2D
var light: ColorRect
var light_mat: ShaderMaterial
var smoke_fx: Node2D
var smoke_mat: ShaderMaterial
var world: Board3D
var editor: LevelEditor
var editing := false  # 在游戏内编辑器里
var testing := false  # 从编辑器进来试玩


func _ready() -> void:
	RenderingServer.set_default_clear_color(C_BG)
	Art.add_font_fallback()
	world = Board3D.new()
	add_child(world)
	world.setup(game, BOARD)
	world.visible = false
	var l1 := CanvasLayer.new()
	l1.layer = 1
	add_child(l1)
	smoke_fx = Node2D.new()
	smoke_mat = ShaderMaterial.new()
	smoke_mat.shader = Shader.new()
	smoke_mat.shader.code = SMOKE_SHADER
	smoke_fx.material = smoke_mat
	smoke_fx.draw.connect(_draw_smoke_fx)
	l1.add_child(smoke_fx)
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
	var l3 := CanvasLayer.new()
	l3.layer = 3
	add_child(l3)
	editor = LevelEditor.new()
	editor.world = world
	editor.visible = false
	editor.play_requested.connect(_play_from_editor)
	editor.closed.connect(_close_editor)
	l3.add_child(editor)
	# 在 Godot 里按 F6 试玩某一关：关卡场景把自己的路径留在 Levels.test_path，跳到这里直接开始
	if Levels.test_path != "":
		var idx := Levels.index_of(Levels.test_path)
		Levels.test_path = ""
		if idx >= 0:
			_start(idx)


var smoke_t := 0.0  # 这口烟吐出来多久了（对话框弹出动画用）
var _was_cloud := false


func _process(delta: float) -> void:
	t += delta
	if not title and not editing:
		if game.s.cloud and not _was_cloud:
			smoke_t = 0.0
		_was_cloud = game.s.cloud
		smoke_t += delta
		_update_hover()
	queue_redraw()
	ui.queue_redraw()
	smoke_fx.queue_redraw()
	_update_light()


func _unhandled_input(event: InputEvent) -> void:
	if editing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not title and game.s.mode == "play":
			var p = _pick(event.position)
			if p != null:
				game.interact(p)
				world.refresh()
				get_viewport().set_input_as_handled()
		return
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
			KEY_E:
				_open_editor(title_pick)
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
			elif testing:
				_back_to_editor()
				return
			else:
				_to_title()
		KEY_ENTER, KEY_KP_ENTER:
			if game.s.mode == "end":
				if testing:
					_back_to_editor()
					return
				if game.s.outcome == "win" and game.level_idx < Levels.count() - 1:
					_start(game.level_idx + 1)
				else:
					_to_title()
		_:
			return
	get_viewport().set_input_as_handled()
	if not title:
		world.refresh()


func _start(idx: int) -> void:
	game.load_level(idx)
	title_pick = idx
	title = false
	testing = false
	world.game = game
	world.board = BOARD
	world.visible = true
	world.refresh()


func _to_title() -> void:
	title = true
	testing = false
	world.visible = false


# ---------------------------------------------------------------- 游戏内编辑器

func _open_editor(idx: int) -> void:
	title = false
	editing = true
	world.visible = true
	editor.visible = true
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	world.set_edit_light(true)
	editor.open_level(Levels.paths()[clampi(idx, 0, Levels.count() - 1)])


func _play_from_editor(level: Dictionary) -> void:
	editing = false
	testing = true
	editor.visible = false
	world.set_edit_light(false)
	game.load_data(level)
	world.game = game
	world.board = BOARD
	world.refresh()


func _back_to_editor() -> void:
	testing = false
	editing = true
	editor.visible = true
	world.set_edit_light(true)
	world.set_hover(Vector2i.ZERO, false, false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	editor._rebuild_preview()


func _close_editor() -> void:
	editing = false
	editor.visible = false
	world.set_edit_light(false)
	world.game = game
	world.board = BOARD
	Levels.reload()
	title_pick = clampi(title_pick, 0, Levels.count() - 1)
	_to_title()


## 鼠标指着的格子：优先找画面上离鼠标最近的人或物件，否则按地面算格子
func _pick(mp: Vector2) -> Variant:
	var best = null
	var best_d := INF
	for e in game.visible_ents():
		if not e.get("solid", true):
			continue
		var c := world.screen_e(e, 0.3)
		var cell_px := world.screen(e.pos + Vector2i.RIGHT, 0.3).distance_to(c)
		var dd := mp.distance_to(c)
		if dd < cell_px * 0.62 and dd < best_d:
			best_d = dd
			best = e.pos
	if best != null:
		return best
	var g = world.ground_cell(mp)
	if g != null and game.thing_at(g) != null:
		return g
	return null


func _update_hover() -> void:
	var p = null
	if game.s.mode == "play":
		p = _pick(get_viewport().get_mouse_position())
	if p == null:
		world.set_hover(Vector2i.ZERO, false, false)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	else:
		var ok: bool = game.in_reach(p)
		world.set_hover(p, true, ok)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if ok else Input.CURSOR_ARROW)


## 当前画在哪一层（世界或界面），文字等辅助函数都画到这里
var cv: CanvasItem


func _draw() -> void:
	cv = self
	if title:
		_draw_title()
		return
	if editing:
		return
	_draw_tags()
	_draw_density()
	_draw_bubbles()


func _draw_ui() -> void:
	cv = ui
	if title or editing:
		return
	_draw_hud()
	_draw_message()
	if game.s.mode == "end":
		_draw_end()


func _update_light() -> void:
	light_mat.set_shader_parameter("time_s", t)
	light_mat.set_shader_parameter("title", 1.0 if title else 0.0)
	smoke_mat.set_shader_parameter("time_s", t)
	if not title and game.s.cloud:
		smoke_mat.set_shader_parameter("density", float(game.s.turns) / Game.SMOKE_TURNS)


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
	# 档案夹：关卡少时每个一张大卡片，多时排成一列标签，选中的那张展开
	var n := Levels.count()
	if n <= 4:
		for i in n:
			_folder(i, Rect2(Vector2(430 if i == title_pick else 446, 250 + i * 82), Vector2(460, 68)), true)
	else:
		var rows := mini(n, 7)
		var first := clampi(title_pick - rows / 2, 0, n - rows)
		var y := 236.0
		for i in range(first, first + rows):
			var sel := i == title_pick
			var h := 66.0 if sel else 36.0
			_folder(i, Rect2(Vector2(430 if sel else 446, y), Vector2(460, h)), sel)
			y += h + 8
	_text_c("↑↓ 选择   Enter 开始   数字键直接进入   E 编辑这一关", Vector2(650, 600), 13, C_DIM)


func _folder(i: int, r: Rect2, full: bool) -> void:
	var lv: Dictionary = Levels.info(i)
	var sel := i == title_pick
	draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.5))
	var folder := Color("#d8c08a") if sel else Color("#7a6a4c")
	draw_rect(Rect2(r.position + Vector2(16, -8), Vector2(90, 10)), folder.darkened(0.08))
	draw_rect(r, folder)
	draw_rect(r.grow(-4), Color(C_INK, 0.25), false, 1)
	_text("%d" % (i + 1), r.position + Vector2(14, 24), 13, Color(C_INK, 0.6))
	if full:
		_text(String(lv.title), r.position + Vector2(36, 30), 20, C_INK, SERIF)
		_text(String(lv.theme), r.position + Vector2(36, 55), 13, Color(C_INK, 0.75))
	else:
		_text(String(lv.title), r.position + Vector2(36, 24), 15, Color(C_INK, 0.85), SERIF)
	if sel:
		cv.draw_set_transform(r.position + Vector2(408, r.size.y / 2), -0.2, Vector2.ONE)
		cv.draw_rect(Rect2(-32, -15, 64, 30), Color("#a8322a"), false, 2)
		_text_c("调查", Vector2.ZERO, 15, Color("#a8322a"), SERIF)
		cv.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


# ---------------------------------------------------------------- 世界上的标注

## 烟雾窗口的四个角在屏幕上的位置
func _window_corners() -> PackedVector2Array:
	var c := Board3D.at(game.s.center)
	var pts := PackedVector2Array()
	for o in [Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(1.5, 0, 1.5), Vector3(-1.5, 0, 1.5)]:
		pts.append(world.screen_v(c + o))
	return pts


func _draw_smoke_fx() -> void:
	if title or editing or not game.s.cloud:
		return
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	smoke_fx.draw_polygon(_window_corners(), PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs)


## 侦探身边两格以内的人，头顶显示名牌
func _draw_tags() -> void:
	var me: Vector2i = game.s.pos
	for e in game.visible_ents():
		if e.kind not in ["npc", "inspector"]:
			continue
		var dp: Vector2i = e.pos - me
		if maxi(absi(dp.x), absi(dp.y)) > 2:
			continue
		var c := world.screen_e(e, 0.98)
		var s := String(e.get("name", "警探"))
		var size := 12
		var w := FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 10
		var r := Rect2(c - Vector2(w / 2, 9), Vector2(w, 18))
		draw_rect(r, Color(0.05, 0.05, 0.07, 0.82))
		draw_rect(r, Color(C_ACCENT, 0.5), false, 1.0)
		Art.text_center(self, FONT, s, c, size, Color("#efe6d2"))


const WOW_LINES := ["好厉害……", "这烟里……是昨晚？", "我没看花眼吧？", "天哪……", "这是什么戏法？"]


## 烟雾旁边的人看得到烟里的过去：头顶冒出对话框；看见过去的自己会吓一跳
func _draw_bubbles() -> void:
	var looks: Dictionary = game.onlookers()
	if looks.is_empty():
		return
	var pop := clampf(smoke_t * 5.0, 0.0, 1.0)
	for e in game.present_ents():
		if not looks.has(e.id):
			continue
		var line: String
		if looks[e.id] == "self":
			line = "那……那是我？！"
		elif e.kind == "inspector":
			line = "又是你那烟斗戏法。"
		else:
			line = WOW_LINES[absi(hash(e.id)) % WOW_LINES.size()]
		var head := world.screen_e(e, 1.3)
		var size := 12
		var w := FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14
		var shake := Vector2(sin(t * 55.0) * 1.5, 0) if looks[e.id] == "self" else Vector2.ZERO
		var c := head + Vector2(0, -14) + shake
		draw_set_transform(c, 0, Vector2.ONE * (0.4 + 0.6 * pop))
		var r := Rect2(Vector2(-w / 2, -11), Vector2(w, 22))
		draw_rect(r, Color("#f4ecd8"))
		draw_rect(r, Color(C_INK, 0.8), false, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-5, 10), Vector2(5, 10), Vector2(0, 18)]), Color("#f4ecd8"))
		draw_line(Vector2(-5, 11), Vector2(0, 18), Color(C_INK, 0.8), 1.0)
		draw_line(Vector2(5, 11), Vector2(0, 18), Color(C_INK, 0.8), 1.0)
		Art.text_center(self, FONT, line, Vector2.ZERO, size, Color("#a8322a") if looks[e.id] == "self" else C_INK)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## 烟雾浓度：窗口上沿一排小点，每个行动用掉一个
func _draw_density() -> void:
	var s: Dictionary = game.s
	if not s.cloud:
		return
	var c := Board3D.at(s.center)
	for i in Game.SMOKE_TURNS:
		var x := -1.4 + 2.8 * (i + 0.5) / Game.SMOKE_TURNS
		var dp := world.screen_v(c + Vector3(x, 0.95, -1.5))
		if i < s.turns:
			draw_circle(dp, 3.0, Color(0.97, 0.93, 0.85, 0.95))
		else:
			draw_arc(dp, 3.0, 0, TAU, 10, Color(1, 1, 1, 0.3), 1.0)


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
	if now_n + past_n > 0:
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
	_text("方向键 移动   走到旁边点击 互动   Shift 吐烟   1/2 选择   Esc 取消/%s   Z 撤销   Backspace 重来" % ("回编辑器" if testing else "回选关"),
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
	if testing:
		next = "按 Enter 回到编辑器"
	elif win:
		next = "按 Enter 进入下一个案件" if game.level_idx < Levels.count() - 1 else "全部案件结案。按 Enter 回到选关"
	else:
		next = "按 Backspace 重来，Enter 回到选关"
	_text_c(next, Vector2(vp.x / 2, card.end.y - 28), 15, Color("#8a5a20"))


func _text(str: String, pos: Vector2, size: int, col: Color, font: Font = FONT) -> void:
	cv.draw_string(font, pos, str, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_c(str: String, center: Vector2, size: int, col: Color, font: Font = FONT) -> void:
	Art.text_center(cv, font, str, center, size, col)
