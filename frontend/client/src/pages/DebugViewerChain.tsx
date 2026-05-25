/**
 * /debug/viewer/:runId — mount NextflowWorkflowViewer with hardcoded
 * "completed" state and the runId from URL. Mirrors the chat-session
 * render path: ChatOutputAttachments is INSIDE the viewer here, gated
 * by `(invocationId || runId) && showResults`.
 *
 * If viewer mounts AND DensityMapViewer is in DOM here, the chat-session
 * gate is correct and the bug must be in how chat-with-artifacts /
 * chat-message produce these props at CS-14 time.
 */
import { useRoute } from "wouter";
import { NextflowWorkflowViewer } from "@/components/nextflow-workflow-viewer";

export default function DebugViewerChain() {
  const [, params] = useRoute("/debug/viewer/:runId");
  const runId = params?.runId || "";
  return (
    <div style={{ padding: 16, fontFamily: "monospace" }} data-testid="debug-viewer-chain-root">
      <h2>Debug: NextflowWorkflowViewer chain</h2>
      <p>runId: <code data-testid="debug-runid">{runId}</code></p>
      <p>
        Mounts the workflow viewer with hardcoded status='completed' so
        the showResults gate inside the viewer evaluates true. The
        embedded ChatOutputAttachments should render outputs.
      </p>
      <hr />
      <div style={{ minHeight: 600 }}>
        <NextflowWorkflowViewer
          workflowDefinition={{ name: "Debug Workflow", steps: {} }}
          invocationId={runId}
          runId={runId}
          status="completed"
          sessionId="debug-session"
        />
      </div>
    </div>
  );
}
