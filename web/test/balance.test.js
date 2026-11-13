import test from 'node:test';
import assert from 'node:assert/strict';
import { inferMoves, visibleConstraints, simulate, wilson } from '../scripts/balance.mjs';
import { World } from '../src/scene.js';
import { Board, REVEALED, HIDDEN, FLAGGED, QUESTION, closedFaceMask, seededRng } from '../src/logic.js';

test('求解器单约束：全安全与全雷', () => {
  const { safe, mines } = inferMoves([{ cells: [1, 2], count: 0 }, { cells: [3, 4], count: 2 }]);
  assert.deepEqual([...safe], [1, 2]);
  assert.deepEqual([...mines], [3, 4]);
});

test('求解器子集差：全安全与全雷，非子集不推断', () => {
  assert.deepEqual([...inferMoves([{ cells: [1, 2], count: 1 }, { cells: [1, 2, 3], count: 1 }]).safe], [3]);
  assert.deepEqual([...inferMoves([{ cells: [1, 2], count: 1 }, { cells: [1, 2, 3], count: 2 }]).mines], [3]);
  const result = inferMoves([{ cells: [1, 2], count: 1 }, { cells: [2, 3], count: 1 }]);
  assert.equal(result.safe.size + result.mines.size, 0);
});

test('求解器不读取雷位或未揭示数字', () => {
  const board = {
    total: 3,
    states: [REVEALED, HIDDEN, FLAGGED],
    get mines() { throw new Error('偷看雷位'); },
    get counts() { throw new Error('偷看计数'); },
    faceCounts: new Proxy([], { get: (_, key) => {
      assert.ok(Number(key) < 6, '只能读已揭示格数字');
      return 1;
    } }),
    relatedCells: () => [1, 2],
  };
  const { safe } = inferMoves(visibleConstraints(board, 'open'));
  assert.deepEqual([...safe], [1]);
});

test('平衡实验固定种子可复现', () => {
  assert.deepEqual(simulate(5, 0.3, 42), simulate(5, 0.3, 42));
});

test('推理层级：单约束优先，只有必要时才计子集步骤', () => {
  const subset = [{ cells: [1, 2], count: 1 }, { cells: [1, 2, 3], count: 1 }];
  assert.equal(inferMoves(subset).level, 2);
  assert.equal(inferMoves([...subset, { cells: [4], count: 0 }]).level, 1);
  assert.equal(inferMoves([{ cells: [1, 2], count: 1 }]).level, 0);
});

const DIRECTIONS = [[0, 0, 1], [0, 0, -1], [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0]];

test('closed 仅方向轴邻格已揭示或越界时可见，旗与问号不能透视', () => {
  const b = new Board(3, 1);
  const center = b.index(1, 1, 1);
  assert.equal(closedFaceMask(b, center), 0);
  assert.equal(closedFaceMask(b, b.index(0, 0, 0)), 42);
  for (let face = 0; face < 6; face++) {
    const c = DIRECTIONS[face].map((v) => v + 1);
    for (const state of [HIDDEN, FLAGGED, QUESTION, REVEALED]) {
      b.states.fill(HIDDEN);
      b.states[b.index(...c)] = state;
      assert.equal(closedFaceMask(b, center), state === REVEALED ? 1 << face : 0);
    }
  }
});

test('提取可见性后，scene 的紧凑、剥层、展开间距判定保持原语义', () => {
  const rng = seededRng(123);
  for (const side of [3, 4, 5]) {
    const b = new Board(side, 1);
    for (let i = 0; i < b.total; i++) b.states[i] = Math.floor(rng() * 4);
    for (let i = 0; i < b.total; i++) {
      const c = b.coord(i);
      for (let peel = 0; peel <= Math.floor((side - 1) / 2); peel++) {
        // 独立保留原 faceMask 定义，防止共用函数产生同错同过
        let expected = 0;
        DIRECTIONS.forEach((normal, face) => {
          const n = c.map((v, axis) => v + normal[axis]);
          if (!b.inBounds(...n) || b.states[b.index(...n)] === REVEALED ||
            Math.min(...n, ...n.map((v) => side - 1 - v)) < peel) expected |= 1 << face;
        });
        assert.equal(World.prototype.faceMask.call({ board: b, openView: false, peel }, i), expected);
        assert.equal(World.prototype.faceMask.call({ board: b, openView: true, peel }, i), 63);
        if (peel === 0) assert.equal(closedFaceMask(b, i), expected);
      }
    }
  }
});

test('closed 求解器不读取被遮挡面的数字，open 读取所有已揭示面', () => {
  const b = new Board(3, 1);
  b.states[b.index(1, 1, 1)] = REVEALED;
  b.states[b.index(1, 1, 2)] = REVEALED;
  const reads = [];
  b.faceCounts = new Proxy([], { get: (_, key) => {
    const index = Number(key);
    reads.push(index);
    return 0;
  } });
  visibleConstraints(b, 'closed');
  assert.equal(reads.length, 3, '中心 +Z、前邻格的 ±Z 面可见');
  assert.deepEqual(reads, [b.index(1, 1, 1) * 6, b.index(1, 1, 2) * 6, b.index(1, 1, 2) * 6 + 1]);
  reads.length = 0;
  visibleConstraints(b, 'open');
  assert.equal(reads.length, 12);
  assert.throws(() => visibleConstraints(b, 'invalid'), /未知可见性/);
});

test('Wilson 区间在零成功和全成功时仍保留不确定性', () => {
  const zero = wilson(0, 300);
  const all = wilson(300, 300);
  assert.ok(zero[0] < 1e-12 && zero[1] > 0.012 && zero[1] < 0.013);
  assert.ok(all[0] > 0.987 && all[0] < 0.988 && all[1] > 1 - 1e-12);
  const half = wilson(150, 300);
  assert.ok(Math.abs(half[0] + half[1] - 1) < 1e-12);
  assert.throws(() => wilson(0, 0), /样本数/);
});

test('两种可见性下实验可复现，卡住比例与步骤计数范围有效', () => {
  for (const visibility of ['open', 'closed']) {
    const result = simulate(5, 0.45, 42, visibility);
    assert.deepEqual(result, simulate(5, 0.45, 42, visibility));
    assert.ok(result.subsetSteps <= result.logicSteps);
    assert.ok(result.stalledRevealSum >= 0 && result.stalledRevealSum <= result.guesses);
  }
});
