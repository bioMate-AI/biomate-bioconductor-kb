/**
 * Columns view (design spec 04 §4.3) — "Per column: name, inferred type, % missing
 * with a bar, distinct count or a note, and a watch chip where something is wrong …
 * the view that makes a quality verdict arguable rather than mysterious."
 *
 * Stats are derived CLIENT-SIDE from the rows the caller passes — the FULL rows
 * paged in from GET /api/projects/:id/files/:fileId/rows (or the profiler sample
 * when no project rows are available). The note under the table states exactly
 * which rows they were computed on ("all N rows" vs "the n loaded rows of N"), so a
 * partial %-missing is never presented as the whole-file truth. A column is flagged "watch" only
 * when a structured profiler finding names THAT column as a problem (its `column`/`columns`
 * param — never a substring of free-text notes), or when many of its loaded cells are missing.
 * A header-only table still lists its columns, with "no data rows yet".
 */
import { findingText, type PerceptionFinding, type ProfileColumnStat } from "@/components/data-perception";
import { columnProblems } from "./dataset-view-model";
import { parseCellNumber } from "./dataset-sample-plot";

type TFn = (key: string, vars?: any) => string;

const MISSING_TOKENS = new Set(["", "na", "n/a", "nan", "null", "none", ".", "-"]);
const isMissing = (v: unknown): boolean =>
  v == null || (typeof v === "string" && MISSING_TOKENS.has(v.trim().toLowerCase()));

export type ColumnRole = NonNullable<ProfileColumnStat["role"]>;
const ROLES = new Set<ColumnRole>(["annotation", "identifier", "label", "constant"]);

export type ColumnStat = {
  name: string;
  type: "numeric" | "categorical" | "text" | "empty";
  missingPct: number;   // fraction 0..1, over the rows the stats cover
  present: number;      // non-missing cells
  distinct: number;     // distinct non-missing values
  allUnique: boolean;   // every present value distinct (≥2 present)
  watch: boolean;       // named by a problem finding (or, without the profiler's stats, high missing)
  watchFindings: PerceptionFinding[]; // the findings that name this column as a problem
  highMissing: boolean;
  /** Not an ordinary value column (identifier, tool-layout annotation, the group label, constant). */
  role?: ColumnRole;
  min?: number;
  max?: number;
  mean?: number;
  /** Who computed it: the backend profiler (`columnStats`) or the client over the loaded rows. */
  source: "profile" | "rows";
};

/**
 * Per-column stats. The profiler's `columnStats` win where they cover a column — they are parsed
 * with the table's decimal mark and carry the column's role, so an identifier or a tool layout's
 * annotation column is labelled as such and a column is "watch" only when a finding names it (the
 * backend applies its high-missing rule with the role in mind). A column the profiler did not
 * describe is computed here over the loaded rows (numbers read with `decimal`). Pure + testable.
 */
export function computeColumnStats(
  columns: string[],
  sampleRows: string[][],
  findings: PerceptionFinding[] = [],
  opts: { profileStats?: ProfileColumnStat[] | null; decimal?: string | null } = {},
): ColumnStat[] {
  const n = sampleRows.length;
  const problems = columnProblems(findings);
  const byName = new Map((opts.profileStats ?? []).filter((c) => c && typeof c.name === "string").map((c) => [c.name, c] as const));
  return columns.map((name, i) => {
    const named = problems.get(name) ?? [];
    const ps = opts.profileStats?.[i]?.name === name ? opts.profileStats[i] : byName.get(name);
    if (ps) {
      const total = (ps.present ?? 0) + (ps.missing ?? 0);
      const missingPct = total > 0 ? (ps.missing ?? 0) / total : 0;
      const role = ps.role && ROLES.has(ps.role) ? ps.role : undefined;
      return {
        name,
        type: ps.type,
        missingPct,
        present: ps.present ?? 0,
        distinct: ps.distinct ?? 0,
        allUnique: (ps.present ?? 0) >= 2 && ps.distinct === ps.present,
        watch: named.length > 0,
        watchFindings: named,
        highMissing: false,
        ...(role ? { role } : {}),
        ...(typeof ps.min === "number" ? { min: ps.min } : {}),
        ...(typeof ps.max === "number" ? { max: ps.max } : {}),
        ...(typeof ps.mean === "number" ? { mean: ps.mean } : {}),
        source: "profile" as const,
      };
    }
    const values = sampleRows.map((r) => (r ? r[i] : undefined));
    const present = values.filter((v) => !isMissing(v)) as string[];
    const missing = n - present.length;
    const distinctSet = new Set(present.map((v) => String(v)));
    const numericCount = present.filter((v) => Number.isFinite(parseCellNumber(String(v), opts.decimal))).length;
    let type: ColumnStat["type"];
    if (present.length === 0) type = "empty";
    else if (numericCount === present.length) type = "numeric";
    else if (distinctSet.size <= Math.max(2, Math.ceil(present.length / 2))) type = "categorical";
    else type = "text";
    // watch: a finding names this exact column as a problem, or >20% of the loaded cells are missing.
    const highMissing = n > 0 && missing / n > 0.2;
    return {
      name,
      type,
      missingPct: n > 0 ? missing / n : 0,
      present: present.length,
      distinct: distinctSet.size,
      allUnique: present.length >= 2 && distinctSet.size === present.length,
      watch: named.length > 0 || highMissing,
      watchFindings: named,
      highMissing,
      source: "rows" as const,
    };
  });
}

const fmtNum = (v: number) => v.toLocaleString(undefined, { maximumFractionDigits: 3 });

export function DatasetColumnsView({ columns, sampleRows, findings = [], totalRows, profileStats, profiledRows, decimal, t }: {
  columns: string[];
  sampleRows: string[][];
  /** The profiler's structured findings (a column is flagged only when one names it). */
  findings?: PerceptionFinding[];
  totalRows?: number;
  /** The profiler's per-column stats (`columnStats`), preferred where they cover a column. */
  profileStats?: ProfileColumnStat[] | null;
  /** Rows the profiler's stats cover when fewer than the file's (`profiledRows`). */
  profiledRows?: number | null;
  /** The table's decimal mark ("," → "1,5" is a number). */
  decimal?: string | null;
  t: TFn;
}) {
  const stats = computeColumnStats(columns, sampleRows, findings, { profileStats, decimal });
  const fromProfile = stats.length > 0 && stats.every((s) => s.source === "profile");
  // No data rows anywhere: not loaded here, and the profiler saw none either.
  const headerOnly = sampleRows.length === 0 && (totalRows == null || totalRows === 0)
    && !stats.some((s) => s.source === "profile" && s.present > 0);
  const showRange = stats.some((s) => typeof s.min === "number" && typeof s.max === "number");
  const typeLabel = (ty: ColumnStat["type"]) => t(`dataset_obj.col_type_${ty}`);
  return (
    <div className="space-y-1" data-testid="dataset-preview-columns">
      <div className="overflow-x-auto rounded border">
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr style={{ background: "var(--bm-accent-soft)" }}>
              <th className="px-2 py-1 text-left font-semibold border-b" style={{ color: "var(--bm-accent-ink)" }}>{t("dataset_obj.col_header_name")}</th>
              <th className="px-2 py-1 text-left font-semibold border-b" style={{ color: "var(--bm-accent-ink)" }}>{t("dataset_obj.col_header_type")}</th>
              <th className="px-2 py-1 text-left font-semibold border-b" style={{ color: "var(--bm-accent-ink)" }}>{t("dataset_obj.col_header_missing")}</th>
              <th className="px-2 py-1 text-left font-semibold border-b" style={{ color: "var(--bm-accent-ink)" }}>{t("dataset_obj.col_header_distinct")}</th>
              {showRange && <th className="px-2 py-1 text-left font-semibold border-b" style={{ color: "var(--bm-accent-ink)" }}>{t("dataset_obj.col_header_range")}</th>}
            </tr>
          </thead>
          <tbody>
            {stats.map((s, i) => (
              <tr key={i} className="odd:bg-muted/20" data-testid="dataset-column-row" data-watch={s.watch ? "true" : "false"}
                data-type={s.type} data-role={s.role ?? undefined} data-source={s.source}>
                <td className="whitespace-nowrap px-2 py-0.5 font-mono border-b">
                  {s.name}
                  {s.role && (
                    <span
                      className="ml-1.5 inline-flex items-center rounded px-1 py-0 font-sans text-fs-xs font-medium border border-border bg-muted text-muted-foreground"
                      data-testid="dataset-column-role"
                      data-role={s.role}
                      title={t(`dataset_obj.col_role_${s.role}_tip`)}
                    >{t(`dataset_obj.col_role_${s.role}`)}</span>
                  )}
                  {s.watch && (
                    <span
                      className="ml-1.5 inline-flex items-center rounded px-1 py-0 text-fs-xs font-medium border border-amber-500/40 bg-amber-500/10 text-amber-600 dark:text-amber-400"
                      data-testid="dataset-column-watch"
                      title={[...s.watchFindings.map((f) => findingText(f)), ...(s.highMissing ? [t("dataset_obj.col_watch_missing")] : [])].join("\n")}
                    >{t("dataset_obj.col_watch")}</span>
                  )}
                </td>
                <td className="whitespace-nowrap px-2 py-0.5 border-b text-muted-foreground">{headerOnly ? "—" : typeLabel(s.type)}</td>
                <td className="px-2 py-0.5 border-b">
                  {headerOnly ? <span className="text-muted-foreground">—</span> : <div className="flex items-center gap-1.5">
                    <div className="h-1.5 w-16 rounded bg-muted overflow-hidden" aria-hidden>
                      <div
                        className={s.missingPct > 0.2 ? "h-full bg-amber-500" : "h-full bg-sky-500/60"}
                        style={{ width: `${Math.round(s.missingPct * 100)}%` }}
                      />
                    </div>
                    <span className="text-xs tabular-nums text-muted-foreground">{Math.round(s.missingPct * 100)}%</span>
                  </div>}
                </td>
                <td className="whitespace-nowrap px-2 py-0.5 border-b text-muted-foreground tabular-nums">
                  {s.type === "empty" ? "—" : s.allUnique ? t("dataset_obj.col_all_unique") : s.distinct}
                </td>
                {showRange && (
                  <td className="whitespace-nowrap px-2 py-0.5 border-b text-muted-foreground tabular-nums" data-testid="dataset-column-range">
                    {typeof s.min === "number" && typeof s.max === "number"
                      ? t("dataset_obj.col_range", { min: fmtNum(s.min), max: fmtNum(s.max), mean: typeof s.mean === "number" ? fmtNum(s.mean) : "—" })
                      : "—"}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-muted-foreground" data-testid="dataset-columns-sample-note">
        {headerOnly
          ? t("dataset_obj.columns_header_only")
          : fromProfile
          ? profiledRows != null && totalRows != null && profiledRows < totalRows
            ? t("dataset_obj.columns_profiled_subset_note", { n: profiledRows.toLocaleString(), total: totalRows.toLocaleString() })
            : t("dataset_obj.columns_profiled_note", { total: (totalRows ?? sampleRows.length).toLocaleString() })
          : totalRows != null && sampleRows.length >= totalRows
          ? t("dataset_obj.columns_full_note", { total: totalRows.toLocaleString() })
          : t("dataset_obj.columns_loaded_note", {
              n: sampleRows.length.toLocaleString(),
              total: totalRows != null ? totalRows.toLocaleString() : "?",
            })}
      </p>
    </div>
  );
}
