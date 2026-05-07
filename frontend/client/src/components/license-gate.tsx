import React, { useCallback, useEffect, useState } from 'react';
import { CheckCircle, AlertTriangle, Info, Loader2, ExternalLink, KeyRound } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { CredentialModal, LicenseRequirement } from './credential-modal';

interface LicenseGateProps {
  nextflowPath: string;
  onBlockedChange: (blocked: boolean) => void;
}

export function LicenseGate({ nextflowPath, onBlockedChange }: LicenseGateProps) {
  const [loading, setLoading] = useState(true);
  const [requirements, setRequirements] = useState<LicenseRequirement[]>([]);
  const [modalTool, setModalTool] = useState<LicenseRequirement | null>(null);

  const fetchRequirements = useCallback(async () => {
    if (!nextflowPath) {
      setLoading(false);
      return;
    }
    try {
      const res = await fetch(
        `/api/workflows/license-requirements?nextflow_path=${encodeURIComponent(nextflowPath)}`
      );
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      const reqs: LicenseRequirement[] = data.requirements || [];
      setRequirements(reqs);
      // Only block execution when a required tool has no credential AND no built-in fallback.
      // Tools like Simcyp and NONMEM have workflow-level fallbacks (native PBPK / nlmixr2)
      // and should run in degraded mode rather than be blocked entirely.
      const hardBlocked = reqs.some(r => r.source === 'none' && !r.has_fallback);
      onBlockedChange(hardBlocked);
    } catch {
      setRequirements([]);
      onBlockedChange(false);
    } finally {
      setLoading(false);
    }
  }, [nextflowPath, onBlockedChange]);

  useEffect(() => { fetchRequirements(); }, [fetchRequirements]);

  if (!loading && requirements.length === 0) return null;

  return (
    <>
      <div className="rounded-md border border-border bg-card p-3 space-y-2">
        <div className="flex items-center gap-2 text-xs font-semibold text-muted-foreground uppercase tracking-wide">
          <KeyRound className="h-3.5 w-3.5" />
          Tool Credentials
        </div>

        {loading ? (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
            Checking license requirements…
          </div>
        ) : (
          <div className="space-y-2">
            {requirements.map(req => (
              <CredentialRow
                key={req.tool_id}
                requirement={req}
                onProvide={() => setModalTool(req)}
              />
            ))}
          </div>
        )}
      </div>

      {modalTool && (
        <CredentialModal
          tool={modalTool}
          onSaved={() => {
            setModalTool(null);
            setLoading(true);
            fetchRequirements();
          }}
          onClose={() => setModalTool(null)}
        />
      )}
    </>
  );
}

function CredentialRow({
  requirement,
  onProvide,
}: {
  requirement: LicenseRequirement;
  onProvide: () => void;
}) {
  const { source, display_name, vendor, registration_url, open_alternatives, has_fallback } = requirement;
  const resolved = source === 'user' || source === 'biomate';
  // Advisory = no credential but workflow has a built-in fallback (won't block execution)
  const advisory = !resolved && has_fallback;

  return (
    <div
      className={cn(
        'flex items-start gap-3 rounded-md px-3 py-2 text-sm',
        resolved
          ? 'bg-green-50/50 dark:bg-green-950/20 border border-green-200/60 dark:border-green-800/40'
          : advisory
          ? 'bg-blue-50/50 dark:bg-blue-950/20 border border-blue-200/60 dark:border-blue-800/40'
          : 'bg-amber-50/50 dark:bg-amber-950/20 border border-amber-200/60 dark:border-amber-800/40'
      )}
      data-testid={`license-row-${requirement.tool_id}`}
      data-status={resolved ? 'resolved' : advisory ? 'fallback' : 'blocked'}
    >
      <div className="mt-0.5 shrink-0">
        {resolved ? (
          <CheckCircle className="h-4 w-4 text-green-600 dark:text-green-400" />
        ) : advisory ? (
          <Info className="h-4 w-4 text-blue-600 dark:text-blue-400" />
        ) : (
          <AlertTriangle className="h-4 w-4 text-amber-600 dark:text-amber-400" />
        )}
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="font-medium">{display_name}</span>
          {vendor && <span className="text-xs text-muted-foreground">{vendor}</span>}
          {resolved && (
            <span className="text-xs text-green-600 dark:text-green-400">
              {source === 'user' ? '(your credentials)' : '(provided by BioMate)'}
            </span>
          )}
          {advisory && (
            <span className="text-xs text-blue-600 dark:text-blue-400">
              (running with open-source fallback)
            </span>
          )}
        </div>

        {advisory && open_alternatives && open_alternatives.length > 0 && (
          <p className="mt-1 text-xs text-blue-700 dark:text-blue-300">
            No {display_name} license — will use{' '}
            <strong>{open_alternatives[0].label}</strong> instead.{' '}
            {open_alternatives[0].note && (
              <span className="text-muted-foreground">{open_alternatives[0].note}.</span>
            )}
            {' '}Add your license in Settings → Credentials for full {display_name} capability.
          </p>
        )}

        {!resolved && !advisory && (
          <>
            <div className="mt-1.5 flex items-center gap-2 flex-wrap">
              <Button size="sm" variant="outline" className="h-7 text-xs" onClick={onProvide}>
                Provide credentials
              </Button>
              {registration_url && (
                <a
                  href={registration_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-1 text-xs text-blue-600 dark:text-blue-400 hover:underline"
                >
                  <ExternalLink className="h-3 w-3" />
                  Register
                </a>
              )}
            </div>
            {open_alternatives && open_alternatives.length > 0 && (
              <p className="mt-1 text-xs text-muted-foreground">
                Open alternatives: {open_alternatives.map(a => a.label).join(', ')}
              </p>
            )}
          </>
        )}
      </div>
    </div>
  );
}
