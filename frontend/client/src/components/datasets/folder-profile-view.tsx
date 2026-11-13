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
import { Download, Folder, Play } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { ProfileErrorState } from "./profile-error"
import { Skeleton } from "@/components/ui/skeleton"
import { findingText, pathBaseText, type PerceptionFinding } from "@/components/data-perception"
import { t, tOr } from "@/lib/i18n"
import { cn } from "@/lib/utils"
import { analyzeFolderChatUrl } from "@/lib/folder-as-input"
import { folderProfileUrl, useFolderProfile, type FolderProfile, type FolderSample } from "./datasets-api"
import { kindLabel, localizedFormatLabel } from "./dataset-presentation"
import { VIEW_KINDS, type ViewKind } from "./dataset-view-model"
import { breakAtSeparators } from "./name-breaks"

const base = (p: string | null | undefined) => (p ? p.split("/").pop() || p : "")

const STATUS_BADGE: Record<FolderSample["status"], string> = {
  paired: "border-emerald-500/40 text-emerald-700 dark:text-emerald-400",
  orphan: "border-amber-500/50 text-amber-700 dark:text-amber-400",
  single: "border-border text-muted-foreground",
}

const LEVEL_DOT: Record<string, string> = { info: "bg-sky-500", watch: "bg-amber-500", blocked: "bg-red-500" }

type RollupEntry = FolderProfile["rollup"][number]
const isViewKind = (v: unknown): v is ViewKind => typeof v === "string" && (VIEW_KINDS as readonly string[]).includes(v)

/** One roll-up entry, localized: "2 featureCounts 计数表", "8 FASTQ · pairs: 4". The label is the
 *  backend's (each file's own content decision), translated like the format chip. */
export function rollupPartText(r: RollupEntry): string {
  const label = r.format === "unrecognised" ? t("folder_profile.unrecognised") : localizedFormatLabel({ ext: r.format, label: r.label })
  const pairs = typeof r.pairs === "number" && r.pairs > 0 ? t("folder_profile.rollup_pairs", { n: r.pairs }) : ""
  return t("folder_profile.rollup_part", { n: r.count, label, pairs })
}

/** "12 files: 8 FASTQ (4 pairs), 2 CSV, 2 unrecognised" — localized parts. */
export function rollupText(p: Pick<FolderProfile, "fileCount" | "rollup">): string {
  return t("folder_profile.rollup", { n: p.fileCount, parts: p.rollup.map(rollupPartText).join(t("perception.list_sep")) })
}

/** The roll-up sentence with each entry tagged by its format and view kind (the kind's name on hover). */
function Rollup({ prof }: { prof: FolderProfile }) {
  const [head, tail] = t("folder_profile.rollup", { n: prof.fileCount, parts: "\u0000" }).split("\u0000")
  return (
    <p className="text-sm text-foreground" data-testid="folder-rollup">
      {head}
      {prof.rollup.map((r, i) => (
        <span key={i}>
          {i > 0 ? t("perception.list_sep") : ""}
          <span data-testid="folder-rollup-part" data-format={r.format} data-view-kind={isViewKind(r.viewKind) ? r.viewKind : undefined}
            title={isViewKind(r.viewKind) ? kindLabel(r.viewKind) : undefined}>{rollupPartText(r)}</span>
        </span>
      ))}
      {tail}
    </p>
  )
}

/** The folder's kind badge: "MAGeCK counts files" for a single-format folder, never "Mixed formats". */
export function folderKindText(p: Pick<FolderProfile, "kind" | "kindFormat">): string {
  if (p.kind === "single_format" && p.kindFormat?.label) {
    return t("folder_profile.kind_single_format", { label: localizedFormatLabel({ ext: p.kindFormat.format, label: p.kindFormat.label }) })
  }
  return tOr(`folder_profile.kind_${p.kind}`, p.kind)
}

const PATTERN_KEYS = new Set(["Rs", "illumina", "dot12s"])
const MAX_EXCLUDED_SHOWN = 8

/** "<folder>_<name>" — the same download name the server gives the paired sheet (project-folders.ts). */
function sheetDownloadName(folder: string, filename: string): string {
  const leaf = folder.split("/").filter(Boolean).pop() || "inputs"
  return `${leaf.replace(/[^A-Za-z0-9._-]/g, "_")}_${filename}`
}
const csvHref = (csv: string) => `data:text/csv;charset=utf-8,${encodeURIComponent(csv)}`

/**
 * Folder findings the FASTQ samples section already states, by code and params (never text) — each
 * folder fact once: the sample table's badge for a missing mate, the excluded note for the files
 * left out of the paired sheet, the pattern line for how pairs were named, the paths line for the
 * samplesheet. Only when that section is drawn (it is for any FASTQ samples); never another finding.
 */
export function findingsShownBySamples(prof: FolderProfile): ReadonlySet<FolderProfile["findings"][number]> {
  const out = new Set<FolderProfile["findings"][number]>()
  const fq = prof.fastq
  if (!fq || fq.samples.length === 0) return out
  const orphanFiles = new Set(fq.samples.filter((s) => s.status === "orphan").map((s) => base(s.forward || s.reverse)))
  const orphanSamples = new Set(fq.samples.filter((s) => s.status === "orphan").map((s) => s.sample))
  const excluded = new Set((prof.samplesheet?.excluded ?? []).slice(0, MAX_EXCLUDED_SHOWN).map((x) => base(x)))
  const patternLine = (fq.patterns ?? []).some((x) => PATTERN_KEYS.has(x))
  const pathsLine = Boolean(prof.samplesheet && (prof.samplesheet.layout || prof.samplesheet.pathBase))
  for (const f of prof.findings ?? []) {
    const p = (f.params ?? {}) as Record<string, unknown>
    const names = Array.isArray(p.names) ? p.names.map((x) => base(String(x))) : []
    if (f.code === "folder_fastq_orphan" && (orphanFiles.has(base(String(p.name ?? ""))) || orphanSamples.has(String(p.sample ?? "")))) out.add(f)
    // The mixed layout = the header's "Paired + unpaired" badge, and its consequence (the unpaired
    // files go to their own sheet) is the excluded note.
    else if (f.code === "folder_fastq_mixed_layout" && fq.verdict === "mixed" && excluded.size > 0) out.add(f)
    else if (f.code === "folder_samplesheet_single_end" && prof.samplesheet?.single && names.length > 0 && names.every((n) => excluded.has(n))) out.add(f)
    else if (f.code === "folder_fastq_pairs" && patternLine) out.add(f)
    else if (f.code === "folder_samplesheet" && pathsLine) out.add(f)
  }
  return out
}

export function FolderProfileView({
  projectId,
  path,
  className,
  onAnalyze,
}: {
  projectId: string
  path: string
  className?: string
  /** Attach every file under this folder to chat (default: navigate with attachFolder). */
  onAnalyze?: () => void
}) {
  const q = useFolderProfile(projectId, path)
  const name = path ? path : t("dataset_obj.inputs")
  const prof = q.data
  const shownBySamples = prof && Array.isArray(prof.findings) ? findingsShownBySamples(prof) : new Set()
  const shownFindings = (prof?.findings ?? []).filter((f) => !shownBySamples.has(f))
  const canAnalyze = (prof?.fileCount ?? 0) > 0
  const handleAnalyze = () => {
    if (onAnalyze) onAnalyze()
    else window.location.assign(analyzeFolderChatUrl(projectId, path))
  }
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
              {folderKindText(prof)}
            </Badge>
          )}
          {prof?.fastq && (
            <Badge variant="outline" className="text-xs" data-testid="folder-profile-verdict" data-verdict={prof.fastq.verdict}>
              {tOr(`folder_profile.verdict_${prof.fastq.verdict}`, prof.fastq.verdict)}
            </Badge>
          )}
          {canAnalyze && (
            <Button
              size="sm"
              className="h-8 text-sm px-3 gap-1.5 ml-auto"
              onClick={handleAnalyze}
              data-testid="folder-profile-analyze"
              title={t("folder_profile.ask_in_chat_tip")}
            >
              <Play className="h-3.5 w-3.5" />
              {t("dataset_obj.ask_in_chat")}
            </Button>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {q.isLoading ? (
          <div className="space-y-2" data-testid="folder-profile-loading">
            <Skeleton className="h-4 w-56" />
            <Skeleton className="h-20 w-full" />
          </div>
        ) : q.isError ? (
          <ProfileErrorState error={q.error} onRetry={() => { void q.refetch() }} retrying={q.isFetching} testId="folder-profile-error" />
        ) : !prof || typeof prof.kind !== "string" || !Array.isArray(prof.rollup) ? (
          <p className="text-sm text-muted-foreground" data-testid="folder-profile-error" data-reason="invalid">{t("folder_profile.error")}</p>
        ) : (
          <>
            <Rollup prof={prof} />

            {shownFindings.length > 0 && (
              <ul className="flex flex-col gap-1 rounded border p-2.5" data-testid="folder-findings">
                {shownFindings.map((f, i) => (
                  <li key={i} className="flex items-start gap-2 text-xs" data-testid="folder-finding" data-code={f.code} data-level={f.level}>
                    <span className={cn("mt-1 h-2 w-2 shrink-0 rounded-full", LEVEL_DOT[f.level] ?? LEVEL_DOT.info)} />
                    <span className="text-foreground [overflow-wrap:anywhere]">{findingText(f as unknown as PerceptionFinding)}</span>
                  </li>
                ))}
              </ul>
            )}

            {prof.fastq && prof.fastq.samples.length > 0 && (
              <div className="space-y-2" data-testid="folder-samples">
                {/* The download buttons wrap under the heading in a narrow panel, never clipped. */}
                <div className="flex flex-wrap items-center gap-2" data-testid="folder-samples-head">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground flex-1 whitespace-nowrap">
                    {t("folder_profile.samples_heading", { n: prof.fastq.samples.length })}
                  </p>
                  {prof.samplesheet && (
                    <Button asChild variant="outline" size="sm" className="h-7 text-xs gap-1">
                      <a href={folderProfileUrl(projectId, path, true)} download={prof.samplesheet.filename}
                         data-testid="folder-samplesheet-download" data-layout={prof.samplesheet.layout}
                         title={t("folder_profile.samplesheet_tip")}>
                        <Download className="h-3 w-3" />{t("folder_profile.samplesheet_download")}
                      </a>
                    </Button>
                  )}
                  {prof.samplesheet?.single && (
                    // The unpaired files' own single-end sheet: its CSV is in the profile, served as is.
                    <Button asChild variant="outline" size="sm" className="h-7 text-xs gap-1">
                      <a href={csvHref(prof.samplesheet.single.csv)} download={sheetDownloadName(path, prof.samplesheet.single.filename)}
                         data-testid="folder-samplesheet-single-download" data-layout={prof.samplesheet.single.layout ?? "single_end"}
                         title={t("folder_profile.samplesheet_single_tip")}>
                        <Download className="h-3 w-3" />{t("folder_profile.samplesheet_single_download")}
                      </a>
                    </Button>
                  )}
                </div>
                {(prof.fastq.patterns ?? []).some((x) => PATTERN_KEYS.has(x)) && (
                  <p className="text-xs text-muted-foreground" data-testid="folder-fastq-patterns">
                    {t("folder_profile.patterns", {
                      patterns: prof.fastq.patterns!.filter((x) => PATTERN_KEYS.has(x)).map((x) => t(`folder_profile.pattern_${x}`)).join(t("perception.list_and")),
                    })}
                  </p>
                )}
                {prof.samplesheet && (prof.samplesheet.layout || prof.samplesheet.pathBase) && (
                  <p className="text-xs text-muted-foreground" data-testid="folder-samplesheet-paths">
                    {t("folder_profile.samplesheet_paths", {
                      layout: prof.samplesheet.layout ? t(`folder_profile.layout_${prof.samplesheet.layout}`) : "nf-core",
                      base: pathBaseText(prof.samplesheet.pathBase || "project inputs"),
                    })}
                  </p>
                )}
                {(prof.samplesheet?.excluded ?? []).length > 0 && (
                  <p className="text-xs text-amber-700 dark:text-amber-400 [overflow-wrap:anywhere]" data-testid="folder-samplesheet-excluded">
                    {t("folder_profile.samplesheet_excluded", {
                      names: prof.samplesheet!.excluded!.slice(0, MAX_EXCLUDED_SHOWN).map((x) => base(x)).join(t("perception.list_sep")),
                    })}
                    {prof.samplesheet!.excluded!.length > MAX_EXCLUDED_SHOWN
                      ? ` ${t("dataset_obj.summary_more", { n: prof.samplesheet!.excluded!.length - MAX_EXCLUDED_SHOWN })}` : ""}
                  </p>
                )}
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
                            {/* File names break only after a separator (S1_R1.<wbr>fastq.<wbr>gz), never mid-word. */}
                            <td className="px-2 py-1 font-mono [overflow-wrap:break-word]" title={s.forward ?? ""} data-testid="folder-sample-read1">{s.forward ? breakAtSeparators(base(s.forward)) : "—"}</td>
                            <td className="px-2 py-1 font-mono [overflow-wrap:break-word]" title={s.reverse ?? ""} data-testid="folder-sample-read2">{s.reverse ? breakAtSeparators(base(s.reverse)) : "—"}</td>
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
                {/* A proper name ("10x Genomics"): its own capitalisation, never forced to all caps. */}
                <p className="text-xs font-semibold text-muted-foreground" data-testid="folder-tenx-heading">{t("folder_profile.tenx_heading")}</p>
                {prof.tenx.sets.map((s) => (
                  <div key={`${s.dir}/${s.prefix ?? ""}`} className="rounded border p-2.5 space-y-1" data-testid={`folder-tenx-set-${s.dir || "."}`} data-complete={String(s.complete)}>
                    <div className="flex items-center gap-2 flex-wrap text-sm">
                      <span className={s.dir ? "font-mono" : undefined}>{s.dir || t("perception.this_folder")}{s.prefix ? ` · ${s.prefix}` : ""}</span>
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
