// DatasetSamplePlot — an inline distribution plot for the dataset-object Plot tab,
// built CLIENT-SIDE from the profiler's SAMPLE rows (profile.sampleRows) that the
// Table view already renders. The Plot tab previously showed a "no plot data from
// the profiler" placeholder, but the sample rows ARE present — so this leverages
// existing data (no new backend/profiler work) to chart numeric columns as a
// histogram. Honestly labelled as the N-row sample; the full-dataset path stays
// Jupyter/RStudio. Non-numeric / too-small samples → `hasNumericColumns` is false
// and the caller keeps the Jupyter/chat fallback (never an empty axis).
import { useMemo, useState } from "react";
import { locale } from "@/lib/i18n";
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from "recharts";

export interface DatasetSamplePlotProps {
  columns: string[];
  sampleRows: string[][];
  /** The table's decimal mark when the reader reports one ("," → "1,5" is 1.5). */
  decimal?: string | null;
  /** i18n passthrough; (key, vars) — matches the app's narrowed t signature. */
  t?: (key: string, vars?: any) => string;
}

/**
 * A cell as a number, or NaN. With a decimal comma ("1,5", "1.234,5") the comma is the decimal
 * mark and a dot only groups thousands; otherwise the usual "1.5".
 */
export function parseCellNumber(raw: string | null | undefined, decimal?: string | null): number {
  let v = (raw ?? "").trim();
  if (v === "") return NaN;
  if (decimal === ",") {
    if (!/^[+-]?(\d{1,3}(\.\d{3})+|\d+)(,\d+)?([eE][+-]?\d+)?$/.test(v)) return NaN;
    v = v.replace(/\./g, "").replace(",", ".");
  }
  const n = Number(v);
  return Number.isFinite(n) ? n : NaN;
}

/** Indices of columns whose sample cells are >=60% finite numbers (>=2 non-empty). */
export function numericColumnIndices(columns: string[], rows: string[][], decimal?: string | null): number[] {
  const out: number[] = [];
  columns.forEach((_, ci) => {
    let num = 0, tot = 0;
    for (const r of rows) {
      const v = (r?.[ci] ?? "").trim();
      if (v === "") continue;
      tot++;
      if (Number.isFinite(parseCellNumber(v, decimal))) num++;
    }
    if (tot >= 2 && num / tot >= 0.6) out.push(ci);
  });
  return out;
}

export function hasNumericColumns(columns: string[], rows: string[][], decimal?: string | null): boolean {
  return numericColumnIndices(columns, rows, decimal).length > 0;
}

export interface HistogramBin {
  /** Bin start, formatted (the axis tick). */
  bin: string;
  /** "start – end" in the same format (the tooltip). */
  range: string;
  start: number;
  end: number;
  count: number;
}

/** A "nice" step (1, 2, 2.5 or 5 × 10^k) at least `raw` wide. */
function niceStep(raw: number): number {
  const p = Math.pow(10, Math.floor(Math.log10(raw)));
  const f = raw / p;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * p;
}

/**
 * A number formatter for one axis: locale grouping (1,840 / zh 1,840), the SAME number of
 * decimals on every tick (enough to tell neighbouring edges apart), and compact notation for
 * millions and beyond (1.8M / 180万). Never scientific "1.84e+3".
 */
export function axisNumberFormat(step: number, maxAbs: number, tag = locale === "zh" ? "zh-CN" : "en-US"): (v: number) => string {
  if (maxAbs >= 1e6) {
    const nf = new Intl.NumberFormat(tag, { notation: "compact", maximumSignificantDigits: 3 });
    return (v) => nf.format(v);
  }
  let decimals = step >= 1 ? 0 : Math.min(6, Math.ceil(-Math.log10(step)));
  // 2.5 × 10^k steps need one more digit (0.25, 0.5, 0.75).
  if (decimals < 6 && Math.abs(Math.round(step * 10 ** decimals) - step * 10 ** decimals) > 1e-9) decimals += 1;
  const nf = new Intl.NumberFormat(tag, { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  return (v) => nf.format(Math.abs(v) < step * 1e-9 ? 0 : v);
}

/** Histogram on nice, aligned bin edges with human-formatted labels. Pure + testable. */
export function histogramBins(values: number[], targetBins = 12, tag?: string): HistogramBin[] {
  if (values.length === 0) return [];
  const min = Math.min(...values), max = Math.max(...values);
  if (min === max) {
    const fmt = axisNumberFormat(Math.abs(min) || 1, Math.abs(min), tag);
    return [{ bin: fmt(min), range: fmt(min), start: min, end: max, count: values.length }];
  }
  const step = niceStep((max - min) / targetBins);
  const first = Math.floor(min / step) * step;
  const n = Math.max(1, Math.floor((max - first) / step) + 1);
  const counts = new Array(n).fill(0);
  for (const v of values) counts[Math.min(n - 1, Math.max(0, Math.floor((v - first) / step)))]++;
  const fmt = axisNumberFormat(step, Math.max(Math.abs(first), Math.abs(first + n * step)), tag);
  return counts.map((count, i) => {
    const start = first + i * step, end = start + step;
    return { bin: fmt(start), range: `${fmt(start)} – ${fmt(end)}`, start, end, count };
  });
}

export function DatasetSamplePlot({ columns, sampleRows, decimal, t }: DatasetSamplePlotProps) {
  const tr = t || ((_k: string, v?: any) => `Distribution of column “${v?.col}” · rows loaded: ${v?.n}`);
  const numCols = useMemo(() => numericColumnIndices(columns, sampleRows, decimal), [columns, sampleRows, decimal]);
  const [sel, setSel] = useState<number>(numCols[0] ?? -1);
  const colIdx = numCols.includes(sel) ? sel : (numCols[0] ?? -1);

  const data = useMemo(() => {
    if (colIdx < 0) return [];
    const vals = sampleRows
      .map((r) => parseCellNumber(r?.[colIdx], decimal))
      .filter((v) => Number.isFinite(v));
    return histogramBins(vals);
  }, [colIdx, sampleRows, decimal]);

  if (colIdx < 0 || data.length === 0) return null; // caller renders the fallback

  return (
    <div data-testid="dataset-sample-plot" className="space-y-2">
      {numCols.length > 1 && (
        <select
          value={colIdx}
          onChange={(e) => setSel(Number(e.target.value))}
          data-testid="dataset-sample-plot-col"
          className="rounded border bg-background px-2 py-1 text-xs"
        >
          {numCols.map((ci) => <option key={ci} value={ci}>{columns[ci]}</option>)}
        </select>
      )}
      <div style={{ width: "100%", height: 200 }}>
        <ResponsiveContainer>
          <BarChart data={data} margin={{ top: 8, right: 8, bottom: 4, left: 0 }}>
            <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" vertical={false} />
            <XAxis dataKey="bin" tick={{ fontSize: 10, fill: "var(--text-muted)" }} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 10, fill: "var(--text-muted)" }} width={28} allowDecimals={false} />
            <Tooltip
              labelFormatter={(_l, payload) => (payload?.[0]?.payload as HistogramBin | undefined)?.range ?? String(_l)}
              contentStyle={{ fontSize: 'var(--fs-xs)', background: "var(--bg-elev, #fff)", border: "1px solid var(--border)", borderRadius: 6 }}
            />
            <Bar dataKey="count" name={t ? t("dataset_obj.plot_count") : "Count"} fill="var(--accent, oklch(0.55 0.18 260))" radius={[2, 2, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <p className="text-xs text-muted-foreground" data-testid="dataset-sample-plot-caption">
        {tr("dataset_obj.plot_sample_caveat", { col: columns[colIdx], n: sampleRows.length.toLocaleString(locale === "zh" ? "zh-CN" : "en-US") })}
      </p>
    </div>
  );
}
