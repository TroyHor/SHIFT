#!/usr/bin/env bash
# 把 deliver_to_godot 交付的一个模型收进游戏：压缩、写 tscn、留一份来源记录（去掉会过期的签名链接）。
#   tools/models/add.sh <交付文件夹> <游戏里的名字>
# 交付文件夹里要有 <交付名>.glb 和 _delivery.json（就是 res://assets/generated/<交付名>/）。
# 游戏里的名字是物件的画法名（desk、bookshelf……）、person_<人物造型> 或 tin，见 docs/models.md。
set -euo pipefail
src="$1"; key="$2"
here="$(cd "$(dirname "$0")" && pwd)"
dst="$here/../../assets/generated/$key"
glb="$(ls "$src"/*.glb | head -n1)"
[ -d "$here/node_modules" ] || (cd "$here" && npm install --silent)
mkdir -p "$dst"
node "$here/optimize.mjs" "$glb" "$dst/$key.glb" "${MAX_TRIS:-6000}" "${TEX:-512}"
cat > "$dst/$key.tscn" <<TSCN
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/generated/$key/$key.glb" id="1_model"]

[node name="$key" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_model")]
TSCN
if [ -f "$src/_delivery.json" ]; then
	python3 -I - "$src/_delivery.json" "$dst/_delivery.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
keep = {k: d[k] for k in ("job_id", "run_id", "brief", "asset_type", "delivered_at", "final_stage", "model_size_m") if k in d}
keep["note"] = "Dify「Godot 素材生成器」交付，经 tools/models/optimize.mjs 压缩"
json.dump(keep, open(sys.argv[2], "w"), ensure_ascii=False, indent=2)
PY
fi
ls -la "$dst"
