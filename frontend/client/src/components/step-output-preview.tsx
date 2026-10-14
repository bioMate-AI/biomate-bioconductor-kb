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
 *   vcf     → variant table
 *   annotation → BED/GFF table
 *   structure  → PDB/mmCIF rendered with 3Dmol.js (cartoon + spectrum default)
 *   html    → sandboxed iframe
 *   text    → <pre> with tail toggle
 *   download → download link for unknown binary formats
 */

import { t } from "@/lib/i18n";
import { useState, useEffect, useRef } from "react";
import { Loader2, X, FileText, Download, ZoomIn, ChevronDown, ChevronUp, Laptop, Maximize2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn, stripAnsi } from "@/lib/utils";
import { DensityMapViewer } from "./viewers/density-map-viewer";
import { FscCurveChart } from "./viewers/fsc-curve-chart";
import { MotionHistogramChart } from "./viewers/motion-histogram-chart";
import { CtfQualityChart } from "./viewers/ctf-quality-chart";
import { InteractiveLauncher } from "./interactive-launcher";
import { useInteractiveToolsAvailable } from "@/hooks/use-interactive-tools";
import { PlddtChart } from "./viewers/plddt-chart";
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
  file: { name: string; path: string; extension: string };
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
}

interface FetchedContent {
  url: string;
  contentType: string;
  text?: string;
}

// ---------------------------------------------------------------------------
// Extension → viewer category
// ---------------------------------------------------------------------------

// Single-cell / AnnData formats → CellxGene interactive viewer
const SINGLECELL_EXTS = new Set(['h5ad', 'loom', 'h5']);
const IMAGE_EXTS   = new Set(['png', 'jpg', 'jpeg', 'gif', 'svg']);
// PDF is the dominant Bioconductor figure output (pdf()/ggsave .pdf). It is NOT an
// <img>-renderable raster — browsers display it natively in an <iframe>/<embed>.
// Putting it in IMAGE_EXTS rendered it in <img> → broken-image icon for most figures.
const PDF_EXTS     = new Set(['pdf']);
const TABLE_EXTS   = new Set(['csv', 'tsv', 'json', 'tabular', 'star']);
const SEQ_EXTS     = new Set(['fasta', 'fa', 'fastq', 'fq']);
const VCF_EXTS     = new Set(['vcf', 'bcf']);
const ANNOT_EXTS   = new Set(['bed', 'gff', 'gtf', 'gff3']);
const STRUCT_EXTS  = new Set(['pdb', 'mmcif', 'cif']);
const DENSITY_EXTS = new Set(['mrc', 'map', 'mrcs', 'rec']);
// CryoSPARC binary dataset format — not browser-renderable, offer download only
const CRYO_BINARY_EXTS = new Set(['cs', 'csg']);
const HTML_EXTS    = new Set(['html', 'htm']);
const TEXT_EXTS    = new Set(['log', 'txt', 'sh', 'py', 'out', 'err']);
// R serialised objects — binary, open in RStudio
const R_EXTS       = new Set(['rds', 'rdata']);

type ViewerKind =
  | 'image' | 'pdf' | 'table' | 'sequence' | 'vcf' | 'annotation'
  | 'structure' | 'density' | 'r-object' | 'singlecell' | 'html' | 'text' | 'download';

function resolveViewer(ext: string): ViewerKind {
  const e = ext.toLowerCase().replace(/^\./, '');
  if (IMAGE_EXTS.has(e))        return 'image';
  if (PDF_EXTS.has(e))          return 'pdf';
  if (TABLE_EXTS.has(e))        return 'table';
  if (SEQ_EXTS.has(e))          return 'sequence';
  if (VCF_EXTS.has(e))          return 'vcf';
  if (ANNOT_EXTS.has(e))        return 'annotation';
  if (STRUCT_EXTS.has(e))       return 'structure';
  if (DENSITY_EXTS.has(e))      return 'density';
  if (R_EXTS.has(e))            return 'r-object';
  if (SINGLECELL_EXTS.has(e))   return 'singlecell';
  if (CRYO_BINARY_EXTS.has(e))  return 'download';
  if (HTML_EXTS.has(e))         return 'html';
  if (TEXT_EXTS.has(e))         return 'text';
  return 'download';
}

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

/** Download URL for a step output — the honest fallback when the matching
 *  interactive tool isn't provisioned in this environment. */
function stepFileDownloadUrl(runId: string, file: { name: string; path: string }): string {
  return `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(file.path)}&name=${encodeURIComponent(file.name)}`;
}

/** Shown in place of an "Open in <tool>" button when that interactive tool
 *  isn't launchable here (it would 400). Offers the download instead of a dead
 *  button, so the user can analyze the file locally. */
function InteractiveUnavailableNote({
  runId, file, toolLabel,
}: { runId: string; file: { name: string; path: string }; toolLabel: string }) {
  return (
    <div className="flex flex-col gap-2" data-testid="interactive-unavailable">
      <p className="text-xs text-muted-foreground">
        {toolLabel} isn’t enabled in this environment. Download the file to analyze it locally.
      </p>
      <a href={stepFileDownloadUrl(runId, file)} download={file.name}>
        <Button size="sm" variant="outline" className="gap-1.5 h-7 text-xs">
          <Download className="h-3.5 w-3.5" />
          {t('preview.download_file', { name: file.name })}
        </Button>
      </a>
    </div>
  );
}

/** Viewers that need text content (not a blob URL). */
const TEXT_VIEWERS: ViewerKind[] = ['table', 'sequence', 'vcf', 'annotation', 'structure', 'text'];

/**
 * Viewers that fetch their own data — StepOutputPreview skips the blob/text
 * fetch entirely and hands the URL to the viewer component directly.
 * 'r-object' and 'singlecell' are binary; no preview content to fetch.
 */
const SELF_FETCHING: ViewerKind[] = ['density', 'r-object', 'singlecell'];

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

function parseStar(text: string): { headers: string[]; rows: string[][] } | null {
  const lines = text.split('\n');
  const headers: string[] = [];
  let inLoop = false;
  let dataStartIdx = -1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line === 'loop_') { inLoop = true; continue; }
    if (inLoop && line.startsWith('_')) {
      // "_rlnColumnName #N" — take just the column name, strip leading _
      headers.push(line.split(/\s+/)[0].slice(1));
    } else if (inLoop && headers.length > 0 && line && !line.startsWith('#') && !line.startsWith('data_')) {
      dataStartIdx = i;
      break;
    }
  }

  if (headers.length === 0 || dataStartIdx < 0) return null;

  const rows: string[][] = [];
  for (let i = dataStartIdx; i < lines.length && rows.length < 200; i++) {
    const line = lines[i].trim();
    if (!line || line.startsWith('#') || line.startsWith('data_') || line.startsWith('loop_') || line.startsWith('_')) continue;
    rows.push(line.split(/\s+/));
  }

  return rows.length > 0 ? { headers, rows } : null;
}

// ---------------------------------------------------------------------------
// Inline table viewer (CSV / TSV / JSON / STAR)
// ---------------------------------------------------------------------------

function InlineTableViewer({ text, ext }: { text: string; ext: string }) {
  const lines = text.trim().split('\n').filter(Boolean);
  if (lines.length === 0) return <p className="text-xs text-muted-foreground">{t('preview.empty_file')}</p>;

  // STAR / RELION format (used by CryoSPARC and RELION for particle tables)
  if (ext === 'star' || (text.includes('loop_') && text.includes('_rln'))) {
    const star = parseStar(text);
    if (star) {
      return (
        <>
          <p className="text-[10px] text-muted-foreground mb-1">STAR/RELION format · {star.rows.length} particles shown</p>
          <TableGrid headers={star.headers} rows={star.rows} totalRows={star.rows.length} />
        </>
      );
    }
  }

  const trimmed = text.trim();
  if (ext === 'json' || trimmed.startsWith('[') || trimmed.startsWith('{')) {
    let parsed: unknown;
    try { parsed = JSON.parse(trimmed); } catch { parsed = undefined; }
    if (parsed !== undefined) {
      // Only an array of records is tabular; objects and scalars keep their
      // structure — the CSV path below would split them on commas.
      if (Array.isArray(parsed) && parsed.length > 0 && parsed.every(r => r && typeof r === 'object' && !Array.isArray(r))) {
        const records = parsed as Record<string, unknown>[];
        const headers = Object.keys(records[0]);
        const rows = records.slice(0, 200).map(item =>
          headers.map(h => item[h] != null ? (typeof item[h] === 'object' ? JSON.stringify(item[h]) : String(item[h])) : '')
        );
        return <TableGrid headers={headers} rows={rows} totalRows={records.length} />;
      }
      return <InlineJsonViewer value={parsed} />;
    }
    if (ext === 'json') return <InlineTextViewer text={text} />;
  }

  // Delimiter detection (CSV / TSV)
  const firstLine = lines[0];
  const tabCount   = (firstLine.match(/\t/g)  || []).length;
  const commaCount = (firstLine.match(/,/g)   || []).length;
  const delimiter  = tabCount >= commaCount ? '\t' : ',';
  const headers = firstLine.split(delimiter).map(h => h.trim().replace(/^"|"$/g, ''));
  const rows = lines.slice(1, 201).map(l => l.split(delimiter).map(c => c.trim().replace(/^"|"$/g, '')));

  return <TableGrid headers={headers} rows={rows} totalRows={lines.length - 1} />;
}

/** Pretty-printed JSON; top-level multi-line strings (e.g. a tool's text report) are also shown with their line breaks. */
function InlineJsonViewer({ value }: { value: unknown }) {
  const multiline = value && typeof value === 'object' && !Array.isArray(value)
    ? Object.entries(value as Record<string, unknown>).filter((e): e is [string, string] => typeof e[1] === 'string' && e[1].includes('\n'))
    : [];
  return (
    <div data-testid="json-preview">
      <InlineTextViewer text={JSON.stringify(value, null, 2)} />
      {multiline.map(([key, str]) => (
        <div key={key} className="mt-2" data-testid="json-preview-text-field">
          <p className="text-[10px] text-muted-foreground mb-1 font-mono">{key}</p>
          <InlineTextViewer text={str} />
        </div>
      ))}
    </div>
  );
}

// Round a full-precision numeric string to ~4 significant figures for display
// (keeps non-numeric and integer-ish values verbatim). Spec 14.2: tables should
// show readable cells, not raw floats like 2.58942740502748.
function fmtCell(v: string | undefined): string {
  if (v == null || v === '') return '';
  const n = Number(v);
  if (!Number.isFinite(n) || !/^-?\d*\.?\d+(e-?\d+)?$/i.test(v.trim())) return v;
  if (Number.isInteger(n)) return v;
  // Only shorten genuinely long decimals; leave short ones (e.g. 0.05) alone.
  if (v.replace(/^-/, '').length <= 6) return v;
  const abs = Math.abs(n);
  if (abs !== 0 && (abs < 1e-4 || abs >= 1e6)) return n.toExponential(3);
  return String(Number(n.toPrecision(4)));
}

function TableGrid({ headers, rows, totalRows }: { headers: string[]; rows: string[][]; totalRows: number }) {
  return (
    <div className="rounded border text-xs font-mono">
      {/* Shape header — spec 14.2: the header states N rows × M cols. */}
      <div className="flex items-center justify-between px-2 py-1 border-b bg-muted/60 text-[10px] text-muted-foreground font-sans">
        <span>{totalRows.toLocaleString()} {totalRows === 1 ? 'row' : 'rows'} × {headers.length} {headers.length === 1 ? 'col' : 'cols'}</span>
        {totalRows > rows.length && <span>showing first {rows.length.toLocaleString()}</span>}
      </div>
      <div className="overflow-auto max-h-64">
        <table className="min-w-full">
          <thead className="sticky top-0 bg-muted">
            <tr>
              {headers.map((h, i) => (
                <th key={i} className="px-2 py-1 text-left font-semibold whitespace-nowrap border-b">{h || `Col ${i + 1}`}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, ri) => (
              <tr key={ri} className="hover:bg-muted/40 border-b last:border-0">
                {headers.map((_, ci) => (
                  <td key={ci} className="px-2 py-0.5 max-w-[180px] truncate" title={row[ci]}>{fmtCell(row[ci])}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

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
      <p className="text-[10px] text-muted-foreground text-center mt-1">Click to enlarge</p>

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

// ---------------------------------------------------------------------------
// Sequence viewer (FASTA / FASTQ)
// ---------------------------------------------------------------------------

function InlineSequenceViewer({ text }: { text: string }) {
  const lines = text.split('\n');
  const records: { id: string; seq: string }[] = [];
  let current: { id: string; seq: string } | null = null;
  for (const line of lines) {
    if (line.startsWith('>') || line.startsWith('@')) {
      if (current) records.push(current);
      current = { id: line.slice(1).split(/\s+/)[0], seq: '' };
    } else if (current && line && !line.startsWith('+') && !line.startsWith('#')) {
      current.seq += line;
    }
    if (records.length >= 20) break;
  }
  if (current) records.push(current);
  return (
    <div className="max-h-64 overflow-auto space-y-1.5 text-xs font-mono">
      {records.slice(0, 20).map((r, i) => (
        <div key={i} className="rounded border p-1.5 bg-muted/30">
          <p className="font-semibold text-blue-600 dark:text-blue-400 truncate">&gt;{r.id}</p>
          <p className="break-all text-[10px] leading-relaxed">{r.seq.slice(0, 200)}{r.seq.length > 200 ? '…' : ''}</p>
          <p className="text-muted-foreground text-[10px]">{r.seq.length} bp</p>
        </div>
      ))}
      {records.length === 0 && <p className="text-muted-foreground">No sequences found</p>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// VCF viewer
// ---------------------------------------------------------------------------

function InlineVcfViewer({ text }: { text: string }) {
  const lines = text.split('\n').filter(l => !l.startsWith('##'));
  const dataLines = lines.filter(l => l.trim() !== '');
  if (dataLines.length === 0) return <p className="text-xs text-muted-foreground">Empty VCF</p>;
  const headers = dataLines[0].startsWith('#CHROM')
    ? dataLines[0].slice(1).split('\t')
    : ['CHROM', 'POS', 'ID', 'REF', 'ALT', 'QUAL', 'FILTER', 'INFO'];
  const rows = dataLines.filter(l => !l.startsWith('#')).slice(0, 100).map(l => l.split('\t'));
  return <TableGrid headers={headers} rows={rows} totalRows={rows.length} />;
}

// ---------------------------------------------------------------------------
// Annotation viewer (BED / GFF)
// ---------------------------------------------------------------------------

function InlineAnnotationViewer({ text, ext }: { text: string; ext: string }) {
  const lines = text.split('\n').filter(l => l.trim() && !l.startsWith('#') && !l.startsWith('track') && !l.startsWith('browser'));
  const isBed = ext === 'bed';
  const headers = isBed
    ? ['chrom', 'start', 'end', 'name', 'score', 'strand']
    : ['seqname', 'source', 'feature', 'start', 'end', 'score', 'strand', 'frame', 'attribute'];
  const rows = lines.slice(0, 100).map(l => l.split('\t'));
  return <TableGrid headers={headers} rows={rows} totalRows={lines.length} />;
}

// ---------------------------------------------------------------------------
// Text viewer with tail toggle (log files are useful from the end)
// ---------------------------------------------------------------------------

function InlineTextViewer({ text }: { text: string }) {
  const cleanText = stripAnsi(text);
  const lines = cleanText.split('\n');
  const [showTail, setShowTail] = useState(lines.length > 50);
  const displayed = showTail ? lines.slice(-80).join('\n') : cleanText;
  return (
    <div>
      {lines.length > 50 && (
        <div className="flex items-center justify-between mb-1">
          <span className="text-[10px] text-muted-foreground">{t('preview.lines_total', { n: lines.length })}</span>
          <button
            onClick={() => setShowTail(t => !t)}
            className="text-[10px] text-primary flex items-center gap-0.5 hover:underline"
          >
            {showTail ? <><ChevronDown className="h-3 w-3" />{t('preview.show_from_start')}</> : <><ChevronUp className="h-3 w-3" />{t('preview.show_tail')}</>}
          </button>
        </div>
      )}
      <pre className={cn("text-xs font-mono bg-muted p-2 rounded max-h-64 overflow-auto whitespace-pre-wrap")}>
        {showTail && lines.length > 80 && <span className="text-muted-foreground italic">… {lines.length - 80} lines above …{'\n'}</span>}
        {displayed}
      </pre>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

// Density viewer wrapper — renders DensityMapViewer without going through
// the blob/text fetch machinery (the viewer fetches its own data).
function DensityPreview({ runId, file, onClose, projectId }: StepOutputPreviewProps) {
  const stepFileUrl = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(file.path)}&name=${encodeURIComponent(file.name)}`;
  return (
    <div className="mt-2">
      <div className="flex items-center justify-between mb-2 gap-2 px-1">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>
      <DensityMapViewer src={stepFileUrl} name={file.name} />
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
function RObjectPreview({ runId, file, onClose, projectId }: StepOutputPreviewProps) {
  const [launcherOpen, setLauncherOpen] = useState(false);
  const [summary, setSummary] = useState<RdsSummary | null>(null);
  const [sidecarTried, setSidecarTried] = useState(false);
  const { data: itAvail } = useInteractiveToolsAvailable();
  const rstudioAvailable = !itAvail || itAvail.tools.rstudio; // optimistic until known
  const output = { id: file.path, name: file.name, size: 0, type: file.extension };

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
        <span className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</span>
        {items.slice(0, 12).map((it, i) => (
          <span key={i} className="text-xs font-mono px-1.5 py-0.5 rounded bg-muted/60">{it}</span>
        ))}
        {items.length > 12 && <span className="text-[10px] text-muted-foreground">+{items.length - 12}</span>}
      </div>
    ) : null;

  return (
    <div className="mt-2 border rounded-md bg-background p-3">
      <div className="flex items-center justify-between mb-2 gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>

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
        <InteractiveUnavailableNote runId={runId} file={file} toolLabel="RStudio" />
      )}
    </div>
  );
}

/** Single-cell AnnData / Loom preview — binary format; cannot be read inline.
 *  Offers CellxGene (ideal for .h5ad / .loom) and Jupyter as fallback. */
function SingleCellPreview({ runId, file, onClose }: StepOutputPreviewProps) {
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
  const output = { id: file.path, name: file.name, size: 0, type: file.extension };

  const openWith = (tool: 'cellxgene' | 'jupyter') => {
    setLauncherTool(tool);
    setLauncherOpen(true);
  };

  return (
    <div className="mt-2 border rounded-md bg-background p-3">
      <div className="flex items-center justify-between mb-2 gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
          <X className="h-3.5 w-3.5" />
        </Button>
      </div>

      {/* In-app summary (UMAP + clusters + markers) from the pipeline's sidecar,
          when present. Self-hides and calls onAbsent when there's no sidecar. */}
      <SingleCellSummaryPanel runId={runId} file={file} onAbsent={() => setSummaryAbsent(true)} />

      {/* Deeper exploration (secondary when the summary is shown) / fallback. */}
      {anyAvailable ? (
        <div className="mt-3">
          <p className="text-[11px] text-muted-foreground mb-1">
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
          <InteractiveUnavailableNote runId={runId} file={file} toolLabel="Interactive viewers (CellxGene/Jupyter)" />
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
function CryoChartPreview({ runId, file, onClose, projectId, chartType }: StepOutputPreviewProps & {
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
      <div className="flex items-center justify-between mb-2 gap-2 px-1">
        <span className="text-xs font-mono font-medium truncate">{file.name}</span>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>
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
function DlJsonPreview({ runId, file, onClose, viewerKind }: StepOutputPreviewProps & {
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
      <div className="flex items-center justify-between mb-2 gap-2 px-1">
        <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label={t('preview.close')}>
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>
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

export function StepOutputPreview({ runId, file, onClose, projectId, onOpenFullStepView }: StepOutputPreviewProps) {
  const ext = file.extension.toLowerCase().replace(/^\./, '');
  const viewer = resolveViewer(ext);

  // Route density files to a separate component (avoids hook-after-conditional).
  if (viewer === 'density') {
    return <DensityPreview runId={runId} file={file} onClose={onClose} projectId={projectId} />;
  }

  // R object files — binary, no inline preview; offer RStudio launch instead.
  if (viewer === 'r-object') {
    return <RObjectPreview runId={runId} file={file} onClose={onClose} projectId={projectId} />;
  }

  // Single-cell AnnData/Loom files — binary; offer CellxGene launch.
  if (viewer === 'singlecell') {
    return <SingleCellPreview runId={runId} file={file} onClose={onClose} />;
  }

  // Route special CryoEM JSON reports to dedicated chart viewers.
  if (ext === 'json') {
    const chartType = resolveCryoChartViewer(file.name);
    if (chartType) {
      return <CryoChartPreview runId={runId} file={file} onClose={onClose} projectId={projectId} chartType={chartType} />;
    }
    // DL-model JSON sidecars (genomic tracks / ranked chemical hits).
    const dlKind = resolveDlJsonViewer(file.name);
    if (dlKind) {
      return <DlJsonPreview runId={runId} file={file} onClose={onClose} projectId={projectId} viewerKind={dlKind} />;
    }
  }

  return <FetchingPreview runId={runId} file={file} onClose={onClose} projectId={projectId} viewer={viewer} ext={ext} onOpenFullStepView={onOpenFullStepView} />;
}

function FetchingPreview({
  runId, file, onClose, projectId, viewer, ext, onOpenFullStepView,
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
        } else {
          let blob = await res.blob();
          if (cancelled) return;
          // The step-file endpoint sometimes serves binaries as
          // application/octet-stream; an <iframe> only renders a PDF blob whose
          // type is application/pdf. Force it so the inline viewer always works.
          if (viewer === 'pdf' && blob.type !== 'application/pdf') {
            blob = new Blob([blob], { type: 'application/pdf' });
          }
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
      <div className="flex items-center justify-between mb-2 gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          {onOpenFullStepView && (
            <Button
              variant="ghost"
              size="sm"
              className="h-6 gap-1 px-1.5 shrink-0 text-[11px]"
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
      </div>

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
        <ViewerContent viewer={viewer} content={content} file={file} ext={ext} />
      )}

      {/* Secondary action: open in the appropriate interactive tool.
          Shown for table/text/sequence/annotation/vcf viewers — all file types
          a biologist might want to analyse further. Image, PDF, structure,
          and density viewers are excluded (not useful in Jupyter/RStudio). */}
      {(['table', 'text', 'sequence', 'annotation', 'vcf'] as ViewerKind[]).includes(viewer)
        && !loading && !error && (() => {
          const { tool, label } = pickInteractiveTool(ext);
          return (
            <div className="mt-2 pt-2 border-t flex items-center gap-2 flex-wrap">
              <Button
                size="sm"
                variant="outline"
                className="gap-1.5 h-7 text-xs"
                onClick={() => { setLauncherTool(tool); setLauncherOpen(true); }}
              >
                <Laptop className="h-3.5 w-3.5" />
                {label}
              </Button>
              {tool !== 'jupyter' && (
                <Button
                  size="sm"
                  variant="ghost"
                  className="gap-1.5 h-7 text-xs"
                  onClick={() => { setLauncherTool('jupyter'); setLauncherOpen(true); }}
                  data-tool="jupyter"
                >
                  <Laptop className="h-3.5 w-3.5" />
                  {t('preview.open_jupyter')}
                </Button>
              )}
              <span className="text-[10px] text-muted-foreground">{t('preview.opens_preloaded')}</span>
            </div>
          );
        })()
      }

      {(['table', 'text', 'sequence', 'annotation', 'vcf'] as ViewerKind[]).includes(viewer) && (
        <InteractiveLauncher
          open={launcherOpen}
          onOpenChange={setLauncherOpen}
          outputs={[{ id: file.path, name: file.name, size: 0, type: file.extension }]}
          initialTool={launcherTool}
        />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// ViewerContent — picks the right inline renderer
// ---------------------------------------------------------------------------

function ViewerContent({
  viewer, content, file, ext,
}: {
  viewer: ViewerKind;
  content: FetchedContent;
  file: { name: string; path: string; extension: string };
  ext: string;
}) {
  switch (viewer) {
    case 'image':
      return <InlineImageViewer src={content.url} name={file.name} />;

    case 'pdf':
      // PDFs render natively in an iframe (vector figures stay sharp). Taller than
      // the html box since figures are usually full-page. A download link is offered
      // by the surrounding chrome for browsers without an inline PDF plugin.
      return (
        <iframe
          src={content.url}
          className="w-full h-96 border rounded"
          title={file.name}
        />
      );

    case 'html':
      return (
        <iframe src={content.url} sandbox="allow-scripts" className="w-full h-64 border rounded" title={file.name} />
      );

    case 'table':
      return content.text != null ? <InlineTableViewer text={content.text} ext={ext} /> : null;

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
      return content.text != null ? <InlineTextViewer text={content.text} /> : null;

    case 'density':
      // Handled above in the self-fetching early-return path; unreachable here.
      return null;

    case 'download':
    default:
      return (
        <a href={content.url} download={file.name} className="inline-flex items-center gap-1.5 text-xs text-primary hover:underline">
          <Download className="h-3.5 w-3.5" />
          {t('preview.download_file', { name: file.name })}
        </a>
      );
  }
}


/**
 * Parse per-residue pLDDT from a PDB's B-factor column.
 *
 * Spec 14 §14.2: a predicted structure carries "pLDDT in the B-factor column".
 * AlphaFold/ESMFold/Boltz write the per-residue confidence (0–100) into the
 * temperature-factor field of every atom. We read the CA (alpha-carbon) atom of
 * each residue — one representative value per residue, in residue order.
 *
 * PDB ATOM record fixed columns (0-based):
 *   [12:16] atom name · [17:20] resName · [22:26] resSeq · [60:66] tempFactor
 *
 * Returns [] when the file is not a per-residue-confidence PDB (no CA B-factors,
 * or values outside the 0–100 pLDDT range) — the caller then shows no chart
 * rather than a fabricated one.
 */
export function parsePlddtFromPdb(text: string): number[] {
  const out: number[] = [];
  const seen = new Set<string>();
  for (const line of text.split('\n')) {
    if (!line.startsWith('ATOM') && !line.startsWith('HETATM')) continue;
    const atomName = line.slice(12, 16).trim();
    if (atomName !== 'CA') continue;
    const chain = line.slice(21, 22);
    const resSeq = line.slice(22, 27).trim(); // include insertion code column
    const key = `${chain}:${resSeq}`;
    if (seen.has(key)) continue; // one value per residue (skip altlocs)
    const b = parseFloat(line.slice(60, 66));
    if (!Number.isFinite(b)) continue;
    seen.add(key);
    out.push(b);
  }
  if (out.length === 0) return [];
  // pLDDT is 0–100. If every value is outside that band (e.g. a crystal
  // structure's real temperature factors), it is not a confidence column — do
  // not present it as one.
  const inBand = out.every((v) => v >= 0 && v <= 100);
  return inBand ? out : [];
}

/**
 * InlineStructureViewer — 3Dmol.js rendering of PDB / mmCIF text content
 * fetched by the parent. Dynamic import keeps 3Dmol out of the main bundle.
 * Falls back to a text dump when WebGL or 3Dmol init fails.
 *
 * When the file is a predicted structure (per-residue pLDDT in the B-factor
 * column) it renders the PlddtChart beside the 3D view (Spec 08 §8.5 — "a
 * predicted structure opens the 3D view with its per-residue confidence
 * chart"). Clicking a residue in the chart centres the 3D view on it: chart
 * selection and structure selection are one selection, not two.
 */
function InlineStructureViewer({ text, ext }: { text: string; ext: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  // 3Dmol viewer instance, kept so the pLDDT chart's residue click can drive it.
  const viewerRef = useRef<any>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'fallback'>('loading');
  const [style, setStyle] = useState<'cartoon' | 'stick' | 'sphere' | 'line'>('cartoon');

  const format = ext === 'cif' || ext === 'mmcif' ? 'cif' : 'pdb';
  // pLDDT only lives in the B-factor column of PDB-format predicted structures.
  const plddt = format === 'pdb' ? parsePlddtFromPdb(text) : [];
  const hasConfidence = plddt.length > 0;

  useEffect(() => {
    if (!containerRef.current || !text) return;
    let cancelled = false;
    const container = containerRef.current;

    import('3dmol')
      .then((mod) => {
        if (cancelled) return;
        try {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const $3Dmol = (mod as any).default ?? mod;
          container.innerHTML = '';
          const viewer = $3Dmol.createViewer(container, { backgroundColor: 'white', antialias: true });
          viewer.addModel(text, format);
          const styleObj: Record<string, object> = {
            cartoon: { cartoon: { color: 'spectrum' } },
            stick: { stick: { radius: 0.15 } },
            sphere: { sphere: { scale: 0.4 } },
            line: { line: {} },
          };
          viewer.setStyle({}, styleObj[style]);
          viewer.zoomTo();
          viewer.render();
          viewerRef.current = viewer;
          (container as HTMLDivElement & { __viewer?: unknown }).__viewer = viewer;
          setStatus('ready');
        } catch (e) {
          console.warn('[InlineStructureViewer] 3Dmol init failed:', e);
          setStatus('fallback');
        }
      })
      .catch((e) => {
        console.warn('[InlineStructureViewer] 3Dmol import failed:', e);
        if (!cancelled) setStatus('fallback');
      });

    return () => { cancelled = true; viewerRef.current = null; };
  }, [text, ext, style, format]);

  // Centre the 3D view on a residue when the pLDDT chart fires a selection.
  const centreOnResidue = (residue: number) => {
    const viewer = viewerRef.current;
    if (!viewer) return;
    try {
      const sel = { resi: residue };
      // Highlight the selected residue as sticks over the base cartoon so the
      // centred position is legible, then zoom the camera to it.
      viewer.setStyle({}, { cartoon: { color: 'spectrum' } });
      viewer.setStyle(sel, { cartoon: { color: 'spectrum' }, stick: { radius: 0.2, color: 'orange' } });
      viewer.zoomTo(sel);
      viewer.render();
    } catch (e) {
      console.warn('[InlineStructureViewer] centreOnResidue failed:', e);
    }
  };

  if (status === 'fallback') {
    return (
      <pre className="text-xs font-mono bg-muted p-2 rounded max-h-64 overflow-auto whitespace-pre-wrap">
        {text.slice(0, 4000)}{text.length > 4000 ? '\n…' : ''}
      </pre>
    );
  }

  return (
    <div className="space-y-2" data-testid="inline-structure-viewer" data-has-confidence={hasConfidence ? 'true' : 'false'}>
      <div className="flex items-center gap-1">
        <span className="text-xs text-muted-foreground mr-1">Style:</span>
        {(['cartoon', 'stick', 'sphere', 'line'] as const).map((s) => (
          <Button
            key={s}
            variant={style === s ? 'default' : 'outline'}
            size="sm"
            className="h-6 text-[10px] px-2"
            onClick={() => setStyle(s)}
          >
            {s.charAt(0).toUpperCase() + s.slice(1)}
          </Button>
        ))}
        {status === 'loading' && (
          <Loader2 className="h-3 w-3 animate-spin text-muted-foreground ml-2" />
        )}
      </div>
      <div
        ref={containerRef}
        className="w-full bg-white rounded border"
        style={{ height: 320, position: 'relative' }}
      />
      {hasConfidence && (
        <PlddtChart plddt={plddt} onSelectResidue={centreOnResidue} />
      )}
    </div>
  );
}
