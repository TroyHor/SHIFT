class_name Levels
extends RefCounted
## 关卡列表。每关是 res://levels/ 里的一个场景（.tscn），按文件名排序，自动出现在选关界面。
## 在 Godot 里打开场景就能编辑：画地图、拖人物和物件、在检查器里填属性；也可以用游戏里的编辑器（选关界面按 E）。
## 规则都在 game.gd 里；这里只把场景转换成游戏用的数据。

const DIR := "res://levels/"

## 在 Godot 里按 F6 试玩某一关时，关卡场景把自己的路径放在这里
static var test_path := ""

static var _paths: Array = []
static var _cache := {}
static var _save_dir := ""


## 游戏内编辑器把关卡存到哪里：
## 在 Godot 里运行 → 项目的 levels/；导出的游戏放在项目文件夹里（比如 build/ 下）→ 也是项目的 levels/；
## 都不是（比如网页版）→ 存在本机的 user://levels/，只有这台电脑、这个浏览器看得到。
static func save_dir() -> String:
	if _save_dir != "":
		return _save_dir
	if OS.has_feature("editor"):
		_save_dir = DIR
		return _save_dir
	if not OS.has_feature("web"):
		var dir := OS.get_executable_path().get_base_dir()
		for i in 8:
			if FileAccess.file_exists(dir.path_join("project.godot")) and DirAccess.dir_exists_absolute(dir.path_join("levels")):
				_save_dir = dir.path_join("levels") + "/"
				return _save_dir
			var up := dir.get_base_dir()
			if up == dir:
				break
			dir = up
	_save_dir = "user://levels/"
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir


## 存档位置是不是项目文件夹（存下来的关卡会进 git）
static func saves_to_project() -> bool:
	return not save_dir().begins_with("user://")


static func _scan(dir: String, into: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		f = f.trim_suffix(".remap")
		if f.ends_with(".tscn") and not f.begins_with("_"):
			into[f] = dir + f


static func paths() -> Array:
	if _paths.is_empty():
		var by_name := {}
		_scan(DIR, by_name)
		if save_dir() != DIR:
			_scan(save_dir(), by_name)  # 同名的以编辑器存下的为准
		var files: Array = by_name.keys()
		files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		for f in files:
			_paths.append(by_name[f])
	return _paths


## 编辑器存档后重新读一遍
static func reload() -> void:
	_paths.clear()
	_cache.clear()


static func count() -> int:
	return paths().size()


## 按文件名找（res://levels/ 和编辑器存档位置里的同名关卡算同一关）
static func index_of(path: String) -> int:
	var f := path.get_file()
	for i in paths().size():
		if String(paths()[i]).get_file() == f:
			return i
	return -1


static func load_scene(path: String) -> PackedScene:
	return ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene


## 只读的关卡数据（选关界面用）
static func info(i: int) -> Dictionary:
	var p: String = paths()[i]
	if not _cache.has(p):
		var node = load_scene(p).instantiate()
		_cache[p] = node.to_level()
		node.free()
	return _cache[p]


## 一份可以改动的关卡数据（开局用）
static func get_level(i: int) -> Dictionary:
	return info(i).duplicate(true)
