/**
 * Localize backend-sourced catalog labels (phase / step / parameter names) for the
 * active UI locale. Outside zh this is the identity. Under zh it renders the English
 * source immediately and swaps in the translation from /api/i18n/labels when it
 * arrives (server: server/label-translation.ts — batched LLM call, cached). Never
 * blocks rendering; a failed fetch simply leaves the source text.
 */
import { useEffect, useMemo, useState } from 'react';
import { locale as activeLocale } from './i18n';

const cache = new Map<string, string>();
const inflight = new Map<string, Promise<void>>();
const listeners = new Set<() => void>();

function request(strings: string[]): Promise<void> {
  const missing = strings.filter(s => !cache.has(s) && !inflight.has(s));
  if (missing.length === 0) return Promise.all(strings.map(s => inflight.get(s)).filter(Boolean)).then(() => undefined);
  const p = fetch('/api/i18n/labels', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ lang: 'zh', strings: missing }),
  })
    .then(r => (r.ok ? r.json() : { translations: {} }))
    .then((d: { translations?: Record<string, string> }) => {
      for (const s of missing) cache.set(s, d.translations?.[s] ?? s);
    })
    .catch(() => { for (const s of missing) cache.set(s, s); })
    .finally(() => {
      for (const s of missing) inflight.delete(s);
      listeners.forEach(l => l());
    });
  for (const s of missing) inflight.set(s, p);
  return p;
}

/** Returns a translate function for the given labels (identity until loaded / outside zh). */
export function useLocalizedLabels(strings: Array<string | undefined | null>, lang: string = activeLocale): (s: string) => string {
  const list = useMemo(
    () => [...new Set(strings.filter((s): s is string => typeof s === 'string' && s.trim().length > 0))],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [strings.join('\u0001')],
  );
  const [, bump] = useState(0);
  useEffect(() => {
    if (lang !== 'zh' || list.length === 0) return;
    const l = () => bump(n => n + 1);
    listeners.add(l);
    void request(list);
    return () => { listeners.delete(l); };
  }, [lang, list]);
  return (s: string) => (lang === 'zh' ? cache.get(s) ?? s : s);
}

/** Test hook. */
export function _resetLocalizedLabelCache() { cache.clear(); inflight.clear(); listeners.clear(); }
