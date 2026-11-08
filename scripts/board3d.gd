class_name Board3D
extends Node3D
## 3D 俯视角画面。规则和格子都在 game.gd 里，这里只负责把当前状态搭成 3D 场景。
## 一格 = 1 个单位，格子 (x, y) 的中心在世界坐标 (x + 0.5, 0, y + 0.5)。
## 每次状态变化调用 refresh() 重搭物件；地面和墙用 MultiMesh，一次画完。
##
## 美术风格「白昼里的一块夜」（见 docs/art-style.md）：每一关是一座犯罪现场模型。
## 现在 = 案发后的清晨，阴天的白光；烟雾窗口 = 案发当晚，深蓝的夜里点着暖色的灯。
## 两个时代不靠调色区分，而是靠光：所有表面共用一段着色代码，按"这一点在不在烟里"
## 换一套光照（日光 / 月光 + 灯光）。所以物件只做一次，也不用按时代分材质。
## 烟雾窗口是烟斗吐出的烟圈：一圈翻滚的烟管从侦探脚下滚出去，卷开 3x3；合上时再卷回来。

const WALL_H := 0.72
const PITCH := 58.0  # 镜头俯角（度）
const FOV := 30.0
const PERSON_SCALE := 1.35
const WIN := 1.5  # 烟雾窗口的半宽（3x3）
const OPEN_TIME := 0.75
const DOOR_OPEN := 1.55  # 门开到多大（弧度）
const DOOR_OPEN_TIME := 0.15
const DOOR_CLOSE_TIME := 0.45
const CLOSE_TIME := 0.6

const FLOOR_KINDS := {"parquet": 0, "planks": 1, "carpet": 2, "garden": 3, "snow": 4, "platform": 5}

## 所有表面共用：判断在不在烟里，按时代换光
const SHADE_COMMON := """
global uniform vec4 smoke_a;
global uniform vec4 smoke_b;
global uniform float smoke_all;
// 两个时代各自是白天(0)还是黑夜(1)，由关卡的时间点决定（见 Board3D._era_light）
global uniform vec2 era_night;
varying vec3 wpos;
varying vec3 wnrm;
varying float nite;
varying float v_spec;
varying float v_shin;

float hsh(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hsh(i), hsh(i + vec2(1.0, 0.0)), f.x), mix(hsh(i + vec2(0.0, 1.0)), hsh(i + vec2(1.0, 1.0)), f.x), f.y);
}

// x = 在烟里的程度，y = 烟圈里外一圈的影子（烟管挡住了光）
vec2 era(vec2 p) {
	if (smoke_all > 0.5) return vec2(1.0, 0.0);
	vec2 r = vec2(0.0);
	for (int i = 0; i < 2; i++) {
		vec4 w = i == 0 ? smoke_a : smoke_b;
		if (w.z > 0.001) {
			vec2 d = abs(p - w.xy);
			float c = max(d.x, d.y);
			float m = 1.0 - smoothstep(w.z - 0.02, w.z + 0.02, c);
			r.x = max(r.x, m);
			r.y = max(r.y, 1.0 - smoothstep(0.0, 0.45, abs(c - w.z)));
		}
	}
	return r;
}

// 现在的颜色淡一点（案发后），烟里保留原色。光按这一点的时代是白天还是黑夜来定
vec3 finish(vec3 c, out vec3 emit, out float nt, out float pst) {
	vec2 e = era(wpos.xz);
	pst = e.x;
	nt = mix(era_night.x, era_night.y, pst);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, mix(0.8, 1.0, pst));
	// 烟管压在地上的一圈影子：让窗口的边一眼看得出
	c *= 1.0 - 0.45 * e.y;
	// 环境光自己算（兼容渲染器不认 AO）：白天是明亮的天光，夜里几乎没有
	emit = c * mix(vec3(0.36, 0.38, 0.42), vec3(0.02, 0.03, 0.07), nt);
	return c;
}

void light() {
	float ndl = clamp((dot(NORMAL, LIGHT) + 0.35) / 1.35, 0.0, 1.0);
	vec3 k;
	if (LIGHT_IS_DIRECTIONAL) {
		k = mix(vec3(1.0), vec3(0.045, 0.065, 0.15), nite);
	} else {
		k = vec3(mix(0.06, 1.0, nite));
	}
	// 介于白天和黑夜之间（两个时代时间相近时）是黄昏：主光偏暖
	if (LIGHT_IS_DIRECTIONAL) k *= mix(vec3(1.0), vec3(1.3, 0.85, 0.55), 4.0 * nite * (1.0 - nite));
	vec3 lc = LIGHT_COLOR * ATTENUATION * k;
	DIFFUSE_LIGHT += ndl * lc / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += pow(max(dot(NORMAL, hv), 0.0), v_shin) * v_spec * lc * 0.3;
}
"""

## 物件：一种颜色 + 光泽；lamp 是只在过去亮着的灯（台灯、壁灯）
const PROP_SHADER := """
shader_type spatial;
render_mode %s;
uniform vec4 albedo : source_color = vec4(1.0);
// Dify 工作流做的模型带一张颜色贴图；程序拼的物件没有贴图，就是白色
uniform sampler2D tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float spec_amt = 0.15;
uniform float shin_amt = 16.0;
uniform vec4 lamp : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float lamp_e = 0.0;
%s
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	v_spec = spec_amt;
	v_shin = shin_amt;
	vec3 em;
	float nt;
	float pst;
	// 贴图取模糊一点的那层：细碎的写实纹理变成大块的颜色，像手工上漆
	vec4 tc = texture(tex, UV, 1.5);
	ALBEDO = finish(albedo.rgb * tc.rgb, em, nt, pst);
	nite = nt;
	EMISSION = em + lamp.rgb * lamp_e * nt;
	ROUGHNESS = 0.8;
	%s
}
"""

## 地面和墙：按格子种类画纹理。墙是剖开的模型墙：顶上是浅色的剖面，侧面是墙纸或外墙
const TILE_SHADER := """
shader_type spatial;
%s
varying vec4 cus;
const float WALL_H = 0.72;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cus = INSTANCE_CUSTOM;
}
bool bit(int m, int b) { return (m / b) %% 2 == 1; }
void fragment() {
	vec3 c = COLOR.rgb;
	int k = int(cus.r + 0.5);
	vec2 p = wpos.xz;
	vec2 f = fract(p);
	vec2 cell = floor(p);
	float spec = 0.06;
	float shin = 12.0;
	int m = int(cus.a + 0.5);
	if (k == 6) {
		int th = int(cus.g + 0.5);
		int nb = m / 16;
		if (wnrm.y > 0.5) {
			// 墙顶剖面：浅色卡纸，旁边没有墙的那一边描一道深色的边
			// 剖面的颜色跟着主题：书房暖灰、旅馆浅木、列车深灰
			vec3 cap = th == 0 ? vec3(0.5, 0.47, 0.42) : (th == 1 ? vec3(0.54, 0.48, 0.41) : vec3(0.5, 0.49, 0.48));
			c = cap * (0.95 + 0.08 * vn(p * 7.0));
			float e = 1.0;
			if (!bit(nb, 1)) e = min(e, 1.0 - f.x);
			if (!bit(nb, 2)) e = min(e, f.x);
			if (!bit(nb, 4)) e = min(e, 1.0 - f.y);
			if (!bit(nb, 8)) e = min(e, f.y);
			if (e < 0.05) c *= 0.5;
		} else {
			int side = wnrm.x > 0.5 ? 1 : (wnrm.x < -0.5 ? 2 : (wnrm.z > 0.5 ? 4 : 8));
			float s = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
			float y = clamp(wpos.y / WALL_H, 0.0, 1.0);
			if (bit(m %% 16, side)) {
				// 外墙
				if (th == 0) {
					float row = floor(y * 9.0);
					float bx = fract(s * 3.0 + 0.5 * mod(row, 2.0));
					c = vec3(0.5, 0.27, 0.2) * (0.88 + 0.2 * hsh(vec2(floor(s * 3.0 + 0.5 * mod(row, 2.0)), row)));
					if (fract(y * 9.0) < 0.14 || bx < 0.05) c = vec3(0.62, 0.58, 0.52);
				} else if (th == 1) {
					float fy = fract(y * 5.0);
					c = vec3(0.32, 0.22, 0.15) * (0.7 + 0.45 * sin(fy * 3.1416));
				} else {
					c = vec3(0.2, 0.32, 0.26);
					if (y > 0.58 && y < 0.66) c = vec3(0.78, 0.72, 0.58);
					if (length(vec2(fract(s * 4.0) - 0.5, (fract(y * 6.0) - 0.5) * 0.7)) < 0.09) c *= 1.5;
					spec = 0.3;
					shin = 30.0;
				}
			} else {
				// 室内：墙纸 / 木板 / 车厢护墙板
				if (th == 0) {
					if (y < 0.36) {
						c = vec3(0.3, 0.19, 0.12);
						vec2 pq = vec2(fract(s * 2.0), y / 0.36);
						if (pq.x > 0.1 && pq.x < 0.9 && pq.y > 0.2 && pq.y < 0.8) c *= 1.18;
						spec = 0.2;
					} else if (y < 0.41) {
						c = vec3(0.44, 0.3, 0.18);
					} else {
						c = c * 1.15;
						if (fract(s * 5.0) < 0.16) c = mix(c, vec3(0.86, 0.82, 0.68), 0.3);
						if (y > 0.94) c *= 0.7;
					}
				} else if (th == 1) {
					float row = floor(y * 6.0);
					c = c * (0.85 + 0.25 * hsh(vec2(floor(s * 0.7 + row * 0.37), row)));
					if (fract(y * 6.0) < 0.1) c *= 0.5;
				} else {
					if (y < 0.45) {
						c *= 0.75;
						if (abs(fract(s * 2.0) - 0.5) > 0.46) c *= 0.6;
					} else if (y < 0.49) {
						c = vec3(0.7, 0.54, 0.3);
						spec = 0.5;
						shin = 40.0;
					} else {
						c *= 1.05;
						if (abs(fract(s * 2.0) - 0.5) > 0.47) c *= 0.6;
						spec = 0.25;
						shin = 30.0;
					}
				}
			}
			// 墙脚压暗一点
			c *= mix(0.72, 1.0, smoothstep(0.0, 0.18, y));
		}
	} else {
		if (k == 0) {
			// 拼花地板：相邻格子的木条方向交错
			bool alt = mod(cell.x + cell.y, 2.0) > 0.5;
			vec2 q = alt ? f.yx : f;
			float row = floor(q.y * 3.0);
			c *= 0.94 + 0.1 * hsh(cell * 3.1 + row);
			c *= 0.95 + 0.08 * vn(vec2(q.x * 2.0, q.y * 30.0) + cell * 5.0);
			if (fract(q.y * 3.0) < 0.04) c *= 0.78;
			if (min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)) < 0.015) c *= 0.82;
			spec = 0.22;
			shin = 24.0;
		} else if (k == 1) {
			float row = floor(p.y * 4.0);
			float off = hsh(vec2(row, 3.0)) * 2.0;
			float pl = floor((p.x + off) / 1.6);
			c *= 0.86 + 0.24 * hsh(vec2(pl, row));
			c *= 0.94 + 0.1 * vn(vec2(p.x * 3.0, p.y * 40.0));
			if (fract(p.y * 4.0) < 0.07) c *= 0.55;
			if (fract((p.x + off) / 1.6) < 0.015) c *= 0.6;
			spec = 0.15;
		} else if (k == 2) {
			vec2 q = fract(p * 2.0) - 0.5;
			float dm = abs(abs(q.x) + abs(q.y) - 0.35);
			if (dm < 0.035) c = mix(c, vec3(0.72, 0.56, 0.3), 0.6);
			c *= 0.95 + 0.08 * vn(p * 30.0);
		} else if (k == 3) {
			float n = vn(p * 1.7) * 0.6 + vn(p * 5.0) * 0.4;
			c = mix(c * 0.8, c * 1.2, n);
			c *= 0.88 + 0.2 * vn(p * 40.0);
		} else if (k == 4) {
			c *= 0.9 + 0.1 * vn(p * 2.3) + 0.04 * vn(p * 9.0);
			spec = 0.35;
			shin = 60.0;
		} else if (k == 5) {
			c *= 0.92 + 0.1 * hsh(cell) + 0.06 * vn(p * 25.0);
			if (min(f.x, f.y) < 0.025) c *= 0.6;
		}
		if (cus.g > 0.5) {
			c = mix(c, vec3(0.72, 0.86, 0.94), 0.45);
			if (vn(p * 14.0) > 0.78) c = mix(c, vec3(1.0), 0.45);
			spec = 0.6;
			shin = 50.0;
		}
		// 靠墙的地方压暗（假的环境光遮蔽）
		float ao2 = 1.0;
		if (bit(m, 1)) ao2 *= mix(0.62, 1.0, smoothstep(0.0, 0.22, 1.0 - f.x));
		if (bit(m, 2)) ao2 *= mix(0.62, 1.0, smoothstep(0.0, 0.22, f.x));
		if (bit(m, 4)) ao2 *= mix(0.62, 1.0, smoothstep(0.0, 0.22, 1.0 - f.y));
		if (bit(m, 8)) ao2 *= mix(0.62, 1.0, smoothstep(0.0, 0.22, f.y));
		c *= ao2;
	}
	v_spec = spec;
	v_shin = shin;
	vec3 em;
	float nt;
	float pst;
	ALBEDO = finish(c, em, nt, pst);
	nite = nt;
	EMISSION = em;
	ROUGHNESS = 0.8;
}
"""

## 烟圈：一圈沿 3x3 边缘的烟管。网格里存的是单位路径点（VERTEX）和管子的截面方向（NORMAL），
## 着色器按 half_w 放大路径、按 thick 撑开管子；roll 让烟管表面像卷轴一样滚动。
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform float half_w = 1.5;
uniform float thick = 0.25;
uniform float roll = 0.0;
uniform float fade = 1.0;
uniform float warm = 0.0;
uniform float t = 0.0;
varying float ang;
varying float u;
float hs(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hs(i), hs(i + vec3(1, 0, 0)), f.x), mix(hs(i + vec3(0, 1, 0)), hs(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hs(i + vec3(0, 0, 1)), hs(i + vec3(1, 0, 1)), f.x), mix(hs(i + vec3(0, 1, 1)), hs(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	u = UV.x;
	ang = UV.y * 6.2832;
	float lump = 1.0 + 0.2 * sin(UV.x * 6.2832 * 7.0 + t * 1.1) * sin(UV.x * 6.2832 * 3.0 - t * 0.6);
	float th = thick * lump;
	VERTEX = vec3(VERTEX.x * half_w, th * 0.8, VERTEX.z * half_w) + NORMAL * th;
}
void fragment() {
	// 截面上的一点随 roll 转动：张开时顶上往外滚，合上时往里滚
	float a = ang + roll;
	float K = 8.0 + half_w * 14.0;
	vec3 q = vec3(u * K, cos(a) * 1.4, sin(a) * 1.4);
	vec3 q2 = q - vec3(K, 0.0, 0.0);
	float n = n3(q) * 0.6 + n3(q * 2.3 + vec3(t * 0.15)) * 0.4;
	float n2 = n3(q2) * 0.6 + n3(q2 * 2.3 + vec3(t * 0.15)) * 0.4;
	n = mix(n, n2, smoothstep(0.85, 1.0, u));  // 首尾接上，没有缝
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float lit = clamp(wn.y * 0.55 + 0.5, 0.0, 1.0);
	vec3 col = mix(vec3(0.48, 0.5, 0.58), vec3(0.97, 0.95, 0.9), lit);
	col *= 0.85 + 0.3 * n;
	// 朝里的一面被烟里的灯照暖
	float inner = clamp(-cos(ang), 0.0, 1.0);
	col = mix(col, vec3(1.0, 0.72, 0.42), inner * warm * 0.45);
	float rim = smoothstep(0.0, 0.55, abs(dot(NORMAL, VIEW)));
	ALBEDO = col;
	ALPHA = clamp(rim * (0.45 + 0.75 * n), 0.0, 1.0) * fade;
}
"""

var game
var board := Rect2(48, 76, 864, 470)
var t := 0.0

var cam: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var lamp: OmniLight3D  # 侦探烟斗的火光，只在烟里看得出
var smoke_lamp: OmniLight3D  # 烟里的暖光
var floor_mm: MultiMeshInstance3D
var wall_mm: MultiMeshInstance3D
var plinth: MeshInstance3D
var dyn: Node3D
var player: Node3D
var player_ring: MeshInstance3D
var ring_mat: StandardMaterial3D
var ember: MeshInstance3D
var _player_to := Vector3.ZERO
var _hop_from := Vector3.ZERO
var _hop_k := 1.0
var _past := false  # 正在搭的这个物件属于哪个时代

var _meshes := {}
var _mats := {}
var _shaders := {}
var _puff_tex: GradientTexture2D
var _pipe_puffs: Array = []
var _feet: Array = []  # [StandardMaterial3D, step, 亮度]
var _ghosts: Array = []  # StandardMaterial3D
var _flames: Array = []  # [Node3D, OmniLight3D or null]
var _glows: Array = []  # StandardMaterial3D
var _bait_puffs: Array = []  # [MeshInstance3D, Vector3]
var _fit_key := ""
var _people := {}  # 实体 id → [节点, 原位置]，烟雾旁边的人做反应用
var _figures: Array = []  # [节点, 相位]：人物的呼吸
var env: Environment
var _offsets := {}  # 实体 id → 同一格里多个人时的错开量，免得穿模
var _player_off := Vector3.ZERO
var _looks := {}
var hover: MeshInstance3D
var hover_mat: StandardMaterial3D
var _tile_mat: ShaderMaterial

## 烟雾窗口的动画：{c: 格子, p: 0..1 卷开的程度, open: 正在卷开还是卷回, roll: 烟管转过的角度}
## 最多两个：再吐一口烟时，旧的卷回、新的卷开
var _wins: Array = []
var _rings: Array = []  # [MeshInstance3D, ShaderMaterial]
## 窗口范围里两个时代的东西都搭好，烟管滚过去时换：[节点, 格子, 是不是过去]
var _swap: Array = []
var _last_level = null
## 门：[门扇的转轴, 格子, 是不是过去, 记录的键]。开门的进度存在 _door_state 里，重搭场景时不丢
var _doors: Array = []
var _door_state := {}  # 键 → [0..1 开到哪, 往哪边开]
var _door_level = null
var _last_cell := Vector2i(-99, -99)
var _came_from := Vector2i(-99, -99)
var _edit_light := false
## 两个时代各自是白天(0)还是黑夜(1)；截图工具可以强行指定来看效果
var era_night := Vector2(0, 1)
var force_night := Vector2(-1, -1)


func setup(g, board_rect: Rect2) -> void:
	game = g
	board = board_rect
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0b0908")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# 环境光在着色器里按时代算（见 SHADE_COMMON 的 finish），这里只留编辑器用的补光
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
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

	# 清晨的天光：从左上方的高窗照进来，影子软
	sun = DirectionalLight3D.new()
	sun.light_color = Color(0.96, 0.97, 1.0)
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-56, -38, 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.light_color = Color(0.66, 0.74, 0.88)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-40, 140, 0)
	add_child(fill)

	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.4)
	lamp.light_energy = 0.45
	lamp.omni_range = 1.8
	lamp.omni_attenuation = 1.4
	add_child(lamp)

	smoke_lamp = OmniLight3D.new()
	smoke_lamp.light_color = Color(1.0, 0.72, 0.42)
	smoke_lamp.light_energy = 1.2
	smoke_lamp.omni_range = 2.6
	smoke_lamp.omni_attenuation = 2.2
	smoke_lamp.visible = false
	add_child(smoke_lamp)

	_tile_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TILE_SHADER % SHADE_COMMON
	_tile_mat.shader = sh
	floor_mm = _new_mm(_box(Vector3(1, 0.1, 1), false))
	wall_mm = _new_mm(_box(Vector3(1, WALL_H, 1), false))
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

	var ring_mesh := _ring_mesh()
	var rsh := Shader.new()
	rsh.code = RING_SHADER
	for i in 2:
		var rm := ShaderMaterial.new()
		rm.shader = rsh
		var mi := _part(self, ring_mesh, rm, Vector3.ZERO)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.visible = false
		_rings.append([mi, rm])

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


## 当前烟雾窗口卷开了多少（0 = 合上，1 = 完全张开）。界面上的浓度点跟着它出现
func window_open() -> float:
	for w in _wins:
		if w.open:
			return _ease_open(w.p)
	return 0.0


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
	sun.directional_shadow_max_distance = dist + maxf(W, H)


# ---------------------------------------------------------------- 网格与材质

## 家具用圆角方块（模型的手工感）；太薄的板子、地面和墙用直角
func _box(size: Vector3, round := true) -> Mesh:
	var r := minf(minf(size.x, size.y), size.z)
	var bevel := clampf(r * 0.16, 0.0, 0.045)
	if not round or bevel < 0.008:
		var k := "b%s" % size
		if not _meshes.has(k):
			var m := BoxMesh.new()
			m.size = size
			_meshes[k] = m
		return _meshes[k]
	var k2 := "rb%s" % size
	if not _meshes.has(k2):
		_meshes[k2] = _rbox(size, bevel)
	return _meshes[k2]


## 圆角方块：每个面分 3x3，外圈那一条往里收成圆角
static func _rbox(size: Vector3, r: float) -> ArrayMesh:
	var h := size / 2.0
	var inner := h - Vector3.ONE * r
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for fc in faces:
		var n: Vector3 = fc[0]
		var a: Vector3 = fc[1]
		var b: Vector3 = fc[2]
		var ha := absf(a.dot(h))
		var hb := absf(b.dot(h))
		var ia := absf(a.dot(inner)) / ha
		var ib := absf(b.dot(inner)) / hb
		var ua := [-1.0, -ia, ia, 1.0]
		var ub := [-1.0, -ib, ib, 1.0]
		var base := verts.size()
		for i in 4:
			for j in 4:
				var q: Vector3 = (n + a * ua[i] + b * ub[j]) * h
				var cl := q.clamp(-inner, inner)
				var nn := (q - cl).normalized()
				verts.append(cl + nn * r)
				norms.append(nn)
		for i in 3:
			for j in 3:
				var v0 := base + i * 4 + j
				var v1 := v0 + 4
				var v2 := v0 + 5
				var v3 := v0 + 1
				for tri in [[v0, v1, v2], [v0, v2, v3]]:
					var p0: Vector3 = verts[tri[0]]
					var cr := (verts[tri[1]] - p0).cross(verts[tri[2]] - p0)
					if cr.dot(n) > 0:
						idx.append_array([tri[0], tri[2], tri[1]])
					else:
						idx.append_array([tri[0], tri[1], tri[2]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 烟圈的网格：圆角正方形路径（半宽 1）上的一根管子
static func _ring_mesh() -> ArrayMesh:
	var cr := 0.32
	var straight := 2.0 * (1.0 - cr)
	var arc := PI / 2.0 * cr
	var total := 4.0 * (straight + arc)
	var N := 128
	var M := 12
	var pts: Array = []
	var outs: Array = []
	for i in N + 1:
		var s := fposmod(total * i / N, total)
		var side := int(s / (straight + arc)) % 4
		var l := s - side * (straight + arc)
		var p2: Vector2
		var o2: Vector2
		if l < straight:
			p2 = Vector2(1.0, -1.0 + cr + l)
			o2 = Vector2(1, 0)
		else:
			var a := (l - straight) / cr
			o2 = Vector2(cos(a), sin(a))
			p2 = Vector2(1.0 - cr, 1.0 - cr) + o2 * cr
		# 四条边：把第一条边转 90° 的倍数
		var rot := side * PI / 2.0
		pts.append(p2.rotated(rot))
		outs.append(o2.rotated(rot))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in N + 1:
		var p2: Vector2 = pts[i]
		var o2: Vector2 = outs[i]
		for j in M + 1:
			var a := TAU * j / M
			var d := Vector3(o2.x * cos(a), sin(a), o2.y * cos(a))
			verts.append(Vector3(p2.x, 0, p2.y))
			norms.append(d)
			uvs.append(Vector2(float(i) / N, float(j) / M))
	for i in N:
		for j in M:
			var v0 := i * (M + 1) + j
			var v1 := v0 + M + 1
			var v2 := v1 + 1
			var v3 := v0 + 1
			# 用半宽 1、管粗 0.2 时的实际位置判断朝向，让三角形朝外
			for tri in [[v0, v1, v2], [v0, v2, v3]]:
				var q: Array = []
				for vi in tri:
					q.append(verts[vi] + norms[vi] * 0.2)
				var cr2: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
				var nn: Vector3 = norms[tri[0]] + norms[tri[1]] + norms[tri[2]]
				if cr2.dot(nn) > 0:
					idx.append_array([tri[0], tri[2], tri[1]])
				else:
					idx.append_array([tri[0], tri[1], tri[2]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


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


func _cap(r: float, hgt: float) -> CapsuleMesh:
	var k := "k%s,%s" % [r, hgt]
	if not _meshes.has(k):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = hgt
		m.radial_segments = 12
		m.rings = 4
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


func _shader(alpha: bool) -> Shader:
	if not _shaders.has(alpha):
		var s := Shader.new()
		s.code = PROP_SHADER % [
			"blend_mix, depth_draw_opaque, cull_back" if alpha else "cull_back",
			SHADE_COMMON,
			"ALPHA = albedo.a * tc.a;" if alpha else "",
		]
		_shaders[alpha] = s
	return _shaders[alpha]


## 物件材质：只管颜色和光泽，现在 / 过去的光由着色器按位置换
func _m(c: Color, rough := 0.8, metal := 0.0) -> ShaderMaterial:
	var k := "%s|%s|%s" % [c.to_html(), rough, metal]
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = _shader(c.a < 0.99)
		m.set_shader_parameter("albedo", c)
		# 粗糙度换成上漆的光泽：越光滑、越像金属，高光越亮越小
		var gloss := 1.0 - rough
		m.set_shader_parameter("spec_amt", 0.08 + gloss * 0.5 + metal * 0.6)
		m.set_shader_parameter("shin_amt", 8.0 + gloss * 50.0 + metal * 30.0)
		_mats[k] = m
	return _mats[k]


## 只在夜里亮着的灯（台灯灯泡、灯罩里面）
func _lamp_m(c: Color, glow: Color, energy := 3.0) -> ShaderMaterial:
	var k := "L%s|%s|%s" % [c.to_html(), glow.to_html(), energy]
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = _shader(false)
		m.set_shader_parameter("albedo", c)
		m.set_shader_parameter("lamp", glow)
		m.set_shader_parameter("lamp_e", energy)
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


# ---------------------------------------------------------------- 烟雾窗口

static func _ease_open(p: float) -> float:
	return 1.0 - pow(1.0 - clampf(p, 0.0, 1.0), 2.4)


static func _ease_close(p: float) -> float:
	var q := clampf(p, 0.0, 1.0)
	return q * q * (3.0 - 2.0 * q)


func _half(w: Dictionary) -> float:
	return WIN * (_ease_open(w.p) if w.open else _ease_close(w.p))


## 按游戏状态决定哪个窗口在卷开、哪个在卷回
func _sync_windows() -> void:
	if not is_same(game.L, _last_level):
		_last_level = game.L
		_wins.clear()
	var s: Dictionary = game.s
	var want = s.center if s.cloud and not game.reveal_all else null
	var keep := false
	for w in _wins:
		if w.open and want != null and w.c == want:
			keep = true
		elif w.open:
			w.open = false
	if want != null and not keep:
		_wins.append({"c": want, "p": 0.0, "open": true, "roll": 0.0})
	while _wins.size() > 2:
		_wins.pop_front()


## 这一格此刻显示的是不是过去：烟管滚过格子中心之后就换
func _past_shown(p: Vector2i) -> bool:
	if game.reveal_all:
		return true
	for w in _wins:
		var d := maxi(absi(p.x - w.c.x), absi(p.y - w.c.y))
		if d <= 1 and _half(w) > float(d) + 0.05:
			return true
	return false


func _in_zone(p: Vector2i) -> bool:
	for w in _wins:
		if maxi(absi(p.x - w.c.x), absi(p.y - w.c.y)) <= 1:
			return true
	return false


func _animate_windows(delta: float) -> void:
	var s: Dictionary = game.s
	var density := float(s.turns) / Game.SMOKE_TURNS if s.cloud else 0.4
	for w in _wins:
		var before := _half(w)
		if w.open:
			w.p = minf(1.0, w.p + delta / OPEN_TIME)
		else:
			w.p = maxf(0.0, w.p - delta / CLOSE_TIME)
		var hw := _half(w)
		var th := _thick(w, hw, density)
		# 不打滑地滚：边往外推多少，管子就转多少
		w.roll += (hw - before) / maxf(th, 0.05) + delta * 0.35
	for i in range(_wins.size() - 1, -1, -1):
		if not _wins[i].open and _wins[i].p <= 0.0:
			_wins.remove_at(i)
	var g := [Vector4.ZERO, Vector4.ZERO]
	for i in _rings.size():
		var mi: MeshInstance3D = _rings[i][0]
		var rm: ShaderMaterial = _rings[i][1]
		if i >= _wins.size():
			mi.visible = false
			continue
		var w: Dictionary = _wins[i]
		var hw := _half(w)
		var c := at(w.c)
		g[i] = Vector4(c.x, c.z, hw, 0)
		mi.visible = true
		mi.position = Vector3(c.x, 0.0, c.z)
		rm.set_shader_parameter("half_w", hw)
		rm.set_shader_parameter("thick", _thick(w, hw, density))
		rm.set_shader_parameter("roll", w.roll)
		rm.set_shader_parameter("t", t)
		rm.set_shader_parameter("warm", clampf(hw / WIN, 0.0, 1.0) * era_night.y)
		rm.set_shader_parameter("fade", clampf(hw * 3.0, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("smoke_a", g[0])
	RenderingServer.global_shader_parameter_set("smoke_b", g[1])
	RenderingServer.global_shader_parameter_set("smoke_all", 1.0 if game.reveal_all else 0.0)
	# 烟里的暖光跟着张开的窗口
	var lw = null
	for w in _wins:
		if lw == null or w.open:
			lw = w
	smoke_lamp.visible = lw != null
	if lw != null:
		smoke_lamp.position = at(lw.c, 1.2)
		smoke_lamp.light_energy = (0.22 + density * 0.2) * _half(lw) / WIN * era_night.y
	for sw in _swap:
		var nd: Node3D = sw[0]
		nd.visible = _past_shown(sw[1]) == sw[2]


## 烟管的粗细：越浓越粗；刚吐出来和快卷回去时细
func _thick(_w: Dictionary, hw: float, density: float) -> float:
	var full := 0.2 + 0.1 * density
	return minf(full, 0.05 + hw * 0.4)


# ---------------------------------------------------------------- 重搭场景

func refresh() -> void:
	fit()
	era_night = force_night if force_night.x >= 0.0 else era_light(game.L)
	RenderingServer.global_shader_parameter_set("era_night", era_night)
	_sync_windows()
	_build_tiles()
	for c in dyn.get_children():
		c.free()
	_feet.clear()
	_ghosts.clear()
	_flames.clear()
	_glows.clear()
	_bait_puffs.clear()
	_swap.clear()
	_figures.clear()
	_people.clear()
	_looks = game.onlookers()
	_spread_people()
	var all_past: bool = game.reveal_all
	_doors.clear()
	if not is_same(game.L, _door_level):
		_door_level = game.L
		_door_state.clear()
	var cell: Vector2i = game.s.pos
	if cell != _last_cell:
		_came_from = _last_cell
		_last_cell = cell
	# 后来的建造：现在挡路；过去那一格是一扇没锁的门、一个空门洞，或者什么都没有
	for lt in game.L.later:
		var look: String = lt.get("past", "door")
		if not all_past:
			_past = false
			var n: Node3D = null
			if lt in game.d.later_active:
				n = _later(lt)
			elif look != "nothing":
				n = _door(lt, look == "door", false)
			if n != null and _in_zone(lt.pos):
				_swap.append([n, lt.pos, false])
		if look != "nothing" and (all_past or _in_zone(lt.pos)):
			_past = true
			var pn := _door(lt, look == "door", false)
			if not all_past:
				_swap.append([pn, lt.pos, true])
	if not all_past:
		for e in game.present_ents():
			_past = false
			var node := _place(e)
			if _in_zone(e.pos):
				_swap.append([node, e.pos, false])
			elif _looks.has(e.id):
				_people[e.id] = [node, node.position]
	for e in game.past_ents():
		if not all_past and not _in_zone(e.pos):
			continue
		_past = true
		var node := _place(e)
		if not all_past:
			_swap.append([node, e.pos, true])
	_anchors()
	_routes()
	var s: Dictionary = game.s
	var to := at(s.pos) + _player_off
	if to != _player_to:
		_hop_from = player.position
		_player_to = to
		_hop_k = 0.0 if player.position.distance_to(to) < 1.5 else 1.0
		if _hop_k >= 1.0:
			player.position = to
	ember.visible = s.tobacco > 0
	_animate_windows(0.0)


## 时间点是夜里吗：19:00 以后、6:00 以前算夜里。没写时间就用 fallback
static func _is_night(label: String, fallback: bool) -> bool:
	var re := RegEx.create_from_string("(\\d{1,2})[:：](\\d{2})")
	var m := re.search(label)
	if m == null:
		return fallback
	var h := int(m.get_string(1))
	return h >= 19 or h < 6


## 两个时代的光：按关卡的两个时间点决定谁是白天、谁是黑夜。
## 两个时间都是白天或都是夜里时，烟里换成黄昏的光（0.5），窗口照样一眼看得出来
static func era_light(L: Dictionary) -> Vector2:
	var now := 1.0 if _is_night(String(L.get("present_label", "")), false) else 0.0
	var past := 1.0 if _is_night(String(L.get("past_label", "")), true) else 0.0
	if now == past:
		past = 0.5
	return Vector2(now, past)


## 正在搭的这个物件那个时代是不是夜里（夜里台灯才亮）
func _lit() -> bool:
	return (era_night.y if _past else era_night.x) > 0.75


func _place(e: Dictionary) -> Node3D:
	var node := _entity(e)
	node.position = at(e.pos) + _offsets.get(e.id, Vector3.ZERO)
	dyn.add_child(node)
	return node


## 编辑器里整张地图都要看得清：调亮环境光
func set_edit_light(on: bool) -> void:
	_edit_light = on
	env.ambient_light_energy = 0.6 if on else 0.0
	sun.shadow_enabled = not on


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


func _outdoor(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= game.W or p.y >= game.H:
		return true
	return not _wall(p) and String(game.L.map[p.y])[p.x] == ","


const _SIDES := [[Vector2i.RIGHT, 1], [Vector2i.LEFT, 2], [Vector2i.DOWN, 4], [Vector2i.UP, 8]]


func _build_tiles() -> void:
	var ti := clampi(int(game.L.get("style", 0)), 0, Art.THEMES.size() - 1)
	var th: Dictionary = Art.THEMES[ti]
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
		var wm := 0
		for sd in _SIDES:
			if _wall(p + sd[0]):
				wm += sd[1]
		_inst(fbuf, at(p, -0.05), _floor_color(kind),
			Color(FLOOR_KINDS.get(kind, 6), 1.0 if cold.has(p) else 0.0, 0, wm))
	var wbuf := PackedFloat32Array()
	for p in walls:
		var ext := 0
		var nb := 0
		for sd in _SIDES:
			var q: Vector2i = p + sd[0]
			if _wall(q):
				nb += sd[1]
			elif _outdoor(q):
				ext += sd[1]
		_inst(wbuf, at(p, WALL_H / 2.0), th.face, Color(6, ti, 0, ext + nb * 16))
	_fill(floor_mm, floors.size(), fbuf)
	_fill(wall_mm, walls.size(), wbuf)
	# 模型底座：深色胡桃木，边上一道黄铜线
	var key := "%dx%d %s" % [game.W, game.H, board]
	if plinth.get_meta("key", "") != key:
		plinth.set_meta("key", key)
		for c in plinth.get_children():
			c.free()
		plinth.mesh = _box(Vector3(game.W + 0.7, 0.36, game.H + 0.7), false)
		plinth.material_override = _m(Color("#3a2416"), 0.4)
		plinth.position = Vector3(game.W / 2.0, -0.28, game.H / 2.0)
		var trim := _part(plinth, _box(Vector3(game.W + 0.74, 0.03, game.H + 0.74), false), _m(Color("#b08a50"), 0.25, 0.8), Vector3(0, 0.1, 0))
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
			return Color("#76492c")
		"planks":
			return Color("#94704a")
		"carpet":
			return Color("#6a1e28")
		"garden":
			return Color("#5e7c48")
		"snow":
			return Color("#e4eaee")
		"platform":
			return Color("#7c7a76")
	return Color("#666666")


# ---------------------------------------------------------------- 后来的建造

func _later(lt: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.position = at(lt.pos)
	dyn.add_child(n)
	# 墙在左右两边：缺口是东西向的，木板、门沿 x 方向；否则沿 z 方向
	var along_x: bool = _wall(lt.pos + Vector2i.LEFT) or _wall(lt.pos + Vector2i.RIGHT)
	var ry := 0.0 if along_x else PI / 2.0
	if lt.kind == "planks" and lt.get("past", "door") == "door":
		# 木板钉在原来那扇门上
		_door_parts(n, ry, lt, true, true)
	_body_from(n)
	match lt.kind:
		"brick":
			# 新砌的砖：比原来的墙颜色新、砖缝白
			var row_h := WALL_H / 6.0
			for i in 6:
				var off := 0.0 if i % 2 == 0 else 0.25
				for k in 3:
					var x := -0.5 + off + 0.25 + k * 0.5
					var w := 0.46
					if x - w / 2.0 < -0.5:
						w -= (-0.5 - (x - w / 2.0))
						x = -0.5 + w / 2.0
					if x + w / 2.0 > 0.5:
						w -= (x + w / 2.0 - 0.5)
						x = 0.5 - w / 2.0
					if w < 0.05:
						continue
					var bc := Color("#9a4a34").lerp(Color("#7a3424"), Art.h(i, k))
					_part(n, _box(Vector3(w - 0.02, row_h - 0.02, 0.9)), _m(bc, 0.85), Vector3(x, row_h * (i + 0.5), 0).rotated(Vector3.UP, ry), Vector3(0, ry, 0))
			_part(n, _box(Vector3(0.97, WALL_H - 0.05, 0.8), false), _m(Color("#bcb2a2")), Vector3(0, (WALL_H - 0.05) / 2.0, 0), Vector3(0, ry, 0))
		"planks":
			for i in 3:
				var y := 0.16 + i * 0.22
				var tilt := 0.18 if i % 2 == 0 else -0.14
				_part(n, _box(Vector3(1.06, 0.13, 0.06)), _m(Color("#a07a4a").lerp(Color("#8a6236"), Art.h(i, 2))), Vector3(0, y, 0.08).rotated(Vector3.UP, ry), Vector3(0, ry, tilt))
				for sx in [-0.42, 0.42]:
					_part(n, _sph(0.018), _m(Color("#c8ccd4"), 0.2, 0.9), (Vector3(sx, y + sx * tilt * 0.9, 0.12)).rotated(Vector3.UP, ry))
			for sx in [-0.44, 0.44]:
				_part(n, _box(Vector3(0.08, WALL_H, 0.08)), _m(Color("#5a4026")), Vector3(sx, WALL_H / 2.0, 0).rotated(Vector3.UP, ry))
		"lock":
			_door_parts(n, ry, lt, true, true)
	if lt.kind in ["brick", "planks"]:
		_use_model(n, "later_" + lt.kind, false)
	return n


## 门洞和门：[leaf] 要不要门扇，[locked] 锁着（或钉死）的门不会开，门锁的门上挂一把锁
func _door(lt: Dictionary, leaf: bool, locked: bool) -> Node3D:
	var n := Node3D.new()
	n.position = at(lt.pos)
	dyn.add_child(n)
	var along_x: bool = _wall(lt.pos + Vector2i.LEFT) or _wall(lt.pos + Vector2i.RIGHT)
	_door_parts(n, 0.0 if along_x else PI / 2.0, lt, leaf, locked)
	return n


func _door_parts(n: Node3D, ry: float, lt: Dictionary, leaf: bool, locked: bool) -> void:
	var fr := Node3D.new()
	fr.rotation.y = ry
	n.add_child(fr)
	var wood := _m(Color("#4a2e1c"), 0.6)
	var hgt := WALL_H - 0.06
	# 门框：两根门柱、一根门楣
	for sx in [-0.46, 0.46]:
		_part(fr, _box(Vector3(0.08, WALL_H, 0.26)), wood, Vector3(sx, WALL_H / 2.0, 0))
	_part(fr, _box(Vector3(1.0, 0.07, 0.26)), wood, Vector3(0, WALL_H - 0.035, 0))
	_part(fr, _box(Vector3(0.84, 0.012, 0.24), false), _m(Color("#3a2416"), 0.7), Vector3(0, 0.006, 0))
	if not leaf:
		return
	# 门扇挂在左边的门柱上，开门就是转这个轴
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.42, 0, 0)
	fr.add_child(hinge)
	var w := 0.84
	var face := Color("#6e4428")
	_part(hinge, _box(Vector3(w, hgt - 0.01, 0.06)), _m(face, 0.55), Vector3(w / 2.0, hgt / 2.0 + 0.005, 0))
	# 四块门板，两面都有
	for i in 2:
		for j in 2:
			for side in [-1.0, 1.0]:
				_part(hinge, _box(Vector3(0.3, hgt * 0.34, 0.014)), _m(face.darkened(0.2), 0.55), Vector3(w / 2.0 - 0.19 + i * 0.38, hgt * (0.26 + 0.46 * j), side * 0.036))
	for side in [-1.0, 1.0]:
		_part(hinge, _sph(0.03), _m(Art.GOLD, 0.25, 0.8), Vector3(w - 0.09, hgt * 0.47, side * 0.05))
	if locked and lt.kind == "lock":
		# 新挂的锁：铁搭扣横跨门缝，黄铜锁头要在远处也看得见
		var iron := _m(Color("#3a3c42"), 0.4, 0.7)
		var brass := _m(Color("#c8a050"), 0.25, 0.85)
		var steel := _m(Color("#c4c8d0"), 0.2, 0.9)
		for side in [-1.0, 1.0]:
			_part(hinge, _box(Vector3(0.24, 0.06, 0.02)), iron, Vector3(w - 0.02, hgt * 0.5, side * 0.045))
			_part(hinge, _box(Vector3(0.17, 0.19, 0.07)), brass, Vector3(w - 0.04, hgt * 0.5 - 0.1, side * 0.085))
			_part(hinge, _torus(0.045, 0.072), steel, Vector3(w - 0.04, hgt * 0.5 + 0.01, side * 0.085), Vector3(PI / 2, 0, 0))
	if locked:
		return
	var key := "%d,%d,%s" % [lt.pos.x, lt.pos.y, "p" if _past else "n"]
	if not _door_state.has(key):
		_door_state[key] = [0.0, -1.0]
	_doors.append([hinge, lt.pos, _past, key, ry])
	hinge.rotation.y = _door_state[key][1] * DOOR_OPEN * _ease_door(_door_state[key][0])


static func _ease_door(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


## 门开着：侦探站在门里，或者这个时代有人、有东西在门口
func _door_wanted(cell: Vector2i, past: bool) -> bool:
	if game.s.pos == cell:
		return true
	var list: Array = game.past_ents() if past else game.present_ents()
	for e in list:
		if e.pos == cell:
			return true
	return false


func _animate_doors(delta: float) -> void:
	for dr in _doors:
		var st: Array = _door_state[dr[3]]
		var want := _door_wanted(dr[1], dr[2])
		if want and st[0] <= 0.0:
			# 往侦探走的方向推开
			var mv: Vector2i = dr[1] - _came_from if game.s.pos == dr[1] and absi(dr[1].x - _came_from.x) + absi(dr[1].y - _came_from.y) == 1 else Vector2i.ZERO
			var lz := Vector3(mv.x, 0, mv.y).rotated(Vector3.UP, -dr[4]).z
			st[1] = 1.0 if lz < -0.1 else -1.0
		if want:
			st[0] = minf(1.0, st[0] + delta / DOOR_OPEN_TIME)
		else:
			st[0] = maxf(0.0, st[0] - delta / DOOR_CLOSE_TIME)
		dr[0].rotation.y = st[1] * DOOR_OPEN * _ease_door(st[0])


# ---------------------------------------------------------------- 物件

func _entity(e: Dictionary) -> Node3D:
	var n := Node3D.new()
	var kind: String = e.get("kind", "")
	if kind == "source" or e.get("model", "") == "tin":
		_tin(n, false, kind == "source")
	elif kind in ["inspector", "npc"]:
		var body := Node3D.new()
		n.add_child(body)
		var style := Art.style_for(e)
		_person(body, style, false)
		_use_model(body, "person_" + style, false)
		body.scale = Vector3.ONE * PERSON_SCALE
		_figures.append([body, Art.h(e.pos.x, e.pos.y) * TAU])
	else:
		var done: bool = (kind in ["cache", "clue"] and game.s.clues.has(e.get("clue", ""))) \
			or (kind == "container" and e.get("taken", false))
		var sprite := Art.sprite_for(e)
		_thing(n, sprite, e, done)
		if sprite != "":
			_use_model(n, sprite, done and sprite in DIM_WHEN_DONE)
	return n


## 烟丝罐：所有烟丝来源共用。黄铜罐、红标签、盖子上一圈压纹
func _tin(n: Node3D, ghost: bool, glow: bool) -> void:
	var body := Color("#b88c4a")
	var mb: Material
	var ml: Material
	var mr: Material
	if ghost:
		var gm := StandardMaterial3D.new()
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(0.92, 0.82, 0.6, 0.35)
		gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mb = gm
		ml = gm
		mr = gm
		_ghosts.append(gm)
	else:
		mb = _m(body, 0.35, 0.7)
		ml = _m(body.lightened(0.2), 0.25, 0.8)
		mr = _m(Color("#9a2a22"), 0.6)
	var parts := [
		_part(n, _cyl(0.15, 0.15, 0.26), mb, Vector3(0, 0.13, 0)),
		_part(n, _cyl(0.153, 0.153, 0.1), mr, Vector3(0, 0.12, 0)),
		_part(n, _cyl(0.16, 0.16, 0.035), ml, Vector3(0, 0.275, 0)),
		_part(n, _cyl(0.1, 0.1, 0.01), mr, Vector3(0, 0.296, 0)),
	]
	_body(n)
	_use_model(n, "tin", false, mb if ghost else null)
	if ghost:
		for p in n.get_children():
			if p is GeometryInstance3D:
				p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for q in p.find_children("*", "GeometryInstance3D", true, false):
				q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if glow:
		var gm := _flat_mat(Color(0.95, 0.78, 0.45, 0.5))
		var g := _part(n, _plane(0.95, 0.95), gm, Vector3(0, 0.012, 0))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glows.append(gm)


## 人物：上了漆的木头小人，站在一块圆底座上（桌游棋子的样子）
func _person(n: Node3D, style: String, detective: bool) -> void:
	var st: Dictionary = Art.PEOPLE.get(style, Art.PEOPLE.butler)
	var coat := _m(st.coat, 0.7)
	var coat_d := _m(Color(st.coat).darkened(0.18), 0.7)
	var skin := _m(st.skin, 0.6)
	var hatc := _m(st.hatc, 0.6)
	# 底座
	_part(n, _cyl(0.17, 0.18, 0.035, 24), _m(Color("#1c1816"), 0.3), Vector3(0, 0.0175, 0))
	_part(n, _cyl(0.181, 0.181, 0.008, 24), _m(Art.GOLD if detective else Color("#4a4038"), 0.3, 0.8 if detective else 0.2), Vector3(0, 0.03, 0))
	# 身体：下摆、肩、两只手臂、头
	_part(n, _cyl(0.11, 0.17, 0.4), coat, Vector3(0, 0.235, 0))
	_part(n, _sph(0.135), coat, Vector3(0, 0.43, 0), Vector3.ZERO, Vector3(1.12, 0.6, 0.88))
	for sx in [-1.0, 1.0]:
		_part(n, _cap(0.042, 0.28), coat_d, Vector3(sx * 0.135, 0.33, 0.01), Vector3(0, 0, sx * 0.16))
		_part(n, _sph(0.032), skin, Vector3(sx * 0.155, 0.2, 0.02))
	_part(n, _cyl(0.04, 0.045, 0.05), skin, Vector3(0, 0.5, 0))
	_part(n, _sph(0.095), skin, Vector3(0, 0.565, 0.0))
	match st.hat:
		"fedora":
			_part(n, _cyl(0.18, 0.18, 0.016), hatc, Vector3(0, 0.625, 0))
			_part(n, _cyl(0.085, 0.1, 0.09), hatc, Vector3(0, 0.672, 0))
			_part(n, _cyl(0.102, 0.102, 0.022), _m(Color("#5a2a22")), Vector3(0, 0.64, 0))
		"cap":
			_part(n, _cyl(0.11, 0.105, 0.07), hatc, Vector3(0, 0.645, 0))
			_part(n, _box(Vector3(0.15, 0.015, 0.09), false), hatc, Vector3(0, 0.615, 0.11))
			_part(n, _box(Vector3(0.04, 0.03, 0.012), false), _m(Art.GOLD, 0.25, 0.8), Vector3(0, 0.65, 0.11))
		"hair":
			_part(n, _sph(0.1), hatc, Vector3(0, 0.585, -0.015), Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
		"bonnet":
			_part(n, _sph(0.115), hatc, Vector3(0, 0.59, -0.02), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
			_part(n, _torus(0.085, 0.11), _m(Color("#efe8da")), Vector3(0, 0.61, 0.03), Vector3(1.2, 0, 0))
		"chef":
			_part(n, _cyl(0.095, 0.09, 0.14), hatc, Vector3(0, 0.68, 0))
			_part(n, _sph(0.115), hatc, Vector3(0, 0.77, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		"top":
			_part(n, _cyl(0.165, 0.165, 0.016), hatc, Vector3(0, 0.625, 0))
			_part(n, _cyl(0.085, 0.085, 0.19), hatc, Vector3(0, 0.72, 0))
			_part(n, _cyl(0.087, 0.087, 0.025), _m(Color("#3a3a44")), Vector3(0, 0.645, 0))
		"pillbox":
			_part(n, _cyl(0.08, 0.08, 0.06), hatc, Vector3(0, 0.65, 0))
			_part(n, _cyl(0.082, 0.082, 0.01), _m(Art.GOLD, 0.3, 0.8), Vector3(0, 0.67, 0))
	match st.get("detail", ""):
		"collar":
			_part(n, _box(Vector3(0.1, 0.06, 0.03), false), _m(Color("#efe8da")), Vector3(0, 0.44, 0.115))
			_part(n, _box(Vector3(0.05, 0.025, 0.015), false), _m(Color("#1a1a1a")), Vector3(0, 0.465, 0.13))
		"apron":
			_part(n, _box(Vector3(0.18, 0.26, 0.02), false), _m(Color("#efe8da")), Vector3(0, 0.22, 0.15), Vector3(-0.15, 0, 0))
			_part(n, _box(Vector3(0.12, 0.08, 0.02), false), _m(Color("#efe8da")), Vector3(0, 0.39, 0.12))
		"belt":
			_part(n, _cyl(0.158, 0.158, 0.03), _m(Color("#2a1a10")), Vector3(0, 0.22, 0))
	if style == "inspector":
		_part(n, _box(Vector3(0.04, 0.05, 0.02), false), _m(Art.GOLD, 0.25, 0.8), Vector3(0.06, 0.36, 0.13))
	_body(n)
	if detective:
		# 风衣：腰带、翻领；烟斗
		_part(n, _cyl(0.142, 0.142, 0.03), _m(Color("#6a4a2a")), Vector3(0, 0.3, 0))
		for sx in [-1.0, 1.0]:
			_part(n, _box(Vector3(0.05, 0.12, 0.02), false), coat_d, Vector3(sx * 0.045, 0.43, 0.12), Vector3(-0.3, 0, sx * 0.4))
		_part(n, _cyl(0.011, 0.011, 0.1), _m(Color("#2a1a10"), 0.4), Vector3(0.05, 0.53, 0.11), Vector3(0, 0, PI / 2 - 0.3))
		_part(n, _cyl(0.028, 0.022, 0.05), _m(Color("#5a321c"), 0.4), Vector3(0.1, 0.55, 0.11))
		ember = _part(n, _sph(0.018), _glow(Color(1.0, 0.5, 0.15), 4.0), Vector3(0.1, 0.576, 0.11))
func _thing(n: Node3D, sprite: String, e: Dictionary, done: bool) -> void:
	match sprite:
		"desk":
			_part(n, _box(Vector3(0.84, 0.05, 0.6)), _m(Color("#6a4226"), 0.5), Vector3(0, 0.4, 0))
			for sx in [-0.37, 0.37]:
				_part(n, _box(Vector3(0.08, 0.38, 0.52)), _m(Color("#5a3820")), Vector3(sx, 0.19, 0))
			_part(n, _box(Vector3(0.22, 0.01, 0.28)), _m(Color("#efe6d0")), Vector3(-0.16, 0.43, 0.04), Vector3(0, 0.15, 0))
			_body(n)  # 台灯只在夜里亮，始终用程序画的
			_part(n, _cyl(0.05, 0.06, 0.02), _m(Color("#2a2a2a")), Vector3(0.22, 0.435, -0.12))
			_part(n, _cyl(0.008, 0.008, 0.18), _m(Color("#2a2a2a")), Vector3(0.22, 0.52, -0.12))
			_part(n, _cyl(0.04, 0.09, 0.07), _m(Color("#2f6a42"), 0.25), Vector3(0.22, 0.62, -0.1))
			_part(n, _sph(0.03), _lamp_m(Color("#d8d0b8"), Color(1.0, 0.82, 0.5), 5.0), Vector3(0.22, 0.585, -0.1))
			if _lit():
				_lamp_light(n, Vector3(0.22, 0.55, -0.1), 1.6, 2.6)
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
			_part(n, _box(Vector3(0.56, 0.025, 0.56)), _m(Color("#0a0806")), Vector3(0, 0.008, 0))
			_body(n)
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
			_body(n)  # 转盘、把手、打开的门是状态，始终用程序画的
			if done:
				_part(n, _box(Vector3(0.46, 0.46, 0.02)), _m(Color("#14161a")), Vector3(0, 0.3, 0.281))
				_part(n, _box(Vector3(0.46, 0.46, 0.04)), _m(Color("#4a525e"), 0.35, 0.7), Vector3(0.43, 0.3, 0.45), Vector3(0, -1.3, 0))
			else:
				_part(n, _cyl(0.09, 0.09, 0.03), _m(Color("#2a2e36"), 0.3, 0.8), Vector3(0, 0.33, 0.29), Vector3(PI / 2, 0, 0))
				_part(n, _box(Vector3(0.012, 0.07, 0.01)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0, 0.36, 0.307), Vector3(0, 0, t * 0.3))
				_part(n, _box(Vector3(0.1, 0.03, 0.03)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0.18, 0.3, 0.29))
		"rack":
			_part(n, _box(Vector3(0.8, 0.1, 0.24)), _m(Color("#5a4026")), Vector3(0, 0.05, 0))
			_part(n, _box(Vector3(0.8, 0.06, 0.06)), _m(Color("#5a4026")), Vector3(0, 0.42, -0.06))
			_body(n)  # 冰锥的根数是线索，始终用程序画的
			var picks := 7 if e.era == "past" else 6
			for k in picks:
				_part(n, _cyl(0.012, 0.012, 0.36), _m(Color("#cfe6f2"), 0.2, 0.8), Vector3(-0.33 + k * 0.11, 0.26, 0))
		"candle":
			_part(n, _cyl(0.16, 0.16, 0.04), _m(Color("#a07a30"), 0.3, 0.8), Vector3(0, 0.02, 0))
			_part(n, _cyl(0.055, 0.06, 0.26), _m(Color("#efe6d0"), 0.6), Vector3(0, 0.17, 0))
			_body(n)
			if e.get("lit", false) and _past:
				var f := _part(n, _sph(0.04), _glow(Color(1.0, 0.6, 0.24), 5.0), Vector3(0, 0.34, 0), Vector3.ZERO, Vector3(0.7, 1.4, 0.7))
				_flames.append([f, _lamp_light(n, Vector3(0, 0.45, 0), 1.5, 2.4)])
		"wax":
			_part(n, _cyl(0.14, 0.16, 0.03), _m(Color("#d8cfb8")), Vector3(0, 0.015, 0))
			_part(n, _cyl(0.008, 0.008, 0.04), _m(Color("#1a1a1a")), Vector3(0, 0.04, 0))
		"logs":
			for k in 5:
				var row := 0 if k < 3 else 1
				var col := k if k < 3 else k - 3
				_part(n, _cyl(0.1, 0.1, 0.72, 10), _m(Color("#7a5232")),
					Vector3(-0.2 + col * 0.2 + row * 0.1, 0.1 + row * 0.17, 0), Vector3(0, 0, PI / 2))
		"embers":
			_part(n, _cyl(0.32, 0.36, 0.04), _m(Color("#3a3634"), 0.95), Vector3(0, 0.02, 0))
			_body(n)
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
			_body(n)
			if e.era == "past":
				_part(n, _box(Vector3(0.34, 0.025, 0.05)), _m(Color("#c8ccd4"), 0.2, 0.9), Vector3(0, 0.26, 0.04), Vector3(0, 0.4, 0))
		"puddle":
			var wm := _m(Color(0.42, 0.56, 0.66, 0.55), 0.02, 0.2)
			_part(n, _cyl(0.34, 0.34, 0.006, 20), wm, Vector3(-0.05, 0.004, 0.03), Vector3.ZERO, Vector3(1, 1, 0.8))
			_part(n, _cyl(0.16, 0.16, 0.006, 16), wm, Vector3(0.2, 0.004, -0.14))
		"ice":
			_part(n, _box(Vector3(0.62, 0.62, 0.62)), _m(Color(0.66, 0.85, 0.93, 0.78), 0.05), Vector3(0, 0.31, 0))
			_part(n, _box(Vector3(0.4, 0.4, 0.4)), _m(Color(1, 1, 1, 0.25), 0.05), Vector3(0, 0.31, 0))
		"ashtray":
			_part(n, _cyl(0.18, 0.2, 0.06), _m(Color("#6a6a72"), 0.3, 0.6), Vector3(0, 0.03, 0))
			_part(n, _cyl(0.13, 0.13, 0.01), _m(Color("#3a3a40")), Vector3(0, 0.062, 0))
			_body(n)
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


# ---------------------------------------------------------------- Dify 工作流做的模型

## 模型放在 res://assets/generated/<名字>/<名字>.tscn（dify-godot-assets 的 deliver_to_godot 交付的样子）。
## 名字就是物件的画法名（desk、bookshelf……）、person_<人物造型>（person_detective……）或 tin。
## 有模型就用模型换掉程序拼的"身体"，没有就保持原样。状态部件（台灯、转盘、冰锥、火苗……）始终程序画。
## 模型按程序拼的那一份的大小摆放：底部贴地、居中、塞进同样的占地范围，所以关卡不用改。
const MODEL_DIR := "res://assets/generated"
## 东西已经拿走 / 查过时变暗的物件
const DIM_WHEN_DONE := ["book", "paper", "glove"]
## 个别模型朝向不对时在这里转（弧度，绕竖轴）。没写的：正面朝 +Z（朝镜头），长条的东西自动转到和程序拼的同一个方向
const MODEL_YAW := {"safe": -PI / 2, "wardrobe": -PI / 2, "chair": -PI / 2, "bed": -PI / 2, "barrel": -PI / 2, "cart": -PI / 2, "horse": 0.0, "snowman": -PI / 2, "toolbox": -PI / 2, "person_inspector": -PI / 2, "person_butler": -PI / 2, "book": PI / 2}
## 平放在地上的薄东西：模型太厚时压扁，不按厚度缩小
const FLAT_MODELS := ["paper", "glove", "book", "wax", "cache", "embers"]
## 模型可以比程序拼的高出多少
const MODEL_TALL := 2.0

const ModelTints := preload("res://scripts/model_tints.gd")
var _scenes := {}  # 名字 -> PackedScene 或 null
var _model_mats := {}  # 原材质 -> 换成两个时代光的材质


## 标记：到这里为止的部件是"身体"，有模型时被换掉；后面加的是状态部件
func _body(n: Node3D) -> void:
	n.set_meta("body", n.get_child_count())


## 标记：从这里开始才是"身体"（前面的部件，比如木板下面那扇门，不换）
func _body_from(n: Node3D) -> void:
	n.set_meta("body_from", n.get_child_count())


func model_scene(key: String) -> PackedScene:
	if not _scenes.has(key):
		var path := "%s/%s/%s.tscn" % [MODEL_DIR, key, key]
		_scenes[key] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[key]


func _use_model(n: Node3D, key: String, dim: bool, ghost: Material = null) -> void:
	var ps := model_scene(key)
	if ps == null:
		return
	var cut: int = n.get_meta("body", n.get_child_count())
	var start: int = n.get_meta("body_from", 0)
	var box := AABB()
	var first := true
	var old: Array = []
	for i in range(start, cut):
		var c := n.get_child(i)
		old.append(c)
		if c is MeshInstance3D and c.mesh != null:
			var b: AABB = c.transform * (c as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	if first:
		return
	for c in old:
		n.remove_child(c)
		c.queue_free()
	var m: Node3D = ps.instantiate()
	if MODEL_YAW.has(key):
		m.rotation.y = MODEL_YAW[key]
	else:
		# 长条的东西（书桌、书架）：模型的长边和程序拼的不在同一个方向就转 90°
		var mb0 := _model_box(m)
		var want := box.size.x / box.size.z
		var got := mb0.size.x / mb0.size.z
		if (want > 1.25 and got < 0.8) or (want < 0.8 and got > 1.25):
			m.rotation.y = PI / 2
	var mb := _model_box(m)
	if mb.size.x <= 0.0 or mb.size.z <= 0.0 or mb.size.y <= 0.0:
		m.free()
		return
	# 最长的一边和程序拼的一样长；不出这一格，也不比程序拼的高太多
	var sc := maxf(box.size.x, box.size.z) / maxf(mb.size.x, mb.size.z)
	sc = minf(sc, minf(0.98 / mb.size.x, 0.98 / mb.size.z))
	var sy := minf(sc, box.size.y * MODEL_TALL / mb.size.y)
	if key not in FLAT_MODELS:
		sc = sy
	var holder := Node3D.new()
	holder.add_child(m)
	# 平放的小东西（纸、手套……）模型常常做得太厚：只压扁，不缩小
	m.scale = Vector3(sc, sy, sc)
	var mid := mb.get_center() * Vector3(sc, sy, sc)
	m.position = Vector3(box.get_center().x - mid.x, box.position.y - mb.position.y * sy, box.get_center().z - mid.z)
	_retint(m, key, dim, ghost)
	n.add_child(holder)
	n.move_child(holder, start)


## 模型（含旋转）在它自己父节点坐标里的包围盒，缩放前
func _model_box(m: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var rot := Transform3D(Basis(Vector3.UP, m.rotation.y), Vector3.ZERO)
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != m and p != null:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = rot * xf * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## 模型原来的材质换成游戏的着色：保留颜色贴图，光照按两个时代换（和程序拼的物件一样）
func _retint(m: Node3D, key: String, dim: bool, ghost: Material) -> void:
	var tint: Color = ModelTints.TINTS.get(key, Color.WHITE)
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		if ghost != null:
			mi.material_override = ghost
			continue
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			var k := [src, dim, tint]
			if not _model_mats.has(k):
				var col := Color.WHITE
				var tex: Texture2D = null
				var rough := 0.8
				var metal := 0.0
				if src is BaseMaterial3D:
					col = src.albedo_color
					tex = src.albedo_texture
					rough = src.roughness
					metal = src.metallic
				# 校色：平均色拉回美术文档的配色（tools/model_tints.gd 算的）
				col = Color(col.r * tint.r, col.g * tint.g, col.b * tint.b, col.a)
				if dim:
					col = col.darkened(0.5)
				# 上漆的哑光模型：Tripo 的材质常常太亮太滑，压一压
				rough = maxf(rough, 0.6)
				metal = minf(metal, 0.4)
				var sm: ShaderMaterial = _m(col, rough, metal).duplicate()
				sm.set_shader_parameter("tex", tex)
				_model_mats[k] = sm
			mi.set_surface_override_material(i, _model_mats[k])


## 夜里的灯光（只在过去那一份物件上加）
func _lamp_light(n: Node3D, pos: Vector3, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.38)
	l.omni_range = rng
	l.light_energy = energy
	l.omni_attenuation = 1.3
	l.position = pos
	n.add_child(l)
	return l


# ---------------------------------------------------------------- 烟丝锚点与路线

## 另一个时代的烟丝源画成虚影；同一格两个时代都有东西时先显示现在的
func _anchors() -> void:
	for e in game.anchors():
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
		# 虚影在"另一个时代"露出：过去的罐子，现在看得到虚影；烟管滚过去以后换成实物
		_swap.append([n, e.pos, e.era != "past"])


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
				var m := _flat_mat(Color(0.95, 0.76, 0.45, 0.6))
				var sgn := 1.0 if (steps % 2 == 0) == (fk < 0.5) else -1.0
				var p := at(a, 0.015).lerp(at(b, 0.015), fk) + side * sgn
				var fm := _part(dyn, _plane(0.12, 0.2), m, p, Vector3(0, atan2(dir.x, dir.z), 0))
				fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_feet.append([m, steps, 1.0 if inside else 0.8])
		if not inside and not game.in_window(path[path.size() - 1]):
			continue
		var end := at(path[path.size() - 1], 0.02)
		for r in [PI / 4, -PI / 4]:
			var x := _part(dyn, _box(Vector3(0.42, 0.01, 0.05), false), _glow(Art.GOLD, 1.2), end, Vector3(0, r, 0))
			x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- 侦探

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	ring_mat = _flat_mat(Color(0.95, 0.78, 0.45, 0.5))
	player_ring = _part(player, _plane(0.9, 0.9), ring_mat, Vector3(0, 0.012, 0))
	player_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * PERSON_SCALE
	player.add_child(body)
	_person(body, "detective", true)
	_use_model(body, "person_detective", false)
	for i in 5:
		var m := _puff_mat()
		var mi := _part(player, _quad(0.12), m, Vector3.ZERO)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pipe_puffs.append([mi, m, i / 5.0])


# ---------------------------------------------------------------- 动画

func _process(delta: float) -> void:
	if game == null or not visible:
		return
	t += delta
	# 侦探像棋子一样跳一格
	if _hop_k < 1.0:
		_hop_k = minf(1.0, _hop_k + delta / 0.16)
		var k := _hop_k * _hop_k * (3.0 - 2.0 * _hop_k)
		player.position = _hop_from.lerp(_player_to, k) + Vector3(0, sin(_hop_k * PI) * 0.12, 0)
	else:
		player.position = _player_to
	lamp.position = player.position + Vector3(0.14, 0.95, 0.2)
	lamp.light_energy = 0.32 + 0.06 * sin(t * 7.0) * sin(t * 3.1)
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	ring_mat.albedo_color.a = 0.18 + 0.22 * pulse
	var s: Dictionary = game.s
	for pp in _pipe_puffs:
		var k := fposmod(t * 0.6 + pp[2], 1.0)
		var on: bool = s.tobacco > 0
		pp[0].visible = on
		pp[0].position = Vector3(0.14 + sin(t * 2.0 + pp[2] * 9.0) * 0.04 * k, 0.8 + k * 0.6, 0.15)
		pp[0].scale = Vector3.ONE * (0.6 + k * 2.2)
		pp[1].albedo_color.a = 0.45 * (1.0 - k)
	for g in _ghosts:
		g.albedo_color.a = 0.26 + 0.16 * (0.5 + 0.5 * sin(t * 2.0))
	for g in _glows:
		g.albedo_color.a = 0.22 + 0.33 * (0.5 + 0.5 * sin(t * 2.5))
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
	# 人物轻轻呼吸
	for fg in _figures:
		var b: Node3D = fg[0]
		b.scale = Vector3(PERSON_SCALE, PERSON_SCALE * (1.0 + 0.012 * sin(t * 2.2 + fg[1])), PERSON_SCALE)
	# 烟雾旁边的人：看呆了的轻轻踮脚，看见过去自己的吓得发抖
	for id in _people:
		var nd: Node3D = _people[id][0]
		var base: Vector3 = _people[id][1]
		if _looks.get(id, "") == "self":
			nd.position = base + Vector3(sin(t * 58.0) * 0.035, 0, cos(t * 47.0) * 0.02)
		else:
			nd.position = base + Vector3(0, absf(sin(t * 5.0 + base.x)) * 0.05, 0)
	hover.rotation.y = t * 1.5
	_animate_doors(delta)
	_animate_windows(delta)
