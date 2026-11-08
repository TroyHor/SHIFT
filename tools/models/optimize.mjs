// 把 Dify 工作流（Tripo）交付的模型压成游戏能用的大小。
//
//   cd tools/models && npm install
//   node optimize.mjs <输入.glb> <输出.glb> [三角面上限=6000] [贴图边长=512]
//
// Tripo 的模型约 3 万三角面、三张 4K 贴图（颜色、法线、金属粗糙度），一个就有 10–17 MB。
// 游戏用自己的着色器（按位置换两个时代的光、上漆的高光），只用得到颜色贴图，
// 而且物件在屏幕上只有几十像素，所以：
//   - 去掉法线贴图和金属粗糙度贴图
//   - 颜色贴图缩到 512 并存成 JPEG
//   - 网格简化到三角面上限以内
// 结果一般在 100–300 KB，网页版也放得下。
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, weld, simplify, textureCompress } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const [, , input, output, maxTrisArg, texArg] = process.argv;
if (!input || !output) {
	console.error('用法: node optimize.mjs <输入.glb> <输出.glb> [三角面上限] [贴图边长]');
	process.exit(1);
}
const maxTris = Number(maxTrisArg || 6000);
const texSize = Number(texArg || 512);

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();

const tris = () => {
	let n = 0;
	for (const mesh of root.listMeshes()) {
		for (const p of mesh.listPrimitives()) {
			const idx = p.getIndices();
			n += (idx ? idx.getCount() : p.getAttribute('POSITION').getCount()) / 3;
		}
	}
	return n;
};

for (const m of root.listMaterials()) {
	m.setNormalTexture(null);
	m.setMetallicRoughnessTexture(null);
	m.setOcclusionTexture(null);
	m.setEmissiveTexture(null);
}

const before = tris();
await doc.transform(dedup(), weld());
await MeshoptSimplifier.ready;
let ratio = Math.min(1, maxTris / Math.max(1, tris()));
for (let i = 0; i < 4 && tris() > maxTris; i++) {
	await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.01 * (i + 1) }));
	ratio *= 0.8;
}
await doc.transform(
	prune(),
	textureCompress({ encoder: sharp, targetFormat: 'jpeg', resize: [texSize, texSize], quality: 85 }),
);
await io.write(output, doc);
console.log(`${input}: ${Math.round(before)} → ${Math.round(tris())} 三角面`);
