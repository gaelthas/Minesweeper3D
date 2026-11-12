// 端到端检查：用真实浏览器打开构建产物，模拟鼠标操作，断言盘面状态。
// 只在本地跑（CI 里没有稳定的 Chrome 路径）：
//   node scripts/e2e.mjs [path/to/dist/index.html]
//
// macOS 默认用系统 Chrome，其他平台用 CHROME_PATH 环境变量。

import puppeteer from 'puppeteer-core';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const CANDIDATES = [
  process.env.CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean);

const chrome = CANDIDATES.find((p) => existsSync(p));
if (!chrome) {
  console.error('找不到 Chrome，设置 CHROME_PATH 再跑');
  process.exit(1);
}

const target = resolve(process.argv[2] || 'dist/index.html');
if (!existsSync(target)) {
  console.error(`产物不存在：${target}，先跑 npm run build`);
  process.exit(1);
}

let failures = 0;
const check = (ok, msg) => {
  console.log(`${ok ? '  ok  ' : '  x  '}${msg}`);
  if (!ok) failures++;
};

const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--enable-unsafe-swiftshader', '--window-size=1280,720'],
  defaultViewport: { width: 1280, height: 720 },
});

try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });

  await page.goto(`${pathToFileURL(target).href}?seed=20261112`);
  await page.waitForFunction(() => window.minecube && window.minecube.state.board, { timeout: 15000 });
  await new Promise((r) => setTimeout(r, 600));

  const stats = () => page.evaluate(() => ({
    mines: window.minecube.state.board.mineTotal,
    revealed: window.minecube.state.board.revealedCount,
    flags: window.minecube.state.board.flagCount,
    over: window.minecube.state.board.gameOver,
    generated: window.minecube.state.board.generated,
  }));

  // 找一个能点到的方块：把中心方块投影到屏幕坐标
  const centerOf = (x, y, z) =>
    page.evaluate((x, y, z) => {
      const { world, state } = window.minecube;
      const i = state.board.index(x, y, z);
      const cell = world.cells[i];
      if (!cell) return null;
      const v = cell.root.position.clone();
      v.project(world.camera);
      return { x: (v.x * 0.5 + 0.5) * 1280, y: (-v.y * 0.5 + 0.5) * 720, index: i };
    }, x, y, z);

  const side = await page.evaluate(() => window.minecube.state.board.side);
  const hi = side - 1;
  const target1 = await centerOf(hi, hi, hi);
  check(target1 !== null, '取到面向相机那个角格的屏幕坐标');

  // 左键揭示
  const before = await stats();
  await page.mouse.click(target1.x, target1.y);
  await new Promise((r) => setTimeout(r, 300));
  const afterReveal = await stats();
  check(afterReveal.generated, '首次点击后布雷完成');
  check(afterReveal.revealed > before.revealed, `左键揭示生效（${before.revealed} → ${afterReveal.revealed}）`);
  check(afterReveal.mines === before.mines, '雷数不变');

  // 右键三次循环：旗 → 问号 → 未标记
  // 找一个「从相机看过去能直接点到」的未揭示格：
  // 光靠投影中心不行，深处的格子会被外层挡住
  const hidden = await page.evaluate(() => {
    const { state, world } = window.minecube;
    const b = state.board;
    const W = 1280;
    const H = 720;
    for (let i = 0; i < b.total; i++) {
      if (b.states[i] !== 0 || b.mines[i] === 1) continue;
      const cell = world.cells[i];
      const v = cell.root.position.clone().project(world.camera);
      const sx = (v.x * 0.5 + 0.5) * W;
      const sy = (-v.y * 0.5 + 0.5) * H;
      if (sx < 0 || sy < 0 || sx > W || sy > H) continue;
      const hit = world.pick(sx, sy);
      if (hit && hit.index === i) return { x: sx, y: sy, index: i };
    }
    return null;
  });
  const spot = hidden;
  if (spot) {
    await page.mouse.click(spot.x, spot.y, { button: 'right' });
    await new Promise((r) => setTimeout(r, 150));
    let s = await page.evaluate((i) => window.minecube.state.board.states[i], spot.index);
    check(s === 2, '右键插旗');
    await page.mouse.click(spot.x, spot.y, { button: 'right' });
    await new Promise((r) => setTimeout(r, 150));
    s = await page.evaluate((i) => window.minecube.state.board.states[i], spot.index);
    check(s === 3, '右键第二下变问号');
    await page.mouse.click(spot.x, spot.y, { button: 'right' });
    await new Promise((r) => setTimeout(r, 150));
    s = await page.evaluate((i) => window.minecube.state.board.states[i], spot.index);
    check(s === 0, '右键第三下回到未标记');
  } else {
    check(false, '没找到可标记的格子');
  }

  // 间距滑块：只挪位置，不改方块尺寸
  const posBefore = await page.evaluate(() => window.minecube.world.cells[0].root.position.x);
  await page.evaluate(() => {
    const el = document.getElementById('spacing');
    el.value = '150';
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await new Promise((r) => setTimeout(r, 200));
  const moved = await page.evaluate(() => ({
    pos: window.minecube.world.cells[0].root.position.x,
    scale: window.minecube.world.cells[0].cube.scale.x,
  }));
  check(Math.abs(moved.pos - posBefore) > 1e-6, '间距变化后方块位置改变');
  check(Math.abs(moved.scale - 0.88) < 1e-6, '方块尺寸不变（0.88）');

  // 和弦：左右同按。先探出射线实际命中的面，再按那一面的数字插旗
  const chordSetup = await page.evaluate(() => {
    const { state, world } = window.minecube;
    const b = state.board;
    const W = 1280;
    const H = 720;
    for (let i = 0; i < b.total; i++) {
      if (b.states[i] !== 1) continue;
      const cell = world.cells[i];
      const v = cell.root.position.clone().project(world.camera);
      const sx = (v.x * 0.5 + 0.5) * W;
      const sy = (-v.y * 0.5 + 0.5) * H;
      const hit = world.pick(sx, sy);
      if (!hit || hit.index !== i) continue;

      const face = hit.face;
      const need = b.faceCounts[i * 6 + face];
      if (need === 0) continue;
      const hidden = b.faceNeighbors(i, face).filter((n) => b.states[n] === 0);
      // 至少要留一格给和弦去开，否则看不出效果
      if (hidden.length <= need) continue;

      // 直接摆状态，不管旗插的是不是雷：这一项测的是「左右同按会不会走和弦」
      for (let k = 0; k < need; k++) {
        b.states[hidden[k]] = 2;
        b.flagCount++;
        world.refresh(hidden[k]);
      }
      world.refresh(i);
      return { x: sx, y: sy, need, face, revealed: b.revealedCount };
    }
    return null;
  });
  if (chordSetup) {
    // 记录实际到达画布的事件序列，便于定位是浏览器没发还是逻辑没走
    await page.evaluate(() => {

    });
    await page.mouse.move(chordSetup.x, chordSetup.y);
    await page.mouse.down({ button: 'left' });
    await page.mouse.down({ button: 'right' });
    await page.mouse.up({ button: 'left' });
    await page.mouse.up({ button: 'right' });
    await new Promise((r) => setTimeout(r, 250));
    const after = await page.evaluate(() => ({
      revealed: window.minecube.state.board.revealedCount,
      over: window.minecube.state.board.gameOver,
    }));
    check(after.revealed > chordSetup.revealed || after.over,
      `左右同按触发和弦（面 ${chordSetup.face}，需 ${chordSetup.need} 旗，${chordSetup.revealed} → ${after.revealed}）`);
  } else {
    check(false, '找不到可用于和弦的格子');
  }

  // 和弦可能踩雷，结算弹窗会盖住界面；先收掉再测浮层
  await page.evaluate(() => window.minecube.ui.hideResult());
  await new Promise((r) => setTimeout(r, 100));

  // 布局：浮层开关
  await page.click('#btn-options');
  await new Promise((r) => setTimeout(r, 200));
  check(await page.$eval('#options-panel', (e) => !e.hidden), '选项页可以打开');
  const shownVersion = await page.$eval('#version', (e) => e.textContent);
  const pkgVersion = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version;
  check(shownVersion.includes(pkgVersion), `版本号来自 package.json（${shownVersion.trim()}）`);
  await page.keyboard.press('Escape');
  await new Promise((r) => setTimeout(r, 200));
  check(await page.$eval('#options-panel', (e) => e.hidden), 'Esc 关掉选项页');

  // 结算弹窗：直接揭示到胜利
  await page.evaluate(() => {
    const { state, world } = window.minecube;
    const b = state.board;
    for (let i = 0; i < b.total; i++) {
      if (b.mines[i] === 0) {
        const res = b.reveal(i);
        world.refreshArea(res.opened);
      }
    }
    window.minecube.ui?.updateStats?.();
  });
  await new Promise((r) => setTimeout(r, 300));
  const won = await page.evaluate(() => window.minecube.state.board.won);

  check(errors.length === 0, `控制台无报错${errors.length ? '：' + errors.slice(0, 2).join(' | ') : ''}`);

  // 结算弹窗：直接调 UI，验证文案与按钮
  await page.evaluate(() => window.minecube.ui.showResult(true, 83.4, 5, 38));
  await new Promise((r) => setTimeout(r, 150));
  check(await page.$eval('#result', (e) => !e.hidden), '结算弹窗可以打开');
  check((await page.$eval('#result-title', (e) => e.textContent)) === '清空', '胜利标题是「清空」');
  check((await page.$eval('#result-time', (e) => e.textContent)) === '01:23', '用时格式化成 mm:ss');
  await page.click('#result-again');
  await new Promise((r) => setTimeout(r, 300));
  const restarted = await page.evaluate(() => ({
    revealed: window.minecube.state.board.revealedCount,
    hidden: document.getElementById('result').hidden,
  }));
  check(restarted.hidden, '再来一局会关掉弹窗');
  check(restarted.revealed === 0, '再来一局重置盘面');

  // 截图前把间距还原成 100%，便于看默认观感
  await page.evaluate(() => {
    const el = document.getElementById('spacing');
    el.value = '100';
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await new Promise((r) => setTimeout(r, 400));
  await page.screenshot({ path: 'dist/e2e.png' });
  console.log(`\n${failures === 0 ? 'PASS' : `FAIL ${failures}`}`);
  process.exitCode = failures === 0 ? 0 : 1;
} finally {
  await browser.close();
}
