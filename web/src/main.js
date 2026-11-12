import './style.css';
import { Board, REVEALED, FLAGGED, QUESTION, seededRng } from './logic.js';
import { World, OPEN_VIEW_PITCH } from './scene.js';
import { Sfx } from './audio.js';
import { createUi, formatTime } from './ui.js';

const VERSION = __APP_VERSION__;
const STORE_KEY = 'minecube3d.settings';

const MIN_SIDE = 3;
const MAX_SIDE = 11;
const DRAG_THRESHOLD = 4;
const CHORD_SLOP = 14;
const ACTIONS = ['none', 'reveal', 'flag', 'chord', 'pan'];

const defaults = {
  side: 5,
  mines: 38,
  volume: 70,
  muted: false,
  showFps: false,
  spacing: 100,
  mouseMap: ['reveal', 'pan', 'flag'],
};

function loadSettings() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (!raw) return { ...defaults };
    const saved = JSON.parse(raw);
    return {
      ...defaults,
      ...saved,
      mouseMap: Array.isArray(saved.mouseMap) && saved.mouseMap.length === 3
        ? saved.mouseMap.map((a) => (ACTIONS.includes(a) ? a : 'none'))
        : [...defaults.mouseMap],
    };
  } catch {
    return { ...defaults };
  }
}

const settings = loadSettings();
const sfx = new Sfx(settings.volume, settings.muted);

const canvas = document.getElementById('view');
const world = new World(canvas);

const state = {
  board: null,
  elapsed: 0,
  timing: false,
  paused: false,
  started: false,
};

const ui = createUi({
  onRestart: () => newGame(settings.side, settings.mines),
  onOpenBoard: () => {
    sfx.play('ui');
    pause();
    ui.openBoard(settings.side, settings.mines);
  },
  onOpenOptions: () => {
    sfx.play('ui');
    pause();
    ui.openOptions({ ...settings, version: VERSION });
  },
  onApplyBoard: (side, mines) => {
    sfx.play('ui');
    settings.side = side;
    settings.mines = mines;
    save();
    newGame(side, mines);
  },
  onSpacing: (pct) => {
    settings.spacing = pct;
    world.relayout(pct / 100);
    ui.setSpacing(pct);
    save();
  },
  onOptions: (patch) => {
    if (patch.volume !== undefined) {
      settings.volume = patch.volume;
      sfx.setVolume(patch.volume);
      ui.syncVolume(patch.volume);
    }
    if (patch.muted !== undefined) {
      settings.muted = patch.muted;
      sfx.setMuted(patch.muted);
      ui.syncMute(patch.muted);
      updateHint();
    }
    if (patch.showFps !== undefined) {
      settings.showFps = patch.showFps;
      ui.el.showFps.setAttribute('aria-pressed', String(patch.showFps));
    }
    if (patch.mapSlot !== undefined) {
      settings.mouseMap[patch.mapSlot] = patch.mapAction;
      updateHint();
    }
    save();
  },
});

function save() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(settings));
  } catch {
    /* 隐私模式下写不进去，不影响本局 */
  }
}

/* ---------------- 提示行按当前映射生成 ---------------- */

const ACTION_TEXT = {
  reveal: '揭示',
  flag: '插旗',
  chord: '和弦',
  pan: '平移',
};

function updateHint() {
  const names = ['左键', '中键', '右键'];
  const parts = [];
  settings.mouseMap.forEach((a, i) => {
    if (a === 'none' || !ACTION_TEXT[a]) return;
    parts.push(`${names[i]} ${ACTION_TEXT[a]}`);
  });
  const tail = settings.muted ? '左右键同按和弦 · 滚轮缩放 · R 重开 · M 静音（已静音）' : '左右键同按和弦 · 滚轮缩放 · R 重开 · M 静音';
  ui.setHint(`${parts.join(' · ')} · ${tail}`);
}

/* ---------------- 开局 ---------------- */

// ?seed=123 固定局面，方便复现与自动测试
const seedParam = new URLSearchParams(location.search).get('seed');
const rng = seedParam === null ? Math.random : seededRng(Number(seedParam) || 1);

function newGame(side, mines) {
  state.board = new Board(side, mines, rng);
  state.elapsed = 0;
  state.timing = false;
  state.paused = false;
  state.started = false;

  world.frame(side);
  world.build(state.board, settings.spacing / 100);
  world.applyCamera();
  ui.hideResult();
  ui.setTime(0);
  ui.setStats(state.board.mineTotal, 0, 0, state.board.total - state.board.mineTotal);
  updateHint();
}

function pause() {
  if (state.timing) {
    state.paused = true;
    state.timing = false;
  }
}

function resume() {
  if (state.paused && state.board && !state.board.gameOver && state.board.generated) {
    state.paused = false;
    state.timing = true;
  }
}

function anyOverlayOpen() {
  return ui.isBoardOpen() || ui.isOptionsOpen() || ui.isResultOpen();
}

/* ---------------- 动作 ---------------- */

function hitTarget(px, py) {
  const hit = world.pick(px, py);
  if (!hit) return null;
  return hit;
}

function doReveal(px, py) {
  const board = state.board;
  if (board.gameOver) return;
  const hit = hitTarget(px, py);
  if (!hit) return;
  const st = board.states[hit.index];
  if (st === REVEALED || st === FLAGGED) return;

  if (!board.generated) {
    board.placeMines(hit.index);
    state.elapsed = 0;
    state.timing = true;
    state.started = true;
  }

  const res = board.reveal(hit.index);
  world.refreshArea(res.opened);
  updateStats();

  if (res.boom) {
    finish(false);
  } else {
    if (res.opened.length >= 3) sfx.play('flood');
    else if (res.opened.length > 0) sfx.play('reveal');
    if (board.won) finish(true);
  }
}

function doFlag(px, py) {
  const board = state.board;
  if (board.gameOver) return;
  const hit = hitTarget(px, py);
  if (!hit) return;
  if (board.states[hit.index] === REVEALED) return;
  const prev = board.states[hit.index];
  board.cycleMark(hit.index);
  world.refresh(hit.index);
  updateStats();
  if (prev !== FLAGGED && prev !== QUESTION) sfx.play('flag');
  else sfx.play('ui');
}

function doChord(px, py, forcedFace) {
  const board = state.board;
  if (board.gameOver) return;
  const hit = hitTarget(px, py);
  if (!hit) return;
  const face = forcedFace !== undefined ? forcedFace : hit.face;
  const res = board.chordFace(hit.index, face);
  if (!res.opened.length && !res.boom) return;
  world.refreshArea(res.opened);
  updateStats();
  if (res.boom) finish(false);
  else {
    sfx.play('chord' in sfx.buffers ? 'chord' : 'flood');
    if (board.won) finish(true);
  }
}

function finish(won) {
  state.timing = false;
  const board = state.board;
  if (!won) world.markMines();
  ui.setTime(state.elapsed);
  if (won) sfx.play('win');
  else sfx.play('boom');
  ui.showResult(won, state.elapsed, board.side, board.mineTotal);
  ui.setStats(board.mineTotal, board.flagCount, board.revealedCount, board.total - board.mineTotal);
}

function updateStats() {
  const b = state.board;
  ui.setStats(b.mineTotal, b.flagCount, b.revealedCount, b.total - b.mineTotal);
}

/* ---------------- 输入 ---------------- */

const down = new Set();
let pressPos = { x: 0, y: 0 };
let dragging = false;
let chordArmed = false;
let actionDone = false;
let lastPointer = { x: 0, y: 0 };

const isClickAction = (action) => action === 'reveal' || action === 'flag' || action === 'chord';
const panningHeld = () => [...down].some((b) => settings.mouseMap[b] === 'pan');

canvas.addEventListener('contextmenu', (e) => e.preventDefault());

// 用 mousedown/mouseup 而不是 pointer 事件：右键在部分环境下不派发 pointerdown，
// 但 mousedown 一定会到。拖动仍然走 pointermove。
canvas.addEventListener('mousedown', (e) => {
  if (anyOverlayOpen()) return;
  sfx.unlock();
  const slot = e.button; // 0 左 / 1 中 / 2 右
  if (slot > 2) return;

  if (down.size === 0) {
    pressPos = { x: e.clientX, y: e.clientY };
    dragging = false;
    chordArmed = false;
    actionDone = false;
  }
  down.add(slot);
  lastPointer = { x: e.clientX, y: e.clientY };

  if (down.has(0) && down.has(2) && isClickAction(settings.mouseMap[0]) && isClickAction(settings.mouseMap[2])) {
    chordArmed = true;
    if (Math.hypot(e.clientX - pressPos.x, e.clientY - pressPos.y) <= CHORD_SLOP) dragging = false;
  }
});

window.addEventListener('mousemove', (e) => {
  if (anyOverlayOpen() || down.size === 0) return;
  const dx = e.clientX - lastPointer.x;
  const dy = e.clientY - lastPointer.y;
  lastPointer = { x: e.clientX, y: e.clientY };

  // 和弦手势期间不转相机，否则手一抖和弦就没了
  if (chordArmed) return;

  if (!dragging && Math.hypot(e.clientX - pressPos.x, e.clientY - pressPos.y) > DRAG_THRESHOLD) {
    dragging = true;
  }
  if (!dragging) return;

  if (panningHeld()) world.pan(dx, dy);
  else world.orbit(dx, dy);
});

window.addEventListener('mouseup', (e) => {
  const slot = e.button;
  if (slot > 2) return;
  if (!down.has(slot)) return;
  down.delete(slot);

  if (!anyOverlayOpen() && !actionDone && !dragging) {
    const action = settings.mouseMap[slot];
    if (action !== 'none' && action !== 'pan') {
      if (chordArmed || action === 'chord') {
        doChord(e.clientX, e.clientY);
        actionDone = true;
      } else if (action === 'reveal') {
        doReveal(e.clientX, e.clientY);
        actionDone = true;
      } else if (action === 'flag') {
        doFlag(e.clientX, e.clientY);
        actionDone = true;
      }
    }
  }

  if (down.size === 0) {
    chordArmed = false;
    actionDone = false;
    dragging = false;
  }
});

canvas.addEventListener(
  'wheel',
  (e) => {
    if (anyOverlayOpen()) return;
    e.preventDefault();
    world.zoom(e.deltaY > 0 ? 0.55 : -0.55);
  },
  { passive: false }
);

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    closeTopOverlay();
    return;
  }
  if (anyOverlayOpen()) return;
  if (e.key === 'r' || e.key === 'R') newGame(settings.side, settings.mines);
  else if (e.key === 'm' || e.key === 'M') {
    settings.muted = !settings.muted;
    sfx.setMuted(settings.muted);
    ui.syncMute(settings.muted);
    save();
    updateHint();
  }
});

function closeTopOverlay() {
  if (ui.isResultOpen()) {
    ui.hideResult();
    return;
  }
  if (ui.isOptionsOpen()) {
    ui.closeOptions();
    resume();
    return;
  }
  if (ui.isBoardOpen()) {
    ui.closeBoard();
    resume();
  }
}

window.addEventListener('resize', () => world.resize());

/* ---------------- 循环 ---------------- */

let last = performance.now();
let fpsAcc = 0;
let fpsFrames = 0;

function loop(now) {
  const dt = Math.min((now - last) / 1000, 0.1);
  last = now;

  if (state.timing && !anyOverlayOpen()) {
    state.elapsed += dt;
    ui.setTime(state.elapsed);
  }

  if (settings.showFps) {
    fpsAcc += dt;
    fpsFrames++;
    if (fpsAcc >= 0.5) {
      ui.setFps(Math.round(fpsFrames / fpsAcc));
      fpsAcc = 0;
      fpsFrames = 0;
    }
  } else if (ui.el.fps.textContent) {
    ui.setFps(-1);
  }

  world.render();
  requestAnimationFrame(loop);
}

world.resize();
newGame(settings.side, settings.mines);
ui.setSpacing(settings.spacing);
ui.syncVolume(settings.volume);
ui.syncMute(settings.muted);
requestAnimationFrame(loop);

// 供控制台调试
window.minecube = { world, state, settings, ui };
