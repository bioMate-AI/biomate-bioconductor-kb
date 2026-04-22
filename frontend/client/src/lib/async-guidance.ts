export interface AsyncGuidance {
  title: string;
  reason: string;
  retry: string;
  escalation: string;
  isTimeout: boolean;
  isNetworkRelated: boolean;
}

function normalizeError(rawError: string | null | undefined): string {
  return (rawError || "").trim();
}

function classifyError(error: string) {
  const lower = error.toLowerCase();
  const isTimeout =
    lower.includes("timeout") ||
    lower.includes("timed out") ||
    lower.includes("deadline exceeded") ||
    lower.includes("etimedout");
  const isNetworkRelated =
    lower.includes("network") ||
    lower.includes("failed to fetch") ||
    lower.includes("fetch") ||
    lower.includes("connection");
  return { isTimeout, isNetworkRelated };
}

export function getExecutionAsyncGuidance(
  rawError: string | null | undefined,
  options: { isOnline?: boolean } = {}
): AsyncGuidance {
  const error = normalizeError(rawError);
  const { isTimeout, isNetworkRelated } = classifyError(error);
  const isOnline = options.isOnline ?? true;

  if (!isOnline || isNetworkRelated) {
    return {
      title: "Connection issue during execution",
      reason:
        error || "The browser or API connection was interrupted while workflow execution status was being updated.",
      retry:
        "Reconnect network, then retry run actions or refresh execution status from the workflow panel.",
      escalation:
        "If this repeats, report the issue with run ID and timestamp for backend connectivity triage.",
      isTimeout,
      isNetworkRelated: true,
    };
  }

  if (isTimeout) {
    return {
      title: "Execution timed out",
      reason:
        "The workflow did not complete in the expected time window. This usually indicates heavy compute load, large inputs, or a stalled backend runner.",
      retry:
        "Retry after checking input size/parameters and backend load. If this repeats, run a smaller subset first.",
      escalation:
        "Escalate with run ID and timestamp so we can inspect backend logs and executor health.",
      isTimeout: true,
      isNetworkRelated,
    };
  }

  return {
    title: "Execution failed",
    reason: error || "The workflow could not be executed due to an unexpected backend or validation issue.",
    retry:
      "Retry after confirming required inputs, file paths, and parameters are valid. You can rerun directly from the workflow card.",
    escalation:
      "If retry does not work, report confusion so context is attached automatically for triage.",
    isTimeout: false,
    isNetworkRelated,
  };
}

export function getChatAsyncGuidance(
  rawError: string | null | undefined,
  options: { isOnline?: boolean } = {}
): AsyncGuidance {
  const error = normalizeError(rawError);
  const { isTimeout, isNetworkRelated } = classifyError(error);
  const isOnline = options.isOnline ?? true;

  if (!isOnline || isNetworkRelated) {
    return {
      title: "Connection error",
      reason:
        error || "Could not reach the workflow generation service because the network connection appears interrupted.",
      retry: "Reconnect and send the prompt again. If this keeps happening, wait briefly and retry.",
      escalation:
        "Use Report issue if repeated failures continue so logs and request context can be attached.",
      isTimeout,
      isNetworkRelated: true,
    };
  }

  if (isTimeout) {
    return {
      title: "Response timed out",
      reason: error || "Workflow generation exceeded the response time budget.",
      retry: "Retry with a narrower request or simpler input context.",
      escalation: "If timeouts persist, report issue with timestamp and prompt summary.",
      isTimeout: true,
      isNetworkRelated: false,
    };
  }

  const isRateLimit = /temporarily busy|wait a moment|rate.?limit|too many|overload/i.test(error);
  if (isRateLimit) {
    return {
      title: "Service temporarily busy",
      reason: "BioMate's AI service is handling many requests right now. Your request was not lost.",
      retry: "Wait 10–30 seconds and send the message again — it will process normally.",
      escalation: "If this keeps happening after a few retries, report issue with timestamp.",
      isTimeout: false,
      isNetworkRelated: false,
    };
  }

  return {
    title: "Workflow generation failed",
    reason: error || "The service returned an unexpected error while generating your workflow.",
    retry: "Rephrase the request with data type and analysis goal, then try again.",
    escalation: "If this persists, use Report issue so the backend trace can be reviewed.",
    isTimeout: false,
    isNetworkRelated: false,
  };
}
