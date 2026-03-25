import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { submitFeedback } from "@/lib/feedback";
import { UX_FEEDBACK_ENABLED } from "@/lib/feature-flags";

interface DownloadOutcomePromptProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  outputId?: string;
  outputName?: string;
  invocationId?: string;
  sessionId?: string;
  runId?: string;
  isDownloadAll?: boolean;
}

export function DownloadOutcomePrompt({
  open,
  onOpenChange,
  outputId,
  outputName,
  invocationId,
  sessionId,
  runId,
  isDownloadAll = false,
}: DownloadOutcomePromptProps) {
  if (!UX_FEEDBACK_ENABLED) return null;

  const [success, setSuccess] = useState<boolean | null>(null);
  const [reason, setReason] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async () => {
    if (success === null) return;
    setIsSubmitting(true);
    const ok = await submitFeedback({
      feedback_type: "download_check",
      download_success: success,
      comment: reason.trim() || undefined,
      output_id: outputId,
      invocation_id: invocationId,
      session_id: sessionId,
      run_id: runId,
      ui_context: { outputName, isDownloadAll },
    });
    setIsSubmitting(false);
    if (ok.success) {
      setSuccess(null);
      setReason("");
      onOpenChange(false);
    }
  };

  const handleSkip = () => {
    setSuccess(null);
    setReason("");
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md" data-testid="download-outcome-prompt-dialog">
        <DialogHeader>
          <DialogTitle>Download feedback</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          Did you get the expected file{isDownloadAll ? "s" : ""}?
        </p>
        <div className="flex gap-2 py-2">
          <Button
            variant={success === true ? "default" : "outline"}
            size="sm"
            onClick={() => setSuccess(true)}
          >
            Yes
          </Button>
          <Button
            variant={success === false ? "default" : "outline"}
            size="sm"
            onClick={() => setSuccess(false)}
          >
            No
          </Button>
        </div>
        {success === false && (
          <Textarea
            placeholder="What went wrong? (optional)"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="min-h-[60px]"
            rows={2}
          />
        )}
        <DialogFooter>
          <Button variant="ghost" onClick={handleSkip}>
            Skip
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={success === null || isSubmitting}
          >
            {isSubmitting ? "Submitting…" : "Submit"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
