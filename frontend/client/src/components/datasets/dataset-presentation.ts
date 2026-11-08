import { tOr } from "@/lib/i18n"
import type { DataProfile } from "@/components/data-perception"

/** Generic storage MIME does not establish that a named JSON file is binary. */
export function datasetContentType(name: string, declared?: string | null): string {
  if (declared && declared !== "application/octet-stream") return declared
  const ext = name.split(".").pop()?.toLowerCase()
  return ({ json: "application/json", yaml: "application/yaml", yml: "application/yaml", csv: "text/csv", tsv: "text/tab-separated-values", txt: "text/plain", md: "text/markdown" } as Record<string, string>)[ext ?? ""] || declared || "—"
}

/** Legacy 0×0 for unprofiled text/binary is unknown, not a measured empty table. */
export function datasetShape(profile?: DataProfile) {
  const shape = profile?.shape
  if (!shape || (shape.rows === 0 && shape.cols === 0 && !profile?.columns?.length)) return { rows: undefined, cols: undefined }
  return { rows: shape.rows, cols: shape.cols }
}

export function openInErrorMessage(body: { message?: unknown; error?: unknown }, tool: string, status: number) {
  const detail = typeof body.message === "string" ? body.message : typeof body.error === "string" ? body.error : ""
  if (detail && !/^Request failed with status code \d+$/.test(detail) && !/^[A-Za-z]+Error$/.test(detail)) return `${tool}: ${detail}`
  return tOr("dataset_obj.open_in_retry", "{{tool}} could not open this file ({{status}}). The file was not opened; try again or contact your workspace administrator if this continues.", { tool, status })
}
