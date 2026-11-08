// DatasetSamplePlot — an inline distribution plot for the dataset-object Plot tab,
// built CLIENT-SIDE from the profiler's SAMPLE rows (profile.sampleRows) that the
// Table view already renders. The Plot tab previously showed a "no plot data from
// the profiler" placeholder, but the sample rows ARE present — so this leverages
// existing data (no new backend/profiler work) to chart numeric columns as a
// histogram. Honestly labelled as the N-row sample; the full-dataset path stays
// Jupyter/RStudio. Non-numeric / too-small samples → `hasNumericColumns` is false
// and the caller keeps the Jupyter/chat fallback (never an empty axis).
import { useMemo, useState } from "react";
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from "recharts";

export interface DatasetSamplePlotProps {
  columns: string[];
  sampleRows: string[][];
  /** i18n passthrough; (key, vars) — matches the app's narrowed t signature. */
  t?: (key: string, vars?: any) => string;
}

/** Indices of columns whose sample cells are >=60% finite numbers (>=2 non-empty). */
export function numericColumnIndices(columns: string[], rows: string[][]): number[] {
  const out: number[] = [];
  columns.forEach((_, ci) => {
    let num = 0, tot = 0;
    for (const r of rows) {
      const v = (r?.[ci] ?? "").trim();
      if (v === "") continue;
      tot++;
      if (Number.isFinite(Number(v))) num++;
    }
    if (tot >= 2 && num / tot >= 0.6) out.push(ci);
  });
  return out;
}

export function hasNumericColumns(columns: string[], rows: string[][]): boolean {
  return numericColumnIndices(columns, rows).length > 0;
}

function histogram(values: number[], bins = 12): Array<{ bin: string; count: number }> {
  if (values.length === 0) return [];
  const min = Math.min(...values), max = Math.max(...values);
  if (min === max) return [{ bin: String(min), count: values.length }];
  const w = (max - min) / bins;
  const counts = new Array(bins).fill(0);
  for (const v of values) {
    let b = Math.floor((v - min) / w);
    if (b >= bins) b = bins - 1;
    if (b < 0) b = 0;
    counts[b]++;
  }
  return counts.map((count, i) => ({ bin: (min + i * w).toPrecision(3), count }));
}

export function DatasetSamplePlot({ columns, sampleRows, t }: DatasetSamplePlotProps) {
  const tr = t || ((_k: string, v?: any) =>
    `Distribution of ${v?.col} across the ${v?.n}-row sample — open in Jupyter/RStudio for the full dataset.`);
  const numCols = useMemo(() => numericColumnIndices(columns, sampleRows), [columns, sampleRows]);
  const [sel, setSel] = useState<number>(numCols[0] ?? -1);
  const colIdx = numCols.includes(sel) ? sel : (numCols[0] ?? -1);

  const data = useMemo(() => {
    if (colIdx < 0) return [];
    const vals = sampleRows
      .map((r) => Number((r?.[colIdx] ?? "").trim()))
      .filter((v) => Number.isFinite(v));
    return histogram(vals);
  }, [colIdx, sampleRows]);

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
            <Tooltip contentStyle={{ fontSize: 11, background: "var(--bg-elev, #fff)", border: "1px solid var(--border)", borderRadius: 6 }} />
            <Bar dataKey="count" fill="var(--accent, oklch(0.55 0.18 260))" radius={[2, 2, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <p className="text-xs text-muted-foreground">
        {tr("dataset_obj.plot_sample_caveat", { col: columns[colIdx], n: sampleRows.length })}
      </p>
    </div>
  );
}
