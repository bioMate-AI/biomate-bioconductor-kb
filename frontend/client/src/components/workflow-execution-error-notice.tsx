import type { WorkflowExecutionErrorDetails } from "@/hooks/useUnifiedExecution";
import { presentWorkflowExecutionError } from "@/lib/workflow-execution-error";
import { AlertTriangle } from "lucide-react";

/** The actionable, non-retry-only surface for a rejected workflow launch. */
export function WorkflowExecutionErrorNotice({ error }: { error: WorkflowExecutionErrorDetails }) {
  const presentation = presentWorkflowExecutionError(error);
  return (
    <div className="border-b bg-red-50 px-4 py-2" data-testid="execution-error-notice">
      <div className="space-y-2 text-sm text-red-700">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-4 w-4" />
          <span className="font-semibold" data-testid="execution-error-title">{presentation.title}</span>
        </div>
        <p data-testid="execution-error-detail">{presentation.detail}</p>
        {presentation.missingLabels.length ? (
          <ul className="list-disc pl-5 text-xs" data-testid="execution-error-missing-params">
            {presentation.missingLabels.map((label) => <li key={label}>{label}</li>)}
          </ul>
        ) : null}
        <p className="text-xs" data-testid="execution-error-action">{presentation.action}</p>
      </div>
    </div>
  );
}
