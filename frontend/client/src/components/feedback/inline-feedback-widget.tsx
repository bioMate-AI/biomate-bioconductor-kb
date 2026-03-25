import { useState } from "react";
import { ThumbsUp, ThumbsDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import {
  submitFeedback,
  FEEDBACK_REASON_TAGS,
  FEEDBACK_REASON_LABELS,
  type FeedbackReasonTag,
} from "@/lib/feedback";
import { UX_FEEDBACK_ENABLED } from "@/lib/feature-flags";

interface InlineFeedbackWidgetProps {
  messageId: string;
  sessionId?: string;
  runId?: string;
  invocationId?: string;
  workflowId?: string;
  className?: string;
}

export function InlineFeedbackWidget({
  messageId,
  sessionId,
  runId,
  invocationId,
  workflowId,
  className,
}: InlineFeedbackWidgetProps) {
  if (!UX_FEEDBACK_ENABLED) return null;

  const [submitted, setSubmitted] = useState<'up' | 'down' | null>(null);
  const [showDownReason, setShowDownReason] = useState(false);
  const [selectedReasons, setSelectedReasons] = useState<Set<FeedbackReasonTag>>(new Set());
  const [comment, setComment] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const toggleReason = (tag: FeedbackReasonTag) => {
    setSelectedReasons((prev) => {
      const next = new Set(prev);
      if (next.has(tag)) next.delete(tag);
      else next.add(tag);
      return next;
    });
  };

  const handleUp = async () => {
    if (submitted) return;
    setIsSubmitting(true);
    const ok = await submitFeedback({
      feedback_type: "inline",
      rating: "up",
      message_id: messageId,
      session_id: sessionId,
      run_id: runId,
      invocation_id: invocationId,
      workflow_id: workflowId,
    });
    setIsSubmitting(false);
    if (ok.success) setSubmitted("up");
  };

  const handleDown = () => {
    if (submitted) return;
    setShowDownReason(true);
  };

  const submitDown = async () => {
    if (selectedReasons.size === 0) return;
    setIsSubmitting(true);
    const ok = await submitFeedback({
      feedback_type: "inline",
      rating: "down",
      reason_tags: Array.from(selectedReasons),
      comment: comment.trim() || undefined,
      message_id: messageId,
      session_id: sessionId,
      run_id: runId,
      invocation_id: invocationId,
      workflow_id: workflowId,
    });
    setIsSubmitting(false);
    if (ok.success) {
      setSubmitted("down");
      setShowDownReason(false);
    }
  };

  if (submitted) {
    return (
      <span className={cn("text-xs text-muted-foreground", className)}>
        Thanks for your feedback
      </span>
    );
  }

  return (
    <div className={cn("flex items-center gap-1", className)} data-testid="inline-feedback-widget">
      <Button
        variant="ghost"
        size="sm"
        className="h-7 w-7 p-0"
        onClick={handleUp}
        disabled={isSubmitting}
        aria-label="Helpful"
        data-testid="inline-feedback-thumbs-up"
      >
        <ThumbsUp className="h-3.5 w-3.5" />
      </Button>
      <Popover open={showDownReason} onOpenChange={setShowDownReason}>
        <PopoverTrigger asChild>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0"
            disabled={isSubmitting}
            aria-label="Not helpful"
            data-testid="inline-feedback-thumbs-down"
          >
            <ThumbsDown className="h-3.5 w-3.5" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-72" align="start">
          <div className="space-y-3">
            <p className="text-sm font-medium">What went wrong?</p>
            <div className="flex flex-wrap gap-1.5">
              {FEEDBACK_REASON_TAGS.map((tag) => (
                <Button
                  key={tag}
                  variant={selectedReasons.has(tag) ? "default" : "outline"}
                  size="sm"
                  className="h-7 text-xs"
                  onClick={() => toggleReason(tag)}
                >
                  {FEEDBACK_REASON_LABELS[tag]}
                </Button>
              ))}
            </div>
            <Textarea
              placeholder="Optional comment..."
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              className="min-h-[60px] text-sm"
              rows={2}
            />
            <div className="flex justify-end gap-2">
              <Button variant="ghost" size="sm" onClick={() => setShowDownReason(false)}>
                Cancel
              </Button>
              <Button
                size="sm"
                onClick={submitDown}
                disabled={selectedReasons.size === 0 || isSubmitting}
              >
                Submit
              </Button>
            </div>
          </div>
        </PopoverContent>
      </Popover>
    </div>
  );
}
