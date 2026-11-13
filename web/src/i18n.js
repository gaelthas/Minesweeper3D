// 语言选择与插值不依赖 DOM，便于测试宿主、存档与 URL 的优先级。
export function languagePreference(value) {
  return ['auto', 'zh_CN', 'en'].includes(value) ? value : 'auto';
}

export function normalizeLocale(value) {
  return /^zh(?:[-_]|$)/i.test(String(value || '')) ? 'zh_CN' : 'en';
}

export function urlLanguage(search) {
  const lang = new URLSearchParams(search).get('lang');
  return lang === 'zh' ? 'zh_CN' : lang === 'en' ? 'en' : null;
}

export function resolveLocale(preference, automatic, override = null) {
  if (override === 'zh_CN' || override === 'en') return override;
  const lang = languagePreference(preference);
  return lang === 'auto' ? normalizeLocale(automatic) : lang;
}

export function translate(messages, locale, key, vars = {}) {
  const table = messages[locale] || messages.en;
  const text = table[key] ?? messages.zh_CN[key] ?? key;
  return text.replace(/\{(\w+)\}/g, (_, name) => String(vars[name] ?? ''));
}
