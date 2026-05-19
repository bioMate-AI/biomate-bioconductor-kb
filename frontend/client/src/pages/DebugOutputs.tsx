/**
 * /debug/outputs/:runId — standalone harness for ChatOutputAttachments.
 *
 * Mounts the component with hardcoded props pointing at the URL's runId,
 * skipping the chat-session render path so we can confirm whether
 * ChatOutputAttachments mounts, whether otherFiles contains the .mrc items,
 * and whether DensityMapViewer renders with its testid.
 *
 * Used to diagnose the CS-14 "viewer not in DOM" gap without a GPU run.
 * See docs/20260518_OUTPUTS_CONSOLIDATION_AND_DEV_HARDENING_SESSION.md.
 */
import { useRoute } from "wouter";
import { ChatOutputAttachments } from "@/components/chat-output-attachments";

export default function DebugOutputs() {
  const [, params] = useRoute("/debug/outputs/:runId");
  const runId = params?.runId || "";
  return (
    <div style={{ padding: 16, fontFamily: "monospace" }} data-testid="debug-outputs-root">
      <h2>Debug: ChatOutputAttachments standalone</h2>
      <p>runId: <code data-testid="debug-runid">{runId}</code></p>
      <p>
        This page mounts the component with the runId from URL. If outputs
        render here, the bug is in the chat-session render path (state
        propagation, gating); if outputs DO NOT render here, the bug is
        in ChatOutputAttachments itself (queryFn, filtering, OutputRenderer).
      </p>
      <hr />
      <ChatOutputAttachments
        invocationId={runId}
        runId={runId}
        sessionId="debug-session"
        executionStatus="completed"
      />
    </div>
  );
}
