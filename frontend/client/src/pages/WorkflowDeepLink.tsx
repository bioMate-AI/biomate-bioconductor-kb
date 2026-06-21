/**
 * /workflow/:id — public deep-link target for chat connectors.
 *
 * Loads a workflow draft persisted at generation time (POST /api/chat/stream →
 * GET /api/workflow-draft/:id) and renders ChatWithArtifacts with a synthetic
 * single-message session so the existing right-panel auto-open logic focuses the
 * workflow panel on it (it keys off a message with metadata.type === 'workflow').
 *
 * Auth: the draft endpoint is owner-scoped. A logged-in browser (cookie session,
 * including the one minted by /api/auth/magic) loads it directly; an anonymous
 * visitor is bounced to /login?next=<this path> — the connector's magic link
 * establishes the session before landing here.
 */
import { useEffect, useState } from "react";
import { useRoute, useLocation } from "wouter";
import { ChatWithArtifacts } from "@/components/chat-with-artifacts";
import { useAuth } from "@/contexts/auth-context";
import type { ChatSession } from "@shared/schema";

function buildSyntheticSession(id: string, draft: any): ChatSession {
  const now = new Date();
  return {
    id: `draft-${id}`,
    title: draft.workflow_name || draft.workflowName || "Workflow",
    timestamp: now,
    lastActivity: now,
    status: "active",
    messages: [
      {
        id: `draft-msg-${id}`,
        role: "assistant",
        content: draft.response || "",
        timestamp: now,
        suggestions: draft.suggestions || [],
        metadata: {
          type: "workflow",
          workflow: draft.workflow,
          inlineParameters: draft.inlineParameters || undefined,
          prerequisitesValidation: draft.prerequisitesValidation || null,
          source: "deeplink",
        },
      },
    ],
  };
}

export default function WorkflowDeepLink() {
  const [, params] = useRoute("/workflow/:id");
  const id = params?.id || "";
  const { isAuthenticated, isLoading } = useAuth();
  const [, navigate] = useLocation();
  const [session, setSession] = useState<ChatSession | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (isLoading) return;
    if (!isAuthenticated) {
      navigate(`/login?next=${encodeURIComponent(`/workflow/${id}`)}`);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/workflow-draft/${id}`, { credentials: "include" });
        if (!res.ok) {
          if (res.status === 404) throw new Error("This workflow link is invalid or was removed.");
          if (res.status === 410) throw new Error("This workflow link has expired.");
          throw new Error(`Failed to load workflow (${res.status}).`);
        }
        const draft = await res.json();
        if (!cancelled) setSession(buildSyntheticSession(id, draft));
      } catch (e: any) {
        if (!cancelled) setError(e?.message || "Failed to load workflow.");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isLoading, isAuthenticated, id, navigate]);

  if (isLoading || !isAuthenticated) return null;

  if (error) {
    return (
      <div className="h-screen w-full flex flex-col items-center justify-center gap-4 p-6 text-center">
        <p className="text-sm" style={{ color: "var(--bm-text-muted, hsl(var(--muted-foreground)))" }}>
          {error}
        </p>
        <button
          onClick={() => navigate("/")}
          className="px-4 py-2 rounded-md text-sm font-medium"
          style={{ background: "var(--bm-text, hsl(var(--foreground)))", color: "var(--bm-bg-elev, white)" }}
          data-testid="button-deeplink-home"
        >
          Open BioMate
        </button>
      </div>
    );
  }

  if (!session) {
    return (
      <div className="h-screen w-full flex items-center justify-center">
        <p className="text-sm" style={{ color: "var(--bm-text-muted, hsl(var(--muted-foreground)))" }}>
          Loading workflow…
        </p>
      </div>
    );
  }

  // chat-with-artifacts owns its own top bar; render it in a bare full-height
  // shell (the right panel auto-opens on the workflow message).
  return (
    <div className="h-screen w-full flex flex-col overflow-hidden" data-testid="workflow-deeplink">
      <ChatWithArtifacts
        currentChatSession={session}
        onChatUpdated={(s) => setSession(s)}
        onWorkflowPanelOpenChange={() => {}}
      />
    </div>
  );
}
