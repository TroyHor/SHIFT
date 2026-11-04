class_name LevelDoc
extends RefCounted
## 游戏内编辑器正在改的一关：直接改关卡场景（LevelDef 节点树），存回同样的 .tscn。
## 所以在游戏里改的和在 Godot 里改的是同一份文件，两边都能接着改。

const TILE := 32
const TILES_RES := "res://levels/tiles.tres"
## 地块：0 室内地面  1 墙  2 室外地面  3 冷地面（和 LevelDef 的图集位置一致）
const T_FLOOR := 0
const T_WALL := 1
const T_OUTDOOR := 2
const T_COLD := 3

## 新放一个东西时的模板：[按钮上的名字, 属性]
const TEMPLATES := [
	["人物 · 现在", {"kind": "npc", "era": "present", "display_name": "新人物", "sprite": "clerk", "say": "……"}],
	["人物 · 过去", {"kind": "npc", "era": "past", "display_name": "新人物", "sprite": "clerk", "say": "……"}],
	["警长", {"kind": "inspector", "era": "present", "display_name": "警长", "sprite": "inspector"}],
	["证物", {"kind": "clue", "era": "both", "display_name": "证物", "sprite": "paper", "clue": "", "text": ""}],
	["烟丝罐 · 现在", {"kind": "source", "era": "present", "display_name": "烟丝罐", "model": "tin", "amount": 1, "text": "罐子里还有一撮烟丝。"}],
	["烟丝罐 · 过去", {"kind": "source", "era": "past", "display_name": "烟丝罐", "model": "tin", "amount": 1, "text": "罐子里还有一撮烟丝。"}],
	["指纹", {"kind": "prints", "era": "present", "display_name": "", "sprite": "bottle", "clue": "", "text": "", "hint": ""}],
	["暗格", {"kind": "cache", "era": "present", "display_name": "暗格", "clue": "", "text": ""}],
	["可推的家具 · 过去", {"kind": "crate", "era": "past", "display_name": "衣橱", "sprite": "wardrobe", "push": true, "persist": true}],
	["摆设", {"kind": "static", "era": "both", "display_name": "桌子", "sprite": "table"}],
	["容器", {"kind": "container", "era": "both", "display_name": "箱子", "sprite": "crates", "clue": "", "text": "", "empty": "空了。"}],
	["蜡烛 · 过去", {"kind": "candle", "era": "past", "display_name": "蜡烛", "sprite": "candle", "push": true}],
	["冰块 · 过去", {"kind": "ice", "era": "past", "display_name": "冰块", "sprite": "ice", "push": true}],
	["对照物", {"kind": "compare", "era": "both", "display_name": "架子", "sprite": "rack", "pair": "", "text": "", "past_text": ""}],
	["烟灰缸 · 过去", {"kind": "ashtray", "era": "past", "display_name": "烟灰缸", "sprite": "ashtray"}],
]

var root: LevelDef
var file_name := ""  # 存成什么文件名（数字前缀决定顺序）
var _opened_as := ""  # 打开时的文件名，改名后存档要删掉旧文件
var _undo: Array = []
var dirty := false


static func open(path: String) -> LevelDoc:
	var doc := LevelDoc.new()
	doc.root = Levels.load_scene(path).instantiate()
	doc.file_name = path.get_file()
	doc._opened_as = doc.file_name
	return doc


## 新的一关：一圈墙、一个起点、一个警长
static func blank(file: String) -> LevelDoc:
	var doc := LevelDoc.new()
	var r := LevelDef.new()
	r.name = "Level"
	r.title = "新案件"
	r.theme = "一句话介绍。"
	r.intro = "开场白。"
	r.past_label = "昨夜 23:00"
	r.present_label = "今早 8:00"
	r.tobacco = 1
	var map := TileMapLayer.new()
	map.name = "Map"
	map.tile_set = load(TILES_RES)
	r.add_child(map)
	var start := LevelMarker.new()
	start.name = "Start"
	start.what = "start"
	r.add_child(start)
	for n in ["Later", "Ents"]:
		var g := Node2D.new()
		g.name = n
		r.add_child(g)
	doc.root = r
	doc.file_name = file
	doc.resize(Vector2i(12, 8))
	for y in 8:
		for x in 12:
			doc.paint(Vector2i(x, y), T_WALL if x == 0 or y == 0 or x == 11 or y == 7 else T_FLOOR)
	start.position = Vector2(2, 3) * TILE
	var insp := doc.add_ent(TEMPLATES[2][1], Vector2i(1, 5))
	insp.name = "inspector"
	r.suspects = PackedStringArray(["嫌疑人甲", "嫌疑人乙"])
	doc._own(r)
	return doc


func close() -> void:
	if root != null:
		root.free()
		root = null


# ---------------------------------------------------------------- 撤销

## 改动之前调用：把现在的样子存一份
func snapshot() -> void:
	_undo.append(_pack())
	if _undo.size() > 80:
		_undo.pop_front()
	dirty = true


func can_undo() -> bool:
	return not _undo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var ps: PackedScene = _undo.pop_back()
	root.free()
	root = ps.instantiate()
	dirty = true
	return true


func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c)


func _pack() -> PackedScene:
	_own(root)
	var ps := PackedScene.new()
	ps.pack(root)
	return ps


# ---------------------------------------------------------------- 存档

## 存到 dir（默认是 Levels.save_dir()），返回存下的路径；失败返回空字符串
func save(dir := "") -> String:
	if dir == "":
		dir = Levels.save_dir()
	if not file_name.ends_with(".tscn"):
		file_name += ".tscn"
	var path := dir + file_name
	var err := ResourceSaver.save(_pack(), path)
	if err != OK:
		return ""
	if _opened_as != "" and _opened_as != file_name and FileAccess.file_exists(dir + _opened_as):
		DirAccess.remove_absolute(dir + _opened_as)
	_opened_as = file_name
	dirty = false
	Levels.reload()
	return path


func to_level() -> Dictionary:
	return root.to_level()


# ---------------------------------------------------------------- 地图

func map() -> TileMapLayer:
	return root.get_node("Map")


func size() -> Vector2i:
	var u := map().get_used_rect()
	return Vector2i(maxi(u.end.x, 1), maxi(u.end.y, 1))


func tile(p: Vector2i) -> int:
	var c := map().get_cell_atlas_coords(p)
	return c.x if c.x >= 0 else -1


func paint(p: Vector2i, code: int) -> void:
	var sz := size()
	if p.x < 0 or p.y < 0 or p.x >= sz.x or p.y >= sz.y:
		return
	map().set_cell(p, 0, Vector2i(code, 0))


## 改地图大小：保留左上角，新出来的格子是墙
func resize(sz: Vector2i) -> void:
	sz = Vector2i(clampi(sz.x, 3, 40), clampi(sz.y, 3, 30))
	var m := map()
	var old := m.get_used_rect()
	for c in m.get_used_cells():
		if c.x >= sz.x or c.y >= sz.y:
			m.erase_cell(c)
	for y in sz.y:
		for x in sz.x:
			if x >= old.end.x or y >= old.end.y or m.get_cell_source_id(Vector2i(x, y)) < 0:
				m.set_cell(Vector2i(x, y), 0, Vector2i(T_WALL, 0))


# ---------------------------------------------------------------- 物件

func ents() -> Array:
	var out: Array = []
	_collect(root.get_node("Ents"), out)
	return out


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is LevelEnt:
			out.append(c)
		elif c is Node2D and not (c is LevelMarker):
			_collect(c, out)


func laters() -> Array:
	var out: Array = []
	for c in root.get_node("Later").get_children():
		if c is LevelLater:
			out.append(c)
	return out


func start() -> LevelMarker:
	return root.get_node("Start")


static func cell(n: Node2D) -> Vector2i:
	return LevelDef.cell_of(n)


## 一格里所有能选中的东西：人物物件、后来的建造、起点
func things_at(p: Vector2i) -> Array:
	var out: Array = []
	for e in ents():
		if cell(e) == p:
			out.append(e)
	for l in laters():
		if cell(l) == p:
			out.append(l)
	if cell(start()) == p:
		out.append(start())
	return out


func ent_by_id(id: String) -> LevelEnt:
	for e in ents():
		if String(e.name) == id:
			return e
	return null


func _free_id(base: String) -> String:
	base = base.strip_edges()
	if base == "":
		base = "thing"
	if ent_by_id(base) == null:
		return base
	var i := 2
	while ent_by_id("%s%d" % [base, i]) != null:
		i += 1
	return "%s%d" % [base, i]


func add_ent(props: Dictionary, p: Vector2i) -> LevelEnt:
	var e := LevelEnt.new()
	for k in props:
		e.set(k, props[k])
	var base: String = props.get("sprite", "")
	if base == "":
		base = "tin" if props.get("model", "") == "tin" else String(props.get("kind", "thing"))
	e.name = _free_id(base)
	root.get_node("Ents").add_child(e)
	e.owner = root
	move_to(e, p)
	return e


func add_later(kind: String, p: Vector2i) -> LevelLater:
	var l := LevelLater.new()
	l.kind = kind
	l.display_name = {"brick": "砖墙", "planks": "木板", "lock": "门锁"}.get(kind, "")
	l.text = "这里是后来才%s的。" % {"brick": "砌", "planks": "钉", "lock": "锁"}.get(kind, "建")
	var later := root.get_node("Later")
	later.add_child(l)
	l.name = "%s%d" % [kind.capitalize(), later.get_child_count()]
	l.owner = root
	move_to(l, p)
	return l


## 挪到某一格（路线、座位标记不跟着动）
func move_to(n: Node2D, p: Vector2i) -> void:
	n.position += Vector2(p - cell(n)) * TILE


func remove(n: Node) -> void:
	if n == start() or n == null:
		return
	n.get_parent().remove_child(n)
	n.free()


## 改 id：不能和别的重名，返回实际用上的 id
func rename(e: Node, id: String) -> String:
	id = id.strip_edges().replace("/", "_").replace(":", "_").replace(".", "_")
	if id == "" or id == String(e.name):
		return String(e.name)
	if e is LevelEnt:
		id = _free_id(id)
	e.name = id
	return String(e.name)


# ---------------------------------------------------------------- 路线、座位、"走到哪"

## 这个东西能加哪种格子标记：人物 → 路线，烟灰缸 → 座位，有建造者的建造 → 走到哪
static func marker_kind(n: Node) -> String:
	if n is LevelEnt:
		if n.kind == "npc" and n.era == "past":
			return "route"
		if n.kind == "ashtray":
			return "seat"
	if n is LevelLater and n.by != "":
		return "at"
	return ""


func markers(n: Node, what: String) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is LevelMarker and c.what == what:
			out.append(c)
	return out


func add_marker(n: Node2D, what: String, p: Vector2i) -> void:
	if what in ["seat", "at"]:
		for m in markers(n, what):
			m.get_parent().remove_child(m)
			m.free()
	var m := LevelMarker.new()
	m.what = what
	m.top_level = true
	m.position = Vector2(p) * TILE
	n.add_child(m)
	m.name = "%s%d" % [what.capitalize(), n.get_child_count()]
	m.owner = root


func pop_marker(n: Node, what: String) -> bool:
	var ms := markers(n, what)
	if ms.is_empty():
		return false
	var m: Node = ms[-1]
	n.remove_child(m)
	m.free()
	return true
