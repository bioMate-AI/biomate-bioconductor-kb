import { t, tOr } from "@/lib/i18n"
import { formatLabelText } from "./format-labels"
import type { DataProfile } from "@/components/data-perception"
import type { ViewKind } from "./dataset-view-model"

/**
 * A format label in the UI language: the client-side mapping keyed by `format.ext`
 * (format-labels.ts), falling back to the profiler's (English) label.
 */
export function localizedFormatLabel(format: { ext?: string; label: string }): string {
  return formatLabelText(format)
}

/** The human name of a data kind ("Table", "Sequencing reads", "Image") — shown instead of a MIME type. */
export function kindLabel(kind: ViewKind): string {
  return t(`dataset_obj.kind_${kind}`)
}

/** Generic storage MIME does not establish that a named JSON file is binary. */
export function datasetContentType(name: string, declared?: string | null): string {
  if (declared && declared !== "application/octet-stream") return declared
  const ext = name.split(".").pop()?.toLowerCase()
  return ({ json: "application/json", yaml: "application/yaml", yml: "application/yaml", csv: "text/csv", tsv: "text/tab-separated-values", txt: "text/plain", md: "text/markdown" } as Record<string, string>)[ext ?? ""] || declared || "—"
}

/**
 * Row/column count for the stat grid. Prefer a measured table `shape`, but
 * reconcile with the parsed preview (`columns` / `sampleRows`) that the
 * Table/Columns/Edit views already render — so the grid never shows "—" for a
 * small CSV those views clearly display (e.g. a header + 1 data row). Only
 * genuinely non-tabular profiles (no shape, no columns, no sample rows) → "—".
 */
export function datasetShape(profile?: DataProfile) {
  const shape = profile?.shape
  const cols = shape?.cols && shape.cols > 0 ? shape.cols : (profile?.columns?.length || undefined)
  const rows = shape && typeof shape.rows === "number" && cols != null
    ? shape.rows
    : (profile?.sampleRows?.length || undefined)
  if (rows == null && cols == null) return { rows: undefined, cols: undefined }
  return { rows: rows ?? undefined, cols: cols ?? undefined }
}

export function openInErrorMessage(body: { message?: unknown; error?: unknown }, tool: string, status: number) {
  const detail = typeof body.message === "string" ? body.message : typeof body.error === "string" ? body.error : ""
  if (detail && !/^Request failed with status code \d+$/.test(detail) && !/^[A-Za-z]+Error$/.test(detail)) return `${tool}: ${detail}`
  return tOr("dataset_obj.open_in_retry", "{{tool}} could not open this file ({{status}}). The file was not opened; try again or contact your workspace administrator if this continues.", { tool, status })
}

/** Stable reasons the edit route refuses a save for, by the code the server may send. */
const EDIT_ERROR_CODES: Record<string, string> = {
  version_conflict: "dataset_obj.edit_conflict_version",
  cell_conflict: "dataset_obj.edit_conflict_cell",
  too_large: "dataset_obj.edit_err_too_large",
  file_too_large: "dataset_obj.edit_err_too_large",
  not_utf8: "dataset_obj.edit_err_not_utf8",
  not_plain_text: "dataset_obj.edit_err_not_utf8",
  not_tabular: "dataset_obj.edit_err_not_editable",
  not_editable: "dataset_obj.edit_err_not_editable",
}

/**
 * The user-facing reason a cell edit was not saved. The server's stable code (`code`, or `error`
 * when it is a code) wins; otherwise the status names the reason: 409 the file / a cell changed,
 * 413 over the in-place-edit size limit, 422 not plain UTF-8, 415 a kind that is not edited in
 * place, 400 a request the server could not apply. Anything else keeps its status.
 */
export function editErrorMessage(status: number, body?: { code?: unknown; error?: unknown } | null): string {
  for (const c of [body?.code, body?.error]) {
    if (typeof c === "string" && EDIT_ERROR_CODES[c]) return t(EDIT_ERROR_CODES[c])
  }
  if (status === 409) return t("dataset_obj.edit_conflict")
  if (status === 413) return t("dataset_obj.edit_err_too_large")
  if (status === 422) return t("dataset_obj.edit_err_not_utf8")
  if (status === 415) return t("dataset_obj.edit_err_not_editable")
  if (status === 400) return t("dataset_obj.edit_err_bad_request")
  return t("dataset_obj.with_status", { message: t("dataset_obj.edit_failed"), status })
}
