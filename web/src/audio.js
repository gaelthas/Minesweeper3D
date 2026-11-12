// 音效：六段 CC0 素材以 base64 内联，单文件里也能出声。
// 浏览器要求用户手势后才能播放，所以解码和 AudioContext 的启动都推迟到第一次交互。

import revealUrl from '../../prototypes/minecube/assets/sfx/reveal.mp3?inline';
import floodUrl from '../../prototypes/minecube/assets/sfx/flood.mp3?inline';
import flagUrl from '../../prototypes/minecube/assets/sfx/flag.mp3?inline';
import uiUrl from '../../prototypes/minecube/assets/sfx/ui_click.mp3?inline';
import boomUrl from '../../prototypes/minecube/assets/sfx/boom.mp3?inline';
import winUrl from '../../prototypes/minecube/assets/sfx/win.mp3?inline';

const SOURCES = {
  reveal: revealUrl,
  flood: floodUrl,
  flag: flagUrl,
  ui: uiUrl,
  boom: boomUrl,
  win: winUrl,
};

export class Sfx {
  constructor(volume = 70, muted = false) {
    this.volume = volume;
    this.muted = muted;
    this.ctx = null;
    this.gain = null;
    this.buffers = {};
    this.ready = false;
    this._decoding = null;
  }

  setVolume(v) {
    this.volume = v;
    this._applyGain();
  }

  setMuted(m) {
    this.muted = m;
    this._applyGain();
  }

  _applyGain() {
    if (!this.gain) return;
    const v = this.muted ? 0 : Math.max(0, Math.min(1, this.volume / 100));
    this.gain.gain.value = v * v; // 感知上更接近线性
  }

  /** 第一次用户手势时调用 */
  async unlock() {
    if (!this.ctx) {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      this.ctx = new Ctx();
      this.gain = this.ctx.createGain();
      this.gain.connect(this.ctx.destination);
      this._applyGain();
    }
    if (this.ctx.state === 'suspended') await this.ctx.resume();
    if (this.ready || this._decoding) return this._decoding;

    this._decoding = (async () => {
      const entries = Object.entries(SOURCES);
      await Promise.all(
        entries.map(async ([name, url]) => {
          try {
            const res = await fetch(url);
            const data = await res.arrayBuffer();
            this.buffers[name] = await this.ctx.decodeAudioData(data);
          } catch {
            // 单个音效解码失败不该拖垮整局
          }
        })
      );
      this.ready = true;
    })();
    return this._decoding;
  }

  play(name) {
    if (!this.ctx || !this.buffers[name]) return;
    const src = this.ctx.createBufferSource();
    src.buffer = this.buffers[name];
    src.connect(this.gain);
    src.start();
  }
}
