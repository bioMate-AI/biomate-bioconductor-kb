/**
 * Preview views for data kinds that have no inline table or text viewer, built from what the
 * profiler read (never fabricated):
 *  - AnnDataSummary — h5ad / Loom: cells × genes, cell (obs) and gene (var) annotation columns,
 *    embeddings and layers, from the profile's stats + structured findings.
 *  - KindSummary    — alignments, Matrix Market, spreadsheets the rows reader does not parse:
 *    a spreadsheet's first rows, else where the numbers (stat grid) and findings (QC card) are.
 *  - DownloadState  — archives, binaries, unknown formats: an honest "not shown here" + Download.
 */
import { Download } from "lucide-react"
import { Button } from "@/components/ui/button"
import { t, tOr, locale } from "@/lib/i18n"
import type { DataProfile, PerceptionFinding } from "@/components/data-perception"
import { previewedSheet, profileStats, type ViewKind } from "./dataset-view-model"
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
export function AnnDataSummary({ profile, kind, canOpenIn = false }: {
  profile?: DataProfile; kind: ViewKind
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
          {/* cells × genes are the stat grid's numbers (shown once, there). */}
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
    </div>
  )
}

/**
 * Kinds without an inline viewer (alignments, Matrix Market, spreadsheets the rows reader does not
 * parse). The content shown here is what IS content: a spreadsheet's first rows. Its numbers are in
 * the stat grid, what the profiler noted is in the Data QC card and Download is in the header —
 * each shown once, so this view says only that and where to look.
 */
export function KindSummary({ profile, kind }: { profile?: DataProfile; kind: ViewKind }) {
  const sheet = previewedSheet(profile)
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
