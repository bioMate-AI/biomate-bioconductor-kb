/**
 * /debug/afterrun/:runId — standalone harness for the merged After-run
 * "Results" report (v2 AfterRunReport).
 *
 * Mounts AfterRunReport with the URL's runId so the real merged view
 * (findings banner + searchable inline output gallery) can be verified/QA'd
 * against a completed run WITHOUT a fresh Batch run. Outputs are fetched by
 * the component's own /output_files fallback; findings by runId. Same intent
 * as DebugOutputs.tsx / DebugViewerChain.tsx.
 */
import { useRoute } from "wouter";
import { AfterRunReport } from "@/v2/AfterRunReport";

export default function DebugAfterRun() {
  const [, params] = useRoute("/debug/afterrun/:runId");
  const runId = params?.runId || "";
  // Optional query overrides so the harness can render non-completed states too
  // (e.g. ?status=failed to capture the failed after-run block, with ?wf= to set
  // the matching workflow name). Default stays the completed ADMET view; only the
  // known non-completed statuses are honored.
  const qs = typeof window !== "undefined"
    ? new URLSearchParams(window.location.search)
    : new URLSearchParams();
  const statusParam = qs.get("status");
  const executionStatus =
    statusParam === "failed" || statusParam === "cancelled" || statusParam === "error" || statusParam === "running"
      ? statusParam
      : "completed";
  const workflowName = qs.get("wf") || "Predict ADMET Properties (AI)";
  return (
    <div style={{ padding: 16, maxWidth: 820, margin: "0 auto" }} data-testid="debug-afterrun-root">
      <p style={{ fontFamily: "monospace", fontSize: 12 }}>
        runId: <code data-testid="debug-runid">{runId}</code>
      </p>
      <AfterRunReport
        runId={runId}
        executionStatus={executionStatus}
        workflowName={workflowName}
      />
    </div>
  );
}
