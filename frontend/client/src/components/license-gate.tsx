import React, { useCallback, useEffect, useState } from 'react';
import { CheckCircle, AlertTriangle, Loader2, ExternalLink, KeyRound } from 'lucide-react';
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
      onBlockedChange(reqs.some(r => r.source === 'none'));
    } catch {
      // On error, don't block execution
      setRequirements([]);
      onBlockedChange(false);
    } finally {
      setLoading(false);
    }
  }, [nextflowPath, onBlockedChange]);

  useEffect(() => { fetchRequirements(); }, [fetchRequirements]);

  // Nothing to show if no requirements detected
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
  const { source, display_name, vendor, registration_url, open_alternatives } = requirement;
  const resolved = source === 'user' || source === 'biomate';

  return (
    <div
      className={cn(
        'flex items-start gap-3 rounded-md px-3 py-2 text-sm',
        resolved
          ? 'bg-green-50/50 dark:bg-green-950/20 border border-green-200/60 dark:border-green-800/40'
          : 'bg-amber-50/50 dark:bg-amber-950/20 border border-amber-200/60 dark:border-amber-800/40'
      )}
    >
      <div className="mt-0.5 shrink-0">
        {resolved ? (
          <CheckCircle className="h-4 w-4 text-green-600 dark:text-green-400" />
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
        </div>

        {!resolved && (
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
        )}

        {!resolved && open_alternatives && open_alternatives.length > 0 && (
          <p className="mt-1 text-xs text-muted-foreground">
            Open alternatives: {open_alternatives.map(a => a.label).join(', ')}
          </p>
        )}
      </div>
    </div>
  );
}
