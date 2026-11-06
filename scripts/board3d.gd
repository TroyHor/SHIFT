class_name Board3D
extends Node3D
## 3D 俯视角画面。规则和格子都在 game.gd 里，这里只负责把当前状态搭成 3D 场景。
## 一格 = 1 个单位，格子 (x, y) 的中心在世界坐标 (x + 0.5, 0, y + 0.5)。
## 每次状态变化调用 refresh() 重搭物件；地面和墙用 MultiMesh，一次画完。
## 颜色和 2D 版一样按时代调色：现在是冷蓝夜色，烟雾里是暖褐老照片。

const WALL_H := 0.62
const PITCH := 58.0  # 镜头俯角（度）
const FOV := 30.0
const PERSON_SCALE := 1.35
const OPEN_TIME := 0.62  # 烟雾卷开要多久（秒）
const CLOSE_TIME := 0.5  # 卷回去要多久
const WIN_HW := 1.52  # 完全展开时，烟雾窗口从中心到边的距离（比 1.5 多一点，盖住墙面）

const FLOOR_KINDS := {"parquet": 0, "planks": 1, "carpet": 2, "garden": 3, "snow": 4, "platform": 5}

## 美术风格「黑色旧照」：
##  现在 = 墨蓝夜色的水墨画，明暗两档的卡通光照，所有东西用墨线勾边；
##  过去 = 褐色老照片，像一张卷着的旧照片被烟雾从中间向两边摊开，过去的东西像立体书一样从纸面上立起来。
## 地面和墙的着色器：按格子种类画纹理、靠墙的地方晕一圈墨，再按时代调色（与 Art.grade 相同的公式）。
## 过去的范围由 win（中心 x、中心 z、展开的半宽、0）决定，所以能一列一列地卷开、卷回。
const TILE_SHADER := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform vec4 win = vec4(0.0, 0.0, -1.0, 0.0);
uniform float wall_h = 0.62;
varying vec3 wpos;
varying vec3 wnrm;
varying vec2 cellc;
varying vec4 cus;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cellc = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	cus = INSTANCE_CUSTOM;
}
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
vec3 grade(vec3 c, float past) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 sep = mix(vec3(0.13, 0.085, 0.05), vec3(0.82, 0.73, 0.58), clamp(l * 1.15, 0.0, 1.0));
	vec3 pc = mix(sep, c, 0.12);
	vec3 ink = mix(vec3(0.045, 0.05, 0.075), vec3(0.6, 0.62, 0.7), smoothstep(0.0, 0.85, l));
	vec3 nc = mix(ink, c, 0.3);
	return mix(nc, pc, past);
}
bool bit(int m, int b) { return ((m / b) % 2) == 1; }
void fragment() {
	vec3 c = COLOR.rgb;
	int k = int(cus.r + 0.5);
	int nb = int(cus.a + 0.5);  // 四邻是墙的位：1 北 2 南 4 西 8 东（墙顶则是四邻也是墙）
	vec2 p = wpos.xz;
	vec2 f = fract(p);
	vec2 cell = floor(p);
	float rough = 0.85;
	if (k == 0) {
		// 人字拼木地板
		vec2 q = p * vec2(4.0, 4.0);
		float band = floor(q.x);
		float run = q.y + (mod(band, 2.0) < 1.0 ? q.x : -q.x);
		float plank = floor(run);
		c *= 0.9 + 0.16 * h(vec2(band, plank));
		if (fract(run) < 0.07 || fract(q.x) < 0.05) c *= 0.7;
		rough = 0.5;
	} else if (k == 1) {
		// 长木板
		float row = floor(f.y * 3.0);
		float fy = fract(f.y * 3.0);
		c *= 0.92 + 0.12 * h(cell * 3.1 + row);
		c *= 0.96 + 0.06 * sin(p.x * 23.0 + h(cell + row) * 6.0);
		if (fy < 0.05) c *= 0.6;
		float seam = fract(0.3 + 0.37 * (row + cell.y * 2.0 + cell.x));
		if (abs(f.x - seam) < 0.012) c *= 0.7;
		rough = 0.55;
	} else if (k == 2) {
		// 地毯：深红底，金色菱形和边框
		vec2 q = abs(f - 0.5);
		float d = q.x + q.y;
		if (d < 0.12) c = mix(c, vec3(0.72, 0.56, 0.3), 0.45);
		if (abs(d - 0.3) < 0.015) c = mix(c, vec3(0.72, 0.56, 0.3), 0.25);
		if (max(q.x, q.y) > 0.48) c *= 0.75;
	} else if (k == 3) {
		// 草地：大片明暗，少量草丛
		c *= 0.82 + 0.3 * vn(p * 1.7) + 0.08 * vn(p * 6.0);
	} else if (k == 4) {
		// 雪：柔和起伏，偶尔一点反光
		c *= 0.9 + 0.1 * vn(p * 2.3);
		if (h(floor(p * 14.0)) > 0.985) c = mix(c, vec3(1.0), 0.6);
		rough = 0.95;
	} else if (k == 5) {
		// 站台：石板
		c *= 0.92 + 0.1 * h(cell) + 0.05 * vn(p * 5.0);
		if (min(f.x, f.y) < 0.025) c *= 0.6;
		rough = 0.6;
	} else if (k == 6) {
		// 墙面：下半截护墙板，上半截竖条墙纸，中间一道木线
		float y = wpos.y / wall_h;
		float along = abs(wnrm.x) > 0.5 ? p.y : p.x;
		if (y < 0.38) {
			c *= 0.62;
			if (fract(along * 2.0) < 0.05) c *= 0.75;
		} else {
			if (fract(along * 6.0) < 0.5) c *= 0.9;
		}
		if (abs(y - 0.4) < 0.03) c = COLOR.rgb * 1.6;
		if (y < 0.05) c *= 0.5;
	} else if (k == 7) {
		// 墙顶：墨色，朝外的边一道亮线（相邻也是墙的边不画，墙就连成一整段）
		float e = 0.045;
		bool edge = (!bit(nb, 1) && f.y < e) || (!bit(nb, 2) && f.y > 1.0 - e)
			|| (!bit(nb, 4) && f.x < e) || (!bit(nb, 8) && f.x > 1.0 - e);
		// 墨线排出的斜纹
		float hatch = fract((p.x + p.y) * 6.0);
		if (hatch < 0.18) c *= 0.72;
		if (edge) c = vec3(0.62, 0.58, 0.5);
	}
	if (cus.g > 0.5) {
		c = mix(c, vec3(0.62, 0.82, 0.91), 0.35);
		if (h(floor(p * 11.0)) > 0.95) c = mix(c, vec3(1.0), 0.5);
		rough = 0.25;
	}
	// 靠墙的地面晕一圈墨，房间轮廓更清楚
	if (k <= 5) {
		float ao = 1.0;
		if (bit(nb, 1)) ao = min(ao, f.y);
		if (bit(nb, 2)) ao = min(ao, 1.0 - f.y);
		if (bit(nb, 4)) ao = min(ao, f.x);
		if (bit(nb, 8)) ao = min(ao, 1.0 - f.x);
		c *= mix(0.45, 1.0, smoothstep(0.0, 0.32, ao));
	}
	// 烟雾窗口：格子在 3x3 里、而且烟卷已经滚过这一列
	vec2 dc = abs(cellc - win.xy);
	float inwin = (dc.x < 1.1 && dc.y < 1.1 && win.z > 0.0) ? 1.0 : 0.0;
	float dx = abs(p.x - win.x);
	float past = max(cus.b, inwin * step(dx, win.z));
	if (past > 0.5 && cus.b < 0.5) {
		// 老照片：纸纹和四周的一圈深色边
		c *= 0.94 + 0.1 * vn(p * 18.0);
		float dz = abs(p.y - win.y);
		if (dz > 1.44 && dz < 1.52) c *= 0.55;
	}
	vec3 col = grade(c, past);
	// 卷轴压过的地方投下一道影子
	if (inwin > 0.5 && win.z < 1.5) {
		col *= 1.0 - 0.45 * smoothstep(0.35, 0.0, abs(dx - win.z));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
"""

## 烟卷：一根半透明的圆筒，表面是翻滚的烟涡（不规则、时断时续），边缘虚化。
## UV.x 绕圆周，UV.y 沿轴；spin 让烟涡跟着滚动
const ROLL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float spin = 0.0;
uniform float alpha = 1.0;
uniform float past = 1.0;
uniform float time_s = 0.0;
varying vec3 wn;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	return vn(p) * 0.55 + vn(p * 2.1 + 3.7) * 0.3 + vn(p * 4.3 + 9.1) * 0.15;
}
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	// 绕圆周的坐标随 spin 滚动，再被噪声扭成一团团烟涡
	vec2 q = vec2(UV.x * 4.0 + spin, UV.y * 6.0);
	float warp = fbm(q * 0.8 + vec2(time_s * 0.15, 0.0));
	float smoke = fbm(q + vec2(warp * 2.2, time_s * 0.1));
	vec3 lo = mix(vec3(0.36, 0.38, 0.44), vec3(0.4, 0.33, 0.26), past);
	vec3 hi = mix(vec3(0.86, 0.87, 0.9), vec3(0.95, 0.9, 0.8), past);
	float up = clamp(wn.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = mix(lo, hi, clamp(up * 0.7 + smoke * 0.5, 0.0, 1.0));
	// 烟涡之间的暗缝，让卷的层次看得出来
	c *= 0.75 + 0.25 * smoothstep(0.35, 0.6, smoke);
	float rim = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float ends = smoothstep(0.0, 0.14, UV.y) * smoothstep(1.0, 0.86, UV.y);
	ALBEDO = c;
	ALPHA = alpha * smoothstep(0.05, 0.6, rim) * ends * (0.55 + 0.45 * smoothstep(0.25, 0.65, smoke));
}
"""

## 墨线：反面外扩一圈，只画背面。盒子沿对角方向扩（不会在棱角处裂开），其它沿法线扩
const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 ink : source_color = vec4(0.03, 0.035, 0.06, 1.0);
uniform float width = 0.014;
uniform bool boxy = false;
void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 dir = boxy ? sign(VERTEX) : NORMAL;
	VERTEX += dir * width / max(sc, vec3(0.05));
}
void fragment() {
	ALBEDO = ink.rgb;
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
const SMOKE_PUFFS := 24  # 从烟卷上飘起来的几缕烟
var _smoke_puffs: Array = []  # [MeshInstance3D, StandardMaterial3D, phase]
var _rolls: Array = []  # 四根烟卷：左右两根往外滚，上下两根细的是卷起的边。[节点, 材质]
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
var _outline_sh: Shader
var _outlines := {}

## 烟雾卷开卷回的动画状态：窗口中心、目标（展开 1 / 卷回 0）、当前进度
var _win_c := Vector2i.ZERO
var _win_on := false  # 有没有一个正在显示或正在卷回的窗口
var _open := 0.0
var _open_to := 0.0
var _was_cloud := false
var _hw := -1.0  # 当前展开的半宽
var _pops: Array = []  # [节点, 格子, 是过去吗, 原缩放] 随卷轴立起/倒下的东西
var _player_face := 0.0
var _face_to := 0.0
var _last_pos := Vector2i(-99, -99)
var _bob := 0.0


func setup(g, board_rect: Rect2) -> void:
	game = g
	board = board_rect
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#07080c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.53, 0.64)
	env.ambient_light_energy = 0.55
	env.tonemap_exposure = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
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
	moon.light_color = Color(0.74, 0.79, 0.95)
	moon.light_energy = 0.75
	moon.rotation_degrees = Vector3(-55, -32, 0)
	moon.shadow_enabled = true
	moon.shadow_opacity = 0.75
	add_child(moon)

	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	lamp.omni_attenuation = 1.3
	lamp.shadow_enabled = false
	add_child(lamp)

	smoke_lamp = OmniLight3D.new()
	smoke_lamp.light_color = Color(1.0, 0.76, 0.46)
	smoke_lamp.light_energy = 0.6
	smoke_lamp.omni_range = 2.6
	smoke_lamp.visible = false
	add_child(smoke_lamp)

	_tile_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TILE_SHADER
	_tile_mat.shader = sh
	_tile_mat.set_shader_parameter("wall_h", WALL_H)
	_outline_sh = Shader.new()
	_outline_sh.code = OUTLINE_SHADER
	floor_mm = _new_mm(_box(Vector3(1, 0.1, 1)))
	wall_mm = _new_mm(_box(Vector3(1, WALL_H, 1)))
	cap_mm = _new_mm(_box(Vector3(1.0, 0.05, 1.0)))
	plinth = MeshInstance3D.new()
	add_child(plinth)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	_puff_tex = GradientTexture2D.new()
	_puff_tex.gradient = grad
	_puff_tex.fill = GradientTexture2D.FILL_RADIAL
	_puff_tex.fill_from = Vector2(0.5, 0.5)
	_puff_tex.fill_to = Vector2(1.0, 0.5)
	_puff_tex.width = 64
	_puff_tex.height = 64

	for i in SMOKE_PUFFS:
		var m := _puff_mat()
		var mi := _part(self, _quad(1.0), m, Vector3.ZERO)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		_smoke_puffs.append([mi, m, float(i)])
	var roll_sh := Shader.new()
	roll_sh.code = ROLL_SHADER
	for i in 4:
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 24
		cm.rings = 6
		cm.cap_top = false
		cm.cap_bottom = false
		var rm := ShaderMaterial.new()
		rm.shader = roll_sh
		var ri := MeshInstance3D.new()
		ri.mesh = cm
		ri.material_override = rm
		ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ri.visible = false
		add_child(ri)
		_rolls.append([ri, rm])

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


## 按当前时代调好色的材质（卡通光照：明暗两档）
func _m(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	return _raw(Art.grade(c, _past), rough, metal)


func _raw(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [c.to_html(), rough, metal]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON if metal > 0.3 else BaseMaterial3D.SPECULAR_DISABLED
		if c.a < 0.99:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[k] = m
	return _mats[k]


## 墨线材质：现在是墨蓝，过去是深褐
func _outline(boxy: bool, past: bool) -> ShaderMaterial:
	var k := "%s%s" % [boxy, past]
	if not _outlines.has(k):
		var m := ShaderMaterial.new()
		m.shader = _outline_sh
		m.set_shader_parameter("boxy", boxy)
		m.set_shader_parameter("ink", Color("#1e1008") if past else Color("#05060b"))
		_outlines[k] = m
	return _outlines[k]


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
	# 不透明的实物都勾一圈墨线
	if mat is StandardMaterial3D and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and not mat.emission_enabled:
		mi.material_overlay = _outline(mesh is BoxMesh, _past)
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- 重搭场景

func refresh() -> void:
	fit()
	_track_window()
	_build_tiles()
	for c in dyn.get_children():
		c.free()
	_feet.clear()
	_ghosts.clear()
	_flames.clear()
	_glows.clear()
	_bait_puffs.clear()
	_pops.clear()
	var anim: bool = _win_on and not game.reveal_all
	# 后来的建造（现在才有）。在卷轴范围里的，卷开时倒下、卷回时立起
	for lt in game.d.later_active:
		if game.reveal_all and game.in_window(lt.pos):
			continue
		_past = false
		var ln := _later(lt)
		if anim and _in_anim(lt.pos):
			_pops.append([ln, lt.pos, false, ln.scale])
	_people.clear()
	_looks = game.onlookers()
	_spread_people()
	var shown: Array = []
	if anim:
		# 卷轴范围里两个时代的东西都搭出来，按卷轴走到哪一列来切换
		for e in game.present_ents():
			shown.append([e, false, _in_anim(e.pos)])
		for e in game.past_ents():
			if _in_anim(e.pos):
				shown.append([e, true, true])
	else:
		for e in game.visible_ents():
			shown.append([e, game.in_window(e.pos), false])
	for it in shown:
		var e: Dictionary = it[0]
		_past = it[1]
		var node := _entity(e)
		node.position = at(e.pos) + _offsets.get(e.id, Vector3.ZERO)
		dyn.add_child(node)
		if it[2]:
			_pops.append([node, e.pos, _past, node.scale])
		if _looks.has(e.id) and not it[2]:
			_people[e.id] = [node, node.position]
	_anchors()
	_routes()
	var s: Dictionary = game.s
	if s.pos != _last_pos:
		var dp: Vector2i = s.pos - _last_pos
		if absi(dp.x) + absi(dp.y) == 1:
			_face_to = atan2(dp.x, dp.y)
		_last_pos = s.pos
	_player_to = at(s.pos) + _player_off
	if player.position.distance_to(_player_to) > 1.5:
		player.position = _player_to
	smoke_lamp.visible = s.cloud
	if s.cloud:
		smoke_lamp.position = at(s.center, 1.3)
	_apply_pops()


## 烟雾开合：新吐的一口从中间卷开，散掉或走出去就卷回中间
func _track_window() -> void:
	var s: Dictionary = game.s
	if game.reveal_all:
		_win_on = false
		_open = 0.0
		_open_to = 0.0
		_was_cloud = s.cloud
		return
	if s.cloud and (not _was_cloud or s.center != _win_c or not _win_on):
		_win_c = s.center
		_win_on = true
		_open = 0.0
		_open_to = 1.0
	elif not s.cloud and _was_cloud:
		_open_to = 0.0
	_was_cloud = s.cloud


func _in_anim(p: Vector2i) -> bool:
	return absi(p.x - _win_c.x) <= 1 and absi(p.y - _win_c.y) <= 1


## 卷轴展开的半宽：先快后慢，像纸卷滚开
func _half_width() -> float:
	if not _win_on:
		return -1.0
	var k := _open
	return WIN_HW * (1.0 - pow(1.0 - k, 3.0)) if _open_to > 0.5 else WIN_HW * k * k * (3.0 - 2.0 * k)


## 一格被卷轴盖过多少（0 还是现在，1 已经是过去）
func reveal(p: Vector2i) -> float:
	if game.reveal_all:
		return 1.0 if game.in_window(p) else 0.0
	if not _win_on or not _in_anim(p):
		return 0.0
	var dx := absf(p.x - _win_c.x)
	var lo := maxf(dx - 0.5, 0.0)
	return clampf((_hw - lo) / (dx + 0.5 - lo), 0.0, 1.0)


## 这个东西现在有没有立在画面上（卷轴卷过去之前，过去的人还躺在纸里）
func is_shown(e: Dictionary) -> bool:
	if not _win_on or not _in_anim(e.pos):
		return true
	var f := reveal(e.pos)
	return f > 0.5 if game.in_window(e.pos) else f <= 0.5


## 立体书：过去的东西从纸面上翻起来，现在的东西倒下去
func _apply_pops() -> void:
	for pp in _pops:
		var node: Node3D = pp[0]
		if not is_instance_valid(node):
			continue
		var p: Vector2i = pp[1]
		var f := reveal(p)
		var k := f if pp[2] else 1.0 - f
		node.visible = k > 0.02
		var side := signf(p.x - _win_c.x)
		if side == 0.0:
			side = 1.0
		var e := _back_out(k)
		node.rotation.z = (1.0 - e) * PI * 0.5 * side * (1.0 if pp[2] else -1.0)
		node.scale = pp[3] * Vector3(1.0, maxf(0.05, minf(e, 1.08)), 1.0)


static func _back_out(k: float) -> float:
	var c1 := 1.9
	var x := k - 1.0
	return 1.0 + (c1 + 1.0) * x * x * x + c1 * x * x


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
			Color(FLOOR_KINDS.get(kind, 6), 1.0 if cold.has(p) else 0.0, _forced_past(p), _wall_bits(p)))
	var wbuf := PackedFloat32Array()
	var cbuf := PackedFloat32Array()
	for p in walls:
		var past := _forced_past(p)
		_inst(wbuf, at(p, WALL_H / 2.0), th.face, Color(6, 0, past, 0))
		_inst(cbuf, at(p, WALL_H + 0.025), Color("#46403c"), Color(7, 0, past, _wall_bits(p)))
	_fill(floor_mm, floors.size(), fbuf)
	_fill(wall_mm, walls.size(), wbuf)
	_fill(cap_mm, walls.size(), cbuf)
	# 地图像镶在相框里的老照片：深色木底座，一道金线，外面一圈深酒红的衬底
	var key := "%dx%d %s" % [game.W, game.H, board]
	if plinth.get_meta("key", "") != key:
		plinth.set_meta("key", key)
		for c in plinth.get_children():
			c.free()
		plinth.mesh = _box(Vector3(game.W + 0.2, 0.34, game.H + 0.2))
		plinth.material_override = _raw(Color("#1a120c"), 0.9)
		plinth.position = Vector3(game.W / 2.0, -0.27, game.H / 2.0)
		var mount := _part(plinth, _box(Vector3(game.W + 1.1, 0.04, game.H + 1.1)), _raw(Color("#2a1012"), 0.9), Vector3(0, 0.06, 0))
		mount.material_overlay = null
		var trim := _part(plinth, _box(Vector3(game.W + 0.5, 0.045, game.H + 0.5)), _glow(Color(0.86, 0.68, 0.4), 0.5), Vector3(0, 0.065, 0))
		trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var inner := _part(plinth, _box(Vector3(game.W + 0.36, 0.05, game.H + 0.36)), _raw(Color("#120d09"), 0.9), Vector3(0, 0.07, 0))
		inner.material_overlay = null


## 编辑器的"过去"视图直接整张变成过去；游戏里由卷轴决定
func _forced_past(p: Vector2i) -> float:
	return 1.0 if game.reveal_all and game.in_window(p) else 0.0


## 四邻是墙的位：1 北 2 南 4 西 8 东
func _wall_bits(p: Vector2i) -> float:
	var m := 0
	if _wall(p + Vector2i.UP):
		m |= 1
	if _wall(p + Vector2i.DOWN):
		m |= 2
	if _wall(p + Vector2i.LEFT):
		m |= 4
	if _wall(p + Vector2i.RIGHT):
		m |= 8
	return float(m)


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
			return Color("#7a5434")
		"planks":
			return Color("#86623e")
		"carpet":
			return Color("#7a2228")
		"garden":
			return Color("#33452e")
		"snow":
			return Color("#8e98a6")
		"platform":
			return Color("#4e4e54")
	return Color("#555555")


# ---------------------------------------------------------------- 后来的建造

func _later(lt: Dictionary) -> Node3D:
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
	return n


# ---------------------------------------------------------------- 物件

func _entity(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var kind: String = e.get("kind", "")
	if kind == "source" or e.get("model", "") == "tin":
		_tin(n, false, kind == "source")
	elif kind in ["inspector", "npc"]:
		var body := Node3D.new()
		body.name = "Body"
		body.rotation.y = _face_of(e)
		body.scale = Vector3.ONE * PERSON_SCALE
		n.add_child(body)
		_person(body, Art.style_for(e), false)
		n.set_meta("person", true)
	else:
		var done: bool = (kind in ["cache", "clue"] and game.s.clues.has(e.get("clue", ""))) \
			or (kind == "container" and e.get("taken", false))
		_thing(n, Art.sprite_for(e), e, done)
	return n


## 人朝哪边：过去要走路的人面朝下一步，其他人大致面朝镜头（各自偏一点）
func _face_of(e: Dictionary) -> float:
	if _past and e.has("route"):
		var path: Array = game.route_of(e.id)
		for i in range(1, path.size()):
			var dp: Vector2i = path[i] - path[0]
			if dp != Vector2i.ZERO:
				return atan2(dp.x, dp.y)
	return (Art.h(e.pos.x, e.pos.y) - 0.5) * 1.2


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


## 人物：腿、长外套、双臂、肩、头、帽子。正面朝 +z
func _person(n: Node3D, style: String, detective: bool) -> void:
	var st: Dictionary = Art.PEOPLE.get(style, Art.PEOPLE.butler)
	var coat := _m(st.coat, 0.85)
	var dark := _m(Color(st.coat).darkened(0.45), 0.85)
	var skin := _m(st.skin, 0.7)
	var hatc := _m(st.hatc, 0.75)
	var shoe := _m(Color("#16120e"), 0.6)
	# 腿和鞋
	for sx in [-0.055, 0.055]:
		_part(n, _cyl(0.035, 0.032, 0.14, 8), dark, Vector3(sx, 0.07, 0))
		_part(n, _box(Vector3(0.06, 0.035, 0.1)), shoe, Vector3(sx, 0.017, 0.02))
	# 外套：下摆张开一点
	_part(n, _cyl(0.11, 0.16, 0.3, 14), coat, Vector3(0, 0.27, 0))
	# 肩
	_part(n, _sph(0.13), coat, Vector3(0, 0.43, 0), Vector3.ZERO, Vector3(1.22, 0.62, 0.92))
	# 手臂
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.15 * sx, 0.44, 0)
		arm.rotation.z = 0.12 * sx
		n.add_child(arm)
		_part(arm, _cyl(0.035, 0.042, 0.24, 8), coat, Vector3(0, -0.12, 0))
		_part(arm, _sph(0.032), skin, Vector3(0, -0.25, 0.01))
	# 头和脸
	_part(n, _sph(0.095), skin, Vector3(0, 0.56, 0.01))
	var eye := _raw(Color("#0a0806") if not _past else Color("#2a1608"))
	for sx in [-0.035, 0.035]:
		var ey := _part(n, _sph(0.013), eye, Vector3(sx, 0.565, 0.095))
		ey.material_overlay = null
	match st.hat:
		"fedora":
			_part(n, _cyl(0.19, 0.2, 0.018, 20), hatc, Vector3(0, 0.62, 0))
			_part(n, _cyl(0.085, 0.105, 0.1, 14), hatc, Vector3(0, 0.675, 0))
			_part(n, _cyl(0.107, 0.107, 0.022, 14), _m(Color("#7a2a22")), Vector3(0, 0.64, 0))
		"cap":
			_part(n, _cyl(0.115, 0.105, 0.075, 14), hatc, Vector3(0, 0.645, 0))
			_part(n, _box(Vector3(0.15, 0.015, 0.09)), hatc, Vector3(0, 0.615, 0.12))
			_part(n, _box(Vector3(0.04, 0.03, 0.01)), _m(Art.GOLD, 0.3, 0.8), Vector3(0, 0.65, 0.115))
		"hair":
			_part(n, _sph(0.102), hatc, Vector3(0, 0.585, -0.02), Vector3.ZERO, Vector3(1.0, 0.78, 1.0))
		"bonnet":
			_part(n, _sph(0.12), hatc, Vector3(0, 0.585, -0.025), Vector3.ZERO, Vector3(1.0, 0.82, 1.0))
			_part(n, _torus(0.085, 0.11), _m(Color("#efe8da")), Vector3(0, 0.6, 0.035), Vector3(1.2, 0, 0))
		"chef":
			_part(n, _cyl(0.1, 0.092, 0.14), hatc, Vector3(0, 0.67, 0))
			_part(n, _sph(0.12), hatc, Vector3(0, 0.76, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		"top":
			_part(n, _cyl(0.17, 0.17, 0.016, 20), hatc, Vector3(0, 0.62, 0))
			_part(n, _cyl(0.088, 0.088, 0.19, 14), hatc, Vector3(0, 0.715, 0))
			_part(n, _cyl(0.09, 0.09, 0.025, 14), _m(Color("#4a4a52")), Vector3(0, 0.64, 0))
		"pillbox":
			_part(n, _sph(0.1), _m(Color("#2a1a12")), Vector3(0, 0.585, -0.02), Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
			_part(n, _cyl(0.08, 0.08, 0.065, 14), hatc, Vector3(0, 0.655, 0.01))
	match st.get("detail", ""):
		"collar":
			_part(n, _box(Vector3(0.09, 0.06, 0.03)), _m(Color("#efe8da")), Vector3(0, 0.45, 0.115))
			_part(n, _box(Vector3(0.03, 0.03, 0.02)), _m(Color("#141418")), Vector3(0, 0.465, 0.13))
		"apron":
			_part(n, _box(Vector3(0.2, 0.26, 0.02)), _m(Color("#efe8da")), Vector3(0, 0.27, 0.15), Vector3(-0.15, 0, 0))
		"belt":
			_part(n, _cyl(0.142, 0.142, 0.03, 14), _m(Color("#2a1a10")), Vector3(0, 0.36, 0))
	if style == "inspector":
		_part(n, _box(Vector3(0.04, 0.05, 0.02)), _m(Art.GOLD, 0.3, 0.8), Vector3(0.06, 0.4, 0.12))
	if style == "conductor" or style == "porter":
		for k in 3:
			_part(n, _sph(0.012), _m(Art.GOLD, 0.3, 0.8), Vector3(0, 0.38 - k * 0.07, 0.15 - k * 0.006))
	if detective:
		# 风衣的翻领和腰带，嘴里叼着烟斗
		_part(n, _box(Vector3(0.05, 0.12, 0.02)), dark, Vector3(-0.045, 0.43, 0.115), Vector3(0, 0, 0.35))
		_part(n, _box(Vector3(0.05, 0.12, 0.02)), dark, Vector3(0.045, 0.43, 0.115), Vector3(0, 0, -0.35))
		_part(n, _cyl(0.142, 0.142, 0.03, 14), _m(Color("#5a3a20")), Vector3(0, 0.33, 0))
		_part(n, _cyl(0.011, 0.011, 0.11), _m(Color("#2a1a10")), Vector3(0.04, 0.53, 0.12), Vector3(PI / 2 - 0.2, 0, -0.5))
		_part(n, _cyl(0.03, 0.022, 0.055), _m(Color("#5a2e18")), Vector3(0.085, 0.545, 0.16))
		ember = _part(n, _sph(0.02), _glow(Color(1.0, 0.5, 0.15), 4.0), Vector3(0.085, 0.574, 0.16))


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
			var wood := _m(Color("#6a4226"), 0.6)
			_part(n, _box(Vector3(0.8, 0.82, 0.48)), wood, Vector3(0, 0.45, 0))
			_part(n, _box(Vector3(0.86, 0.05, 0.54)), _m(Color("#4a2a18")), Vector3(0, 0.885, 0))
			_part(n, _box(Vector3(0.84, 0.04, 0.52)), _m(Color("#4a2a18")), Vector3(0, 0.03, 0))
			for sx in [-0.2, 0.2]:
				_part(n, _box(Vector3(0.3, 0.62, 0.02)), _m(Color("#7a5232"), 0.6), Vector3(sx, 0.47, 0.245))
			for sx in [-0.04, 0.04]:
				_part(n, _sph(0.024), _m(Art.GOLD, 0.3, 0.8), Vector3(sx, 0.47, 0.265))
		"safe":
			var steel := _m(Color("#56606c"), 0.35, 0.7)
			_part(n, _box(Vector3(0.6, 0.58, 0.56)), steel, Vector3(0, 0.33, 0))
			for sx in [-0.24, 0.24]:
				for sz in [-0.22, 0.22]:
					_part(n, _box(Vector3(0.07, 0.05, 0.07)), _m(Color("#2a2e36")), Vector3(sx, 0.025, sz))
			_part(n, _box(Vector3(0.62, 0.03, 0.58)), _m(Color("#6a7480"), 0.3, 0.7), Vector3(0, 0.63, 0))
			if done:
				_part(n, _box(Vector3(0.46, 0.44, 0.02)), _raw(Color("#14161a")), Vector3(0, 0.33, 0.281))
				_part(n, _box(Vector3(0.46, 0.44, 0.04)), steel, Vector3(0.43, 0.33, 0.45), Vector3(0, -1.3, 0))
			else:
				_part(n, _box(Vector3(0.48, 0.46, 0.02)), _m(Color("#4a525e"), 0.35, 0.7), Vector3(0, 0.33, 0.285))
				_part(n, _cyl(0.085, 0.085, 0.03), _m(Art.GOLD, 0.3, 0.8), Vector3(0, 0.36, 0.3), Vector3(PI / 2, 0, 0))
				_part(n, _box(Vector3(0.012, 0.07, 0.01)), _m(Color("#2a2e36"), 0.2, 0.9), Vector3(0, 0.38, 0.317), Vector3(0, 0, t * 0.3))
				_part(n, _box(Vector3(0.12, 0.03, 0.03)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0.17, 0.26, 0.3))
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
	var past := reveal(game.s.pos) > 0.5
	var key := "past" if past else "now"
	if body.get_meta("era", "") == key:
		return
	body.set_meta("era", key)
	for c in body.get_children():
		c.free()
	var keep := _past
	_past = past
	_person(body, "detective", true)
	_past = keep


# ---------------------------------------------------------------- 动画

func _process(delta: float) -> void:
	if game == null or not visible:
		return
	t += delta
	var s: Dictionary = game.s
	# 烟雾的卷开卷回
	if _win_on:
		if _open_to > _open:
			_open = minf(1.0, _open + delta / OPEN_TIME)
		elif _open_to < _open:
			_open = maxf(0.0, _open - delta / CLOSE_TIME)
		elif _open_to == 0.0:
			_win_on = false
	_hw = _half_width()
	_tile_mat.set_shader_parameter("win", Vector4(_win_c.x + 0.5, _win_c.y + 0.5, _hw, 0.0))
	_apply_pops()
	_paint_player()
	# 侦探：走到新格子时轻轻一跳，转身面朝走的方向，站着时缓缓呼吸
	var moving := player.position.distance_to(_player_to) > 0.03
	player.position = player.position.lerp(_player_to, minf(1.0, delta * 14.0))
	_bob = minf(1.0, _bob + delta * 6.0) if moving else maxf(0.0, _bob - delta * 4.0)
	var body: Node3D = player.get_node("Body")
	_player_face = lerp_angle(_player_face, _face_to, minf(1.0, delta * 14.0))
	body.rotation.y = _player_face
	body.position.y = absf(sin(t * 16.0)) * 0.06 * _bob
	body.scale = Vector3.ONE * PERSON_SCALE * Vector3(1.0, 1.0 + 0.012 * sin(t * 2.2), 1.0)
	lamp.position = player.position + Vector3(0, 1.5, 0.35)
	lamp.light_energy = 1.4 + 0.06 * sin(t * 7.0) * sin(t * 3.1)
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	ring_mat.albedo_color.a = 0.2 + 0.25 * pulse
	ring_glow.emission_energy_multiplier = 0.6 + 1.0 * pulse
	if ember != null and is_instance_valid(ember):
		ember.visible = s.tobacco > 0
	var pipe := Vector3(0.085, 0.6, 0.16).rotated(Vector3.UP, _player_face) * PERSON_SCALE
	for pp in _pipe_puffs:
		var k := fposmod(t * 0.5 + pp[2], 1.0)
		var on: bool = s.tobacco > 0
		pp[0].visible = on
		pp[0].position = pipe + Vector3(sin(t * 2.0 + pp[2] * 9.0) * 0.05 * k, k * 0.7, 0)
		pp[0].scale = Vector3.ONE * (0.5 + k * 2.4)
		pp[1].albedo_color.a = 0.4 * (1.0 - k) * minf(1.0, k * 6.0)
	for g in _ghosts:
		g.albedo_color.a = 0.28 + 0.16 * (0.5 + 0.5 * sin(t * 2.0))
	for g in _glows:
		g.albedo_color.a = 0.25 + 0.35 * (0.5 + 0.5 * sin(t * 2.5))
	for f in _feet:
		var k := fposmod(t * 1.2 - f[1] * 0.1, 1.0)
		f[0].albedo_color.a = (0.3 + 0.6 * k) * f[2] * clampf(_open * 1.5 - 0.5, 0.0, 1.0)
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
	# 人：站着轻轻呼吸；烟雾旁边的人，看呆了的踮脚，看见过去自己的吓得发抖
	for nd in dyn.get_children():
		if nd.has_meta("person"):
			var b: Node3D = nd.get_node("Body")
			b.scale = Vector3.ONE * PERSON_SCALE * Vector3(1.0, 1.0 + 0.012 * sin(t * 2.0 + nd.position.x * 3.0), 1.0)
	for id in _people:
		var nd: Node3D = _people[id][0]
		var base: Vector3 = _people[id][1]
		if _looks.get(id, "") == "self":
			nd.position = base + Vector3(sin(t * 58.0) * 0.035, 0, cos(t * 47.0) * 0.02)
		else:
			nd.position = base + Vector3(0, absf(sin(t * 5.0 + base.x)) * 0.05, 0)
	hover.rotation.y = t * 1.5
	_animate_smoke(s)


## 现在展开到多宽（给 2D 的胶片颗粒层用）；没有烟雾时是负数
func half_width() -> float:
	return _hw


func window_center() -> Vector3:
	return at(_win_c)


## 烟雾窗口：两根烟卷从中间滚向左右两边，像摊开一张卷着的旧照片，把过去展开；
## 上下两根细烟卷是照片卷起的边。浓度越低，烟卷越细越淡。卷回去时两根烟卷滚回中间，合成一团散掉。
func _animate_smoke(s: Dictionary) -> void:
	var hw := _hw
	if hw <= 0.0 and not (_win_on and _open_to > 0.0):
		for sp in _smoke_puffs:
			sp[0].visible = false
		for r in _rolls:
			r[0].visible = false
		smoke_lamp.visible = false
		return
	hw = maxf(hw, 0.0)
	var c := at(_win_c)
	var density := float(s.turns) / Game.SMOKE_TURNS if s.cloud else 0.35
	var grow := clampf(_open * 3.0, 0.0, 1.0) if _open_to > 0.5 else clampf(_open * 3.0, 0.0, 1.0)
	smoke_lamp.visible = true
	smoke_lamp.position = c + Vector3(0, 1.3, 0)
	smoke_lamp.light_energy = (0.2 + density * 0.3) * grow
	var R := (0.13 + 0.09 * density) * (0.4 + 0.6 * grow)
	var alpha := (0.7 + 0.3 * density) * grow
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var ro: MeshInstance3D = _rolls[i][0]
		var rm: ShaderMaterial = _rolls[i][1]
		ro.visible = true
		ro.position = Vector3(c.x + side * (hw + R * 0.3), 0.3 + R, c.z)
		ro.rotation = Vector3(PI / 2, 0, 0)
		ro.scale = Vector3(R, 3.06, R)
		# 向外滚：滚过的距离 / 半径 = 转过的角度
		rm.set_shader_parameter("spin", -side * (hw / (TAU * R)) - side * t * 0.12)
		rm.set_shader_parameter("alpha", alpha)
		rm.set_shader_parameter("time_s", t)
		rm.set_shader_parameter("past", 1.0)
	for i in 2:
		var edge := -1.0 if i == 0 else 1.0
		var ro: MeshInstance3D = _rolls[2 + i][0]
		var rm: ShaderMaterial = _rolls[2 + i][1]
		var r2 := R * 0.38
		ro.visible = hw > 0.08
		ro.position = Vector3(c.x, r2 + 0.01, c.z + edge * 1.5)
		ro.rotation = Vector3(0, 0, PI / 2)
		ro.scale = Vector3(r2, maxf(hw * 2.0, 0.01), r2)
		rm.set_shader_parameter("spin", t * 0.2 * edge)
		rm.set_shader_parameter("alpha", alpha * 0.8)
		rm.set_shader_parameter("time_s", t + 3.0 * edge)
		rm.set_shader_parameter("past", 1.0)
	# 从两根烟卷上飘起来的几缕烟
	var n := _smoke_puffs.size()
	for j in n:
		var sp: Array = _smoke_puffs[j]
		var side := -1.0 if j % 2 == 0 else 1.0
		var k := fposmod(t * 0.35 + sp[2] * 0.618, 1.0)
		var z := c.z - 1.3 + 2.6 * Art.h(sp[2], 3.0)
		sp[0].visible = true
		sp[0].position = Vector3(c.x + side * (hw + R * 0.3) + sin(t + sp[2]) * 0.08 * k, 0.3 + R * 1.8 + k * 0.9, z)
		sp[0].scale = Vector3.ONE * (0.12 + 0.4 * k)
		sp[1].albedo_color = Color(0.92, 0.88, 0.8, 0.28 * (1.0 - k) * minf(1.0, k * 5.0) * grow * (0.5 + density * 0.5))
