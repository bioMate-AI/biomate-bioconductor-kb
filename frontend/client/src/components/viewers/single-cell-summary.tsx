import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";

/**
 * In-app single-cell summary panel — a basic, interactive-ish view of an
 * scRNA-seq result WITHOUT launching an external tool. It reads a small JSON
 * sidecar the pipeline emits next to the .h5ad (`<h5ad path>.summary.json`),
 * mirroring the `<rds>.json` sidecar the R-object viewer already consumes.
 *
 * The sidecar carries only what a quick look needs (never the whole matrix):
 *   { n_cells, n_genes,
 *     clusters: [{ label, n }],
 *     umap:    { points: [[x, y, clusterLabel], ...] },   // subsampled ≤ ~2000
 *     markers: [{ cluster, genes: [...] }] }
 *
 * When no sidecar is present the component reports `absent` so the caller can
 * fall back to the download / interactive-tool path — it never fabricates a
 * plot from data it doesn't have.
 */
export interface SingleCellSummary {
  n_cells?: number;
  n_genes?: number;
  clusters?: Array<{ label: string; n: number }>;
  umap?: { points?: Array<[number, number, string]> };
  markers?: Array<{ cluster: string; genes: string[] }>;
}

// A stable, colour-blind-friendly-ish categorical palette (Okabe–Ito + extras).
const PALETTE = [
  "#4C72B0", "#DD8452", "#55A868", "#C44E52", "#8172B3", "#937860",
  "#DA8BC3", "#8C8C8C", "#CCB974", "#64B5CD", "#E69F00", "#009E73",
];

function colorFor(label: string, order: string[]): string {
  const i = order.indexOf(label);
  return PALETTE[(i < 0 ? 0 : i) % PALETTE.length];
}

export function SingleCellSummaryPanel({
  runId,
  file,
  onAbsent,
}: {
  runId: string;
  file: { name: string; path: string };
  /** Called once we know no sidecar exists, so the caller can show a fallback. */
  onAbsent?: () => void;
}) {
  const [data, setData] = useState<SingleCellSummary | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "absent">("loading");

  useEffect(() => {
    let alive = true;
    const url = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(
      file.path + ".summary.json",
    )}&name=${encodeURIComponent(file.name + ".summary.json")}`;
    fetch(url, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : Promise.reject(`HTTP ${r.status}`)))
      .then((j: SingleCellSummary) => {
        if (!alive) return;
        // Only treat as "ready" if it carries something worth showing.
        const useful =
          (j.clusters && j.clusters.length > 0) ||
          (j.umap?.points && j.umap.points.length > 0) ||
          (j.markers && j.markers.length > 0);
        if (useful) { setData(j); setState("ready"); }
        else { setState("absent"); onAbsent?.(); }
      })
      .catch(() => { if (alive) { setState("absent"); onAbsent?.(); } });
    return () => { alive = false; };
  }, [runId, file.path, file.name, onAbsent]);

  if (state === "loading") {
    return (
      <div className="flex items-center gap-2 text-xs text-muted-foreground py-3">
        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading single-cell summary…
      </div>
    );
  }
  if (state === "absent" || !data) return null;

  const clusters = (data.clusters ?? []).slice().sort((a, b) => b.n - a.n);
  const order = clusters.map((c) => c.label);
  const maxN = clusters.reduce((m, c) => Math.max(m, c.n), 0) || 1;
  const points = data.umap?.points ?? [];

  return (
    <div className="space-y-3" data-testid="single-cell-summary">
      <div className="flex items-baseline gap-3 text-xs">
        {typeof data.n_cells === "number" && (
          <span><span className="font-semibold">{data.n_cells.toLocaleString()}</span> cells</span>
        )}
        {typeof data.n_genes === "number" && (
          <span className="text-muted-foreground">{data.n_genes.toLocaleString()} genes</span>
        )}
        {clusters.length > 0 && (
          <span className="text-muted-foreground">{clusters.length} clusters</span>
        )}
      </div>

      {/* UMAP scatter (subsampled), coloured by cluster. */}
      {points.length > 0 && (
        <UmapScatter points={points} order={order} />
      )}

      {/* Cluster composition. */}
      {clusters.length > 0 && (
        <div className="space-y-1" data-testid="single-cell-clusters">
          {clusters.map((c) => (
            <div key={c.label} className="flex items-center gap-2 text-[11px]">
              <span
                className="h-2.5 w-2.5 rounded-sm shrink-0"
                style={{ background: colorFor(c.label, order) }}
              />
              <span className="w-32 truncate" title={c.label}>{c.label}</span>
              <span className="flex-1 h-1.5 rounded-full bg-muted overflow-hidden">
                <span
                  className="block h-full rounded-full"
                  style={{ width: `${Math.round((c.n / maxN) * 100)}%`, background: colorFor(c.label, order) }}
                />
              </span>
              <span className="font-mono text-muted-foreground tabular-nums">{c.n.toLocaleString()}</span>
            </div>
          ))}
        </div>
      )}

      {/* Top markers per cluster. */}
      {data.markers && data.markers.length > 0 && (
        <div className="space-y-1" data-testid="single-cell-markers">
          <div className="text-[11px] font-medium text-muted-foreground">Top markers</div>
          {data.markers.map((m) => (
            <div key={m.cluster} className="text-[11px] flex gap-2">
              <span className="w-32 truncate shrink-0" title={m.cluster}>
                <span
                  className="inline-block h-2 w-2 rounded-sm mr-1 align-middle"
                  style={{ background: colorFor(m.cluster, order) }}
                />
                {m.cluster}
              </span>
              <span className="font-mono text-muted-foreground truncate">{m.genes.slice(0, 8).join(", ")}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/** Minimal dependency-free UMAP scatter (SVG). Points are pre-subsampled by the
 *  pipeline, so we just scale to the viewbox. */
function UmapScatter({ points, order }: { points: Array<[number, number, string]>; order: string[] }) {
  const W = 280, H = 200, PAD = 6;
  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  const sx = (x: number) => PAD + ((x - minX) / (maxX - minX || 1)) * (W - 2 * PAD);
  // SVG y grows downward; flip so higher UMAP-2 is up.
  const sy = (y: number) => H - PAD - ((y - minY) / (maxY - minY || 1)) * (H - 2 * PAD);
  return (
    <svg
      width="100%"
      viewBox={`0 0 ${W} ${H}`}
      className="rounded-md border bg-background"
      data-testid="single-cell-umap"
      role="img"
      aria-label="UMAP embedding coloured by cluster"
    >
      {points.map((p, i) => (
        <circle key={i} cx={sx(p[0])} cy={sy(p[1])} r={1.6} fill={colorFor(p[2], order)} fillOpacity={0.7} />
      ))}
    </svg>
  );
}
