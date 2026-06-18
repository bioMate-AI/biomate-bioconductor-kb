/**
 * Project grounded findings key_results into FindingsFigure[] for the after-run panel.
 * A TS port of the backend _build_figures_from_key_results so the Node (Gemini) findings
 * path gets illustration figures too — Bioconductor CSV outputs hit that path, while the
 * Python output_analyzer figures only fire for VCF/domain-specific analyzers.
 *
 * Domain-agnostic; emits at most one qc/composition/bars figure, only from real numbers,
 * never fabricates. Each figure inherits source_file when its contributing metrics agree.
 * Kept in its own side-effect-free module so it is unit-testable without importing the
 * whole server (routes.ts pulls in s3-client etc. at import time).
 */
type Item = { metric: string; n: number; src?: string };

function parseNum(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  const m = String(v ?? "").replace(/,/g, "").match(/-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/);
  return m ? parseFloat(m[0]) : null;
}

export function buildFiguresFromKeyResults(keyResults: any[]): any[] {
  if (!Array.isArray(keyResults) || keyResults.length === 0) return [];

  const numeric: Item[] = [];
  for (const kr of keyResults) {
    const metric = String(kr?.metric ?? kr?.label ?? "").trim();
    const n = parseNum(kr?.value);
    if (metric && n !== null) numeric.push({ metric, n, src: kr?.source_file });
  }
  if (numeric.length === 0) return [];

  const sharedSrc = (ms: Item[]): string | undefined => {
    const s = new Set(ms.map(m => m.src).filter(Boolean) as string[]);
    return s.size === 1 ? [...s][0] : undefined;
  };

  const figures: any[] = [];
  const used = new Set<Item>();

  // QC: a (kept, total) pair.
  const total = numeric.find(it => /\btotal\b|\ball\b/i.test(it.metric));
  const kept = numeric.find(it => /\bpass\b|kept|retained|passing/i.test(it.metric));
  if (total && kept && total !== kept && total.n > 0 && kept.n >= 0 && kept.n <= total.n) {
    figures.push({ kind: "qc", title: `${kept.metric} / ${total.metric}`, kept: kept.n, total: total.n, source_file: sharedSrc([kept, total]) });
    used.add(total); used.add(kept);
  }

  // Composition: >=2 metrics sharing a trailing word (e.g. "HIGH impact", "LOW impact").
  const lastWord = (m: string) => { const p = m.toLowerCase().match(/[a-z]+/g); return p ? p[p.length - 1] : ""; };
  const groups: Record<string, Item[]> = {};
  for (const it of numeric) {
    if (used.has(it) || /\btotal\b|\ball\b/i.test(it.metric) || it.n < 0) continue;
    const k = lastWord(it.metric); if (!k) continue;
    (groups[k] ||= []).push(it);
  }
  let comp: Item[] = [];
  for (const k of Object.keys(groups)) {
    if (groups[k].length >= 2 && groups[k].reduce((a, b) => a + b.n, 0) > 0) { comp = groups[k]; break; }
  }
  if (comp.length) {
    figures.push({
      kind: "composition",
      title: comp.length <= 3 ? comp.slice(0, 3).map(m => m.metric).join(" vs ") : `${comp[0].metric} breakdown`,
      data: comp.map(m => [m.metric, m.n]),
      source_file: sharedSrc(comp),
    });
    comp.forEach(m => used.add(m));
  }

  // Bars: remaining >=2 numeric metrics.
  const rest = numeric.filter(it => !used.has(it) && it.n >= 0 && !/\btotal\b|\ball\b/i.test(it.metric));
  if (rest.length >= 2) {
    figures.push({ kind: "bars", title: "Key metrics", data: rest.map(it => [it.metric, it.n]), source_file: sharedSrc(rest) });
  }

  return figures;
}
