/**
 * /run/:token — BioMate-native pre-filled run landing claim page (Wave 4).
 *
 * Distinct from /workflow/:id (owner-scoped draft deep link). Shareable token
 * → login if needed → POST claim → ChatWithArtifacts with synthetic workflow
 * message so the right panel auto-opens Confirm & Run ready.
 */
import { useEffect, useState } from "react";
import { useRoute, useLocation } from "wouter";
import { ChatWithArtifacts } from "@/components/chat-with-artifacts";
import { useAuth } from "@/contexts/auth-context";
import type { ChatSession } from "@shared/schema";

function buildSyntheticSession(token: string, claimed: any): ChatSession {
  const now = new Date();
  const name = claimed.workflow_name || claimed.workflow?.name || "Workflow";
  return {
    id: `run-landing-${token}`,
    title: name,
    timestamp: now,
    lastActivity: now,
    status: "active",
    messages: [
      {
        id: `run-landing-msg-${token}`,
        role: "assistant",
        content: claimed.response || `Shared run ready: **${name}**. Review parameters, then click **Confirm & Run**.`,
        timestamp: now,
        suggestions: [],
        metadata: {
          type: "workflow",
          workflow: claimed.workflow,
          inlineParameters: claimed.inlineParameters || claimed.params || undefined,
          prerequisitesValidation: null,
          source: "run_landing",
          runLandingId: claimed.id,
          projectId: claimed.project_id || undefined,
        },
      },
    ],
  };
}

export default function RunLanding() {
  const [, params] = useRoute("/run/:token");
  const token = params?.token || "";
  const { isAuthenticated, isLoading } = useAuth();
  const [, navigate] = useLocation();
  const [session, setSession] = useState<ChatSession | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [previewName, setPreviewName] = useState<string | null>(null);

  // Public preview (name) while auth resolves — mirrors join-project UX.
  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/workflows/landings/${encodeURIComponent(token)}`);
        if (!res.ok) {
          if (res.status === 410) {
            if (!cancelled) setError("This run link has expired.");
            return;
          }
          if (!cancelled) setError("This run link is invalid or was revoked.");
          return;
        }
        const data = await res.json();
        if (!cancelled) setPreviewName(data.workflow_name || "Workflow");
      } catch {
        if (!cancelled) setError("Failed to load run link.");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [token]);

  useEffect(() => {
    if (isLoading || error) return;
    if (!isAuthenticated) {
      navigate(`/login?next=${encodeURIComponent(`/run/${token}`)}`);
      return;
    }
    if (!token) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/workflows/landings/${encodeURIComponent(token)}/claim`, {
          method: "POST",
          credentials: "include",
        });
        if (!res.ok) {
          if (res.status === 404) throw new Error("This run link is invalid or was revoked.");
          if (res.status === 410) throw new Error("This run link has expired.");
          throw new Error(`Failed to claim run link (${res.status}).`);
        }
        const claimed = await res.json();
        if (!cancelled) setSession(buildSyntheticSession(token, claimed));
      } catch (e: any) {
        if (!cancelled) setError(e?.message || "Failed to claim run link.");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isLoading, isAuthenticated, token, navigate, error]);

  if (error) {
    return (
      <div
        className="h-screen w-full flex flex-col items-center justify-center gap-4 p-6 text-center"
        data-testid="run-landing-error"
      >
        <p className="text-sm" style={{ color: "var(--bm-text-muted, hsl(var(--muted-foreground)))" }}>
          {error}
        </p>
        <button
          onClick={() => navigate("/")}
          className="px-4 py-2 rounded-md text-sm font-medium"
          style={{ background: "var(--bm-text, hsl(var(--foreground)))", color: "var(--bm-bg-elev, white)" }}
          data-testid="button-run-landing-home"
        >
          Open BioMate
        </button>
      </div>
    );
  }

  if (isLoading || !isAuthenticated || !session) {
    return (
      <div
        className="h-screen w-full flex flex-col items-center justify-center gap-2"
        data-testid="run-landing-loading"
      >
        <p className="text-sm" style={{ color: "var(--bm-text-muted, hsl(var(--muted-foreground)))" }}>
          {previewName ? `Opening ${previewName}…` : "Loading run link…"}
        </p>
      </div>
    );
  }

  return (
    <div className="h-screen w-full flex flex-col overflow-hidden" data-testid="run-landing">
      <ChatWithArtifacts
        currentChatSession={session}
        onChatUpdated={(s) => setSession(s)}
        onWorkflowPanelOpenChange={() => {}}
      />
    </div>
  );
}
