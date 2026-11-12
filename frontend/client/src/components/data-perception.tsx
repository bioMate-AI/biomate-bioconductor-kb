/**
 * DataPerception — the dataset QC card ("what we saw in your data").
 *
 * Answers two user questions:
 *   1. "What did you see in my data?"  — shape, leakage, effective N,
 *      class balance, signal summary — and WHY the verdict is Watch/Blocked.
 *   2. "How did that shape the plan?"  — e.g. "single FASTQ → single-end pipeline".
 *
 * Presentational only: the numbers come from the backend profiler
 * (backend/lib/galaxy/ai/data_perception.py) and are never fabricated here.
 *
 * Language: every visible string goes through i18n (`perception.*`). The profiler
 * emits each note/signal/leakage/plan line twice — as legacy free text AND as a
 * structured finding {section, code, level, params}; the card renders the
 * structured findings via `perception.msg.<code>`, so a Chinese UI never shows
 * the profiler's English sentences. Only a profile from an older backend (no
 * `findings`) falls back to the free text.
 */

import { AlertTriangle, CheckCircle2, XCircle, Eye, ArrowRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { t, tOr } from "@/lib/i18n";

// ---------------------------------------------------------------------------
// Types — the shape the backend profiler emits (DataProfile.to_dict()).
// ---------------------------------------------------------------------------

export type PerceptionQuality = "good" | "watch" | "blocked";

export interface ClassBalanceEntry {
  /** Class / group label as it appears in the data. */
  label: string;
  /** Fraction of rows in this class, in [0, 1]. */
  frac: number;
}

export interface LeakageFinding {
  /** Free-text detail (legacy; the UI renders the structured findings instead). */
  detail: string;
}

/** One structured, localizable profiler finding. */
export interface PerceptionFinding {
  section: "note" | "signal" | "leakage" | "plan";
  /** i18n code — rendered as `perception.msg.<code>` (plan effects: `<code>_effect`). */
  code: string;
  /** "info" | "watch" | "blocked" — findings at the verdict's level are its reasons. */
  level: "info" | "watch" | "blocked";
  params?: Record<string, unknown>;
}

/** Which reduction bound effective N. The profiler emits "dedup" | "imbalance". */
export type EffectiveNReason = "dedup" | "imbalance" | "correlation";

export interface DataProfile {
  /** Raw shape the profiler observed (rows = the TRUE row count). */
  shape: { rows: number; cols: number };
  structured?: { format: string; root: string; nodes: number; keys: number; nulls: number; depth: number };
  /** Suspected data-leakage finding, if any. */
  leakage?: LeakageFinding;
  /** Effective sample size after de-duplication / imbalance. */
  effectiveN?: number;
  /** Why effective N is what it is (drives the hint under the stat). */
  effectiveNReason?: EffectiveNReason;
  /** Exact duplicate rows among the profiled rows. */
  duplicateRows?: number;
  /** Rows the statistics were computed on, when fewer than shape.rows. */
  profiledRows?: number;
  /** Class-balance breakdown (ordered as the profiler emitted it). */
  classBalance?: ClassBalanceEntry[];
  /** Numeric-first signal summary lines (legacy free text). */
  signalSummary?: string[];
  /** Overall ingest-quality verdict. */
  quality: PerceptionQuality;
  /** Free-text perception notes (legacy free text). */
  notes: string[];
  /** Structured, localizable findings (preferred over the free-text fields). */
  findings?: PerceptionFinding[];
  /** The file's format (format chip): Galaxy datatype ext when Galaxy identified it, else BioMate's. */
  format?: { ext: string; label: string; source: "galaxy" | "biomate" };
  /** Column headers of a table-like dataset (capped), for the Preview tab. */
  columns?: string[];
  /** First rows of a table-like dataset (capped), for the Preview tab. */
  sampleRows?: string[][];
  /** Detected file format (absent on profiles from older backends). */
  format?: DatasetFormat;
}

/** A dataset's detected format: `source` says who identified it — Galaxy's datatype
 *  registry ("galaxy") or BioMate's own sniffing ("biomate"). */
export interface DatasetFormat {
  ext: string;
  label: string;
  source: "galaxy" | "biomate";
}

export interface DataPerceptionProps {
  /** The profile emitted by the backend perception profiler. */
  profile: DataProfile;
  /** Legacy free-text cause → effect lines (used only when `findings` is absent). */
  planImpact?: { observed: string; effect: string }[];
  /** Optional dataset name for the header crumb. */
  datasetName?: string;
  className?: string;
}

// ---------------------------------------------------------------------------
// Quality vocabulary
// ---------------------------------------------------------------------------

const QUALITY_META: Record<
  PerceptionQuality,
  { icon: typeof CheckCircle2; badge: string; dot: string; panel: string }
> = {
  good: {
    icon: CheckCircle2,
    badge: "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
    dot: "bg-emerald-500",
    panel: "",
  },
  watch: {
    icon: AlertTriangle,
    badge: "border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400",
    dot: "bg-amber-500",
    panel: "border-amber-500/30 bg-amber-500/5",
  },
  blocked: {
    icon: XCircle,
    badge: "border-red-500/30 bg-red-500/10 text-red-600 dark:text-red-400",
    dot: "bg-red-500",
    panel: "border-red-500/30 bg-red-500/5",
  },
};

function fmtInt(n: number): string {
  return n.toLocaleString("en-US");
}

function fmtPct(frac: number): string {
  return `${(frac * 100).toFixed(frac < 0.1 ? 1 : 0)}%`;
}

/** Turn a finding's params into i18n vars: numbers grouped, lists joined with the
 *  locale's separator, `at_least` → a "≥" prefix, structural roots translated. */
function findingVars(f: PerceptionFinding): Record<string, string | number> {
  const vars: Record<string, string | number> = { prefix: "" };
  for (const [k, v] of Object.entries(f.params ?? {})) {
    if (k === "at_least") vars.prefix = v ? "≥" : "";
    else if (Array.isArray(v)) vars[k] = v.map(String).join(t("perception.list_sep"));
    else if (typeof v === "number") vars[k] = Number.isInteger(v) ? fmtInt(v) : String(v);
    else if (k === "root" && typeof v === "string") vars[k] = tOr(`perception.root_${v}`, v);
    else if (v != null) vars[k] = String(v);
  }
  return vars;
}

/** Localized text of a finding; an unknown code (newer backend) shows its code, never English prose. */
export function findingText(f: PerceptionFinding, suffix = ""): string {
  return tOr(`perception.msg.${f.code}${suffix}`, f.code, findingVars(f));
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
  const structuredMode = Array.isArray(profile.findings);
  const findings = profile.findings ?? [];

  // "Why Watch / Blocked": the findings at the verdict's level are its reasons.
  const reasons = profile.quality === "good"
    ? []
    : findings.filter((f) => f.level === profile.quality && f.section !== "plan");
  const isReason = (f: PerceptionFinding) => reasons.includes(f);
  const signalItems = findings.filter((f) => f.section === "signal" && !isReason(f));
  const noteItems = findings.filter((f) => f.section === "note" && !isReason(f));
  const leakageItems = findings.filter((f) => f.section === "leakage" && !isReason(f));
  const planItems = findings.filter((f) => f.section === "plan");

  const hasClassBalance = !!profile.classBalance && profile.classBalance.length > 0;

  // For sequence files the profiler's shape.rows/cols are reads × read-length,
  // not table rows/columns — label them accordingly.
  const nm = (datasetName || "").toLowerCase();
  const isFastq = /\.(fastq|fq)(\.gz)?$/.test(nm);
  const isFasta = /\.(fasta|fa|fna|faa)(\.gz)?$/.test(nm);
  const rowLabel = t(isFastq ? "perception.stat_reads" : isFasta ? "perception.stat_sequences" : "perception.stat_rows");
  const colLabel = t(isFastq ? "perception.stat_read_length" : isFasta ? "perception.stat_length" : "perception.stat_columns");

  // Effective-N hint states the REAL reason the backend reported — never a generic guess.
  const effBase = profile.profiledRows ?? profile.shape.rows;
  const effHints: string[] = [];
  if (typeof profile.effectiveN === "number" && profile.effectiveN < effBase) {
    if (profile.effectiveNReason === "dedup") {
      effHints.push(t("perception.effn_hint_dedup", {
        dup: fmtInt(profile.duplicateRows ?? effBase - profile.effectiveN),
      }));
    } else if (profile.effectiveNReason === "imbalance") {
      effHints.push(t("perception.effn_hint_imbalance"));
    } else if (profile.effectiveNReason === "correlation") {
      effHints.push(t("perception.effn_hint_correlation"));
    }
  }
  if (typeof profile.effectiveN === "number" && profile.profiledRows != null) {
    effHints.push(t("perception.effn_hint_subset", { n: fmtInt(profile.profiledRows) }));
  }

  const legacyNotes = !structuredMode ? profile.notes : [];
  const legacySignal = !structuredMode ? profile.signalSummary ?? [] : [];
  const legacyPlan = !structuredMode ? planImpact ?? [] : [];
  const whyTitle = t(profile.quality === "blocked" ? "perception.why_blocked" : "perception.why_watch");

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
        <div className="flex min-w-0 flex-col gap-0.5">
          <div className="text-sm font-semibold leading-tight">{t("perception.title")}</div>
          {datasetName && (
            <div className="font-mono text-xs text-muted-foreground [overflow-wrap:anywhere]">{datasetName}</div>
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
          {t(`perception.quality_${profile.quality}`)}
        </span>
      </div>

      {/* Shape + effective-N stat strip */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {profile.structured ? <>
          <Stat k={t("perception.stat_format")} v={profile.structured.format} />
          <Stat k={t("perception.stat_root")} v={tOr(`perception.root_${profile.structured.root}`, profile.structured.root)} />
          <Stat k={t("perception.stat_values")} v={fmtInt(profile.structured.nodes)} />
          <Stat k={t("perception.stat_keys")} v={fmtInt(profile.structured.keys)} />
          <Stat k={t("perception.stat_nulls")} v={fmtInt(profile.structured.nulls)} />
          <Stat k={t("perception.stat_depth")} v={fmtInt(profile.structured.depth)} />
        </> : <>
          <Stat k={rowLabel} v={fmtInt(profile.shape.rows)} />
          <Stat k={colLabel} v={fmtInt(profile.shape.cols)} />
        </>}
        {typeof profile.effectiveN === "number" && (
          <Stat
            k={t("perception.stat_effective_n")}
            v={fmtInt(profile.effectiveN)}
            hints={effHints}
            testId="perception-effective-n"
            wide={effHints.length > 0}
          />
        )}
      </div>

      {/* Why Watch / Blocked — the signals that set the verdict. */}
      {structuredMode && profile.quality !== "good" && (
        <div data-testid="perception-why" className={cn("flex flex-col gap-1.5 rounded-lg border p-3", q.panel)}>
          <div className="text-xs font-semibold text-foreground">{whyTitle}</div>
          {reasons.length > 0 ? (
            <ul className="flex flex-col gap-1">
              {reasons.map((f, i) => (
                <li key={i} className="flex items-start gap-2 text-xs" data-testid="perception-why-item" data-code={f.code}>
                  <span className={cn("mt-1 h-2 w-2 shrink-0 rounded-full", q.dot)} />
                  <span className="text-foreground [overflow-wrap:anywhere]">{findingText(f)}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-xs text-muted-foreground">{t("perception.why_unspecified")}</p>
          )}
        </div>
      )}

      {/* Leakage callout (info-level leakage, or a legacy profile's free text) */}
      {(leakageItems.length > 0 || (!structuredMode && profile.leakage)) && (
        <div
          data-testid="perception-leakage"
          className="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 text-xs"
        >
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-500" aria-hidden />
          <div>
            <span className="font-semibold text-amber-600 dark:text-amber-400">
              {t("perception.section_leakage")}{" "}
            </span>
            <span className="text-foreground">
              {structuredMode ? leakageItems.map((f) => findingText(f)).join(" ") : profile.leakage!.detail}
            </span>
          </div>
        </div>
      )}

      {/* Class balance */}
      {hasClassBalance && (
        <div className="flex flex-col gap-2" data-testid="perception-class-balance">
          <div className="text-xs font-semibold text-muted-foreground">{t("perception.section_class_balance")}</div>
          <div className="flex flex-col gap-1.5">
            {profile.classBalance!.map((c, i) => (
              <div key={`${c.label}-${i}`} className="flex items-center gap-2">
                <span className="w-28 shrink-0 truncate font-mono text-xs" title={c.label}>
                  {c.label}
                </span>
                <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                  <div
                    className={cn("h-full rounded-full", c.frac < 0.1 ? "bg-amber-500" : "bg-primary")}
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

      {/* Signal summary */}
      {(signalItems.length > 0 || legacySignal.length > 0) && (
        <Section title={t("perception.section_signal")} testId="perception-signal"
          lines={structuredMode ? signalItems.map((f) => findingText(f)) : legacySignal} />
      )}

      {/* Notes */}
      {(noteItems.length > 0 || legacyNotes.length > 0) && (
        <Section title={t("perception.section_notes")} testId="perception-notes"
          lines={structuredMode ? noteItems.map((f) => findingText(f)) : legacyNotes} />
      )}

      {/* How it shaped the plan */}
      {(planItems.length > 0 || legacyPlan.length > 0) && (
        <div className="flex flex-col gap-2 border-t border-card-border pt-3" data-testid="perception-plan-impact">
          <div className="text-xs font-semibold text-muted-foreground">{t("perception.section_plan")}</div>
          <div className="flex flex-col gap-1.5">
            {(structuredMode
              ? planItems.map((f) => ({ observed: findingText(f), effect: findingText(f, "_effect") }))
              : legacyPlan
            ).map((p, i) => (
              <div key={i} className="flex flex-wrap items-center gap-1.5 text-xs">
                <span className="rounded bg-muted px-1.5 py-0.5 font-medium text-foreground">{p.observed}</span>
                <ArrowRight className="h-3 w-3 shrink-0 text-muted-foreground" aria-hidden />
                <span className="text-muted-foreground">{p.effect}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function Section({ title, lines, testId }: { title: string; lines: string[]; testId: string }) {
  return (
    <div className="flex flex-col gap-1.5" data-testid={testId}>
      <div className="text-xs font-semibold text-muted-foreground">{title}</div>
      <ul className="flex flex-col gap-1">
        {lines.map((s, i) => (
          <li key={i} className="flex items-start gap-2 text-xs">
            <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-muted-foreground/60" />
            <span className="text-foreground [overflow-wrap:anywhere]">{s}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function Stat({
  k,
  v,
  hints,
  testId,
  wide,
}: {
  k: string;
  v: string;
  hints?: string[];
  testId?: string;
  /** Span two columns so a reason hint wraps on readable lines instead of being cropped. */
  wide?: boolean;
}) {
  return (
    <div className={cn("flex min-w-0 flex-col gap-0.5", wide && "col-span-2")} data-testid={testId}>
      <span className="text-fs-xs font-medium uppercase tracking-wide text-muted-foreground">{k}</span>
      <span className="text-sm font-semibold tabular-nums">{v}</span>
      {hints?.map((h, i) => (
        <span
          key={i}
          className="whitespace-normal text-fs-xs leading-snug text-amber-600 [overflow-wrap:anywhere] dark:text-amber-400"
          data-testid="perception-effective-n-hint"
        >
          {h}
        </span>
      ))}
    </div>
  );
}
