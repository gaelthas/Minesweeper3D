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

const messages = JSON.parse(readFileSync(new URL('../src/strings.json', import.meta.url), 'utf8'));

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
  await page.waitForFunction(() => window.minesweeper3d && window.minesweeper3d.state.board, { timeout: 15000 });
  await new Promise((r) => setTimeout(r, 600));

  const currentStrings = async (tab = page) => messages[await tab.$eval('html', (el) => el.lang === 'zh-CN' ? 'zh_CN' : 'en')];

  const stats = () => page.evaluate(() => ({
    mines: window.minesweeper3d.state.board.mineTotal,
    revealed: window.minesweeper3d.state.board.revealedCount,
    flags: window.minesweeper3d.state.board.flagCount,
    over: window.minesweeper3d.state.board.gameOver,
    generated: window.minesweeper3d.state.board.generated,
  }));

  // 找一个能点到的方块：把中心方块投影到屏幕坐标
  const centerOf = (x, y, z) =>
    page.evaluate((x, y, z) => {
      const { world, state } = window.minesweeper3d;
      const i = state.board.index(x, y, z);
      const cell = world.cells[i];
      if (!cell) return null;
      const v = cell.root.position.clone();
      v.project(world.camera);
      return { x: (v.x * 0.5 + 0.5) * 1280, y: (-v.y * 0.5 + 0.5) * 720, index: i };
    }, x, y, z);

  const side = await page.evaluate(() => window.minesweeper3d.state.board.side);
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
    const { state, world } = window.minesweeper3d;
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
    let s = await page.evaluate((i) => window.minesweeper3d.state.board.states[i], spot.index);
    check(s === 2, '右键插旗');
    await page.mouse.click(spot.x, spot.y, { button: 'right' });
    await new Promise((r) => setTimeout(r, 150));
    s = await page.evaluate((i) => window.minesweeper3d.state.board.states[i], spot.index);
    check(s === 3, '右键第二下变问号');
    await page.mouse.click(spot.x, spot.y, { button: 'right' });
    await new Promise((r) => setTimeout(r, 150));
    s = await page.evaluate((i) => window.minesweeper3d.state.board.states[i], spot.index);
    check(s === 0, '右键第三下回到未标记');
  } else {
    check(false, '没找到可标记的格子');
  }

  // 间距滑块：只挪位置，不改方块尺寸
  const posBefore = await page.evaluate(() => window.minesweeper3d.world.cells[0].root.position.x);
  await page.evaluate(() => {
    const el = document.getElementById('spacing');
    el.value = '150';
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await new Promise((r) => setTimeout(r, 200));
  const moved = await page.evaluate(() => ({
    pos: window.minesweeper3d.world.cells[0].root.position.x,
    scale: window.minesweeper3d.world.cells[0].cube.scale.x,
  }));
  check(Math.abs(moved.pos - posBefore) > 1e-6, '间距变化后方块位置改变');
  check(Math.abs(moved.scale - 0.88) < 1e-6, '方块尺寸不变（0.88）');

  // 和弦：左右同按。先探出射线实际命中的面，再按那一面的数字插旗
  const chordSetup = await page.evaluate(() => {
    const { state, world } = window.minesweeper3d;
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
      return { x: sx, y: sy, index: i, need, face, revealed: b.revealedCount };
    }
    return null;
  });
  if (chordSetup) {
    await page.mouse.move(chordSetup.x, chordSetup.y);
    await page.mouse.down({ button: 'left' });
    await page.mouse.down({ button: 'right' });
    const highlight = await page.evaluate(({ index, face }) => {
      const { world, state } = window.minesweeper3d;
      const b = state.board;
      const related = b.relatedCells(index, face);
      const expected = related.filter((i) => b.states[i] === 0 || b.states[i] === 3 || b.states[i] === 2);
      const flags = related.filter((i) => b.states[i] === 2);
      const other = world.cells.findIndex((cell, i) => i !== index && !related.includes(i) &&
        b.states[i] === 0 && cell.root.visible && cell.cube.visible);
      // 保存恢复前的引用，避免和弦揭示改变状态后把恢复检查变成空断言
      window.chordVisualCheck = { flags, other };
      const dim = other >= 0 ? world.cells[other].cube.material : null;
      return {
        matches: expected.length > 0 && world.highlighted.size === expected.length && expected.every((i) => world.highlighted.has(i)),
        flags: flags.length > 0 && flags.every((i) => world.cells[i].cube.material === world.highlightMats.flag),
        dimmed: !!dim && dim === world.dimMats.hidden && dim.transparent && !dim.depthWrite && Math.abs(dim.opacity - 0.15) < 1e-6,
        protected: !world.dimmed.has(index) && related.every((i) => !world.dimmed.has(i)),
        materials: expected.length > 0 && expected.every((i) => world.cells[i].cube.material === world.highlightMats[b.states[i] === 2 ? 'flag' : b.states[i] === 3 ? 'question' : 'hidden']),
      };
    }, chordSetup);
    check(highlight.matches, '双键按住时高亮恰好覆盖未揭示关联格及旗子');
    check(highlight.materials, '关联格使用高亮材质');
    check(highlight.flags, '关联旗子使用金色高亮材质');
    check(highlight.dimmed, '非关联可见未揭示格淡化且不写深度');
    check(highlight.protected, '被按格和全部关联格均不淡化');
    // 移到画布外清除提示后松开，避免本次恢复断言被实际和弦改变盘面干扰
    await page.mouse.move(-10, -10);
    await page.mouse.up({ button: 'left' });
    await page.mouse.up({ button: 'right' });
    check(await page.evaluate(() => {
      const { world } = window.minesweeper3d;
      const { flags, other } = window.chordVisualCheck;
      return world.highlighted.size === 0 && world.dimmed.size === 0 &&
        flags.every((i) => world.cells[i].cube.material === world.materials.flag) &&
        other >= 0 && world.cells[other].cube.material === world.materials.hidden;
    }), '离开画布并松开后旗子和非关联格恢复原材质');

    // 关闭淡化时仍然高亮旗子；恢复开关后继续原来的和弦动作测试
    await page.click('#btn-options');
    await page.click('#dim-others-on-chord');
    await page.keyboard.press('Escape');
    await page.mouse.move(chordSetup.x, chordSetup.y);
    await page.mouse.down({ button: 'left' });
    await page.mouse.down({ button: 'right' });
    check(await page.evaluate(() => {
      const { world, settings } = window.minesweeper3d;
      return !settings.dimOthersOnChord && world.dimmed.size === 0 &&
        window.chordVisualCheck.flags.every((i) => world.cells[i].cube.material === world.highlightMats.flag);
    }), '关闭淡化开关时仍高亮关联旗子');
    await page.mouse.move(-10, -10);
    await page.mouse.up({ button: 'left' });
    await page.mouse.up({ button: 'right' });
    await page.click('#btn-options');
    await page.click('#dim-others-on-chord');
    await page.keyboard.press('Escape');
    await page.mouse.move(chordSetup.x, chordSetup.y);
    await page.mouse.down({ button: 'left' });
    await page.mouse.down({ button: 'right' });
    await page.mouse.up({ button: 'left' });
    await page.mouse.up({ button: 'right' });
    check(await page.evaluate(() => window.minesweeper3d.world.highlighted.size === 0 && window.minesweeper3d.world.dimmed.size === 0), '松开双键后清除高亮与淡化');
    await new Promise((r) => setTimeout(r, 250));
    const after = await page.evaluate(() => ({
      revealed: window.minesweeper3d.state.board.revealedCount,
      over: window.minesweeper3d.state.board.gameOver,
    }));
    check(after.revealed > chordSetup.revealed || after.over,
      `左右同按触发和弦（面 ${chordSetup.face}，需 ${chordSetup.need} 旗，${chordSetup.revealed} → ${after.revealed}）`);
  } else {
    check(false, '找不到可用于和弦的格子');
  }

  // 和弦可能踩雷，结算弹窗会盖住界面；先收掉再测浮层
  await page.evaluate(() => window.minesweeper3d.ui.hideResult());
  await new Promise((r) => setTimeout(r, 100));

  // 布局：浮层开关
  await page.click('#btn-options');
  await new Promise((r) => setTimeout(r, 200));
  check(await page.$eval('#options-panel', (e) => !e.hidden), '选项页可以打开');
  const shownVersion = await page.$eval('#version', (e) => e.textContent);
  const pkgVersion = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version;
  check(shownVersion.includes(pkgVersion), `版本号来自 package.json（${shownVersion.trim()}）`);

  // 同时准备结算文案与尚未应用的开局设置，切语言不能重开或覆盖草稿
  await page.evaluate(() => {
    const { ui, state, world } = window.minesweeper3d;
    window.languageSnapshot = { board: state.board, states: [...state.board.states], elapsed: state.elapsed, peel: world.peel };
    ui.openBoard(7, 44);
    ui.showResult(true, 83.4, 5, 38);
  });
  for (const lang of ['en', 'zh_CN']) {
    await page.select('#lang', lang);
    const translated = await page.evaluate((table) => {
      const { state, world, settings } = window.minesweeper3d;
      const snapshot = window.languageSnapshot;
      const text = (key, vars = {}) => table[key].replace(/\{(\w+)\}/g, (_, name) => String(vars[name] ?? ''));
      const b = state.board;
      const statusKey = b.gameOver ? (b.won ? 'statusWon' : 'statusLost') : 'statusStart';
      return {
        htmlLang: document.documentElement.lang,
        staticText: [...document.querySelectorAll('[data-text]')].every((el) => el.textContent === text(el.dataset.text)),
        accessible: [...document.querySelectorAll('[data-aria-label]')].every((el) => el.getAttribute('aria-label') === text(el.dataset.ariaLabel)),
        title: document.title === table.appTitle,
        stats: document.getElementById('stats').textContent === text('stats', { mines: b.mineTotal, flags: b.flagCount, opened: b.revealedCount, need: b.total - b.mineTotal }),
        status: document.getElementById('status').textContent === table[statusKey],
        hint: document.getElementById('hint').textContent.includes(table.hintPeel),
        peel: document.getElementById('peel-value').textContent === text('peelDepth', { depth: world.peel, max: Math.floor((b.side - 1) / 2) }),
        result: !document.getElementById('result').hidden && document.getElementById('result-title').textContent === table.resultWon &&
          document.getElementById('result-detail').textContent === text('resultDetail', { side: 5, mines: 38 }) && document.getElementById('result-time').textContent === '01:23',
        draft: document.getElementById('side').value === '7' && document.getElementById('mines').value === '44' &&
          document.getElementById('board-hint').textContent === text('boardHint', { side: 7, total: 343, density: (44 / 343 * 100).toFixed(1), rec: 103 }),
        preserved: state.board === snapshot.board && [...state.board.states].every((v, i) => v === snapshot.states[i]) &&
          state.elapsed === snapshot.elapsed && world.peel === snapshot.peel,
        preference: settings.lang,
        stored: JSON.parse(localStorage.getItem('minesweeper3d.settings')).lang,
      };
    }, messages[lang]);
    check(translated.htmlLang === (lang === 'en' ? 'en' : 'zh-CN') && translated.staticText && translated.title && translated.accessible,
      `${lang} 即时更新按钮、选项、标题、无障碍标签与 html lang`);
    check(translated.stats && translated.status && translated.hint && translated.peel && translated.result && translated.draft,
      `${lang} 即时更新 HUD、状态、操作提示、剥层、结算与推荐雷数文案`);
    check(translated.preserved && translated.preference === lang && translated.stored === lang,
      `${lang} 已持久化，棋盘、计时和剥层保持不变`);
  }
  await page.evaluate(() => {
    const { ui } = window.minesweeper3d;
    ui.hideResult();
    ui.closeBoard();
  });

  await page.keyboard.press('Escape');
  await new Promise((r) => setTimeout(r, 200));
  check(await page.$eval('#options-panel', (e) => e.hidden), 'Esc 关掉选项页');

  // 剥层：真实键盘输入，隐藏外壳后拾取应穿过它
  await page.keyboard.press('r');
  const outer = await centerOf(hi, hi, hi);
  await page.keyboard.press('h');
  const peeled = await page.evaluate(({ x, y }) => {
    const { world } = window.minesweeper3d;
    const hit = world.pick(x, y);
    return {
      depth: world.peel,
      hidden: world.cells.filter((c) => c.layer === 0).every((c) => !c.root.visible),
      inner: world.cells.filter((c) => c.layer >= 1).every((c) => c.root.visible),
      pick: !hit || world.cells[hit.index].layer > 0,
      label: document.getElementById('peel-value').textContent,
    };
  }, outer);
  check(peeled.depth === 1 && peeled.hidden && peeled.inner, 'H 隐藏最外层，保留内层');
  const peelStrings = await currentStrings();
  check(peeled.label === peelStrings.peelDepth.replace('{depth}', '1').replace('{max}', String(Math.floor((side - 1) / 2))),
    '剥层文案按当前语言显示深度');
  check(peeled.pick, '外层屏幕坐标拾取不会命中隐藏外层');
  await page.keyboard.down('Shift');
  await page.keyboard.press('h');
  await page.keyboard.up('Shift');
  check(await page.evaluate(() => {
    const { world } = window.minesweeper3d;
    return world.peel === 0 && world.cells.every((c) => c.root.visible);
  }), 'Shift+H 恢复第 0 层');
  await page.keyboard.press('h');
  await page.keyboard.press('r');
  check(await page.evaluate(() => window.minesweeper3d.world.peel === 0), 'R 重开重置剥层深度');

  // 结算弹窗：直接调 UI，验证文案与按钮
  const resultStrings = await currentStrings();
  await page.evaluate(() => window.minesweeper3d.ui.showResult(true, 83.4, 5, 38));
  await new Promise((r) => setTimeout(r, 150));
  check(await page.$eval('#result', (e) => !e.hidden), '结算弹窗可以打开');
  check((await page.$eval('#result-title', (e) => e.textContent)) === resultStrings.resultWon, '胜利标题使用当前语言');
  check((await page.$eval('#result-time', (e) => e.textContent)) === '01:23', '用时格式化成 mm:ss');
  await page.click('#result-again');
  await new Promise((r) => setTimeout(r, 300));
  const restarted = await page.evaluate(() => ({
    revealed: window.minesweeper3d.state.board.revealedCount,
    hidden: document.getElementById('result').hidden,
  }));
  check(restarted.hidden, '再来一局会关掉弹窗');
  check(restarted.revealed === 0, '再来一局重置盘面');

  // URL 仅临时覆盖语言：即使已保存中文，新页面也显示英文，存档仍是中文
  const urlPage = await browser.newPage();
  urlPage.on('pageerror', (e) => errors.push(String(e)));
  urlPage.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await urlPage.goto(`${pathToFileURL(target).href}?seed=20261112&lang=en`);
  await urlPage.waitForFunction(() => window.minesweeper3d?.state.board, { timeout: 15000 });
  const urlView = await urlPage.evaluate(() => ({
    lang: document.documentElement.lang,
    restart: document.getElementById('btn-restart').textContent,
    preference: window.minesweeper3d.settings.lang,
    stored: JSON.parse(localStorage.getItem('minesweeper3d.settings')).lang,
  }));
  check(urlView.lang === 'en' && urlView.restart === messages.en.restart, '?lang=en 临时覆盖已保存的中文选择');
  check(urlView.preference === 'zh_CN' && urlView.stored === 'zh_CN', 'URL 语言覆盖不写入 settings 或存档');
  await urlPage.close();

  // 截图前把间距还原成 100%，便于看默认观感
  await page.evaluate(() => {
    const el = document.getElementById('spacing');
    el.value = '100';
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await new Promise((r) => setTimeout(r, 400));
  await page.screenshot({ path: 'dist/e2e.png' });
  check(errors.length === 0, `控制台无报错${errors.length ? '：' + errors.slice(0, 2).join(' | ') : ''}`);
  console.log(`\n${failures === 0 ? 'PASS' : `FAIL ${failures}`}`);
  process.exitCode = failures === 0 ? 0 : 1;
} finally {
  await browser.close();
}
