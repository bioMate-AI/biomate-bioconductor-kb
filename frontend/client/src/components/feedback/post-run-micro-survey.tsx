import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { submitFeedback } from "@/lib/feedback";
import { UX_FEEDBACK_ENABLED } from "@/lib/feature-flags";

type RunStatus = "completed" | "failed" | "cancelled";

interface PostRunMicroSurveyProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  runId: string;
  runStatus: RunStatus;
  sessionId?: string;
  invocationId?: string;
  workflowName?: string;
}

// Likert scale labels
const LIKERT = ["Strongly disagree", "Disagree", "Neutral", "Agree", "Strongly agree"] as const;

function LikertScale({
  id,
  value,
  onChange,
}: {
  id: string;
  value: number | null;
  onChange: (v: number) => void;
}) {
  return (
    <div className="flex gap-1 mt-1" role="group">
      {LIKERT.map((label, i) => (
        <button
          key={i}
          data-testid={`survey-${id}-${i + 1}`}
          title={label}
          onClick={() => onChange(i + 1)}
          className={`flex-1 rounded border py-1 text-xs transition-colors ${
            value === i + 1
              ? "border-blue-500 bg-blue-500 text-white"
              : "border-border hover:bg-muted"
          }`}
        >
          {i + 1}
        </button>
      ))}
    </div>
  );
}

const PRICING_OPTIONS = [
  "Yes — from my lab budget",
  "Yes — from a core facility / institutional subscription",
  "Maybe — depends on grant cycle",
  "No",
] as const;

export function PostRunMicroSurvey({
  open,
  onOpenChange,
  runId,
  runStatus,
  sessionId,
  invocationId,
  workflowName,
}: PostRunMicroSurveyProps) {
  if (!UX_FEEDBACK_ENABLED) return null;

  // ── Pilot evaluation KPIs (evaluation model H1–H3) ────────────────────────
  // H3: QC defensibility — rating 1–5, target ≥4 (publication-ready)
  const [qcRating, setQcRating] = useState<number | null>(null);
  // H1: Workflow quality — did it run without manual correction?
  const [ranWithoutCorrection, setRanWithoutCorrection] = useState<boolean | null>(null);
  // H2: Time-to-result baseline — how long would this have taken before BioMate?
  const [priorTimeHours, setPriorTimeHours] = useState<string>("");
  // H4: Pricing
  const [pricingResponse, setPricingResponse] = useState<string | null>(null);

  // ── UX signal questions (existing) ───────────────────────────────────────
  const [executionClear, setExecutionClear] = useState<boolean | null>(null);
  const [comment, setComment] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  // Only QC rating and workflow quality are required for pilot KPIs
  const canSubmit = runStatus !== "completed" || (qcRating !== null && ranWithoutCorrection !== null);

  const handleSubmit = async () => {
    if (!canSubmit || isSubmitting) return;
    setIsSubmitting(true);
    const ok = await submitFeedback({
      feedback_type: "post_run",
      run_id: runId,
      run_status: runStatus,
      session_id: sessionId,
      invocation_id: invocationId,
      workflow_name: workflowName,
      // Pilot KPI fields
      qc_publication_rating: qcRating ?? undefined,
      ran_without_manual_correction: ranWithoutCorrection ?? undefined,
      prior_time_hours: priorTimeHours ? Number(priorTimeHours) : undefined,
      pricing_response: pricingResponse ?? undefined,
      // UX signal
      execution_clear: executionClear ?? undefined,
      comment: comment.trim() || undefined,
      submitted_at: new Date().toISOString(),
    });
    setIsSubmitting(false);
    if (ok.success) {
      setSubmitted(true);
      setTimeout(() => onOpenChange(false), 1800);
    }
  };

  if (submitted) {
    return (
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent
          showOverlay={false}
          className="sm:max-w-md w-[calc(100vw-2rem)] left-auto right-4 top-auto bottom-4 translate-x-0 translate-y-0"
        >
          <div className="py-6 text-center text-sm text-green-700 dark:text-green-300">
            ✓ Thank you — your feedback helps validate the pilot study results.
          </div>
        </DialogContent>
      </Dialog>
    );
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showOverlay={false}
        className="sm:max-w-md w-[calc(100vw-2rem)] left-auto right-4 top-auto bottom-4 translate-x-0 translate-y-0 max-h-[90vh] overflow-y-auto"
        data-testid="post-run-survey-dialog"
      >
        <DialogHeader>
          <DialogTitle>Quick feedback {workflowName ? `— ${workflowName}` : ""}</DialogTitle>
          <DialogDescription>
            Share quick feedback on run clarity, outputs, and usability.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5 py-2 text-sm">

          {runStatus === "completed" && (
            <>
              {/* H3 — QC defensibility (pilot primary KPI) */}
              <div>
                <Label className="text-sm font-medium">
                  The QC output is suitable for a research manuscript methods section.
                  <span className="ml-1 text-xs text-blue-600 font-normal">(required)</span>
                </Label>
                <p className="text-xs text-muted-foreground mt-0.5 mb-1">
                  1 = strongly disagree · 5 = strongly agree (≥ 4 = publication-ready)
                </p>
                <LikertScale id="qc_rating" value={qcRating} onChange={setQcRating} />
              </div>

              {/* H1 — Workflow quality (pilot primary KPI) */}
              <div>
                <Label className="text-sm font-medium">
                  The workflow ran end-to-end without me correcting any parameters.
                  <span className="ml-1 text-xs text-blue-600 font-normal">(required)</span>
                </Label>
                <div className="flex gap-2 mt-1">
                  {(["Yes", "No — I had to correct something"] as const).map((opt) => (
                    <Button
                      key={opt}
                      variant={ranWithoutCorrection === (opt === "Yes") ? "default" : "outline"}
                      size="sm"
                      data-testid={`survey-no-correction-${opt === "Yes" ? "yes" : "no"}`}
                      onClick={() => setRanWithoutCorrection(opt === "Yes")}
                    >
                      {opt}
                    </Button>
                  ))}
                </div>
              </div>

              {/* H2 — Time-to-result baseline */}
              <div>
                <Label className="text-sm font-medium">
                  Without BioMate, this analysis would have taken approximately:
                </Label>
                <div className="flex items-center gap-2 mt-1">
                  <Input
                    type="number"
                    min={0}
                    step={0.5}
                    placeholder="e.g. 8"
                    data-testid="survey-prior-time"
                    className="w-24"
                    value={priorTimeHours}
                    onChange={(e) => setPriorTimeHours(e.target.value)}
                  />
                  <span className="text-muted-foreground">hours</span>
                  <span className="text-xs text-muted-foreground">(leave blank if unsure)</span>
                </div>
              </div>

              {/* H4 — Pricing */}
              <div>
                <Label className="text-sm font-medium">
                  I would pay $29/month for continued access to BioMate:
                </Label>
                <div className="flex flex-wrap gap-2 mt-1">
                  {PRICING_OPTIONS.map((opt) => (
                    <button
                      key={opt}
                      data-testid={`survey-pricing-${opt.split(" ")[0].toLowerCase()}`}
                      onClick={() => setPricingResponse(opt)}
                      className={`rounded border px-3 py-1 text-xs transition-colors ${
                        pricingResponse === opt
                          ? "border-blue-500 bg-blue-500 text-white"
                          : "border-border hover:bg-muted"
                      }`}
                    >
                      {opt}
                    </button>
                  ))}
                </div>
              </div>
            </>
          )}

          {/* UX signal — execution clarity */}
          <div>
            <Label className="text-sm font-medium">Was the run status easy to follow?</Label>
            <div className="flex gap-2 mt-1">
              {(["Yes", "No"] as const).map((opt) => (
                <Button
                  key={opt}
                  variant={executionClear === (opt === "Yes") ? "default" : "outline"}
                  size="sm"
                  data-testid={`survey-execution-clear-${opt.toLowerCase()}`}
                  onClick={() => setExecutionClear(opt === "Yes")}
                >
                  {opt}
                </Button>
              ))}
            </div>
          </div>

          {/* Free text */}
          <div>
            <Label className="text-sm font-medium">Anything else? (optional)</Label>
            <Textarea
              data-testid="survey-comment"
              placeholder="What worked well or didn't work?"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              className="mt-1 min-h-[56px]"
              rows={2}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" size="sm" onClick={() => onOpenChange(false)}>
            Skip
          </Button>
          <Button
            data-testid="survey-submit"
            size="sm"
            disabled={!canSubmit || isSubmitting}
            onClick={handleSubmit}
          >
            {isSubmitting ? "Submitting…" : "Submit"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
