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
import { t } from "@/lib/i18n";

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
// BED family (incl. ENCODE narrowPeak/broadPeak, bedGraph, BEDPE) + GFF/GTF intervals.
export const ANNOT_EXTS   = new Set(['bed', 'gff', 'gtf', 'gff3', 'narrowpeak', 'broadpeak', 'bedgraph', 'bedpe']);
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

/** One read of a FASTQ file: id, bases, and the per-base Phred quality decoded from the
 *  quality line (Sanger / Illumina 1.8+ encoding, ASCII − 33). */
export interface FastqRead { id: string; seq: string; qual: string; meanQ: number | null }

/** Parse up to `limit` 4-line FASTQ records. Quality lines may start with '@' or '+', so records
 *  are read by position, never by searching for the next '@'. */
export function parseFastq(text: string, limit = 20): FastqRead[] {
  const body = text.split('\n').map(l => l.replace(/\r$/, '')).filter(l => l.trim());
  const out: FastqRead[] = [];
  for (let i = 0; i + 1 < body.length && out.length < limit; i += 4) {
    if (!body[i]?.startsWith('@') || body[i + 1] === undefined) break;
    const qual = body[i + 2]?.startsWith('+') ? (body[i + 3] ?? '') : '';
    let sum = 0;
    for (let k = 0; k < qual.length; k++) sum += qual.charCodeAt(k) - 33;
    out.push({ id: body[i].slice(1).split(/\s+/)[0], seq: body[i + 1], qual, meanQ: qual.length ? sum / qual.length : null });
  }
  return out;
}

/** Colour of one base's Phred score: ≥30 good, 20–29 fair, <20 poor. */
const qClass = (q: number) => (q >= 30 ? 'bg-emerald-500' : q >= 20 ? 'bg-amber-500' : 'bg-red-500');

/** FASTA records as sequence cards (">" ids); FASTQ as reads ("@" ids) with their base quality. */
export function InlineSequenceViewer({ text }: { text: string }) {
  const first = text.split('\n').find(l => l.trim());
  if (first?.startsWith('@')) {
    const reads = parseFastq(text);
    return (
      <div className="max-h-64 overflow-auto space-y-1.5 text-xs font-mono" data-testid="inline-fastq-viewer">
        {reads.map((r, i) => (
          <div key={i} className="rounded border p-1.5 bg-muted/30" data-testid="inline-fastq-read">
            <p className="font-semibold text-blue-600 dark:text-blue-400 truncate">@{r.id}</p>
            <p className="break-all text-fs-xs leading-relaxed">{r.seq.slice(0, 200)}{r.seq.length > 200 ? '…' : ''}</p>
            {r.qual && (
              // One cell per base, height = Phred score (0–41): the read's quality at a glance.
              <div className="mt-0.5 flex h-3 items-end gap-px" aria-hidden title={t('dataset_obj.viewer_quality_track')}>
                {Array.from(r.qual.slice(0, 200)).map((c, k) => {
                  const q = c.charCodeAt(0) - 33;
                  return <span key={k} className={`w-0.5 ${qClass(q)}`} style={{ height: `${Math.max(8, Math.min(100, (q / 41) * 100))}%` }} />;
                })}
              </div>
            )}
            <p className="text-muted-foreground text-fs-xs" data-testid="inline-fastq-meta">
              {r.meanQ != null
                ? t('dataset_obj.viewer_read_meta', { len: r.seq.length.toLocaleString(), q: r.meanQ.toFixed(1) })
                : t('dataset_obj.viewer_seq_length', { len: r.seq.length.toLocaleString() })}
            </p>
          </div>
        ))}
        {reads.length === 0 && <p className="text-muted-foreground">{t('dataset_obj.viewer_no_reads')}</p>}
        {reads.length > 0 && <p className="text-muted-foreground font-sans text-fs-xs">{t('dataset_obj.viewer_phred_gloss')}</p>}
      </div>
    );
  }
  const lines = text.split('\n').map(l => l.replace(/\r$/, ''));
  const records: { id: string; seq: string }[] = [];
  let current: { id: string; seq: string } | null = null;
  for (const line of lines) {
    if (line.startsWith('>')) {
      if (current) records.push(current);
      current = { id: line.slice(1).split(/\s+/)[0], seq: '' };
    } else if (current && line && !line.startsWith(';') && !line.startsWith('#')) {
      current.seq += line.trim();
    }
    if (records.length >= 20) break;
  }
  if (current && records.length < 20) records.push(current);
  return (
    <div className="max-h-64 overflow-auto space-y-1.5 text-xs font-mono" data-testid="inline-fasta-viewer">
      {records.map((r, i) => (
        <div key={i} className="rounded border p-1.5 bg-muted/30">
          <p className="font-semibold text-blue-600 dark:text-blue-400 truncate">&gt;{r.id}</p>
          <p className="break-all text-fs-xs leading-relaxed">{r.seq.slice(0, 200)}{r.seq.length > 200 ? '…' : ''}</p>
          <p className="text-muted-foreground text-fs-xs">{t('dataset_obj.viewer_seq_length', { len: r.seq.length.toLocaleString() })}</p>
        </div>
      ))}
      {records.length === 0 && <p className="text-muted-foreground">{t('dataset_obj.viewer_no_sequences')}</p>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// VCF viewer
// ---------------------------------------------------------------------------

export function InlineVcfViewer({ text }: { text: string }) {
  const lines = text.split('\n').filter(l => !l.startsWith('##'));
  const dataLines = lines.filter(l => l.trim() !== '');
  if (dataLines.length === 0) return <p className="text-xs text-muted-foreground">{t('dataset_obj.viewer_vcf_empty')}</p>;
  const headers = dataLines[0].startsWith('#CHROM')
    ? dataLines[0].slice(1).split('\t')
    : ['CHROM', 'POS', 'ID', 'REF', 'ALT', 'QUAL', 'FILTER', 'INFO'];
  const rows = dataLines.filter(l => !l.startsWith('#')).slice(0, 100).map(l => l.split('\t'));
  return <TableGrid headers={headers} rows={rows} totalRows={rows.length} />;
}

// ---------------------------------------------------------------------------
// Annotation viewer (BED / GFF)
// ---------------------------------------------------------------------------

/** Column names per interval spec (UCSC BED / ENCODE peak / bedGraph / BEDPE / GFF). */
const ANNOT_COLUMNS: Record<string, string[]> = {
  bed: ['chrom', 'start', 'end', 'name', 'score', 'strand', 'thickStart', 'thickEnd', 'itemRgb', 'blockCount', 'blockSizes', 'blockStarts'],
  narrowpeak: ['chrom', 'start', 'end', 'name', 'score', 'strand', 'signalValue', 'pValue', 'qValue', 'peak'],
  broadpeak: ['chrom', 'start', 'end', 'name', 'score', 'strand', 'signalValue', 'pValue', 'qValue'],
  bedgraph: ['chrom', 'start', 'end', 'value'],
  bedpe: ['chrom1', 'start1', 'end1', 'chrom2', 'start2', 'end2', 'name', 'score', 'strand1', 'strand2'],
  gff: ['seqname', 'source', 'feature', 'start', 'end', 'score', 'strand', 'frame', 'attribute'],
};

/** Header for the observed column count: BED-family files carry a variable number
 *  of the spec's leading columns (BED3…BED12, BEDPE6…10); extra columns are numbered. */
export function annotationHeaders(ext: string, width: number): string[] {
  const e = ext.toLowerCase();
  const spec = ANNOT_COLUMNS[e] ?? ANNOT_COLUMNS[e === 'gtf' || e === 'gff3' ? 'gff' : 'bed'];
  const variable = e === 'bed' || e === 'bedpe';
  const base = variable ? spec.slice(0, Math.max(3, Math.min(width, spec.length))) : spec;
  const extra = Array.from({ length: Math.max(0, width - base.length) }, (_, i) => `col${base.length + i + 1}`);
  return [...base, ...extra];
}

export function InlineAnnotationViewer({ text, ext }: { text: string; ext: string }) {
  const lines = text.split('\n').filter(l => l.trim() && !l.startsWith('#') && !l.startsWith('track') && !l.startsWith('browser'));
  const rows = lines.slice(0, 100).map(l => l.replace(/\r$/, '').split('\t'));
  const width = rows.reduce((m, r) => Math.max(m, r.length), 0);
  return <TableGrid headers={annotationHeaders(ext, width)} rows={rows} totalRows={lines.length} />;
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
 * Is this PDB a PREDICTED model (whose B-factor column holds per-residue pLDDT), an
 * experimental structure (real temperature factors), or unknown? Read from the file itself:
 *  - predicted: the header names a predictor (AlphaFold, ColabFold, ESMFold, RoseTTAFold,
 *    OpenFold, Boltz, Chai) or EXPDTA says THEORETICAL MODEL / PREDICTED;
 *  - experimental: EXPDTA names an experimental method (X-ray / NMR / EM / neutron …), or a
 *    CRYST1 record carries a real unit cell (a model has none, or the 1 Å placeholder);
 *  - otherwise, with no header at all: predicted only when every residue's atoms share one
 *    B-factor (pLDDT is per residue; real temperature factors vary atom by atom).
 */
export function structureConfidenceSource(text: string): 'predicted' | 'experimental' | 'unknown' {
  const header: string[] = [];
  for (const line of text.split('\n')) {
    if (line.startsWith('ATOM') || line.startsWith('HETATM')) break;
    header.push(line);
  }
  const head = header.join('\n').toUpperCase();
  if (/ALPHAFOLD|COLABFOLD|ESMFOLD|ROSETTAFOLD|OPENFOLD|BOLTZ|CHAI-1|PLDDT/.test(head)) return 'predicted';
  const expdta = header.filter(l => l.startsWith('EXPDTA')).join(' ').toUpperCase();
  if (/THEORETICAL MODEL|PREDICTED/.test(expdta)) return 'predicted';
  if (/X-RAY|NMR|ELECTRON|NEUTRON|FIBER|DIFFRACTION|SOLUTION SCATTERING|CRYO/.test(expdta)) return 'experimental';
  const cryst = header.find(l => l.startsWith('CRYST1'));
  if (cryst) {
    const [a, b, c] = [cryst.slice(6, 15), cryst.slice(15, 24), cryst.slice(24, 33)].map(Number);
    if ([a, b, c].every(Number.isFinite) && !(a === 1 && b === 1 && c === 1)) return 'experimental';
  }
  if (/^HEADER/m.test(head)) return 'unknown';
  // No header: per-residue-constant B-factors are the signature of a confidence column.
  const byRes = new Map<string, Set<string>>();
  for (const line of text.split('\n')) {
    if (!line.startsWith('ATOM')) continue;
    const key = `${line.slice(21, 22)}:${line.slice(22, 27).trim()}`;
    const set = byRes.get(key) ?? new Set<string>();
    set.add(line.slice(60, 66).trim());
    byRes.set(key, set);
  }
  if (byRes.size === 0) return 'unknown';
  return Array.from(byRes.values()).every(s => s.size === 1) ? 'predicted' : 'unknown';
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
  // pLDDT only lives in the B-factor column of PDB-format PREDICTED structures; an X-ray /
  // NMR / EM structure's B-factors are temperature factors and never shown as confidence.
  const plddt = format === 'pdb' && structureConfidenceSource(text) === 'predicted' ? parsePlddtFromPdb(text) : [];
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
          // Cartoon draws only protein / nucleic-acid backbones (CA / P atoms); a small molecule or
          // a crystal (e.g. Si.cif) would render an empty canvas — show atoms instead.
          const hasBackbone = (viewer.selectedAtoms?.({ atom: ['CA', 'P'] }) ?? [1]).length > 0;
          if (style === 'cartoon' && !hasBackbone) {
            viewer.removeAllModels?.();
            if (!cancelled) setStyle('sphere');
            return;
          }
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
        <span className="text-xs text-muted-foreground mr-1">{t('dataset_obj.viewer_style')}</span>
        {(['cartoon', 'stick', 'sphere', 'line'] as const).map((s) => (
          <Button
            key={s}
            variant={style === s ? 'default' : 'outline'}
            size="sm"
            className="h-6 text-fs-xs px-2"
            onClick={() => setStyle(s)}
          >
            {t(`dataset_obj.viewer_style_${s}`)}
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
