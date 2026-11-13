import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { languagePreference, normalizeLocale, urlLanguage, resolveLocale, translate } from '../src/i18n.js';

const messages = JSON.parse(readFileSync(new URL('../src/strings.json', import.meta.url), 'utf8'));

test('语言存档值校验，旧存档默认自动', () => {
  for (const lang of ['auto', 'zh_CN', 'en']) assert.equal(languagePreference(lang), lang);
  for (const lang of [undefined, null, 'zh', 'fr', 1]) assert.equal(languagePreference(lang), 'auto');
});

test('自动语言接受浏览器与宿主格式，手动语言优先', () => {
  for (const lang of ['zh', 'zh-CN', 'zh_CN', 'ZH-tw']) assert.equal(normalizeLocale(lang), 'zh_CN');
  for (const lang of ['en-US', 'en', 'fr', undefined]) assert.equal(normalizeLocale(lang), 'en');
  assert.equal(resolveLocale('auto', 'zh_CN'), 'zh_CN');
  assert.equal(resolveLocale('auto', 'en-US'), 'en');
  assert.equal(resolveLocale('en', 'zh_CN'), 'en');
  assert.equal(resolveLocale('zh_CN', 'en'), 'zh_CN');
});

test('URL 临时覆盖存档，撤销覆盖后回到存档或宿主语言', () => {
  assert.equal(urlLanguage('?seed=1&lang=zh'), 'zh_CN');
  assert.equal(urlLanguage('?lang=en'), 'en');
  assert.equal(urlLanguage('?lang=unknown'), null);
  assert.equal(urlLanguage(''), null);
  const settings = Object.freeze({ lang: 'zh_CN' });
  assert.equal(resolveLocale(settings.lang, 'zh_CN', urlLanguage('?lang=en')), 'en');
  assert.equal(settings.lang, 'zh_CN');
  assert.equal(resolveLocale(settings.lang, 'en', null), 'zh_CN');
  assert.equal(resolveLocale('auto', 'en', null), 'en');
});

test('中英字典键与占位符一致，模板文案和无障碍标签均有翻译', () => {
  assert.deepEqual(Object.keys(messages.zh_CN).sort(), Object.keys(messages.en).sort());
  const placeholders = (text) => [...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]).sort();
  for (const key of Object.keys(messages.zh_CN)) {
    assert.ok(messages.zh_CN[key] && messages.en[key], key);
    assert.deepEqual(placeholders(messages.zh_CN[key]), placeholders(messages.en[key]), key);
  }
  for (const path of ['../src/template.html', '../index.html']) {
    const html = readFileSync(new URL(path, import.meta.url), 'utf8');
    for (const [, key] of html.matchAll(/data-(?:text|aria-label|title)="([^"]+)"/g)) {
      assert.ok(Object.hasOwn(messages.en, key), key);
    }
  }
});

test('动态文案按当前语言插值，数字零不丢失', () => {
  assert.equal(translate(messages, 'en', 'peelDepth', { depth: 0, max: 2 }), 'Layer 0/2');
  assert.equal(translate(messages, 'zh_CN', 'peelDepth', { depth: 0, max: 2 }), '第 0/2 层');
});
