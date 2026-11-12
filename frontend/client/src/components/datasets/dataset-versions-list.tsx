/**
 * DatasetVersionsList — the version rows of a dataset's Versions tab (R13 client side).
 *
 * - Author: the server's display name (`authorName`); a raw user id is never shown — when
 *   only an id is known the author is left out rather than printed as a UUID.
 * - Time: each row shows its own `createdAt` (the server owns which time that is).
 * - Note: an automatic note that only repeats the label ("v1") is not repeated.
 * - Compare: changed cells are numbered from 1 (data row 1 = the first row under the header);
 *   the diff API reports a 0-based `row`.
 * - Restore asks first: it writes a NEW current version with the old content (append-only).
 */
import { useState } from "react"
import { Badge } from "@/components/ui/badge"
import { t, locale } from "@/lib/i18n"
import type { DatasetVersion } from "./datasets-api"

const INTL_LOCALE = locale === "zh" ? "zh-CN" : "en-US"

export type VersionRow = Pick<DatasetVersion, "version" | "label" | "current" | "createdAt" | "note" | "author"> & {
  /** Display name of the author, resolved by the server. */
  authorName?: string | null
}

export interface VersionDiff {
  identical?: boolean
  tabular?: boolean
  truncated?: boolean
  target?: { size?: number }
  current?: { size?: number }
  columns?: { added?: string[]; removed?: string[] }
  /** `row` is the 0-based data row (header excluded); `rowNumber`, when sent, is already 1-based. */
  changedCells?: Array<{ row: number; rowNumber?: number; col: string; from: unknown; to: unknown }>
}

export interface DatasetVersionsListProps {
  versions: VersionRow[]
  /** Runs that consumed the current version. */
  usedByCount: number
  /** Project file versions can be compared / restored. */
  versionable: boolean
  error: string | null
  diffFor: string | null
  diffData: VersionDiff | null
  diffLoading: boolean
  restoringVersion: string | null
  onCompare: (version: string) => void
  onRestore: (version: string) => void
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** A name a person would recognize, or null. Ids (UUIDs, bare numbers) are never shown. */
export function authorLabel(v: Pick<VersionRow, "author" | "authorName">): string | null {
  const name = typeof v.authorName === "string" ? v.authorName.trim() : ""
  if (name) return name
  const raw = typeof v.author === "string" ? v.author.trim() : ""
  if (!raw || UUID_RE.test(raw) || /^\d+$/.test(raw)) return null
  return raw
}

/** 1-based row number of a changed cell. */
export function diffRowNumber(c: { row: number; rowNumber?: number }): number {
  return typeof c.rowNumber === "number" ? c.rowNumber : c.row + 1
}

function formatTime(createdAt: VersionRow["createdAt"]): string | null {
  if (createdAt == null || createdAt === "") return null
  const d = new Date(typeof createdAt === "number" ? createdAt * 1000 : createdAt)
  return Number.isNaN(d.getTime()) ? null : d.toLocaleString(INTL_LOCALE)
}

function shownValue(v: unknown): string {
  const s = v == null ? "" : String(v)
  return s === "" ? t("dataset_versions.empty_value") : s
}

export function DatasetVersionsList({
  versions, usedByCount, versionable, error, diffFor, diffData, diffLoading, restoringVersion, onCompare, onRestore,
}: DatasetVersionsListProps) {
  // The version whose Restore was clicked and awaits confirmation.
  const [confirmFor, setConfirmFor] = useState<string | null>(null)
  return (
    <>
      {error && <p className="text-xs text-destructive" data-testid="dataset-version-error">{error}</p>}
      {versions.map((v) => {
        const time = formatTime(v.createdAt)
        const author = authorLabel(v)
        const note = v.note && v.note.trim() !== v.label ? v.note : null
        return (
          <div
            key={v.version}
            className={`rounded border px-2 py-1.5 text-xs ${v.current ? "bg-primary/5 border-primary/40" : ""}`}
            data-testid={`dataset-version-${v.version}`}
          >
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
              <span className="font-mono font-semibold">{v.label}</span>
              {v.current && (
                <Badge variant="outline" className="text-xs">{t("dataset_obj.current")}</Badge>
              )}
              {v.current && usedByCount > 0 && (
                <span className="text-xs text-muted-foreground" data-testid="dataset-version-usedby">
                  {t("dataset_obj.used_by_runs", { n: usedByCount })}
                </span>
              )}
              {/* Compare this version against current (column + cell diff). */}
              {versionable && !v.current && (
                <button
                  type="button"
                  className="text-xs text-primary hover:underline disabled:opacity-50"
                  data-testid={`dataset-version-compare-${v.version}`}
                  disabled={diffLoading && diffFor === v.version}
                  aria-expanded={diffFor === v.version}
                  onClick={() => onCompare(v.version)}
                >{diffFor === v.version ? t("dataset_obj.compare_hide") : t("dataset_obj.compare")}</button>
              )}
              {/* Restore a past version (append-only — writes a new version). */}
              {versionable && !v.current && (
                <button
                  type="button"
                  className="text-xs text-primary hover:underline disabled:opacity-50"
                  data-testid={`dataset-version-restore-${v.version}`}
                  disabled={restoringVersion === v.version}
                  aria-expanded={confirmFor === v.version}
                  onClick={() => setConfirmFor(confirmFor === v.version ? null : v.version)}
                >{restoringVersion === v.version ? t("dataset_obj.restoring") : t("dataset_obj.restore")}</button>
              )}
              {time && (
                <span className="ml-auto text-xs text-muted-foreground tabular-nums" data-testid={`dataset-version-time-${v.version}`}>
                  {time}
                </span>
              )}
            </div>
            {versionable && !v.current && confirmFor === v.version && (
              <div role="group" className="mt-1.5 flex flex-wrap items-center gap-2 rounded border border-amber-500/40 bg-amber-500/5 p-2" data-testid={`dataset-version-restore-confirm-${v.version}`}>
                <span className="text-sm text-foreground">{t("dataset_obj.restore_confirm", { v: v.label })}</span>
                <button
                  type="button"
                  className="rounded border border-primary bg-primary px-2 py-0.5 text-xs text-primary-foreground"
                  data-testid={`dataset-version-restore-yes-${v.version}`}
                  onClick={() => { setConfirmFor(null); onRestore(v.version) }}
                >{t("dataset_obj.restore_confirm_yes", { v: v.label })}</button>
                <button
                  type="button"
                  className="rounded border px-2 py-0.5 text-xs"
                  data-testid={`dataset-version-restore-cancel-${v.version}`}
                  onClick={() => setConfirmFor(null)}
                >{t("actions.cancel")}</button>
              </div>
            )}
            {(note || author) && (
              <p className="text-sm text-foreground pt-0.5" data-testid={`dataset-version-meta-${v.version}`}>
                {note}
                {author && (
                  <span className="text-muted-foreground" data-testid={`dataset-version-author-${v.version}`}>
                    {note ? " — " : ""}{t("dataset_versions.by", { name: author })}
                  </span>
                )}
              </p>
            )}
            {diffFor === v.version && (
              <div className="mt-1.5 rounded border bg-muted/20 p-2 text-xs space-y-1" data-testid={`dataset-version-diff-${v.version}`}>
                {diffLoading ? (
                  <p className="text-muted-foreground">{t("dataset_obj.comparing")}</p>
                ) : diffData?.identical ? (
                  <p className="text-muted-foreground">{t("dataset_obj.diff_identical")}</p>
                ) : diffData?.tabular === false ? (
                  <p className="text-muted-foreground">{t("dataset_obj.diff_nontabular", { a: diffData?.target?.size ?? "?", b: diffData?.current?.size ?? "?" })}</p>
                ) : diffData ? (
                  <>
                    {(diffData.columns?.added?.length || diffData.columns?.removed?.length) ? (
                      <p>
                        {diffData.columns.added?.length ? <span className="text-emerald-600 dark:text-emerald-400">+{diffData.columns.added.join(", ")} </span> : null}
                        {diffData.columns.removed?.length ? <span className="text-red-600 dark:text-red-400 line-through">−{diffData.columns.removed.join(", ")}</span> : null}
                      </p>
                    ) : null}
                    <p className="text-muted-foreground" data-testid="dataset-diff-cellcount">
                      {t("dataset_obj.diff_changed_cells", { n: diffData.changedCells?.length ?? 0 })}
                      {diffData.truncated ? ` ${t("dataset_obj.diff_sampled")}` : ""}
                    </p>
                    {(diffData.changedCells ?? []).slice(0, 5).map((c, ci) => (
                      <p key={ci} className="font-mono text-fs-xs" data-testid="dataset-diff-cell">
                        <span className="text-muted-foreground" data-testid="dataset-diff-cell-where">
                          {t("dataset_versions.diff_row", { n: diffRowNumber(c) })} · {c.col}:{" "}
                        </span>
                        <span className="text-red-600 dark:text-red-400 line-through">{shownValue(c.from)}</span>
                        {" → "}
                        <span className="text-emerald-600 dark:text-emerald-400">{shownValue(c.to)}</span>
                      </p>
                    ))}
                  </>
                ) : null}
              </div>
            )}
          </div>
        )
      })}
    </>
  )
}
