extends SceneTree
## 无界面测试：godot --headless --path . --script res://tests/test_game.gd

const GameLogic := preload("res://scripts/game.gd")

var failures := 0


func _init() -> void:
	test_full_solution()
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


func walk(g, path: String) -> void:
	for c in path:
		match c:
			"U": g.move(Vector2i.UP)
			"D": g.move(Vector2i.DOWN)
			"L": g.move(Vector2i.LEFT)
			"R": g.move(Vector2i.RIGHT)
			"S": g.puff()
			"F": g.refill()


func test_full_solution() -> void:
	var g = GameLogic.new()
	# 去书房，在 (7,3) 吐烟：拿纸条，再和现在的管家对质
	walk(g, "UUURRRRURS")
	check(g.s.pos == Vector2i(7, 3) and g.s.cloud, "puff in study")
	walk(g, "RU")
	check(g.s.inv.has("note"), "took note from the past desk")
	walk(g, "LLDD")
	check(g.s.clues.has("lie"), "caught butler's lie")
	walk(g, "L")
	check(not g.s.cloud, "left the smoke")
	# 在过去推书架
	walk(g, "RRRRDDS")
	walk(g, "LDR")
	check(g.ent("shelf_now").pos == Vector2i(10, 7), "past push carried to present")
	walk(g, "D")
	check(not g.s.cloud, "left the smoke after push")
	walk(g, "UR")
	check(g.s.clues.has("knife"), "found knife under the old shelf spot")
	# 穿过案发当晚还开着的门
	walk(g, "UUUURRRS")
	walk(g, "RR")
	check(g.s.pos == Vector2i(13, 3) and not g.s.cloud, "walked through bricked door")
	walk(g, "RUR")
	check(g.s.clues.has("will"), "opened safe with note")
	walk(g, "DDDDDR")
	check(g.s.pouch == 2, "picked up tobacco tin")
	walk(g, "F")
	check(g.s.bowl == 3 and g.s.pouch == 1, "refilled")
	walk(g, "UUUULSLL")
	check(g.s.pos == Vector2i(11, 3) and not g.s.cloud, "walked back out")
	walk(g, "DLLLLLLLUULL")
	check(g.s.mode == "accuse", "accuse mode with 3 clues")
	g.choose(1)
	check(g.s.outcome == "win", "won")
	check(g.s.puffs == 4 and g.rating() == 3, "par rating, puffs=%d" % g.s.puffs)


func test_push_out_of_window_blocked() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRRRDDD")  # (8,7)
	check(g.s.pos == Vector2i(8, 7), "at (8,7), got %s" % g.s.pos)
	walk(g, "S")  # 窗口 x7..9：书架往右推到 (10,7) 会出窗口
	walk(g, "R")
	check(g.ent("shelf_then").pos == Vector2i(9, 7), "cannot push out of window")


func test_reality_pushes_back() -> void:
	var g = GameLogic.new()
	walk(g, "UUURRRRRRRRR")  # (11,4)
	walk(g, "U")  # (11,3)
	check(g.s.pos == Vector2i(11, 3), "at (11,3)")
	# 吐烟后在门洞 (12,3) 和 (11,3) 之间来回，第 8 个行动（装填）时烟散，人正站在墙里
	walk(g, "SRLRLRLRF")
	check(not g.s.cloud, "smoke timed out")
	check(g.s.pos == Vector2i(11, 3), "pushed back out of the wall, got %s" % g.s.pos)


func test_undo() -> void:
	var g = GameLogic.new()
	walk(g, "U")
	walk(g, "S")
	g.undo()
	check(not g.s.cloud and g.s.bowl == 3 and g.s.puffs == 0, "undo puff")
	g.undo()
	check(g.s.pos == Game.START, "undo move")
