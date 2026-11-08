import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { tOr } from '@/lib/i18n';
interface RegisteredVersion { campaign_id: string; model_name: string; version: number; status: string; gate?: { passed: boolean; reason?: string } }
export function TrainingRegistration({ runId, eligible = false }: { runId: string; eligible?: boolean }) {
 const [busy, setBusy] = useState(false);
 const [error, setError] = useState('');
 const [versions, setVersions] = useState<RegisteredVersion[] | null>(null);
 const endpoint = `/api/model-training-activity/${encodeURIComponent(runId)}`;
 async function read(register: boolean) {
  setBusy(true); setError('');
  try {
   const response = await fetch(`${endpoint}/${register ? 'register' : 'versions'}`, register ? { method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: '{}' } : { credentials: 'include' });
   const body = await response.json().catch(() => ({}));
   if (!response.ok) throw new Error(typeof body.error === 'string' ? body.error : typeof body.detail === 'string' ? body.detail : tOr('models.registration_failed', 'Could not read or register this training result.'));
   if (register) {
    const refreshed = await fetch(`${endpoint}/versions`, { credentials: 'include' });
    const data = await refreshed.json().catch(() => ({}));
    if (!refreshed.ok) throw new Error(data.error || tOr('models.registration_refresh_failed', 'Registration returned, but versions could not be refreshed. Check versions before retrying.'));
    setVersions(data.versions ?? []);
   } else setVersions(body.versions ?? []);
  } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
  finally { setBusy(false); }
 }
 return <div className="space-y-1" data-testid={`training-registration-${runId}`}>
   <div className="flex flex-wrap gap-2">
    {eligible && <Button size="sm" variant="outline" disabled={busy} onClick={() => read(true)}>{tOr('models.register_result', 'Register training result')}</Button>}
    <Button size="sm" variant="outline" disabled={busy} onClick={() => read(false)}>{tOr('models.check_versions', 'Check registered versions')}</Button>
   </div>
   {busy && <p role="status">{tOr('models.registration_pending', 'Checking training artifacts…')}</p>}
   {error && <p role="alert" className="text-destructive break-words">{error}</p>}
   {versions?.length === 0 && <p>{tOr('models.no_registered_versions', 'No registered version for this run. Older runs may lack the launch snapshot needed for registration.')}</p>}
   {versions?.map(version => <p key={`${version.campaign_id}:${version.model_name}:${version.version}`} data-testid="training-registered-version">{version.model_name} · v{version.version} · {version.status}{version.gate?.reason ? ` · ${version.gate.reason}` : ''}</p>)}
   {Boolean(versions?.length) && <p className="text-muted-foreground">{tOr('models.registration_not_serving', 'Registered artifact versions are not automatically deployed for inference.')}</p>}
 </div>;
}
