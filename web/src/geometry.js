import * as THREE from 'three';

// 削角立方体：八个顶点各被一块球面切掉，十二条棱保持直边。
// 用「沿方向求最大半径」的方式生成——形状是凸的，所以球面参数化不会自交。
// cut 是沿棱从顶点切掉的长度（边长按 1 计），与 Godot 版 Blender 脚本里的 0.30 一致。

const CORNERS = [];
for (const sx of [-1, 1]) {
  for (const sy of [-1, 1]) {
    for (const sz of [-1, 1]) CORNERS.push([sx, sy, sz]);
  }
}

/** 点是否在削角立方体内：六个平面内、八个切角球外 */
function isInside(x, y, z, cut) {
  const half = 0.5;
  if (Math.abs(x) > half || Math.abs(y) > half || Math.abs(z) > half) return false;
  for (const [sx, sy, sz] of CORNERS) {
    const dx = x - sx * half;
    const dy = y - sy * half;
    const dz = z - sz * half;
    if (dx * dx + dy * dy + dz * dz < cut * cut) return false;
  }
  return true;
}

/** 沿单位方向求边界距离。形状是凸的，二分比解析求根稳。 */
function radiusAlong(dx, dy, dz, cut) {
  const half = 0.5;
  let hi = half / Math.max(Math.abs(dx), Math.abs(dy), Math.abs(dz));
  let lo = 0;
  for (let i = 0; i < 26; i++) {
    const mid = (lo + hi) * 0.5;
    if (isInside(dx * mid, dy * mid, dz * mid, cut)) lo = mid;
    else hi = mid;
  }
  return lo;
}

/**
 * 削角立方体：六个面是平的，十二条棱是直的，八个角被球面切掉。
 *
 * 做法是球面参数化——对每个方向求"从中心出发能走多远"。形状是凸的，
 * 所以按方向采样不会自交。着色交给 flatShading：平面区每个三角形的
 * 几何法线都指向同一轴，看起来是平的；切削区靠密集三角形近似球面。
 */
export function makeCubeGeometry(cut = 0.3, detail = 6) {
  const src = new THREE.IcosahedronGeometry(1, detail);
  const pos = src.getAttribute('position');
  const out = new Float32Array(pos.count * 3);

  const v = new THREE.Vector3();
  for (let i = 0; i < pos.count; i++) {
    v.fromBufferAttribute(pos, i).normalize();
    const t = radiusAlong(v.x, v.y, v.z, cut);
    out[i * 3] = v.x * t;
    out[i * 3 + 1] = v.y * t;
    out[i * 3 + 2] = v.z * t;
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(out, 3));
  src.dispose();
  geo.computeBoundingSphere();
  return geo;
}

// 数字配色：深色方块上要够亮
const NUMBER_COLORS = [
  'transparent',
  '#7FB0FF', // 1
  '#7FE3A1', // 2
  '#FF8E8E', // 3
  '#C9A6FF', // 4
  '#FFC178', // 5
  '#7FE0E0', // 6
  '#E8EDF7', // 7
  '#B9C2D4', // 8
  '#9AA3B5', // 9
];

function canvasTexture(size, draw) {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const ctx = c.getContext('2d');
  draw(ctx, size);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

/** 数字贴图：透明底上的粗体数字，1..9 */
export function makeNumberTexture(n) {
  return canvasTexture(256, (ctx, s) => {
    ctx.clearRect(0, 0, s, s);
    ctx.fillStyle = NUMBER_COLORS[n] || '#E8EDF7';
    ctx.font = `700 ${Math.round(s * 0.72)}px "Helvetica Neue", Helvetica, Arial, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(n), s / 2, s * 0.54);
  });
}

/** 旗：粗杆 + 小三角旗面，缩到 0.34 单位还能认出来 */
export function makeFlagTexture() {
  return canvasTexture(256, (ctx, s) => {
    ctx.clearRect(0, 0, s, s);
    const ink = '#2A2118';
    ctx.fillStyle = ink;
    ctx.fillRect(s * 0.27, s * 0.1, s * 0.1 * 1.4, s * 0.8);
    ctx.beginPath();
    ctx.moveTo(s * 0.41, s * 0.13);
    ctx.lineTo(s * 0.82, s * 0.3);
    ctx.lineTo(s * 0.41, s * 0.47);
    ctx.closePath();
    ctx.fill();
  });
}

/** 问号 */
export function makeQuestionTexture() {
  return canvasTexture(256, (ctx, s) => {
    ctx.clearRect(0, 0, s, s);
    ctx.fillStyle = '#2E3541';
    ctx.font = `700 ${Math.round(s * 0.66)}px "Helvetica Neue", Helvetica, Arial, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('?', s / 2, s * 0.54);
  });
}
