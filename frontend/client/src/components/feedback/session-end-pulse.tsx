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
import { submitFeedback } from "@/lib/feedback";
import { UX_FEEDBACK_ENABLED } from "@/lib/feature-flags";

interface SessionEndPulseProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  sessionId?: string;
  runId?: string;
  invocationId?: string;
}

export function SessionEndPulse({
  open,
  onOpenChange,
  sessionId,
  runId,
  invocationId,
}: SessionEndPulseProps) {
  if (!UX_FEEDBACK_ENABLED) return null;

  const [overallHelpful, setOverallHelpful] = useState<boolean | null>(null);
  const [comeBackLikely, setComeBackLikely] = useState<boolean | null>(null);
  const [comment, setComment] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const canSubmit = overallHelpful !== null && comeBackLikely !== null;

  const handleSubmit = async () => {
    if (!canSubmit || isSubmitting) return;
    setIsSubmitting(true);
    const ok = await submitFeedback({
      feedback_type: "session_pulse",
      session_id: sessionId,
      run_id: runId,
      invocation_id: invocationId,
      rating: overallHelpful ? "up" : "down",
      reason_tags: overallHelpful ? undefined : ["other"],
      comment: comment.trim() || undefined,
      ui_context: {
        comeBackLikely,
        pulseAt: new Date().toISOString(),
        route: typeof window !== "undefined" ? window.location.pathname : undefined,
      },
    });
    setIsSubmitting(false);
    if (ok.success) {
      onOpenChange(false);
      setOverallHelpful(null);
      setComeBackLikely(null);
      setComment("");
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showOverlay={false}
        className="sm:max-w-md w-[calc(100vw-2rem)] left-auto right-4 top-auto bottom-4 translate-x-0 translate-y-0"
        data-testid="session-end-pulse-dialog"
      >
        <DialogHeader>
          <DialogTitle>Before you go</DialogTitle>
          <DialogDescription>
            Two quick questions to improve the session experience.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-3">
          <p className="text-sm text-muted-foreground">
            Quick 2-question pulse to help us improve BioMate.
          </p>
          <div>
            <Label className="text-sm">Was this session helpful overall?</Label>
            <div className="flex gap-2 mt-1">
              <Button
                variant={overallHelpful === true ? "default" : "outline"}
                size="sm"
                onClick={() => setOverallHelpful(true)}
              >
                Yes
              </Button>
              <Button
                variant={overallHelpful === false ? "default" : "outline"}
                size="sm"
                onClick={() => setOverallHelpful(false)}
              >
                No
              </Button>
            </div>
          </div>
          <div>
            <Label className="text-sm">Would you use BioMate again for a similar task?</Label>
            <div className="flex gap-2 mt-1">
              <Button
                variant={comeBackLikely === true ? "default" : "outline"}
                size="sm"
                onClick={() => setComeBackLikely(true)}
              >
                Yes
              </Button>
              <Button
                variant={comeBackLikely === false ? "default" : "outline"}
                size="sm"
                onClick={() => setComeBackLikely(false)}
              >
                No
              </Button>
            </div>
          </div>
          <div>
            <Label className="text-sm">Optional comment</Label>
            <Textarea
              placeholder="What should we improve next?"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              className="mt-1 min-h-[60px]"
              rows={2}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Skip
          </Button>
          <Button onClick={handleSubmit} disabled={!canSubmit || isSubmitting}>
            {isSubmitting ? "Submitting..." : "Submit"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
