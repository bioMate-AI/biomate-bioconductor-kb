/**
 * Project Notes page — Stream-A platform.
 *
 * Renders the latest LLM synthesis for a project. The user clicks
 * "Refresh synthesis" to spend ~$0.05 generating a new one from
 * completed runs + recent chat episodes. The result is markdown
 * stored in `project_knowledge` with knowledgeType='notes_synthesis'.
 *
 * Backend: frontend/server/notes-routes.ts (commit e3955d0da).
 * Route registered in App.tsx as /projects/:projectId/notes.
 *
 * Palette aligned to the cream / navy / leaf-green logo per
 * reference/claude_design/design_handoff_wiki_canvas/Wiki-Canvas-Prototype.html.
 */
import { useEffect, useState, useCallback } from "react";
import { useRoute, useLocation } from "wouter";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeRaw from "rehype-raw";
import { Button } from "@/components/ui/button";
import { downloadAsMd } from "@/lib/download-response";

type Note = {
  id?: string;
  projectId?: string;
  knowledgeType?: string;
  title?: string;
  content: string;
  source?: string;
  createdAt?: string;
};

const PALETTE = {
  bg: "#f5efe2",
  surface: "#fffdf7",
  ink: "#1e3a5f",
  inkSoft: "#4a5e7a",
  inkMute: "#8a93a1",
  rule: "#d5cdb8",
  green: "#7fb24a",
  greenSoft: "#e3efd2",
};

function formatTs(iso?: string): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}

export default function ProjectNotesPage() {
  const [, params] = useRoute<{ projectId: string }>("/projects/:projectId/notes");
  const [, navigate] = useLocation();
  const projectId = params?.projectId;

  const [note, setNote] = useState<Note | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchNote = useCallback(async () => {
    if (!projectId) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/projects/${projectId}/notes`, {
        credentials: "include",
      });
      if (res.status === 404) {
        setNote(null);
        setNotFound(true);
        return;
      }
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const body = await res.json();
      setNote(body.note ?? null);
      setNotFound(!body.note);
    } catch (e: any) {
      setError(e?.message ?? "Failed to load notes");
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  useEffect(() => {
    fetchNote();
  }, [fetchNote]);

  const handleRefresh = async () => {
    if (!projectId || refreshing) return;
    setRefreshing(true);
    setError(null);
    try {
      const res = await fetch(`/api/projects/${projectId}/notes/refresh`, {
        method: "POST",
        credentials: "include",
      });
      if (!res.ok) {
        const txt = await res.text().catch(() => "");
        throw new Error(`Refresh failed (${res.status}) ${txt}`);
      }
      // Re-fetch to display latest.
      await fetchNote();
    } catch (e: any) {
      setError(e?.message ?? "Refresh failed");
    } finally {
      setRefreshing(false);
    }
  };

  const handleDownload = () => {
    if (!note?.content) return;
    const title = note.title || `project-${projectId}-notes`;
    downloadAsMd(note.content, title);
  };

  return (
    <div
      data-testid="project-notes-page"
      style={{
        minHeight: "100vh",
        background: PALETTE.bg,
        color: PALETTE.ink,
        padding: "32px 24px",
      }}
    >
      <div style={{ maxWidth: 880, margin: "0 auto" }}>
        {/* Header */}
        <header style={{ marginBottom: 24 }}>
          <button
            onClick={() => navigate("/projects")}
            style={{
              background: "transparent",
              border: "none",
              color: PALETTE.inkSoft,
              fontSize: 13,
              cursor: "pointer",
              padding: 0,
              marginBottom: 12,
            }}
            data-testid="link-back-to-projects"
          >
            ← Back to projects
          </button>
          <h1
            style={{
              fontSize: 28,
              fontWeight: 700,
              letterSpacing: "-0.02em",
              margin: 0,
            }}
          >
            Notes
          </h1>
          <div
            data-testid="notes-meta"
            style={{
              marginTop: 8,
              fontSize: 13,
              color: PALETTE.inkMute,
              display: "flex",
              gap: 16,
              flexWrap: "wrap",
            }}
          >
            <span>
              Last refreshed: <strong style={{ color: PALETTE.inkSoft }}>{formatTs(note?.createdAt)}</strong>
            </span>
            {note?.source && <span>Source: {note.source}</span>}
          </div>
        </header>

        {/* Action bar */}
        <div
          style={{
            display: "flex",
            gap: 8,
            marginBottom: 20,
            flexWrap: "wrap",
          }}
        >
          <Button
            onClick={handleRefresh}
            disabled={refreshing || loading}
            data-testid="button-refresh-synthesis"
            style={{
              background: PALETTE.green,
              color: "white",
              border: "none",
            }}
          >
            {refreshing ? "Synthesising…" : "Refresh synthesis"}
          </Button>
          <Button
            variant="ghost"
            onClick={handleDownload}
            disabled={!note?.content || refreshing}
            data-testid="button-download-md"
          >
            Download as Markdown
          </Button>
        </div>

        {error && (
          <div
            data-testid="notes-error"
            style={{
              padding: 12,
              marginBottom: 16,
              background: "#fce4dc60",
              border: `1px solid #b85a4a`,
              borderRadius: 6,
              color: "#7a3a2e",
              fontSize: 13,
            }}
          >
            {error}
          </div>
        )}

        {/* Body */}
        <section
          style={{
            background: PALETTE.surface,
            border: `1px solid ${PALETTE.rule}`,
            borderRadius: 8,
            padding: 28,
            minHeight: 240,
          }}
        >
          {loading ? (
            <div data-testid="notes-loading" style={{ color: PALETTE.inkMute }}>
              Loading…
            </div>
          ) : notFound || !note ? (
            <div data-testid="notes-empty" style={{ color: PALETTE.inkSoft }}>
              <p style={{ marginTop: 0 }}>
                This project doesn't have a synthesis yet. Click{" "}
                <strong>Refresh synthesis</strong> to generate one from completed
                runs and chat history.
              </p>
            </div>
          ) : (
            <article
              data-testid="notes-content"
              className="prose prose-sm max-w-none"
              style={{ color: PALETTE.ink, lineHeight: 1.6 }}
            >
              <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeRaw]}>
                {note.content}
              </ReactMarkdown>
            </article>
          )}
        </section>
      </div>
    </div>
  );
}
