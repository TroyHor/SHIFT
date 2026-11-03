class_name Game
extends RefCounted
## 纯逻辑：不依赖场景节点，方便无界面测试。
## 规则摘要：
##  - Shift 吐一口烟（花 1 撮烟丝）：以侦探为中心的 3x3 格子变成"过去"（案发当晚）。
##  - 烟雾停在原地；在烟里走动、互动都不散，走出烟雾或浓度耗尽才复原。
##  - 每个行动（移动、碰撞互动）消耗 1 点烟雾浓度。
##  - 在过去做的改动会保留到现在；物品可以随意跨时代携带。
## 烟丝资源：
##  - 获取：现在的烟灰缸、密室里的烟丝罐、过去老爷的烟丝罐（拿走后现在那罐也消失，罐上的指纹随之消失）。
##  - 消耗：吐烟开窗；或者送给过去的人，改变他们当晚的行动，现在的证词随之改变。
##  - 副产品：每吐一口烟得到 1 份烟灰，撒在物体上可以显出指纹。

const W := 18
const H := 10
const SMOKE_TURNS := 8
const START_TOBACCO := 2
const START := Vector2i(2, 7)

enum Tile { FLOOR, WALL, BRICK }

# 现在（次日清晨）的地图。# 墙  . 地板  X 砖砌死的门
const PRESENT_MAP := [
	"##################",
	"#....#......#....#",
	"#....#......#....#",
	"#....#......X....#",
	"#...........#....#",
	"#....#......#....#",
	"#....#......#....#",
	"#....#......#....#",
	"#....#......#....#",
	"##################",
]

# 过去（案发当晚 22:50）的地图：东侧那扇门当时还没被砌死。
const PAST_MAP := [
	"##################",
	"#....#......#....#",
	"#....#......#....#",
	"#....#...........#",
	"#...........#....#",
	"#....#......#....#",
	"#....#......#....#",
	"#....#......#....#",
	"#....#......#....#",
	"##################",
]

const CLUE_NAMES := {
	"lie": "证词矛盾", "print": "罐上指纹", "witness": "女仆证词",
	"knife": "凶器", "will": "遗嘱",
}
# 指认需要三类证据：在场、凶器、动机。"在场"有三条路可以拿到。
const CATEGORIES := {
	"presence": ["在场", ["lie", "print", "witness"]],
	"weapon": ["凶器", ["knife"]],
	"motive": ["动机", ["will"]],
}
const ITEM_NAMES := {"note": "密码纸条"}

var s: Dictionary
var history: Array = []


func _init() -> void:
	reset()


func reset() -> void:
	s = {
		"pos": START,
		"tobacco": START_TOBACCO,
		"ash": 0,
		"cloud": false,
		"center": Vector2i.ZERO,
		"turns": 0,
		"inv": [],
		"clues": [],
		"ents": _make_ents(),
		"msg": "富商死在书房里。按 Shift 吐一口烟，看看案发当晚发生了什么。烟丝不多，省着点用。",
		"mode": "play",
		"choice": "",
		"outcome": "",
	}
	history.clear()


func _make_ents() -> Array:
	# 列表靠后的实体画在上层，碰撞时也优先命中。
	return [
		{"id": "inspector", "kind": "inspector", "era": "present", "pos": Vector2i(2, 2)},
		{"id": "maid_now", "kind": "maid", "era": "present", "pos": Vector2i(3, 7)},
		{"id": "maid_then", "kind": "maid", "era": "past", "pos": Vector2i(3, 3)},
		{"id": "butler_now", "kind": "butler", "era": "present", "pos": Vector2i(6, 5)},
		{"id": "butler_then", "kind": "butler", "era": "past", "pos": Vector2i(7, 2)},
		{"id": "jar_now", "kind": "jar", "era": "present", "pos": Vector2i(6, 2)},
		{"id": "jar_then", "kind": "jar", "era": "past", "pos": Vector2i(6, 2)},
		{"id": "desk_now", "kind": "desk", "era": "present", "pos": Vector2i(8, 2)},
		{"id": "desk_then", "kind": "desk", "era": "past", "pos": Vector2i(8, 2), "note": true},
		{"id": "ashtray", "kind": "ashtray", "era": "present", "pos": Vector2i(11, 1), "used": false},
		{"id": "cache", "kind": "cache", "era": "present", "pos": Vector2i(9, 7), "open": false},
		{"id": "shelf_now", "kind": "shelf", "era": "present", "pos": Vector2i(9, 7)},
		{"id": "shelf_then", "kind": "shelf", "era": "past", "pos": Vector2i(9, 7)},
		{"id": "safe_now", "kind": "safe", "era": "present", "pos": Vector2i(15, 2), "open": false},
		{"id": "safe_then", "kind": "safe", "era": "past", "pos": Vector2i(15, 2)},
		{"id": "tin", "kind": "tin", "era": "present", "pos": Vector2i(15, 7)},
	]


# ---------- 查询 ----------

func tile_at(era: String, p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
		return Tile.WALL
	var row: String = (PAST_MAP if era == "past" else PRESENT_MAP)[p.y]
	match row[p.x]:
		"#":
			return Tile.WALL
		"X":
			return Tile.BRICK
	return Tile.FLOOR


func in_window(p: Vector2i) -> bool:
	if not s.cloud:
		return false
	var c: Vector2i = s.center
	return absi(p.x - c.x) <= 1 and absi(p.y - c.y) <= 1


func era_at(p: Vector2i) -> String:
	return "past" if in_window(p) else "present"


func ent_at(era: String, p: Vector2i) -> Variant:
	var ents: Array = s.ents
	for i in range(ents.size() - 1, -1, -1):
		var e: Dictionary = ents[i]
		if e.era == era and e.pos == p and not e.get("gone", false):
			return e
	return null


func ent(id: String) -> Dictionary:
	for e in s.ents:
		if e.id == id:
			return e
	return {}


func visible_ents() -> Array:
	var out: Array = []
	for e in s.ents:
		if e.get("gone", false):
			continue
		if era_at(e.pos) == e.era:
			out.append(e)
	return out


func has_category(cat: String) -> bool:
	for c in CATEGORIES[cat][1]:
		if s.clues.has(c):
			return true
	return false


func all_categories() -> bool:
	for cat in CATEGORIES:
		if not has_category(cat):
			return false
	return true


# ---------- 行动 ----------

func move(dir: Vector2i) -> void:
	if s.mode != "play":
		return
	var t: Vector2i = s.pos + dir
	var era := era_at(t)
	var tile := tile_at(era, t)
	if tile == Tile.WALL:
		return
	if tile == Tile.BRICK:
		s.msg = "这扇门被砖砌死了。……可案发那晚，它还开着吗？"
		return
	_snapshot()
	s.msg = ""
	var e = ent_at(era, t)
	if e != null:
		_bump(e, dir, era)
	else:
		s.pos = t
	_after_action()


func puff() -> void:
	if s.mode != "play":
		return
	if s.tobacco <= 0:
		s.msg = _stuck_msg()
		return
	_snapshot()
	s.tobacco -= 1
	s.ash += 1
	s.cloud = true
	s.center = s.pos
	s.turns = SMOKE_TURNS
	s.msg = "你吐出一口烟，烟雾里浮现出案发当晚。（烟灰 +1）"


## 选择框里按数字键。
func choose(n: int) -> void:
	if s.mode != "choice":
		return
	if s.choice != "accuse" and n != 1:
		cancel()
		return
	_snapshot()
	s.mode = "play"
	var c: String = s.choice
	s.choice = ""
	match c:
		"accuse":
			s.mode = "end"
			if n == 1:
				s.outcome = "win"
				s.msg = "你指认了管家。证据摆在面前，他终于认罪。"
			else:
				s.outcome = "lose"
				s.msg = "女仆一脸茫然。真凶趁乱溜走了……"
		"jar":
			if not in_window(ent("jar_then").pos):
				s.msg = "烟雾已经散了，够不着过去的东西。"
				return
			s.tobacco += 2
			ent("jar_then").gone = true
			ent("jar_now").gone = true
			s.msg = "你拿走了过去的烟丝罐。（烟丝 +2）\n现在书房里那只罐子，也从来没出现过了。"
		"maid":
			if not in_window(ent("maid_then").pos):
				s.msg = "烟雾已经散了，她听不见你了。"
				return
			s.tobacco -= 1
			ent("maid_then").gone = true
			ent("maid_now").bribed = true
			s.msg = "你分给过去的女仆一撮烟丝。（烟丝 -1）\n她道了谢，往后院走去。这一晚，从此不一样了。"


func cancel() -> void:
	if s.mode == "choice":
		s.mode = "play"
		s.choice = ""
		s.msg = "你决定再想想。"


func undo() -> void:
	if history.is_empty():
		return
	s = history.pop_back()


func _offer(id: String, text: String) -> void:
	s.mode = "choice"
	s.choice = id
	s.msg = text


func _snapshot() -> void:
	history.append(s.duplicate(true))
	if history.size() > 500:
		history.pop_front()


func _after_action() -> void:
	if s.cloud:
		if not in_window(s.pos):
			_close_cloud("你走出烟雾，回到了现在。")
		else:
			s.turns -= 1
			if s.turns <= 0:
				_close_cloud("烟雾散了。")
	if s.mode == "choice" and not s.cloud and s.choice in ["jar", "maid"]:
		# 互动用掉了最后一点烟雾，过去的东西已经够不着了
		s.mode = "play"
		s.choice = ""
	if s.mode == "play" and s.tobacco == 0 and not s.cloud and not all_categories():
		s.msg += "\n" + _stuck_msg()


func _close_cloud(reason: String) -> void:
	s.cloud = false
	s.msg = reason if s.msg == "" else s.msg + "\n" + reason
	if not _present_free(s.pos):
		s.pos = _nearest_free(s.center)
		s.msg += "\n现实合拢，把你挤回了烟雾升起的地方。"


func _present_free(p: Vector2i) -> bool:
	return tile_at("present", p) == Tile.FLOOR and ent_at("present", p) == null


func _nearest_free(from: Vector2i) -> Vector2i:
	var seen := {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if _present_free(p):
			return p
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = p + d
			if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return START


func _stuck_msg() -> String:
	return "烟丝用完了。还有哪里能弄到烟丝？实在不行，按 Z 撤销或 Backspace 重来。"


func _add_clue(id: String) -> void:
	if not s.clues.has(id):
		s.clues.append(id)


func _bump(e: Dictionary, dir: Vector2i, era: String) -> void:
	match e.kind:
		"inspector":
			if all_categories():
				_offer("accuse", "警长：在场、凶器、动机都齐了？那么，凶手是谁？\n[1] 管家    [2] 女仆    [Esc] 再想想")
			else:
				var missing: Array = []
				for cat in CATEGORIES:
					if not has_category(cat):
						missing.append(CATEGORIES[cat][0])
				s.msg = "警长：老爷死在书房，现场门窗都从里面锁着。还缺的证据：%s。" % "、".join(missing)
		"butler":
			if era == "past":
				s.msg = "管家（过去）：老爷，您的茶。……今晚的事，您可别怪我。"
			elif s.cloud and in_window(ent("butler_then").pos):
				_add_clue("lie")
				s.msg = "管家（现在）：我整晚都在厨房，从没进过书……\n烟雾里，过去的他正站在老爷身旁。他的脸一下子白了。——获得证据【证词矛盾】"
			else:
				s.msg = "管家：案发时我整晚都在厨房，从没进过书房。"
		"maid":
			if era == "past":
				if s.tobacco <= 0:
					s.msg = "女仆（过去）：先生，您身上有烟丝吗？……没有啊，那算了。"
				else:
					_offer("maid", "女仆（过去）：先生，能分我一撮烟丝吗？我想去后院歇会儿。\n[1] 给她一撮（烟丝 -1）    [Esc] 算了")
			elif e.get("bribed", false):
				_add_clue("witness")
				s.msg = "女仆：昨晚有位怪先生给了我一撮烟丝，我去后院抽了一会儿。\n回来时，我看见管家从书房出来，袖口上有血！——获得证据【女仆证词】"
			else:
				s.msg = "女仆：我十点就睡下了，什么也没看见。"
		"jar":
			if era == "past":
				_offer("jar", "老爷的烟丝罐，里面还有两撮上好的烟丝。拿走的话，现在那只罐子也就不存在了。\n[1] 拿走（烟丝 +2）    [Esc] 算了")
			elif s.clues.has("print"):
				s.msg = "罐子上的指纹已经拓下来了。"
			elif s.ash > 0:
				s.ash -= 1
				_add_clue("print")
				s.msg = "罐子已经空了。你往上撒了点烟灰，显出一枚指纹，是管家的。（烟灰 -1）——获得证据【罐上指纹】"
			else:
				s.msg = "空烟丝罐上好像有指纹，可惜看不清。要是有点粉末撒上去就好了……"
		"desk":
			if era == "past" and e.get("note", false):
				e.note = false
				s.inv.append("note")
				s.msg = "你从过去的书桌上拿起一张纸条：『保险箱 0923』。"
			elif era == "past":
				s.msg = "过去的书桌上只剩一杯凉掉的茶。"
			else:
				s.msg = "书桌上空荡荡的，像是少了什么东西。"
		"ashtray":
			if e.used:
				s.msg = "烟灰缸里已经没什么了。"
			else:
				e.used = true
				s.tobacco += 1
				s.msg = "烟灰缸里有半截没抽完的雪茄。你把它拆开，装进了烟丝袋。（烟丝 +1）"
		"safe":
			if era == "past":
				s.msg = "保险箱锁着。"
			elif e.open:
				s.msg = "保险箱已经空了。"
			elif s.inv.has("note"):
				e.open = true
				_add_clue("will")
				s.msg = "你输入 0923，保险箱开了。遗嘱上写着：管家一分钱也拿不到。——获得证据【遗嘱】"
			else:
				s.msg = "保险箱上了四位密码锁。"
		"shelf":
			if era == "present":
				s.msg = "书架被钉死在地板上，纹丝不动。"
			else:
				var tgt: Vector2i = e.pos + dir
				if not in_window(tgt):
					s.msg = "烟雾外面是现在。过去的东西，推不出烟雾。"
				elif tile_at("past", tgt) != Tile.FLOOR or ent_at("past", tgt) != null:
					s.msg = "推不动，那边被挡住了。"
				else:
					e.pos = tgt
					ent("shelf_now").pos = tgt
					s.msg = "你在过去推开了书架。现在的它，也会停在这个位置。"
		"cache":
			if not e.open:
				e.open = true
				_add_clue("knife")
				s.msg = "书架原来的位置下有个暗格，里面藏着一把带血的拆信刀。——获得证据【凶器】"
			else:
				s.msg = "暗格已经空了。"
		"tin":
			e.gone = true
			s.tobacco += 1
			s.msg = "密室角落里有一罐烟丝。（烟丝 +1）"
