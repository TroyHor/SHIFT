@tool
class_name Art
extends RefCounted
## 画面：全部用 _draw() 程序化绘制，不依赖贴图。
## 物件都用"真实颜色"定义，再按时代调色：现在是冷蓝夜色，过去是暖褐老照片。

const SANS := preload("res://assets/fonts/NotoSansSC-Subset.ttf")
const SERIF := preload("res://assets/fonts/NotoSerifSC-Subset.ttf")

const GOLD := Color("#e0b46a")
const INK := Color("#2a2018")
const PAPER := Color("#e9dfc8")

## 每个案件的场景主题：核心区域地面、外圈地面、墙
const THEMES := [
	{"core": "parquet", "ring": "garden", "cap": Color("#3b2a22"), "face": Color("#46584a"), "trim": Color("#8a6a40")},
	{"core": "planks", "ring": "snow", "cap": Color("#3a2c24"), "face": Color("#6a4a34"), "trim": Color("#9a7a50")},
	{"core": "carpet", "ring": "platform", "cap": Color("#2a2a30"), "face": Color("#5a3a28"), "trim": Color("#b08a50")},
]

## 实体 id → 画法
const SPRITES := {
	"desk": "desk", "table1": "table", "table2": "table", "bench": "chair", "crates": "crates",
	"plant": "plant", "horse": "horse", "snowman": "snowman", "barrels": "barrel", "cache": "cache",
	"cart": "cart", "shelf": "bookshelf", "wardrobe": "wardrobe", "safe_now": "safe", "safe_then": "safe",
	"rack_now": "rack", "rack_then": "rack", "candle": "candle", "woodpile": "logs", "ledger": "book",
	"telegram": "paper", "bed": "bed", "tools_now": "toolbox", "tools_then": "toolbox", "ice": "ice",
	"ashtray_a": "ashtray", "ashtray_b": "ashtray",
}

## 人物造型
const PEOPLE := {
	"detective": {"coat": Color("#c09a62"), "skin": Color("#d8b090"), "hat": "fedora", "hatc": Color("#2e2620")},
	"inspector": {"coat": Color("#2c3e66"), "skin": Color("#d8b090"), "hat": "cap", "hatc": Color("#1c2846")},
	"butler": {"coat": Color("#1c1c22"), "skin": Color("#d8b090"), "hat": "hair", "hatc": Color("#4a4a4a"), "detail": "collar"},
	"maid": {"coat": Color("#2c2a3a"), "skin": Color("#e0b898"), "hat": "bonnet", "hatc": Color("#5a3a24"), "detail": "apron"},
	"cook": {"coat": Color("#e6e0d2"), "skin": Color("#d8a888"), "hat": "chef", "hatc": Color("#f2eee4")},
	"clerk": {"coat": Color("#6b4a2e"), "skin": Color("#d8b090"), "hat": "hair", "hatc": Color("#9a9a9a"), "detail": "belt"},
	"conductor": {"coat": Color("#22305a"), "skin": Color("#d8b090"), "hat": "cap", "hatc": Color("#18224a")},
	"passenger": {"coat": Color("#5a5a62"), "skin": Color("#e0c0a0"), "hat": "top", "hatc": Color("#141418")},
	"porter": {"coat": Color("#7a2a2a"), "skin": Color("#c89878"), "hat": "pillbox", "hatc": Color("#b83a32")},
}


## 字体是按游戏里用到的字裁剪过的。关卡里新写的字如果还没裁进去，
## 桌面版和编辑器先用系统自带的中文字体补上（网页版要重新运行 tools/subset_font.py）。
static func add_font_fallback() -> void:
	if not SANS.fallbacks.is_empty() or DisplayServer.get_name() == "headless":
		return
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
	SANS.set("fallbacks", [sf])
	SERIF.set("fallbacks", [sf])


# ---------------------------------------------------------------- 选画法

static func base_id(e: Dictionary) -> String:
	var id: String = e.get("src", e.get("id", ""))
	return id.split("#")[0]


## 人物造型：优先用关卡里填的 sprite，否则按 id 猜
static func style_for(e: Dictionary) -> String:
	if e.get("kind", "") == "inspector":
		return "inspector"
	var sp: String = e.get("sprite", "")
	if PEOPLE.has(sp):
		return sp
	var id := base_id(e)
	for k in PEOPLE:
		if id.begins_with(k):
			return k
	return "butler"


## 物件画法：优先用关卡里填的 sprite，否则按 id 查表；查不到就画成带字的方块
static func sprite_for(e: Dictionary) -> String:
	var sp: String = e.get("sprite", "")
	if sp != "":
		return sp
	var key := base_id(e)
	var s: String = SPRITES.get(key, "")
	if e.get("burnt", false):
		s = "wax" if key == "candle" else "embers"
	return s


## 画一个实体（人物、烟丝罐或物件），供游戏和 Godot 编辑器共用
static func entity(ci: CanvasItem, cell: Rect2, e: Dictionary, past: bool, t: float, done: bool) -> void:
	var kind: String = e.get("kind", "")
	if kind == "source" or e.get("model", "") == "tin":
		tin(ci, cell, 1.0, kind == "source", t)
	elif kind in ["inspector", "npc"]:
		person(ci, cell, style_for(e), past, t, false)
	else:
		thing(ci, cell, sprite_for(e), e, past, t, done)


# ---------------------------------------------------------------- 基础

static func grade(c: Color, past: bool) -> Color:
	var l := c.get_luminance()
	if past:
		var sep := Color("#3a2614").lerp(Color("#f4e2bc"), clampf(l * 1.1, 0.0, 1.0))
		return Color(sep.lerp(c, 0.22), c.a)
	var cool := Color(l * 0.78, l * 0.88, l * 1.12)
	return Color(cool.lerp(c, 0.38).darkened(0.08), c.a)


static func h(x: float, y: float) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


static func vgrad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


static func box(ci: CanvasItem, r: Rect2, col: Color, past: bool, u: float) -> void:
	## 带投影和描边的方块家具
	ci.draw_rect(Rect2(r.position + Vector2(2, 3) * u, r.size), Color(0, 0, 0, 0.35))
	var g := grade(col, past)
	ci.draw_rect(r, g)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(2.0, r.size.y * 0.14))), g.lightened(0.12))
	ci.draw_rect(r, g.darkened(0.45), false, maxf(1.0, u))


static func text_center(ci: CanvasItem, font: Font, s: String, center: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	ci.draw_string(font, center + Vector2(-w / 2, (asc - desc) / 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---------------------------------------------------------------- 地面与墙

static func floor_tile(ci: CanvasItem, r: Rect2, p: Vector2i, kind: String, past: bool, cold: bool) -> void:
	var u := r.size.x / 32.0
	var n := h(p.x, p.y)
	match kind:
		"parquet", "planks":
			var base := Color("#6a4a30") if kind == "parquet" else Color("#7a5a3a")
			var rows := 3
			for i in rows:
				var rr := Rect2(r.position + Vector2(0, r.size.y * i / rows), Vector2(r.size.x, r.size.y / rows))
				var v := h(p.x * 3 + i, p.y * 7) * 0.12 - 0.06
				ci.draw_rect(rr, grade(base.lightened(v), past))
				ci.draw_line(rr.position, Vector2(rr.end.x, rr.position.y), grade(base.darkened(0.35), past), maxf(1.0, u * 0.8))
				var seam := r.position.x + r.size.x * fposmod(0.3 + 0.37 * (i + p.y * 2 + p.x), 1.0)
				ci.draw_line(Vector2(seam, rr.position.y), Vector2(seam, rr.end.y), grade(base.darkened(0.3), past), maxf(1.0, u * 0.8))
			if kind == "parquet" and (p.x + p.y) % 2 == 0:
				ci.draw_rect(r, Color(0, 0, 0, 0.06))
		"carpet":
			ci.draw_rect(r, grade(Color("#6a2026"), past))
			var gd := grade(Color("#b08a50"), past)
			var c := r.get_center()
			var s := r.size.x * 0.16
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), Color(gd, 0.55))
			ci.draw_rect(r, Color(grade(Color("#4a1418"), past), 0.6), false, maxf(1.0, u))
		"garden":
			ci.draw_rect(r, grade(Color("#3e5236").lightened(n * 0.08), past))
			for i in 3:
				var q := r.position + Vector2(h(p.x + i, p.y) * r.size.x, h(p.y + i, p.x) * r.size.y)
				ci.draw_line(q, q + Vector2(u, -3 * u), grade(Color("#5a7448"), past), maxf(1.0, u * 0.8))
		"snow":
			ci.draw_rect(r, grade(Color("#d6dde4").darkened(n * 0.08), past))
			ci.draw_circle(r.position + Vector2(h(p.x, p.y + 3), h(p.y, p.x + 5)) * r.size, u * 1.5, grade(Color("#f4f6f8"), past))
		"platform":
			ci.draw_rect(r, grade(Color("#5a5a5e").lightened(n * 0.06), past))
			ci.draw_rect(r, grade(Color("#3a3a3e"), past), false, maxf(1.0, u * 0.8))
		_:
			ci.draw_rect(r, grade(Color("#555555"), past))
	if cold:
		ci.draw_rect(r, Color(grade(Color("#9fd0e8"), past), 0.22))
		for i in 2:
			var q := r.position + Vector2(h(p.x * 5 + i, p.y), h(p.y * 3, p.x + i)) * r.size
			ci.draw_circle(q, u, Color(1, 1, 1, 0.35))


static func wall_tile(ci: CanvasItem, r: Rect2, theme: Dictionary, past: bool, face: bool, shade_l: bool, shade_r: bool) -> void:
	var u := r.size.x / 32.0
	var cap := grade(theme.cap, past)
	ci.draw_rect(r, cap)
	ci.draw_rect(r.grow(-u * 2), cap.lightened(0.05))
	if face:
		var fr := Rect2(Vector2(r.position.x, r.position.y + r.size.y * 0.55), Vector2(r.size.x, r.size.y * 0.45))
		var fc := grade(theme.face, past)
		ci.draw_rect(fr, fc)
		for i in 3:
			var x := fr.position.x + fr.size.x * (i + 0.5) / 3.0
			ci.draw_line(Vector2(x, fr.position.y), Vector2(x, fr.end.y), fc.darkened(0.2), maxf(1.0, u))
		ci.draw_line(fr.position, Vector2(fr.end.x, fr.position.y), grade(theme.trim, past), maxf(1.5, u * 1.5))
		ci.draw_rect(Rect2(Vector2(fr.position.x, fr.end.y - u * 3), Vector2(fr.size.x, u * 3)), fc.darkened(0.4))
	if shade_l:
		ci.draw_line(r.position, Vector2(r.position.x, r.end.y), cap.lightened(0.12), maxf(1.0, u))
	if shade_r:
		ci.draw_line(Vector2(r.end.x, r.position.y), r.end, cap.darkened(0.3), maxf(1.0, u))


static func wall_shadow(ci: CanvasItem, r: Rect2) -> void:
	vgrad(ci, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.4)), Color(0, 0, 0, 0.4), Color(0, 0, 0, 0))


static func doorway(ci: CanvasItem, r: Rect2, vertical: bool, past: bool) -> void:
	var u := r.size.x / 32.0
	var col := grade(Color("#8a6a40"), past)
	if vertical:
		ci.draw_rect(Rect2(Vector2(r.get_center().x - u * 2, r.position.y), Vector2(u * 4, r.size.y)), Color(col, 0.5))
	else:
		ci.draw_rect(Rect2(Vector2(r.position.x, r.get_center().y - u * 2), Vector2(r.size.x, u * 4)), Color(col, 0.5))


# ---------------------------------------------------------------- 后来的建造

static func later(ci: CanvasItem, r: Rect2, kind: String) -> void:
	var u := r.size.x / 32.0
	match kind:
		"brick":
			ci.draw_rect(r, grade(Color("#7a3a2a"), false))
			var mortar := grade(Color("#3a2a24"), false)
			for i in 4:
				var yy := r.position.y + r.size.y * i / 4.0
				ci.draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), mortar, maxf(1.0, u * 1.2))
				var off := r.size.x * (0.3 if i % 2 == 0 else 0.7)
				ci.draw_line(Vector2(r.position.x + off, yy), Vector2(r.position.x + off, yy + r.size.y / 4.0), mortar, maxf(1.0, u * 1.2))
			ci.draw_rect(r, Color(0.8, 0.8, 0.7, 0.08))
		"planks":
			ci.draw_rect(r, Color("#0c0d12"))
			var wood := grade(Color("#8a6440"), false)
			for i in 3:
				var a := r.position + Vector2(0, r.size.y * (0.2 + 0.3 * i))
				var b := a + Vector2(r.size.x, -r.size.y * 0.12 + i * u * 2)
				ci.draw_line(a, b, wood.darkened(0.4), u * 7)
				ci.draw_line(a, b, wood, u * 5.5)
				ci.draw_circle(a + Vector2(u * 3, 0), u, Color("#c0c0c8"))
				ci.draw_circle(b - Vector2(u * 3, 0), u, Color("#c0c0c8"))
		"lock":
			ci.draw_rect(r, grade(Color("#5a3a28"), false))
			ci.draw_rect(r.grow(-u * 3), grade(Color("#6a4a32"), false), false, u * 1.5)
			var c := r.get_center()
			ci.draw_arc(c - Vector2(0, u * 3), u * 4.5, PI, TAU, 12, Color("#c8a050"), u * 2)
			ci.draw_rect(Rect2(c - Vector2(u * 6, u * 3), Vector2(u * 12, u * 10)), Color("#c8a050"))
			ci.draw_circle(c + Vector2(0, u * 1.5), u * 1.5, Color("#3a2a10"))


# ---------------------------------------------------------------- 烟丝罐（所有烟丝来源共用）

static func tin(ci: CanvasItem, cell: Rect2, alpha: float, glow: bool, t: float) -> void:
	var u := cell.size.x / 32.0
	var c := cell.get_center() + Vector2(0, u)
	var rx := u * 10.0
	var hgt := u * 12.0
	if glow:
		var pulse := 0.5 + 0.5 * sin(t * 2.5)
		ci.draw_circle(c, u * 15, Color(GOLD, 0.06 + 0.08 * pulse))
		ci.draw_arc(c, u * 14, 0, TAU, 28, Color(GOLD, 0.25 + 0.35 * pulse), maxf(1.0, u * 1.2))
	if alpha >= 0.99:
		ellipse(ci, c + Vector2(u * 2, hgt * 0.55), rx, u * 3.5, Color(0, 0, 0, 0.35))
	var body := Color("#b0884a")
	var dark := Color("#6a4a22")
	# 罐身
	ci.draw_rect(Rect2(c - Vector2(rx, hgt * 0.5 - u * 2), Vector2(rx * 2, hgt)), Color(body.darkened(0.15), alpha))
	ellipse(ci, c + Vector2(0, hgt * 0.5 + u * 2), rx, u * 3, Color(body.darkened(0.3), alpha))
	# 红色标签
	ci.draw_rect(Rect2(c - Vector2(rx, -u * 0.5), Vector2(rx * 2, u * 6)), Color(Color("#8a2a22"), alpha))
	# 盖子
	ellipse(ci, c - Vector2(0, hgt * 0.5 - u * 2), rx, u * 3.5, Color(body.lightened(0.15), alpha))
	ci.draw_arc(c - Vector2(0, hgt * 0.5 - u * 2), rx * 0.6, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.5 * alpha), maxf(1.0, u))
	ci.draw_line(c + Vector2(-rx, -hgt * 0.5 + u * 2), c + Vector2(-rx, hgt * 0.5 + u * 2), Color(dark, alpha), maxf(1.0, u))
	ci.draw_line(c + Vector2(rx, -hgt * 0.5 + u * 2), c + Vector2(rx, hgt * 0.5 + u * 2), Color(dark, alpha), maxf(1.0, u))
	text_center(ci, SANS, "烟", c + Vector2(0, u * 3.5), maxi(8, int(u * 7)), Color(Color("#f2e6c8"), alpha))


# ---------------------------------------------------------------- 人物

static func person(ci: CanvasItem, cell: Rect2, style: String, past: bool, t: float, ember: bool) -> void:
	var u := cell.size.x / 32.0
	var c := cell.get_center() + Vector2(0, u)
	var st: Dictionary = PEOPLE.get(style, PEOPLE.butler)
	ellipse(ci, c + Vector2(2 * u, 9 * u), 10 * u, 4 * u, Color(0, 0, 0, 0.38))
	var coat := grade(st.coat, past)
	ellipse(ci, c + Vector2(0, 4 * u), 11 * u, 8 * u, coat.darkened(0.35))
	ellipse(ci, c + Vector2(0, 3 * u), 10 * u, 7 * u, coat)
	match st.get("detail", ""):
		"collar":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 0) * u, c + Vector2(3, 0) * u, c + Vector2(0, 6) * u]), grade(Color("#f0ece4"), past))
		"apron":
			ci.draw_rect(Rect2(c + Vector2(-5, 2) * u, Vector2(10, 7) * u), grade(Color("#f0ece4"), past))
		"belt":
			ci.draw_line(c + Vector2(-9, 5) * u, c + Vector2(9, 5) * u, grade(Color("#2a1a10"), past), 2 * u)
	if style == "detective":
		# 风衣领子
		ci.draw_line(c + Vector2(-6, -1) * u, c + Vector2(-2, 6) * u, coat.darkened(0.3), 1.5 * u)
		ci.draw_line(c + Vector2(6, -1) * u, c + Vector2(2, 6) * u, coat.darkened(0.3), 1.5 * u)
	var head := c + Vector2(0, -3 * u)
	var skin := grade(st.skin, past)
	var hc := grade(st.hatc, past)
	match st.hat:
		"fedora":
			ci.draw_circle(head, 5 * u, skin)
			ellipse(ci, head + Vector2(0, -1.5 * u), 9 * u, 7.5 * u, hc)
			ci.draw_circle(head + Vector2(0, -2 * u), 5.5 * u, hc.lightened(0.12))
			ci.draw_arc(head + Vector2(0, -2 * u), 5.5 * u, 0, TAU, 20, grade(Color("#6a2a22"), past), 1.3 * u)
			ci.draw_line(head + Vector2(0, -6 * u), head + Vector2(0, 1.5 * u), hc.darkened(0.3), u)
		"cap":
			ci.draw_circle(head, 5.5 * u, skin)
			ci.draw_circle(head + Vector2(0, -1.5 * u), 5.5 * u, hc)
			ellipse(ci, head + Vector2(0, 3 * u), 5 * u, 2 * u, hc.darkened(0.3))
			ci.draw_circle(head + Vector2(0, -2 * u), 1.4 * u, GOLD)
		"hair":
			ci.draw_circle(head, 5.5 * u, skin)
			ci.draw_arc(head, 5 * u, PI, TAU, 12, hc, 3 * u)
		"bonnet":
			ci.draw_circle(head, 5.5 * u, hc)
			ci.draw_circle(head + Vector2(0, 1.5 * u), 4 * u, skin)
			ellipse(ci, head + Vector2(0, -3.5 * u), 4.5 * u, 2.5 * u, grade(Color("#f0ece4"), past))
		"chef":
			ci.draw_circle(head, 5.5 * u, skin)
			for k in 5:
				var a := TAU * k / 5.0
				ci.draw_circle(head + Vector2(cos(a), sin(a)) * 3 * u + Vector2(0, -3 * u), 3.2 * u, hc)
			ci.draw_circle(head + Vector2(0, -3 * u), 3 * u, hc.darkened(0.06))
		"top":
			ci.draw_circle(head, 5 * u, skin)
			ci.draw_circle(head + Vector2(0, -1.5 * u), 7.5 * u, hc)
			ci.draw_circle(head + Vector2(0, -1.5 * u), 4.5 * u, hc.lightened(0.15))
			ci.draw_arc(head + Vector2(0, -1.5 * u), 4.5 * u, 0, TAU, 16, hc.darkened(0.4), u)
		"pillbox":
			ci.draw_circle(head, 5.5 * u, skin)
			ci.draw_circle(head + Vector2(0, -2.5 * u), 3.8 * u, hc)
			ci.draw_arc(head + Vector2(0, -2.5 * u), 3.8 * u, 0, TAU, 14, GOLD, u)
	if style == "detective":
		# 烟斗
		var stem_a := head + Vector2(3, 3) * u
		var bowl := head + Vector2(10, 4) * u
		ci.draw_line(stem_a, bowl, Color("#2a1a10"), 1.6 * u)
		ci.draw_circle(bowl, 2.4 * u, Color("#4a2a18"))
		if ember:
			var f := 0.6 + 0.4 * sin(t * 7.0)
			ci.draw_circle(bowl, 1.4 * u, Color(1.0, 0.55, 0.2, 0.6 + 0.4 * f))
			ci.draw_circle(bowl, 4 * u, Color(1.0, 0.6, 0.2, 0.12 * f))


static func name_tag(ci: CanvasItem, cell: Rect2, s: String) -> void:
	var size := maxi(10, int(cell.size.x * 0.32))
	var w := SANS.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8
	var c := Vector2(cell.get_center().x, cell.end.y + size * 0.4)
	var r := Rect2(c - Vector2(w / 2, size * 0.62), Vector2(w, size * 1.24))
	ci.draw_rect(r, Color(0.05, 0.05, 0.07, 0.82))
	ci.draw_rect(r, Color(GOLD, 0.5), false, 1.0)
	text_center(ci, SANS, s, c, size, Color("#efe6d2"))


# ---------------------------------------------------------------- 物件

static func thing(ci: CanvasItem, cell: Rect2, sprite: String, e: Dictionary, past: bool, t: float, done: bool) -> void:
	var u := cell.size.x / 32.0
	var c := cell.get_center()
	var inset := cell.grow(-u * 3)
	match sprite:
		"desk":
			box(ci, inset, Color("#6a4226"), past, u)
			ci.draw_rect(Rect2(c + Vector2(-9, -6) * u, Vector2(9, 11) * u), grade(Color("#efe6d0"), past))
			for i in 3:
				ci.draw_line(c + Vector2(-8, -4 + i * 3) * u, c + Vector2(-2, -4 + i * 3) * u, grade(Color("#6a6050"), past), u * 0.8)
			ci.draw_circle(c + Vector2(6, -4) * u, 3.5 * u, grade(Color("#2f6a42"), past))
			ci.draw_circle(c + Vector2(6, -4) * u, 9 * u, Color(1.0, 0.85, 0.5, 0.10))
			ci.draw_line(c + Vector2(4, 5) * u, c + Vector2(10, 3) * u, grade(Color("#1a1a1a"), past), u * 1.5)
		"table":
			ci.draw_circle(c + Vector2(2, 3) * u, 12 * u, Color(0, 0, 0, 0.35))
			ci.draw_circle(c, 12 * u, grade(Color("#5a3820"), past))
			ci.draw_circle(c, 10 * u, grade(Color("#ddd6c4"), past))
			ci.draw_circle(c + Vector2(-3, -2) * u, 2.5 * u, grade(Color("#f8f4ea"), past))
			ci.draw_circle(c + Vector2(4, 3) * u, 2 * u, grade(Color("#8a2a22"), past))
		"chair":
			box(ci, Rect2(c + Vector2(-11, -4) * u, Vector2(22, 10) * u), Color("#6a4a2e"), past, u)
			ci.draw_rect(Rect2(c + Vector2(-11, -9) * u, Vector2(22, 4) * u), grade(Color("#4a3020"), past))
		"crates":
			box(ci, Rect2(c + Vector2(-12, -6) * u, Vector2(14, 14) * u), Color("#8a6a40"), past, u)
			box(ci, Rect2(c + Vector2(-1, -11) * u, Vector2(13, 13) * u), Color("#9a7a4a"), past, u)
			var lc := grade(Color("#5a4026"), past)
			ci.draw_line(c + Vector2(-12, -6) * u, c + Vector2(2, 8) * u, lc, u)
			ci.draw_line(c + Vector2(-1, -11) * u, c + Vector2(12, 2) * u, lc, u)
		"plant":
			ci.draw_circle(c + Vector2(2, 4) * u, 9 * u, Color(0, 0, 0, 0.3))
			ci.draw_circle(c, 7 * u, grade(Color("#8a4a30"), past))
			for k in 6:
				var a := TAU * k / 6.0 + 0.4
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * 6 * u, 5 * u, grade(Color("#3d6b3a").lightened(k * 0.03), past))
			ci.draw_circle(c, 4 * u, grade(Color("#5a8a48"), past))
		"horse":
			ellipse(ci, c + Vector2(2, 5) * u, 13 * u, 6 * u, Color(0, 0, 0, 0.3))
			var hc := grade(Color("#6b4226"), past)
			ellipse(ci, c + Vector2(1, 0) * u, 11 * u, 6 * u, hc)
			ellipse(ci, c + Vector2(-11, -3) * u, 4.5 * u, 3 * u, hc.lightened(0.05))
			ci.draw_line(c + Vector2(-8, -3) * u, c + Vector2(6, -3) * u, grade(Color("#2a1a10"), past), 2 * u)
			ci.draw_line(c + Vector2(12, 0) * u, c + Vector2(15, 4) * u, grade(Color("#2a1a10"), past), 2 * u)
		"snowman":
			ci.draw_circle(c + Vector2(2, 6) * u, 9 * u, Color(0, 0, 0, 0.2))
			ci.draw_circle(c + Vector2(0, 4) * u, 9 * u, grade(Color("#f4f6f8"), past))
			ci.draw_circle(c + Vector2(0, -6) * u, 6 * u, grade(Color("#ffffff"), past))
			ci.draw_circle(c + Vector2(-2, -7) * u, u, Color("#1a1a1a"))
			ci.draw_circle(c + Vector2(2, -7) * u, u, Color("#1a1a1a"))
			ci.draw_line(c + Vector2(0, -5) * u, c + Vector2(5, -4) * u, grade(Color("#e07a2a"), past), 1.5 * u)
		"barrel":
			for k in 2:
				var bc := c + Vector2(-6 + k * 12, -2 + k * 4) * u
				ci.draw_circle(bc + Vector2(2, 3) * u, 7 * u, Color(0, 0, 0, 0.3))
				ci.draw_circle(bc, 7 * u, grade(Color("#7a5232"), past))
				ci.draw_arc(bc, 7 * u, 0, TAU, 20, grade(Color("#3a3a3e"), past), 1.5 * u)
				ci.draw_arc(bc, 4.5 * u, 0, TAU, 16, grade(Color("#5a3a22"), past), u)
		"cache":
			ci.draw_rect(inset, Color("#0a0806"))
			ci.draw_rect(inset, grade(Color("#6a4a2e"), past), false, 2 * u)
			if not done:
				ci.draw_line(c + Vector2(-6, 4) * u, c + Vector2(6, -4) * u, Color("#c8ccd4"), 2 * u)
				ci.draw_line(c + Vector2(-8, 5) * u, c + Vector2(-4, 3) * u, Color("#4a2a1a"), 3 * u)
		"cart":
			box(ci, Rect2(c + Vector2(-11, -7) * u, Vector2(22, 14) * u), Color("#7a5434"), past, u)
			for k in 4:
				var wc := c + Vector2(-10 + (k % 2) * 20, -8 + (k / 2) * 16) * u
				ci.draw_circle(wc, 2 * u, grade(Color("#2a2a2a"), past))
			ci.draw_circle(c + Vector2(-3, 0) * u, 4 * u, grade(Color("#e8e2d4"), past))
			ci.draw_circle(c + Vector2(5, 1) * u, 2.5 * u, grade(Color("#e8e2d4"), past))
		"bookshelf":
			box(ci, inset, Color("#4a2e1c"), past, u)
			var cols := [Color("#7a2a22"), Color("#2a4a3a"), Color("#2a3458"), Color("#a07a30"), Color("#5a2a4a")]
			var n := 6
			var bw := (inset.size.x - 4 * u) / n
			for k in n:
				var br := Rect2(inset.position + Vector2(2 * u + k * bw, 3 * u), Vector2(bw - u * 0.6, inset.size.y * 0.42))
				ci.draw_rect(br, grade(cols[k % cols.size()], past))
				var br2 := Rect2(inset.position + Vector2(2 * u + k * bw, inset.size.y * 0.52), Vector2(bw - u * 0.6, inset.size.y * 0.4))
				ci.draw_rect(br2, grade(cols[(k + 2) % cols.size()], past))
		"wardrobe":
			box(ci, inset, Color("#5a3820"), past, u)
			var lc := grade(Color("#2a1a10"), past)
			ci.draw_line(Vector2(c.x, inset.position.y + 3 * u), Vector2(c.x, inset.end.y - 2 * u), lc, u)
			ci.draw_circle(c + Vector2(-2, 2) * u, u, grade(GOLD, past))
			ci.draw_circle(c + Vector2(2, 2) * u, u, grade(GOLD, past))
		"safe":
			box(ci, inset, Color("#4a525e"), past, u)
			var open: bool = done
			if open:
				ci.draw_rect(inset.grow(-u * 3), Color("#14161a"))
			else:
				ci.draw_circle(c, 5 * u, grade(Color("#2a2e36"), past))
				ci.draw_arc(c, 5 * u, 0, TAU, 16, grade(Color("#c8ccd4"), past), u)
				ci.draw_line(c, c + Vector2(cos(t * 0.3), sin(t * 0.3)) * 4 * u, grade(Color("#c8ccd4"), past), u)
		"rack":
			box(ci, Rect2(c + Vector2(-12, -4) * u, Vector2(24, 8) * u), Color("#5a4026"), past, u)
			var picks := 7 if e.era == "past" else 6
			for k in picks:
				var x := c.x + (-10.5 + k * 3.5) * u
				ci.draw_line(Vector2(x, c.y - 9 * u), Vector2(x, c.y + 8 * u), grade(Color("#cfe6f2"), past), 1.3 * u)
		"candle":
			ci.draw_circle(c + Vector2(2, 3) * u, 8 * u, Color(0, 0, 0, 0.3))
			ci.draw_circle(c, 8 * u, grade(Color("#a07a30"), past))
			ci.draw_circle(c, 4 * u, grade(Color("#efe6d0"), past))
			if e.get("lit", false) and past:
				var f := sin(t * 11.0) * 0.5 + 0.5
				ci.draw_circle(c, 14 * u, Color(1.0, 0.7, 0.3, 0.10 + 0.05 * f))
				ci.draw_circle(c + Vector2(0, -2) * u, (2.5 + f) * u, Color("#ff9a3c"))
				ci.draw_circle(c + Vector2(0, -2) * u, 1.2 * u, Color("#fff2c0"))
		"wax":
			ellipse(ci, c, 7 * u, 4 * u, grade(Color("#d8cfb8"), past))
			ci.draw_circle(c, 1.5 * u, Color("#1a1a1a"))
		"logs":
			for k in 4:
				var lc := c + Vector2(-6 + (k % 2) * 11, -5 + (k / 2) * 10) * u
				ci.draw_circle(lc + Vector2(1.5, 2) * u, 5.5 * u, Color(0, 0, 0, 0.3))
				ci.draw_circle(lc, 5.5 * u, grade(Color("#7a5232"), past))
				ci.draw_arc(lc, 3 * u, 0, TAU, 12, grade(Color("#a07a4a"), past), u)
		"embers":
			ellipse(ci, c, 11 * u, 7 * u, grade(Color("#3a3634"), past))
			for k in 5:
				ci.draw_circle(c + Vector2(h(k, 1) - 0.5, h(1, k) - 0.5) * 14 * u, u * 1.2, Color(1, 0.5, 0.2, 0.25 + 0.2 * sin(t * 3 + k)))
		"book":
			ci.draw_rect(Rect2(c + Vector2(-8, -10) * u + Vector2(2, 3) * u, Vector2(16, 20) * u), Color(0, 0, 0, 0.35))
			var bc := grade(Color("#6a1e1a"), past)
			if done:
				bc = bc.darkened(0.5)
			ci.draw_rect(Rect2(c + Vector2(-8, -10) * u, Vector2(16, 20) * u), bc)
			ci.draw_rect(Rect2(c + Vector2(6, -9) * u, Vector2(2, 18) * u), grade(Color("#efe6d0"), past))
			ci.draw_rect(Rect2(c + Vector2(-5, -4) * u, Vector2(8, 3) * u), Color(GOLD, 0.8))
		"paper":
			var pc := grade(PAPER, past)
			if done:
				pc = pc.darkened(0.5)
			ci.draw_set_transform(c, -0.15, Vector2.ONE)
			ci.draw_rect(Rect2(Vector2(-9, -7) * u + Vector2(2, 3) * u, Vector2(18, 14) * u), Color(0, 0, 0, 0.35))
			ci.draw_rect(Rect2(Vector2(-9, -7) * u, Vector2(18, 14) * u), pc)
			for i in 3:
				ci.draw_line(Vector2(-7, -3 + i * 3) * u, Vector2(5, -3 + i * 3) * u, grade(Color("#5a5040"), past), u * 0.8)
			ci.draw_circle(Vector2(5, 4) * u, 2.2 * u, Color("#a82a22"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"bed":
			box(ci, inset, Color("#5a3820"), past, u)
			ci.draw_rect(Rect2(inset.position + Vector2(2, 2) * u, Vector2(inset.size.x - 4 * u, 7 * u)), grade(Color("#efe8da"), past))
			ci.draw_rect(Rect2(inset.position + Vector2(2, 10) * u, Vector2(inset.size.x - 4 * u, inset.size.y - 12 * u)), grade(Color("#5a2a32"), past))
		"toolbox":
			box(ci, Rect2(c + Vector2(-11, -6) * u, Vector2(22, 13) * u), Color("#8a2e22"), past, u)
			ci.draw_arc(c + Vector2(0, -6) * u, 4 * u, PI, TAU, 10, grade(Color("#2a2a2a"), past), 1.5 * u)
			var has_wrench: bool = e.era == "past"
			var wc := grade(Color("#c8ccd4"), past)
			if has_wrench:
				ci.draw_line(c + Vector2(-7, 3) * u, c + Vector2(6, -2) * u, wc, 2 * u)
				ci.draw_circle(c + Vector2(7, -2.5) * u, 2.5 * u, wc)
			else:
				ci.draw_line(c + Vector2(-7, 3) * u, c + Vector2(6, -2) * u, Color(0, 0, 0, 0.5), 2 * u)
				ci.draw_circle(c + Vector2(7, -2.5) * u, 2.5 * u, Color(0, 0, 0, 0.5))
		"ice":
			ci.draw_rect(Rect2(inset.position + Vector2(2, 3) * u, inset.size), Color(0, 0, 0, 0.3))
			ci.draw_rect(inset, Color(grade(Color("#a8d8ee"), past), 0.85))
			ci.draw_rect(inset.grow(-u * 3), Color(1, 1, 1, 0.18))
			ci.draw_line(inset.position + Vector2(3, 6) * u, inset.position + Vector2(9, 3) * u, Color(1, 1, 1, 0.8), u)
			ci.draw_rect(inset, Color(1, 1, 1, 0.6), false, u)
		"ashtray":
			ci.draw_circle(c + Vector2(2, 3) * u, 8 * u, Color(0, 0, 0, 0.3))
			ci.draw_circle(c, 8 * u, grade(Color("#6a6a72"), past))
			ci.draw_circle(c, 5.5 * u, grade(Color("#3a3a40"), past))
			for k in 3:
				var a := TAU * k / 3.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * 7.5 * u, 1.5 * u, grade(Color("#4a4a50"), past))
			if e.get("baited", false):
				ci.draw_circle(c, 3 * u, grade(Color("#b0884a"), past))
				var k := fposmod(t * 0.6, 1.0)
				ci.draw_circle(c + Vector2(sin(t * 2) * 2, -6 - k * 10) * u, (1.5 + k * 3) * u, Color(1, 1, 1, 0.4 * (1 - k)))
		_:
			box(ci, inset, Color("#6b5440"), past, u)
			text_center(ci, SANS, e.get("label", "?"), c, maxi(10, int(u * 13)), Color("#efe6d2"))
