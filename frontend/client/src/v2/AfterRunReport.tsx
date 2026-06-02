/**
 * AfterRunReport — 7-tab inline after-run panel for the v2 workflow surface.
 *
 * Tabs (per A3 audit recommendation, docs/20260528_AFTERRUN_FINDINGS.md):
 *   Findings    — always shown (AI-fallback covers every workflow)
 *   Outputs     — always shown (step file list)
 *   Methods     — shown when /api/invocations/:id/methods-report returns
 *                 a non-stub report (i.e. tool_versions or methods_text present)
 *   Parameters  — always shown
 *   Software    — "Coming soon" placeholder for v0; v1 will read
 *                 pipeline_info/software_versions.yml (~98% catalog)
 *   Citations   — shown when /api/workflows/:name/citations returns ≥1 entry
 *                 (cryo-EM RAG + qc_evidence.yaml gate DOIs)
 *   QC audit    — shown when /api/workflows/runs/:id/qc-events returns ≥1 event
 *
 * Hides empty tabs entirely rather than showing placeholders — per audit,
 * placeholders read as "this product is unfinished".
 */
import React, { useEffect, useMemo, useState } from "react";
import { FindingsCard } from "@/components/findings-card";

interface AfterRunReportProps {
  runId: string;
  invocationId?: string;       // backend Galaxy/Nextflow invocation id (for /qc-events)
  workflowName?: string;
  parameters?: Record<string, unknown>;
  /** Pre-fetched outputs from the parent's executionRun state — preferred
   *  over a separate /steps fetch which doesn't exist as an endpoint. */
  outputs?: OutputFile[];
  /** Run state for the failure section + Outputs header directory link. */
  executionStatus?: string;
  errorMessage?: string;
  nextflowOutputDir?: string;
  logTail?: string[];
  failedSteps?: string[];
  onContinueAnalysis?: (suggestion: string) => void;
}

type TabId = "findings" | "outputs" | "methods" | "params" | "qc";
// "software" + "citations" will rejoin once their backend routes exist.

interface OutputFile {
  step: string;
  name: string;
  path: string;
  ext: string;
}

export function AfterRunReport({
  runId,
  invocationId,
  workflowName,
  parameters,
  outputs: outputsProp,
  executionStatus,
  errorMessage,
  nextflowOutputDir,
  logTail,
  failedSteps,
  onContinueAnalysis,
}: AfterRunReportProps) {
  const isFailed = executionStatus === "failed" || executionStatus === "cancelled" || executionStatus === "error";
  const [tab, setTab] = useState<TabId>("findings");

  // Outputs come from the parent's executionRun state (no /steps endpoint exists).
  const outputs = outputsProp ?? [];
  // Methods + QC events keyed off invocationId (the backend Nextflow id), falling back to runId.
  const idForBackend = invocationId || runId;
  const methods = useFetchMethods(idForBackend);
  const qcEvents = useFetchQcEvents(idForBackend);
  // workflowName param kept for future Citations tab; suppress unused-var warning.
  void workflowName;

  // Compute which optional tabs to show based on real data presence.
  // Software + Citations intentionally hidden until their backend routes ship
  // (per A3 audit + user direction 2026-05-29). Re-enable by appending:
  //   t.push(["software", "Software"]);          // needs /api/invocations/:id/software
  //   if (citations.length > 0) t.push([...]);   // needs /api/workflows/:name/citations
  const visibleTabs = useMemo<Array<[TabId, string]>>(() => {
    const t: Array<[TabId, string]> = [
      ["findings", "Findings"],
      ["outputs", "Outputs"],
    ];
    if (methods.hasRealContent) t.push(["methods", "Methods"]);
    t.push(["params", "Parameters"]);
    if (qcEvents.length > 0) t.push(["qc", "QC audit"]);
    return t;
  }, [methods.hasRealContent, qcEvents.length]);

  const handleDownload = () => {
    const md = buildFullReportMarkdown({
      runId,
      workflowName,
      parameters,
      outputs,
      methods: methods.text,
      qcEvents,
    });
    const blob = new Blob([md], { type: "text/markdown;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `biomate-run-${runId}.md`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="after-run-report" style={styles.root}>
      <div style={styles.head}>
        <span style={styles.kicker}>After run</span>
        <span style={{ flex: 1 }} />
        <button
          type="button"
          onClick={handleDownload}
          style={{ ...styles.linkish, background: "none", border: "none", cursor: "pointer", padding: 0 }}
          title="Download a comprehensive markdown report stitching every tab"
          data-testid="afterrun-download-report"
        >
          ↓ Download report
        </button>
      </div>
      <div role="tablist" style={styles.tabBar}>
        {visibleTabs.map(([id, label]) => (
          <button
            key={id}
            role="tab"
            aria-selected={tab === id}
            onClick={() => setTab(id)}
            data-testid={`after-tab-${id}`}
            style={{
              ...styles.tab,
              ...(tab === id ? styles.tabActive : null),
            }}
          >
            {label}
          </button>
        ))}
      </div>
      <div style={styles.body}>
        {tab === "findings" && (
          <FindingsCard runId={runId} onContinueAnalysis={onContinueAnalysis} />
        )}
        {tab === "outputs" && <OutputsTab outputs={outputs} runId={runId} invocationId={invocationId} />}
        {tab === "methods" && <MethodsTab methods={methods} />}
        {tab === "params" && <ParametersTab parameters={parameters} />}
        {tab === "qc" && <QcAuditTab events={qcEvents} />}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Data hooks — each tab fetches its own endpoint, gracefully tolerating 404s.
// ---------------------------------------------------------------------------

interface MethodsData {
  text: string;
  toolVersions: Record<string, string>;
  hasRealContent: boolean;
}

function useFetchMethods(invocationId: string): MethodsData {
  const [data, setData] = useState<MethodsData>({ text: "", toolVersions: {}, hasRealContent: false });
  useEffect(() => {
    if (!invocationId) return;
    let cancelled = false;
    fetch(`/api/invocations/${invocationId}/methods-report`, { credentials: "include" })
      .then((r) => (r.ok ? r.text() : ""))
      .then((text) => {
        if (cancelled) return;
        // Stub detector: per A3 audit, the local fallback writes 5 lines
        // ending with "No QC events recorded for this invocation."
        const isStub = !text || /No QC events recorded/.test(text) || text.length < 200;
        setData({ text, toolVersions: {}, hasRealContent: !isStub });
      })
      .catch(() => { /* ignore */ });
    return () => { cancelled = true; };
  }, [invocationId]);
  return data;
}

// Citations tab is commented out until /api/workflows/:name/citations
// backend route ships. Restoration template kept inline near the visibleTabs
// builder for re-enabling later.

interface QcEvent {
  ts?: string;
  gate?: string;
  status?: string;
  message?: string;
  measured?: string | number;
  threshold?: string | number;
}

function useFetchQcEvents(invocationId: string): QcEvent[] {
  const [events, setEvents] = useState<QcEvent[]>([]);
  useEffect(() => {
    if (!invocationId) return;
    let cancelled = false;
    // Backend route lives at /api/invocations/:id/qc-events (nextflow_executor.py:4478)
    fetch(`/api/invocations/${invocationId}/qc-events`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        const arr = Array.isArray(data) ? data : data.events || [];
        setEvents(arr);
      })
      .catch(() => { /* not all workflows emit QC; tab simply hides */ });
    return () => { cancelled = true; };
  }, [invocationId]);
  return events;
}

// ---------------------------------------------------------------------------
// Tab body components
// ---------------------------------------------------------------------------

function OutputsTab({
  outputs,
  runId,
  invocationId,
}: { outputs: OutputFile[]; runId: string; invocationId?: string }) {
  // Total size summary (when present in the output records)
  const totalCount = outputs.length;
  const dlAllUrl = invocationId ? `/api/invocations/${invocationId}/download-all` : null;
  const reproUrl = `/api/nextflow/runs/${runId}/reproducibility`;

  if (totalCount === 0) {
    return (
      <div style={styles.tabContent}>
        <p style={styles.empty}>No output files registered yet.</p>
        {/* Bulk-download actions still visible so the user can pull a partial bundle. */}
        <div style={styles.bulkActions}>
          {dlAllUrl && (
            <a href={dlAllUrl} download style={styles.bulkBtn} data-testid="afterrun-download-all">
              ↓ Download all as ZIP
            </a>
          )}
          <a href={reproUrl} download style={{ ...styles.bulkBtn, ...styles.bulkBtnSecondary }}>
            ↓ Reproducibility bundle
          </a>
        </div>
      </div>
    );
  }

  const byStep = outputs.reduce<Record<string, OutputFile[]>>((acc, o) => {
    (acc[o.step] = acc[o.step] || []).push(o);
    return acc;
  }, {});

  return (
    <div style={styles.tabContent}>
      {/* Bulk-download actions — for intermediate / large outputs where
          per-file preview isn't useful, the user grabs everything as a
          ZIP and inspects locally. */}
      <div style={styles.bulkActions}>
        {dlAllUrl && (
          <a href={dlAllUrl} download style={styles.bulkBtn} data-testid="afterrun-download-all">
            ↓ Download all ({totalCount}) as ZIP
          </a>
        )}
        <a
          href={reproUrl}
          download
          style={{ ...styles.bulkBtn, ...styles.bulkBtnSecondary }}
          title="Configs, command scripts, logs, versions.yml — enough to re-run elsewhere"
        >
          ↓ Reproducibility bundle
        </a>
      </div>

      {Object.entries(byStep).map(([step, files]) => (
        <div key={step} style={{ marginBottom: 12 }}>
          <div style={styles.outputStep}>{step}</div>
          <ul style={styles.outputList}>
            {files.map((f) => {
              const fileUrl = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(f.path || f.name)}&download=1`;
              return (
                <li key={f.path || f.name} style={styles.outputItem}>
                  <a
                    href={fileUrl}
                    download
                    style={{ ...styles.outputName, textDecoration: 'none', color: 'inherit' }}
                    title={`Download ${f.name}`}
                  >
                    {f.name}
                  </a>
                  <span style={styles.outputExt}>{f.ext}</span>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </div>
  );
}

function MethodsTab({ methods }: { methods: MethodsData }) {
  if (!methods.hasRealContent) {
    return <p style={styles.empty}>Methods report not available for this workflow.</p>;
  }
  return (
    <pre style={styles.methodsBody}>{methods.text}</pre>
  );
}

function ParametersTab({ parameters }: { parameters?: Record<string, unknown> }) {
  const entries = parameters ? Object.entries(parameters) : [];
  if (entries.length === 0) {
    return <p style={styles.empty}>No parameter values recorded.</p>;
  }
  return (
    <div style={styles.tabContent}>
      <table style={styles.kvTable}>
        <tbody>
          {entries.map(([k, v]) => (
            <tr key={k}>
              <td style={styles.kvKey}>{k}</td>
              <td style={styles.kvVal}>{String(v)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// SoftwareTab + CitationsTab removed for v0 — restore when backend routes
// /api/invocations/:id/software and /api/workflows/:name/citations ship.

function QcAuditTab({ events }: { events: QcEvent[] }) {
  return (
    <div style={styles.tabContent}>
      <table style={styles.qcTable}>
        <thead>
          <tr>
            <th>Time</th>
            <th>Gate</th>
            <th>Status</th>
            <th>Measured</th>
            <th>Threshold</th>
            <th>Message</th>
          </tr>
        </thead>
        <tbody>
          {events.map((e, i) => (
            <tr key={i}>
              <td style={styles.qcCell}>{e.ts ?? ""}</td>
              <td style={styles.qcCell}>{e.gate ?? ""}</td>
              <td style={{ ...styles.qcCell, color: qcStatusColor(e.status) }}>{e.status ?? ""}</td>
              <td style={styles.qcCell}>{e.measured ?? ""}</td>
              <td style={styles.qcCell}>{e.threshold ?? ""}</td>
              <td style={styles.qcCell}>{e.message ?? ""}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * Build a comprehensive markdown report stitching every visible tab into
 * one document. Lives client-side so no new backend route is needed for v0.
 * Future: add a server-side DOCX/PDF generator and switch the download
 * button to call it.
 */
function buildFullReportMarkdown(args: {
  runId: string;
  workflowName?: string;
  parameters?: Record<string, unknown>;
  outputs: OutputFile[];
  methods: string;
  qcEvents: QcEvent[];
}): string {
  const { runId, workflowName, parameters, outputs, methods, qcEvents } = args;
  const lines: string[] = [];
  lines.push(`# BioMate Run Report`);
  lines.push("");
  lines.push(`- **Run ID**: \`${runId}\``);
  if (workflowName) lines.push(`- **Workflow**: ${workflowName}`);
  lines.push(`- **Generated**: ${new Date().toISOString()}`);
  lines.push("");

  // Findings — Findings tab content is fetched independently inside
  // FindingsCard and not held by this component. Surface a pointer so
  // the report reader knows to fetch the live findings if they need them.
  lines.push(`## Findings`);
  lines.push("");
  lines.push(`The Findings tab in the UI loads structured AI-generated findings`);
  lines.push(`from \`/api/workflows/runs/${runId}/findings\`. Open that URL or the`);
  lines.push(`run in BioMate to view the live findings summary, key results, caveats,`);
  lines.push(`and recommended next steps.`);
  lines.push("");

  // Outputs
  lines.push(`## Outputs`);
  lines.push("");
  if (outputs.length === 0) {
    lines.push(`_No output files registered for this run._`);
  } else {
    const byStep: Record<string, OutputFile[]> = {};
    for (const o of outputs) (byStep[o.step] = byStep[o.step] || []).push(o);
    for (const [step, files] of Object.entries(byStep)) {
      lines.push(`### ${step || "(unspecified step)"}`);
      lines.push("");
      lines.push(`| File | Type |`);
      lines.push(`|------|------|`);
      for (const f of files) lines.push(`| ${f.name} | ${f.ext || "—"} |`);
      lines.push("");
    }
  }

  // Methods
  if (methods && methods.trim()) {
    lines.push(`## Methods`);
    lines.push("");
    lines.push("```");
    lines.push(methods.trim());
    lines.push("```");
    lines.push("");
  }

  // Parameters
  lines.push(`## Parameters`);
  lines.push("");
  const params = parameters ? Object.entries(parameters) : [];
  if (params.length === 0) {
    lines.push(`_No parameter values recorded._`);
  } else {
    lines.push(`| Parameter | Value |`);
    lines.push(`|-----------|-------|`);
    for (const [k, v] of params) lines.push(`| \`${k}\` | ${String(v)} |`);
  }
  lines.push("");

  // QC audit
  if (qcEvents.length > 0) {
    lines.push(`## QC Audit`);
    lines.push("");
    lines.push(`| Time | Gate | Status | Measured | Threshold | Message |`);
    lines.push(`|------|------|--------|----------|-----------|---------|`);
    for (const e of qcEvents) {
      lines.push(
        `| ${e.ts ?? ""} | ${e.gate ?? ""} | ${e.status ?? ""} | ${e.measured ?? ""} | ${e.threshold ?? ""} | ${(e.message ?? "").replace(/\|/g, "\\|")} |`,
      );
    }
    lines.push("");
  }

  lines.push(`---`);
  lines.push(`_Generated by BioMate AfterRunReport (v2 preview). Software`);
  lines.push(`versions and citation tabs will appear once their backend routes`);
  lines.push(`ship — see docs/20260528_AFTERRUN_FINDINGS.md._`);

  return lines.join("\n");
}

function qcStatusColor(status: string | undefined): string {
  if (!status) return "inherit";
  if (/pass|ok|advis/i.test(status)) return "oklch(0.55 0.13 145)";
  if (/halt|fail|block/i.test(status)) return "oklch(0.55 0.18 25)";
  return "inherit";
}

// ---------------------------------------------------------------------------
// Inline styles — kept local so this component doesn't depend on v2 CSS tokens
// (which are scoped to [data-v2-ui]). Lets us mount AfterRunReport anywhere.
// ---------------------------------------------------------------------------

const styles: Record<string, React.CSSProperties> = {
  root: { display: "flex", flexDirection: "column", gap: 8, padding: 12 },
  head: { display: "flex", alignItems: "center", gap: 8 },
  kicker: { fontSize: 10.5, textTransform: "uppercase", letterSpacing: "0.07em", color: "oklch(0.48 0.012 260)", fontWeight: 600 },
  linkish: { fontSize: 11.5, color: "oklch(0.55 0.14 245)", textDecoration: "none", display: "inline-flex", alignItems: "center", gap: 4 },
  tabBar: { display: "flex", gap: 4, borderBottom: "1px solid oklch(0.92 0.005 240)" },
  tab: { background: "transparent", border: "none", padding: "8px 12px", fontSize: 12.5, color: "oklch(0.48 0.012 260)", cursor: "pointer", borderBottom: "2px solid transparent", marginBottom: -1 },
  tabActive: { color: "oklch(0.22 0.01 260)", borderBottomColor: "oklch(0.55 0.14 245)", fontWeight: 500 },
  body: { paddingTop: 8 },
  empty: { fontSize: 12, color: "oklch(0.48 0.012 260)", fontStyle: "italic", padding: "16px 4px" },
  tabContent: { fontSize: 12.5 },
  bulkActions: { display: "flex", gap: 8, marginBottom: 12, flexWrap: "wrap" as React.CSSProperties["flexWrap"] },
  bulkBtn: { display: "inline-flex", alignItems: "center", gap: 6, padding: "6px 12px", fontSize: 12, color: "white", background: "oklch(0.55 0.14 245)", borderRadius: 6, textDecoration: "none", cursor: "pointer" },
  bulkBtnSecondary: { background: "oklch(0.93 0.01 240)", color: "oklch(0.22 0.01 260)" },
  outputStep: { fontSize: 11, fontWeight: 600, color: "oklch(0.35 0.01 260)", marginBottom: 4, textTransform: "uppercase", letterSpacing: "0.04em" },
  outputList: { listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 3 },
  outputItem: { display: "flex", justifyContent: "space-between", padding: "4px 8px", background: "oklch(0.98 0.003 240)", borderRadius: 4 },
  outputName: { fontFamily: "JetBrains Mono, ui-monospace, monospace", fontSize: 11.5, color: "oklch(0.22 0.01 260)" },
  outputExt: { fontSize: 10, color: "oklch(0.48 0.012 260)", textTransform: "uppercase" },
  methodsBody: { fontSize: 11.5, fontFamily: "ui-monospace, monospace", background: "oklch(0.97 0.003 240)", padding: 12, borderRadius: 6, whiteSpace: "pre-wrap", maxHeight: 480, overflowY: "auto" },
  kvTable: { width: "100%", borderCollapse: "collapse" as React.CSSProperties["borderCollapse"] },
  kvKey: { padding: "4px 8px", fontSize: 11.5, fontWeight: 500, color: "oklch(0.35 0.01 260)", verticalAlign: "top", whiteSpace: "nowrap" },
  kvVal: { padding: "4px 8px", fontSize: 11.5, fontFamily: "ui-monospace, monospace", color: "oklch(0.22 0.01 260)", wordBreak: "break-all" },
  comingSoon: { fontSize: 12, color: "oklch(0.48 0.012 260)", padding: 16, background: "oklch(0.98 0.003 240)", borderRadius: 6, lineHeight: 1.5 },
  citationsList: { listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 6 },
  citationItem: { padding: "6px 8px", fontSize: 11.5, background: "oklch(0.98 0.003 240)", borderRadius: 4 },
  citationDoi: { color: "oklch(0.48 0.012 260)", fontFamily: "ui-monospace, monospace" },
  qcTable: { width: "100%", borderCollapse: "collapse" as React.CSSProperties["borderCollapse"], fontSize: 11 },
  qcCell: { padding: "4px 6px", borderBottom: "1px solid oklch(0.93 0.005 240)", textAlign: "left", verticalAlign: "top" },
};
