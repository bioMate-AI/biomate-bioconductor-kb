/**
 * StepOutputPreview — inline viewer for a single Nextflow step output file.
 * Fetches file content from the /api/workflows/runs/:id/step-file endpoint
 * and renders it using the most appropriate viewer for the file type.
 */

import { useState, useEffect } from "react";
import { Loader2, X, FileText, Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface StepOutputPreviewProps {
  runId: string;
  file: { name: string; path: string; extension: string };
  onClose: () => void;
}

interface FetchedContent {
  url: string;
  contentType: string;
  text?: string;
}

// ---------------------------------------------------------------------------
// Extension → viewer category
// ---------------------------------------------------------------------------

const IMAGE_EXTS   = new Set(['png', 'jpg', 'jpeg', 'gif', 'svg', 'pdf']);
const TABLE_EXTS   = new Set(['csv', 'tsv', 'json', 'tabular', 'star']);
const SEQ_EXTS     = new Set(['fasta', 'fa', 'fastq', 'fq']);
const VCF_EXTS     = new Set(['vcf', 'bcf']);
const ANNOT_EXTS   = new Set(['bed', 'gff', 'gtf', 'gff3']);
const STRUCT_EXTS  = new Set(['pdb', 'mmcif', 'cif']);
const DENSITY_EXTS = new Set(['mrc', 'map', 'mrcs', 'rec']);
const HTML_EXTS    = new Set(['html', 'htm']);
const TEXT_EXTS    = new Set(['log', 'txt', 'sh', 'py', 'out', 'err']);

type ViewerKind =
  | 'image' | 'table' | 'sequence' | 'vcf' | 'annotation'
  | 'structure' | 'density' | 'html' | 'text' | 'download';

function resolveViewer(ext: string): ViewerKind {
  const e = ext.toLowerCase().replace(/^\./, '');
  if (IMAGE_EXTS.has(e))   return 'image';
  if (TABLE_EXTS.has(e))   return 'table';
  if (SEQ_EXTS.has(e))     return 'sequence';
  if (VCF_EXTS.has(e))     return 'vcf';
  if (ANNOT_EXTS.has(e))   return 'annotation';
  if (STRUCT_EXTS.has(e))  return 'structure';
  if (DENSITY_EXTS.has(e)) return 'density';
  if (HTML_EXTS.has(e))    return 'html';
  if (TEXT_EXTS.has(e))    return 'text';
  return 'download';
}

/** Viewers that need text content (not a blob URL). */
const TEXT_VIEWERS: ViewerKind[] = ['table', 'sequence', 'vcf', 'annotation', 'structure', 'text'];

// ---------------------------------------------------------------------------
// Lazy-import helpers for heavy viewers
// We use dynamic import + inline rendering to avoid circular deps with the
// existing Galaxy-API-backed viewers.  Text/table content is rendered directly.
// Structure / density viewers need the blob URL or ArrayBuffer, so we pass
// the object URL we created from the blob.
// ---------------------------------------------------------------------------

/** Simple table renderer for CSV/TSV/JSON content without requiring CsvTableViewer's
 *  Galaxy dataset plumbing.  Parses and renders the first 200 rows inline. */
function InlineTableViewer({ text }: { text: string }) {
  const lines = text.trim().split('\n').filter(Boolean);
  if (lines.length === 0) return <p className="text-xs text-muted-foreground">Empty file</p>;

  // JSON array detection
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
    } catch {
      // fall through to delimiter detection
    }
  }

  // Delimiter detection
  const firstLine = lines[0];
  const tabCount  = (firstLine.match(/\t/g)  || []).length;
  const commaCount = (firstLine.match(/,/g)   || []).length;
  const delimiter = tabCount >= commaCount ? '\t' : ',';

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

/** Lightweight FASTA/FASTQ sequence viewer. */
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

/** Lightweight VCF/BCF viewer — shows variant table. */
function InlineVcfViewer({ text }: { text: string }) {
  const lines = text.split('\n').filter(l => !l.startsWith('##'));
  const dataLines = lines.filter(l => l.trim() !== '');
  if (dataLines.length === 0) return <p className="text-xs text-muted-foreground">Empty VCF</p>;

  const headers = dataLines[0].startsWith('#CHROM')
    ? dataLines[0].slice(1).split('\t')
    : ['CHROM', 'POS', 'ID', 'REF', 'ALT', 'QUAL', 'FILTER', 'INFO'];
  const rows = dataLines
    .filter(l => !l.startsWith('#'))
    .slice(0, 100)
    .map(l => l.split('\t'));

  return <TableGrid headers={headers} rows={rows} totalRows={rows.length} />;
}

/** Lightweight annotation (BED/GFF) viewer. */
function InlineAnnotationViewer({ text, ext }: { text: string; ext: string }) {
  const lines = text.split('\n').filter(l => l.trim() && !l.startsWith('#') && !l.startsWith('track') && !l.startsWith('browser'));
  const isBed = ['bed'].includes(ext);
  const headers = isBed
    ? ['chrom', 'start', 'end', 'name', 'score', 'strand']
    : ['seqname', 'source', 'feature', 'start', 'end', 'score', 'strand', 'frame', 'attribute'];
  const rows = lines.slice(0, 100).map(l => l.split('\t'));
  return <TableGrid headers={headers} rows={rows} totalRows={lines.length} />;
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function StepOutputPreview({ runId, file, onClose }: StepOutputPreviewProps) {
  const [content, setContent] = useState<FetchedContent | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const ext = file.extension.toLowerCase().replace(/^\./, '');
  const viewer = resolveViewer(ext);
  const needsText = TEXT_VIEWERS.includes(viewer);

  useEffect(() => {
    let cancelled = false;
    let objectUrl: string | null = null;

    setLoading(true);
    setError(null);
    setContent(null);

    const url = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(file.path)}&name=${encodeURIComponent(file.name)}`;

    fetch(url)
      .then(async res => {
        if (!res.ok) {
          const body = await res.text();
          throw new Error(`HTTP ${res.status}: ${body}`);
        }
        const ct = res.headers.get('content-type') || 'application/octet-stream';

        if (needsText) {
          const text = await res.text();
          if (cancelled) return;
          setContent({ url, contentType: ct, text });
        } else {
          const blob = await res.blob();
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
  }, [runId, file.path, file.name, needsText]);

  return (
    <div className="mt-2 border rounded-md bg-background p-3">
      {/* Header */}
      <div className="flex items-center justify-between mb-2 gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <span className="text-xs font-mono font-medium truncate" title={file.name}>{file.name}</span>
        </div>
        <Button
          variant="ghost"
          size="sm"
          className="h-6 w-6 p-0 shrink-0"
          onClick={onClose}
          aria-label="Close preview"
        >
          <X className="h-3.5 w-3.5" />
        </Button>
      </div>

      {/* Content area */}
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
    </div>
  );
}

// ---------------------------------------------------------------------------
// ViewerContent — picks the right inline renderer
// ---------------------------------------------------------------------------

function ViewerContent({
  viewer,
  content,
  file,
  ext,
}: {
  viewer: ViewerKind;
  content: FetchedContent;
  file: { name: string; path: string; extension: string };
  ext: string;
}) {
  switch (viewer) {
    case 'image':
      return (
        <img
          src={content.url}
          alt={file.name}
          className="max-h-96 w-auto rounded border mx-auto block"
        />
      );

    case 'html':
      return (
        <iframe
          src={content.url}
          sandbox="allow-scripts"
          className="w-full h-64 border rounded"
          title={file.name}
        />
      );

    case 'table':
      return content.text != null
        ? <InlineTableViewer text={content.text} />
        : null;

    case 'sequence':
      return content.text != null
        ? <InlineSequenceViewer text={content.text} />
        : null;

    case 'vcf':
      return content.text != null
        ? <InlineVcfViewer text={content.text} />
        : null;

    case 'annotation':
      return content.text != null
        ? <InlineAnnotationViewer text={content.text} ext={ext} />
        : null;

    case 'structure':
      // Structure viewer needs data from /api/outputs/:id/display — not available here.
      // Fall back to text preview for PDB/mmCIF files.
      return content.text != null ? (
        <pre className="text-xs font-mono bg-muted p-2 rounded max-h-64 overflow-auto whitespace-pre-wrap">
          {content.text.slice(0, 4000)}{content.text.length > 4000 ? '\n…' : ''}
        </pre>
      ) : null;

    case 'density':
      // MRC/MAP files are binary — just offer a download link.
      return (
        <a
          href={content.url}
          download={file.name}
          className="inline-flex items-center gap-1.5 text-xs text-primary hover:underline"
        >
          <Download className="h-3.5 w-3.5" />
          Download {file.name}
        </a>
      );

    case 'text':
      return (
        <pre className={cn(
          "text-xs font-mono bg-muted p-2 rounded max-h-64 overflow-auto whitespace-pre-wrap"
        )}>
          {content.text}
        </pre>
      );

    case 'download':
    default:
      return (
        <a
          href={content.url}
          download={file.name}
          className="inline-flex items-center gap-1.5 text-xs text-primary hover:underline"
        >
          <Download className="h-3.5 w-3.5" />
          Download {file.name}
        </a>
      );
  }
}
