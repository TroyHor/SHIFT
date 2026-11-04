class_name Levels
extends RefCounted
## 关卡列表。每关是 res://levels/ 里的一个场景（.tscn），按文件名排序，自动出现在选关界面。
## 在 Godot 里打开场景就能编辑：画地图、拖人物和物件、在检查器里填属性。
## 规则都在 game.gd 里；这里只把场景转换成游戏用的数据。

const DIR := "res://levels/"

## 在 Godot 里按 F6 试玩某一关时，关卡场景把自己的路径放在这里
static var test_path := ""

static var _paths: Array = []
static var _cache := {}


static func paths() -> Array:
	if _paths.is_empty():
		var files: Array = []
		for f in DirAccess.get_files_at(DIR):
			f = f.trim_suffix(".remap")
			if f.ends_with(".tscn") and not f.begins_with("_"):
				files.append(DIR + f)
		files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		_paths = files
	return _paths


static func count() -> int:
	return paths().size()


static func index_of(path: String) -> int:
	return paths().find(path)


## 只读的关卡数据（选关界面用）
static func info(i: int) -> Dictionary:
	var p: String = paths()[i]
	if not _cache.has(p):
		var node = load(p).instantiate()
		_cache[p] = node.to_level()
		node.free()
	return _cache[p]


## 一份可以改动的关卡数据（开局用）
static func get_level(i: int) -> Dictionary:
	return info(i).duplicate(true)
