extends SceneTree
## 无界面测试：godot --headless --path . --script res://tests/test_game.gd

const GameLogic := preload("res://scripts/game.gd")

var failures := 0


func _init() -> void:
	test_route_lie()
	test_route_fingerprint()
	test_route_witness()
	test_taking_past_jar_erases_present_jar()
	test_no_tobacco_no_smoke()
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


## U/D/L/R 移动，S 吐烟，1/2 选择，E 取消
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


## 推书架拿凶器、进密室开保险箱、出密室、找警长指认。从 (11,2) 出发。
func finish_from_ashtray(g, label: String) -> void:
	walk(g, "DDLLDDS" + "LDR" + "D" + "UR")
	check(g.s.clues.has("knife"), label + ": knife")
	walk(g, "UUUURRRS" + "RR" + "RUR")
	check(g.s.clues.has("will"), label + ": will")
	walk(g, "DDDDDR")
	walk(g, "UUUULS" + "LL")
	check(g.s.pos == Vector2i(11, 3) and not g.s.cloud, label + ": back out of sealed room")
	walk(g, "DLLLLLLLUULL")
	check(g.s.mode == "choice" and g.s.choice == "accuse", label + ": accuse prompt")
	walk(g, "1")
	check(g.s.outcome == "win", label + ": won")


func test_route_lie() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRURS")
	check(g.s.cloud and g.s.tobacco == 1 and g.s.ash == 1, "lie: puff costs tobacco, gives ash")
	walk(g, "RU")
	check(g.s.inv.has("note"), "lie: note")
	walk(g, "LLDD")
	check(g.s.clues.has("lie"), "lie: caught the butler")
	walk(g, "L")
	walk(g, "RRRRRRUUU")
	check(g.s.tobacco == 2, "lie: cigar from ashtray")
	finish_from_ashtray(g, "lie")
	check(g.s.tobacco == 0, "lie: route uses every pinch, got %d" % g.s.tobacco)


func test_route_fingerprint() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRURS" + "RU" + "LLDL")
	check(not g.s.cloud and not g.s.clues.has("lie"), "print: left study without the lie")
	walk(g, "RUU")
	check(g.s.clues.has("print") and g.s.ash == 0, "print: ash revealed the fingerprint")
	walk(g, "RRRRRUU")
	check(g.s.tobacco == 2, "print: cigar")
	finish_from_ashtray(g, "print")


func test_route_witness() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRURS" + "RU" + "LLU")
	check(g.s.mode == "choice" and g.s.choice == "jar", "witness: jar offer")
	walk(g, "1")
	check(g.s.tobacco == 3, "witness: took the past jar")
	walk(g, "DL")
	check(not g.s.cloud, "witness: out of the study smoke")
	walk(g, "RRRRRRUUU")
	check(g.s.tobacco == 4, "witness: cigar")
	walk(g, "DDLLLLLLLL")
	check(g.s.pos == Vector2i(3, 4), "witness: in the hallway, got %s" % g.s.pos)
	walk(g, "SU")
	check(g.s.choice == "maid", "witness: maid asks for tobacco")
	walk(g, "1")
	check(g.s.tobacco == 2 and g.ent("maid_now").get("bribed", false), "witness: gave her a pinch")
	walk(g, "DDD")
	check(g.s.clues.has("witness"), "witness: present maid's story changed")
	walk(g, "UURRRRRRDD")
	check(g.s.pos == Vector2i(9, 6), "witness: at the shelf, got %s" % g.s.pos)
	# 从这里开始和 finish_from_ashtray 的书架部分一样
	walk(g, "S" + "LDR" + "D" + "UR")
	check(g.s.clues.has("knife"), "witness: knife")
	walk(g, "UUUURRRS" + "RR" + "RUR" + "DDDDDR" + "UUUULS" + "LL" + "DLLLLLLLUULL" + "1")
	check(g.s.outcome == "win", "witness: won")


func test_taking_past_jar_erases_present_jar() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRURS" + "LU1")
	check(g.ent("jar_now").get("gone", false), "jar: present jar gone after taking it in the past")
	walk(g, "DDL" + "RUU")
	check(not g.s.clues.has("print"), "jar: no fingerprint left to find")


func test_no_tobacco_no_smoke() -> void:
	var g = GameLogic.new()
	walk(g, "S" + "U" + "S")
	check(g.s.tobacco == 0, "spent both pinches")
	walk(g, "UUUU")
	walk(g, "S")
	check(not g.s.cloud, "cannot puff without tobacco")


func test_push_out_of_window_blocked() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRRRDDD")  # (8,7)
	check(g.s.pos == Vector2i(8, 7), "at (8,7), got %s" % g.s.pos)
	walk(g, "S")  # 窗口 x7..9：书架往右推到 (10,7) 会出窗口
	walk(g, "R")
	check(g.ent("shelf_then").pos == Vector2i(9, 7), "cannot push out of window")


func test_reality_pushes_back() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRRRRRRUU")  # (11,2)
	check(g.s.pos == Vector2i(11, 2), "at (11,2), got %s" % g.s.pos)
	# 窗口 x10..12 y1..3 盖住了门洞 (12,3)。第 8 个行动走进门洞，烟正好散掉。
	walk(g, "SDRLRLRL")
	check(g.s.cloud and g.s.turns == 1, "one action of smoke left")
	walk(g, "R")
	check(not g.s.cloud, "smoke ran out")
	check(g.s.pos == Vector2i(11, 2), "reality pushed us out of the wall, got %s" % g.s.pos)


func test_undo() -> void:
	var g = GameLogic.new()
	walk(g, "U")
	walk(g, "S")
	g.undo()
	check(not g.s.cloud and g.s.tobacco == Game.START_TOBACCO and g.s.ash == 0, "undo puff")
	g.undo()
	check(g.s.pos == Game.START, "undo move")
