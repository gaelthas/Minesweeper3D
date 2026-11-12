// 方块模型来自 Godot 版同一份 Blender 产物（assets/build_cube.py）。
// 按 GLB 结构取出顶点即可，不引 GLTFLoader。
// 好处是两个版本的模型完全一致：六个面平直、十二条棱是直线、八个角是球面。

import * as THREE from 'three';
import { loadAsset } from '@assets';

const CHUNK_JSON = 0x4e4f534a;
const CHUNK_BIN = 0x004e4942;

const COMPONENTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
const ARRAY_TYPES = { 5121: Uint8Array, 5123: Uint16Array, 5125: Uint32Array, 5126: Float32Array };

function readAccessor(json, bin, index) {
  const accessor = json.accessors[index];
  const view = json.bufferViews[accessor.bufferView];
  const Type = ARRAY_TYPES[accessor.componentType];
  const size = COMPONENTS[accessor.type];
  const offset = (view.byteOffset || 0) + (accessor.byteOffset || 0);
  return new Type(bin.buffer, bin.byteOffset + offset, accessor.count * size);
}

/** 解析 GLB，返回一份可复用的 BufferGeometry */
export async function loadCubeGeometry() {
  const bytes = await loadAsset('models/cube.glb');
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const totalLength = header.getUint32(8, true);

  let json = null;
  let bin = null;
  let offset = 12;
  while (offset < totalLength) {
    const length = header.getUint32(offset, true);
    const type = header.getUint32(offset + 4, true);
    const chunk = bytes.subarray(offset + 8, offset + 8 + length);
    if (type === CHUNK_JSON) json = JSON.parse(new TextDecoder().decode(chunk));
    else if (type === CHUNK_BIN) bin = chunk;
    offset += 8 + length;
  }
  if (!json || !bin) throw new Error('GLB 解析失败：缺少 JSON 或 BIN 块');

  const primitive = json.meshes[0].primitives[0];
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(readAccessor(json, bin, primitive.attributes.POSITION), 3));
  if (primitive.attributes.NORMAL !== undefined) {
    geo.setAttribute('normal', new THREE.BufferAttribute(readAccessor(json, bin, primitive.attributes.NORMAL), 3));
  }
  if (primitive.indices !== undefined) {
    geo.setIndex(new THREE.BufferAttribute(readAccessor(json, bin, primitive.indices), 1));
  }
  geo.computeBoundingSphere();
  return geo;
}
