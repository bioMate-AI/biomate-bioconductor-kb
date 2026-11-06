/**
 * Shared inline content viewers + the file-extension → viewer registry.
 *
 * Extracted from step-output-preview.tsx so BOTH the workflow step-output
 * preview AND the dataset object (Files module) render the same rich viewers
 * for the same file types — a PDB opens in 3D, a VCF as a variant table, a
 * FASTA as sequence cards, a BED/GFF as an annotation table — instead of each
 * surface reinventing a weaker preview. The actual heavy viewers live in
 * ./plddt-chart, ../file-content-view (TableGrid), and the lazy `3dmol` import.
 */
import { useEffect, useRef, useState } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { TableGrid } from "../file-content-view";
import { PlddtChart } from "./plddt-chart";

// ---------------------------------------------------------------------------
// File-extension → viewer registry
// ---------------------------------------------------------------------------

// Single-cell / AnnData formats → CellxGene interactive viewer
export const SINGLECELL_EXTS = new Set(['h5ad', 'loom', 'h5']);
export const IMAGE_EXTS   = new Set(['png', 'jpg', 'jpeg', 'gif', 'svg']);
// PDF is the dominant Bioconductor figure output (pdf()/ggsave .pdf). It is NOT an
// <img>-renderable raster — browsers display it natively in an <iframe>/<embed>.
// Putting it in IMAGE_EXTS rendered it in <img> → broken-image icon for most figures.
export const PDF_EXTS     = new Set(['pdf']);
export const TABLE_EXTS   = new Set(['csv', 'tsv', 'json', 'tabular', 'star']);
export const SEQ_EXTS     = new Set(['fasta', 'fa', 'fastq', 'fq']);
export const VCF_EXTS     = new Set(['vcf', 'bcf']);
export const ANNOT_EXTS   = new Set(['bed', 'gff', 'gtf', 'gff3']);
export const STRUCT_EXTS  = new Set(['pdb', 'mmcif', 'cif']);
export const DENSITY_EXTS = new Set(['mrc', 'map', 'mrcs', 'rec']);
// CryoSPARC binary dataset format — not browser-renderable, offer download only
export const CRYO_BINARY_EXTS = new Set(['cs', 'csg']);
export const HTML_EXTS    = new Set(['html', 'htm']);
export const TEXT_EXTS    = new Set(['log', 'txt', 'sh', 'py', 'out', 'err']);
// R serialised objects — binary, open in RStudio
export const R_EXTS       = new Set(['rds', 'rdata']);

export type ViewerKind =
  | 'image' | 'pdf' | 'table' | 'sequence' | 'vcf' | 'annotation'
  | 'structure' | 'density' | 'r-object' | 'singlecell' | 'html' | 'text' | 'download';

export function resolveViewer(ext: string): ViewerKind {
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

/** Viewers that need text content (not a blob URL). */
export const TEXT_VIEWERS: ViewerKind[] = ['table', 'sequence', 'vcf', 'annotation', 'structure', 'text'];

/**
 * Viewers that fetch their own data — the caller skips the blob/text fetch
 * entirely and hands the URL to the viewer component directly.
 * 'r-object' and 'singlecell' are binary; no preview content to fetch.
 */
export const SELF_FETCHING: ViewerKind[] = ['density', 'r-object', 'singlecell'];

// ---------------------------------------------------------------------------
// Sequence viewer (FASTA / FASTQ)
// ---------------------------------------------------------------------------

export function InlineSequenceViewer({ text }: { text: string }) {
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

export function InlineVcfViewer({ text }: { text: string }) {
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

export function InlineAnnotationViewer({ text, ext }: { text: string; ext: string }) {
  const lines = text.split('\n').filter(l => l.trim() && !l.startsWith('#') && !l.startsWith('track') && !l.startsWith('browser'));
  const isBed = ext === 'bed';
  const headers = isBed
    ? ['chrom', 'start', 'end', 'name', 'score', 'strand']
    : ['seqname', 'source', 'feature', 'start', 'end', 'score', 'strand', 'frame', 'attribute'];
  const rows = lines.slice(0, 100).map(l => l.split('\t'));
  return <TableGrid headers={headers} rows={rows} totalRows={lines.length} />;
}

// ---------------------------------------------------------------------------
// Structure viewer (PDB / mmCIF) — 3Dmol.js with optional pLDDT chart
// ---------------------------------------------------------------------------

/**
 * Parse per-residue pLDDT confidence from a PDB B-factor column.
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
 * column) it renders the PlddtChart beside the 3D view. Clicking a residue in
 * the chart centres the 3D view on it: chart selection and structure selection
 * are one selection, not two.
 */
export function InlineStructureViewer({ text, ext }: { text: string; ext: string }) {
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
      <pre className="text-xs font-mono bg-muted p-2 rounded max-h-40 overflow-auto whitespace-pre-wrap">
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
