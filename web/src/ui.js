import { recommendedMines } from './logic.js';

const $ = (id) => document.getElementById(id);

// 取值顺序与 logic / main 里的动作名一致
export const ACTION_KEYS = ['none', 'reveal', 'flag', 'chord', 'pan'];

export function formatTime(sec) {
  const t = Math.max(0, Math.floor(sec));
  const m = String(Math.floor(t / 60)).padStart(2, '0');
  const s = String(t % 60).padStart(2, '0');
  return `${m}:${s}`;
}

export function createUi(handlers, t) {
  let resultData = null;
  let fpsValue = -1;
  const el = {
    lang: $('lang'),
    stats: $('stats'),
    time: $('time'),
    fps: $('fps'),
    hint: $('hint'),
    status: $('status'),
    peelValue: $('peel-value'),
    peelHide: $('peel-hide'),
    peelShow: $('peel-show'),
    spacing: $('spacing'),
    spacingValue: $('spacing-value'),
    boardPanel: $('board-panel'),
    side: $('side'),
    sideValue: $('side-value'),
    mines: $('mines'),
    minesValue: $('mines-value'),
    boardHint: $('board-hint'),
    optionsPanel: $('options-panel'),
    volume: $('volume'),
    volumeValue: $('volume-value'),
    mute: $('mute'),
    showFps: $('show-fps'),
    dimOthersOnChord: $('dim-others-on-chord'),
    mapLeft: $('map-left'),
    mapMiddle: $('map-middle'),
    mapRight: $('map-right'),
    result: $('result'),
    resultTitle: $('result-title'),
    resultTime: $('result-time'),
    resultDetail: $('result-detail'),
    version: $('version'),
  };

  // 鼠标映射下拉
  for (const sel of [el.mapLeft, el.mapMiddle, el.mapRight]) {
    for (const key of ACTION_KEYS) {
      const opt = document.createElement('option');
      opt.value = key;
      opt.dataset.text = key;
      opt.textContent = t(key);
      sel.append(opt);
    }
  }

  $('btn-restart').addEventListener('click', () => handlers.onRestart());
  $('btn-board').addEventListener('click', () => handlers.onOpenBoard());
  $('btn-options').addEventListener('click', () => handlers.onOpenOptions());
  $('board-cancel').addEventListener('click', () => closeBoard());
  $('board-start').addEventListener('click', () => {
    const side = Number(el.side.value);
    const mines = Number(el.mines.value);
    closeBoard();
    handlers.onApplyBoard(side, mines);
  });
  $('options-close').addEventListener('click', () => closeOptions());
  $('result-close').addEventListener('click', () => hideResult());
  $('result-again').addEventListener('click', () => {
    hideResult();
    handlers.onRestart();
  });

  el.lang.addEventListener('change', () => handlers.onOptions({ lang: el.lang.value }));
  el.peelHide.addEventListener('click', () => handlers.onPeel(1));
  el.peelShow.addEventListener('click', () => handlers.onPeel(-1));

  el.spacing.addEventListener('input', () => {
    handlers.onSpacing(Number(el.spacing.value));
  });

  el.volume.addEventListener('input', () => {
    handlers.onOptions({ volume: Number(el.volume.value) });
  });
  el.mute.addEventListener('click', () => {
    handlers.onOptions({ muted: el.mute.getAttribute('aria-pressed') !== 'true' });
  });
  el.dimOthersOnChord.addEventListener('click', () => {
    handlers.onOptions({ dimOthersOnChord: el.dimOthersOnChord.getAttribute('aria-pressed') !== 'true' });
  });
  el.showFps.addEventListener('click', () => {
    handlers.onOptions({ showFps: el.showFps.getAttribute('aria-pressed') !== 'true' });
  });

  const bindMap = (sel, slot) =>
    sel.addEventListener('change', () => handlers.onOptions({ mapSlot: slot, mapAction: sel.value }));
  bindMap(el.mapLeft, 0);
  bindMap(el.mapMiddle, 1);
  bindMap(el.mapRight, 2);

  // 阶数变化时按 30% 推荐密度重算雷数
  el.side.addEventListener('input', () => {
    const side = Number(el.side.value);
    const total = side ** 3;
    const mines = recommendedMines(side);
    el.mines.max = String(Math.max(1, total - 1));
    el.mines.value = String(mines);
    syncBoardHint();
  });
  el.mines.addEventListener('input', syncBoardHint);

  function syncBoardHint() {
    const side = Number(el.side.value);
    const mines = Number(el.mines.value);
    const total = side ** 3;
    const density = ((mines / total) * 100).toFixed(1);
    const rec = recommendedMines(side);
    el.sideValue.value = String(side);
    el.minesValue.value = String(mines);
    el.boardHint.textContent = t('boardHint', { side, total, density, rec });
  }

  function closeBoard() {
    el.boardPanel.hidden = true;
  }
  function closeOptions() {
    el.optionsPanel.hidden = true;
  }
  function hideResult() {
    el.result.hidden = true;
  }

  function renderResult() {
    if (!resultData) return;
    const { won, sec, side, mines } = resultData;
    el.resultTitle.textContent = t(won ? 'resultWon' : 'resultLost');
    el.resultTime.textContent = formatTime(sec);
    el.resultDetail.textContent = t('resultDetail', { side, mines });
  }

  return {
    el,
    refreshText({ lang, version }) {
      el.lang.value = lang;
      el.version.textContent = t('version', { version });
      el.fps.textContent = fpsValue < 0 ? '' : t('fpsValue', { fps: fpsValue });
      syncBoardHint(); // 用面板正在编辑的值，不覆盖尚未应用的开局设置
      if (!el.result.hidden) renderResult();
    },
    setStats(mines, flags, opened, need) {
      el.stats.textContent = t('stats', { mines, flags, opened, need });
    },
    setTime(sec) {
      el.time.textContent = formatTime(sec);
    },
    setFps(v) {
      fpsValue = v;
      if (v < 0) {
        el.fps.textContent = '';
        return;
      }
      el.fps.textContent = t('fpsValue', { fps: v });
    },
    setHint(text) {
      el.hint.textContent = text;
    },
    setStatus(text) {
      if (el.status) el.status.textContent = text;
    },
    setPeel(depth, max) {
      el.peelValue.textContent = t('peelDepth', { depth, max });
      el.peelHide.disabled = depth >= max;
      el.peelShow.disabled = depth <= 0;
    },
    setSpacing(pct) {
      el.spacing.value = String(pct);
      el.spacingValue.textContent = `${pct}%`;
    },
    openBoard(side, mines) {
      const total = side ** 3;
      el.side.value = String(side);
      el.mines.max = String(Math.max(1, total - 1));
      el.mines.value = String(mines);
      syncBoardHint();
      el.boardPanel.hidden = false;
    },
    openOptions(s) {
      el.lang.value = s.lang;
      el.volume.value = String(s.volume);
      el.volumeValue.value = String(s.volume);
      el.mute.setAttribute('aria-pressed', String(s.muted));
      el.showFps.setAttribute('aria-pressed', String(s.showFps));
      el.dimOthersOnChord.setAttribute('aria-pressed', String(s.dimOthersOnChord));
      el.mapLeft.value = s.mouseMap[0];
      el.mapMiddle.value = s.mouseMap[1];
      el.mapRight.value = s.mouseMap[2];
      el.version.textContent = t('version', { version: s.version });
      el.optionsPanel.hidden = false;
    },
    syncVolume(v) {
      el.volume.value = String(v);
      el.volumeValue.value = String(v);
    },
    syncMute(m) {
      el.mute.setAttribute('aria-pressed', String(m));
    },
    showResult(won, sec, side, mines) {
      resultData = { won, sec, side, mines };
      el.result.classList.toggle('won', won);
      el.result.classList.toggle('lost', !won);
      renderResult();
      el.result.hidden = false;
    },

    isBoardOpen: () => !el.boardPanel.hidden,
    isOptionsOpen: () => !el.optionsPanel.hidden,
    isResultOpen: () => !el.result.hidden,
    closeBoard,
    closeOptions,
    hideResult,
  };
}
