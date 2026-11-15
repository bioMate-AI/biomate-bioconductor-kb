import { PdfCanvasViewer } from "./pdf-canvas-viewer";
import { RunFileDownload } from "./run-file-download";
/**
 * StepOutputPreview — inline viewer for a single Nextflow step output file.
 *
 * Fetches file content from /api/workflows/runs/:id/step-file and renders
 * the most appropriate viewer for the file type:
 *
 *   image   → <img> with click-to-zoom lightbox
 *   table   → InlineTableViewer (handles CSV/TSV/JSON + STAR/RELION format)
 *   density → DensityMapViewer (full 3-axis slice viewer — same as ChatOutputAttachments)
 *   sequence → FASTA/FASTQ record list
 *   vcf     → variant table (plain .vcf)
 *   igv     → IGV.js for .bam+.bai / .vcf.gz+.tbi (Range GETs; not Interactive Tools)
 *   annotation → BED/GFF table
 *   structure  → PDB/mmCIF rendered with 3Dmol.js (cartoon + spectrum default)
 *   html    → sandboxed iframe
 *   text    → <pre> with tail toggle
 *   download → download link for unknown binary formats
 */

import { t, tOr } from "@/lib/i18n";
import { useState, useEffect, useRef } from "react";
import { Loader2, X, FileText, ZoomIn, ChevronDown, ChevronUp, Laptop, Maximize2, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn, stripAnsi } from "@/lib/utils";
import { DensityMapViewer } from "./viewers/density-map-viewer";
import { FscCurveChart } from "./viewers/fsc-curve-chart";
import { MotionHistogramChart } from "./viewers/motion-histogram-chart";
import { CtfQualityChart } from "./viewers/ctf-quality-chart";
import { InteractiveLauncher } from "./interactive-launcher";
import { InlineTextViewer, InlineTableViewer } from "./file-content-view";
import { useInteractiveToolsAvailable } from "@/hooks/use-interactive-tools";
import {
  SINGLECELL_EXTS, R_EXTS, TABLE_EXTS,
  resolveViewer, parsePlddtFromPdb,
  TEXT_VIEWERS, SELF_FETCHING,
  InlineSequenceViewer, InlineVcfViewer, InlineAnnotationViewer, InlineStructureViewer,
  type ViewerKind,
} from "./viewers/inline-content-viewers";
import { InlineIgvViewer } from "./viewers/inline-igv-viewer";
import { stepFileUrl } from "./viewers/genomics-index";
// Re-exported for existing importers (e.g. step-output-preview.test.tsx).
export { parsePlddtFromPdb };
export type { ViewerKind };
import { SeqTracks, type SeqTrack, type FlaggedInterval } from "./viewers/seq-tracks";
import { HitGrid, type ChemHit, type HitVerdict } from "./viewers/hit-grid";
import { PaeHeatmap } from "./viewers/pae-heatmap";
import { SingleCellSummaryPanel } from "./viewers/single-cell-summary";
// 3Dmol.js loaded dynamically inside InlineStructureViewer so the structure
// path doesn't pull ~700 KB into the main bundle.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface StepOutputPreviewProps {
  runId: string;
  file: { name: string; path: string; extension: string; size?: number };
  onClose: () => void;
  /**
   * Optional project ID threaded through from callers with project context.
   */
  projectId?: string | null;
  /**
   * Optional "Open full step view" affordance. When provided, a button is shown
   * in the preview header that opens the step-as-object surface (StepDetail):
   * provenance, resolved params with origin badges, and a rendered ⇄ raw toggle.
   */
  onOpenFullStepView?: () => void;
  /**
   * Optional max-height class for the text/table inline viewers. Defaults to the
   * compact run-output height; a larger preview surface (e.g. the Outputs modal
   * pane) passes a taller value like "max-h-[70vh]".
   */
  maxHClass?: string;
  /** Parent already supplies file identity, close and download controls. */
  embedded?: boolean;
  expanded?: boolean;
}

interface FetchedContent {
  pdfData?: Uint8Array;
  url: string;
  contentType: string;
  text?: string;
}

// ---------------------------------------------------------------------------
// Extension → viewer category
// ---------------------------------------------------------------------------

// The file-extension → viewer registry (ViewerKind, resolveViewer, the ext sets)
// now lives in ./viewers/inline-content-viewers and is imported above, so the
// dataset object (Files module) resolves the same viewers as this run-output
// preview. SINGLECELL_EXTS / R_EXTS / TABLE_EXTS are imported for
// pickInteractiveTool below.

/**
 * Pick the best interactive tool for a given file extension.
 * Used to pre-select the correct tab in InteractiveLauncher and label the button.
 */
function pickInteractiveTool(ext: string): {
  tool: 'jupyter' | 'rstudio' | 'cellxgene';
  label: string;
} {
  const e = ext.toLowerCase().replace(/^\./, '');
  if (SINGLECELL_EXTS.has(e))
    return { tool: 'cellxgene', label: t('preview.explore_cellxgene') };
  if (R_EXTS.has(e) || e === 'rda')
    return { tool: 'rstudio', label: t('preview.open_rstudio') };
  if (TABLE_EXTS.has(e))
    return { tool: 'rstudio', label: t('preview.analyze_rstudio') };
  // sequences, annotations, VCF, text — Jupyter is the universal fallback
  return { tool: 'jupyter', label: t('preview.open_jupyter') };
}

/** Shown in place of an "Open in <tool>" button when that interactive tool
 *  isn't launchable here (it would 400). Offers the download instead of a dead
 *  button, so the user can analyze the file locally. */
function InteractiveUnavailableNote({
  runId, file, toolLabel, embedded,
}: { embedded?: boolean; runId: string; file: { name: string; path: string }; toolLabel: string }) {
  return (
    <div className="flex flex-col gap-2" data-testid="interactive-unavailable">
      <p className="text-xs text-muted-foreground">
        {toolLabel} isn’t enabled in this environment. Download the file to analyze it locally.
      </p>
      {!embedded && <RunFileDownload runId={runId} file={file} />}
    </div>
  );
}

// TEXT_VIEWERS / SELF_FETCHING now live in ./viewers/inline-content-viewers (imported above).

// ---------------------------------------------------------------------------
// STAR / RELION format parser
// CryoSPARC and RELION both use the STAR format:
//   data_
//   loop_
//   _rlnColumnName #1
//   _rlnOtherName  #2
//   value1  value2
//   ...
// ---------------------------------------------------------------------------

// parseStar, InlineTableViewer, fmtCell, TableGrid and InlineTextViewer now live
// in ./file-content-view (shared with the files-module dataset preview) and are
// imported at the top of this file.

// ---------------------------------------------------------------------------
// Image viewer with click-to-zoom lightbox
// ---------------------------------------------------------------------------

function InlineImageViewer({ src, name }: { src: string; name: string }) {
  const [lightboxOpen, setLightboxOpen] = useState(false);
  return (
    <>
      <div className="relative group cursor-zoom-in" onClick={() => setLightboxOpen(true)}>
        <img
          src={src}
          alt={name}
          className="max-h-64 w-auto rounded border mx-auto block"
        />
        <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity bg-black/20 rounded">
          <ZoomIn className="h-6 w-6 text-white drop-shadow" />
        </div>
      </div>
      <p className="text-fs-xs text-muted-foreground text-center mt-1">Click to enlarge</p>

      {lightboxOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setLightboxOpen(false)}
        >
          <div className="relative max-w-[90vw] max-h-[90vh]" onClick={e => e.stopPropagation()}>
            <img
              src={src}
              alt={name}
              className="max-w-full max-h-[85vh] rounded shadow-2xl object-contain"
            />
            <button
              className="absolute top-2 right-2 bg-black/60 hover:bg-black/80 text-white rounded-full p-1"
              onClick={() => setLightboxOpen(false)}
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
            <p className="text-center text-white/70 text-xs mt-2">{name}</p>
          </div>
        </div>
      )}
    </>
  );
}

// InlineSequenceViewer / InlineVcfViewer / InlineAnnotationViewer now live in
// ./viewers/inline-content-viewers (imported above) — shared with the dataset object.

// ---------------------------------------------------------------------------
// Text viewer with tail toggle (log files are useful from the end)
// ---------------------------------------------------------------------------

// InlineTextViewer now lives in ./file-content-view (imported above).

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

// Density viewer wrapper — renders DensityMapViewer without going through
// the blob/text fetch machinery (the viewer fetches its own data).
function DensityPreview({ runId, file, onClose, embedded, projectId }: StepOutputPreviewProps) {
  const url = stepFileUrl(runId, file.path, file.name);
  return (
    <div className="mt-2">
      {!embedded && <div className="flex items-center justify-between mb-2 gap-2 px-1">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>}
      <DensityMapViewer src={url} name={file.name} />
    </div>
  );
}

/** BAM / indexed VCF.gz — IGV.js with Range GETs; never full-file fetch. */
function IgvPreview({ runId, file, onClose, embedded }: StepOutputPreviewProps) {
  const url = stepFileUrl(runId, file.path, file.name);
  return (
    <div className="mt-2" data-testid="step-igv-preview">
      {!embedded && <div className="flex items-center justify-between mb-2 gap-2 px-1">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>}
      <InlineIgvViewer
        url={url}
        name={file.name}
        runId={runId}
        filePath={file.path}
        downloadUrl={url}
      />
    </div>
  );
}

/** Summary emitted by the run-time RDS introspector (scripts/rds_introspect.R), if present. */
interface RdsSummary {
  class?: string | string[];
  dim?: number[];
  summary?: string;
  assays?: string[];
  reducedDims?: string[];
  colData?: string[];
  rowData?: string[];
  names?: string[];
  length?: number;
}

/** R object viewer — RDS/RData are binary. If the run produced a `<name>.rds.json`
 * sidecar (object class, dims, assays, reductions, colData), render it inline; otherwise
 * fall back to the RStudio launcher. */
function RObjectPreview({ runId, file, onClose, embedded, projectId }: StepOutputPreviewProps) {
  const [launcherOpen, setLauncherOpen] = useState(false);
  const [summary, setSummary] = useState<RdsSummary | null>(null);
  const [sidecarTried, setSidecarTried] = useState(false);
  const { data: itAvail } = useInteractiveToolsAvailable();
  const rstudioAvailable = !itAvail || itAvail.tools.rstudio; // optimistic until known
  const output = { id: file.path, name: file.name, size: file.size ?? 0, type: file.extension };

  // Try to fetch the sidecar produced alongside the .rds (best-effort, graceful).
  useEffect(() => {
    const sidecarPath = `${file.path}.json`;
    const url = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(sidecarPath)}&name=${encodeURIComponent(file.name + '.json')}`;
    let alive = true;
    fetch(url)
      .then(r => (r.ok ? r.json() : Promise.reject(`HTTP ${r.status}`)))
      .then(j => { if (alive && j && typeof j === 'object') setSummary(j as RdsSummary); })
      .catch(() => {})
      .finally(() => { if (alive) setSidecarTried(true); });
    return () => { alive = false; };
  }, [runId, file.path, file.name]);

  const cls = Array.isArray(summary?.class) ? summary?.class?.[0] : summary?.class;
  const chipRow = (label: string, items?: string[]) =>
    items && items.length > 0 ? (
      <div className="flex flex-wrap items-baseline gap-1.5 mb-1">
        <span className="text-fs-xs uppercase tracking-wide text-muted-foreground">{label}</span>
        {items.slice(0, 12).map((it, i) => (
          <span key={i} className="text-xs font-mono px-1.5 py-0.5 rounded bg-muted/60">{it}</span>
        ))}
        {items.length > 12 && <span className="text-fs-xs text-muted-foreground">+{items.length - 12}</span>}
      </div>
    ) : null;

  return (
    <div className="mt-2 border rounded-md bg-background p-3">
      {!embedded && <div className="flex items-center justify-between mb-2 gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>}

      {summary ? (
        <div className="mb-3">
          <div className="flex items-baseline gap-2 mb-2">
            {cls && <span className="text-xs font-semibold">{cls}</span>}
            {summary.dim && summary.dim.length >= 2 && (
              <span className="text-xs text-muted-foreground font-mono">
                {summary.dim[0].toLocaleString()} × {summary.dim[1].toLocaleString()}
              </span>
            )}
            {typeof summary.length === 'number' && !summary.dim && (
              <span className="text-xs text-muted-foreground font-mono">length {summary.length.toLocaleString()}</span>
            )}
          </div>
          {summary.summary && <p className="text-xs text-muted-foreground mb-2">{summary.summary}</p>}
          {chipRow('assays', summary.assays)}
          {chipRow('reductions', summary.reducedDims)}
          {chipRow('colData', summary.colData)}
          {chipRow('rowData', summary.rowData)}
          {chipRow('elements', summary.names)}
        </div>
      ) : (
        <p className="text-xs text-muted-foreground mb-3">
          R serialised object ({file.extension.toUpperCase()})
          {sidecarTried ? ' — open in RStudio to load and explore.' : '…'}
        </p>
      )}

      {rstudioAvailable ? (
        <>
          <Button size="sm" variant="outline" className="gap-1.5 h-7 text-xs" onClick={() => setLauncherOpen(true)}>
            <Laptop className="h-3.5 w-3.5" />
            Open in RStudio
          </Button>
          <InteractiveLauncher
            open={launcherOpen}
            onOpenChange={setLauncherOpen}
            outputs={[output]}
            initialTool="rstudio"
          />
        </>
      ) : (
        <InteractiveUnavailableNote embedded={embedded} runId={runId} file={file} toolLabel="RStudio" />
      )}
    </div>
  );
}

/** Single-cell AnnData / Loom preview — binary format; cannot be read inline.
 *  Offers CellxGene (ideal for .h5ad / .loom) and Jupyter as fallback. */
function SingleCellPreview({ runId, file, onClose, embedded }: StepOutputPreviewProps) {
  const [launcherOpen, setLauncherOpen] = useState(false);
  const [launcherTool, setLauncherTool] = useState<'cellxgene' | 'jupyter'>('cellxgene');
  // Whether the in-app summary sidecar is missing (→ interactive/download is the
  // primary path); starts false so we don't flash a fallback before it loads.
  const [summaryAbsent, setSummaryAbsent] = useState(false);
  const { data: itAvail } = useInteractiveToolsAvailable();
  // Optimistic until availability is known; hide a tool once known-unavailable.
  const cellxgeneAvailable = !itAvail || itAvail.tools.cellxgene;
  const jupyterAvailable = !itAvail || itAvail.tools.jupyter;
  const anyAvailable = cellxgeneAvailable || jupyterAvailable;
  const output = { id: file.path, name: file.name, size: file.size ?? 0, type: file.extension };

  const openWith = (tool: 'cellxgene' | 'jupyter') => {
    setLauncherTool(tool);
    setLauncherOpen(true);
  };

  return (
    <div className="mt-2 border rounded-md bg-background p-3">
      {!embedded && <div className="flex items-center justify-between mb-2 gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
          <X className="h-3.5 w-3.5" />
        </Button>
      </div>}

      {/* In-app summary (UMAP + clusters + markers) from the pipeline's sidecar,
          when present. Self-hides and calls onAbsent when there's no sidecar. */}
      <SingleCellSummaryPanel runId={runId} file={file} onAbsent={() => setSummaryAbsent(true)} />

      {/* Deeper exploration (secondary when the summary is shown) / fallback. */}
      {anyAvailable ? (
        <div className="mt-3">
          <p className="text-fs-xs text-muted-foreground mb-1">
            {summaryAbsent ? 'Single-cell object — open interactively to explore.' : 'Explore interactively:'}
          </p>
          <div className="flex flex-wrap gap-2">
            {cellxgeneAvailable && (
              <Button size="sm" variant="outline" className="gap-1.5 h-7 text-xs" onClick={() => openWith('cellxgene')}>
                <Laptop className="h-3.5 w-3.5" />
                {t('preview.explore_cellxgene')}
              </Button>
            )}
            {jupyterAvailable && (
              <Button size="sm" variant="ghost" className="gap-1.5 h-7 text-xs" onClick={() => openWith('jupyter')}>
                <Laptop className="h-3.5 w-3.5" />
                {t('preview.open_jupyter')}
              </Button>
            )}
          </div>
          <InteractiveLauncher
            open={launcherOpen}
            onOpenChange={setLauncherOpen}
            outputs={[output]}
            initialTool={launcherTool}
          />
        </div>
      ) : summaryAbsent ? (
        // No in-app summary AND no interactive tool → offer the download.
        <div className="mt-3">
          <InteractiveUnavailableNote embedded={embedded} runId={runId} file={file} toolLabel="Interactive viewers (CellxGene/Jupyter)" />
        </div>
      ) : null}
    </div>
  );
}

/** Detect special CryoEM JSON report filenames and render dedicated chart viewers */
function resolveCryoChartViewer(fileName: string): 'fsc-curve' | 'motion-histogram' | 'ctf-quality' | null {
  const n = fileName.toLowerCase();
  if (n.includes('fsc_validation'))  return 'fsc-curve';
  if (n.includes('motion_report'))   return 'motion-histogram';
  if (n.includes('ctf_report'))      return 'ctf-quality';
  return null;
}

/** Fetches JSON from step-file and renders a CryoEM chart component */
function CryoChartPreview({ runId, file, onClose, embedded, projectId, chartType }: StepOutputPreviewProps & {
  chartType: 'fsc-curve' | 'motion-histogram' | 'ctf-quality'
}) {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const stepFileUrl = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(file.path)}&name=${encodeURIComponent(file.name)}`;

  useEffect(() => {
    fetch(stepFileUrl)
      .then(r => r.ok ? r.json() : Promise.reject(`HTTP ${r.status}`))
      .then(setData)
      .catch(e => setError(String(e)));
  }, [stepFileUrl]);

  return (
    <div className="mt-2">
      {!embedded && <div className="flex items-center justify-between mb-2 gap-2 px-1">
        <span className="text-xs font-mono font-medium truncate">{file.name}</span>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>}
      {error && <p className="text-xs text-destructive">{error}</p>}
      {data && chartType === 'fsc-curve'         && <FscCurveChart data={data} />}
      {data && chartType === 'motion-histogram'  && <MotionHistogramChart data={data} />}
      {data && chartType === 'ctf-quality'       && <CtfQualityChart data={data} />}
    </div>
  );
}

/**
 * Detect DL-model JSON sidecar outputs that carry a domain-specific evidence
 * payload (genomic score tracks, ranked chemical hits). These follow the same
 * convention as the CryoEM JSON reports: a well-known filename suffix names the
 * viewer, and the JSON body IS the viewer's data contract (Spec 08 §8.5 —
 * "domain-specific outputs use their own viewers within these classes").
 */
function resolveDlJsonViewer(fileName: string): 'seq-tracks' | 'hit-grid' | 'pae' | null {
  const n = fileName.toLowerCase();
  if (n.includes('seqtracks') || n.includes('seq_tracks') || n.includes('_tracks')) return 'seq-tracks';
  if (n.includes('hitgrid') || n.includes('hit_grid') || n.includes('_hits')) return 'hit-grid';
  // Predicted-structure PAE sidecars (AlphaFold/Boltz/ColabFold): *_pae.json,
  // predicted_aligned_error.json.
  if (n.includes('pae') || n.includes('predicted_aligned_error')) return 'pae';
  return null;
}

// Normalise the various PAE JSON shapes to an n×n matrix. AlphaFold/ColabFold
// emit {predicted_aligned_error}, {pae}, or a single-element list wrapping one
// of those; anything else yields [] and PaeHeatmap shows its honest empty state.
function normalizePae(data: any): number[][] {
  if (!data) return [];
  const src = Array.isArray(data) ? data[0] : data;
  const m = src?.predicted_aligned_error ?? src?.pae ?? null;
  return Array.isArray(m) && Array.isArray(m[0]) ? (m as number[][]) : [];
}

// The WS1 hit verdicts are open strings; narrow to the viewer's union, default "held".
const HIT_VERDICTS: HitVerdict[] = ['accepted', 'flagged', 'rejected', 'held'];
function toHitVerdict(v: unknown): HitVerdict {
  return typeof v === 'string' && (HIT_VERDICTS as string[]).includes(v) ? (v as HitVerdict) : 'held';
}

/**
 * Fetches a DL-domain JSON output and renders the matching evidence viewer.
 * The viewers own their honest empty states, so a malformed / empty body shows
 * "no data" rather than a fabricated result.
 */
function DlJsonPreview({ runId, file, onClose, embedded, viewerKind }: StepOutputPreviewProps & {
  viewerKind: 'seq-tracks' | 'hit-grid' | 'pae'
}) {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const stepFileUrl = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(file.path)}&name=${encodeURIComponent(file.name)}`;

  useEffect(() => {
    let cancelled = false;
    fetch(stepFileUrl)
      .then(r => r.ok ? r.json() : Promise.reject(`HTTP ${r.status}`))
      .then(d => { if (!cancelled) setData(d); })
      .catch(e => { if (!cancelled) setError(String(e)); });
    return () => { cancelled = true; };
  }, [stepFileUrl]);

  // Normalise the JSON body to the viewer's prop contract. Missing arrays
  // become empty — the viewer renders its own honest empty state.
  const tracks: SeqTrack[] = viewerKind === 'seq-tracks'
    ? (Array.isArray(data?.tracks) ? data.tracks : [])
    : [];
  const flagged: FlaggedInterval[] = viewerKind === 'seq-tracks'
    ? (Array.isArray(data?.flagged) ? data.flagged : [])
    : [];
  const hits: ChemHit[] = viewerKind === 'hit-grid' && Array.isArray(data?.hits)
    ? data.hits.map((h: any) => ({
        id: String(h.id ?? ''),
        smiles: h.smiles,
        // A held/unscored hit has no measured score — keep it null (NOT 0) so
        // HitGrid sorts it as unranked rather than as the worst real score.
        score: typeof h.score === 'number' ? h.score : null,
        confidence: h.confidence,
        herg: h.herg ?? '—',
        drugLike: h.drugLike ?? '—',
        verdict: toHitVerdict(h.verdict),
      }))
    : [];

  return (
    <div className="mt-2" data-testid="dl-json-preview">
      {!embedded && <div className="flex items-center justify-between mb-2 gap-2 px-1">
        <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>}
      {error && <p className="text-xs text-destructive">{t('preview.failed', { error })}</p>}
      {data && viewerKind === 'seq-tracks' && (
        <SeqTracks
          locus={typeof data.locus === 'string' ? data.locus : 'user-supplied'}
          tracks={tracks}
          flagged={flagged}
          bp={typeof data.bp === 'number' ? data.bp : undefined}
        />
      )}
      {data && viewerKind === 'hit-grid' && (
        <HitGrid
          hits={hits}
          modelName={typeof data.modelName === 'string' ? data.modelName : undefined}
          modelId={typeof data.modelId === 'string' ? data.modelId : undefined}
        />
      )}
      {data && viewerKind === 'pae' && (
        <PaeHeatmap pae={normalizePae(data)} />
      )}
    </div>
  );
}

export function StepOutputPreview({ runId, file, onClose, projectId, onOpenFullStepView, maxHClass, embedded, expanded }: StepOutputPreviewProps) {
  const ext = file.extension.toLowerCase().replace(/^\./, '');
  const viewer = resolveViewer(ext, file.name);

  // Route density files to a separate component (avoids hook-after-conditional).
  if (viewer === 'density') {
    return <DensityPreview runId={runId} file={file} embedded={embedded} onClose={onClose} projectId={projectId} />;
  }

  if (viewer === 'igv') {
    return <IgvPreview runId={runId} file={file} embedded={embedded} onClose={onClose} projectId={projectId} />;
  }

  // R object files — binary, no inline preview; offer RStudio launch instead.
  if (viewer === 'r-object') {
    return <RObjectPreview runId={runId} file={file} embedded={embedded} onClose={onClose} projectId={projectId} />;
  }

  // Single-cell AnnData/Loom files — binary; offer CellxGene launch.
  if (viewer === 'singlecell') {
    return <SingleCellPreview runId={runId} file={file} embedded={embedded} onClose={onClose} />;
  }

  // Route special CryoEM JSON reports to dedicated chart viewers.
  if (ext === 'json') {
    const chartType = resolveCryoChartViewer(file.name);
    if (chartType) {
      return <CryoChartPreview runId={runId} file={file} embedded={embedded} onClose={onClose} projectId={projectId} chartType={chartType} />;
    }
    // DL-model JSON sidecars (genomic tracks / ranked chemical hits).
    const dlKind = resolveDlJsonViewer(file.name);
    if (dlKind) {
      return <DlJsonPreview runId={runId} file={file} embedded={embedded} onClose={onClose} projectId={projectId} viewerKind={dlKind} />;
    }
  }

  return <FetchingPreview runId={runId} file={file} onClose={onClose} projectId={projectId} viewer={viewer} ext={ext} onOpenFullStepView={onOpenFullStepView} maxHClass={maxHClass} embedded={embedded} expanded={expanded} />;
}

function FetchingPreview({
  runId, file, onClose, projectId, viewer, ext, onOpenFullStepView, maxHClass, embedded, expanded,
}: StepOutputPreviewProps & { viewer: ViewerKind; ext: string }) {
  const [content, setContent] = useState<FetchedContent | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [launcherOpen, setLauncherOpen] = useState(false);
  const [launcherTool, setLauncherTool] = useState<'jupyter' | 'rstudio' | 'cellxgene'>(() => pickInteractiveTool(ext).tool);
  // kept for compat with the local variable name used in JSX below
  const rstudioOpen = launcherOpen;
  const setRstudioOpen = setLauncherOpen;

  const needsText = TEXT_VIEWERS.includes(viewer);
  const stepFileUrl = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(file.path)}&name=${encodeURIComponent(file.name)}`;

  useEffect(() => {
    let cancelled = false;
    let objectUrl: string | null = null;
    setLoading(true); setError(null); setContent(null);

    fetch(stepFileUrl)
      .then(async res => {
        if (!res.ok) {
          const body = await res.text();
          throw new Error(`HTTP ${res.status}: ${body}`);
        }
        const ct = res.headers.get('content-type') || 'application/octet-stream';
        if (needsText) {
          const text = await res.text();
          if (cancelled) return;
          setContent({ url: stepFileUrl, contentType: ct, text });
        } else if (viewer === 'pdf') {
          const pdfData = new Uint8Array(await res.arrayBuffer());
          if (!cancelled) setContent({url: stepFileUrl, contentType: ct, pdfData});
        } else if (viewer === 'html') {
          // Keep the server's CSP sandbox on navigation. A new blob URL would
          // discard those headers and execute the report with the app's origin.
          if (!cancelled) setContent({ url: stepFileUrl, contentType: ct });
        } else {
          let blob = await res.blob();
          if (cancelled) return;
          objectUrl = URL.createObjectURL(blob);
          setContent({ url: objectUrl, contentType: ct });
        }
        setLoading(false);
      })
      .catch(err => {
        if (cancelled) return;
        setError((err as Error).message);
        setLoading(false);
      });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [stepFileUrl, needsText]);

  return (
    <div className="mt-2 border rounded-md bg-background p-3">
      {!embedded && <div className="flex items-center justify-between mb-2 gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          {onOpenFullStepView && (
            <Button
              variant="ghost"
              size="sm"
              className="h-6 gap-1 px-1.5 shrink-0 text-fs-xs"
              onClick={onOpenFullStepView}
              data-testid="open-full-step-view"
              title={t('preview.full_step_view_tip')}
            >
              <Maximize2 className="h-3 w-3" />
              {t('preview.full_step_view')}
            </Button>
          )}
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>}

      {loading && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground py-4 justify-center">
          <Loader2 className="h-4 w-4 animate-spin" />
          {t('preview.loading')}
        </div>
      )}
      {error && (
        <div className="text-xs text-destructive bg-destructive/10 rounded p-2">
          {t('preview.failed', { error })}
        </div>
      )}
      {!loading && !error && content && (
        <ViewerContent runId={runId} embedded={embedded} expanded={expanded} viewer={viewer} content={content} file={file} ext={ext} maxHClass={maxHClass} />
      )}

      {/* Per-file "Open in Jupyter / Analyze in RStudio" buttons removed
          2026-10-20 (UI refinement): too much per row. Interactive sessions
          launch once from the "Interactive panel" button at the top of the
          output list, where files are selected — not per preview. */}
    </div>
  );
}

// ---------------------------------------------------------------------------
// ViewerContent — picks the right inline renderer
// ---------------------------------------------------------------------------

function ViewerContent({
  runId, embedded, expanded, viewer, content, file, ext, maxHClass,
}: {
  runId: string;
  viewer: ViewerKind;
  content: FetchedContent;
  file: { name: string; path: string; extension: string };
  ext: string;
  maxHClass?: string;
  /** Parent already supplies file identity, close and download controls. */
  embedded?: boolean;
  expanded?: boolean;
}) {
  switch (viewer) {
    case 'image':
      return expanded ? <img src={content.url} alt={file.name} className="w-full max-h-[80vh] object-contain" data-testid="expanded-output-image" /> : <InlineImageViewer src={content.url} name={file.name} />;

    case 'pdf':
      return content.pdfData ? <PdfCanvasViewer data={content.pdfData} name={file.name} /> : null;

    case 'html':
      // FIX #9.3 — a 256px iframe sandboxed with ONLY `allow-scripts` renders
      // JS-driven pipeline reports (Nextflow dag.html / report.html, MultiQC)
      // as a blank box: they need same-origin storage/XHR and a usable height.
      // We deliberately do NOT add `allow-same-origin`: `content.url` is a
      // blob: URL minted from the app's own origin, so a sandboxed iframe with
      // allow-scripts + allow-same-origin would inherit THIS app's origin and
      // let arbitrary report HTML read our cookies / localStorage / call our
      // credentialed APIs (stored-XSS). Instead we open the full report in a
      // new top-level tab (isolated browsing context, rel="noopener noreferrer"
      // severs window.opener), which also gives the report real screen space —
      // a 256px pane could never usefully display a full Nextflow report.
      return (
        <div className="w-full border rounded p-4 flex flex-col items-center gap-2 bg-muted/40 text-center">
          <ExternalLink className="h-5 w-5 text-muted-foreground" />
          <div className="text-xs text-muted-foreground max-w-xs">
            This is an interactive HTML report. Open it in a new tab for the full view.
          </div>
          <a
            href={content.url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1.5 text-xs text-primary hover:underline font-medium"
          >
            <ExternalLink className="h-3.5 w-3.5" />
            Open full report in a new tab
          </a>
        </div>
      );

    case 'table':
      return content.text != null ? <InlineTableViewer text={content.text} ext={ext} maxHClass={maxHClass} complete={expanded} /> : null;

    case 'sequence':
      return content.text != null ? <InlineSequenceViewer text={content.text} /> : null;

    case 'vcf':
      return content.text != null ? <InlineVcfViewer text={content.text} /> : null;

    case 'annotation':
      return content.text != null ? <InlineAnnotationViewer text={content.text} ext={ext} /> : null;

    case 'structure': {
      // PDB / mmCIF / CIF — render with 3Dmol.js (cartoon + spectrum default).
      // Falls back to text dump if the WebGL viewer fails to initialise.
      return content.text != null ? (
        <InlineStructureViewer text={stripAnsi(content.text)} ext={ext} />
      ) : null;
    }

    case 'text':
      return content.text != null ? <InlineTextViewer text={content.text} maxHClass={maxHClass} /> : null;

    case 'density':
      // Handled above in the self-fetching early-return path; unreachable here.
      return null;

    case 'download':
    default:
      return (
        embedded ? <p className="text-xs text-muted-foreground">{tOr('afterrun.preview_unavailable_download_card', 'Preview is unavailable. Use Download on the output card.')}</p> : <RunFileDownload runId={runId} file={file} />
      );
  }
}


// parsePlddtFromPdb + InlineStructureViewer now live in ./viewers/inline-content-viewers (imported above).
