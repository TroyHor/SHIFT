class_name Board3D
extends Node3D
## 3D 俯视角画面。规则和格子都在 game.gd 里，这里只负责把当前状态搭成 3D 场景。
## 一格 = 1 个单位，格子 (x, y) 的中心在世界坐标 (x + 0.5, 0, y + 0.5)。
## 每次状态变化调用 refresh() 重搭物件；地面和墙用 MultiMesh，一次画完。
## 颜色和 2D 版一样按时代调色：现在是冷蓝夜色，烟雾里是暖褐老照片。

const WALL_H := 0.72
const PITCH := 58.0  # 镜头俯角（度）
const FOV := 30.0
const PERSON_SCALE := 1.35

const FLOOR_KINDS := {"parquet": 0, "planks": 1, "carpet": 2, "garden": 3, "snow": 4, "platform": 5}

## 地面和墙的着色器：按格子种类画纹理，再按时代调色（与 Art.grade 相同的公式）
const TILE_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
varying vec3 wpos;
varying vec4 cus;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cus = INSTANCE_CUSTOM;
}
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
vec3 grade(vec3 c, float past) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 sep = mix(vec3(0.227, 0.149, 0.078), vec3(0.957, 0.886, 0.737), clamp(l * 1.1, 0.0, 1.0));
	vec3 pc = mix(sep, c, 0.22) * 0.72;
	vec3 cool = vec3(l * 0.78, l * 0.88, l * 1.12);
	vec3 nc = mix(cool, c, 0.38) * 0.92;
	return mix(nc, pc, past);
}
void fragment() {
	vec3 c = COLOR.rgb;
	int k = int(cus.r + 0.5);
	vec2 p = wpos.xz;
	vec2 f = fract(p);
	vec2 cell = floor(p);
	float rough = 0.85;
	if (k == 0 || k == 1) {
		float row = floor(f.y * 3.0);
		float fy = fract(f.y * 3.0);
		c *= 0.94 + 0.14 * h(cell * 3.1 + row);
		if (fy < 0.05) c *= 0.62;
		float seam = fract(0.3 + 0.37 * (row + cell.y * 2.0 + cell.x));
		if (abs(f.x - seam) < 0.015) c *= 0.7;
		if (k == 0 && mod(cell.x + cell.y, 2.0) < 0.5) c *= 0.93;
		rough = 0.55;
	} else if (k == 2) {
		vec2 q = abs(f - 0.5);
		if (q.x + q.y < 0.16) c = mix(c, vec3(0.69, 0.54, 0.31), 0.55);
		if (max(q.x, q.y) > 0.46) c *= 0.7;
	} else if (k == 3) {
		c *= 0.9 + 0.2 * h(floor(p * 9.0));
	} else if (k == 4) {
		c *= 0.94 + 0.08 * h(floor(p * 7.0));
		rough = 0.95;
	} else if (k == 5) {
		c *= 0.95 + 0.08 * h(cell);
		if (min(f.x, f.y) < 0.03) c *= 0.65;
		rough = 0.6;
	} else if (k == 7) {
		// 墙顶：一圈亮边
		if (min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)) < 0.06) c *= 1.25;
	}
	if (cus.g > 0.5) {
		c = mix(c, vec3(0.62, 0.82, 0.91), 0.35);
		if (h(floor(p * 11.0)) > 0.93) c = mix(c, vec3(1.0), 0.5);
		rough = 0.25;
	}
	ALBEDO = grade(c, cus.b);
	ROUGHNESS = rough;
}
"""

var game
var board := Rect2(48, 76, 864, 470)
var t := 0.0

var cam: Camera3D
var lamp: OmniLight3D
var smoke_lamp: OmniLight3D
var floor_mm: MultiMeshInstance3D
var wall_mm: MultiMeshInstance3D
var cap_mm: MultiMeshInstance3D
var plinth: MeshInstance3D
var dyn: Node3D
var player: Node3D
var player_ring: MeshInstance3D
var ring_mat: StandardMaterial3D
var ring_glow: StandardMaterial3D
var ember: MeshInstance3D
var _player_to := Vector3.ZERO
var _past := false

var _meshes := {}
var _mats := {}
var _puff_tex: GradientTexture2D
var _smoke_puffs: Array = []  # [MeshInstance3D, StandardMaterial3D, phase]
var _pipe_puffs: Array = []
var _feet: Array = []  # [StandardMaterial3D, step, 亮度]
var _ghosts: Array = []  # StandardMaterial3D
var _flames: Array = []  # [Node3D, OmniLight3D or null]
var _glows: Array = []  # StandardMaterial3D
var _bait_puffs: Array = []  # [MeshInstance3D, Vector3]
var _fit_key := ""
var _people := {}  # 实体 id → [节点, 原位置]，烟雾旁边的人做反应用
var env: Environment
var moon: DirectionalLight3D
var _offsets := {}  # 实体 id → 同一格里多个人时的错开量，免得穿模
var _player_off := Vector3.ZERO
var _looks := {}
var hover: MeshInstance3D
var hover_mat: StandardMaterial3D
var _tile_mat: ShaderMaterial


func setup(g, board_rect: Rect2) -> void:
	game = g
	board = board_rect
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#08090d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.5, 0.72)
	env.ambient_light_energy = 0.65
	env.tonemap_exposure = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.5
	cam.far = 200.0
	add_child(cam)
	cam.current = true

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 0.95)
	moon.light_energy = 0.4
	moon.rotation_degrees = Vector3(-62, -28, 0)
	moon.shadow_enabled = true
	add_child(moon)

	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.52)
	lamp.light_energy = 2.2
	lamp.omni_range = 7.5
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = true
	add_child(lamp)

	smoke_lamp = OmniLight3D.new()
	smoke_lamp.light_color = Color(1.0, 0.72, 0.4)
	smoke_lamp.light_energy = 1.6
	smoke_lamp.omni_range = 2.4
	smoke_lamp.visible = false
	add_child(smoke_lamp)

	_tile_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TILE_SHADER
	_tile_mat.shader = sh
	floor_mm = _new_mm(_box(Vector3(1, 0.1, 1)))
	wall_mm = _new_mm(_box(Vector3(1, WALL_H, 1)))
	cap_mm = _new_mm(_box(Vector3(1.0, 0.05, 1.0)))
	plinth = MeshInstance3D.new()
	add_child(plinth)

	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	_puff_tex = GradientTexture2D.new()
	_puff_tex.gradient = grad
	_puff_tex.fill = GradientTexture2D.FILL_RADIAL
	_puff_tex.fill_from = Vector2(0.5, 0.5)
	_puff_tex.fill_to = Vector2(1.0, 0.5)
	_puff_tex.width = 64
	_puff_tex.height = 64

	for i in 36:
		var m := _puff_mat()
		var mi := _part(self, _quad(1.0), m, Vector3.ZERO)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smoke_puffs.append([mi, m, float(i)])

	dyn = Node3D.new()
	add_child(dyn)
	_build_player()
	hover_mat = StandardMaterial3D.new()
	hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover = _part(self, _torus(0.4, 0.46), hover_mat, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.25, 1))
	hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover.visible = false


func _new_mm(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = _tile_mat
	add_child(mmi)
	return mmi


# ---------------------------------------------------------------- 坐标

static func at(p: Vector2i, y := 0.0) -> Vector3:
	return Vector3(p.x + 0.5, y, p.y + 0.5)


## 世界坐标在屏幕上的位置（给名牌、烟雾浓度等 2D 界面用）
func screen(p: Vector2i, y := 0.0) -> Vector2:
	return cam.unproject_position(at(p, y))


## 人物在同一格时会错开站，名字和对话框要跟着人走
func screen_e(e: Dictionary, y := 0.0) -> Vector2:
	return cam.unproject_position(at(e.pos, y) + _offsets.get(e.id, Vector3.ZERO))


func screen_v(v: Vector3) -> Vector2:
	return cam.unproject_position(v)


## 鼠标在地面上指着哪一格
func ground_cell(mp: Vector2) -> Variant:
	var o := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return null
	var k := -o.y / dir.y
	if k < 0:
		return null
	var hit := o + dir * k
	return Vector2i(floori(hit.x), floori(hit.z))


## 鼠标指着的东西：够得着是金色，太远是灰色
func set_hover(p: Vector2i, on: bool, reach: bool) -> void:
	hover.visible = on
	if on:
		hover.position = at(p, 0.03)
		hover_mat.albedo_color = Color(0.95, 0.78, 0.45, 0.9) if reach else Color(0.7, 0.72, 0.78, 0.45)


## 镜头：整张地图放进 board 区域，居中
func fit() -> void:
	var key := "%dx%d %s" % [game.W, game.H, board]
	if key == _fit_key:
		return
	_fit_key = key
	var W: float = game.W
	var H: float = game.H
	var target := Vector3(W / 2.0, 0, H / 2.0)
	var dir := Vector3(0, sin(deg_to_rad(PITCH)), cos(deg_to_rad(PITCH)))
	var dist := maxf(W, H) * 1.6
	var corners: Array = []
	for x in [0.0, W]:
		for z in [0.0, H]:
			for y in [0.0, WALL_H]:
				corners.append(Vector3(x, y, z))
	for it in 12:
		cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in corners:
			var s := cam.unproject_position(c)
			lo = lo.min(s)
			hi = hi.max(s)
		var size := hi - lo
		var k := maxf(size.x / board.size.x, size.y / board.size.y)
		dist *= lerpf(1.0, k, 0.9)
		var off := board.get_center() - (lo + hi) / 2.0
		var ppu := size.x / W
		target.x -= off.x / ppu
		target.z -= off.y / (ppu * sin(deg_to_rad(PITCH)))
	cam.look_at_from_position(target + dir * dist, target, Vector3.UP)


# ---------------------------------------------------------------- 网格与材质

func _box(size: Vector3) -> BoxMesh:
	var k := "b%s" % size
	if not _meshes.has(k):
		var m := BoxMesh.new()
		m.size = size
		_meshes[k] = m
	return _meshes[k]


func _cyl(top: float, bottom: float, hgt: float, seg := 20) -> CylinderMesh:
	var k := "c%s,%s,%s,%d" % [top, bottom, hgt, seg]
	if not _meshes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = hgt
		m.radial_segments = seg
		m.rings = 1
		_meshes[k] = m
	return _meshes[k]


func _sph(r: float) -> SphereMesh:
	var k := "s%s" % r
	if not _meshes.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 16
		m.rings = 8
		_meshes[k] = m
	return _meshes[k]


func _torus(inner: float, outer: float) -> TorusMesh:
	var k := "t%s,%s" % [inner, outer]
	if not _meshes.has(k):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 6
		_meshes[k] = m
	return _meshes[k]


func _quad(s: float) -> QuadMesh:
	var k := "q%s" % s
	if not _meshes.has(k):
		var m := QuadMesh.new()
		m.size = Vector2(s, s)
		_meshes[k] = m
	return _meshes[k]


func _plane(w: float, d: float) -> PlaneMesh:
	var k := "p%s,%s" % [w, d]
	if not _meshes.has(k):
		var m := PlaneMesh.new()
		m.size = Vector2(w, d)
		_meshes[k] = m
	return _meshes[k]


## 按当前时代调好色的材质
func _m(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var g := Art.grade(c, _past)
	if _past:
		g = Color(g.r * 0.72, g.g * 0.72, g.b * 0.72, g.a)
	return _raw(g, rough, metal)


func _raw(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [c.to_html(), rough, metal]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if c.a < 0.99:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[k] = m
	return _mats[k]


func _glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var k := "g%s|%s" % [c.to_html(), energy]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[k] = m
	return _mats[k]


func _puff_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _puff_tex
	m.albedo_color = Color(0.95, 0.92, 0.85, 0.0)
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _flat_mat(c: Color) -> StandardMaterial3D:
	## 贴在地上的发光小图形（脚印、光圈）
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _puff_tex
	m.albedo_color = c
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- 重搭场景

func refresh() -> void:
	fit()
	_build_tiles()
	for c in dyn.get_children():
		c.free()
	_feet.clear()
	_ghosts.clear()
	_flames.clear()
	_glows.clear()
	_bait_puffs.clear()
	for lt in game.d.later_active:
		if game.in_window(lt.pos):
			continue
		_past = false
		_later(lt)
	_people.clear()
	_looks = game.onlookers()
	_spread_people()
	for e in game.visible_ents():
		_past = game.in_window(e.pos)
		var node := _entity(e)
		node.position = at(e.pos) + _offsets.get(e.id, Vector3.ZERO)
		dyn.add_child(node)
		if _looks.has(e.id):
			_people[e.id] = [node, node.position]
	_anchors()
	_routes()
	var s: Dictionary = game.s
	_player_to = at(s.pos) + _player_off
	if player.position.distance_to(_player_to) > 1.5:
		player.position = _player_to
	_past = game.in_window(s.pos)
	_paint_player()
	smoke_lamp.visible = s.cloud
	if s.cloud:
		smoke_lamp.position = at(s.center, 1.3)


## 编辑器里整张地图都要看得清：调亮环境光和月光
func set_edit_light(on: bool) -> void:
	env.ambient_light_energy = 1.5 if on else 0.65
	moon.light_energy = 1.0 if on else 0.4
	moon.shadow_enabled = not on


## 同一格里站了几个人（包括侦探）就左右错开，谁也不穿过谁
func _spread_people() -> void:
	_offsets.clear()
	_player_off = Vector3.ZERO
	var cells := {}
	for e in game.visible_ents():
		if e.kind in ["npc", "inspector"]:
			if not cells.has(e.pos):
				cells[e.pos] = []
			cells[e.pos].append(e.id)
	for p in cells:
		var ids: Array = cells[p]
		var n: int = ids.size() + (1 if p == game.s.pos else 0)
		if n < 2:
			continue
		var gap := 0.62 / float(n)
		var x0 := -gap * (n - 1) / 2.0
		var i := 0
		if p == game.s.pos:
			_player_off = Vector3(x0, 0, 0.06)
			i = 1
		for id in ids:
			_offsets[id] = Vector3(x0 + gap * i, 0, -0.06 if i % 2 else 0.06)
			i += 1


func _wall(p: Vector2i) -> bool:
	return game.tile_at(p) == Game.Tile.WALL


func _build_tiles() -> void:
	var th: Dictionary = Art.THEMES[clampi(int(game.L.get("style", 0)), 0, Art.THEMES.size() - 1)]
	var cold: Array = game.L.cold
	var floors: Array = []
	var walls: Array = []
	for y in game.H:
		for x in game.W:
			var p := Vector2i(x, y)
			if _wall(p):
				walls.append(p)
			else:
				floors.append(p)
	var fbuf := PackedFloat32Array()
	for p in floors:
		var kind: String = th.ring if String(game.L.map[p.y])[p.x] == "," else th.core
		_inst(fbuf, at(p, -0.05), _floor_color(kind),
			Color(FLOOR_KINDS.get(kind, 6), 1.0 if cold.has(p) else 0.0, 1.0 if game.in_window(p) else 0.0, 0))
	var wbuf := PackedFloat32Array()
	var cbuf := PackedFloat32Array()
	for p in walls:
		var past := 1.0 if game.in_window(p) else 0.0
		_inst(wbuf, at(p, WALL_H / 2.0), th.face.darkened(0.25), Color(6, 0, past, 0))
		_inst(cbuf, at(p, WALL_H + 0.025), th.cap.lightened(0.1), Color(7, 0, past, 0))
	_fill(floor_mm, floors.size(), fbuf)
	_fill(wall_mm, walls.size(), wbuf)
	_fill(cap_mm, walls.size(), cbuf)
	# 地图下面一块深色底座，边上一圈金线
	var key := "%dx%d %s" % [game.W, game.H, board]
	if plinth.get_meta("key", "") != key:
		plinth.set_meta("key", key)
		for c in plinth.get_children():
			c.free()
		plinth.mesh = _box(Vector3(game.W + 0.6, 0.3, game.H + 0.6))
		plinth.material_override = _raw(Color("#120f0b"), 0.9)
		plinth.position = Vector3(game.W / 2.0, -0.26, game.H / 2.0)
		var trim := _part(plinth, _box(Vector3(game.W + 0.64, 0.02, game.H + 0.64)), _glow(Color(0.88, 0.7, 0.42), 0.4), Vector3(0, 0.12, 0))
		trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 一个实例：变换 12 个数（按行）+ 颜色 4 个 + 自定义数据 4 个
static func _inst(buf: PackedFloat32Array, pos: Vector3, col: Color, custom: Color) -> void:
	buf.append_array([1, 0, 0, pos.x, 0, 1, 0, pos.y, 0, 0, 1, pos.z,
		col.r, col.g, col.b, col.a, custom.r, custom.g, custom.b, custom.a])


## 每次重搭都换一个新的 MultiMesh，一次写入全部数据
func _fill(mmi: MultiMeshInstance3D, n: int, buf: PackedFloat32Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mmi.multimesh.mesh
	mm.instance_count = n
	if n > 0:
		mm.buffer = buf
	mmi.multimesh = mm


func _floor_color(kind: String) -> Color:
	match kind:
		"parquet":
			return Color("#6a4a30")
		"planks":
			return Color("#7a5a3a")
		"carpet":
			return Color("#6a2026")
		"garden":
			return Color("#3e5236")
		"snow":
			return Color("#d6dde4")
		"platform":
			return Color("#5a5a5e")
	return Color("#555555")


# ---------------------------------------------------------------- 后来的建造

func _later(lt: Dictionary) -> void:
	var n := Node3D.new()
	n.position = at(lt.pos)
	dyn.add_child(n)
	# 墙在左右两边：缺口是东西向的，木板、门沿 x 方向；否则沿 z 方向
	var along_x: bool = _wall(lt.pos + Vector2i.LEFT) or _wall(lt.pos + Vector2i.RIGHT)
	var ry := 0.0 if along_x else PI / 2.0
	match lt.kind:
		"brick":
			_part(n, _box(Vector3(0.98, WALL_H, 0.98)), _m(Color("#7a3a2a")), Vector3(0, WALL_H / 2.0, 0))
			for i in 4:
				var y := 0.12 + i * 0.16
				_part(n, _box(Vector3(1.0, 0.018, 1.0)), _m(Color("#b0a090")), Vector3(0, y, 0))
			_part(n, _box(Vector3(0.02, WALL_H, 1.0)), _m(Color("#b0a090")), Vector3(0.12, WALL_H / 2.0, 0), Vector3(0, ry, 0))
		"planks":
			for i in 3:
				var y := 0.18 + i * 0.22
				var tilt := 0.18 if i % 2 == 0 else -0.14
				_part(n, _box(Vector3(1.04, 0.11, 0.05)), _m(Color("#8a6a40")), Vector3(0, y, 0), Vector3(0, ry, tilt))
			for sx in [-0.42, 0.42]:
				_part(n, _box(Vector3(0.08, WALL_H, 0.08)), _m(Color("#5a4026")), Vector3(sx, WALL_H / 2.0, 0).rotated(Vector3.UP, ry))
		"lock":
			_part(n, _box(Vector3(0.96, WALL_H * 0.96, 0.14)), _m(Color("#4a2e1c")), Vector3(0, WALL_H * 0.48, 0), Vector3(0, ry, 0))
			var front := Vector3(0.25, 0.36, 0.09).rotated(Vector3.UP, ry)
			_part(n, _sph(0.035), _m(Art.GOLD, 0.3, 0.8), front)
			_part(n, _box(Vector3(0.12, 0.14, 0.05)), _m(Color("#8a8e96"), 0.4, 0.7), Vector3(0, 0.3, 0.1).rotated(Vector3.UP, ry))
			_part(n, _torus(0.03, 0.05), _m(Color("#8a8e96"), 0.4, 0.7), Vector3(0, 0.39, 0.1).rotated(Vector3.UP, ry), Vector3(PI / 2, ry, 0))


# ---------------------------------------------------------------- 物件

func _entity(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var kind: String = e.get("kind", "")
	if kind == "source" or e.get("model", "") == "tin":
		_tin(n, false, kind == "source")
	elif kind in ["inspector", "npc"]:
		_person(n, Art.style_for(e), false)
		n.scale = Vector3.ONE * PERSON_SCALE
	else:
		var done: bool = (kind in ["cache", "clue"] and game.s.clues.has(e.get("clue", ""))) \
			or (kind == "container" and e.get("taken", false))
		_thing(n, Art.sprite_for(e), e, done)
	return n


func _tin(n: Node3D, ghost: bool, glow: bool) -> void:
	var body := Color("#b0884a")
	var mb: StandardMaterial3D
	var ml: StandardMaterial3D
	var mr: StandardMaterial3D
	if ghost:
		mb = StandardMaterial3D.new()
		mb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mb.albedo_color = Color(0.85, 0.7, 0.45, 0.35)
		ml = mb
		mr = mb
		_ghosts.append(mb)
	else:
		mb = _m(body.darkened(0.15), 0.4, 0.6)
		ml = _m(body.lightened(0.15), 0.35, 0.6)
		mr = _m(Color("#8a2a22"), 0.7)
	var parts := [
		_part(n, _cyl(0.14, 0.14, 0.24), mb, Vector3(0, 0.12, 0)),
		_part(n, _cyl(0.143, 0.143, 0.08), mr, Vector3(0, 0.11, 0)),
		_part(n, _cyl(0.148, 0.148, 0.03), ml, Vector3(0, 0.255, 0)),
	]
	if ghost:
		for p in parts:
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if glow:
		var gm := _flat_mat(Color(0.88, 0.7, 0.42, 0.5))
		var g := _part(n, _plane(0.9, 0.9), gm, Vector3(0, 0.012, 0))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glows.append(gm)


func _person(n: Node3D, style: String, detective: bool) -> void:
	var st: Dictionary = Art.PEOPLE.get(style, Art.PEOPLE.butler)
	var coat := _m(st.coat, 0.85)
	var skin := _m(st.skin, 0.7)
	var hatc := _m(st.hatc, 0.75)
	_part(n, _cyl(0.12, 0.19, 0.42), coat, Vector3(0, 0.21, 0))
	_part(n, _sph(0.14), coat, Vector3(0, 0.42, 0), Vector3.ZERO, Vector3(1.15, 0.55, 0.9))
	_part(n, _sph(0.1), skin, Vector3(0, 0.55, 0.01))
	match st.hat:
		"fedora":
			_part(n, _cyl(0.19, 0.19, 0.018), hatc, Vector3(0, 0.615, 0))
			_part(n, _cyl(0.09, 0.105, 0.09), hatc, Vector3(0, 0.665, 0))
			_part(n, _cyl(0.107, 0.107, 0.02), _m(Color("#6a2a22")), Vector3(0, 0.632, 0))
		"cap":
			_part(n, _cyl(0.115, 0.11, 0.07), hatc, Vector3(0, 0.64, 0))
			_part(n, _box(Vector3(0.15, 0.015, 0.09)), hatc, Vector3(0, 0.61, 0.12))
			_part(n, _box(Vector3(0.04, 0.03, 0.01)), _m(Art.GOLD, 0.3, 0.8), Vector3(0, 0.645, 0.115))
		"hair":
			_part(n, _sph(0.106), hatc, Vector3(0, 0.575, -0.015), Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
		"bonnet":
			_part(n, _sph(0.125), hatc, Vector3(0, 0.58, -0.02), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
			_part(n, _torus(0.09, 0.115), _m(Color("#efe8da")), Vector3(0, 0.6, 0.03), Vector3(1.2, 0, 0))
		"chef":
			_part(n, _cyl(0.1, 0.095, 0.14), hatc, Vector3(0, 0.67, 0))
			_part(n, _sph(0.12), hatc, Vector3(0, 0.76, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		"top":
			_part(n, _cyl(0.17, 0.17, 0.016), hatc, Vector3(0, 0.615, 0))
			_part(n, _cyl(0.09, 0.09, 0.19), hatc, Vector3(0, 0.71, 0))
		"pillbox":
			_part(n, _cyl(0.085, 0.085, 0.06), hatc, Vector3(0, 0.64, 0))
	match st.get("detail", ""):
		"collar":
			_part(n, _box(Vector3(0.1, 0.05, 0.03)), _m(Color("#efe8da")), Vector3(0, 0.43, 0.12))
		"apron":
			_part(n, _box(Vector3(0.2, 0.28, 0.02)), _m(Color("#efe8da")), Vector3(0, 0.2, 0.165), Vector3(-0.17, 0, 0))
		"belt":
			_part(n, _cyl(0.172, 0.172, 0.03), _m(Color("#2a1a10")), Vector3(0, 0.2, 0))
	if style == "inspector":
		_part(n, _box(Vector3(0.04, 0.05, 0.02)), _m(Art.GOLD, 0.3, 0.8), Vector3(0.07, 0.36, 0.14))
	if detective:
		_part(n, _cyl(0.012, 0.012, 0.1), _m(Color("#2a1a10")), Vector3(0.05, 0.51, 0.12), Vector3(0, 0, PI / 2 - 0.3))
		_part(n, _cyl(0.028, 0.022, 0.05), _m(Color("#4a2a18")), Vector3(0.1, 0.53, 0.12))
		ember = _part(n, _sph(0.018), _glow(Color(1.0, 0.5, 0.15), 4.0), Vector3(0.1, 0.556, 0.12))


func _thing(n: Node3D, sprite: String, e: Dictionary, done: bool) -> void:
	match sprite:
		"desk":
			_part(n, _box(Vector3(0.84, 0.05, 0.6)), _m(Color("#6a4226"), 0.5), Vector3(0, 0.4, 0))
			for sx in [-0.37, 0.37]:
				_part(n, _box(Vector3(0.08, 0.38, 0.52)), _m(Color("#5a3820")), Vector3(sx, 0.19, 0))
			_part(n, _box(Vector3(0.22, 0.01, 0.28)), _m(Color("#efe6d0")), Vector3(-0.16, 0.43, 0.04), Vector3(0, 0.15, 0))
			_part(n, _cyl(0.05, 0.06, 0.02), _m(Color("#2a2a2a")), Vector3(0.22, 0.435, -0.12))
			_part(n, _cyl(0.008, 0.008, 0.18), _m(Color("#2a2a2a")), Vector3(0.22, 0.52, -0.12))
			_part(n, _cyl(0.04, 0.09, 0.07), _m(Color("#2f6a42"), 0.4), Vector3(0.22, 0.62, -0.1))
			_part(n, _sph(0.03), _glow(Color(1.0, 0.86, 0.55), 3.0), Vector3(0.22, 0.585, -0.1))
		"table":
			_part(n, _cyl(0.38, 0.38, 0.04, 28), _m(Color("#5a3820"), 0.5), Vector3(0, 0.38, 0))
			_part(n, _cyl(0.34, 0.34, 0.01, 28), _m(Color("#ddd6c4")), Vector3(0, 0.405, 0))
			_part(n, _cyl(0.05, 0.12, 0.36), _m(Color("#3a2414")), Vector3(0, 0.18, 0))
			_part(n, _cyl(0.05, 0.04, 0.06), _m(Color("#f8f4ea"), 0.3), Vector3(-0.1, 0.44, -0.06))
			_part(n, _cyl(0.035, 0.03, 0.1), _m(Color("#8a2a22"), 0.2), Vector3(0.12, 0.46, 0.09))
		"chair":
			_part(n, _box(Vector3(0.74, 0.06, 0.3)), _m(Color("#6a4a2e")), Vector3(0, 0.24, 0.06))
			_part(n, _box(Vector3(0.74, 0.32, 0.05)), _m(Color("#4a3020")), Vector3(0, 0.42, -0.1))
			for sx in [-0.33, 0.33]:
				for sz in [-0.06, 0.18]:
					_part(n, _box(Vector3(0.05, 0.24, 0.05)), _m(Color("#4a3020")), Vector3(sx, 0.12, sz))
		"crates":
			_part(n, _box(Vector3(0.44, 0.44, 0.44)), _m(Color("#8a6a40")), Vector3(-0.15, 0.22, 0.1), Vector3(0, 0.1, 0))
			_part(n, _box(Vector3(0.4, 0.4, 0.4)), _m(Color("#9a7a4a")), Vector3(0.17, 0.2, -0.13), Vector3(0, -0.2, 0))
			_part(n, _box(Vector3(0.3, 0.3, 0.3)), _m(Color("#7a5a36")), Vector3(-0.12, 0.59, 0.08), Vector3(0, 0.4, 0))
			_part(n, _box(Vector3(0.46, 0.05, 0.46)), _m(Color("#5a4026")), Vector3(-0.15, 0.22, 0.1), Vector3(0, 0.1, 0))
		"plant":
			_part(n, _cyl(0.15, 0.11, 0.24), _m(Color("#8a4a2a")), Vector3(0, 0.12, 0))
			_part(n, _sph(0.2), _m(Color("#3e6a3a")), Vector3(0, 0.38, 0))
			_part(n, _sph(0.14), _m(Color("#4e7a44")), Vector3(0.12, 0.5, 0.05))
			_part(n, _sph(0.13), _m(Color("#36603a")), Vector3(-0.1, 0.52, -0.06))
		"horse":
			var hc := _m(Color("#6a4a30"))
			_part(n, _box(Vector3(0.62, 0.24, 0.24)), hc, Vector3(0, 0.45, 0))
			for sx in [-0.24, 0.24]:
				for sz in [-0.08, 0.08]:
					_part(n, _cyl(0.035, 0.03, 0.34), hc, Vector3(sx, 0.17, sz))
			_part(n, _box(Vector3(0.12, 0.3, 0.14)), hc, Vector3(0.32, 0.62, 0), Vector3(0, 0, -0.5))
			_part(n, _box(Vector3(0.22, 0.1, 0.12)), hc, Vector3(0.43, 0.74, 0))
			_part(n, _box(Vector3(0.3, 0.06, 0.04)), _m(Color("#2a1a10")), Vector3(0.24, 0.66, 0), Vector3(0, 0, -0.5))
			_part(n, _cyl(0.02, 0.04, 0.22), _m(Color("#2a1a10")), Vector3(-0.36, 0.42, 0), Vector3(0, 0, -0.6))
		"snowman":
			var sw := _m(Color("#e8eef2"), 0.95)
			_part(n, _sph(0.22), sw, Vector3(0, 0.2, 0))
			_part(n, _sph(0.16), sw, Vector3(0, 0.52, 0))
			_part(n, _sph(0.11), sw, Vector3(0, 0.76, 0))
			_part(n, _cyl(0.0, 0.02, 0.1), _m(Color("#d06a2a")), Vector3(0, 0.76, 0.14), Vector3(PI / 2, 0, 0))
			_part(n, _cyl(0.12, 0.12, 0.015), _m(Color("#141418")), Vector3(0, 0.85, 0))
			_part(n, _cyl(0.07, 0.07, 0.12), _m(Color("#141418")), Vector3(0, 0.91, 0))
		"barrel":
			for k in 2:
				var bp := Vector3(-0.17 + k * 0.32, 0, -0.08 + k * 0.16)
				_part(n, _cyl(0.17, 0.17, 0.48), _m(Color("#7a5232")), bp + Vector3(0, 0.24, 0))
				for y in [0.08, 0.4]:
					_part(n, _cyl(0.176, 0.176, 0.03), _m(Color("#3a3a3e"), 0.4, 0.6), bp + Vector3(0, y, 0))
				_part(n, _cyl(0.15, 0.15, 0.01), _m(Color("#5a3a22")), bp + Vector3(0, 0.485, 0))
		"cache":
			_part(n, _box(Vector3(0.66, 0.02, 0.66)), _m(Color("#6a4a2e")), Vector3(0, 0.005, 0))
			_part(n, _box(Vector3(0.56, 0.025, 0.56)), _raw(Color("#0a0806")), Vector3(0, 0.008, 0))
			if not done:
				_part(n, _box(Vector3(0.3, 0.01, 0.04)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0.02, 0.03, 0), Vector3(0, 0.6, 0))
				_part(n, _box(Vector3(0.12, 0.025, 0.05)), _m(Color("#4a2a1a")), Vector3(-0.14, 0.035, 0.1), Vector3(0, 0.6, 0))
		"cart":
			_part(n, _box(Vector3(0.7, 0.2, 0.44)), _m(Color("#7a5434")), Vector3(0, 0.3, 0))
			for sx in [-0.3, 0.3]:
				for sz in [-0.24, 0.24]:
					_part(n, _cyl(0.09, 0.09, 0.04), _m(Color("#2a2a2a")), Vector3(sx, 0.1, sz), Vector3(PI / 2, 0, 0))
			_part(n, _cyl(0.1, 0.1, 0.03), _m(Color("#e8e2d4"), 0.3), Vector3(-0.1, 0.415, 0))
			_part(n, _cyl(0.04, 0.035, 0.08), _m(Color("#e8e2d4"), 0.3), Vector3(0.15, 0.44, 0.05))
		"bookshelf":
			_part(n, _box(Vector3(0.86, 0.82, 0.38)), _m(Color("#4a2e1c")), Vector3(0, 0.41, -0.06))
			var cols := [Color("#7a2a22"), Color("#2a4a3a"), Color("#2a3458"), Color("#a07a30"), Color("#5a2a4a")]
			for row in 2:
				for k in 7:
					var bh := 0.22 + Art.h(k, row) * 0.08
					_part(n, _box(Vector3(0.09, bh, 0.06)), _m(cols[(k + row * 2) % cols.size()]),
						Vector3(-0.33 + k * 0.11, 0.08 + row * 0.38 + bh / 2.0, 0.14))
		"wardrobe":
			_part(n, _box(Vector3(0.82, 0.86, 0.5)), _m(Color("#5a3820"), 0.6), Vector3(0, 0.43, 0))
			_part(n, _box(Vector3(0.012, 0.76, 0.02)), _m(Color("#2a1a10")), Vector3(0, 0.44, 0.25))
			for sx in [-0.05, 0.05]:
				_part(n, _sph(0.022), _m(Art.GOLD, 0.3, 0.8), Vector3(sx, 0.46, 0.26))
			_part(n, _box(Vector3(0.86, 0.04, 0.54)), _m(Color("#4a2a18")), Vector3(0, 0.87, 0))
		"safe":
			_part(n, _box(Vector3(0.6, 0.6, 0.56)), _m(Color("#4a525e"), 0.35, 0.7), Vector3(0, 0.3, 0))
			if done:
				_part(n, _box(Vector3(0.46, 0.46, 0.02)), _raw(Color("#14161a")), Vector3(0, 0.3, 0.281))
				_part(n, _box(Vector3(0.46, 0.46, 0.04)), _m(Color("#4a525e"), 0.35, 0.7), Vector3(0.43, 0.3, 0.45), Vector3(0, -1.3, 0))
			else:
				_part(n, _cyl(0.09, 0.09, 0.03), _m(Color("#2a2e36"), 0.3, 0.8), Vector3(0, 0.33, 0.29), Vector3(PI / 2, 0, 0))
				_part(n, _box(Vector3(0.012, 0.07, 0.01)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0, 0.36, 0.307), Vector3(0, 0, t * 0.3))
				_part(n, _box(Vector3(0.1, 0.03, 0.03)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0.18, 0.3, 0.29))
		"rack":
			_part(n, _box(Vector3(0.8, 0.1, 0.24)), _m(Color("#5a4026")), Vector3(0, 0.05, 0))
			_part(n, _box(Vector3(0.8, 0.06, 0.06)), _m(Color("#5a4026")), Vector3(0, 0.42, -0.06))
			var picks := 7 if e.era == "past" else 6
			for k in picks:
				_part(n, _cyl(0.012, 0.012, 0.36), _m(Color("#cfe6f2"), 0.2, 0.8), Vector3(-0.33 + k * 0.11, 0.26, 0))
		"candle":
			_part(n, _cyl(0.16, 0.16, 0.04), _m(Color("#a07a30"), 0.3, 0.8), Vector3(0, 0.02, 0))
			_part(n, _cyl(0.055, 0.06, 0.26), _m(Color("#efe6d0"), 0.6), Vector3(0, 0.17, 0))
			if e.get("lit", false) and _past:
				var f := _part(n, _sph(0.04), _glow(Color(1.0, 0.6, 0.24), 5.0), Vector3(0, 0.34, 0), Vector3.ZERO, Vector3(0.7, 1.4, 0.7))
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.65, 0.3)
				l.omni_range = 2.4
				l.light_energy = 1.5
				l.position = Vector3(0, 0.45, 0)
				n.add_child(l)
				_flames.append([f, l])
		"wax":
			_part(n, _cyl(0.14, 0.16, 0.03), _m(Color("#d8cfb8")), Vector3(0, 0.015, 0))
			_part(n, _cyl(0.008, 0.008, 0.04), _raw(Color("#1a1a1a")), Vector3(0, 0.04, 0))
		"logs":
			for k in 5:
				var row := 0 if k < 3 else 1
				var col := k if k < 3 else k - 3
				_part(n, _cyl(0.1, 0.1, 0.72, 10), _m(Color("#7a5232")),
					Vector3(-0.2 + col * 0.2 + row * 0.1, 0.1 + row * 0.17, 0), Vector3(0, 0, PI / 2))
		"embers":
			_part(n, _cyl(0.32, 0.36, 0.04), _m(Color("#3a3634"), 0.95), Vector3(0, 0.02, 0))
			for k in 6:
				var ep := Vector3((Art.h(k, 1) - 0.5) * 0.5, 0.05, (Art.h(1, k) - 0.5) * 0.5)
				var em := _part(n, _sph(0.025), _glow(Color(1, 0.45, 0.15), 3.0), ep)
				_flames.append([em, null])
		"book":
			var bc := Color("#6a1e1a")
			if done:
				bc = bc.darkened(0.5)
			_part(n, _box(Vector3(0.3, 0.06, 0.38)), _m(bc, 0.7), Vector3(0, 0.03, 0), Vector3(0, 0.2, 0))
			_part(n, _box(Vector3(0.28, 0.05, 0.36)), _m(Color("#efe6d0")), Vector3(0.012, 0.03, 0), Vector3(0, 0.2, 0))
			_part(n, _box(Vector3(0.1, 0.004, 0.04)), _glow(Art.GOLD, 0.6), Vector3(0, 0.063, 0), Vector3(0, 0.2, 0))
		"paper":
			var pc := Art.PAPER
			if done:
				pc = pc.darkened(0.5)
			_part(n, _box(Vector3(0.34, 0.008, 0.26)), _m(pc, 0.9), Vector3(0, 0.005, 0), Vector3(0, -0.15, 0))
			_part(n, _cyl(0.035, 0.035, 0.01), _m(Color("#a82a22"), 0.4), Vector3(0.1, 0.012, 0.06))
		"bed":
			_part(n, _box(Vector3(0.84, 0.24, 0.9)), _m(Color("#5a3820")), Vector3(0, 0.12, 0))
			_part(n, _box(Vector3(0.78, 0.08, 0.84)), _m(Color("#efe8da")), Vector3(0, 0.28, 0))
			_part(n, _box(Vector3(0.8, 0.06, 0.56)), _m(Color("#5a2a32")), Vector3(0, 0.33, 0.13))
			_part(n, _box(Vector3(0.5, 0.08, 0.18)), _m(Color("#f4efe4")), Vector3(0, 0.35, -0.3))
		"toolbox":
			_part(n, _box(Vector3(0.56, 0.24, 0.3)), _m(Color("#8a2e22"), 0.5, 0.3), Vector3(0, 0.12, 0))
			_part(n, _torus(0.08, 0.1), _m(Color("#2a2a2a")), Vector3(0, 0.25, 0), Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.6))
			if e.era == "past":
				_part(n, _box(Vector3(0.34, 0.025, 0.05)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0, 0.26, 0.04), Vector3(0, 0.4, 0))
		"puddle":
			var wm := _m(Color(0.42, 0.56, 0.66, 0.55), 0.02, 0.2)
			_part(n, _cyl(0.34, 0.34, 0.006, 20), wm, Vector3(-0.05, 0.004, 0.03), Vector3.ZERO, Vector3(1, 1, 0.8))
			_part(n, _cyl(0.16, 0.16, 0.006, 16), wm, Vector3(0.2, 0.004, -0.14))
		"ice":
			_part(n, _box(Vector3(0.62, 0.62, 0.62)), _m(Color(0.66, 0.85, 0.93, 0.78), 0.05), Vector3(0, 0.31, 0))
			_part(n, _box(Vector3(0.4, 0.4, 0.4)), _raw(Color(1, 1, 1, 0.25), 0.05), Vector3(0, 0.31, 0))
		"ashtray":
			_part(n, _cyl(0.18, 0.2, 0.06), _m(Color("#6a6a72"), 0.3, 0.6), Vector3(0, 0.03, 0))
			_part(n, _cyl(0.13, 0.13, 0.01), _m(Color("#3a3a40")), Vector3(0, 0.062, 0))
			if e.get("baited", false):
				_part(n, _sph(0.06), _m(Color("#b0884a")), Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
				var pm := _puff_mat()
				var pu := _part(n, _quad(0.18), pm, Vector3(0, 0.2, 0))
				pu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_bait_puffs.append([pu, pm])
		"glove":
			var gc := Color("#c8b48a").darkened(0.4 if done else 0.0)
			_part(n, _box(Vector3(0.18, 0.05, 0.2)), _m(gc, 0.9), Vector3(0, 0.025, 0.04), Vector3(0, 0.4, 0))
			for k in 4:
				var fp := Vector3(-0.06 + k * 0.04, 0.02, -0.1).rotated(Vector3.UP, 0.4)
				_part(n, _box(Vector3(0.03, 0.035, 0.1)), _m(gc, 0.9), fp, Vector3(0, 0.4, 0))
				_part(n, _box(Vector3(0.032, 0.037, 0.03)), _m(Color("#a82a22"), 0.5), fp + Vector3(0, 0, -0.05).rotated(Vector3.UP, 0.4), Vector3(0, 0.4, 0))
			_part(n, _box(Vector3(0.06, 0.035, 0.08)), _m(gc, 0.9), Vector3(0.1, 0.02, 0.06), Vector3(0, -0.3, 0))
		"bottle":
			_part(n, _cyl(0.07, 0.07, 0.3), _m(Color(0.22, 0.38, 0.24, 0.85), 0.1), Vector3(0, 0.07, 0), Vector3(0, 0, PI / 2 - 0.05))
			_part(n, _cyl(0.025, 0.035, 0.1), _m(Color(0.22, 0.38, 0.24, 0.85), 0.1), Vector3(0.19, 0.07, 0), Vector3(0, 0, PI / 2))
			_part(n, _cyl(0.072, 0.072, 0.08), _m(Color("#e8dcc0")), Vector3(-0.02, 0.07, 0), Vector3(0, 0, PI / 2 - 0.05))
		_:
			_part(n, _box(Vector3(0.7, 0.42, 0.7)), _m(Color("#6b5440")), Vector3(0, 0.21, 0))
			var lb := Label3D.new()
			lb.text = String(e.get("label", "?"))
			lb.font = Art.SANS
			lb.font_size = 48
			lb.pixel_size = 0.008
			lb.modulate = Color("#efe6d2")
			lb.rotation = Vector3(-PI / 2, 0, 0)
			lb.position = Vector3(0, 0.425, 0)
			n.add_child(lb)


# ---------------------------------------------------------------- 烟丝锚点与路线

## 另一个时代的烟丝源画成虚影；同一格两个时代都有东西时先显示现在的
func _anchors() -> void:
	for e in game.anchors():
		var shown: bool = game.in_window(e.pos) == (e.era == "past")
		if shown:
			continue
		var other: Array = game.present_ents() if e.era == "past" else game.past_ents()
		var covered := false
		for o in other:
			if o.pos == e.pos and o.id != e.id:
				covered = true
				break
		if covered:
			continue
		var n := Node3D.new()
		n.position = at(e.pos)
		dyn.add_child(n)
		_tin(n, true, false)


## 烟雾里能看到的人，脚下画出他们接下来要走的脚印。
## 人不在烟雾里、但这一夜会从烟雾里走过的，也画出烟雾里那一段（淡一些，终点不打叉）
func _routes() -> void:
	for e in game.past_ents():
		if e.kind != "npc" or not e.has("route"):
			continue
		var inside: bool = game.in_window(e.pos)
		var path: Array = game.route_of(e.id)
		var steps := 0
		for i in range(1, path.size()):
			var a: Vector2i = path[i - 1]
			var b: Vector2i = path[i]
			if a == b:
				continue
			steps += 1
			if not inside and not (game.in_window(a) or game.in_window(b)):
				continue
			var dir := Vector3(b.x - a.x, 0, b.y - a.y)
			var side := Vector3(-dir.z, 0, dir.x) * 0.12
			for fk in [0.25, 0.75]:
				var m := _flat_mat(Color(0.88, 0.7, 0.42, 0.6))
				var sgn := 1.0 if (steps % 2 == 0) == (fk < 0.5) else -1.0
				var p := at(a, 0.015).lerp(at(b, 0.015), fk) + side * sgn
				var fm := _part(dyn, _plane(0.12, 0.2), m, p, Vector3(0, atan2(dir.x, dir.z), 0))
				fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_feet.append([m, steps, 1.0 if inside else 0.8])
		if not inside and not game.in_window(path[path.size() - 1]):
			continue
		var end := at(path[path.size() - 1], 0.02)
		for r in [PI / 4, -PI / 4]:
			var x := _part(dyn, _box(Vector3(0.42, 0.01, 0.05)), _glow(Art.GOLD, 1.2), end, Vector3(0, r, 0))
			x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- 侦探

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	ring_mat = _flat_mat(Color(0.88, 0.7, 0.42, 0.5))
	player_ring = _part(player, _plane(1.0, 1.0), ring_mat, Vector3(0, 0.012, 0))
	player_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * PERSON_SCALE
	ring_glow = _glow(Art.GOLD, 1.5)
	var tr := _part(player, _torus(0.36, 0.42), ring_glow, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.add_child(body)
	for i in 5:
		var m := _puff_mat()
		var mi := _part(player, _quad(0.12), m, Vector3.ZERO)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pipe_puffs.append([mi, m, i / 5.0])


func _paint_player() -> void:
	var body: Node3D = player.get_node("Body")
	var key := "past" if _past else "now"
	if body.get_meta("era", "") == key:
		return
	body.set_meta("era", key)
	for c in body.get_children():
		c.free()
	_person(body, "detective", true)


# ---------------------------------------------------------------- 动画

func _process(delta: float) -> void:
	if game == null or not visible:
		return
	t += delta
	player.position = player.position.lerp(_player_to, minf(1.0, delta * 18.0))
	lamp.position = player.position + Vector3(0, 1.5, 0.35)
	lamp.light_energy = 2.2 + 0.08 * sin(t * 7.0) * sin(t * 3.1)
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	ring_mat.albedo_color.a = 0.25 + 0.3 * pulse
	ring_glow.emission_energy_multiplier = 0.8 + 1.4 * pulse
	var s: Dictionary = game.s
	if ember != null and is_instance_valid(ember):
		ember.visible = s.tobacco > 0
	for pp in _pipe_puffs:
		var k := fposmod(t * 0.6 + pp[2], 1.0)
		var on: bool = s.tobacco > 0
		pp[0].visible = on
		pp[0].position = Vector3(0.1 + sin(t * 2.0 + pp[2] * 9.0) * 0.04 * k, 0.6 + k * 0.6, 0.12)
		pp[0].scale = Vector3.ONE * (0.6 + k * 2.2)
		pp[1].albedo_color.a = 0.5 * (1.0 - k)
	for g in _ghosts:
		g.albedo_color.a = 0.28 + 0.16 * (0.5 + 0.5 * sin(t * 2.0))
	for g in _glows:
		g.albedo_color.a = 0.25 + 0.35 * (0.5 + 0.5 * sin(t * 2.5))
	for f in _feet:
		var k := fposmod(t * 1.2 - f[1] * 0.1, 1.0)
		f[0].albedo_color.a = (0.3 + 0.6 * k) * f[2]
	for fl in _flames:
		var fk := 0.5 + 0.5 * sin(t * 11.0 + fl[0].position.x * 20.0)
		fl[0].scale = Vector3(0.7, 1.2 + 0.4 * fk, 0.7) if fl[1] != null else Vector3.ONE * (0.7 + 0.5 * fk)
		if fl[1] != null:
			fl[1].light_energy = 1.3 + 0.4 * fk
	for bp in _bait_puffs:
		var k := fposmod(t * 0.6, 1.0)
		bp[0].position = Vector3(sin(t * 2.0) * 0.03, 0.12 + k * 0.4, 0)
		bp[0].scale = Vector3.ONE * (0.6 + k * 1.6)
		bp[1].albedo_color.a = 0.45 * (1.0 - k)
	# 烟雾旁边的人：看呆了的轻轻踮脚，看见过去自己的吓得发抖
	for id in _people:
		var nd: Node3D = _people[id][0]
		var base: Vector3 = _people[id][1]
		if _looks.get(id, "") == "self":
			nd.position = base + Vector3(sin(t * 58.0) * 0.035, 0, cos(t * 47.0) * 0.02)
		else:
			nd.position = base + Vector3(0, absf(sin(t * 5.0 + base.x)) * 0.05, 0)
	hover.rotation.y = t * 1.5
	_animate_smoke()


## 烟雾窗口：沿 3x3 的四边翻滚的烟团，越淡烟团越小
func _animate_smoke() -> void:
	var s: Dictionary = game.s
	var on: bool = s.cloud
	if not on:
		for sp in _smoke_puffs:
			sp[0].visible = false
		return
	var c := at(s.center)
	var density := float(s.turns) / Game.SMOKE_TURNS
	smoke_lamp.light_energy = 0.25 + density * 0.2
	var n := _smoke_puffs.size()
	for i in n:
		var sp: Array = _smoke_puffs[i]
		sp[0].visible = true
		var side := i % 4
		var k := (float(i / 4) + 0.5) / float(n / 4)
		var a: float = t * 0.7 + sp[2] * 1.3
		var e := 1.5
		var pos: Vector3
		match side:
			0:
				pos = c + Vector3(-e + 2 * e * k, 0, -e)
			1:
				pos = c + Vector3(e, 0, -e + 2 * e * k)
			2:
				pos = c + Vector3(e - 2 * e * k, 0, e)
			_:
				pos = c + Vector3(-e, 0, e - 2 * e * k)
		pos += Vector3(sin(a) * 0.08, 0.25 + 0.25 * (0.5 + 0.5 * sin(a * 0.7)), cos(a * 1.3) * 0.08)
		sp[0].position = pos
		sp[0].scale = Vector3.ONE * (0.7 + 0.2 * sin(a * 0.8)) * (0.6 + 0.5 * density)
		sp[1].albedo_color.a = 0.3 * (0.4 + density)
