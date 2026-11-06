// Grounded Standards Assistant — BioMate panel (prototype, drop-in).
//
// Conventions match the existing frontend (see frontend/client/src/components/
// workflow-report-viewer.tsx): named export, shadcn primitives from
// "@/components/ui/*", Tailwind utility classes + var(--bm-*) tokens, relative
// "/api/..." fetch with an ok-check, lucide-react icons.
//
// Integration (see docs/20261014_GROUNDED_STANDARDS_ASSISTANT.md):
//   1. copy this file to frontend/client/src/components/grounded-assistant-panel.tsx
//   2. copy grounded-api.ts to frontend/client/src/lib/grounded-api.ts
//   3. add a <Route path="/grounded"> in App.tsx wrapped in <PlatformLayout>
//   4. add a sidebar button in app-sidebar.tsx -> setLocation('/grounded')
//   5. add POST /api/grounded/answer in frontend/server/routes.ts -> Galaxy engine

import { useState } from "react";
import { ShieldCheck, AlertTriangle, FileText, Lock, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { askGrounded, type GroundedAnswer, type GroundedSource } from "@/lib/grounded-api";

const TIER_CLASS: Record<string, string> = {
  A: "bg-emerald-500/15 text-emerald-400",
  B: "bg-blue-500/15 text-blue-400",
  C: "bg-violet-500/15 text-violet-400",
  D: "bg-amber-500/15 text-amber-400",
};

const GRADE_CLASS: Record<string, string> = {
  high: "border-emerald-500 text-emerald-400",
  moderate: "border-amber-500 text-amber-400",
  low: "border-orange-500 text-orange-400",
  not_established: "border-red-500 text-red-400",
};

function SourceLine({ s }: { s: GroundedSource }) {
  return (
    <div className="text-xs text-muted-foreground ml-1 flex items-start gap-1.5 my-0.5">
      <span className={`font-bold px-1.5 rounded ${TIER_CLASS[s.tier] ?? ""}`}>{s.tier}</span>
      <span>
        {s.citation} ·{" "}
        {s.verified ? "verified" : <span className="text-amber-400 font-semibold">UNVERIFIED</span>}
        {s.locator ? <> · <code className="px-1 rounded bg-muted">{s.locator}</code></> : null}
      </span>
    </div>
  );
}

export function GroundedAssistantPanel() {
  const [question, setQuestion] = useState(
    "Why is the steam dryness value threshold set to 0.95 in EN 285? " +
      "What experiments and committee work produced that specific number?"
  );
  const [answer, setAnswer] = useState<GroundedAnswer | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run() {
    setLoading(true);
    setError(null);
    try {
      setAnswer(await askGrounded(question));
    } catch (e: any) {
      setError(e?.message ?? "Request failed");
    } finally {
      setLoading(false);
    }
  }

  const grounded = answer?.claims.filter((c) => c.grounded) ?? [];
  const personal = answer?.claims.filter((c) => !c.grounded && c.sources.length) ?? [];
  const iso = answer?.isolation;

  return (
    <div className="flex flex-col gap-4" data-testid="grounded-panel">
      <div>
        <h1 className="text-lg font-semibold flex items-center gap-2">
          <ShieldCheck className="w-5 h-5 text-emerald-400" /> Grounded Standards Assistant
        </h1>
        <p className="text-sm text-muted-foreground">
          Grounds what the authoritative record supports, names where it stops, and routes
          the rest to the people who set the standard — never answering a regulated question
          from memory, never leaking one user's notes to another.
        </p>
      </div>

      <div className="rounded-lg border border-border p-4 flex flex-col gap-3">
        <Textarea
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          className="min-h-[70px]"
          data-testid="grounded-question"
        />
        <div className="flex justify-end">
          <Button onClick={run} disabled={loading || !question.trim()} data-testid="grounded-ask">
            {loading ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : null}
            {loading ? "Asking…" : "Ask"}
          </Button>
        </div>
      </div>

      {error ? (
        <div className="rounded-lg border border-red-500/40 text-red-400 p-4 text-sm">{error}</div>
      ) : null}

      {answer ? (
        <div className="rounded-lg border border-border p-4 flex flex-col gap-3" data-testid="grounded-answer">
          <div className="flex items-center gap-2 flex-wrap">
            <Badge variant="outline" className="capitalize">{answer.question_type}</Badge>
            <Badge variant="outline" className={GRADE_CLASS[answer.grade] ?? ""} data-testid="grounded-grade">
              grade: {answer.grade.replace("_", " ")}
            </Badge>
          </div>

          {grounded.length > 0 && (
            <section>
              <div className="text-xs uppercase tracking-wide text-muted-foreground mb-2 flex items-center gap-1.5">
                <FileText className="w-3.5 h-3.5" /> What the evidence supports
              </div>
              {grounded.map((c, i) => (
                <div key={i} className="border-l-2 border-emerald-500/60 pl-3 my-2.5">
                  <div className="text-sm mb-1">{c.text}</div>
                  {c.sources.map((s) => <SourceLine key={s.id} s={s} />)}
                </div>
              ))}
            </section>
          )}

          {answer.boundaries.map((b, i) => (
            <div key={i} className="rounded-lg border border-amber-700/60 bg-amber-950/30 p-3.5" data-testid="grounded-boundary">
              <h3 className="text-sm font-semibold text-amber-300 flex items-center gap-1.5 mb-2">
                <AlertTriangle className="w-4 h-4" /> Where the record stops — not answered from memory
              </h3>
              <div className="text-sm"><span className="font-semibold">Not grounded:</span> {b.question_fragment}</div>
              <div className="text-xs text-muted-foreground mt-1">{b.reason}</div>
              {b.escalate_to.length > 0 && (
                <>
                  <div className="text-sm font-semibold mt-2">Ask the people who hold this answer:</div>
                  <ul className="list-disc ml-5 text-sm text-muted-foreground">
                    {b.escalate_to.map((x, j) => <li key={j}>{x}</li>)}
                  </ul>
                </>
              )}
              {b.suggested_questions.length > 0 && (
                <>
                  <div className="text-sm font-semibold mt-2">Concrete questions to put to them:</div>
                  <ul className="list-disc ml-5 text-sm text-muted-foreground">
                    {b.suggested_questions.map((x, j) => <li key={j}>{x}</li>)}
                  </ul>
                </>
              )}
            </div>
          ))}

          {personal.length > 0 && (
            <section>
              <div className="text-xs uppercase tracking-wide text-muted-foreground mb-2">
                Your unverified notes (shown to you only — not evidence)
              </div>
              {personal.map((c, i) => (
                <div key={i} className="rounded-lg border border-dashed border-amber-500/60 bg-muted p-3 text-sm">
                  {c.text}
                </div>
              ))}
            </section>
          )}

          {iso && (
            <div className="text-xs text-muted-foreground border-t border-border pt-3 flex items-center gap-1.5 flex-wrap">
              <Lock className="w-3.5 h-3.5" />
              <span><b className="text-foreground">Provenance &amp; isolation audit</b> —</span>
              <span>authoritative sources used: <b className="text-foreground">{iso.shared_sources_used}</b></span>·
              <span>your own notes (demoted): <b className="text-foreground">{iso.own_personal_sources_used}</b></span>·
              <span>other users' private notes blocked: <b className="text-amber-400">{iso.other_tenant_personal_blocked}</b></span>
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
}
