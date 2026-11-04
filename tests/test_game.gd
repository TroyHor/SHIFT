extends SceneTree
## 无界面测试：godot --headless --path . --script res://tests/test_game.gd
## 每个案件至少一条完整通关路线，外加关键规则的单独检查。

const GameLogic := preload("res://scripts/game.gd")

var failures := 0


func _init() -> void:
	test_case1_route_lie()
	test_case1_route_fingerprint()
	test_case1_route_witness()
	test_case1_taking_past_jar_erases_prints()
	test_case1_without_wardrobe_you_run_dry()
	test_case1_pouch_shares_the_maid_window()
	test_anchors_visible()
	test_case2_full()
	test_case2_planks_without_ice()
	test_case2_ice_melts_only_outside_cellar()
	test_case3_full()
	test_case3_default_night()
	test_case3_bait_passenger()
	test_push_out_of_window_blocked()
	test_reality_pushes_back()
	test_undo()
	test_intro_order()
	test_intro1_door()
	test_intro2_ash()
	test_intro3_push()
	test_intro4_two()
	test_blocking()
	test_onlookers()
	test_puff_squeezes_you_out()
	test_level_editor_doc()
	test_editor_keeps_tileset()
	print("ALL TESTS PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


## 三个正式案件在关卡列表里的位置（前面还有引导关）
func case_idx(n: int) -> int:
	var i := Levels.index_of("res://levels/%d0_case%d.tscn" % [n, n])
	check(i >= 0, "case %d scene exists" % n)
	return i


func level(file: String):
	var i := Levels.index_of("res://levels/" + file)
	check(i >= 0, "level %s exists" % file)
	return GameLogic.new(i)


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


## 核心区域里的坐标：原来的关卡用 18x10 的局部坐标写，放在大地图的 (4,2)
const OFF := Vector2i(4, 2)


func lc(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + OFF


## 在现在里按最短路走到 target（不吐烟、不互动）
func goto(g, target: Vector2i) -> void:
	var prev := {g.s.pos: g.s.pos}
	var queue: Array = [g.s.pos]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p == target:
			break
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = p + dir
			if prev.has(n) or g.solid(g.era_at(n), n):
				continue
			prev[n] = p
			queue.append(n)
	if not prev.has(target):
		check(false, "goto: no path to %s" % target)
		return
	var path: Array = [target]
	while path[0] != g.s.pos:
		path.push_front(prev[path[0]])
	for i in range(1, path.size()):
		g.move(path[i] - path[i - 1])


## 案件一开局只有 1 撮：先去花园拿园丁的烟丝，再回到起点
func c1_garden(g) -> void:
	goto(g, Vector2i(1, 11))
	walk(g, "D")
	check(g.s.tobacco == 2, "c1: garden tin (anchor) picked up")
	goto(g, g.L.start)


## 玩家的一步：前面有东西就点它（站在旁边互动），没有就走过去
func step(g, dir: Vector2i) -> void:
	var p: Vector2i = g.s.pos + dir
	if g.thing_at(p) != null:
		g.interact(p)
	else:
		g.move(dir)


## U/D/L/R 一步（前面有东西就点它，没有就走），u/d/l/r 只走不点，S 吐烟，1/2 选择，E 取消
func walk(g, path: String) -> void:
	for c in path:
		match c:
			"U": step(g, Vector2i.UP)
			"D": step(g, Vector2i.DOWN)
			"L": step(g, Vector2i.LEFT)
			"R": step(g, Vector2i.RIGHT)
			"u": g.move(Vector2i.UP)
			"d": g.move(Vector2i.DOWN)
			"l": g.move(Vector2i.LEFT)
			"r": g.move(Vector2i.RIGHT)
			"S": g.puff()
			"1": g.choose(1)
			"2": g.choose(2)
			"E": g.cancel()


# ---------------- 案件一 ----------------

## 从 (8,7) 吐烟推书架、拿凶器
const C1_SHELF := "S" + "DRU" + "LLL" + "RRUR"
## 从 (8,7) 走到 (11,3) 穿墙进密室，拿烟丝，在密室里推开衣橱、拿遗嘱，从后门出来找警长
const C1_SEALED := "UUUURRRS" + "RR" + "RRRUU" + "DDDDDLLS" + "DLU" + "RRUU" + "L" + "LLL" + "UUULLLLLLLUULL"


func test_case1_route_lie() -> void:
	var g = GameLogic.new(case_idx(1))
	c1_garden(g)
	walk(g, "UUURRRRURS")
	check(g.s.cloud and g.s.tobacco == 1 and g.s.ash == 1, "c1 lie: puff costs a pinch and gives ash")
	walk(g, "LDD")
	check(g.s.clues.has("lie"), "c1 lie: butler caught")
	walk(g, "L" + "RRRRRRUUU")
	check(g.s.tobacco == 2, "c1 lie: cigar from ashtray")
	walk(g, "DDLLLDDD")
	check(g.s.pos == lc(8, 7), "c1 lie: at shelf spot, got %s" % g.s.pos)
	walk(g, C1_SHELF)
	check(g.s.clues.has("knife"), "c1 lie: knife")
	check(g.ent("shelf").pos == lc(9, 6), "c1 lie: shelf moved in the past")
	walk(g, "UUUURRRS" + "RR")
	check(g.s.pos == lc(13, 3) and not g.s.cloud, "c1 lie: walked through the later brick wall")
	walk(g, "RRRUU")
	check(g.s.tobacco == 1, "c1 lie: tin in sealed room")
	walk(g, "DDDDDLLS" + "DLU")
	check(g.ent("wardrobe").pos == lc(13, 6), "c1 lie: wardrobe pushed off the back door")
	walk(g, "RRUU")
	check(g.s.clues.has("will"), "c1 lie: will from the past safe")
	walk(g, "L")
	check(not g.s.cloud and g.s.tobacco == 0, "c1 lie: smoke done, no tobacco left")
	walk(g, "LLL")
	check(g.s.pos == lc(11, 7), "c1 lie: left through the back door for free, got %s" % g.s.pos)
	walk(g, "UUULLLLLLLUULL")
	check(g.s.mode == "choice" and g.s.choice.type == "accuse", "c1 lie: accuse prompt")
	walk(g, "1")
	check(g.s.outcome == "win", "c1 lie: won")


func test_case1_route_fingerprint() -> void:
	var g = GameLogic.new(case_idx(1))
	c1_garden(g)
	walk(g, "UUURRRRRRRRRUUU")
	check(g.s.tobacco == 3, "c1 print: ashtray first")
	walk(g, "DDLLLDDD" + C1_SHELF)
	check(g.s.clues.has("knife") and g.s.ash == 1, "c1 print: knife, one ash")
	walk(g, "UUUULLU")
	check(g.s.clues.has("print") and g.s.ash == 0, "c1 print: ash revealed the print")
	walk(g, "RRRRRS" + "RR" + "RRRUU" + "DDDDDLLS" + "DLU" + "RRUU" + "L" + "LLL" + "UUULLLLLLLUULL" + "1")
	check(g.s.outcome == "win", "c1 print: won")
	check(g.s.tobacco == 1, "c1 print: one pinch to spare, got %d" % g.s.tobacco)


func test_case1_route_witness() -> void:
	var g = GameLogic.new(case_idx(1))
	c1_garden(g)
	walk(g, "UUURRRRURS" + "LU")
	check(g.s.mode == "choice" and g.s.choice.type == "take", "c1 witness: jar asks first")
	walk(g, "1")
	check(g.s.tobacco == 3, "c1 witness: took past jar")
	walk(g, "DL" + "RRRRRRUUU")
	check(g.s.tobacco == 4, "c1 witness: cigar")
	walk(g, "DDLLLLLLLL")
	check(g.s.pos == lc(3, 4), "c1 witness: in hallway, got %s" % g.s.pos)
	walk(g, "SU1")
	check(g.s.flags.get("maid_smoke", false) and g.s.tobacco == 2, "c1 witness: gave the maid a pinch")
	walk(g, "DDD")
	check(g.s.clues.has("witness"), "c1 witness: present maid's story changed")
	walk(g, "UURRRRRDDD" + C1_SHELF + C1_SEALED + "1")
	check(g.s.outcome == "win", "c1 witness: won")


func test_case1_taking_past_jar_erases_prints() -> void:
	var g = GameLogic.new(case_idx(1))
	c1_garden(g)
	walk(g, "UUURRRRURS" + "LU1" + "DL" + "RUU")
	check(g.s.pos == lc(6, 2), "c1 jar: present jar never existed, walked onto its spot")
	check(not g.s.clues.has("print"), "c1 jar: no fingerprint to find")


func test_case1_without_wardrobe_you_run_dry() -> void:
	var g = GameLogic.new(case_idx(1))
	c1_garden(g)
	walk(g, "UUURRRRURS" + "LDD" + "L" + "RRRRRRUUU" + "DDLLLDDD" + C1_SHELF + "UUUURRRS" + "RR" + "RRRUU")
	# 不推衣橱，直接在密室里拿遗嘱
	walk(g, "DDDDDLLS" + "RU")
	check(g.s.clues.has("will"), "c1 dry: got the will")
	walk(g, "R")
	check(g.s.tobacco == 0 and not g.s.cloud, "c1 dry: out of smoke and tobacco")
	walk(g, "LLL")
	check(g.s.pos.x >= 13, "c1 dry: still stuck in the sealed room, at %s" % g.s.pos)


func test_case1_pouch_shares_the_maid_window() -> void:
	var g = GameLogic.new(case_idx(1))
	c1_garden(g)
	goto(g, lc(3, 4))
	walk(g, "S" + "U1")
	check(g.s.tobacco == 0, "c1 pouch: window + gift spent both pinches")
	walk(g, "R" + "R")
	check(g.s.tobacco == 1 and g.ent("pouch_then").get("gone", false), "c1 pouch: same window reaches the past pouch, net cost 1")


func test_anchors_visible() -> void:
	for i in 3:
		var g = GameLogic.new(case_idx(i + 1))
		var past := 0
		for a in g.anchors():
			if a.era == "past":
				past += 1
		check(g.anchors().size() >= 3, "anchors: case %d has at least 3 tobacco anchors" % (i + 1))
		if i < 2:
			check(past >= 1, "anchors: case %d has a past-only anchor" % (i + 1))


# ---------------- 案件二 ----------------

func test_case2_full() -> void:
	var g = GameLogic.new(case_idx(2))
	walk(g, "RRRRRURS" + "LU")
	check(g.s.tobacco == 2, "c2: cigar box from the past kitchen")
	walk(g, "RDD")
	check(g.s.clues.has("lie"), "c2: cook caught")
	walk(g, "LL" + "LUUUU")
	check(g.s.tobacco == 3, "c2: ashtray")
	walk(g, "DDDRRRRRRUUS" + "LUR")
	check(g.ent("ice").pos == Vector2i(16, 4), "c2: ice pushed into the cellar doorway")
	walk(g, "DL")
	check(g.later_at(Vector2i(16, 4)) == null, "c2: planks never nailed, ice melted")
	walk(g, "RRURRR")
	check(g.s.pos == Vector2i(18, 4), "c2: walked into the cellar in the present, got %s" % g.s.pos)
	walk(g, "RRU" + "LL")
	check(g.s.tobacco == 3, "c2: cellar tin (anchor behind the planks)")
	walk(g, "U" + "S" + "U")
	check(g.s.clues.has("icicle"), "c2: one icicle missing")
	walk(g, "LL" + "LDDDLDS" + "D1")
	check(g.ent("candle").get("lit", false) and g.s.tobacco == 0, "c2: lit the candle with the pipe")
	walk(g, "LDR")
	check(g.ent("candle").pos == Vector2i(15, 9), "c2: candle next to the woodpile")
	walk(g, "L")
	walk(g, "RRRRRRR")
	check(g.s.clues.has("ledger"), "c2: woodpile burned overnight, ledger reached")
	walk(g, "LLLLLLLUULLLLUUUL1")
	check(g.s.outcome == "win", "c2: won")


func test_case2_planks_without_ice() -> void:
	var g = GameLogic.new(case_idx(2))
	check(g.later_at(Vector2i(16, 4)) != null, "c2: cellar door nailed shut by default")


func test_case2_ice_melts_only_outside_cellar() -> void:
	var g = GameLogic.new(case_idx(2))
	var ice_now := false
	for e in g.present_ents():
		if e.get("src", "") == "ice":
			ice_now = true
	check(not ice_now, "c2: ice in the kitchen is gone by morning")


# ---------------- 案件三 ----------------

func test_case3_default_night() -> void:
	var g = GameLogic.new(case_idx(3))
	check(g.later_at(Vector2i(16, 7)) != null, "c3: conductor locks the C car door by default")
	check(not g.d.saw.get("conductor", {}).has("porter"), "c3: nobody sees the porter by default")
	check(not g.d.saw.get("passenger", {}).has("porter"), "c3: passenger sleeps by default")


func test_case3_full() -> void:
	var g = GameLogic.new(case_idx(3))
	walk(g, "RRRRRRDDD" + "L")
	check(g.s.seen.get("tools@present", false), "c3: looked at present toolbox")
	walk(g, "US" + "DL")
	check(g.s.clues.has("wrench"), "c3: wrench missing")
	walk(g, "UR1")
	check(g.ent("ashtray_b").get("baited", false) and g.s.tobacco == 0, "c3: baited the corridor ashtray")
	walk(g, "UU")
	check(g.later_at(Vector2i(16, 7)) == null, "c3: conductor never locked the door")
	check(g.d.saw.get("conductor", {}).has("porter"), "c3: conductor saw the porter")
	walk(g, "RD")
	check(g.s.clues.has("seen_by_conductor"), "c3: conductor testimony")
	walk(g, "RRRRRUUU")
	check(g.s.clues.has("telegram"), "c3: telegram in C car")
	walk(g, "DDLLLLLLLLLLLLLUUUU1")
	check(g.s.outcome == "win", "c3: won")


func test_case3_bait_passenger() -> void:
	var g = GameLogic.new(case_idx(3))
	walk(g, "RRUS" + "U1")  # (5,4) 吐烟，窗口盖住 A 车厢的烟灰缸 (5,3)
	check(g.ent("ashtray_a").get("baited", false), "c3 passenger: baited car A ashtray")
	check(g.d.saw.get("passenger", {}).has("porter"), "c3 passenger: old man saw the porter")
	check(g.later_at(Vector2i(16, 7)) != null, "c3 passenger: each ashtray lures one smoker, so the conductor still locks up")


# ---------------- 通用规则 ----------------

func test_push_out_of_window_blocked() -> void:
	var g = GameLogic.new(case_idx(1))
	walk(g, "UUURRRRRRDDD")  # (8,7)
	walk(g, "S")  # 窗口 x7..9：书架往右推到 (10,7) 会出窗口（而且那里有茶车）
	walk(g, "R")
	check(g.ent("shelf").pos == lc(9, 7), "push: cannot push out of the window")


func test_reality_pushes_back() -> void:
	var g = GameLogic.new(case_idx(1))
	walk(g, "UUURRRRRRRRRUU")  # (11,2)
	check(g.s.pos == lc(11, 2), "reality: at (11,2), got %s" % g.s.pos)
	walk(g, "SDRLRLRL")
	check(g.s.cloud and g.s.turns == 1, "reality: one action of smoke left")
	walk(g, "R")
	check(not g.s.cloud and g.s.pos == lc(11, 2), "reality: pushed out of the later wall, got %s" % g.s.pos)


func test_undo() -> void:
	var g = GameLogic.new(case_idx(1))
	walk(g, "U")
	walk(g, "S")
	g.undo()
	check(not g.s.cloud and g.s.tobacco == g.L.tobacco and g.s.ash == 0, "undo: puff")
	g.undo()
	check(g.s.pos == g.L.start, "undo: move")


# ---------------- 引导关 ----------------

func test_intro_order() -> void:
	var p: Array = Levels.paths()
	check(p.size() >= 7 and String(p[0]).ends_with("01_door.tscn") and String(p[4]).ends_with("10_case1.tscn"), "intro: four intro levels come before case 1")


func accuse(g, answer: int) -> void:
	var ip: Vector2i = g.ent("inspector").pos
	for d in [[Vector2i.DOWN, "U"], [Vector2i.UP, "D"], [Vector2i.RIGHT, "L"], [Vector2i.LEFT, "R"]]:
		if not g.solid("present", ip + d[0]):
			goto(g, ip + d[0])
			walk(g, d[1])
			break
	check(g.s.mode == "choice", "%s: inspector offers the accusation" % g.L.title)
	g.choose(answer + 1)
	check(g.s.outcome == "win", "%s: accusation wins" % g.L.title)


## 一：只能吐烟穿过后来砌的墙，进去、出来各一口
func test_intro1_door() -> void:
	var g = level("01_door.tscn")
	walk(g, "RRRR")
	check(g.s.pos == Vector2i(5, 3), "intro1: brick stops you in the present")
	walk(g, "S" + "RR")
	check(g.s.pos == Vector2i(7, 3) and not g.s.cloud, "intro1: walked through in smoke and stepped out into the present")
	walk(g, "RRD")
	check(g.s.clues.has("glove"), "intro1: glove found")
	goto(g, Vector2i(7, 3))
	walk(g, "S" + "LL")
	check(g.s.pos == Vector2i(5, 3) and g.s.tobacco == 0, "intro1: back out with the second pinch")
	accuse(g, 1)


## 二：开局没有烟丝；拿罐子、吐烟进门，烟灰拓指纹，再拿一罐出来
func test_intro2_ash() -> void:
	var g = level("02_ash.tscn")
	walk(g, "R")
	check(g.s.msg.find("用完") < 0, "intro2: no 'out of tobacco' nag while a tin is in reach")
	walk(g, "U" + "U")
	check(g.s.tobacco == 1, "intro2: took the tin")
	goto(g, Vector2i(5, 3))
	walk(g, "S" + "RR")
	check(g.s.ash == 1 and g.s.pos == Vector2i(7, 3), "intro2: through the planks with one ash")
	goto(g, Vector2i(10, 3))
	walk(g, "U")
	check(g.s.clues.has("print") and g.s.ash == 0, "intro2: ash lifts the print")
	goto(g, Vector2i(10, 5))
	walk(g, "R")
	check(g.s.tobacco == 1, "intro2: second tin")
	goto(g, Vector2i(7, 3))
	walk(g, "S" + "LL")
	accuse(g, 1)


## 三：在烟雾里推衣橱，现在它也挪开了，底下的暗格露出来
func test_intro3_push() -> void:
	var g = level("03_push.tscn")
	walk(g, "UU")
	check(g.s.pos == Vector2i(5, 3), "intro3: wardrobe blocks in the present")
	walk(g, "S" + "U")
	check(g.ent("wardrobe").pos == Vector2i(5, 2), "intro3: cannot push it out of the smoke")
	walk(g, "LUR")
	check(g.ent("wardrobe").pos == Vector2i(6, 2), "intro3: pushed inside the smoke")
	walk(g, "DDD")
	check(not g.s.cloud, "intro3: out of the smoke")
	goto(g, Vector2i(5, 3))
	walk(g, "U")
	check(g.s.clues.has("watch"), "intro3: cache revealed under the old spot")
	accuse(g, 0)


## 四：烟雾里看得见过去的园丁时，再问现在的园丁
func test_intro4_two() -> void:
	var g = level("04_two.tscn")
	goto(g, Vector2i(7, 3))
	walk(g, "R")
	check(not g.s.clues.has("lie"), "intro4: without smoke he just repeats himself")
	walk(g, "L")
	walk(g, "S" + "R" + "R")
	check(g.s.clues.has("lie"), "intro4: confronted with his past self")
	accuse(g, 0)


# ---------------- 操作 ----------------

## 家具挡路；人和地上的小物件不挡路；互动要站到旁边
func test_blocking() -> void:
	var g = level("03_push.tscn")
	walk(g, "uuu")
	check(g.s.pos == Vector2i(5, 3), "blocking: the wardrobe blocks, at %s" % g.s.pos)
	g.interact(Vector2i(9, 1))
	check(g.s.msg.find("太远") >= 0, "blocking: things out of reach can't be used")
	var g1 = level("01_door.tscn")
	walk(g1, "rrrr")
	check(g1.s.pos == Vector2i(5, 3), "blocking: a later brick wall blocks")
	walk(g1, "S" + "rr" + "rrd" + "r")
	check(g1.s.pos == Vector2i(10, 4), "blocking: the glove is small, you can step over it, at %s" % g1.s.pos)
	var g4 = level("04_two.tscn")
	goto(g4, Vector2i(7, 3))
	walk(g4, "r")
	check(g4.s.pos == Vector2i(8, 3), "blocking: you can share a cell with a person")


## 烟雾旁边的人看得到烟里的过去；看见过去的自己时是 self
func test_onlookers() -> void:
	var g = level("04_two.tscn")
	check(g.onlookers().is_empty(), "onlookers: nobody reacts without smoke")
	goto(g, Vector2i(6, 3))
	walk(g, "S")
	var o: Dictionary = g.onlookers()
	check(o.get("gardener_now", "") == "self", "onlookers: the gardener sees himself")
	check(not o.has("butler"), "onlookers: the butler is too far away")
	walk(g, "S")
	check(g.s.cloud and g.s.msg == "烟斗空了。", "puff: an empty pipe inside the smoke is not a dead end")


## 吐烟时脚下在过去有挡路的东西，就被挤到旁边
func test_puff_squeezes_you_out() -> void:
	# 案件二：冰块那天晚上在厨房里，到早上化了。站在冰块那一格吐烟，会被挤到旁边
	var g = GameLogic.new(case_idx(2))
	var ice: Vector2i = g.ent("ice").pos
	check(not g.blocks(ice), "squeeze: the ice has melted by morning")
	goto(g, ice)
	walk(g, "S")
	check(g.s.cloud and g.s.pos != ice and not g.blocks(g.s.pos), "squeeze: pushed off the ice's cell, at %s" % g.s.pos)
	check(g.s.msg.find("挤") >= 0, "squeeze: told why")
	# 序章四：过去的园丁不挡路，站在他那一格吐烟不会被挤开
	var g4 = level("04_two.tscn")
	goto(g4, Vector2i(5, 3))
	walk(g4, "S")
	check(g4.s.pos == Vector2i(5, 3), "squeeze: people never push you out")


func test_level_editor_doc() -> void:
	# 游戏内编辑器改的是关卡场景本身：改完存下来，再读回来要一样
	var doc := LevelDoc.open("res://levels/01_door.tscn")
	var before: Dictionary = doc.to_level()
	doc.snapshot()
	doc.paint(Vector2i(2, 2), LevelDoc.T_WALL)
	var e := doc.add_ent(LevelDoc.TEMPLATES[1][1], Vector2i(3, 3))
	doc.add_marker(e, "route", Vector2i(4, 3))
	doc.add_marker(e, "route", Vector2i(5, 3))
	e.say = "我昨晚在这里。"
	doc.move_to(doc.start(), Vector2i(1, 3))
	var dir := "user://editor_test/"
	DirAccess.make_dir_recursive_absolute(dir)
	doc.file_name = "77_test.tscn"
	var path := doc.save(dir)
	check(path != "", "editor: saved")
	var back: Dictionary = Levels.load_scene(path).instantiate().to_level()
	check(String(back.map[2])[2] == "#", "editor: painted wall kept")
	check(back.start == Vector2i(1, 3), "editor: start moved")
	var added: Dictionary = back.ents.filter(func(x): return x.id == e.name)[0]
	check(added.route == [Vector2i(4, 3), Vector2i(5, 3)] and added.say == "我昨晚在这里。", "editor: person with route and line kept")
	var g = GameLogic.new(0)
	g.load_data(back)
	check(g.W == before.map[0].length(), "editor: saved level loads into the game")
	doc.undo()
	check(doc.to_level() == before, "editor: undo restores the level")
	DirAccess.remove_absolute(path)
	var blank := LevelDoc.blank("78_blank.tscn")
	var bl: Dictionary = blank.to_level()
	check(bl.map.size() == 8 and bl.ents.size() == 1 and bl.ents[0].kind == "inspector", "editor: blank level has walls and an inspector")
	doc.close()
	blank.close()


func test_editor_keeps_tileset() -> void:
	# 存档必须把地图的瓦片集写成对 levels/tiles.tres 的引用
	var doc := LevelDoc.open("res://levels/03_push.tscn")
	doc.map().tile_set = TileSet.new()  # 模拟导出版里读进来、没带路径的瓦片集
	doc.file_name = "79_tiles.tscn"
	DirAccess.make_dir_recursive_absolute("user://editor_test/")
	var path := doc.save("user://editor_test/")
	var txt := FileAccess.get_file_as_string(path)
	check(txt.contains('path="res://levels/tiles.tres"') and txt.contains("tile_set = ExtResource"), "editor: tileset saved as a reference")
	DirAccess.remove_absolute(path)
	doc.close()
