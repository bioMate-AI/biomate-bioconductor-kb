import { Download } from 'lucide-react';
import { tOr } from '@/lib/i18n';

export function runFileUrl(runId: string, file: {name: string; path?: string}, download = false) {
  return `/api/workflows/runs/${encodeURIComponent(runId)}/step-file?${new URLSearchParams({path: file.path || file.name, name: file.name, ...(download ? {download:'1'} : {})})}`;
}

/** Native navigation preserves the browser gesture and streams the owned file.
 * The authenticated server route enforces ownership and attachment headers.
 */
export function RunFileDownload({runId, file}: {runId: string; file: {name: string; path?: string}}) {
  return <a href={runFileUrl(runId, file, true)} download={file.name}
    aria-label={`${tOr('afterrun.download','Download')} ${file.name}`}
    className="inline-flex items-center gap-1 text-xs text-primary">
    <Download size={12} />{tOr('afterrun.download','Download')}
  </a>;
}
