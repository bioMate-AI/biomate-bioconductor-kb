/**
 * Pilot Exit Survey — shown at the end of a pilot participant's session.
 * Captures all five pilot evaluation model hypotheses in one comprehensive form.
 * Accessible at /pilot-exit-survey (linked from session-end banner and email).
 *
 * Pilot KPIs collected:
 *   H1 — Workflow quality: % of runs without manual correction
 *   H2 — Time-to-result: avg time vs. baseline
 *   H3 — QC defensibility: % rated publication-ready (≥4/5)
 *   H4 — Pricing acceptance: % willing to pay $29/month
 *   H5 — Hallucination: 0-tolerance count
 */
import { useState } from "react";
import { useLocation } from "wouter";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Progress } from "@/components/ui/progress";
import { CheckCircle2, ChevronRight, ChevronLeft } from "lucide-react";

const PILOT_DIRECTIONS = [
  "A — Drug Discovery (ADMET, virtual screening, lead optimisation)",
  "B — RNA-seq / Precision Medicine",
  "C — Cryo-EM + AI Structures",
  "D — Single-Cell Perturbation",
  "E — Multi-Omics (Proteomics + Metabolomics)",
] as const;

const LIKERT_LABELS = [
  "1 — Strongly disagree",
  "2 — Disagree",
  "3 — Neutral",
  "4 — Agree",
  "5 — Strongly agree",
] as const;

const PRICING_OPTIONS = [
  "Yes — from my lab/department budget",
  "Yes — from a core facility or institutional subscription",
  "Maybe — depends on grant cycle",
  "No",
] as const;

const EXPERIENCE_OPTIONS = ["PI / Faculty", "Postdoc", "PhD student", "Research scientist", "Clinical researcher", "Other"] as const;

function LikertRow({
  id,
  label,
  value,
  onChange,
  sublabel,
}: {
  id: string;
  label: string;
  value: number | null;
  onChange: (v: number) => void;
  sublabel?: string;
}) {
  return (
    <div className="space-y-1">
      <Label className="text-sm font-medium">{label}</Label>
      {sublabel && <p className="text-xs text-muted-foreground">{sublabel}</p>}
      <div className="flex gap-1">
        {LIKERT_LABELS.map((lbl, i) => (
          <button
            key={i}
            title={lbl}
            data-testid={`exit-${id}-${i + 1}`}
            onClick={() => onChange(i + 1)}
            className={`flex-1 rounded border py-1.5 text-xs font-medium transition-colors ${
              value === i + 1
                ? "border-blue-500 bg-blue-500 text-white"
                : "border-border hover:bg-muted"
            }`}
          >
            {i + 1}
          </button>
        ))}
      </div>
      <div className="flex justify-between text-[10px] text-muted-foreground px-0.5">
        <span>Strongly disagree</span>
        <span>Strongly agree</span>
      </div>
    </div>
  );
}

// ── Survey state ──────────────────────────────────────────────────────────────
interface SurveyAnswers {
  // About you
  direction: string;
  role: string;
  // H1 — Workflow quality
  total_runs: string;
  runs_without_correction: string;
  manual_correction_description: string;
  // H2 — Time-to-result
  avg_time_minutes: string;
  prior_time_hours: string;
  // H3 — QC defensibility
  qc_publication_rating: number | null;
  qc_audit_log_useful: number | null;
  methods_text_used: boolean | null;
  // H4 — Pricing
  pricing_response: string;
  // H5 — Hallucinations
  hallucination_incidents: string;
  // Research intelligence
  literature_agent_used: boolean | null;
  literature_agent_rating: number | null;
  // Overall
  overall_rating: number | null;
  would_recommend: number | null;
  biggest_time_saving: string;
  biggest_gap: string;
  publish_together: boolean | null;
  free_text: string;
}

const EMPTY: SurveyAnswers = {
  direction: "", role: "",
  total_runs: "", runs_without_correction: "", manual_correction_description: "",
  avg_time_minutes: "", prior_time_hours: "",
  qc_publication_rating: null, qc_audit_log_useful: null, methods_text_used: null,
  pricing_response: "",
  hallucination_incidents: "0",
  literature_agent_used: null, literature_agent_rating: null,
  overall_rating: null, would_recommend: null,
  biggest_time_saving: "", biggest_gap: "", publish_together: null, free_text: "",
};

const PAGES = ["About you", "Workflow quality", "Time & QC", "Pricing & AI quality", "Overall"] as const;

export default function PilotExitSurveyPage() {
  const [, setLocation] = useLocation();
  const [page, setPage] = useState(0);
  const [answers, setAnswers] = useState<SurveyAnswers>(EMPTY);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = <K extends keyof SurveyAnswers>(key: K, val: SurveyAnswers[K]) =>
    setAnswers((a) => ({ ...a, [key]: val }));

  const handleSubmit = async () => {
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch("/api/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({
          feedback_type: "pilot_exit_survey",
          submitted_at: new Date().toISOString(),
          ...answers,
          // Derived metrics for dashboard
          workflow_quality_pct:
            answers.total_runs && answers.runs_without_correction
              ? (Number(answers.runs_without_correction) / Number(answers.total_runs)) * 100
              : null,
          time_saved_hours:
            answers.prior_time_hours && answers.avg_time_minutes
              ? Number(answers.prior_time_hours) - Number(answers.avg_time_minutes) / 60
              : null,
        }),
      });
      if (!res.ok) throw new Error(`Server error ${res.status}`);
      setSubmitted(true);
    } catch (e: any) {
      setError(e.message ?? "Submission failed. Please try again.");
    } finally {
      setSubmitting(false);
    }
  };

  if (submitted) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-4">
        <Card className="max-w-lg w-full border-green-200 bg-green-50 dark:border-green-800 dark:bg-green-950/20">
          <CardContent className="pt-8 pb-8 text-center space-y-4">
            <CheckCircle2 className="h-12 w-12 text-green-600 mx-auto" />
            <h2 className="text-xl font-semibold text-green-800 dark:text-green-200">
              Thank you for your feedback
            </h2>
            <p className="text-sm text-green-700 dark:text-green-300">
              Your responses directly validate the pilot study hypotheses and will be used
              to improve BioMate for the research community. We will share the aggregated
              results with you at the pilot debrief.
            </p>
            <Button onClick={() => setLocation("/dashboard")} variant="outline">
              Return to dashboard
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  const progressPct = Math.round(((page + 1) / PAGES.length) * 100);

  return (
    <div className="min-h-screen bg-background px-4 py-10">
      <div className="max-w-2xl mx-auto space-y-6">

        {/* Header */}
        <div>
          <h1 className="text-2xl font-bold text-foreground">BioMate Pilot Study — Exit Survey</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Step {page + 1} of {PAGES.length} · {PAGES[page]}
          </p>
          <Progress value={progressPct} className="mt-3 h-2" />
        </div>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">{PAGES[page]}</CardTitle>
            {page === 0 && (
              <CardDescription>
                Help us understand the context of your pilot participation.
              </CardDescription>
            )}
          </CardHeader>
          <CardContent className="space-y-5 text-sm">

            {/* ── Page 0: About you ─────────────────────────────────────── */}
            {page === 0 && (
              <>
                <div>
                  <Label>Which pilot direction did you participate in?</Label>
                  <div className="flex flex-col gap-2 mt-2">
                    {PILOT_DIRECTIONS.map((d) => (
                      <button
                        key={d}
                        data-testid={`exit-direction-${d[0]}`}
                        onClick={() => set("direction", d)}
                        className={`text-left rounded border px-3 py-2 text-sm transition-colors ${
                          answers.direction === d
                            ? "border-blue-500 bg-blue-50 dark:bg-blue-950/20 font-medium"
                            : "border-border hover:bg-muted"
                        }`}
                      >
                        {d}
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <Label>Your role</Label>
                  <div className="flex flex-wrap gap-2 mt-2">
                    {EXPERIENCE_OPTIONS.map((r) => (
                      <button
                        key={r}
                        data-testid={`exit-role-${r.toLowerCase().replace(/\s+/g, "-")}`}
                        onClick={() => set("role", r)}
                        className={`rounded border px-3 py-1 text-xs transition-colors ${
                          answers.role === r
                            ? "border-blue-500 bg-blue-500 text-white"
                            : "border-border hover:bg-muted"
                        }`}
                      >
                        {r}
                      </button>
                    ))}
                  </div>
                </div>
              </>
            )}

            {/* ── Page 1: Workflow quality (H1) ─────────────────────────── */}
            {page === 1 && (
              <>
                <p className="text-xs text-muted-foreground bg-muted/50 rounded p-3">
                  <strong>H1 target:</strong> ≥ 80% of workflows run end-to-end without manual parameter correction.
                </p>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label>Total workflows submitted during pilot</Label>
                    <Input
                      type="number" min={0} placeholder="e.g. 12"
                      data-testid="exit-total-runs"
                      className="mt-1"
                      value={answers.total_runs}
                      onChange={(e) => set("total_runs", e.target.value)}
                    />
                  </div>
                  <div>
                    <Label>Ran without manual correction</Label>
                    <Input
                      type="number" min={0} placeholder="e.g. 10"
                      data-testid="exit-correct-runs"
                      className="mt-1"
                      value={answers.runs_without_correction}
                      onChange={(e) => set("runs_without_correction", e.target.value)}
                    />
                  </div>
                </div>
                {answers.total_runs && answers.runs_without_correction && (
                  <div className="text-xs text-blue-700 dark:text-blue-300 bg-blue-50 dark:bg-blue-950/20 rounded px-3 py-2">
                    Workflow quality: {Math.round((Number(answers.runs_without_correction) / Number(answers.total_runs)) * 100)}%
                    {" "}{Number(answers.runs_without_correction) / Number(answers.total_runs) >= 0.8 ? "✅ Meets H1 target (≥ 80%)" : "⚠ Below H1 target (≥ 80%)"}
                  </div>
                )}
                <div>
                  <Label>If you needed to correct something, briefly describe what (optional)</Label>
                  <Textarea
                    placeholder="e.g. had to specify the genome reference manually the first time"
                    className="mt-1"
                    rows={2}
                    data-testid="exit-correction-description"
                    value={answers.manual_correction_description}
                    onChange={(e) => set("manual_correction_description", e.target.value)}
                  />
                </div>
                <div>
                  <Label>Number of times BioMate used a tool name or parameter that did not exist (hallucinations)</Label>
                  <Input
                    type="number" min={0} placeholder="0"
                    data-testid="exit-hallucinations"
                    className="mt-1 w-24"
                    value={answers.hallucination_incidents}
                    onChange={(e) => set("hallucination_incidents", e.target.value)}
                  />
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Target: 0 incidents. Count only commands that referenced a tool or parameter that does not exist.
                  </p>
                </div>
              </>
            )}

            {/* ── Page 2: Time & QC (H2, H3) ───────────────────────────── */}
            {page === 2 && (
              <>
                <p className="text-xs text-muted-foreground bg-muted/50 rounded p-3">
                  <strong>H2 target:</strong> ≤ 30 min query-to-result.&ensp;
                  <strong>H3 target:</strong> ≥ 70% of outputs rated 4 or 5 (publication-ready).
                </p>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <Label>Average time from query to result (minutes)</Label>
                    <Input
                      type="number" min={0} placeholder="e.g. 25"
                      data-testid="exit-avg-time"
                      className="mt-1"
                      value={answers.avg_time_minutes}
                      onChange={(e) => set("avg_time_minutes", e.target.value)}
                    />
                    {answers.avg_time_minutes && (
                      <p className={`text-xs mt-0.5 ${Number(answers.avg_time_minutes) <= 30 ? "text-green-600" : "text-amber-600"}`}>
                        {Number(answers.avg_time_minutes) <= 30 ? "✅ Meets H2 target (≤ 30 min)" : "⚠ Above H2 target (≤ 30 min)"}
                      </p>
                    )}
                  </div>
                  <div>
                    <Label>This analysis previously took me approximately (hours)</Label>
                    <Input
                      type="number" min={0} step={0.5} placeholder="e.g. 6"
                      data-testid="exit-prior-time"
                      className="mt-1"
                      value={answers.prior_time_hours}
                      onChange={(e) => set("prior_time_hours", e.target.value)}
                    />
                  </div>
                </div>

                <LikertRow
                  id="qc_rating"
                  label="The QC output is suitable for a research manuscript methods section."
                  sublabel="5 = strongly agree = publication-ready. H3 target: ≥ 70% of responses are 4 or 5."
                  value={answers.qc_publication_rating}
                  onChange={(v) => set("qc_publication_rating", v)}
                />

                <LikertRow
                  id="qc_audit_useful"
                  label="The audit log / methods report text saved me time in documenting the analysis."
                  value={answers.qc_audit_log_useful}
                  onChange={(v) => set("qc_audit_log_useful", v)}
                />

                <div>
                  <Label>Did you copy the auto-generated methods text into a manuscript or lab record?</Label>
                  <div className="flex gap-2 mt-1">
                    {(["Yes", "No", "Partially"] as const).map((opt) => (
                      <Button
                        key={opt}
                        size="sm"
                        data-testid={`exit-methods-text-${opt.toLowerCase()}`}
                        variant={answers.methods_text_used === (opt === "Yes") ? "default" : "outline"}
                        onClick={() => set("methods_text_used", opt === "Yes")}
                      >
                        {opt}
                      </Button>
                    ))}
                  </div>
                </div>
              </>
            )}

            {/* ── Page 3: Pricing & AI quality (H4, H5) ────────────────── */}
            {page === 3 && (
              <>
                <p className="text-xs text-muted-foreground bg-muted/50 rounded p-3">
                  <strong>H4 target:</strong> ≥ 60% willing to pay $29/month.
                </p>
                <div>
                  <Label>I would pay $29/month for continued access to BioMate:</Label>
                  <div className="flex flex-col gap-2 mt-2">
                    {PRICING_OPTIONS.map((opt) => (
                      <button
                        key={opt}
                        data-testid={`exit-pricing-${opt.split(" ")[0].toLowerCase()}`}
                        onClick={() => set("pricing_response", opt)}
                        className={`text-left rounded border px-3 py-2 text-sm transition-colors ${
                          answers.pricing_response === opt
                            ? "border-blue-500 bg-blue-50 dark:bg-blue-950/20 font-medium"
                            : "border-border hover:bg-muted"
                        }`}
                      >
                        {opt}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <Label>Did you use BioMate's research / literature assistant during any session?</Label>
                  <div className="flex gap-2 mt-1">
                    {(["Yes", "No"] as const).map((opt) => (
                      <Button
                        key={opt}
                        size="sm"
                        data-testid={`exit-lit-used-${opt.toLowerCase()}`}
                        variant={answers.literature_agent_used === (opt === "Yes") ? "default" : "outline"}
                        onClick={() => set("literature_agent_used", opt === "Yes")}
                      >
                        {opt}
                      </Button>
                    ))}
                  </div>
                </div>

                {answers.literature_agent_used && (
                  <LikertRow
                    id="lit_rating"
                    label="The research assistant responses were accurate and helpful."
                    value={answers.literature_agent_rating}
                    onChange={(v) => set("literature_agent_rating", v)}
                  />
                )}
              </>
            )}

            {/* ── Page 4: Overall ───────────────────────────────────────── */}
            {page === 4 && (
              <>
                <LikertRow
                  id="overall_rating"
                  label="Overall, BioMate met my expectations for this pilot."
                  value={answers.overall_rating}
                  onChange={(v) => set("overall_rating", v)}
                />

                <LikertRow
                  id="would_recommend"
                  label="I would recommend BioMate to a colleague in my field."
                  value={answers.would_recommend}
                  onChange={(v) => set("would_recommend", v)}
                />

                <div>
                  <Label>What was the single biggest time saving BioMate provided?</Label>
                  <Textarea
                    placeholder="e.g. I no longer had to write STAR alignment scripts — the whole pipeline ran in one query"
                    className="mt-1" rows={2}
                    data-testid="exit-time-saving"
                    value={answers.biggest_time_saving}
                    onChange={(e) => set("biggest_time_saving", e.target.value)}
                  />
                </div>

                <div>
                  <Label>What was the most significant gap or limitation you encountered?</Label>
                  <Textarea
                    placeholder="e.g. struggled with custom genome reference; needed to re-submit with more specific parameters"
                    className="mt-1" rows={2}
                    data-testid="exit-biggest-gap"
                    value={answers.biggest_gap}
                    onChange={(e) => set("biggest_gap", e.target.value)}
                  />
                </div>

                <div>
                  <Label>Are you open to co-authoring a methods evaluation paper with BioMate AI?</Label>
                  <div className="flex gap-2 mt-1">
                    {(["Yes", "Maybe", "No"] as const).map((opt) => (
                      <Button
                        key={opt}
                        size="sm"
                        data-testid={`exit-coauthor-${opt.toLowerCase()}`}
                        variant={answers.publish_together === (opt === "Yes") ? "default" : "outline"}
                        onClick={() => set("publish_together", opt === "Yes")}
                      >
                        {opt}
                      </Button>
                    ))}
                  </div>
                </div>

                <div>
                  <Label>Any other feedback or suggestions? (optional)</Label>
                  <Textarea
                    placeholder="Anything else you want us to know"
                    className="mt-1" rows={3}
                    data-testid="exit-free-text"
                    value={answers.free_text}
                    onChange={(e) => set("free_text", e.target.value)}
                  />
                </div>

                {error && (
                  <p className="text-xs text-red-600 bg-red-50 rounded p-2">{error}</p>
                )}
              </>
            )}

          </CardContent>
        </Card>

        {/* Navigation */}
        <div className="flex justify-between">
          <Button
            variant="outline"
            onClick={() => page === 0 ? setLocation("/dashboard") : setPage((p) => p - 1)}
          >
            <ChevronLeft className="h-4 w-4 mr-1" />
            {page === 0 ? "Cancel" : "Back"}
          </Button>
          {page < PAGES.length - 1 ? (
            <Button onClick={() => setPage((p) => p + 1)} data-testid="exit-next">
              Next
              <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          ) : (
            <Button
              onClick={handleSubmit}
              disabled={submitting}
              data-testid="exit-submit"
            >
              {submitting ? "Submitting…" : "Submit survey"}
            </Button>
          )}
        </div>

        <p className="text-xs text-center text-muted-foreground">
          Your responses are stored securely and used only for pilot study evaluation. · BioMate AI Pilot 2026
        </p>
      </div>
    </div>
  );
}
