/**
 * DataPerception — gap 9 "perception-at-ingest" READ surface.
 *
 * Extends DataHub's "quality at ingest" Good/Watch/Blocked flag into a
 * perception panel that answers two user questions:
 *
 *   1. "What did you see in my data?"  — shape, leakage, effective N,
 *      class balance, signal summary.
 *   2. "How did that shape the plan?"  — e.g. "single-end detected →
 *      suggested single-end pipeline".
 *
 * This is a PRESENTATIONAL surface only. The actual profiling
 * (leakage detection, effective-N estimation, class-balance counting,
 * numeric/spectral signal extraction, vision-on-demand for images) is a
 * BACKEND profiler and is OUT OF SCOPE for this component — the panel
 * renders whatever profile it is handed via props and never fabricates
 * a field it was not given.
 *
 * Ref: docs/20260901_OMNISCIENTIST_GAP_ANALYSIS.md (Gap A),
 *      docs/20260903_DESIGN_VS_PLAN_DISCREPANCY_AND_UPDATE_BRIEF.md (gap 9).
 */

import { AlertTriangle, CheckCircle2, XCircle, Eye, ArrowRight } from "lucide-react";
import { cn } from "@/lib/utils";

// ---------------------------------------------------------------------------
// Types — clean data shapes the backend profiler will populate.
// ---------------------------------------------------------------------------

export type PerceptionQuality = "good" | "watch" | "blocked";

export interface ClassBalanceEntry {
  /** Class / group label as it appears in the data. */
  label: string;
  /** Fraction of rows in this class, in [0, 1]. */
  frac: number;
}

export interface LeakageFinding {
  /** Human-readable detail of a suspected leak (e.g. "batch confounds label"). */
  detail: string;
}

export interface DataProfile {
  /** Raw shape the profiler observed. */
  shape: { rows: number; cols: number };
  /** Suspected data-leakage finding, if any. */
  leakage?: LeakageFinding;
  /** Effective sample size after accounting for correlation / imbalance. */
  effectiveN?: number;
  /** Class-balance breakdown (ordered as the profiler emitted it). */
  classBalance?: ClassBalanceEntry[];
  /** Numeric-first signal summary lines (spectral peaks, trends, etc.). */
  signalSummary?: string[];
  /** Overall ingest-quality verdict. */
  quality: PerceptionQuality;
  /** Free-text perception notes ("single-end detected", "12 outliers", …). */
  notes: string[];
  /** Column headers of a table-like dataset (capped), for the Preview tab. */
  columns?: string[];
  /** First rows of a table-like dataset (capped), for the Preview tab. */
  sampleRows?: string[][];
}

export interface DataPerceptionProps {
  /** The profile emitted by the backend perception profiler. */
  profile: DataProfile;
  /**
   * Optional "how it shaped the plan" lines. Each entry is a cause → effect
   * pair, e.g. { observed: "single-end detected", effect: "suggested single-end pipeline" }.
   */
  planImpact?: { observed: string; effect: string }[];
  /** Optional dataset name for the header crumb. */
  datasetName?: string;
  className?: string;
}

// ---------------------------------------------------------------------------
// Quality vocabulary — mirrors DataHub QUAL Good/Watch/Blocked.
// ---------------------------------------------------------------------------

const QUALITY_META: Record<
  PerceptionQuality,
  { label: string; icon: typeof CheckCircle2; badge: string; dot: string }
> = {
  good: {
    label: "Good",
    icon: CheckCircle2,
    badge: "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
    dot: "bg-emerald-500",
  },
  watch: {
    label: "Watch",
    icon: AlertTriangle,
    badge: "border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400",
    dot: "bg-amber-500",
  },
  blocked: {
    label: "Blocked",
    icon: XCircle,
    badge: "border-red-500/30 bg-red-500/10 text-red-600 dark:text-red-400",
    dot: "bg-red-500",
  },
};

function fmtInt(n: number): string {
  return n.toLocaleString("en-US");
}

function fmtPct(frac: number): string {
  return `${(frac * 100).toFixed(frac < 0.1 ? 1 : 0)}%`;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function DataPerception({
  profile,
  planImpact,
  datasetName,
  className,
}: DataPerceptionProps) {
  const q = QUALITY_META[profile.quality];
  const QIcon = q.icon;
  const hasClassBalance = !!profile.classBalance && profile.classBalance.length > 0;
  const hasSignal = !!profile.signalSummary && profile.signalSummary.length > 0;
  const hasNotes = profile.notes.length > 0;

  // For sequence files the profiler's shape.rows/cols are reads × read-length,
  // not table rows/columns — label them accordingly so "COLUMNS 30" (= 30 bp)
  // isn't confusing on a FASTQ.
  const nm = (datasetName || "").toLowerCase();
  const isFastq = /\.(fastq|fq)(\.gz)?$/.test(nm);
  const isFasta = /\.(fasta|fa|fna|faa)(\.gz)?$/.test(nm);
  const rowLabel = isFastq ? "Reads" : isFasta ? "Sequences" : "Rows";
  const colLabel = isFastq ? "Read length (bp)" : isFasta ? "Length (bp)" : "Columns";

  return (
    <div
      data-testid="data-perception"
      data-quality={profile.quality}
      className={cn(
        "shadcn-card rounded-xl border bg-card border-card-border text-card-foreground shadow-sm",
        "flex flex-col gap-4 p-5",
        className,
      )}
    >
      {/* Header */}
      <div className="flex items-start gap-2">
        <Eye className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
        <div className="flex flex-col gap-0.5">
          <div className="text-sm font-semibold leading-tight">What we saw in your data</div>
          {datasetName && (
            <div className="font-mono text-xs text-muted-foreground">{datasetName}</div>
          )}
        </div>
        <span
          data-testid="perception-quality-badge"
          className={cn(
            "ml-auto inline-flex items-center gap-1.5 whitespace-nowrap rounded-md border px-2.5 py-0.5 text-xs font-semibold",
            q.badge,
          )}
        >
          <QIcon className="h-3.5 w-3.5" aria-hidden />
          {q.label}
        </span>
      </div>

      {/* Shape + effective-N stat strip */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Stat k={rowLabel} v={fmtInt(profile.shape.rows)} />
        <Stat k={colLabel} v={fmtInt(profile.shape.cols)} />
        {typeof profile.effectiveN === "number" && (
          <Stat
            k="Effective N"
            v={fmtInt(profile.effectiveN)}
            hint={
              profile.effectiveN < profile.shape.rows
                ? "below row count — correlation / imbalance discounted it"
                : undefined
            }
            testId="perception-effective-n"
          />
        )}
      </div>

      {/* Leakage callout — the highest-signal finding, surfaced on its own. */}
      {profile.leakage && (
        <div
          data-testid="perception-leakage"
          className="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 text-xs"
        >
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-500" aria-hidden />
          <div>
            <span className="font-semibold text-amber-600 dark:text-amber-400">
              Possible leakage:{" "}
            </span>
            <span className="text-foreground">{profile.leakage.detail}</span>
          </div>
        </div>
      )}

      {/* Class balance */}
      {hasClassBalance && (
        <div className="flex flex-col gap-2" data-testid="perception-class-balance">
          <div className="text-xs font-semibold text-muted-foreground">Class balance</div>
          <div className="flex flex-col gap-1.5">
            {profile.classBalance!.map((c, i) => (
              <div key={`${c.label}-${i}`} className="flex items-center gap-2">
                <span className="w-28 shrink-0 truncate font-mono text-xs" title={c.label}>
                  {c.label}
                </span>
                <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                  <div
                    className={cn(
                      "h-full rounded-full",
                      c.frac < 0.1 ? "bg-amber-500" : "bg-primary",
                    )}
                    style={{ width: `${Math.max(2, Math.min(100, c.frac * 100))}%` }}
                  />
                </div>
                <span className="w-10 shrink-0 text-right text-xs tabular-nums text-muted-foreground">
                  {fmtPct(c.frac)}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Numeric-first signal summary */}
      {hasSignal && (
        <div className="flex flex-col gap-1.5" data-testid="perception-signal">
          <div className="text-xs font-semibold text-muted-foreground">Signal summary</div>
          <ul className="flex flex-col gap-1">
            {profile.signalSummary!.map((s, i) => (
              <li key={i} className="flex items-start gap-2 text-xs">
                <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-muted-foreground/60" />
                <span className="text-foreground">{s}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Free-text perception notes */}
      {hasNotes && (
        <div className="flex flex-col gap-1.5" data-testid="perception-notes">
          <div className="text-xs font-semibold text-muted-foreground">Notes</div>
          <ul className="flex flex-col gap-1">
            {profile.notes.map((n, i) => (
              <li key={i} className="flex items-start gap-2 text-xs">
                <span className={cn("mt-1 h-2 w-2 shrink-0 rounded-full", q.dot)} />
                <span className="text-foreground">{n}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* How it shaped the plan */}
      {planImpact && planImpact.length > 0 && (
        <div
          className="flex flex-col gap-2 border-t border-card-border pt-3"
          data-testid="perception-plan-impact"
        >
          <div className="text-xs font-semibold text-muted-foreground">How it shaped the plan</div>
          <div className="flex flex-col gap-1.5">
            {planImpact.map((p, i) => (
              <div key={i} className="flex flex-wrap items-center gap-1.5 text-xs">
                <span className="rounded bg-muted px-1.5 py-0.5 font-medium text-foreground">
                  {p.observed}
                </span>
                <ArrowRight className="h-3 w-3 shrink-0 text-muted-foreground" aria-hidden />
                <span className="text-muted-foreground">{p.effect}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Provenance note: profiling is backend, this is a read surface. */}
      <div className="text-[11px] leading-snug text-muted-foreground/70">
        Perception is computed by the backend profiler at ingest. This panel shows what it
        observed; it does not re-profile the data.
      </div>
    </div>
  );
}

function Stat({
  k,
  v,
  hint,
  testId,
}: {
  k: string;
  v: string;
  hint?: string;
  testId?: string;
}) {
  return (
    <div className="flex flex-col gap-0.5" data-testid={testId}>
      <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        {k}
      </span>
      <span className="text-sm font-semibold tabular-nums">{v}</span>
      {hint && <span className="text-[11px] leading-tight text-amber-600 dark:text-amber-400">{hint}</span>}
    </div>
  );
}
