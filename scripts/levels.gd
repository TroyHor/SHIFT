class_name Levels
extends RefCounted
## 三个案件的数据。规则都在 game.gd 里，关卡只描述"东西在哪、是什么"。
##
## 实体字段（常用）：
##   id, kind, era ("past" 只存在于烟雾里 / "present" 只存在于现在), pos, label（格子上的字）, name
##   persist: 过去的东西会留到现在（现在的位置 = 过去的位置）
##   push: 能在过去推动
## kind 一览：
##   npc         人。过去的人可以有 gift（送烟改变当晚）、route（之后要去哪）、smoker（会被烟丝引走）
##               现在的人可以有 lie（和过去的自己对质）、flag（过去被改变后的新证词）
##   inspector   指认凶手
##   source      烟丝来源。过去的来源可以有 erases（拿走后现在的哪些东西会消失）
##   prints      现在的物件，撒烟灰显出指纹
##   cache       现在地上的暗格，被东西盖住时看不见
##   crate       普通家具（配合 push / persist）
##   container   过去的容器，里面有证物
##   candle      过去的蜡烛：用烟斗点燃（花 1 撮），点燃后整夜燃烧，四邻的可燃物到现在会烧光
##   ice         过去的冰块：到现在会化掉，除非放在冷的格子上
##   compare     同一件东西的过去和现在各看一眼，找出差别
##   ashtray     过去的烟灰缸：放一撮烟丝，会把爱抽烟的人引过来坐着抽到天亮
##   clue        现在的证物，碰一下就拿到
##   static      只是摆设

const COUNT := 3


static func get_level(i: int) -> Dictionary:
	match i:
		0:
			return _wrap(_case1(), _case1_outer())
		1:
			return _wrap(_case2(), _case2_outer())
		_:
			return _wrap(_case3(), _case3_outer())


# ---------------------------------------------------------------
# 大地图：每个案件的核心区域（18x10）放在 26x14 地图的 (4,2)，外面一圈环廊。
# 环廊只通向不需要机制就能进的房间；密室、冰窖、账房、C 车厢仍然只能靠机制进入。
# ---------------------------------------------------------------
const BIG_W := 26
const BIG_H := 14
const OFF := Vector2i(4, 2)


static func _wrap(lv: Dictionary, outer: Dictionary) -> Dictionary:
	var grid: Array = []
	for y in BIG_H:
		var row := ""
		for x in BIG_W:
			var ring := x >= 1 and x <= BIG_W - 2 and y >= 1 and y <= BIG_H - 2
			row += "." if ring else "#"
		grid.append(row)
	for y in lv.map.size():
		var src: String = lv.map[y]
		var row: String = grid[y + OFF.y]
		grid[y + OFF.y] = row.substr(0, OFF.x) + src + row.substr(OFF.x + src.length())
	for wall in outer.get("walls", []):
		_put_char(grid, wall, "#")
	for door in outer.doors:
		_put_char(grid, door, ".")
	lv.map = grid
	lv.start = lv.start + OFF
	var cold: Array = []
	for c in lv.cold:
		cold.append(c + OFF)
	lv.cold = cold
	for lt in lv.later:
		lt.pos += OFF
		if lt.has("at"):
			lt.at += OFF
	for e in lv.ents:
		e.pos += OFF
		if e.has("seat"):
			e.seat += OFF
		if e.has("route"):
			var r: Array = []
			for w in e.route:
				r.append(w + OFF)
			e.route = r
	if outer.has("tobacco"):
		lv.tobacco = outer.tobacco
	for e in outer.get("ents", []):
		lv.ents.append(e)
	return lv


static func _put_char(grid: Array, p: Vector2i, ch: String) -> void:
	var row: String = grid[p.y]
	grid[p.y] = row.substr(0, p.x) + ch + row.substr(p.x + 1)


## 案件一外围：西边花园、北边仆人走廊、南边回廊、东边储物间。
static func _case1_outer() -> Dictionary:
	return {
		"tobacco": 1,
		# 走廊里隔出几个小间，让路线有绕行
		"walls": [Vector2i(22, 5), Vector2i(23, 5), Vector2i(22, 9), Vector2i(23, 9),
			Vector2i(1, 5), Vector2i(2, 5)],
		"doors": [Vector2i(4, 7), Vector2i(6, 2), Vector2i(6, 11), Vector2i(12, 11), Vector2i(12, 2)],
		"ents": [
			{"id": "garden_tin", "kind": "source", "era": "present", "pos": Vector2i(1, 12), "label": "烟", "amount": 1,
				"text": "花园长椅底下，园丁藏了一罐烟丝。"},
			{"id": "bench", "kind": "static", "era": "both", "pos": Vector2i(2, 8), "label": "椅",
				"text": "花园长椅，坐垫还是湿的。", "past_text": "长椅上落满了烟灰。女仆常在这里偷偷抽烟。"},
			{"id": "pouch_then", "kind": "source", "era": "past", "pos": Vector2i(8, 6), "label": "袋", "amount": 1,
				"text": "过去的门厅桌上，有人落下了一小袋烟丝。"},
			{"id": "crates", "kind": "static", "era": "both", "pos": Vector2i(23, 7), "label": "杂",
				"text": "储物间里堆满了杂物。"},
			{"id": "plant", "kind": "static", "era": "both", "pos": Vector2i(24, 1), "label": "植",
				"text": "一盆半死的龟背竹。"},
		],
	}


## 案件二外围：西边马厩、北边雪地回廊、南边后厨走廊、东边后巷。
static func _case2_outer() -> Dictionary:
	return {
		"tobacco": 1,
		"walls": [Vector2i(1, 6), Vector2i(2, 6), Vector2i(22, 7), Vector2i(23, 7)],
		"doors": [Vector2i(4, 7), Vector2i(6, 2), Vector2i(6, 11), Vector2i(12, 2), Vector2i(13, 11)],
		"ents": [
			{"id": "cellar_tin", "kind": "source", "era": "present", "pos": Vector2i(20, 3), "label": "烟", "amount": 1,
				"text": "冰窖角落有一罐受潮的烟丝，还能抽。"},
			{"id": "horse", "kind": "static", "era": "both", "pos": Vector2i(2, 3), "label": "马",
				"text": "马在打响鼻。", "past_text": "马还没卸鞍，雪水顺着鬃毛往下滴。"},
			{"id": "snowman", "kind": "static", "era": "both", "pos": Vector2i(1, 1), "label": "雪",
				"text": "雪人塌了一半。", "past_text": "孩子们刚堆好的雪人。"},
			{"id": "barrels", "kind": "static", "era": "both", "pos": Vector2i(23, 10), "label": "桶",
				"text": "后巷堆着空酒桶。"},
		],
	}


## 案件三外围：西边餐车，北侧和南侧的车外通道（只通 A 车厢，B、C 车厢没有侧门）。
static func _case3_outer() -> Dictionary:
	return {
		"tobacco": 2,
		"doors": [Vector2i(4, 7), Vector2i(6, 2), Vector2i(6, 11)],
		"ents": [
			{"id": "c_tin", "kind": "source", "era": "present", "pos": Vector2i(20, 3), "label": "烟", "amount": 1,
				"text": "行李员的铺位下有一包烟丝。"},
			{"id": "table1", "kind": "static", "era": "both", "pos": Vector2i(2, 4), "label": "桌",
				"text": "餐车的桌子，桌布上有酒渍。", "past_text": "餐车里还有人在打牌。"},
			{"id": "table2", "kind": "static", "era": "both", "pos": Vector2i(2, 10), "label": "桌",
				"text": "餐车的桌子。"},
			{"id": "dining_then", "kind": "source", "era": "past", "pos": Vector2i(3, 8), "label": "包", "amount": 2,
				"text": "过去的餐车柜台上放着一包没拆的烟丝。到了早上，它已经被打牌的人分光了。"},
		],
	}


# ---------------------------------------------------------------
# 案件一：书房（空间）
# 新规则：在过去推东西，现在也在那里；后来砌的墙可以从烟里穿过去；对质；烟丝的来源和代价。
# ---------------------------------------------------------------
static func _case1() -> Dictionary:
	return {
		"title": "案件一 · 反锁的书房",
		"theme": "空间：在过去挪动的东西，现在也在那里。",
		"past_label": "案发当晚 22:50",
		"present_label": "次日清晨 9:00",
		"intro": "富商死在反锁的书房。按 Shift 吐一口烟，看看案发当晚。烟丝不多，先想清楚再吐。",
		"start": Vector2i(2, 7),
		"tobacco": 2,
		"map": [
			"##################",
			"#....#......#....#",
			"#....#......#....#",
			"#....#...........#",
			"#...........#....#",
			"#....#......#....#",
			"#....#......#....#",
			"#....#...........#",
			"#....#......#....#",
			"##################",
		],
		"cold": [],
		"later": [
			{"pos": Vector2i(12, 3), "kind": "brick", "name": "砖墙",
				"text": "这扇门被砖砌死了，灰浆还很新。……案发那晚，它还开着吗？"},
		],
		"categories": [
			["presence", "在场", ["lie", "print", "witness"]],
			["weapon", "凶器", ["knife"]],
			["motive", "动机", ["will"]],
		],
		"clue_names": {"lie": "证词矛盾", "print": "罐上指纹", "witness": "女仆证词", "knife": "凶器", "will": "遗嘱"},
		"accuse": {"options": ["管家", "女仆"], "answer": 0,
			"win": "你指认了管家。证据摆在面前，他终于认罪。",
			"lose": "女仆一脸茫然。真凶趁乱溜走了……"},
		"ents": [
			{"id": "inspector", "kind": "inspector", "era": "present", "pos": Vector2i(2, 2), "label": "警"},
			{"id": "maid_now", "kind": "npc", "era": "present", "pos": Vector2i(3, 7), "label": "仆", "name": "女仆",
				"say": "女仆：我十点就睡下了，什么也没看见。",
				"flag": {"name": "maid_smoke", "clue": "witness",
					"text": "女仆：昨晚有位怪先生给了我一撮烟丝，我去后院抽了一会儿。\n回来时，我看见管家从书房出来，袖口上有血！"}},
			{"id": "maid_then", "kind": "npc", "era": "past", "pos": Vector2i(3, 3), "label": "仆", "name": "女仆",
				"say": "女仆（过去）：先生，您身上有烟丝吗？……没有啊，那算了。",
				"gift": {"flag": "maid_smoke",
					"ask": "女仆（过去）：先生，能分我一撮烟丝吗？我想去后院歇会儿。",
					"done": "她道了谢，往后院走去。这一晚，从此不一样了。"}},
			{"id": "butler_now", "kind": "npc", "era": "present", "pos": Vector2i(6, 5), "label": "管", "name": "管家",
				"say": "管家：案发时我整晚都在厨房，从没进过书房。",
				"lie": {"vs": "butler_then", "clue": "lie",
					"text": "管家（现在）：我整晚都在厨房，从没进过书……\n烟雾里，过去的他正站在老爷身旁。他的脸一下子白了。"}},
			{"id": "butler_then", "kind": "npc", "era": "past", "pos": Vector2i(7, 2), "label": "管", "name": "管家",
				"say": "管家（过去）：老爷，您的茶。……今晚的事，您可别怪我。"},
			{"id": "jar_now", "kind": "prints", "era": "present", "pos": Vector2i(6, 2), "label": "罐", "clue": "print",
				"hint": "空烟丝罐上好像有指纹，可惜看不清。要是有点粉末撒上去就好了……",
				"text": "你往空罐子上撒了点烟灰，显出一枚指纹，是管家的。"},
			{"id": "jar_then", "kind": "source", "era": "past", "pos": Vector2i(6, 2), "label": "罐", "amount": 2,
				"erases": ["jar_now"],
				"ask": "老爷的烟丝罐，里面还有两撮上好的烟丝。\n拿走的话，现在那只罐子（和上面的指纹）就不存在了。",
				"text": "你拿走了过去的烟丝罐。现在书房里那只罐子，也从来没出现过了。"},
			{"id": "desk", "kind": "static", "era": "both", "pos": Vector2i(8, 2), "label": "桌",
				"text": "老爷的书桌。", "past_text": "书桌上摊着一份遗嘱的草稿，墨迹未干。"},
			{"id": "ashtray_now", "kind": "source", "era": "present", "pos": Vector2i(11, 1), "label": "缸", "amount": 1,
				"text": "烟灰缸里有半截没抽完的雪茄。你把它拆开，装进了烟丝袋。"},
			{"id": "cache", "kind": "cache", "era": "present", "pos": Vector2i(9, 7), "label": "格", "clue": "knife",
				"text": "书架原来的位置下有个暗格，里面藏着一把带血的拆信刀。"},
			{"id": "cart", "kind": "crate", "era": "past", "pos": Vector2i(10, 7), "label": "车", "name": "茶车",
				"persist": true, "push": true},
			{"id": "shelf", "kind": "crate", "era": "past", "pos": Vector2i(9, 7), "label": "柜", "name": "书架",
				"persist": true, "push": true,
				"now_text": "书架被钉死在地板上，纹丝不动。"},
			{"id": "wardrobe", "kind": "crate", "era": "past", "pos": Vector2i(13, 7), "label": "橱", "name": "衣橱",
				"persist": true, "push": true,
				"now_text": "沉重的衣橱堵着密室的后门，现在的你推不动它。"},
			{"id": "safe_now", "kind": "static", "era": "present", "pos": Vector2i(15, 6), "label": "箱",
				"text": "保险箱开着，里面是空的。有人抢先一步。"},
			{"id": "safe_then", "kind": "container", "era": "past", "pos": Vector2i(15, 6), "label": "箱", "clue": "will",
				"text": "过去的保险箱还开着，遗嘱就在里面：管家一分钱也拿不到。你把它揣进怀里。",
				"empty": "保险箱里只剩些旧账本。"},
			{"id": "tin", "kind": "source", "era": "present", "pos": Vector2i(16, 1), "label": "烟", "amount": 1,
				"text": "密室角落里有一罐烟丝。"},
		],
	}


# ---------------------------------------------------------------
# 案件二：雪夜旅馆（时间流逝）
# 新规则：用烟斗点燃过去的蜡烛，它会烧一整夜；冰块到早上会化；同一件东西前后对比。
# 复用：推动、后来的建造（钉死的门）、对质、烟丝来源。
# ---------------------------------------------------------------
static func _case2() -> Dictionary:
	var cold: Array = []
	for x in range(13, 17):
		for y in range(1, 5):
			cold.append(Vector2i(x, y))
	return {
		"title": "案件二 · 雪夜旅馆",
		"theme": "时间流逝：你在过去点的火、放的冰，会自己走完这一夜。",
		"past_label": "案发当晚 21:00",
		"present_label": "次日清晨 7:00",
		"intro": "旅馆老板死在账房里，身边只有一滩水。过去的东西会自己走完这一夜：火会烧，冰会化。",
		"start": Vector2i(2, 5),
		"tobacco": 2,
		"map": [
			"##################",
			"#.....#.....#....#",
			"#.....#..........#",
			"#.....#.....#....#",
			"#.....#.....#....#",
			"#...........######",
			"#.....#.....#....#",
			"#.....#..........#",
			"#.....#.....#....#",
			"##################",
		],
		"cold": cold,
		"later": [
			{"pos": Vector2i(12, 2), "kind": "planks", "name": "钉死的门",
				"text": "冰窖的门被木板钉死了，钉子是新的。"},
		],
		"categories": [
			["presence", "在场", ["lie"]],
			["weapon", "凶器", ["icicle"]],
			["motive", "动机", ["ledger"]],
		],
		"clue_names": {"lie": "证词矛盾", "icicle": "少了一根冰锥", "ledger": "账本"},
		"accuse": {"options": ["厨师", "掌柜"], "answer": 0,
			"win": "你指认了厨师。冰锥、账本、谎言，他无话可说。",
			"lose": "掌柜整晚都在前台，好几位客人可以作证。真凶松了一口气……"},
		"ents": [
			{"id": "inspector", "kind": "inspector", "era": "present", "pos": Vector2i(2, 2), "label": "警"},
			{"id": "clerk_now", "kind": "npc", "era": "present", "pos": Vector2i(2, 7), "label": "掌", "name": "掌柜",
				"say": "掌柜：我在前台守了一夜。厨子九点多出去过一趟，说是去冰窖取冰。"},
			{"id": "cook_now", "kind": "npc", "era": "present", "pos": Vector2i(8, 6), "label": "厨", "name": "厨师",
				"say": "厨师：我九点就回房睡了，冰窖？我碰都没碰。",
				"lie": {"vs": "cook_then", "clue": "lie",
					"text": "厨师（现在）：我九点就回房……\n烟雾里，九点整的他正在厨房磨一根冰锥。他闭上了嘴。"}},
			{"id": "cook_then", "kind": "npc", "era": "past", "pos": Vector2i(8, 3), "label": "厨", "name": "厨师",
				"say": "厨师（过去）：（他在磨一根冰锥，没注意到你。）"},
			{"id": "cigars", "kind": "source", "era": "past", "pos": Vector2i(7, 3), "label": "盒", "amount": 2,
				"text": "厨房架子上有一盒老板私藏的烟丝。反正到早上，它也会被厨师抽光。"},
			{"id": "ashtray_now", "kind": "source", "era": "present", "pos": Vector2i(5, 1), "label": "缸", "amount": 1,
				"text": "大堂烟灰缸里有客人留下的半撮烟丝。"},
			{"id": "ice", "kind": "ice", "era": "past", "pos": Vector2i(11, 2), "label": "冰", "name": "冰块",
				"push": true},
			{"id": "rack_now", "kind": "compare", "era": "present", "pos": Vector2i(14, 1), "label": "架", "pair": "rack",
				"text": "冰锥架上挂着六根冰锥，冰窖够冷，一根都没化。"},
			{"id": "rack_then", "kind": "compare", "era": "past", "pos": Vector2i(14, 1), "label": "架", "pair": "rack",
				"text": "案发前的冰锥架上挂着七根冰锥。"},
			{"id": "candle", "kind": "candle", "era": "past", "pos": Vector2i(10, 7), "label": "烛", "name": "蜡烛",
				"push": true, "persist": true},
			{"id": "woodpile", "kind": "crate", "era": "past", "pos": Vector2i(12, 7), "label": "柴", "name": "柴堆",
				"persist": true, "flammable": true,
				"now_text": "账房门口堆满了柴火，过不去。"},
			{"id": "ledger", "kind": "clue", "era": "present", "pos": Vector2i(15, 7), "label": "簿", "clue": "ledger",
				"text": "账本上记着：厨师一直在偷卖冰窖里的冰，老板昨天刚发现。"},
		],
	}


# ---------------------------------------------------------------
# 案件三：末班列车（人的去向）
# 新规则：过去的人在这一刻之后还会走动。挡住他们、引开他们，他们现在的位置和看到的东西就会变。
# 复用：后来的建造（门锁取决于列车员有没有走到）、前后对比、烟丝（这次用来当诱饵）。
# ---------------------------------------------------------------
static func _case3() -> Dictionary:
	return {
		"title": "案件三 · 末班列车",
		"theme": "人的去向：过去的人还会继续走。改变他们的路，就改变了他们看见的东西。",
		"past_label": "案发当晚 23:10",
		"present_label": "次日清晨 6:00",
		"intro": "一位商人死在 A 车厢的卧铺上。过去的人在这一刻之后还会走动，烟雾里能看到他们接下来要走的路。",
		"start": Vector2i(3, 5),
		"tobacco": 2,
		"map": [
			"##################",
			"#.....#.....#....#",
			"#.....#.....#....#",
			"#.....#.....#....#",
			"#.....#.....#....#",
			"#................#",
			"#.....#.....#....#",
			"#.....#.....#....#",
			"#.....#.....#....#",
			"##################",
		],
		"cold": [],
		"later": [
			{"pos": Vector2i(12, 5), "kind": "lock", "name": "锁上的门", "by": "conductor", "at": Vector2i(11, 5),
				"text": "通往 C 车厢的门锁上了。列车员每晚 23:20 锁门。"},
		],
		"categories": [
			["presence", "在场", ["seen_by_conductor", "seen_by_passenger"]],
			["weapon", "凶器", ["wrench"]],
			["motive", "动机", ["telegram"]],
		],
		"clue_names": {"seen_by_conductor": "列车员看见了", "seen_by_passenger": "老先生看见了",
			"wrench": "少了一把扳手", "telegram": "电报"},
		"accuse": {"options": ["行李员", "列车员"], "answer": 0,
			"win": "你指认了行李员。证人、扳手、电报，一样不少。",
			"lose": "列车员整晚都在值班。真凶在下一站下了车……"},
		"ents": [
			{"id": "inspector", "kind": "inspector", "era": "present", "pos": Vector2i(2, 1), "label": "警"},
			{"id": "spare", "kind": "source", "era": "present", "pos": Vector2i(1, 8), "label": "烟", "amount": 1,
				"text": "死者行李里有一小包烟丝。"},
			{"id": "conductor", "kind": "npc", "era": "past", "pos": Vector2i(9, 2), "label": "列", "name": "列车员",
				"smoker": true, "route": [Vector2i(11, 5), Vector2i(8, 1)], "delay": 0,
				"say": "列车员（过去）：巡完这节，我就去把 C 车厢的门锁上，然后回去睡觉。……烟丝早抽完了，真想来一口。",
				"now": {"say": "列车员：我锁好门就睡了，一夜没出过门。",
					"witness": {"of": "porter", "clue": "seen_by_conductor",
						"text": "列车员：昨晚不知谁在烟灰缸里放了撮烟丝，我就坐那儿抽到半夜。\n快十二点时，行李员从 C 车厢匆匆走过去，又匆匆回来。"}}},
			{"id": "passenger", "kind": "npc", "era": "past", "pos": Vector2i(3, 2), "label": "客", "name": "老先生",
				"smoker": true, "route": [], "delay": 0,
				"say": "老先生（过去）：睡不着啊。要是有烟丝，我就去车厢连接处坐着抽一会儿。",
				"now": {"say": "老先生：我一觉睡到天亮，什么也不知道。",
					"witness": {"of": "porter", "clue": "seen_by_passenger",
						"text": "老先生：昨晚我在连接处抽烟，看见行李员往商人的铺位走去，手里拿着扳手！"}}},
			{"id": "porter", "kind": "npc", "era": "past", "pos": Vector2i(15, 7), "label": "行", "name": "行李员",
				"route": [Vector2i(2, 7), Vector2i(15, 7)], "delay": 14,
				"say": "行李员（过去）：（他在擦一把扳手，嘴里念叨着一个名字。）",
				"now": {"say": "行李员：我整晚都在行李车厢，一步也没出去过。"}},
			{"id": "ashtray_a", "kind": "ashtray", "era": "past", "pos": Vector2i(5, 3), "label": "缸", "seat": Vector2i(5, 4),
				"persist": true, "now_text": "连接处的烟灰缸。昨晚有人在这儿抽过烟吗？"},
			{"id": "ashtray_b", "kind": "ashtray", "era": "past", "pos": Vector2i(10, 7), "label": "缸", "seat": Vector2i(10, 6),
				"persist": true, "now_text": "过道边的烟灰缸。昨晚有人在这儿抽过烟吗？"},
			{"id": "tools_now", "kind": "compare", "era": "present", "pos": Vector2i(8, 8), "label": "工", "pair": "tools",
				"text": "工具箱里有钳子和锤子。"},
			{"id": "tools_then", "kind": "compare", "era": "past", "pos": Vector2i(8, 8), "label": "工", "pair": "tools",
				"text": "案发前的工具箱里有钳子、锤子，还有一把大扳手。"},
			{"id": "telegram", "kind": "clue", "era": "present", "pos": Vector2i(15, 2), "label": "电", "clue": "telegram",
				"text": "行李员铺位上的电报：「商人已查明你偷运货物，明日到站报警。」"},
			{"id": "bed", "kind": "static", "era": "both", "pos": Vector2i(1, 7), "label": "铺",
				"text": "商人的卧铺。", "past_text": "商人睡得正沉。"},
		],
	}
