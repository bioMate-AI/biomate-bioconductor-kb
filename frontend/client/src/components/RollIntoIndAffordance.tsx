/**
 * RollIntoIndAffordance — inline "roll this workflow into an IND project"
 * button at the bottom of a completed-workflow chat message.
 *
 * Behavior (matches the existing comment in chat-message.tsx that
 * referenced this component before the file existed):
 *   - On mount, calls listProjects().
 *   - Hides itself entirely if zero projects exist (no IND projects → no
 *     affordance, no clutter).
 *   - If projects exist, shows a small button. Click expands a project
 *     picker; pick one + confirm → POST /api/ind-report/projects/:id/ingest_workflow.
 *   - Target step is inferred from the workflow name (admet / pbpk /
 *     leads → those buckets; everything else falls back to "compounds"
 *     which is the catch-all step in the IND assembly).
 *   - Shows brief status: idle → posting → success/error, auto-resets
 *     after 4s.
 *
 * Source label: "chat_roll_in" matches the IngestWorkflowRequest source
 * enum so backend analytics can distinguish chat-driven roll-ins from
 * manual page-driven ones.
 */

import { useEffect, useState } from "react";
import {
  listProjects,
  ingestWorkflow,
  type IndProjectRow,
  type IngestWorkflowRequest,
} from "@/lib/ind-report-api";

interface Props {
  workflowName?: string;
  workflowRunId?: string;
}

type State =
  | { kind: "loading" }
  | { kind: "hidden" }
  | { kind: "idle"; projects: IndProjectRow[] }
  | { kind: "picking"; projects: IndProjectRow[]; selected: string }
  | { kind: "posting"; projects: IndProjectRow[] }
  | { kind: "ok"; projects: IndProjectRow[]; projectName: string }
  | { kind: "err"; projects: IndProjectRow[]; reason: string };

function inferTargetStep(name?: string): IngestWorkflowRequest["target_step"] {
  const n = (name ?? "").toLowerCase();
  if (/admet/.test(n)) return "admet";
  if (/pbpk|pk\b|pharmacokinet/.test(n)) return "pbpk";
  if (/lead|reinvent|hit|optim/.test(n)) return "leads";
  return "compounds";
}

export function RollIntoIndAffordance({ workflowName, workflowRunId }: Props) {
  const [state, setState] = useState<State>({ kind: "loading" });

  useEffect(() => {
    let cancelled = false;
    listProjects()
      .then((resp) => {
        if (cancelled) return;
        const projects = resp.projects ?? [];
        if (projects.length === 0) {
          setState({ kind: "hidden" });
          return;
        }
        setState({ kind: "idle", projects });
      })
      .catch(() => {
        if (!cancelled) setState({ kind: "hidden" });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Auto-reset success/error back to idle after 4s
  useEffect(() => {
    if (state.kind !== "ok" && state.kind !== "err") return;
    const t = setTimeout(() => {
      if (state.kind === "ok" || state.kind === "err") {
        setState({ kind: "idle", projects: state.projects });
      }
    }, 4000);
    return () => clearTimeout(t);
  }, [state]);

  if (state.kind === "loading" || state.kind === "hidden") return null;
  if (!workflowRunId) return null; // can't roll in without an invocation id

  const submit = async (projectId: string) => {
    const projectName =
      state.projects.find((p) => p.id === projectId)?.molecule ?? projectId;
    setState({ kind: "posting", projects: state.projects });
    try {
      const r = await ingestWorkflow(projectId, {
        workflow_run_id: workflowRunId,
        target_step: inferTargetStep(workflowName),
        payload: {},
        source: "chat_roll_in",
      });
      if (r.ok) {
        setState({ kind: "ok", projects: state.projects, projectName });
      } else {
        setState({
          kind: "err",
          projects: state.projects,
          reason: r.reason || "Roll-in rejected",
        });
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setState({ kind: "err", projects: state.projects, reason: msg.slice(0, 120) });
    }
  };

  // Styles deliberately minimal — picks up the surrounding chat-message
  // card without imposing a heavy visual.
  const root: React.CSSProperties = {
    marginTop: 8,
    display: "flex",
    alignItems: "center",
    gap: 8,
    fontSize: 12,
    color: "oklch(0.48 0.012 260)",
  };
  const btn: React.CSSProperties = {
    border: "1px solid oklch(0.85 0.012 260)",
    background: "oklch(0.98 0.005 260)",
    borderRadius: 6,
    padding: "4px 10px",
    cursor: "pointer",
    color: "oklch(0.28 0.012 260)",
    fontSize: 12,
  };

  if (state.kind === "ok") {
    return (
      <div style={root} role="status">
        <span>✓ Rolled into <strong>{state.projectName}</strong></span>
      </div>
    );
  }

  if (state.kind === "err") {
    return (
      <div style={root} role="alert">
        <span>✗ Couldn't roll in: {state.reason}</span>
      </div>
    );
  }

  if (state.kind === "posting") {
    return (
      <div style={root} role="status">
        <span>Rolling in…</span>
      </div>
    );
  }

  if (state.kind === "picking") {
    return (
      <div style={root}>
        <label htmlFor="ind-project-picker" style={{ marginRight: 4 }}>Roll into:</label>
        <select
          id="ind-project-picker"
          value={state.selected}
          onChange={(e) =>
            setState({ kind: "picking", projects: state.projects, selected: e.target.value })
          }
          style={{ ...btn, padding: "3px 6px" }}
        >
          {state.projects.map((p) => (
            <option key={p.id} value={p.id}>
              {p.molecule}{p.target ? ` / ${p.target}` : ""} ({p.status})
            </option>
          ))}
        </select>
        <button type="button" style={btn} onClick={() => submit(state.selected)}>
          Confirm
        </button>
        <button
          type="button"
          style={{ ...btn, background: "transparent", border: "none" }}
          onClick={() => setState({ kind: "idle", projects: state.projects })}
        >
          Cancel
        </button>
      </div>
    );
  }

  // idle
  return (
    <div style={root}>
      <button
        type="button"
        style={btn}
        onClick={() => {
          // Skip picker when there's only one project — single click is enough
          if (state.projects.length === 1) {
            submit(state.projects[0].id);
            return;
          }
          setState({
            kind: "picking",
            projects: state.projects,
            selected: state.projects[0].id,
          });
        }}
        title={`Roll this run into an IND project as ${inferTargetStep(workflowName)} data`}
      >
        ↳ Roll into IND project
        {state.projects.length > 1 ? ` (${state.projects.length})` : ""}
      </button>
    </div>
  );
}

export default RollIntoIndAffordance;
