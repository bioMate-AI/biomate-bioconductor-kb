/**
 * Preview views for data kinds that have no inline table or text viewer, built from what the
 * profiler read (never fabricated):
 *  - AnnDataSummary — h5ad / Loom: cells × genes, cell (obs) and gene (var) annotation columns,
 *    embeddings and layers, from the profile's stats + structured findings.
 *  - KindSummary    — alignments, Matrix Market, spreadsheets the rows reader does not parse:
 *    the kind's headline numbers and what the profiler noted, plus Download.
 *  - DownloadState  — archives, binaries, unknown formats: an honest "not shown here" + Download.
 */
import { Download, Play } from "lucide-react"
import { Button } from "@/components/ui/button"
import { t, tOr, locale } from "@/lib/i18n"
import { findingText, type DataProfile, type PerceptionFinding } from "@/components/data-perception"
import { profileStats, type ViewKind } from "./dataset-view-model"
import { DatasetRowsTable } from "./dataset-rows-table"

const NUM_LOCALE = locale === "zh" ? "zh-CN" : "en-US"
const num = (v: unknown) => (typeof v === "number" ? v.toLocaleString(NUM_LOCALE) : String(v ?? "—"))

function findingOf(profile: DataProfile | undefined, ...codes: string[]): PerceptionFinding | undefined {
  return profile?.findings?.find((f) => codes.includes(f.code))
}
function listParam(f: PerceptionFinding | undefined, key: string): string[] {
  const v = f?.params?.[key]
  return Array.isArray(v) ? v.map(String) : []
}

function ChipList({ testId, label, names, total }: { testId: string; label: string; names: string[]; total?: number }) {
  if (!names.length) return null
  const more = typeof total === "number" && total > names.length ? total - names.length : 0
  return (
    <div className="space-y-1" data-testid={testId}>
      <p className="text-xs font-medium text-muted-foreground">
        {label}{typeof total === "number" ? ` · ${num(total)}` : ""}
      </p>
      <div className="flex flex-wrap gap-1">
        {names.map((n) => (
          <span key={n} className="rounded border bg-muted/30 px-1.5 py-0.5 font-mono text-xs">{n}</span>
        ))}
        {more > 0 && <span className="px-1 py-0.5 text-xs text-muted-foreground">{t("dataset_obj.summary_more", { n: num(more) })}</span>}
      </div>
    </div>
  )
}

/** AnnData (h5ad) / Loom summary: shape, obs/var columns, embeddings, layers. */
export function AnnDataSummary({ profile, kind, onAnalyze, canOpenIn = false }: {
  profile?: DataProfile; kind: ViewKind; onAnalyze?: () => void
  /** Open-in (Jupyter) is offered for this file: only then does the note point to it. */
  canOpenIn?: boolean
}) {
  const stats = profile ? profileStats(profile, kind) : []
  const cells = stats.find((s) => s.code === "cells")?.value
  const genes = stats.find((s) => s.code === "genes")?.value
  const loom = kind === "loom"
  const obs = findingOf(profile, loom ? "loom_col_attrs" : "anndata_obs")
  const varF = findingOf(profile, loom ? "loom_row_attrs" : "anndata_var")
  const emb = findingOf(profile, "anndata_embeddings")
  // Real expression layers (`adata.layers`: counts, spliced…) are NOT the file's stored
  // components (X, obs, obsm, var, varm, uns, layers — its top-level HDF5 groups). Layers come
  // from the profile's `layers` ([] = none: the values are in X only), else an `anndata_layers` /
  // Loom `loom_layers` finding; the components (`anndata_components`, older profiles
  // `hdf5_groups`) are listed apart, under their own name.
  const layersF = findingOf(profile, loom ? "loom_layers" : "anndata_layers")
  const layerNames = Array.isArray(profile?.layers) ? profile!.layers!.map(String) : listParam(layersF, "layers")
  const layersTotal = Array.isArray(profile?.layers) ? profile!.layers!.length : (layersF?.params?.count as number | undefined)
  const noLayers = !loom && ((Array.isArray(profile?.layers) && profile!.layers!.length === 0) || Boolean(findingOf(profile, "anndata_no_layers")))
  const components = loom ? undefined : findingOf(profile, "anndata_components")
  const legacyGroups = loom || components ? undefined : findingOf(profile, "hdf5_groups")
  const componentNames = components ? listParam(components, "components") : listParam(legacyGroups, "groups")
  const componentsTotal = (components ?? legacyGroups)?.params?.count as number | undefined
  const known = cells != null || genes != null || obs || varF || emb || layerNames.length || noLayers || componentNames.length
  return (
    <div className="space-y-3 rounded border p-3" data-testid="dataset-anndata-summary">
      {known ? (
        <>
          <div className="flex items-baseline gap-2" data-testid="dataset-anndata-shape">
            <span className="text-lg font-semibold tabular-nums">{num(cells)}</span>
            <span className="text-xs text-muted-foreground">{t("dataset_obj.summary_cells")}</span>
            <span className="text-muted-foreground">×</span>
            <span className="text-lg font-semibold tabular-nums">{num(genes)}</span>
            <span className="text-xs text-muted-foreground">{t("dataset_obj.summary_genes")}</span>
          </div>
          <ChipList testId="dataset-anndata-obs" label={t("dataset_obj.summary_obs")} names={listParam(obs, "columns")} total={obs?.params?.count as number | undefined} />
          <ChipList testId="dataset-anndata-var" label={t("dataset_obj.summary_var")} names={listParam(varF, "columns")} total={varF?.params?.count as number | undefined} />
          <ChipList testId="dataset-anndata-embeddings" label={t("dataset_obj.summary_embeddings")} names={listParam(emb, "embeddings")} total={emb?.params?.count as number | undefined} />
          <ChipList testId="dataset-anndata-layers" label={t("dataset_obj.summary_layers")} names={layerNames} total={layersTotal} />
          {noLayers && !layerNames.length && (
            <p className="text-xs text-muted-foreground" data-testid="dataset-anndata-no-layers">{t("perception.msg.anndata_no_layers")}</p>
          )}
          <ChipList testId="dataset-anndata-groups" label={t("dataset_obj.summary_groups")} names={componentNames}
            total={typeof componentsTotal === "number" ? componentsTotal : componentNames.length || undefined} />
          <p className="text-xs text-muted-foreground" data-testid="dataset-anndata-note">
            {t(canOpenIn ? "dataset_obj.summary_anndata_note" : "dataset_obj.summary_anndata_note_chat")}
          </p>
        </>
      ) : (
        <p className="text-sm text-muted-foreground" data-testid="dataset-anndata-unread">
          {t(canOpenIn ? "dataset_obj.summary_anndata_unread" : "dataset_obj.summary_anndata_unread_chat")}
        </p>
      )}
      {onAnalyze && (
        <Button size="sm" variant="outline" className="h-7 text-xs gap-1" onClick={onAnalyze}>
          <Play className="h-3 w-3" />{t("dataset_obj.ask_in_chat")}
        </Button>
      )}
    </div>
  )
}

/** Headline numbers + what the profiler noted, for kinds without an inline viewer. */
export function KindSummary({ profile, kind, onDownload }: { profile?: DataProfile; kind: ViewKind; onDownload?: () => void }) {
  const stats = profile ? profileStats(profile, kind) : []
  // A spreadsheet whose first sheet the profiler read: its first rows ARE the preview (read-only).
  // The notes that only say "preview of sheet X" / "export to CSV to see it" are then not repeated
  // here (the QC card still lists them).
  const sheet = profile && typeof profile.previewSheet === "string" && profile.columns?.length && profile.sampleRows?.length
    ? { name: profile.previewSheet, columns: profile.columns, rows: profile.sampleRows } : null
  const notes = (profile?.findings ?? []).filter((f) => f.section !== "plan"
    && !(sheet && (f.code === "spreadsheet_preview" || f.code === "spreadsheet_convert")))
  return (
    <div className="space-y-2 rounded border p-3 text-sm" data-testid="dataset-kind-summary" data-kind={kind}>
      {sheet ? (
        <div className="space-y-1" data-testid="dataset-spreadsheet-preview" data-sheet={sheet.name}>
          <p className="text-xs font-medium text-muted-foreground" data-testid="dataset-spreadsheet-caption">
            {t("dataset_obj.spreadsheet_preview_caption", { sheet: sheet.name || "—", n: num(sheet.rows.length) })}
          </p>
          <DatasetRowsTable columns={sheet.columns} rows={sheet.rows} total={null} loading={false} error={null}
            onNeedMore={() => {}} scope={t("dataset_obj.spreadsheet_preview_scope")} />
        </div>
      ) : (
        <p className="text-muted-foreground">{tOr(`dataset_obj.summary_intro_${kind}`, t("dataset_obj.summary_intro"))}</p>
      )}
      {stats.length > 0 && (
        <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {stats.map((s) => (
            <div key={s.code} className="min-w-0">
              <dt className="text-fs-xs uppercase tracking-wide text-muted-foreground">{tOr(`perception.stat.${s.code}`, s.code)}</dt>
              <dd className="font-semibold tabular-nums">{num(s.value)}</dd>
            </div>
          ))}
        </dl>
      )}
      {notes.length > 0 && (
        <ul className="list-disc space-y-0.5 pl-4 text-xs">
          {notes.map((f, i) => <li key={i}>{findingText(f)}</li>)}
        </ul>
      )}
      {onDownload && <DownloadButton onDownload={onDownload} />}
    </div>
  )
}

/** Archives, binaries and unknown formats: say plainly it is not shown here; offer Download. */
export function DownloadState({ kind, onDownload }: { kind: ViewKind; onDownload?: () => void }) {
  return (
    <div className="space-y-2 rounded border bg-muted/20 p-3 text-sm" data-testid="dataset-download-state" data-kind={kind}>
      <p className="text-muted-foreground">{tOr(`dataset_obj.download_state_${kind}`, t("dataset_obj.download_state"))}</p>
      {onDownload && <DownloadButton onDownload={onDownload} />}
    </div>
  )
}

function DownloadButton({ onDownload }: { onDownload: () => void }) {
  return (
    <Button size="sm" variant="outline" className="h-7 gap-1 text-xs" onClick={onDownload} data-testid="dataset-kind-download">
      <Download className="h-3 w-3" />{t("dataset_obj.preview_download")}
    </Button>
  )
}
