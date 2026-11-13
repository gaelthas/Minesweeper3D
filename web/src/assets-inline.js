// 单文件构建以 data URI 内联；开发模式通过 URL 加载资源。
// mapp 构建会通过 vite alias 换成 assets-sdk.js，那边走 sdk.assets.readBytes。

import glbUrl from '../../prototypes/minecube/assets/cube_rounded.glb?url';
import mineUrl from '../../prototypes/minecube/assets/mine.glb?url';
import revealUrl from '../../prototypes/minecube/assets/sfx/reveal.mp3?url';
import floodUrl from '../../prototypes/minecube/assets/sfx/flood.mp3?url';
import flagUrl from '../../prototypes/minecube/assets/sfx/flag.mp3?url';
import uiUrl from '../../prototypes/minecube/assets/sfx/ui_click.mp3?url';
import boomUrl from '../../prototypes/minecube/assets/sfx/boom.mp3?url';
import winUrl from '../../prototypes/minecube/assets/sfx/win.mp3?url';

const INLINE = {
  'models/cube.glb': glbUrl,
  'models/mine.glb': mineUrl,
  'sfx/reveal.mp3': revealUrl,
  'sfx/flood.mp3': floodUrl,
  'sfx/flag.mp3': flagUrl,
  'sfx/ui_click.mp3': uiUrl,
  'sfx/boom.mp3': boomUrl,
  'sfx/win.mp3': winUrl,
};

export const ASSET_PATHS = Object.keys(INLINE);

function dataUriToBytes(uri) {
  const binary = atob(uri.slice(uri.indexOf(',') + 1));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export async function loadAsset(path) {
  const uri = INLINE[path];
  if (!uri) throw new Error(`未知资源：${path}`);
  if (uri.startsWith('data:') && /;base64$/i.test(uri.slice(0, uri.indexOf(',')))) {
    return dataUriToBytes(uri);
  }

  // 普通 URL 与非 base64 的 data URI 都交给 fetch 解码
  const res = await fetch(uri);
  if (!res.ok) throw new Error(`资源加载失败：${path}（HTTP ${res.status}）`);
  return new Uint8Array(await res.arrayBuffer());
}

export function initSdk() {}
