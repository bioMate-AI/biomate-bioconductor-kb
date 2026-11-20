/**
 * AddConnectorFlow — the guided "Add a connector" picker (design parity:
 * data_centroid_design_v2/dataui/Connectors.jsx ADD_CONNECTOR). Replaces the bare
 * 4-button switcher with the design's 5 kinds, each carrying its kind + mode + a
 * plain-language question and note. "A directory" opens a real scan-preview flow:
 * you give a path, the backend reports what it found and what each file will become,
 * and nothing is attached until you confirm.
 *
 * Backend contract (see frontend/server/routes.ts connector-directory endpoints):
 *   POST /api/connectors/directory/scan   { path }         -> { ok, summary, mapping, warnings }
 *   POST /api/connectors/directory/attach  { path, mode, projectId? } -> { ok, created, message }
 */
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import { FolderSearch, Database, Brain, Sparkles, Plug, ChevronLeft, Loader2, AlertTriangle } from 'lucide-react';
import { CONNECTOR_DIRECTORY_ENABLED } from '@/lib/feature-flags';

type ScanType = { ext: string; label: string; count: number; bytes: number; becomes: string };
type ScanResult = {
  ok: boolean;
  summary?: { totalFiles: number; totalBytes: number; root: string };
  mapping?: ScanType[];
  warnings?: string[];
  message?: string;
};

function humanBytes(n?: number): string {
  if (n == null || !Number.isFinite(n) || n < 0) return '—';
  if (n < 1024) return `${n} B`;
  const u = ['KB', 'MB', 'GB', 'TB']; let v = n / 1024, i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v >= 10 ? 0 : 1)} ${u[i]}`;
}

/** The directory scan-preview flow: path -> scan -> review -> attach. */
function DirectoryScanFlow({ onBack, projectId }: { onBack: () => void; projectId?: string }) {
  const { toast } = useToast();
  const [path, setPath] = useState('');
  // Index-in-place is the only real behavior; "copy in" was removed (it copied nothing).
  const mode = 'index' as const;
  const [scanning, setScanning] = useState(false);
  const [result, setResult] = useState<ScanResult | null>(null);
  const [attaching, setAttaching] = useState(false);

  const scan = async () => {
    if (!path.trim()) return;
    setScanning(true); setResult(null);
    try {
      const r = await fetch('/api/connectors/directory/scan', {
        method: 'POST', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: path.trim() }),
      });
      const data: ScanResult = await r.json().catch(() => ({ ok: false, message: 'Scan failed' }));
      if (!r.ok || !data.ok) {
        setResult({ ok: false, message: data.message || `Scan failed (${r.status})`, warnings: data.warnings });
      } else {
        setResult(data);
      }
    } catch (e) {
      setResult({ ok: false, message: e instanceof Error ? e.message : 'Scan failed' });
    } finally {
      setScanning(false);
    }
  };

  const attach = async () => {
    setAttaching(true);
    try {
      const r = await fetch('/api/connectors/directory/attach', {
        method: 'POST', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: path.trim(), mode, projectId }),
      });
      const data = await r.json().catch(() => ({ ok: false, message: 'Attach failed' }));
      if (!r.ok || !data.ok) {
        toast({ title: 'Could not attach', description: data.message || `Attach failed (${r.status})`, variant: 'destructive' });
      } else {
        toast({ title: 'Directory connected', description: data.message || `Created ${data.created ?? 0} dataset object(s).` });
        onBack();
      }
    } catch (e) {
      toast({ title: 'Could not attach', description: e instanceof Error ? e.message : 'Attach failed', variant: 'destructive' });
    } finally {
      setAttaching(false);
    }
  };

  return (
    <div className="space-y-4" data-testid="add-connector-directory">
      <button onClick={onBack} className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground" data-testid="directory-back">
        <ChevronLeft className="w-3.5 h-3.5" /> All connector kinds
      </button>
      <div>
        <h3 className="text-sm font-semibold flex items-center gap-2"><FolderSearch className="w-4 h-4" /> Connect a directory</h3>
        <p className="text-xs text-muted-foreground mt-1">
          A share, an HPC scratch path, or an instrument output folder. Indexing reads the files where they
          are and creates dataset objects that point at them — a large run directory is never copied.
        </p>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">Directory path</Label>
        <div className="flex gap-2">
          <Input
            className="font-mono text-xs h-8"
            placeholder="/mnt/shared/run_2026_08_14  or  \\\\host\\share\\outputs"
            value={path}
            onChange={e => setPath(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter' && path.trim() && !scanning) scan(); }}
            data-testid="directory-path-input"
          />
          <Button size="sm" className="h-8 text-xs gap-1" onClick={scan} disabled={scanning || !path.trim()} data-testid="directory-scan-btn">
            {scanning ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <FolderSearch className="w-3.5 h-3.5" />}
            {scanning ? 'Scanning…' : 'Scan'}
          </Button>
        </div>
        <p className="text-fs-xs text-muted-foreground">Nothing is attached until you have seen what the scan found.</p>
      </div>

      {result && !result.ok && (
        <div className="rounded-md border border-destructive/40 bg-destructive/5 p-3 text-xs text-destructive flex items-start gap-2" data-testid="directory-scan-error">
          <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-0.5" />
          <span>{result.message || 'The directory could not be scanned.'}</span>
        </div>
      )}

      {result?.ok && result.summary && (
        <div className="space-y-3" data-testid="directory-scan-result">
          <div className="text-xs text-muted-foreground">
            Found <strong className="text-foreground">{result.summary.totalFiles}</strong> files
            ({humanBytes(result.summary.totalBytes)}) under <span className="font-mono">{result.summary.root}</span>.
          </div>
          {(result.warnings || []).map((w, i) => (
            <div key={i} className="text-fs-xs text-amber-700 dark:text-amber-400 flex items-start gap-1.5">
              <AlertTriangle className="w-3 h-3 shrink-0 mt-0.5" />{w}
            </div>
          ))}
          <div className="rounded-md border border-border overflow-hidden">
            <table className="w-full text-xs">
              <thead>
                <tr className="bg-muted/50 text-muted-foreground">
                  <th className="text-left font-medium px-3 py-1.5">Type</th>
                  <th className="text-right font-medium px-3 py-1.5">Files</th>
                  <th className="text-right font-medium px-3 py-1.5">Size</th>
                  <th className="text-left font-medium px-3 py-1.5">Becomes</th>
                </tr>
              </thead>
              <tbody>
                {(result.mapping || []).map(m => (
                  <tr key={m.ext} className="border-t border-border" data-testid={`scan-type-${m.ext}`}>
                    <td className="px-3 py-1.5 font-mono">{m.label || m.ext || '—'}</td>
                    <td className="px-3 py-1.5 text-right">{m.count}</td>
                    <td className="px-3 py-1.5 text-right text-muted-foreground">{humanBytes(m.bytes)}</td>
                    <td className="px-3 py-1.5 text-muted-foreground">{m.becomes}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <p className="text-fs-xs text-muted-foreground">
            The files are indexed where they are — dataset objects point at them, nothing is copied.
          </p>

          <Button size="sm" className="h-8 text-xs gap-1.5" onClick={attach} disabled={attaching} data-testid="directory-attach-btn">
            {attaching ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : null}
            {attaching ? 'Attaching…' : `Attach ${result.summary.totalFiles} files as dataset objects`}
          </Button>
        </div>
      )}
    </div>
  );
}

export interface AddConnectorFlowProps {
  onPickDatabase: () => void;
  onPickMcp: () => void;
  onPickModel: () => void;
  onPickSkill: () => void;
  onPickInstrument: () => void;
  projectId?: string;
}

const KINDS: {
  key: string; title: string; kind: string; mode: string; q: string; note: string;
  icon: React.ReactNode; action?: keyof Omit<AddConnectorFlowProps, 'projectId'>;
}[] = [
  { key: 'directory', title: 'A directory', kind: 'Data source', mode: 'Index in place', icon: <FolderSearch className="w-4 h-4" />,
    q: 'A share, an HPC scratch path, an instrument output folder.',
    note: 'Indexing reads the files where they are and creates dataset objects that point at them — a 4 TB run directory is not copied.' },
  { key: 'database', title: 'A database', kind: 'Data source', mode: 'Connection + a read scope', icon: <Database className="w-4 h-4" />, action: 'onPickDatabase',
    q: 'Postgres, SQLite, a warehouse, an internal registry.',
    note: 'A read-only role and the tables it may see. A pull becomes a dataset object whose origin records the query and the time it ran — so a result can be reproduced against a moving database.' },
  { key: 'model', title: 'A model', kind: 'Model', mode: 'Hosted scoring endpoint', icon: <Brain className="w-4 h-4" />, action: 'onPickModel',
    q: 'A hosted endpoint or vendor service that scores molecules.',
    note: 'Give its URL and it becomes a runnable model in your Models library, scored like any other. (A raw weights file needs a serving endpoint first.) It still needs held-out evidence before it can gate anything.' },
  { key: 'instrument', title: 'An instrument', kind: 'Data source', mode: 'Feed + residency', icon: <Database className="w-4 h-4" />, action: 'onPickInstrument',
    q: 'A sequencer, a plate reader, a microscope — a device that emits data.',
    note: 'Its output folder becomes a connected directory; runs read from it in place as new files arrive.' },
  { key: 'skill', title: 'A skill or expert', kind: 'Skill', mode: 'Say what it needs and produces', icon: <Sparkles className="w-4 h-4" />, action: 'onPickSkill',
    q: 'A section to draft, a fit to run, a figure to build, or a reading your specialists always apply.',
    note: 'You describe it in your own words. It cannot change a parameter — to change what runs, write it in a project’s instructions.' },
  { key: 'mcp', title: 'An MCP server', kind: 'MCP server', mode: 'URL + auth + a capability review', icon: <Plug className="w-4 h-4" />, action: 'onPickMcp',
    q: 'A tool server that gives the agent capabilities we did not build.',
    note: 'Its tools are listed before it is attached, and each one it contributes is marked with the server it came from — so an unexplained agent capability is always attributable.' },
];

export function AddConnectorFlow(props: AddConnectorFlowProps) {
  const [directory, setDirectory] = useState(false);
  if (directory) return <DirectoryScanFlow onBack={() => setDirectory(false)} projectId={props.projectId} />;

  return (
    <div className="space-y-3" data-testid="add-connector-flow">
      <div>
        <h3 className="text-sm font-semibold">Add a connector</h3>
        <p className="text-xs text-muted-foreground mt-0.5">
          Every kind can be added, including your own. Local is not a separate kind — a directory is a data
          source, your own weights are a model. What changes is where it lives and whether anything is copied.
        </p>
      </div>
      <div className="space-y-2">
        {/* The directory connector needs on-prem scan roots; hide it entirely where it
            can't work (hosted cloud) rather than show a connector that always refuses. */}
        {KINDS.filter(k => k.key !== 'directory' || CONNECTOR_DIRECTORY_ENABLED).map(k => (
          <div key={k.key} className="flex items-start gap-3 rounded-md border border-border p-3" data-testid={`add-kind-${k.key}`}>
            <div className="min-w-0 flex-1 space-y-1">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="inline-flex items-center gap-1.5 text-fs-base font-semibold">{k.icon}{k.title}</span>
                <span className="text-fs-xs rounded-full bg-muted px-2 py-0.5 text-muted-foreground">{k.kind}</span>
                <span className="text-fs-xs rounded-full bg-primary/10 px-2 py-0.5 text-primary">{k.mode}</span>
              </div>
              <p className="text-fs-sm text-muted-foreground">{k.q}</p>
              <p className="text-fs-sm text-muted-foreground/90">{k.note}</p>
            </div>
            <Button
              size="sm" variant="outline" className="h-7 text-xs shrink-0"
              data-testid={`add-kind-setup-${k.key}`}
              onClick={() => { if (k.key === 'directory') setDirectory(true); else if (k.action) props[k.action](); }}
            >
              Set up
            </Button>
          </div>
        ))}
      </div>
      {CONNECTOR_DIRECTORY_ENABLED && (
        <p className="text-fs-xs text-muted-foreground">
          Nothing is attached until you have seen what was found. A directory scan reports the file types and
          counts it detected, and what each will become, before it creates a single dataset object.
        </p>
      )}
    </div>
  );
}

export default AddConnectorFlow;
