class_name Game
extends RefCounted
## 纯逻辑：不依赖场景节点，方便无界面测试。关卡数据见 levels.gd。
##
## 核心规则（三个案件通用）：
##  - Shift 花 1 撮烟丝吐一口烟：以侦探为中心的 3x3 格子变成"过去"，得到 1 份烟灰。
##  - 烟雾停在原地，每个行动消耗 1 点浓度（共 8 点）；走出烟雾或浓度耗尽就回到现在。
##  - 改变世界只能在过去。"现在"只能看、问、拿。
##  - 墙、后来的建造和家具等大件挡路；人和地上的小物件不挡路。走到旁边点击它们来互动。
##  - 吐烟时如果脚下在过去是挡路的东西，侦探会被挤到旁边最近的空地。
##  - 现在 = 过去 + 这一夜的流逝：
##      * 过去推过的家具，现在还在那里（persist）。
##      * 后来才砌的墙 / 钉的门 / 上的锁：如果过去那一格被东西占着，或者负责的人没走到，就不会出现。
##      * 点燃的蜡烛烧一整夜，四邻的可燃物到现在会烧光；冰块到现在会化成一摊水，除非在冷的格子上。
##      * 过去的人在这一刻之后还会走动；他们现在在哪、看见了谁，都由这段路决定。

const SMOKE_TURNS := 8
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

enum Tile { FLOOR, WALL }

var W := 18
var H := 10
var level_idx := 0
var L: Dictionary  # 当前关卡数据（只读）
var s: Dictionary  # 可撤销的状态
var d: Dictionary  # 由 s 推导出来的"现在"，每次状态变化后重算
var history: Array = []


func _init(idx: int = 0) -> void:
	load_level(idx)


func load_level(idx: int) -> void:
	level_idx = clampi(idx, 0, Levels.count() - 1)
	load_data(Levels.get_level(level_idx))


## 直接用一份关卡数据开局（游戏内编辑器预览和试玩用）
func load_data(level: Dictionary) -> void:
	L = level
	H = L.map.size()
	W = String(L.map[0]).length() if H > 0 else 0
	reset()


func reset() -> void:
	var ents: Array = []
	for e in L.ents:
		ents.append(e.duplicate(true))
	s = {
		"pos": L.start,
		"tobacco": L.tobacco,
		"ash": 0,
		"cloud": false,
		"center": Vector2i.ZERO,
		"turns": 0,
		"clues": [],
		"flags": {},
		"seen": {},
		"ents": ents,
		"msg": L.intro,
		"mode": "play",
		"choice": {},
		"outcome": "",
	}
	history.clear()
	_derive()


# =============================================================
# 查询
# =============================================================

func tile_at(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
		return Tile.WALL
	return Tile.WALL if L.map[p.y][p.x] == "#" else Tile.FLOOR


## 编辑器的"过去"视图：整张地图都当成烟雾里
var reveal_all := false


func in_window(p: Vector2i) -> bool:
	if not s.cloud:
		return false
	if reveal_all:
		return true
	var c: Vector2i = s.center
	return absi(p.x - c.x) <= 1 and absi(p.y - c.y) <= 1


func era_at(p: Vector2i) -> String:
	return "past" if in_window(p) else "present"


## 这一格是什么地点（LevelArea 的名字）；不在任何地点里（比如门洞）返回 ""。
## 几块区域叠在一起时算最小的那一块
func area_at(p: Vector2i) -> String:
	var best := ""
	var best_n := 1 << 30
	for a in L.get("areas", []):
		var r: Rect2i = a.rect
		if r.has_point(p) and r.get_area() < best_n:
			best_n = r.get_area()
			best = a.name
	return best


## 一段话里提到了哪些地点（按名字和别名找），返回 [[开始位置, 长度, 地点名], ...]，按位置排好、不重叠
func area_mentions(text: String) -> Array:
	var words: Array = []
	for a in L.get("areas", []):
		for w in [a.name] + Array(a.get("aliases", [])):
			if String(w) != "":
				words.append([String(w), String(a.name)])
	words.sort_custom(func(x, y): return x[0].length() > y[0].length())  # 长的先找："行李车厢"先于"车厢"
	var taken := PackedByteArray()
	taken.resize(text.length())
	var out: Array = []
	for w in words:
		var from := 0
		while true:
			var i := text.find(w[0], from)
			if i < 0:
				break
			var free := true
			for k in w[0].length():
				if taken[i + k] != 0:
					free = false
					break
			if free:
				for k in w[0].length():
					taken[i + k] = 1
				out.append([i, w[0].length(), w[1]])
			from = i + 1
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out


func ent(id: String) -> Dictionary:
	for e in s.ents:
		if e.id == id:
			return e
	return {}


func past_ents() -> Array:
	var out: Array = []
	for e in s.ents:
		if (e.era == "past" or e.era == "both") and not e.get("gone", false):
			out.append(e)
	return out


func present_ents() -> Array:
	return d.present


## 某一格某个时代最上层的东西
func ent_at(era: String, p: Vector2i) -> Variant:
	var list: Array = past_ents() if era == "past" else present_ents()
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if e.pos == p and e.get("solid", true):
			return e
	return null


func later_at(p: Vector2i) -> Variant:
	for lt in d.later_active:
		if lt.pos == p:
			return lt
	return null


func solid(era: String, p: Vector2i) -> bool:
	if tile_at(p) == Tile.WALL:
		return true
	if era == "present" and later_at(p) != null:
		return true
	return ent_at(era, p) != null


## 不挡路的东西：人（可以和侦探站在同一格）和地上的小物件
const PASSABLE_KINDS := ["npc", "inspector", "clue", "cache", "prints", "source"]


static func passable(e: Dictionary) -> bool:
	return e.get("small", false) or e.kind in PASSABLE_KINDS or not e.get("solid", true)


## 侦探走不过去的格子：墙、"现在"里后来的建造，以及当前看到的家具等大件
func blocks(p: Vector2i) -> bool:
	if tile_at(p) == Tile.WALL:
		return true
	var era := era_at(p)
	if era == "present" and later_at(p) != null:
		return true
	var list: Array = past_ents() if era == "past" else present_ents()
	for e in list:
		if e.pos == p and not passable(e):
			return true
	return false


## 烟雾旁边的人能看到烟里的过去：离烟雾两格以内、站在"现在"里的人。
## 值是 "self"（烟里有过去的自己，吓得发抖）或 "wow"（看呆了）。
func onlookers() -> Dictionary:
	var out := {}
	if not s.cloud:
		return out
	var past_names := {}
	for e in past_ents():
		if e.kind == "npc" and in_window(e.pos):
			past_names[e.get("name", "")] = true
	for e in present_ents():
		if e.kind not in ["npc", "inspector"] or in_window(e.pos):
			continue
		var c: Vector2i = s.center
		if maxi(absi(e.pos.x - c.x), absi(e.pos.y - c.y)) > 3:
			continue
		out[e.id] = "self" if past_names.has(e.get("name", "-")) else "wow"
	return out


func visible_ents() -> Array:
	var out: Array = []
	for e in present_ents():
		if not in_window(e.pos):
			out.append(e)
	for e in past_ents():
		if in_window(e.pos):
			out.append(e)
	return out


func has_category(cat_idx: int) -> bool:
	for c in L.categories[cat_idx][2]:
		if s.clues.has(c):
			return true
	return false


func all_categories() -> bool:
	for i in L.categories.size():
		if not has_category(i):
			return false
	return true


func clue_name(id: String) -> String:
	return L.clue_names.get(id, id)


## 所有还在的烟丝来源（不论过去还是现在），给玩家规划路线用
func anchors() -> Array:
	var out: Array = []
	for e in s.ents:
		if e.kind == "source" and not e.get("gone", false):
			out.append(e)
	return out


## 过去的人接下来要走的路（画在烟雾里）
func route_of(id: String) -> Array:
	return d.paths.get(id, [])


# =============================================================
# 推导"现在"
# =============================================================

func _derive() -> void:
	d = {"present": [], "later_active": [], "paths": {}, "saw": {}, "reached": {}}
	var past := past_ents()
	var occupied := {}
	for e in past:
		if e.get("solid", true):
			occupied[e.pos] = true

	# 1. 过去的人接下来的路
	_simulate_people(past)

	# 2. 后来的建造
	for lt in L.later:
		if occupied.has(lt.pos):
			continue
		if lt.has("by") and not d.reached.get(lt.by + "@" + str(lt.at), false):
			continue
		d.later_active.append(lt)

	# 3. 燃烧
	var burned := {}
	for c in past:
		if c.kind == "candle" and c.get("lit", false):
			for dir in DIRS:
				burned[c.pos + dir] = true

	# 4. 现在的东西：先放现在本来就有的，再放从过去留下来的
	var present: Array = []
	for e in s.ents:
		if e.get("gone", false):
			continue
		if e.era == "present" or e.era == "both":
			present.append(e)
	for e in past:
		if e.era == "both":
			continue
		var kind: String = e.kind
		if kind == "ice":
			if L.cold.has(e.pos):
				present.append(_echo(e, e.pos, {}))
			else:
				# 化了：到早上只剩一摊水，不挡路，但看得见
				var wet: String = e.get("now_text", "")
				present.append(_echo(e, e.pos, {"label": "水", "small": true, "melted": true,
					"now_text": wet if wet != "" else "地上有一摊水，还没干透。"}))
			continue
		if kind == "candle":
			if e.get("lit", false):
				present.append(_echo(e, e.pos, {"label": "蜡", "solid": false, "burnt": true}))
			elif e.get("persist", false):
				present.append(_echo(e, e.pos, {}))
			continue
		if kind == "npc" and e.has("route"):
			var path: Array = d.paths[e.id]
			var now: Dictionary = e.now.duplicate(true)
			now.merge({"id": e.id + "#now", "kind": "npc", "era": "present", "pos": path[path.size() - 1],
				"label": e.label, "name": e.name, "src": e.id})
			present.append(now)
			continue
		if e.get("persist", false):
			if e.get("flammable", false) and burned.has(e.pos):
				present.append(_echo(e, e.pos, {"label": "烬", "solid": false, "burnt": true}))
			else:
				present.append(_echo(e, e.pos, {}))
	# 地上的暗格被东西盖住时看不见：把暗格排到最底层
	present.sort_custom(func(a, b): return a.kind == "cache" and b.kind != "cache")
	d.present = present


func _echo(e: Dictionary, pos: Vector2i, extra: Dictionary) -> Dictionary:
	var out := {"id": e.id + "#now", "kind": e.kind, "era": "present", "pos": pos,
		"label": e.label, "name": e.get("name", ""), "src": e.id, "echo": true,
		"now_text": e.get("now_text", ""), "small": e.get("small", false)}
	out.merge(extra, true)
	return out


func _simulate_people(past: Array) -> void:
	var walkers: Array = []
	var baits: Array = []
	for e in past:
		if e.kind == "npc" and e.has("route"):
			walkers.append(e)
		if e.kind == "ashtray" and e.get("baited", false):
			baits.append(e)
	var blocked := {}
	for e in past:
		if e.get("solid", true) and not (e.kind == "npc"):
			blocked[e.pos] = true
	# 每个放了烟丝的烟灰缸，只吸引离它最近的一个烟民；他会坐在旁边抽到天亮
	var lured := {}
	for b in baits:
		var best_id := ""
		var best_len := 9999
		for w in walkers:
			if not w.get("smoker", false) or lured.has(w.id):
				continue
			var p := _bfs(w.pos, b.seat, blocked)
			if not p.is_empty() and p.size() < best_len:
				best_len = p.size()
				best_id = w.id
		if best_id != "":
			lured[best_id] = b.seat
	var timelines := {}
	var longest := 0
	for w in walkers:
		var targets: Array = w.route
		var delay: int = w.get("delay", 0)
		if lured.has(w.id):
			targets = [lured[w.id]]
			delay = 0
		var line: Array = []
		for i in delay + 1:
			line.append(w.pos)
		var cur: Vector2i = w.pos
		for t in targets:
			var p := _bfs(cur, t, blocked)
			if p.is_empty():
				break
			for i in range(1, p.size()):
				line.append(p[i])
				d.reached[w.id + "@" + str(p[i])] = true
			cur = t
		d.reached[w.id + "@" + str(w.pos)] = true
		timelines[w.id] = line
		d.paths[w.id] = line
		longest = maxi(longest, line.size())
	# 同一时刻相距一格以内，就算看见了对方
	for a in walkers:
		d.saw[a.id] = {}
	for t in longest:
		for i in walkers.size():
			for j in range(i + 1, walkers.size()):
				var la: Array = timelines[walkers[i].id]
				var lb: Array = timelines[walkers[j].id]
				var pa: Vector2i = la[mini(t, la.size() - 1)]
				var pb: Vector2i = lb[mini(t, lb.size() - 1)]
				if absi(pa.x - pb.x) <= 1 and absi(pa.y - pb.y) <= 1:
					d.saw[walkers[i].id][walkers[j].id] = true
					d.saw[walkers[j].id][walkers[i].id] = true


func _bfs(from: Vector2i, to: Vector2i, blocked: Dictionary) -> Array:
	if from == to:
		return [from]
	var prev := {from: from}
	var queue: Array = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for dir in DIRS:
			var n: Vector2i = p + dir
			if prev.has(n) or tile_at(n) == Tile.WALL or (blocked.has(n) and n != to):
				continue
			prev[n] = p
			if n == to:
				var path: Array = [n]
				while path[0] != from:
					path.push_front(prev[path[0]])
				return path
			queue.append(n)
	return []


# =============================================================
# 行动
# =============================================================

func move(dir: Vector2i) -> void:
	## 走一格。墙、后来的建造和大件挡路；人和小物件可以走过去。
	if s.mode != "play":
		return
	var t: Vector2i = s.pos + dir
	if tile_at(t) == Tile.WALL:
		return
	if era_at(t) == "present":
		var lt = later_at(t)
		if lt != null:
			s.msg = lt.get("text", "")
			return
	# 推东西靠撞：走向一件推得动的东西，就把它往前推一格（人留在原地）
	var e = thing_at(t)
	if e != null and pushable(e):
		_snapshot()
		s.msg = ""
		_push(e, dir)
		_after_action()
		return
	if blocks(t):
		return
	_snapshot()
	s.msg = ""
	s.pos = t
	_after_action()


## 撞上去能推动的东西：过去的可推家具、蜡烛、冰块（从过去留到现在的那份推不动）
static func pushable(e: Dictionary) -> bool:
	if e.get("echo", false):
		return false
	match e.get("kind", ""):
		"crate":
			return e.get("push", false)
		"candle", "ice":
			return true
	return false


## 侦探站在哪里伸手够得着：自己脚下和周围一圈
func in_reach(p: Vector2i) -> bool:
	return maxi(absi(p.x - s.pos.x), absi(p.y - s.pos.y)) <= 1


## 某一格当前看得到的、可以互动的东西（烟雾里看过去，外面看现在）
func thing_at(p: Vector2i) -> Variant:
	return ent_at(era_at(p), p)


## 点击一格：走近以后才能互动（拿、看、推、对话）
func interact(p: Vector2i) -> void:
	if s.mode != "play":
		return
	var e = thing_at(p)
	if e == null:
		return
	if not in_reach(p):
		s.msg = "太远了，得走近点。"
		return
	_snapshot()
	s.msg = ""
	_bump(e, p - s.pos, era_at(p))
	_after_action()


func puff() -> void:
	if s.mode != "play":
		return
	if s.tobacco <= 0:
		# 真的走投无路才提示撤销；烟还开着、或者现在还有烟丝可拿，就只说烟斗空了
		s.msg = _stuck_msg() if not s.cloud and not _present_source_left() else "烟斗空了。"
		return
	_snapshot()
	s.tobacco -= 1
	s.ash += 1
	s.cloud = true
	s.center = s.pos
	s.turns = SMOKE_TURNS
	s.msg = "我吐出一口烟，烟雾里浮现出%s。（烟灰 +1）" % L.past_label
	if blocks(s.pos):
		var e = thing_at(s.pos)
		s.pos = _nearest_free(s.pos)
		s.msg += "\n那天晚上，这里放着%s，我被挤到了一边。" % (e.get("name", "东西") if e != null else "东西")


func choose(n: int) -> void:
	if s.mode != "choice":
		return
	var c: Dictionary = s.choice
	if c.type != "accuse" and n != 1:
		cancel()
		return
	_snapshot()
	s.mode = "play"
	s.choice = {}
	if c.type == "accuse":
		var acc: Dictionary = L.accuse
		if n < 1 or n > acc.options.size():
			history.pop_back()
			s.mode = "choice"
			s.choice = c
			return
		s.mode = "end"
		s.outcome = "win" if n - 1 == acc.answer else "lose"
		s.msg = acc.win if s.outcome == "win" else acc.lose
		return
	var e := ent(c.target)
	if not in_window(e.pos):
		s.msg = "烟雾已经散了，够不着过去的东西。"
		return
	match c.type:
		"take":
			s.tobacco += e.amount
			e.gone = true
			for id in e.get("erases", []):
				ent(id).gone = true
			s.msg = e.get("text", "") + "（烟丝 +%d）" % e.amount
		"gift":
			s.tobacco -= 1
			e.gone = true
			s.flags[e.gift.flag] = true
			s.msg = "我分出一撮烟丝。（烟丝 -1）\n" + e.gift.done
		"bait":
			s.tobacco -= 1
			e.baited = true
			s.msg = "我在烟灰缸里留下一撮烟丝。（烟丝 -1）"
		"candle":
			s.tobacco -= 1
			e.lit = true
			s.msg = "我把烟斗里的火种倒在烛芯上。（烟丝 -1）"
	_derive()


func cancel() -> void:
	if s.mode == "choice":
		s.mode = "play"
		s.choice = {}
		s.msg = "还是再想想。"


func undo() -> void:
	if history.is_empty():
		return
	s = history.pop_back()
	_derive()


func _offer(type: String, target: String, text: String, dir: Vector2i = Vector2i.ZERO) -> void:
	s.mode = "choice"
	s.choice = {"type": type, "target": target, "dir": dir}
	s.msg = text


func _snapshot() -> void:
	history.append(s.duplicate(true))
	if history.size() > 500:
		history.pop_front()


func _after_action() -> void:
	if s.cloud:
		if not in_window(s.pos):
			_close_cloud("我走出烟雾，回到了现在。")
		else:
			s.turns -= 1
			if s.turns <= 0:
				_close_cloud("烟圈卷了回去，烟雾里的夜合上了。")
	if s.mode == "choice" and not s.cloud and s.choice.type != "accuse":
		s.mode = "play"
		s.choice = {}
	_derive()
	if s.mode == "play" and s.tobacco == 0 and not s.cloud and not all_categories() and not _present_source_left():
		s.msg += "\n" + _stuck_msg()


func _close_cloud(reason: String) -> void:
	s.cloud = false
	_derive()
	s.msg = reason if s.msg == "" else s.msg + "\n" + reason
	if blocks(s.pos):
		s.pos = _nearest_free(s.center)
		s.msg += "\n现实合拢，把我挤回了烟雾升起的地方。"


func _nearest_free(from: Vector2i) -> Vector2i:
	var seen := {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if not blocks(p):
			return p
		for dir in DIRS:
			var n: Vector2i = p + dir
			if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return L.start


## 现在还拿得到的烟丝（过去的要先吐烟才拿得到，不算）
func _present_source_left() -> bool:
	for e in d.present:
		if e.kind == "source":
			return true
	return false


func _stuck_msg() -> String:
	return "烟丝用完了。还有哪里能弄到烟丝？实在不行，按 Z 撤销或 Backspace 重来。"


func _add_clue(id: String) -> String:
	if s.clues.has(id):
		return ""
	s.clues.append(id)
	return "——获得证据【%s】" % clue_name(id)


func _push(e: Dictionary, dir: Vector2i) -> void:
	if absi(dir.x) + absi(dir.y) != 1:
		s.msg = "要站在它的正侧面才推得动。"
		return
	var tgt: Vector2i = e.pos + dir
	if not in_window(tgt):
		s.msg = "烟雾外面是现在。过去的东西，推不出烟雾。"
	elif solid("past", tgt):
		s.msg = "推不动，那边被挡住了。"
	else:
		e.pos = tgt
		s.msg = "我把%s推开了一格。" % e.get("name", "它")


func _bump(e: Dictionary, dir: Vector2i, era: String) -> void:
	var past := era == "past"
	if e.get("echo", false):
		# 从过去留下来的东西：现在改不了它
		var src := ent(e.src)
		if e.get("burnt", false):
			s.msg = "只剩一堆灰烬。"
		else:
			s.msg = e.get("now_text", "") if e.get("now_text", "") != "" else "%s纹丝不动。" % src.get("name", "它")
		return
	match e.kind:
		"inspector":
			if all_categories():
				var opts := ""
				for i in L.accuse.options.size():
					opts += "[%d] %s    " % [i + 1, L.accuse.options[i]]
				_offer("accuse", "", "警长：%s都齐了？那么，凶手是谁？\n%s[Esc] 再想想" % [_cat_list(true), opts])
			else:
				s.msg = "警长：交给你了，侦探。还缺的证据：%s。" % _cat_list(false)
		"npc":
			_talk(e, past)
		"source":
			if past and not e.get("erases", []).is_empty():
				_offer("take", e.id, e.get("ask", "") + "\n[1] 拿走（烟丝 +%d）    [Esc] 算了" % e.amount)
			else:
				e.gone = true
				s.tobacco += e.amount
				s.msg = e.get("text", "") + "（烟丝 +%d）" % e.amount
		"prints":
			if s.clues.has(e.clue):
				s.msg = "指纹已经拓下来了。"
			elif s.ash > 0:
				s.ash -= 1
				s.msg = e.get("text", "") + "（烟灰 -1）" + _add_clue(e.clue)
			else:
				s.msg = e.get("hint", "")
		"cache", "clue":
			if s.clues.has(e.clue):
				s.msg = "这里已经查过了。"
			else:
				s.msg = e.get("text", "") + _add_clue(e.clue)
		"container":
			if e.get("taken", false):
				s.msg = e.get("empty", "")
			else:
				e.taken = true
				s.msg = e.get("text", "") + _add_clue(e.clue)
		"compare":
			s.seen[e.pair + "@" + era] = true
			s.msg = e.get("text", "")
			var other := "past" if era == "present" else "present"
			if s.seen.get(e.pair + "@" + other, false):
				var clue := _compare_clue(e.pair)
				if clue != "" and not s.clues.has(clue):
					s.msg += _add_clue(clue)
		"candle":
			# 点击只用来点火；推它要走过去撞
			if e.get("lit", false):
				s.msg = "蜡烛在烧。"
			elif s.tobacco <= 0:
				s.msg = e.get("text", "") if e.get("text", "") != "" else "一支没点的蜡烛。"
			else:
				var desc: String = e.get("text", "") if e.get("text", "") != "" else "一支没点的蜡烛。"
				_offer("candle", e.id, desc + "\n[1] 用烟斗点燃（烟丝 -1）    [Esc] 算了", dir)
		"ice", "crate":
			s.msg = e.get("text", "")
		"ashtray":
			if e.get("baited", false):
				s.msg = "烟灰缸里已经放了烟丝。"
			else:
				var desc: String = e.get("text", "") if e.get("text", "") != "" else "一只空烟灰缸。"
				if s.tobacco <= 0:
					s.msg = desc
				else:
					_offer("bait", e.id, desc + "\n[1] 放一撮烟丝（烟丝 -1）    [Esc] 算了")
		"static":
			s.msg = e.get("past_text", e.get("text", "")) if past else e.get("text", "")
		_:
			s.msg = ""


func _talk(e: Dictionary, past: bool) -> void:
	if past:
		if e.has("gift") and not s.flags.get(e.gift.flag, false):
			if s.tobacco > 0:
				_offer("gift", e.id, e.gift.ask + "\n[1] 给一撮（烟丝 -1）    [Esc] 算了")
				return
		s.msg = e.say
		return
	# 现在的人
	if e.has("src"):
		var w: Dictionary = e.get("witness", {})
		if not w.is_empty() and d.saw.get(e.src, {}).has(w.of):
			s.msg = w.text + _add_clue(w.clue)
		else:
			s.msg = e.say
		return
	if e.has("flag") and s.flags.get(e.flag.name, false):
		s.msg = e.flag.text + _add_clue(e.flag.clue)
		return
	if e.has("lie") and s.cloud and in_window(ent(e.lie.vs).pos):
		s.msg = e.lie.text + _add_clue(e.lie.clue)
		return
	s.msg = e.say


func _compare_clue(pair: String) -> String:
	# 对照的证物：取这一关"凶器"类里第一个还没拿到的
	for cat in L.categories:
		if cat[0] == "weapon":
			return cat[2][0]
	return ""


func _cat_list(have: bool) -> String:
	var names: Array = []
	for i in L.categories.size():
		if has_category(i) == have:
			names.append(L.categories[i][1])
	return "、".join(names)
