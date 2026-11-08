import { useEffect, useRef, useState } from 'react';
import type { PDFDocumentProxy, RenderTask } from 'pdfjs-dist';
import pdfWorkerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import { t, tOr } from '@/lib/i18n';
import { LocalPdfBinaryDataFactory } from './pdf-local-assets';

/** Canvas-only PDF rendering: no embedded browser plugin, HTML, PDF actions,
 * annotation links or script execution. The caller supplies already-authorized bytes.
 * Worker code is bundled locally; no document or credentials go to a CDN.
 */
export function PdfCanvasViewer({ data, name }: { data: Uint8Array; name: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [document, setDocument] = useState<PDFDocumentProxy | null>(null);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let cancelled = false;
    let task: ReturnType<typeof import('pdfjs-dist').getDocument> | undefined;
    setDocument(null);setPage(1);setError(null);setLoading(true);
    void import('pdfjs-dist').then(pdfjs => {
      if (cancelled) return;
      pdfjs.GlobalWorkerOptions.workerSrc = pdfWorkerUrl;
      // pdf.js transfers this buffer to its worker; keep the caller's bytes intact.
      task = pdfjs.getDocument({ data: data.slice(), stopAtErrors: true, useSystemFonts: true, useWorkerFetch: false, BinaryDataFactory: LocalPdfBinaryDataFactory });
      return task.promise.then(pdf => { if (!cancelled) setDocument(pdf); });
    }).catch(() => { if (!cancelled) { setError(tOr('preview.pdf_failed', 'Could not render this PDF.'));setLoading(false); } });
    return () => { cancelled = true; void task?.destroy(); };
  }, [data]);
  useEffect(() => {
    if (!document) return;
    let cancelled = false;
    let render: RenderTask | undefined;
    setLoading(true);setError(null);
    void document.getPage(page).then(pdfPage => {
      if (cancelled || !canvas.current) return;
      const target = canvas.current;
      const context = target.getContext('2d');
      if (!context) throw new Error('Canvas unavailable');
      const viewport = pdfPage.getViewport({ scale: 1.5 });
      target.width = viewport.width;target.height = viewport.height;
      render = pdfPage.render({ canvas: target, canvasContext: context, viewport });
      return render.promise;
    }).then(() => { if (!cancelled) setLoading(false); }).catch(() => {
      if (!cancelled) { setError(tOr('preview.pdf_failed', 'Could not render this PDF.'));setLoading(false); }
    });
    return () => { cancelled = true; render?.cancel(); };
  }, [document, page]);
  return <section aria-label={name} className="space-y-3" data-testid="pdf-canvas-viewer">
    {document && <div className="flex items-center justify-between gap-3 text-xs">
      <button type="button" disabled={page === 1 || loading} onClick={() => setPage(value => value - 1)}>{tOr('preview.previous_page', 'Previous page')}</button>
      <span>{tOr('preview.pdf_page_count', 'Page {{page}} of {{pages}}', {page, pages: document.numPages})}</span>
      <button type="button" disabled={page === document.numPages || loading} onClick={() => setPage(value => value + 1)}>{tOr('preview.next_page', 'Next page')}</button>
    </div>}
    {loading && <p role="status" className="text-xs text-muted-foreground">{t('preview.loading')}</p>}
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <canvas ref={canvas} role="img" aria-label={tOr('preview.pdf_page_label', '{{name}} — page {{page}}', {name, page})} className="max-w-full h-auto mx-auto border rounded" hidden={!!error || !document}/>
  </section>;
}
