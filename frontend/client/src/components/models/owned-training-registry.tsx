import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { tOr } from '@/lib/i18n';
interface Version { model_name: string; version: number; status: string; artifact_sha256?: string; gate?: { metric?: string; value?: number | null; threshold?: number | null; reason?: string }; spec?: { sourceRunId?: string }; }
export function OwnedTrainingRegistry({ project }: { project?: string }) {
 const [rows, setRows] = useState<Version[]>([]);
 const [loading, setLoading] = useState(true);
 const [error, setError] = useState('');
 const [refresh, setRefresh] = useState(0);
 useEffect(() => {
  const controller = new AbortController(); setLoading(true); setError(''); setRows([]);
  fetch(`/api/model-training-versions${project ? `?project=${encodeURIComponent(project)}` : ''}`, { credentials: 'include', signal: controller.signal })
   .then(async response => { const body = await response.json(); if (!response.ok || !Array.isArray(body.versions)) throw new Error(typeof body.error === 'string' ? body.error : tOr('models.registry_load_error', 'Could not load registered training artifacts.')); return body.versions; })
   .then(versions => { if (!controller.signal.aborted) setRows(versions); })
   .catch(cause => { if (!controller.signal.aborted) setError(cause.message); })
   .finally(() => { if (!controller.signal.aborted) setLoading(false); });
  return () => controller.abort();
 }, [project, refresh]);
 return <section className="rounded border p-3 space-y-3" data-testid="owned-training-registry">
  <div className="flex flex-wrap items-center justify-between gap-2"><h3 className="text-sm font-semibold">{tOr('models.registered_artifacts', 'Registered training artifacts')}</h3><Button variant="outline" size="sm" disabled={loading} onClick={() => setRefresh(value => value + 1)}>{tOr('models.registry_refresh', 'Refresh versions')}</Button></div>
  <p className="text-xs text-muted-foreground">{tOr('models.registration_not_serving', 'Registered artifact versions are not automatically deployed for inference.')}</p>
  {loading ? <p role="status" className="text-xs">{tOr('models.registry_loading', 'Loading registered versions…')}</p> : error ? <p role="alert" className="text-xs text-destructive break-words">{error}</p> : rows.length ? rows.map(row => <details key={`${row.spec?.sourceRunId}:${row.model_name}:${row.version}`} className="rounded border p-2 text-xs break-words">
   <summary className="cursor-pointer">{row.model_name} · v{row.version} · {row.status}</summary>
   <div className="pt-2 space-y-1">
    {row.spec?.sourceRunId && <p>{tOr('models.registry_source_run', 'Source run')}: {row.spec.sourceRunId}</p>}
    {row.gate?.metric && <p>{row.gate.metric}: {row.gate.value ?? '—'} · {tOr('models.registry_threshold', 'Threshold')}: {row.gate.threshold ?? '—'}</p>}
    {row.gate?.reason && <p>{row.gate.reason}</p>}
    {row.artifact_sha256 && <p className="font-mono break-all">SHA-256: {row.artifact_sha256}</p>}
   </div>
  </details>) : <p className="text-xs text-muted-foreground">{tOr('models.registry_empty', 'No training artifacts have been registered in this scope.')}</p>}
 </section>;
}
