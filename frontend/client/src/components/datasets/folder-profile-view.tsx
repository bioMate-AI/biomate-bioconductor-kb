/**
 * FolderProfileView — a project input folder as ONE object (data hub, selected folder).
 *
 * A folder upload is more than a container: paired FASTQs are samples (with orphans flagged
 * and an nf-core samplesheet ready to download), a 10x matrix + barcodes + features is one
 * matrix (cells × genes from the matrix header; the two TSVs are header-less by the 10x spec),
 * anything else is summarised by format. All of it is decided by the backend folder profiler
 * (galaxy/ai/folder_profile.py, pairing = Galaxy's auto_pairing); this view only renders it.
 * Finding texts are i18n `perception.msg.<code>` like the per-file QC card.
 */
import { Download, Folder } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { findingText, type PerceptionFinding } from "@/components/data-perception"
import { t, tOr } from "@/lib/i18n"
import { cn } from "@/lib/utils"
import { folderProfileUrl, useFolderProfile, type FolderProfile, type FolderSample } from "./datasets-api"
import { localizedFormatLabel } from "./dataset-presentation"

const base = (p: string | null | undefined) => (p ? p.split("/").pop() || p : "")

const STATUS_BADGE: Record<FolderSample["status"], string> = {
  paired: "border-emerald-500/40 text-emerald-700 dark:text-emerald-400",
  orphan: "border-amber-500/50 text-amber-700 dark:text-amber-400",
  single: "border-border text-muted-foreground",
}

const LEVEL_DOT: Record<string, string> = { info: "bg-sky-500", watch: "bg-amber-500", blocked: "bg-red-500" }

/** "12 files: 8 FASTQ (4 pairs), 2 CSV, 2 unrecognised" — localized parts. */
export function rollupText(p: Pick<FolderProfile, "fileCount" | "rollup">): string {
  const parts = p.rollup.map((r) => {
    const label = r.format === "unrecognised" ? t("folder_profile.unrecognised") : localizedFormatLabel({ ext: r.format, label: r.label })
    const pairs = typeof r.pairs === "number" && r.pairs > 0 ? t("folder_profile.rollup_pairs", { n: r.pairs }) : ""
    return t("folder_profile.rollup_part", { n: r.count, label, pairs })
  })
  return t("folder_profile.rollup", { n: p.fileCount, parts: parts.join(t("perception.list_sep")) })
}

export function FolderProfileView({ projectId, path, className }: { projectId: string; path: string; className?: string }) {
  const q = useFolderProfile(projectId, path)
  const name = path ? path : t("dataset_obj.inputs")
  const prof = q.data
  return (
    <Card className={cn("min-w-0", className)} data-testid="folder-profile" data-kind={prof?.kind ?? ""} data-path={path}>
      <CardHeader className="space-y-1 pb-2">
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <span>{t("dataset_obj.inputs")}</span>
          {path && <><span>/</span><span className="min-w-0 truncate" title={path}>{path}</span></>}
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <Folder className="h-4 w-4 text-yellow-500 shrink-0" />
          <CardTitle className="text-lg font-mono font-semibold min-w-0 [overflow-wrap:anywhere]" data-testid="folder-profile-name">
            {name}
          </CardTitle>
          {prof && (
            <Badge variant="outline" className="text-xs" data-testid="folder-profile-kind">
              {tOr(`folder_profile.kind_${prof.kind}`, prof.kind)}
            </Badge>
          )}
          {prof?.fastq && (
            <Badge variant="outline" className="text-xs" data-testid="folder-profile-verdict" data-verdict={prof.fastq.verdict}>
              {tOr(`folder_profile.verdict_${prof.fastq.verdict}`, prof.fastq.verdict)}
            </Badge>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {q.isLoading ? (
          <div className="space-y-2" data-testid="folder-profile-loading">
            <Skeleton className="h-4 w-56" />
            <Skeleton className="h-20 w-full" />
          </div>
        ) : q.isError || !prof || typeof prof.kind !== "string" || !Array.isArray(prof.rollup) ? (
          <p className="text-sm text-muted-foreground" data-testid="folder-profile-error">{t("folder_profile.error")}</p>
        ) : (
          <>
            <p className="text-sm text-foreground" data-testid="folder-rollup">{rollupText(prof)}</p>

            {(prof.findings ?? []).length > 0 && (
              <ul className="flex flex-col gap-1 rounded border p-2.5" data-testid="folder-findings">
                {prof.findings.map((f, i) => (
                  <li key={i} className="flex items-start gap-2 text-xs" data-testid="folder-finding" data-code={f.code} data-level={f.level}>
                    <span className={cn("mt-1 h-2 w-2 shrink-0 rounded-full", LEVEL_DOT[f.level] ?? LEVEL_DOT.info)} />
                    <span className="text-foreground [overflow-wrap:anywhere]">{findingText(f as unknown as PerceptionFinding)}</span>
                  </li>
                ))}
              </ul>
            )}

            {prof.fastq && prof.fastq.samples.length > 0 && (
              <div className="space-y-2" data-testid="folder-samples">
                <div className="flex items-center gap-2">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground flex-1">
                    {t("folder_profile.samples_heading", { n: prof.fastq.samples.length })}
                  </p>
                  {prof.samplesheet && (
                    <Button asChild variant="outline" size="sm" className="h-7 text-xs gap-1">
                      <a href={folderProfileUrl(projectId, path, true)} download={prof.samplesheet.filename}
                         data-testid="folder-samplesheet-download" title={t("folder_profile.samplesheet_tip")}>
                        <Download className="h-3 w-3" />{t("folder_profile.samplesheet_download")}
                      </a>
                    </Button>
                  )}
                </div>
                <div className="overflow-x-auto rounded border">
                  <table className="w-full text-xs">
                    <thead className="bg-muted/40 text-muted-foreground">
                      <tr>
                        <th className="px-2 py-1 text-left font-medium">{t("folder_profile.col_sample")}</th>
                        <th className="px-2 py-1 text-left font-medium">{t("folder_profile.col_read1")}</th>
                        <th className="px-2 py-1 text-left font-medium">{t("folder_profile.col_read2")}</th>
                        <th className="px-2 py-1 text-left font-medium">{t("folder_profile.col_status")}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {prof.fastq.samples.map((s, i) => {
                        const file = s.forward || s.reverse
                        return (
                          <tr key={`${s.sample}-${i}`} className="border-t" data-testid={`folder-sample-row-${s.sample}`} data-status={s.status}>
                            <td className="px-2 py-1 font-mono">{s.sample}</td>
                            <td className="px-2 py-1 font-mono [overflow-wrap:anywhere]" title={s.forward ?? ""}>{base(s.forward) || "—"}</td>
                            <td className="px-2 py-1 font-mono [overflow-wrap:anywhere]" title={s.reverse ?? ""}>{base(s.reverse) || "—"}</td>
                            <td className="px-2 py-1">
                              <span
                                className={cn("inline-flex rounded-full border px-1.5 py-0.5", STATUS_BADGE[s.status])}
                                data-testid={s.status === "orphan" ? `folder-orphan-${base(file)}` : `folder-status-${s.sample}`}
                                title={s.status === "orphan" ? t("folder_profile.orphan_tip", { missing: s.role === "reverse" ? "1" : "2" }) : undefined}
                              >
                                {t(`folder_profile.status_${s.status}`)}
                              </span>
                            </td>
                          </tr>
                        )
                      })}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {prof.tenx && prof.tenx.sets.length > 0 && (
              <div className="space-y-2" data-testid="folder-tenx">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{t("folder_profile.tenx_heading")}</p>
                {prof.tenx.sets.map((s) => (
                  <div key={`${s.dir}/${s.prefix ?? ""}`} className="rounded border p-2.5 space-y-1" data-testid={`folder-tenx-set-${s.dir || "."}`} data-complete={String(s.complete)}>
                    <div className="flex items-center gap-2 flex-wrap text-sm">
                      <span className="font-mono">{s.dir || "."}{s.prefix ? ` · ${s.prefix}` : ""}</span>
                      {s.version && <Badge variant="secondary" className="text-xs">{t(`folder_profile.tenx_${s.version}`)}</Badge>}
                      <span className="ml-auto font-semibold" data-testid="folder-tenx-dims">
                        {typeof s.cells === "number" && typeof s.genes === "number"
                          ? t("folder_profile.tenx_dims", { cells: s.cells.toLocaleString(), genes: s.genes.toLocaleString() })
                          : t("folder_profile.tenx_dims_unknown")}
                      </span>
                    </div>
                    <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-xs">
                      {(["matrix", "barcodes", "features"] as const).map((r) => (
                        <div key={r} className="contents">
                          <dt className="text-muted-foreground">{t(`folder_profile.tenx_part_${r}`)}</dt>
                          <dd className="font-mono [overflow-wrap:anywhere]">{base(s[r]) || t("folder_profile.tenx_missing")}</dd>
                        </div>
                      ))}
                    </dl>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}
