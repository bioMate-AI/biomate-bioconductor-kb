import { useState } from "react";
import { HelpCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { submitFeedback } from "@/lib/feedback";
import { UX_FEEDBACK_ENABLED } from "@/lib/feature-flags";

interface ReportConfusionButtonProps {
  runId?: string;
  sessionId?: string;
  invocationId?: string;
  workflowId?: string;
  /** Snapshot of current state for context */
  context?: Record<string, unknown>;
  variant?: "default" | "outline" | "ghost" | "link" | "destructive" | "secondary";
  size?: "default" | "sm" | "lg" | "icon";
  className?: string;
  onClick?: () => void;
}

export function ReportConfusionButton({
  runId,
  sessionId,
  invocationId,
  workflowId,
  context = {},
  variant = "ghost",
  size = "sm",
  className,
  onClick,
}: ReportConfusionButtonProps) {
  if (!UX_FEEDBACK_ENABLED) return null;

  const [open, setOpen] = useState(false);
  const [comment, setComment] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async () => {
    setIsSubmitting(true);
    const ok = await submitFeedback({
      feedback_type: "confusion_report",
      comment: comment.trim() || undefined,
      run_id: runId,
      session_id: sessionId,
      invocation_id: invocationId,
      workflow_id: workflowId,
      ui_context: { ...context, reportedAt: new Date().toISOString() },
    });
    setIsSubmitting(false);
    if (ok.success) {
      setComment("");
      setOpen(false);
    }
  };

  return (
    <>
      <Button
        variant={variant}
        size={size}
        className={className}
        onClick={() => {
          onClick?.();
          setOpen(true);
        }}
        aria-label="Report confusion"
      >
        <HelpCircle className="h-3.5 w-3.5 mr-1" />
        Report confusion
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Report confusion</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Your run ID and context will be included to help us debug.
          </p>
          <Textarea
            placeholder="What was confusing or unclear?"
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            className="min-h-[80px]"
            rows={3}
          />
          <DialogFooter>
            <Button variant="ghost" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button onClick={handleSubmit} disabled={isSubmitting}>
              {isSubmitting ? "Submitting…" : "Submit"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
