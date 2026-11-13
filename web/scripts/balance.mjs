// 固定种子的平衡实验：node scripts/balance.mjs，输出 Markdown 表格。
import { pathToFileURL } from 'node:url';
import { Board, REVEALED, FLAGGED, seededRng, closedFaceMask } from '../src/logic.js';

/** 纯推理：输入仅含未知格集合与剩余雷数，不接触棋盘或布雷数组。 */
export function inferMoves(constraints) {
  const safe = new Set();
  const mines = new Set();
  const unique = new Map();
  const conclude = (cells, count) => {
    if (count < 0 || count > cells.length) throw new Error('约束矛盾');
    if (count === 0) for (const i of cells) safe.add(i);
    else if (count === cells.length) for (const i of cells) mines.add(i);
  };
  for (const { cells, count } of constraints) {
    const sorted = [...new Set(cells)].sort((a, b) => a - b);
    conclude(sorted, count);
    if (!sorted.length) continue;
    const key = sorted.join(',');
    if (unique.has(key) && unique.get(key).count !== count) throw new Error('重复约束矛盾');
    unique.set(key, { cells: sorted, count, set: new Set(sorted) });
  }
  // 单约束能推进就先执行，下一轮用新数字重新收集约束
  if (safe.size || mines.size) return { safe, mines, level: 1 };
  const list = [...unique.values()];
  const containing = new Map();
  for (const c of list) {
    for (const i of c.cells) {
      if (!containing.has(i)) containing.set(i, []);
      containing.get(i).push(c);
    }
  }
  for (const a of list) {
    // 超集必须含 A 的每一格，从候选最少的一格开始找
    const candidates = a.cells.map((i) => containing.get(i)).reduce((x, y) => x.length < y.length ? x : y);
    for (const b of candidates) {
      if (a.cells.length >= b.cells.length || !a.cells.every((i) => b.set.has(i))) continue;
      conclude(b.cells.filter((i) => !a.set.has(i)), b.count - a.count);
    }
  }
  for (const i of safe) if (mines.has(i)) throw new Error('推理矛盾');
  return { safe, mines, level: safe.size || mines.size ? 2 : 0 };
}

/** 只收集已揭示面的数字、邻域和标记；不读 mines / counts 或未揭示数字。 */
export function visibleConstraints(board, visibility = 'closed') {
  if (!['open', 'closed'].includes(visibility)) throw new Error(`未知可见性：${visibility}`);
  const out = [];
  for (let i = 0; i < board.total; i++) {
    if (board.states[i] !== REVEALED) continue;
    const mask = visibility === 'open' ? 63 : closedFaceMask(board, i);
    for (let face = 0; face < 6; face++) {
      if (!(mask & (1 << face))) continue;
      const cells = [];
      let count = board.faceCounts[i * 6 + face];
      for (const n of board.relatedCells(i, face)) {
        if (board.states[n] === FLAGGED) count--;
        else if (board.states[n] !== REVEALED) cells.push(n);
      }
      out.push({ cells, count });
    }
  }
  return out;
}

export function simulate(side, density, seed, visibility = 'closed') {
  // 布雷与猜测分开随机流，让两种可见性下相同参数、局号使用相同初始局面
  const layoutRng = seededRng(seed);
  const guessRng = seededRng(seed ^ 0x9e3779b9);
  const board = new Board(side, Math.round(side ** 3 * density), layoutRng);
  const center = Math.floor(side / 2);
  const firstCoord = Array.from({ length: 3 }, () => center - 1 + Math.floor(layoutRng() * 3));
  const first = board.index(...firstCoord);
  board.placeMines(first);
  board.reveal(first);
  let guesses = 0;
  let logicSteps = 0;
  let subsetSteps = 0;
  let stalledRevealSum = 0;
  while (!board.gameOver) {
    const { safe, mines, level } = inferMoves(visibleConstraints(board, visibility));
    if (safe.size || mines.size) {
      logicSteps++;
      if (level === 2) subsetSteps++;
      for (const i of mines) board.cycleMark(i);
      for (const i of safe) {
        if (board.reveal(i).boom) throw new Error('逻辑推理打开了雷');
        if (board.gameOver) break;
      }
    } else {
      const unknown = [];
      for (let i = 0; i < board.total; i++) {
        if (board.states[i] !== REVEALED && board.states[i] !== FLAGGED) unknown.push(i);
      }
      if (!unknown.length) throw new Error('未结束但无可猜格');
      guesses++;
      stalledRevealSum += board.revealedCount / (board.total - board.mineTotal);
      board.reveal(unknown[Math.floor(guessRng() * unknown.length)]);
    }
  }
  return { won: board.won, guesses, logicSteps, subsetSteps, stalledRevealSum };
}

/** 二项比例的 Wilson 95% 区间（不使用正态近似的 p ± 误差）。 */
export function wilson(successes, trials) {
  if (trials <= 0) throw new Error('样本数必须为正');
  const z = 1.959963984540054;
  const p = successes / trials;
  const denominator = 1 + z * z / trials;
  const center = (p + z * z / (2 * trials)) / denominator;
  const half = z * Math.sqrt(p * (1 - p) / trials + z * z / (4 * trials * trials)) / denominator;
  return [Math.max(0, center - half), Math.min(1, center + half)];
}

export function measure(side, percent, visibility) {
  const games = side === 5 ? 300 : 150;
  const row = { side, percent, visibility, games, wins: 0, noGuess: 0,
    guesses: 0, logicSteps: 0, subsetSteps: 0, stalledRevealSum: 0 };
  for (let trial = 0; trial < games; trial++) {
    const result = simulate(side, percent / 100,
      (20261112 + side * 100000 + percent * 1000 + trial) >>> 0, visibility);
    row.wins += Number(result.won);
    row.noGuess += Number(result.won && result.guesses === 0);
    for (const key of ['guesses', 'logicSteps', 'subsetSteps', 'stalledRevealSum']) row[key] += result[key];
  }
  return row;
}

function printRow(r) {
  const pct = (value, digits = 1) => (100 * value).toFixed(digits) + '%';
  const interval = wilson(r.noGuess, r.games).map((value) => pct(value)).join('–');
  const subset = r.logicSteps ? pct(r.subsetSteps / r.logicSteps, 2) : '—';
  const stalled = r.guesses ? pct(r.stalledRevealSum / r.guesses, 2) : '—';
  console.log(`| ${r.side} | ${r.percent}% | ${r.games} | ${pct(r.noGuess / r.games)} [${interval}] | ${subset} | ${stalled} | ${(r.guesses / r.games).toFixed(3)} | ${pct(r.wins / r.games)} |`);
}

/** 固定扫描原规则，校验默认 30% 密度，不自动选档。 */
export function runBalance() {
  console.log('固定种子：20261112；5 阶每组 300 局、7 阶每组 150 局；不模拟剥层。');
  const rows = [];
  for (const visibility of ['open', 'closed']) {
    console.log(`\n## ${visibility}\n`);
    console.log('| 边长 | 密度 | 局数 | 无猜通关率 [Wilson 95% CI] | 子集步骤占比 | 卡住时已开比例 | 平均猜次数 | 胜率 |');
    console.log('| ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: |');
    for (const side of [5, 7]) {
      for (const percent of [25, 30, 35, 40, 45]) {
        const row = measure(side, percent, visibility);
        rows.push(row);
        printRow(row);
      }
    }
  }
  return rows;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) runBalance();
