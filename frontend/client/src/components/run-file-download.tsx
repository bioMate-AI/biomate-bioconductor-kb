import { useState } from 'react';
import { Download, Loader2 } from 'lucide-react';
import { tOr } from '@/lib/i18n';

export function runFileUrl(runId: string, file: {name: string; path?: string}, download = false) {
  return `/api/workflows/runs/${encodeURIComponent(runId)}/step-file?${new URLSearchParams({path: file.path || file.name, name: file.name, ...(download ? {download:'1'} : {})})}`;
}

/** Always uses the owned, authenticated run-file route; never fetches a payload URL. */
export function RunFileDownload({runId, file}: {runId: string; file: {name: string; path?: string}}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function download() {
    if (pending) return;
    setPending(true);setError(null);
    try {
      const response = await fetch(runFileUrl(runId,file,true), {credentials:'include', method:'HEAD'});
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      // Native attachment navigation streams large outputs without buffering
      // the whole file in JavaScript. HEAD validates auth/status first.
      const anchor = document.createElement('a');
      anchor.href=runFileUrl(runId,file,true);anchor.download=file.name;document.body.appendChild(anchor);
      anchor.click();anchor.remove();
    } catch (failure) {
      setError(tOr('afterrun.file_download_failed', 'Download failed ({{error}}). Try again.', {error: failure instanceof Error ? failure.message : 'network error'}));
    } finally {setPending(false);}
  }
  return <span className="inline-flex flex-col items-start gap-1">
    <button type="button" onClick={download} disabled={pending} aria-label={`${tOr('afterrun.download','Download')} ${file.name}`} className="inline-flex items-center gap-1 text-xs text-primary disabled:opacity-50">
      {pending ? <Loader2 size={12} className="animate-spin" /> : <Download size={12} />}
      {pending ? tOr('afterrun.preparing','Preparing…') : tOr('afterrun.download','Download')}
    </button>
    {error && <span role="alert" className="text-xs text-destructive">{error}</span>}
  </span>;
}
