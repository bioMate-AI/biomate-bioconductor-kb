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
  workflowName?: string;
  parameters?: Record<string, unknown>;
  onContinueAnalysis?: (suggestion: string) => void;
}

type TabId = "findings" | "outputs" | "methods" | "params" | "software" | "citations" | "qc";

interface OutputFile {
  step: string;
  name: string;
  path: string;
  ext: string;
}

export function AfterRunReport({
  runId,
  workflowName,
  parameters,
  onContinueAnalysis,
}: AfterRunReportProps) {
  const [tab, setTab] = useState<TabId>("findings");

  const outputs = useFetchOutputs(runId);
  const methods = useFetchMethods(runId);
  const citations = useFetchCitations(workflowName);
  const qcEvents = useFetchQcEvents(runId);

  // Compute which optional tabs to show based on real data presence.
  const visibleTabs = useMemo<Array<[TabId, string]>>(() => {
    const t: Array<[TabId, string]> = [
      ["findings", "Findings"],
      ["outputs", "Outputs"],
    ];
    if (methods.hasRealContent) t.push(["methods", "Methods"]);
    t.push(["params", "Parameters"]);
    // Software is always shown but renders a "Coming soon" placeholder for v0.
    t.push(["software", "Software"]);
    if (citations.length > 0) t.push(["citations", "Citations"]);
    if (qcEvents.length > 0) t.push(["qc", "QC audit"]);
    return t;
  }, [methods.hasRealContent, citations.length, qcEvents.length]);

  return (
    <div className="after-run-report" style={styles.root}>
      <div style={styles.head}>
        <span style={styles.kicker}>After run</span>
        <span style={{ flex: 1 }} />
        <a
          href={`/api/workflows/runs/${runId}/findings/report`}
          download
          style={styles.linkish}
          title="Download a structured methods report"
        >
          ↓ Download report
        </a>
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
        {tab === "outputs" && <OutputsTab outputs={outputs} runId={runId} />}
        {tab === "methods" && <MethodsTab methods={methods} />}
        {tab === "params" && <ParametersTab parameters={parameters} />}
        {tab === "software" && <SoftwareTab />}
        {tab === "citations" && <CitationsTab citations={citations} />}
        {tab === "qc" && <QcAuditTab events={qcEvents} />}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Data hooks — each tab fetches its own endpoint, gracefully tolerating 404s.
// ---------------------------------------------------------------------------

function useFetchOutputs(runId: string): OutputFile[] {
  const [outputs, setOutputs] = useState<OutputFile[]>([]);
  useEffect(() => {
    let cancelled = false;
    fetch(`/api/workflows/runs/${runId}/steps`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        const list: OutputFile[] = [];
        const steps = Array.isArray(data) ? data : data.steps || [];
        for (const s of steps) {
          for (const f of s.outputs || s.files || []) {
            list.push({
              step: s.name || s.id || "",
              name: f.name || f.path?.split("/").pop() || "",
              path: f.path || "",
              ext: (f.extension || f.name?.split(".").pop() || "").toLowerCase(),
            });
          }
        }
        setOutputs(list);
      })
      .catch(() => { /* ignore */ });
    return () => { cancelled = true; };
  }, [runId]);
  return outputs;
}

interface MethodsData {
  text: string;
  toolVersions: Record<string, string>;
  hasRealContent: boolean;
}

function useFetchMethods(runId: string): MethodsData {
  const [data, setData] = useState<MethodsData>({ text: "", toolVersions: {}, hasRealContent: false });
  useEffect(() => {
    let cancelled = false;
    fetch(`/api/invocations/${runId}/methods-report`, { credentials: "include" })
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
  }, [runId]);
  return data;
}

function useFetchCitations(workflowName?: string): Array<{ doi?: string; title: string; url?: string }> {
  const [citations, setCitations] = useState<Array<{ doi?: string; title: string; url?: string }>>([]);
  useEffect(() => {
    if (!workflowName) return;
    let cancelled = false;
    fetch(`/api/workflows/${encodeURIComponent(workflowName)}/citations`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        const arr = Array.isArray(data) ? data : data.citations || [];
        setCitations(arr);
      })
      .catch(() => { /* endpoint may not exist yet — Citations tab simply hides */ });
    return () => { cancelled = true; };
  }, [workflowName]);
  return citations;
}

interface QcEvent {
  ts?: string;
  gate?: string;
  status?: string;
  message?: string;
  measured?: string | number;
  threshold?: string | number;
}

function useFetchQcEvents(runId: string): QcEvent[] {
  const [events, setEvents] = useState<QcEvent[]>([]);
  useEffect(() => {
    let cancelled = false;
    fetch(`/api/workflows/runs/${runId}/qc-events`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        const arr = Array.isArray(data) ? data : data.events || [];
        setEvents(arr);
      })
      .catch(() => { /* not all workflows emit QC; tab simply hides */ });
    return () => { cancelled = true; };
  }, [runId]);
  return events;
}

// ---------------------------------------------------------------------------
// Tab body components
// ---------------------------------------------------------------------------

function OutputsTab({ outputs, runId: _runId }: { outputs: OutputFile[]; runId: string }) {
  if (outputs.length === 0) {
    return <p style={styles.empty}>No output files registered yet.</p>;
  }
  const byStep = outputs.reduce<Record<string, OutputFile[]>>((acc, o) => {
    (acc[o.step] = acc[o.step] || []).push(o);
    return acc;
  }, {});
  return (
    <div style={styles.tabContent}>
      {Object.entries(byStep).map(([step, files]) => (
        <div key={step} style={{ marginBottom: 12 }}>
          <div style={styles.outputStep}>{step}</div>
          <ul style={styles.outputList}>
            {files.map((f) => (
              <li key={f.path || f.name} style={styles.outputItem}>
                <span style={styles.outputName}>{f.name}</span>
                <span style={styles.outputExt}>{f.ext}</span>
              </li>
            ))}
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

function SoftwareTab() {
  return (
    <div style={styles.tabContent}>
      <p style={styles.comingSoon}>
        <strong>Coming soon</strong> — per-run software versions will be sourced
        from each module's <code>versions.yml</code> (already emitted by ~98% of
        BioMate workflows). Pending a backend route at
        <code> /api/invocations/:id/software</code>.
      </p>
    </div>
  );
}

function CitationsTab({ citations }: { citations: Array<{ doi?: string; title: string; url?: string }> }) {
  return (
    <div style={styles.tabContent}>
      <ul style={styles.citationsList}>
        {citations.map((c, i) => (
          <li key={i} style={styles.citationItem}>
            {c.url ? (
              <a href={c.url} target="_blank" rel="noreferrer noopener">{c.title}</a>
            ) : (
              <span>{c.title}</span>
            )}
            {c.doi && <span style={styles.citationDoi}> doi:{c.doi}</span>}
          </li>
        ))}
      </ul>
    </div>
  );
}

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
