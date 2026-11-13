/**
 * FoldOutputs — renders a completed Boltz-2 fold's result INLINE in the Models
 * panel, so a clinic user never has to leave for the Run Manager to see what
 * came out. Reads /api/workflows/runs/{id}/output_files, then:
 *
 *   • headline confidence (pTM / ipTM / pLDDT / confidence score) parsed from the
 *     Boltz confidence_*.json — the real, measured result, not a placeholder;
 *   • a prominent download for the predicted structure (.cif / .pdb);
 *   • the full artifact list with download links.
 *
 * No value is fabricated: if the confidence file is absent/unparseable we show
 * the files only. Each file downloads through /api/runs/:id/output/:name.
 */

import { useEffect, useState } from "react"
import { Download, FileText, Boxes, Loader2 } from "lucide-react"
import { t } from "@/lib/i18n"
import { Badge } from "@/components/ui/badge"
import { formatBytes } from "@/components/code-execution-block"
import { useRunOutputs, type RunOutputFile } from "./models-api"

/** Canonical, auth'd download path for a run's output file. */
function hrefFor(runId: string, f: RunOutputFile): string {
  return f.download_endpoint || f.downloadUrl || f.download_url
    || `/api/runs/${encodeURIComponent(runId)}/output/${encodeURIComponent(f.name)}`
}

const isStructure = (n: string) => /\.(cif|mmcif|pdb)$/i.test(n)
const isConfidence = (n: string) => /^confidence.*\.json$/i.test(n) || /(^|_)confidence(_|\.)/i.test(n)
const isNoise = (n: string) =>
  /\.(a3m|m8|sh)$/i.test(n) || /\.tar\.gz$/i.test(n) || /^(bfd|uniref|pdb70|msa)\b/i.test(n)

/** The subset of Boltz confidence keys we surface, each 0–1 (shown as %). */
const CONF_KEYS: Array<{ key: string; label: string }> = [
  { key: "confidence_score", label: "confidence" },
  { key: "ptm", label: "pTM" },
  { key: "iptm", label: "ipTM" },
  { key: "complex_plddt", label: "pLDDT" },
]

function parseConfidence(doc: unknown): Array<{ label: string; value: number }> {
  if (!doc || typeof doc !== "object") return []
  const d = doc as Record<string, unknown>
  const out: Array<{ label: string; value: number }> = []
  for (const { key, label } of CONF_KEYS) {
    const v = d[key]
    if (typeof v === "number" && Number.isFinite(v)) out.push({ label, value: v })
  }
  return out
}

export function FoldOutputs({ runId }: { runId: string }) {
  const { data: files, isLoading, isError } = useRunOutputs(runId, true)
  const [conf, setConf] = useState<Array<{ label: string; value: number }> | null>(null)

  // Fetch + parse the confidence JSON (small) to show the headline result.
  useEffect(() => {
    let cancelled = false
    const cf = (files || []).find((f) => isConfidence(f.name))
    if (!cf) { setConf(null); return }
    fetch(hrefFor(runId, cf), { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((doc) => { if (!cancelled) setConf(parseConfidence(doc)) })
      .catch(() => { if (!cancelled) setConf(null) })
    return () => { cancelled = true }
  }, [files, runId])

  if (isLoading) {
    return (
      <p className="flex items-center gap-1 text-fs-xs text-muted-foreground" data-testid="fold-outputs-loading">
        <Loader2 className="h-3 w-3 animate-spin" /> {t("models.fold_outputs_loading")}
      </p>
    )
  }
  if (isError || !files || files.length === 0) {
    return <p className="text-fs-xs text-muted-foreground" data-testid="fold-outputs-empty">{t("models.fold_outputs_empty")}</p>
  }

  const structure = files.find((f) => isStructure(f.name))
  // Show meaningful artifacts first; hide MSA/db intermediates behind the list.
  const listed = files.filter((f) => !isNoise(f.name))

  return (
    <div className="space-y-2" data-testid="fold-outputs">
      {/* Headline confidence — the measured result, inline. */}
      {conf && conf.length > 0 && (
        <div className="flex flex-wrap items-center gap-1.5" data-testid="fold-confidence">
          <span className="text-fs-xs text-muted-foreground">{t("models.fold_confidence_label")}</span>
          {conf.map((c) => (
            <Badge key={c.label} variant="outline" className="text-fs-xs tabular-nums" data-testid="fold-confidence-metric">
              {c.label} {c.value <= 1 ? `${(c.value * 100).toFixed(0)}%` : c.value.toFixed(2)}
            </Badge>
          ))}
        </div>
      )}

      {/* Predicted structure — the primary artifact, prominent. */}
      {structure && (
        <a
          href={hrefFor(runId, structure)}
          download={structure.name}
          className="flex items-center gap-2 rounded border bg-muted/40 px-2 py-1.5 text-xs hover:bg-muted"
          data-testid="fold-structure-download"
        >
          <Boxes className="h-4 w-4 shrink-0 text-primary" />
          <span className="min-w-0 flex-1 truncate font-medium">{t("models.fold_structure")}</span>
          <span className="shrink-0 font-mono text-fs-xs text-muted-foreground">{structure.name}</span>
          <Download className="h-3.5 w-3.5 shrink-0 text-primary" />
        </a>
      )}

      {/* All artifacts, each downloadable in-panel. */}
      <ul className="divide-y divide-border rounded border" data-testid="fold-outputs-list">
        {listed.map((f) => (
          <li key={f.name} className="flex items-center gap-2 px-2 py-1 text-fs-xs" data-testid="fold-output-file">
            <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            <span className="min-w-0 flex-1 truncate font-mono">{f.name}</span>
            {typeof f.size === "number" && f.size > 0 && (
              <span className="shrink-0 tabular-nums text-muted-foreground">{formatBytes(f.size)}</span>
            )}
            <a href={hrefFor(runId, f)} download={f.name} className="shrink-0 text-primary"
              aria-label={t("models.fold_download")} data-testid="fold-output-download">
              <Download className="h-3.5 w-3.5" />
            </a>
          </li>
        ))}
      </ul>
    </div>
  )
}
