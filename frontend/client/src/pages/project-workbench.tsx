/**
 * Project Workbench page — Stream-A platform.
 *
 * Thin route wrapper that pulls :projectId from the URL and renders
 * <WorkbenchPanel/>. Mirrors the project-notes.tsx pattern so the
 * sidebar wiring can be done once for both surfaces later.
 *
 * Sidebar wiring deferred — same gap noted in commit a8b1e98561
 * (app-sidebar.tsx has no per-project slot yet). Reachable via direct
 * URL: /projects/:projectId/workbench.
 */
import { useRoute, useLocation } from "wouter";
import { WorkbenchPanel } from "@/components/workbench-panel";

export default function ProjectWorkbenchPage() {
  const [, params] = useRoute<{ projectId: string }>("/projects/:projectId/workbench");
  const [, navigate] = useLocation();
  const projectId = params?.projectId;

  if (!projectId) {
    return (
      <div style={{ padding: 32, color: "#4a5e7a" }} data-testid="workbench-no-project">
        No project selected.
      </div>
    );
  }

  return (
    <WorkbenchPanel
      projectId={projectId}
      onClose={() => navigate("/projects")}
    />
  );
}
