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

import { useState, useEffect, useRef } from "react";
import { Loader2, X, FileText, Download, ZoomIn, ChevronDown, ChevronUp, Laptop, Pin } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn, stripAnsi } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";
import { DensityMapViewer } from "./viewers/density-map-viewer";
import { FscCurveChart } from "./viewers/fsc-curve-chart";
import { MotionHistogramChart } from "./viewers/motion-histogram-chart";
import { CtfQualityChart } from "./viewers/ctf-quality-chart";
import { InteractiveLauncher } from "./interactive-launcher";
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
   * Optional project ID. When provided, a "Pin to Workbench" button appears
   * in the preview header and POSTs the file to
   * /api/projects/:projectId/workbench/pins. If absent, the button is hidden
   * (silently no-op — callers without project context still get a working preview).
   */
  projectId?: string | null;
}

// ---------------------------------------------------------------------------
// PinToWorkbenchButton — header affordance that POSTs the active file to the
// project's workbench pin list. Hidden when projectId is absent.
// ---------------------------------------------------------------------------

export function PinToWorkbenchButton({
  runId, file, projectId,
}: {
  runId: string;
  file: { name: string; path: string; extension: string };
  projectId?: string | null;
}) {
  const [pinning, setPinning] = useState(false);
  const { toast } = useToast();
  if (!projectId) return null;

  const onPin = async () => {
    if (pinning) return;
    setPinning(true);
    try {
      const res = await fetch(`/api/projects/${projectId}/workbench/pins`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          runId,
          filePath: file.path,
          fileName: file.name,
        }),
      });
      if (!res.ok) {
        const txt = await res.text().catch(() => "");
        throw new Error(`HTTP ${res.status}${txt ? `: ${txt}` : ""}`);
      }
      toast({ title: "Pinned to Workbench", description: file.name });
    } catch (e: any) {
      toast({
        title: "Pin failed",
        description: e?.message ?? "Could not pin file",
        variant: "destructive",
      });
    } finally {
      setPinning(false);
    }
  };

  return (
    <Button
      variant="ghost"
      size="sm"
      className="h-6 px-1.5 shrink-0 gap-1 text-[11px]"
      onClick={onPin}
      disabled={pinning}
      aria-label="Pin to Workbench"
      data-testid="button-pin-to-workbench"
      title="Pin to Workbench"
    >
      <Pin className="h-3.5 w-3.5" />
      {pinning ? "Pinning…" : "Pin"}
    </Button>
  );
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
    return { tool: 'cellxgene', label: 'Explore in CellxGene' };
  if (R_EXTS.has(e) || e === 'rda')
    return { tool: 'rstudio', label: 'Open in RStudio' };
  if (TABLE_EXTS.has(e))
    return { tool: 'rstudio', label: 'Analyze in RStudio' };
  // sequences, annotations, VCF, text — Jupyter is the universal fallback
  return { tool: 'jupyter', label: 'Open in Jupyter' };
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
  if (lines.length === 0) return <p className="text-xs text-muted-foreground">Empty file</p>;

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

  // JSON array
  const trimmed = text.trim();
  if (trimmed.startsWith('[')) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>[];
      if (Array.isArray(parsed) && parsed.length > 0 && typeof parsed[0] === 'object') {
        const headers = Object.keys(parsed[0]);
        const rows = parsed.slice(0, 200).map(item =>
          headers.map(h => item[h] != null ? String(item[h]) : '')
        );
        return <TableGrid headers={headers} rows={rows} totalRows={parsed.length} />;
      }
    } catch { /* fall through */ }
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

function TableGrid({ headers, rows, totalRows }: { headers: string[]; rows: string[][]; totalRows: number }) {
  return (
    <div className="overflow-auto max-h-64 rounded border text-xs font-mono">
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
                <td key={ci} className="px-2 py-0.5 max-w-[180px] truncate" title={row[ci]}>{row[ci] ?? ''}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {totalRows > 200 && (
        <p className="text-[10px] text-muted-foreground px-2 py-1">
          Showing first 200 of {totalRows} rows
        </p>
      )}
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
          <span className="text-[10px] text-muted-foreground">{lines.length} lines total</span>
          <button
            onClick={() => setShowTail(t => !t)}
            className="text-[10px] text-primary flex items-center gap-0.5 hover:underline"
          >
            {showTail ? <><ChevronDown className="h-3 w-3" />Show from start</> : <><ChevronUp className="h-3 w-3" />Show tail (last 80 lines)</>}
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
          <PinToWorkbenchButton runId={runId} file={file} projectId={projectId} />
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label="Close preview">
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
          <PinToWorkbenchButton runId={runId} file={file} projectId={projectId} />
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label="Close preview">
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
    </div>
  );
}

/** Single-cell AnnData / Loom preview — binary format; cannot be read inline.
 *  Offers CellxGene (ideal for .h5ad / .loom) and Jupyter as fallback. */
function SingleCellPreview({ runId: _runId, file, onClose }: StepOutputPreviewProps) {
  const [launcherOpen, setLauncherOpen] = useState(false);
  const [launcherTool, setLauncherTool] = useState<'cellxgene' | 'jupyter'>('cellxgene');
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
        <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label="Close preview">
          <X className="h-3.5 w-3.5" />
        </Button>
      </div>
      <p className="text-xs text-muted-foreground mb-3">
        Single-cell AnnData / Loom object — open interactively to explore.
      </p>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" variant="outline" className="gap-1.5 h-7 text-xs" onClick={() => openWith('cellxgene')}>
          <Laptop className="h-3.5 w-3.5" />
          Explore in CellxGene
        </Button>
        <Button size="sm" variant="ghost" className="gap-1.5 h-7 text-xs" onClick={() => openWith('jupyter')}>
          <Laptop className="h-3.5 w-3.5" />
          Open in Jupyter
        </Button>
      </div>
      <InteractiveLauncher
        open={launcherOpen}
        onOpenChange={setLauncherOpen}
        outputs={[output]}
        initialTool={launcherTool}
      />
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
          <PinToWorkbenchButton runId={runId} file={file} projectId={projectId} />
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

export function StepOutputPreview({ runId, file, onClose, projectId }: StepOutputPreviewProps) {
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
  }

  return <FetchingPreview runId={runId} file={file} onClose={onClose} projectId={projectId} viewer={viewer} ext={ext} />;
}

function FetchingPreview({
  runId, file, onClose, projectId, viewer, ext,
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
          <PinToWorkbenchButton runId={runId} file={file} projectId={projectId} />
          <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onClose} aria-label="Close preview">
            <X className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>

      {loading && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground py-4 justify-center">
          <Loader2 className="h-4 w-4 animate-spin" />
          Loading preview…
        </div>
      )}
      {error && (
        <div className="text-xs text-destructive bg-destructive/10 rounded p-2">
          Failed to load file: {error}
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
                  Open in Jupyter
                </Button>
              )}
              <span className="text-[10px] text-muted-foreground">Opens with this file pre-loaded</span>
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
          Download {file.name}
        </a>
      );
  }
}


/**
 * InlineStructureViewer — 3Dmol.js rendering of PDB / mmCIF text content
 * fetched by the parent. Dynamic import keeps 3Dmol out of the main bundle.
 * Falls back to a text dump when WebGL or 3Dmol init fails.
 */
function InlineStructureViewer({ text, ext }: { text: string; ext: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'fallback'>('loading');
  const [style, setStyle] = useState<'cartoon' | 'stick' | 'sphere' | 'line'>('cartoon');

  useEffect(() => {
    if (!containerRef.current || !text) return;
    let cancelled = false;
    const container = containerRef.current;
    const format = ext === 'cif' || ext === 'mmcif' ? 'cif' : 'pdb';

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

    return () => { cancelled = true; };
  }, [text, ext, style]);

  if (status === 'fallback') {
    return (
      <pre className="text-xs font-mono bg-muted p-2 rounded max-h-64 overflow-auto whitespace-pre-wrap">
        {text.slice(0, 4000)}{text.length > 4000 ? '\n…' : ''}
      </pre>
    );
  }

  return (
    <div className="space-y-2">
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
    </div>
  );
}
