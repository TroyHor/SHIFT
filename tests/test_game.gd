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
	test_case2_full()
	test_case2_planks_without_ice()
	test_case2_ice_melts_only_outside_cellar()
	test_case3_full()
	test_case3_default_night()
	test_case3_bait_passenger()
	test_push_out_of_window_blocked()
	test_reality_pushes_back()
	test_undo()
	print("ALL TESTS PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


## U/D/L/R 移动（撞上即互动），S 吐烟，1/2 选择，E 取消
func walk(g, path: String) -> void:
	for c in path:
		match c:
			"U": g.move(Vector2i.UP)
			"D": g.move(Vector2i.DOWN)
			"L": g.move(Vector2i.LEFT)
			"R": g.move(Vector2i.RIGHT)
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
	var g = GameLogic.new(0)
	walk(g, "UUURRRRURS")
	check(g.s.cloud and g.s.tobacco == 1 and g.s.ash == 1, "c1 lie: puff costs a pinch and gives ash")
	walk(g, "LDD")
	check(g.s.clues.has("lie"), "c1 lie: butler caught")
	walk(g, "L" + "RRRRRRUUU")
	check(g.s.tobacco == 2, "c1 lie: cigar from ashtray")
	walk(g, "DDLLLDDD")
	check(g.s.pos == Vector2i(8, 7), "c1 lie: at shelf spot, got %s" % g.s.pos)
	walk(g, C1_SHELF)
	check(g.s.clues.has("knife"), "c1 lie: knife")
	check(g.ent("shelf").pos == Vector2i(9, 6), "c1 lie: shelf moved in the past")
	walk(g, "UUUURRRS" + "RR")
	check(g.s.pos == Vector2i(13, 3) and not g.s.cloud, "c1 lie: walked through the later brick wall")
	walk(g, "RRRUU")
	check(g.s.tobacco == 1, "c1 lie: tin in sealed room")
	walk(g, "DDDDDLLS" + "DLU")
	check(g.ent("wardrobe").pos == Vector2i(13, 6), "c1 lie: wardrobe pushed off the back door")
	walk(g, "RRUU")
	check(g.s.clues.has("will"), "c1 lie: will from the past safe")
	walk(g, "L")
	check(not g.s.cloud and g.s.tobacco == 0, "c1 lie: smoke done, no tobacco left")
	walk(g, "LLL")
	check(g.s.pos == Vector2i(11, 7), "c1 lie: left through the back door for free, got %s" % g.s.pos)
	walk(g, "UUULLLLLLLUULL")
	check(g.s.mode == "choice" and g.s.choice.type == "accuse", "c1 lie: accuse prompt")
	walk(g, "1")
	check(g.s.outcome == "win", "c1 lie: won")


func test_case1_route_fingerprint() -> void:
	var g = GameLogic.new(0)
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
	var g = GameLogic.new(0)
	walk(g, "UUURRRRURS" + "LU")
	check(g.s.mode == "choice" and g.s.choice.type == "take", "c1 witness: jar asks first")
	walk(g, "1")
	check(g.s.tobacco == 3, "c1 witness: took past jar")
	walk(g, "DL" + "RRRRRRUUU")
	check(g.s.tobacco == 4, "c1 witness: cigar")
	walk(g, "DDLLLLLLLL")
	check(g.s.pos == Vector2i(3, 4), "c1 witness: in hallway, got %s" % g.s.pos)
	walk(g, "SU1")
	check(g.s.flags.get("maid_smoke", false) and g.s.tobacco == 2, "c1 witness: gave the maid a pinch")
	walk(g, "DDD")
	check(g.s.clues.has("witness"), "c1 witness: present maid's story changed")
	walk(g, "UURRRRRDDD" + C1_SHELF + C1_SEALED + "1")
	check(g.s.outcome == "win", "c1 witness: won")


func test_case1_taking_past_jar_erases_prints() -> void:
	var g = GameLogic.new(0)
	walk(g, "UUURRRRURS" + "LU1" + "DL" + "RUU")
	check(g.s.pos == Vector2i(6, 2), "c1 jar: present jar never existed, walked onto its spot")
	check(not g.s.clues.has("print"), "c1 jar: no fingerprint to find")


func test_case1_without_wardrobe_you_run_dry() -> void:
	var g = GameLogic.new(0)
	walk(g, "UUURRRRURS" + "LDD" + "L" + "RRRRRRUUU" + "DDLLLDDD" + C1_SHELF + "UUUURRRS" + "RR" + "RRRUU")
	# 不推衣橱，直接在密室里拿遗嘱
	walk(g, "DDDDDLLS" + "RU")
	check(g.s.clues.has("will"), "c1 dry: got the will")
	walk(g, "R")
	check(g.s.tobacco == 0 and not g.s.cloud, "c1 dry: out of smoke and tobacco")
	walk(g, "LLL")
	check(g.s.pos.x >= 13, "c1 dry: still stuck in the sealed room, at %s" % g.s.pos)


# ---------------- 案件二 ----------------

func test_case2_full() -> void:
	var g = GameLogic.new(1)
	walk(g, "RRRRRURS" + "LU")
	check(g.s.tobacco == 3, "c2: cigar box from the past kitchen")
	walk(g, "RDD")
	check(g.s.clues.has("lie"), "c2: cook caught")
	walk(g, "LL" + "LUUUU")
	check(g.s.tobacco == 4, "c2: ashtray")
	walk(g, "DDDRRRRRRUUS" + "LUR")
	check(g.ent("ice").pos == Vector2i(12, 2), "c2: ice pushed into the cellar doorway")
	walk(g, "DL")
	check(g.later_at(Vector2i(12, 2)) == null, "c2: planks never nailed, ice melted")
	walk(g, "RRURRR")
	check(g.s.pos == Vector2i(14, 2), "c2: walked into the cellar in the present, got %s" % g.s.pos)
	walk(g, "U" + "S" + "U")
	check(g.s.clues.has("icicle"), "c2: one icicle missing")
	walk(g, "LL" + "LDDDLDS" + "D1")
	check(g.ent("candle").get("lit", false) and g.s.tobacco == 0, "c2: lit the candle with the pipe")
	walk(g, "LDR")
	check(g.ent("candle").pos == Vector2i(11, 7), "c2: candle next to the woodpile")
	walk(g, "L")
	walk(g, "RRRRRRR")
	check(g.s.clues.has("ledger"), "c2: woodpile burned overnight, ledger reached")
	walk(g, "LLLLLLLUULLLLUUUL1")
	check(g.s.outcome == "win", "c2: won")


func test_case2_planks_without_ice() -> void:
	var g = GameLogic.new(1)
	check(g.later_at(Vector2i(12, 2)) != null, "c2: cellar door nailed shut by default")


func test_case2_ice_melts_only_outside_cellar() -> void:
	var g = GameLogic.new(1)
	var ice_now := false
	for e in g.present_ents():
		if e.get("src", "") == "ice":
			ice_now = true
	check(not ice_now, "c2: ice in the kitchen is gone by morning")


# ---------------- 案件三 ----------------

func test_case3_default_night() -> void:
	var g = GameLogic.new(2)
	check(g.later_at(Vector2i(12, 5)) != null, "c3: conductor locks the C car door by default")
	check(not g.d.saw.get("conductor", {}).has("porter"), "c3: nobody sees the porter by default")
	check(not g.d.saw.get("passenger", {}).has("porter"), "c3: passenger sleeps by default")


func test_case3_full() -> void:
	var g = GameLogic.new(2)
	walk(g, "RRRRRRDDD" + "L")
	check(g.s.seen.get("tools@present", false), "c3: looked at present toolbox")
	walk(g, "US" + "DL")
	check(g.s.clues.has("wrench"), "c3: wrench missing")
	walk(g, "UR1")
	check(g.ent("ashtray_b").get("baited", false) and g.s.tobacco == 0, "c3: baited the corridor ashtray")
	walk(g, "UU")
	check(g.later_at(Vector2i(12, 5)) == null, "c3: conductor never locked the door")
	check(g.d.saw.get("conductor", {}).has("porter"), "c3: conductor saw the porter")
	walk(g, "RD")
	check(g.s.clues.has("seen_by_conductor"), "c3: conductor testimony")
	walk(g, "RRRRRUUU")
	check(g.s.clues.has("telegram"), "c3: telegram in C car")
	walk(g, "DDLLLLLLLLLLLLLUUUU1")
	check(g.s.outcome == "win", "c3: won")


func test_case3_bait_passenger() -> void:
	var g = GameLogic.new(2)
	walk(g, "RRUS" + "U1")  # (5,4) 吐烟，窗口盖住 A 车厢的烟灰缸 (5,3)
	check(g.ent("ashtray_a").get("baited", false), "c3 passenger: baited car A ashtray")
	check(g.d.saw.get("passenger", {}).has("porter"), "c3 passenger: old man saw the porter")
	check(g.later_at(Vector2i(12, 5)) != null, "c3 passenger: each ashtray lures one smoker, so the conductor still locks up")


# ---------------- 通用规则 ----------------

func test_push_out_of_window_blocked() -> void:
	var g = GameLogic.new(0)
	walk(g, "UUURRRRRRDDD")  # (8,7)
	walk(g, "S")  # 窗口 x7..9：书架往右推到 (10,7) 会出窗口（而且那里有茶车）
	walk(g, "R")
	check(g.ent("shelf").pos == Vector2i(9, 7), "push: cannot push out of the window")


func test_reality_pushes_back() -> void:
	var g = GameLogic.new(0)
	walk(g, "UUURRRRRRRRRUU")  # (11,2)
	check(g.s.pos == Vector2i(11, 2), "reality: at (11,2), got %s" % g.s.pos)
	walk(g, "SDRLRLRL")
	check(g.s.cloud and g.s.turns == 1, "reality: one action of smoke left")
	walk(g, "R")
	check(not g.s.cloud and g.s.pos == Vector2i(11, 2), "reality: pushed out of the later wall, got %s" % g.s.pos)


func test_undo() -> void:
	var g = GameLogic.new(0)
	walk(g, "U")
	walk(g, "S")
	g.undo()
	check(not g.s.cloud and g.s.tobacco == 2 and g.s.ash == 0, "undo: puff")
	g.undo()
	check(g.s.pos == g.L.start, "undo: move")
