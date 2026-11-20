/**
 * RegisterModelForm — the connector "A model" flow, wired for real.
 *
 * Registers a hosted REST scoring endpoint as a runnable custom model:
 * POST /api/models/register-external -> CustomModelRegistry (mode 'rest') -> it appears
 * in the Models catalog (/api/models, origin 'custom') and runs via the existing
 * dispatch (POST {input_key: [smiles]} -> scores at output_path).
 *
 * Honest scope: a URL we can call is runnable now. A raw weights FILE is not — without a
 * serving runtime it can't infer — so this asks for an endpoint URL instead of faking it.
 */
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import { Brain, Loader2, CheckCircle2 } from 'lucide-react';

export function RegisterModelForm() {
  const { toast } = useToast();
  const [name, setName] = useState('');
  const [endpoint, setEndpoint] = useState('');
  const [inputKey, setInputKey] = useState('smiles');
  const [outputPath, setOutputPath] = useState('scores');
  const [advanced, setAdvanced] = useState(false);
  const [busy, setBusy] = useState(false);
  const [registered, setRegistered] = useState<string | null>(null);
  const [error, setError] = useState('');

  const valid = name.trim().length > 0 && /^https?:\/\//.test(endpoint.trim());

  const submit = async () => {
    setBusy(true); setError('');
    try {
      const r = await fetch('/api/models/register-external', {
        method: 'POST', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: name.trim(), endpoint: endpoint.trim(),
          input_key: inputKey.trim() || 'smiles', output_path: outputPath.trim() || 'scores',
        }),
      });
      const body = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(typeof body.error === 'string' ? body.error : typeof body.detail === 'string' ? body.detail : `Registration failed (HTTP ${r.status})`);
      setRegistered(body.name || name.trim());
      toast({ title: 'Model registered', description: `${body.name || name.trim()} is now in your Models library.` });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  if (registered) {
    return (
      <div className="space-y-3" data-testid="register-model-done">
        <div className="flex items-center gap-2 text-sm font-semibold"><CheckCircle2 className="w-4 h-4 text-emerald-600" /> Registered</div>
        <p className="text-xs text-muted-foreground">
          <strong className="text-foreground">{registered}</strong> is now in your Models library (Models → Library),
          runnable like any other model. It still needs held-out evidence before it can gate anything.
        </p>
        <Button size="sm" variant="outline" className="h-8 text-xs" onClick={() => { setRegistered(null); setName(''); setEndpoint(''); }} data-testid="register-model-another">
          Register another
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-3" data-testid="register-model-form">
      <div>
        <h3 className="text-sm font-semibold flex items-center gap-2"><Brain className="w-4 h-4" /> Register a model</h3>
        <p className="text-xs text-muted-foreground mt-1">
          Connect a hosted scoring endpoint — a URL we POST molecules to and read scores back. It becomes a
          real model in your Models library, runnable like any other. (A raw weights file needs a serving
          endpoint before it can run, so provide its URL here.)
        </p>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">Name</Label>
        <Input className="text-xs h-8" placeholder="My hERG scorer" value={name} onChange={e => setName(e.target.value)} data-testid="register-model-name" />
      </div>
      <div className="space-y-1.5">
        <Label className="text-xs">Scoring endpoint (URL)</Label>
        <Input className="font-mono text-xs h-8" placeholder="https://my-model.example.com/score" value={endpoint} onChange={e => setEndpoint(e.target.value)} data-testid="register-model-endpoint" />
        <p className="text-fs-xs text-muted-foreground">We POST {`{ ${inputKey || 'smiles'}: ["CCO", …] }`} and read numeric scores from <span className="font-mono">{outputPath || 'scores'}</span>.</p>
      </div>

      <button type="button" className="text-fs-xs text-muted-foreground underline" onClick={() => setAdvanced(a => !a)} data-testid="register-model-advanced-toggle">
        {advanced ? 'Hide' : 'Response format'}
      </button>
      {advanced && (
        <div className="grid grid-cols-2 gap-2">
          <div className="space-y-1"><Label className="text-fs-xs">Request key</Label><Input className="font-mono text-xs h-8" value={inputKey} onChange={e => setInputKey(e.target.value)} data-testid="register-model-inputkey" /></div>
          <div className="space-y-1"><Label className="text-fs-xs">Scores path</Label><Input className="font-mono text-xs h-8" value={outputPath} onChange={e => setOutputPath(e.target.value)} data-testid="register-model-outputpath" /></div>
        </div>
      )}

      {error && <p className="text-fs-xs text-destructive" role="alert" data-testid="register-model-error">{error}</p>}

      <Button size="sm" className="h-8 text-xs gap-1.5" disabled={!valid || busy} onClick={submit} data-testid="register-model-submit">
        {busy ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : null}
        {busy ? 'Registering…' : 'Register model'}
      </Button>
    </div>
  );
}

export default RegisterModelForm;
