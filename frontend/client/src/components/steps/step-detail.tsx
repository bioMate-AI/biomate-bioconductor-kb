/**
 * StepDetail — the full step view, as a single object.
 *
 * Spec 08 ("The full step view"): a step opens into one surface that answers
 *   1. what fed this and what came out  (provenance row)
 *   2. the parameters it *actually ran with*, each tagged by origin, revertable
 *   3. each output rendered by its evidence class, with a rendered ⇄ raw switch
 *   4. a claim → output hook, so a Findings number can open the exact output
 *
 * This component does NOT re-implement the evidence-typed viewers. The rendered
 * view of each output is delegated to <StepOutputPreview>, which already resolves
 * image / table / density / structure / sequence / vcf / text by extension. The
 * only thing added here is the raw-bytes side of the toggle (fetched from the
 * same step-file endpoint), because "raw first: the summary is derived from these
 * bytes" is a first-class auditability claim.
 *
 * Honest empty states: where the backend does not supply a field (tool version,
 * parameter origin, duration), the view says so plainly. Nothing is fabricated.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import {
  X, ArrowRight, RotateCcw, FileText, Loader2, Download, ExternalLink,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn, stripAnsi } from "@/lib/utils";
import { StepOutputPreview } from "@/components/step-output-preview";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface StepDetailOutput {
  /** Stable id used by claim → output wiring (defaults to path). */
  id?: string;
  name: string;
  path: string;
  extension: string;
}

/** Origin of a resolved parameter value. */
export type ParamOrigin = "default" | "inherited" | "override";

export interface StepDetailParam {
  name: string;
  /** The value the step actually ran with. */
  value: unknown;
  /** Where the value came from. `undefined` → origin unknown (honest). */
  origin?: ParamOrigin;
  /** The workflow default, for a per-row revert. */
  defaultValue?: unknown;
  /** Optional human reason (e.g. "project instruction: high sensitivity"). */
  reason?: string;
}

export interface StepDetailStep {
  id: string;
  name: string;
  processName?: string;
  /** Tool that ran this step (e.g. "STAR", "salmon"). Optional — honest if absent. */
  tool?: string;
  /** Tool version. Optional — honest if absent. */
  toolVersion?: string;
  /** Wall-clock duration string (e.g. "6m 12s"). Optional. */
  duration?: string;
  /** Input chips: upstream dataset names / step names. Empty → "upstream step output". */
  inputs?: string[];
  /** Resolved parameter map this step ran with. */
  parameters?: Record<string, unknown>;
  /** Structured output files. */
  outputs?: StepDetailOutput[];
}

export interface StepDetailProps {
  runId: string;
  step: StepDetailStep;
  /** Optional Nextflow definition — used to resolve param defaults + origins. */
  workflowDefinition?: any;
  projectId?: string | null;
  onClose: () => void;
  /**
   * Claim → output scaffolding: a Findings number can call this with an output
   * id to select the exact output here. The finding-side wiring is a follow-up;
   * this component only needs to accept and honour the selection.
   */
  onOpenOutput?: (outputId: string) => void;
  /** Optional: open the parameter re-run flow (StepAdjustModal) for this step. */
  onAdjustAndRerun?: () => void;
}

// ---------------------------------------------------------------------------
// Param origin resolution (extends what StepAdjustModal collects)
// ---------------------------------------------------------------------------

/**
 * Build the resolved-params list. The step ran with `step.parameters`; the
 * workflow definition carries the defaults. Origin is inferred:
 *   - value == default            → "default"
 *   - value != default            → "override"
 *   - value from project (marked) → "inherited"   (only if the backend tags it)
 * If no default is known for a key, origin is left `undefined` (honest — we do
 * not claim "override" for a value we can't compare).
 */
export function resolveStepParams(
  parameters: Record<string, unknown> | undefined,
  workflowDefinition: any,
): StepDetailParam[] {
  const params = parameters || {};
  const reqList: any[] = Array.isArray(workflowDefinition?.required_params)
    ? workflowDefinition.required_params : [];
  const optList: any[] = Array.isArray(workflowDefinition?.optional_params)
    ? workflowDefinition.optional_params : [];
  const defByName = new Map<string, any>();
  for (const p of [...reqList, ...optList]) {
    if (p && typeof p.name === "string") defByName.set(p.name, p);
  }
  // Some backends carry a project-inherited marker map.
  const inherited: Record<string, unknown> =
    (workflowDefinition?.inherited_parameters && typeof workflowDefinition.inherited_parameters === "object")
      ? workflowDefinition.inherited_parameters
      : {};

  return Object.entries(params).map(([name, value]) => {
    const def = defByName.get(name);
    const hasDefault = def && Object.prototype.hasOwnProperty.call(def, "default");
    const defaultValue = hasDefault ? def.default : undefined;
    let origin: ParamOrigin | undefined;
    let reason: string | undefined;
    if (Object.prototype.hasOwnProperty.call(inherited, name) && sameValue(inherited[name], value)) {
      origin = "inherited";
      reason = typeof (workflowDefinition?.inherited_reasons?.[name]) === "string"
        ? workflowDefinition.inherited_reasons[name] : "from a project instruction";
    } else if (hasDefault) {
      origin = sameValue(defaultValue, value) ? "default" : "override";
    } // else: origin unknown → left undefined
    return { name, value, origin, defaultValue: hasDefault ? defaultValue : undefined, reason };
  });
}

function sameValue(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  // Loose match so 5 == "5" (params arrive as strings from forms).
  if (a == null || b == null) return false;
  return String(a) === String(b);
}

function fmtVal(v: unknown): string {
  if (v === true) return "true";
  if (v === false) return "false";
  if (v == null || v === "") return "—";
  return String(v);
}

// ---------------------------------------------------------------------------
// Origin badge
// ---------------------------------------------------------------------------

const ORIGIN_STYLE: Record<ParamOrigin, string> = {
  // default — grey, quiet (the workflow's own value)
  default: "bg-muted text-muted-foreground border-transparent",
  // inherited — accented, loud (the origin users are most surprised by)
  inherited: "bg-amber-100 text-amber-800 border-amber-300 dark:bg-amber-900/40 dark:text-amber-200 dark:border-amber-700",
  // override — marked (changed by hand)
  override: "bg-blue-100 text-blue-800 border-blue-300 dark:bg-blue-900/40 dark:text-blue-200 dark:border-blue-700",
};

function OriginBadge({ origin }: { origin?: ParamOrigin }) {
  const label = origin ?? "unknown";
  const style = origin
    ? ORIGIN_STYLE[origin]
    : "bg-muted/50 text-muted-foreground border-dashed border-muted-foreground/40";
  return (
    <span
      data-testid={`param-origin-${label}`}
      data-origin={label}
      className={cn("inline-block rounded border px-1.5 py-0.5 text-[10px] font-medium leading-none", style)}
      title={origin ? undefined : "origin not reported by the run — shown honestly rather than guessed"}
    >
      {label}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Raw-bytes viewer (the "raw" side of the rendered ⇄ raw toggle)
// ---------------------------------------------------------------------------

function RawBytesViewer({ runId, file }: { runId: string; file: StepDetailOutput }) {
  const [text, setText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const url = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(file.path)}&name=${encodeURIComponent(file.name)}`;

  useEffect(() => {
    let alive = true;
    setLoading(true); setError(null); setText(null);
    fetch(url)
      .then(async r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.text();
      })
      .then(t => { if (alive) { setText(stripAnsi(t)); setLoading(false); } })
      .catch(e => { if (alive) { setError(String((e as Error).message || e)); setLoading(false); } });
    return () => { alive = false; };
  }, [url]);

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-xs text-muted-foreground py-4 justify-center">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading raw bytes…
      </div>
    );
  }
  if (error) {
    // A binary artifact returns bytes the browser can't show as text — say so
    // plainly instead of a dead "download to inspect" (Terminal-surface rule).
    return (
      <div className="text-xs text-muted-foreground bg-muted/40 rounded p-3 space-y-1.5">
        <p>Raw bytes could not be read as text ({error}).</p>
        <a
          href={`${url}&download=1`}
          download={file.name}
          className="inline-flex items-center gap-1.5 text-primary hover:underline"
        >
          <Download className="h-3.5 w-3.5" /> Download {file.name}
        </a>
      </div>
    );
  }
  const shown = (text || "").slice(0, 8000);
  return (
    <div>
      <p className="text-[10px] text-muted-foreground mb-1">
        First bytes, exactly as written by the step. The rendered view above is derived from these.
      </p>
      <pre className="text-xs font-mono bg-muted p-2 rounded max-h-80 overflow-auto whitespace-pre-wrap">
        {shown || "— empty file —"}
        {text && text.length > 8000 ? "\n…" : ""}
      </pre>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function StepDetail({
  runId, step, workflowDefinition, projectId, onClose, onOpenOutput, onAdjustAndRerun,
}: StepDetailProps) {
  const outputs = useMemo<StepDetailOutput[]>(
    () => (step.outputs || []).map(o => ({ ...o, id: o.id ?? o.path })),
    [step.outputs],
  );
  const params = useMemo(
    () => resolveStepParams(step.parameters, workflowDefinition),
    [step.parameters, workflowDefinition],
  );

  const [selectedId, setSelectedId] = useState<string | null>(outputs[0]?.id ?? null);
  const [raw, setRaw] = useState(false);
  // Per-row live values, so "revert" is meaningful within the view.
  const [vals, setVals] = useState<Record<string, unknown>>(
    () => Object.fromEntries(params.map(p => [p.name, p.value])),
  );
  useEffect(() => {
    setVals(Object.fromEntries(params.map(p => [p.name, p.value])));
  }, [params]);

  // Claim → output scaffolding: honour an externally-requested output id.
  const requestedRef = useRef<string | null>(null);
  const openOutput = (id: string) => {
    requestedRef.current = id;
    setSelectedId(id);
    setRaw(false);
    onOpenOutput?.(id);
  };
  // Expose selection to callers by keeping selectedId in sync when outputs change.
  useEffect(() => {
    if (!selectedId && outputs[0]) setSelectedId(outputs[0].id!);
  }, [outputs, selectedId]);

  const selected = outputs.find(o => o.id === selectedId) || outputs[0] || null;
  const notDefault = params.filter(p => p.origin === "override" || p.origin === "inherited").length;

  return (
    <div
      data-testid="step-detail"
      className="rounded-lg border bg-background text-sm flex flex-col max-h-[85vh]"
    >
      {/* Header + provenance row */}
      <div className="border-b px-4 py-3 space-y-2">
        <div className="flex items-center gap-2">
          <div className="min-w-0">
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Full step view</p>
            <p className="font-semibold truncate" title={step.processName || step.name}>
              {step.processName || step.name}
            </p>
          </div>
          <div className="ml-auto flex items-center gap-1">
            {onAdjustAndRerun && (
              <Button variant="outline" size="sm" className="h-7 gap-1.5 text-xs" onClick={onAdjustAndRerun}>
                <RotateCcw className="h-3.5 w-3.5" /> Re-run from here
              </Button>
            )}
            <Button variant="ghost" size="sm" className="h-7 w-7 p-0" onClick={onClose} aria-label="Close full step view">
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Provenance: ran with [inputs] → [tool + version] → [N outputs] · duration */}
        <div
          data-testid="step-provenance"
          className="flex items-center gap-1.5 flex-wrap text-xs"
        >
          <span className="text-muted-foreground">ran with</span>
          {step.inputs && step.inputs.length > 0
            ? step.inputs.map((inp, i) => (
                <span key={i} className="rounded border bg-muted/60 px-1.5 py-0.5 font-mono">{inp}</span>
              ))
            : <span className="rounded border bg-muted/60 px-1.5 py-0.5 text-muted-foreground">upstream step output</span>}
          <ArrowRight className="h-3 w-3 text-muted-foreground" />
          <span className="rounded border bg-muted/60 px-1.5 py-0.5">
            {step.tool ? step.tool : <span className="text-muted-foreground">tool not reported</span>}
            {step.toolVersion
              ? <span className="ml-1 font-mono text-muted-foreground">{step.toolVersion}</span>
              : <span className="ml-1 text-[10px] text-muted-foreground">(version n/a)</span>}
          </span>
          <ArrowRight className="h-3 w-3 text-muted-foreground" />
          <span className="rounded border bg-muted/60 px-1.5 py-0.5">
            {outputs.length} output{outputs.length !== 1 ? "s" : ""}
          </span>
          <span className="ml-auto font-mono text-muted-foreground">
            {step.duration ? step.duration : "duration n/a"}
          </span>
        </div>
      </div>

      {/* Body */}
      <div className="overflow-auto px-4 py-3 space-y-4">
        {/* Outputs — tabs + rendered/raw switch */}
        <div>
          <div className="flex items-center gap-1.5 flex-wrap mb-2">
            {outputs.length === 0 && (
              <p className="text-xs text-muted-foreground">This step produced no output files, or none were recorded.</p>
            )}
            {outputs.map(o => (
              <button
                key={o.id}
                data-testid={`step-output-tab-${o.name}`}
                onClick={() => openOutput(o.id!)}
                className={cn(
                  "flex items-center gap-1 rounded border px-2 py-1 text-xs font-mono",
                  o.id === selectedId ? "border-primary bg-primary/10" : "border-transparent bg-muted/50 hover:bg-muted",
                )}
              >
                <FileText className="h-3 w-3 shrink-0" />
                <span className="truncate max-w-[160px]">{o.name}</span>
              </button>
            ))}
            {selected && (
              <div
                data-testid="rendered-raw-toggle"
                className="ml-auto inline-flex rounded-md border overflow-hidden"
                role="group"
                aria-label="rendered or raw"
              >
                <button
                  data-testid="toggle-rendered"
                  aria-pressed={!raw}
                  onClick={() => setRaw(false)}
                  className={cn("px-2 py-1 text-xs", !raw ? "bg-primary text-primary-foreground" : "bg-background hover:bg-muted")}
                >
                  rendered
                </button>
                <button
                  data-testid="toggle-raw"
                  aria-pressed={raw}
                  onClick={() => setRaw(true)}
                  className={cn("px-2 py-1 text-xs", raw ? "bg-primary text-primary-foreground" : "bg-background hover:bg-muted")}
                >
                  raw
                </button>
              </div>
            )}
          </div>

          {selected && (
            <div data-testid="step-output-body">
              {raw ? (
                <div data-testid="raw-view">
                  <RawBytesViewer runId={runId} file={selected} />
                </div>
              ) : (
                // Delegate to the shipped evidence-typed viewer — do NOT rebuild it.
                <div data-testid="rendered-view">
                  <StepOutputPreview
                    // Remount when the selected output changes so the viewer refetches.
                    key={selected.id}
                    runId={runId}
                    file={{ name: selected.name, path: selected.path, extension: selected.extension }}
                    onClose={() => { /* the detail surface owns closing */ }}
                    projectId={projectId}
                  />
                </div>
              )}
              <p className="text-[10px] text-muted-foreground mt-1.5">
                {raw
                  ? "Raw first: the summary above is derived from these bytes, and you can check it."
                  : "Rendered by the evidence class resolved from the output itself — the same viewer used on every surface."}
              </p>
            </div>
          )}
        </div>

        {/* Resolved parameters — origin badges + per-row revert */}
        <div>
          <div className="flex items-center gap-2 mb-2">
            <p className="text-xs font-semibold">Parameters this step actually ran with</p>
            <span
              data-testid="not-default-count"
              className="rounded border bg-muted/60 px-1.5 py-0.5 text-[10px] text-muted-foreground"
            >
              {notDefault} not default
            </span>
          </div>
          {params.length === 0 ? (
            <p className="text-xs text-muted-foreground">No parameters were recorded for this step.</p>
          ) : (
            <div className="space-y-1.5">
              {params.map(p => {
                const live = vals[p.name];
                const changed = !sameValue(live, p.value);
                return (
                  <div
                    key={p.name}
                    data-testid={`param-row-${p.name}`}
                    className="grid grid-cols-[minmax(0,1fr)_auto] gap-x-3 gap-y-0.5 items-baseline border-b pb-1.5 last:border-0"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="font-mono text-xs truncate">{p.name}</span>
                      <OriginBadge origin={p.origin} />
                    </div>
                    <div className="flex items-center gap-2 justify-self-end">
                      <span className="font-mono text-xs">{fmtVal(live)}</span>
                      {p.defaultValue !== undefined && changed && (
                        <button
                          data-testid={`param-revert-${p.name}`}
                          className="text-[11px] text-primary hover:underline"
                          onClick={() => setVals(v => ({ ...v, [p.name]: p.value }))}
                        >
                          revert
                        </button>
                      )}
                    </div>
                    {p.reason && (
                      <p className="col-span-2 text-[10px] text-muted-foreground">{p.reason}</p>
                    )}
                  </div>
                );
              })}
            </div>
          )}
          <p className="text-[10px] text-muted-foreground mt-2">
            Defaults are quiet; anything the project inherited or you overrode is marked. Where the run did not
            report an origin, the badge says <span className="font-medium">unknown</span> rather than guessing.
          </p>
        </div>
      </div>

      {/* Footer */}
      {selected && (
        <div className="border-t px-4 py-2 flex items-center gap-2">
          <a
            href={`/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(selected.path)}&download=1`}
            download={selected.name}
            className="inline-flex items-center gap-1.5 text-xs text-primary hover:underline"
          >
            <Download className="h-3.5 w-3.5" /> Download {selected.name}
          </a>
          <span className="ml-auto text-[10px] text-muted-foreground inline-flex items-center gap-1">
            <ExternalLink className="h-3 w-3" /> the artifact itself, unmodified
          </span>
        </div>
      )}
    </div>
  );
}
