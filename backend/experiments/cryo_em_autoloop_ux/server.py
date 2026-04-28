#!/usr/bin/env python3
"""
Standalone BioMate-style UI for the CryoEM Auto-Loop module.

Serves a browser UI at http://localhost:7788 that matches BioMate's
visual language: dark sidebar, workflow execution card, phase timeline,
QC Settings collapsible, live SSE event stream, per-phase data inspector,
and a findings report with downloadable audit/summary files.

Usage:
    cd backend/experiments
    python -m cryo_em_autoloop_ux.server
    # then open http://localhost:7788
"""

import json
import queue
import sys
import threading
import time
import tempfile
import uuid
from io import StringIO
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Thread-per-request HTTP server (needed for concurrent SSE + page loads)."""
    daemon_threads = True

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent.parent))

from rich.console import Console
from cryo_em_autoloop.params import CryoEMParams
from cryo_em_autoloop_ux.demo import run_scenario
from cryo_em_autoloop_ux.progress_reporter import ProgressReporter

# ── Run registry ──────────────────────────────────────────────────────────────
_runs: dict[str, dict] = {}


def _execute_run(run_id: str, config: dict) -> None:
    run_rec = _runs[run_id]
    q = run_rec["queue"]

    class _Sink:
        def write(self, s):
            for line in s.splitlines():
                if line.strip():
                    try:
                        evt = json.loads(line)
                        run_rec["events"].append(evt)
                        q.put(evt)
                    except Exception:
                        pass
        def flush(self): pass

    reporter = ProgressReporter(
        console=Console(file=StringIO(), highlight=False, markup=False),
        json_sink=_Sink(),
        verbose=True,
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        result = run_scenario(
            config.get("scenario", "retry_then_pass"),
            output_dir=Path(tmpdir),
            reporter=reporter,
            auto_loop_enabled=bool(config.get("auto_loop_enabled", True)),
            enabled_phases=set(config.get("enabled_phases",
                ["phase_A", "phase_B", "phase_C", "phase_D", "phase_E"])),
            max_retries=int(config.get("max_retries", 2)),
            qc_profile=config.get("qc_profile", "cryoem_spa_purified"),
            verbose=False,
        )
        # Read audit JSONL and summary text before tmpdir is deleted
        audit_lines: list[dict] = []
        summary_text: str = ""
        try:
            ap = Path(result.get("audit_path", ""))
            if ap.exists():
                for raw in ap.read_text(encoding="utf-8").strip().splitlines():
                    if raw.strip():
                        try:
                            audit_lines.append(json.loads(raw))
                        except Exception:
                            pass
        except Exception:
            pass
        try:
            sp = Path(result.get("summary_path", ""))
            if sp.exists():
                summary_text = sp.read_text(encoding="utf-8")
        except Exception:
            pass

    run_rec["audit_lines"] = audit_lines
    run_rec["summary_text"] = summary_text

    finish = {"type": "run_complete", "result": {
        "phases_passed":    result["phases_passed"],
        "phases_escalated": result["phases_escalated"],
        "total_attempts":   result["total_attempts"],
    }}
    run_rec["events"].append(finish)
    run_rec["done"] = True
    q.put(finish)


# ── HTML ──────────────────────────────────────────────────────────────────────
HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>BioMate — CryoSPARC Auto-Loop</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --bg:       #0f1117;
  --surface:  #161b27;
  --surface2: #1e2535;
  --border:   #2a3347;
  --text:     #e2e8f0;
  --muted:    #64748b;
  --accent:   #10b981;
  --accent2:  #3b82f6;
  --warn:     #f59e0b;
  --danger:   #ef4444;
  --radius:   8px;
}
body { font-family: system-ui,-apple-system,sans-serif; background:var(--bg); color:var(--text);
       min-height:100vh; display:flex; flex-direction:column; }

/* ── Top nav bar ── */
.topbar { height:48px; background:var(--surface); border-bottom:1px solid var(--border);
          display:flex; align-items:center; padding:0 20px; gap:16px; flex-shrink:0; }
.topbar-logo { font-size:.95rem; font-weight:700; color:#f8fafc; display:flex; align-items:center; gap:6px; }
.topbar-logo span { color:var(--accent); }
.topbar-sep { width:1px; height:20px; background:var(--border); }
.topbar-crumb { font-size:.78rem; color:var(--muted); }
.topbar-crumb b { color:var(--text); }
.topbar-badge { margin-left:auto; font-size:.7rem; background:#1e3a5f; color:#60a5fa;
                border:1px solid #2563eb; border-radius:4px; padding:2px 8px; }

/* ── Layout ── */
.layout { display:flex; flex:1; overflow:hidden; }
.sidebar { width:220px; background:var(--surface); border-right:1px solid var(--border);
           padding:16px 12px; flex-shrink:0; display:flex; flex-direction:column; gap:4px; }
.sidebar-item { display:flex; align-items:center; gap:8px; padding:7px 10px; border-radius:6px;
                font-size:.8rem; color:var(--muted); cursor:default; }
.sidebar-item.active { background:var(--surface2); color:var(--text); }
.sidebar-dot { width:6px; height:6px; border-radius:50%; background:var(--accent); flex-shrink:0; }
.sidebar-dot.muted { background:var(--border); }

.main { flex:1; padding:24px; overflow-y:auto; display:flex; gap:20px; align-items:flex-start; }

/* ── Cards ── */
.card { background:var(--surface); border:1px solid var(--border); border-radius:var(--radius); overflow:hidden; }
.card-header { padding:12px 16px; border-bottom:1px solid var(--border);
               display:flex; align-items:center; gap:8px; }
.card-title { font-size:.82rem; font-weight:600; color:#f1f5f9; }
.card-badge { font-size:.68rem; padding:2px 7px; border-radius:10px; font-weight:600; }
.badge-green { background:#064e3b; color:#6ee7b7; border:1px solid #059669; }
.badge-blue  { background:#1e3a5f; color:#93c5fd; border:1px solid #3b82f6; }
.badge-amber { background:#451a03; color:#fcd34d; border:1px solid #d97706; }
.badge-red   { background:#450a0a; color:#fca5a5; border:1px solid #dc2626; }
.badge-gray  { background:var(--surface2); color:var(--muted); border:1px solid var(--border); }

/* ── Left column: workflow card ── */
.col-left { width:420px; flex-shrink:0; display:flex; flex-direction:column; gap:16px; }

/* Phase timeline */
.phase-timeline { padding:14px 16px; display:flex; flex-direction:column; gap:8px; }
.phase-row { display:flex; align-items:center; gap:10px; }
.phase-icon { width:28px; height:28px; border-radius:50%; display:flex; align-items:center;
              justify-content:center; font-size:.7rem; font-weight:700; flex-shrink:0;
              border:2px solid; transition:all .2s; }
.phase-icon.idle     { border-color:var(--border); color:var(--muted); background:transparent; }
.phase-icon.running  { border-color:var(--accent2); color:var(--accent2); background:#1e3a5f;
                       animation:pulse 1.2s ease-in-out infinite; }
.phase-icon.passed   { border-color:var(--accent); color:var(--accent); background:#064e3b; }
.phase-icon.retrying { border-color:var(--warn); color:var(--warn); background:#451a03; }
.phase-icon.escalated{ border-color:var(--danger); color:var(--danger); background:#450a0a; }
@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.5} }
.phase-info { flex:1; }
.phase-name { font-size:.8rem; font-weight:500; color:var(--text); }
.phase-desc { font-size:.71rem; color:var(--muted); margin-top:1px; }
.phase-attempt { font-size:.7rem; padding:1px 6px; border-radius:8px; margin-left:auto;
                 border:1px solid; }
.phase-connector { width:2px; height:14px; background:var(--border); margin-left:13px; }

/* QC Settings collapsible */
.qc-section { border-top:1px solid var(--border); }
.qc-trigger { width:100%; padding:10px 16px; display:flex; align-items:center; justify-content:space-between;
              background:transparent; border:none; color:var(--text); cursor:pointer;
              font-size:.78rem; font-weight:500; }
.qc-trigger:hover { background:var(--surface2); }
.qc-trigger svg { transition:transform .2s; color:var(--muted); }
.qc-trigger.open svg { transform:rotate(180deg); }
.qc-body { padding:12px 16px; border-top:1px solid var(--border); display:flex; flex-direction:column; gap:12px; }

/* Toggle row */
.toggle-row { display:flex; align-items:flex-start; justify-content:space-between; gap:12px; }
.toggle-text .label { font-size:.8rem; font-weight:500; }
.toggle-text .desc  { font-size:.71rem; color:var(--muted); margin-top:2px; }
.switch { position:relative; width:40px; height:22px; flex-shrink:0; cursor:pointer; }
.switch input { opacity:0; width:0; height:0; }
.slider { position:absolute; inset:0; background:#374151; border-radius:22px; transition:.2s; }
.slider:before { content:""; position:absolute; height:16px; width:16px; left:3px; bottom:3px;
                 background:#fff; border-radius:50%; transition:.2s; }
input:checked + .slider { background:var(--accent); }
input:checked + .slider:before { transform:translateX(18px); }

/* Phase chips */
.phase-chips { display:flex; flex-wrap:wrap; gap:6px; }
.phase-chip { padding:3px 9px; border-radius:12px; font-size:.72rem; font-weight:500;
              border:1px solid; cursor:pointer; transition:all .15s; user-select:none; }
.phase-chip.on  { background:#064e3b; border-color:var(--accent); color:#6ee7b7; }
.phase-chip.off { background:transparent; border-color:var(--border); color:var(--muted); }
.phase-chip.locked { opacity:.3; pointer-events:none; }

/* Form elements */
.form-row { display:flex; align-items:center; gap:10px; flex-wrap:wrap; }
.form-label { font-size:.75rem; color:var(--muted); white-space:nowrap; }
select, .num-input { background:var(--surface2); border:1px solid var(--border); color:var(--text);
                     border-radius:5px; padding:5px 8px; font-size:.78rem; }
select:focus, .num-input:focus { outline:2px solid var(--accent); border-color:transparent; }
.num-input { width:52px; text-align:center; }
.divider { height:1px; background:var(--border); }

/* Run button */
.run-btn { margin:14px 16px; padding:9px; width:calc(100% - 32px); background:var(--accent);
           color:#fff; border:none; border-radius:6px; font-size:.84rem; font-weight:600;
           cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px;
           transition:background .15s; }
.run-btn:hover:not(:disabled) { background:#059669; }
.run-btn:disabled { background:#374151; cursor:not-allowed; color:var(--muted); }
.run-btn .spinner { width:14px; height:14px; border:2px solid rgba(255,255,255,.3);
                    border-top-color:#fff; border-radius:50%; display:none;
                    animation:spin .6s linear infinite; }
.run-btn.running .spinner { display:block; }
@keyframes spin { to { transform:rotate(360deg); } }

/* ── Right column ── */
.col-right { flex:1; min-width:0; display:flex; flex-direction:column; gap:16px; }

/* Event stream */
.event-stream { flex:none; }
.event-list { padding:0; height:360px; overflow-y:auto; font-family:'JetBrains Mono','Fira Code',monospace;
              font-size:.71rem; line-height:1.7; }
.event-row { padding:4px 14px; border-bottom:1px solid #0f1117; display:flex; gap:8px; align-items:baseline; }
.event-row:hover { background:var(--surface2); }
.ev-ts { color:#374151; flex-shrink:0; width:90px; }
.ev-type { flex-shrink:0; width:200px; font-weight:600; }
.ev-body { color:#94a3b8; flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.ev-cit  { font-size:.67rem; color:#4b5563; margin-top:-2px; padding:0 14px 4px; display:block; }

.t-autoloop_phase_start    .ev-type { color:#60a5fa; }
.t-autoloop_running        .ev-type { color:#475569; }
.t-autoloop_gate_results   .ev-type { color:#a78bfa; }
.t-autoloop_update         .ev-type { color:var(--warn); }
.t-autoloop_phase_complete .ev-type { color:var(--accent); }
.t-autoloop_escalation     .ev-type { color:var(--danger); }
.t-autoloop_complete       .ev-type { color:#6ee7b7; }
.t-run_complete            .ev-type { color:#6ee7b7; }

/* Summary row */
.summary-row { display:flex; gap:8px; flex-wrap:wrap; padding:12px 16px; }
.sum-chip { padding:3px 10px; border-radius:10px; font-size:.75rem; font-weight:600; border:1px solid; }

/* ── Data Inspector ── */
.phase-tabs { display:flex; border-bottom:1px solid var(--border); background:var(--surface2); }
.phase-tab { flex:1; padding:8px 4px; font-size:.72rem; font-weight:500; border:none;
             background:transparent; color:var(--muted); cursor:pointer; transition:all .15s;
             border-bottom:2px solid transparent; }
.phase-tab:hover { color:var(--text); background:rgba(255,255,255,.03); }
.phase-tab.active { color:var(--accent2); border-bottom-color:var(--accent2); background:transparent; }
.phase-tab.has-data { color:var(--text); }
.phase-tab.has-data.active { color:var(--accent2); }

.inspector-body { height:340px; overflow-y:auto; padding:0; }
.inspector-empty { padding:20px 16px; color:var(--muted); font-size:.78rem; }

.attempt-block { border-bottom:1px solid var(--border); }
.attempt-block:last-child { border-bottom:none; }
.attempt-header { display:flex; align-items:center; gap:8px; padding:8px 14px;
                  background:var(--surface2); font-size:.73rem; font-weight:600; color:var(--text); }
.attempt-header .att-badge { font-size:.66rem; padding:1px 7px; border-radius:8px; border:1px solid; }

.data-section { padding:10px 14px 6px; }
.data-section-label { font-size:.68rem; font-weight:600; color:var(--muted); letter-spacing:.04em;
                       text-transform:uppercase; margin-bottom:6px; }
.data-table { width:100%; border-collapse:collapse; font-size:.72rem; font-family:'JetBrains Mono','Fira Code',monospace; }
.data-table th { color:var(--muted); font-weight:500; padding:3px 8px; text-align:left;
                  border-bottom:1px solid var(--border); font-size:.67rem; text-transform:uppercase; }
.data-table td { padding:3px 8px; border-bottom:1px solid #1a2030; }
.data-table tr:last-child td { border-bottom:none; }
.data-table .param-name { color:#94a3b8; }
.data-table .param-val  { color:#e2e8f0; }
.data-table .param-val.changed { color:#fcd34d; font-weight:600; }
.data-table .num { text-align:right; font-variant-numeric:tabular-nums; }
.gate-pass   td { }
.gate-pass   td:last-child { color:#6ee7b7; }
.gate-advisory td:last-child { color:#fcd34d; }
.gate-halt   td { background:#200a0a; }
.gate-halt   td:last-child { color:#fca5a5; font-weight:600; }
.rationale-box { margin:6px 14px 10px; padding:8px 10px; background:#0d1520;
                  border-left:2px solid #2a3347; border-radius:0 4px 4px 0;
                  font-size:.69rem; color:#64748b; line-height:1.55; }
.rationale-box b { color:#94a3b8; }

/* ── Findings Report ── */
.findings-body { padding:14px 16px; }
.findings-stats { display:flex; gap:10px; flex-wrap:wrap; margin-bottom:12px; }
.stat-chip { padding:5px 12px; border-radius:6px; font-size:.75rem; border:1px solid; }
.summary-pre { font-family:'JetBrains Mono','Fira Code',monospace; font-size:.68rem;
               line-height:1.6; color:#94a3b8; background:#0d1520; border:1px solid var(--border);
               border-radius:5px; padding:12px; overflow-x:auto; white-space:pre;
               max-height:320px; overflow-y:auto; }
.dl-btn { background:var(--surface2); border:1px solid var(--border); color:var(--text);
          padding:5px 12px; border-radius:5px; font-size:.73rem; cursor:pointer;
          transition:all .15s; white-space:nowrap; }
.dl-btn:hover { border-color:var(--accent2); color:var(--accent2); }
.dl-row { display:flex; gap:8px; margin-top:10px; flex-wrap:wrap; }
</style>
</head>
<body>

<!-- Top bar -->
<div class="topbar">
  <div class="topbar-logo">Bio<span>Mate</span></div>
  <div class="topbar-sep"></div>
  <div class="topbar-crumb">Chat &rsaquo; <b>CryoSPARC SPA</b></div>
  <div class="topbar-badge">⚗ Auto-Loop Demo</div>
</div>

<div class="layout">
  <!-- Sidebar -->
  <div class="sidebar">
    <div class="sidebar-item active"><div class="sidebar-dot"></div>CryoSPARC SPA</div>
    <div class="sidebar-item"><div class="sidebar-dot muted"></div>Workflow Params</div>
    <div class="sidebar-item"><div class="sidebar-dot muted"></div>QC Profiles</div>
    <div class="sidebar-item"><div class="sidebar-dot muted"></div>Run History</div>
  </div>

  <!-- Main -->
  <div class="main">

    <!-- Left: workflow execution card -->
    <div class="col-left">
      <div class="card">
        <div class="card-header">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#10b981" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
          <span class="card-title">CryoSPARC Standard SPA</span>
          <span class="card-badge badge-blue" id="run-status-badge">Ready</span>
        </div>

        <!-- Phase timeline -->
        <div class="phase-timeline" id="phase-timeline">
          <!-- rendered by JS -->
        </div>

        <!-- QC Settings -->
        <div class="qc-section">
          <button class="qc-trigger open" onclick="toggleQc(this)">
            <span style="display:flex;align-items:center;gap:6px">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
              QC &amp; Auto-Loop Settings
            </span>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>
          </button>

          <div class="qc-body" id="qc-body">
            <!-- Auto-loop global -->
            <div class="toggle-row">
              <div class="toggle-text">
                <div class="label">Auto-loop parameter tuning</div>
                <div class="desc" id="loop-desc">Retry failed phases with literature-backed param changes</div>
              </div>
              <label class="switch">
                <input type="checkbox" id="global-toggle" checked onchange="onGlobalToggle()">
                <span class="slider"></span>
              </label>
            </div>

            <!-- Per-phase chips -->
            <div id="phase-chips-wrap">
              <div class="form-label" style="margin-bottom:5px">Retry enabled per phase</div>
              <div class="phase-chips" id="phase-chips">
                <span class="phase-chip on" data-phase="phase_A" onclick="togglePhase(this)">A · Motion/CTF</span>
                <span class="phase-chip on" data-phase="phase_B" onclick="togglePhase(this)">B · Picking</span>
                <span class="phase-chip on" data-phase="phase_C" onclick="togglePhase(this)">C · 2D Class</span>
                <span class="phase-chip on" data-phase="phase_D" onclick="togglePhase(this)">D · 3D Recon</span>
                <span class="phase-chip on" data-phase="phase_E" onclick="togglePhase(this)">E · Refine</span>
              </div>
            </div>

            <div class="divider"></div>

            <!-- Scenario + profile -->
            <div class="form-row">
              <span class="form-label">Scenario</span>
              <select id="scenario" style="flex:1">
                <option value="retry_then_pass">retry_then_pass — Phase A fails, retries, passes</option>
                <option value="all_pass">all_pass — All phases pass first try</option>
                <option value="escalation">escalation — Phase A exhausts retries</option>
                <option value="membrane_profile">membrane_profile — Relaxed thresholds</option>
                <option value="multi_gate_failure">multi_gate_failure — Multiple gates fire</option>
              </select>
            </div>
            <div class="form-row">
              <span class="form-label">QC profile</span>
              <select id="qc-profile">
                <option value="cryoem_spa_purified">cryoem_spa_purified</option>
                <option value="cryoem_spa_membrane">cryoem_spa_membrane</option>
                <option value="cryoem_spa_standard">cryoem_spa_standard</option>
              </select>
              <span class="form-label" style="margin-left:8px">Max retries</span>
              <input class="num-input" type="number" id="max-retries" min="0" max="5" value="2">
            </div>
          </div>
        </div>

        <!-- Run button -->
        <button class="run-btn" id="run-btn" onclick="startRun()">
          <div class="spinner"></div>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
          Confirm &amp; Run
        </button>

        <!-- Summary chips (post-run) -->
        <div class="summary-row" id="summary-row" style="display:none"></div>
      </div>
    </div>

    <!-- Right: event stream + inspector + findings -->
    <div class="col-right">

      <!-- Event stream card -->
      <div class="card event-stream">
        <div class="card-header">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#60a5fa" stroke-width="2"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
          <span class="card-title">Live SSE Event Stream</span>
          <span class="card-badge badge-gray" id="event-count">0 events</span>
        </div>
        <div class="event-list" id="event-list">
          <div style="padding:16px;color:var(--muted);font-size:.78rem">
            Configure settings and click <b>Confirm &amp; Run</b> to start.
          </div>
        </div>
      </div>

      <!-- Data Inspector card -->
      <div class="card" id="data-inspector" style="display:none">
        <div class="card-header">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
          <span class="card-title">Phase Data Inspector</span>
          <span class="card-badge badge-gray" id="inspector-badge">Select a phase tab</span>
        </div>
        <!-- Phase tabs -->
        <div class="phase-tabs" id="phase-tabs">
          <button class="phase-tab active" data-phase="phase_A" onclick="selectPhase('phase_A')">A · Motion/CTF</button>
          <button class="phase-tab" data-phase="phase_B" onclick="selectPhase('phase_B')">B · Picking</button>
          <button class="phase-tab" data-phase="phase_C" onclick="selectPhase('phase_C')">C · 2D Class</button>
          <button class="phase-tab" data-phase="phase_D" onclick="selectPhase('phase_D')">D · 3D Recon</button>
          <button class="phase-tab" data-phase="phase_E" onclick="selectPhase('phase_E')">E · Refine</button>
        </div>
        <!-- Phase content -->
        <div class="inspector-body" id="inspector-body">
          <div class="inspector-empty">Run a scenario to inspect per-phase input parameters and gate results.</div>
        </div>
      </div>

      <!-- Findings Report card (shown after run_complete) -->
      <div class="card" id="findings-card" style="display:none">
        <div class="card-header">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#6ee7b7" stroke-width="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>
          <span class="card-title">Run Report &amp; Findings</span>
          <div id="findings-dl-row" style="margin-left:auto;display:flex;gap:6px"></div>
        </div>
        <div class="findings-body" id="findings-body">
          <div style="color:var(--muted);font-size:.78rem">Loading report…</div>
        </div>
      </div>

    </div><!-- col-right -->

  </div><!-- main -->
</div><!-- layout -->

<script>
const PHASES = [
  { id:'phase_A', label:'Motion Correction + CTF', short:'A' },
  { id:'phase_B', label:'Particle Picking',         short:'B' },
  { id:'phase_C', label:'2D Classification',        short:'C' },
  { id:'phase_D', label:'3D Reconstruction',        short:'D' },
  { id:'phase_E', label:'Refinement',               short:'E' },
];

const GATE_LABELS = {
  motion_drift:           'Total motion drift (Å)',
  per_frame_drift:        'Per-frame drift (Å/frame)',
  ctf_fit_quality:        'CTF fit quality (FOM)',
  astigmatism:            'Astigmatism (Å)',
  junk_fraction:          'Junk class fraction',
  particle_yield:         'Particles selected',
  orientation_anisotropy: 'Orientation anisotropy',
  class_quality:          'Mean 2D class quality',
  abinitio_class_score:   'Ab-initio class score',
  abinitio_resolution:    'Ab-initio resolution (Å)',
  fsc_resolution:         'FSC 0.143 resolution (Å)',
};

let phaseState   = Object.fromEntries(PHASES.map(p => [p.id, 'idle']));
let phaseAttempt = Object.fromEntries(PHASES.map(p => [p.id, 1]));
let eventCount   = 0;

// ── Phase data store (populated from SSE events) ──────────────────────────────
// Structure: { phase_A: [ {attempt, params, gates, changes}, ... ], ... }
let phaseData       = Object.fromEntries(PHASES.map(p => [p.id, []]));
let selectedPhaseId = 'phase_A';
let currentRunId    = null;

function resetPhaseData() {
  phaseData       = Object.fromEntries(PHASES.map(p => [p.id, []]));
  selectedPhaseId = 'phase_A';
  // Reset tab highlights
  document.querySelectorAll('.phase-tab').forEach(t => {
    t.classList.remove('has-data');
    t.classList.toggle('active', t.dataset.phase === 'phase_A');
  });
}

// ── Phase timeline renderer ───────────────────────────────────────────────────

function renderTimeline() {
  const el = document.getElementById('phase-timeline');
  el.innerHTML = PHASES.map((p, i) => {
    const s = phaseState[p.id];
    const att = phaseAttempt[p.id];
    const attEl = s !== 'idle'
      ? `<span class="phase-attempt badge-${s==='passed'?'green':s==='retrying'?'amber':s==='escalated'?'red':'blue'}"
             style="border-color:transparent">
           ${s === 'retrying' ? `retry ${att}` : s === 'running' ? 'running' : s === 'escalated' ? 'escalated' : `attempt ${att}`}
         </span>`
      : '';
    const connector = i < PHASES.length - 1
      ? `<div class="phase-connector"></div>` : '';
    return `
      <div class="phase-row">
        <div class="phase-icon ${s}">${p.short}</div>
        <div class="phase-info">
          <div class="phase-name">${p.label}</div>
          <div class="phase-desc">${s==='idle'?'Waiting...':s==='running'?'In progress...':s==='retrying'?'Adjusting parameters...':s==='passed'?'Quality gates passed':s==='escalated'?'Escalated — human review needed':''}</div>
        </div>
        ${attEl}
      </div>${connector}`;
  }).join('');
}
renderTimeline();

// ── QC toggle handlers ────────────────────────────────────────────────────────

function toggleQc(btn) {
  const body = document.getElementById('qc-body');
  const open = body.style.display !== 'none';
  body.style.display = open ? 'none' : 'block';
  btn.classList.toggle('open', !open);
}

function onGlobalToggle() {
  const on = document.getElementById('global-toggle').checked;
  document.getElementById('loop-desc').textContent = on
    ? 'Retry failed phases with literature-backed param changes'
    : 'Run each phase once — no retry on QC failure';
  document.querySelectorAll('.phase-chip').forEach(c => {
    c.classList.toggle('disabled-global', !on);
  });
}

function togglePhase(chip) {
  chip.classList.toggle('on');
  chip.classList.toggle('off');
}

// ── Phase inspector tab selection ─────────────────────────────────────────────

function selectPhase(phaseId) {
  selectedPhaseId = phaseId;
  document.querySelectorAll('.phase-tab').forEach(t => {
    t.classList.toggle('active', t.dataset.phase === phaseId);
  });
  renderInspector();
}

// ── Data Inspector renderer ───────────────────────────────────────────────────

function renderInspector() {
  const body   = document.getElementById('inspector-body');
  const badge  = document.getElementById('inspector-badge');
  const attempts = phaseData[selectedPhaseId] || [];

  if (!attempts.length) {
    body.innerHTML = `<div class="inspector-empty">No data yet for ${selectedPhaseId.replace('_', ' ')}.</div>`;
    badge.textContent = 'No data';
    badge.className   = 'card-badge badge-gray';
    return;
  }

  // Badge: total attempts for this phase
  const last = attempts[attempts.length - 1];
  const lastGatesPassed = last.gates ? last.gates.every(g => g.action === 'pass' || g.action === 'advisory') : null;
  badge.textContent = `${attempts.length} attempt${attempts.length>1?'s':''} · ${selectedPhaseId.replace('_',' ')}`;
  badge.className   = `card-badge ${lastGatesPassed === false ? 'badge-red' : lastGatesPassed === true ? 'badge-green' : 'badge-blue'}`;

  let html = '';
  attempts.forEach(att => {
    // Determine attempt outcome
    const passed = att.gates ? att.gates.every(g => g.action !== 'halt') : null;
    const hasHalt = att.gates ? att.gates.some(g => g.action === 'halt') : false;
    const badgeCls = passed === null ? 'badge-blue' : passed ? 'badge-green' : 'badge-red';
    const badgeLabel = passed === null ? 'running' : passed ? 'PASS' : 'HALT';

    html += `<div class="attempt-block" data-attempt="${att.attempt}">`;
    html += `<div class="attempt-header">
               Attempt ${att.attempt}
               <span class="att-badge ${badgeCls}" style="border-color:transparent">${badgeLabel}</span>
             </div>`;

    // ── Input Parameters ───────────────────────────────────────────────
    if (att.params && Object.keys(att.params).length) {
      html += `<div class="data-section">
                 <div class="data-section-label">Input Parameters</div>
                 <table class="data-table" data-section="input-params">
                   <tr><th>Parameter</th><th>Value</th></tr>`;
      Object.entries(att.params).forEach(([k, v]) => {
        // Highlight params changed from previous attempt
        const prevAtt = att.attempt > 1 ? attempts.find(a => a.attempt === att.attempt - 1) : null;
        const prevVal = prevAtt?.params?.[k];
        const changed = prevAtt && prevVal !== undefined && String(prevVal) !== String(v);
        html += `<tr>
                   <td class="param-name">${k}</td>
                   <td class="param-val${changed ? ' changed' : ''}">${v}${changed ? ` <small style="color:#6b7280">(was ${prevVal})</small>` : ''}</td>
                 </tr>`;
      });
      html += `</table></div>`;
    }

    // ── QC Gate Results ────────────────────────────────────────────────
    if (att.gates && att.gates.length) {
      html += `<div class="data-section">
                 <div class="data-section-label">QC Gate Results</div>
                 <table class="data-table" data-section="gate-results">
                   <tr><th>Gate</th><th class="num">Measured</th><th class="num">Threshold</th><th>Result</th></tr>`;
      att.gates.forEach(g => {
        const cls = g.action === 'halt' ? 'gate-halt' : g.action === 'advisory' ? 'gate-advisory' : 'gate-pass';
        const sym = g.action === 'halt' ? '✗' : g.action === 'advisory' ? '⚠' : '✓';
        const label = GATE_LABELS[g.gate] || g.gate;
        const measured = typeof g.value === 'number' ? g.value.toPrecision(4) : g.value;
        const thresh   = typeof g.threshold === 'number' ? g.threshold.toPrecision(4) : g.threshold;
        html += `<tr class="${cls}">
                   <td>${label}</td>
                   <td class="num">${measured}</td>
                   <td class="num">${thresh}</td>
                   <td>${sym} ${g.action}</td>
                 </tr>`;
      });
      html += `</table></div>`;
    }

    // ── Auto-Loop Parameter Changes (for this attempt's remediations) ──
    if (att.changes && att.changes.length) {
      const hasChanges = att.changes.some(r => Object.keys(r.param_changes || {}).length > 0);
      if (hasChanges) {
        html += `<div class="data-section">
                   <div class="data-section-label">Auto-Loop Parameter Adjustments</div>`;
        att.changes.forEach(rem => {
          const changes = rem.param_changes || {};
          if (!Object.keys(changes).length) return;
          html += `<table class="data-table" data-section="param-changes">
                     <tr><th>Parameter</th><th>New Value</th></tr>`;
          Object.entries(changes).forEach(([k, v]) => {
            html += `<tr><td class="param-name">${k}</td><td class="param-val changed">${v}</td></tr>`;
          });
          html += `</table>`;
          if (rem.rationale) {
            html += `<div class="rationale-box"><b>Rationale:</b> ${escapeHtml(rem.rationale)}</div>`;
          }
        });
        html += `</div>`;
      }
    }

    html += `</div>`; // attempt-block
  });

  body.innerHTML = html;
}

// ── Run ───────────────────────────────────────────────────────────────────────

async function startRun() {
  const btn     = document.getElementById('run-btn');
  const list    = document.getElementById('event-list');
  const summary = document.getElementById('summary-row');

  btn.disabled = true;
  btn.classList.add('running');
  list.innerHTML = '';
  summary.style.display = 'none';
  summary.innerHTML = '';
  eventCount = 0;
  document.getElementById('event-count').textContent = '0 events';
  document.getElementById('run-status-badge').textContent = 'Running';
  document.getElementById('run-status-badge').className = 'card-badge badge-blue';

  // Reset phase state
  phaseState   = Object.fromEntries(PHASES.map(p => [p.id, 'idle']));
  phaseAttempt = Object.fromEntries(PHASES.map(p => [p.id, 1]));
  renderTimeline();

  // Reset data inspector
  resetPhaseData();
  document.getElementById('data-inspector').style.display = 'none';
  document.getElementById('findings-card').style.display = 'none';
  document.getElementById('findings-body').innerHTML = '<div style="color:var(--muted);font-size:.78rem">Loading report…</div>';

  const globalOn = document.getElementById('global-toggle').checked;
  const enabledPhases = globalOn
    ? [...document.querySelectorAll('.phase-chip.on')].map(c => c.dataset.phase)
    : [];

  const res = await fetch('/api/run', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({
      scenario:          document.getElementById('scenario').value,
      qc_profile:        document.getElementById('qc-profile').value,
      max_retries:       parseInt(document.getElementById('max-retries').value, 10),
      auto_loop_enabled: globalOn,
      enabled_phases:    enabledPhases,
    }),
  });
  const {run_id} = await res.json();
  currentRunId = run_id;

  const es = new EventSource(`/api/events/${run_id}`);
  es.onmessage = (msg) => {
    const evt = JSON.parse(msg.data);
    handleEvent(evt);
    if (evt.type === 'run_complete') {
      es.close();
      btn.disabled = false;
      btn.classList.remove('running');
      const passed = evt.result.phases_escalated.length === 0;
      document.getElementById('run-status-badge').textContent = passed ? 'Completed' : 'Escalated';
      document.getElementById('run-status-badge').className = `card-badge ${passed ? 'badge-green' : 'badge-amber'}`;
      showSummary(evt.result);
      fetchAndShowReport(run_id);
    }
  };
  es.onerror = () => {
    es.close();
    btn.disabled = false;
    btn.classList.remove('running');
  };
}

// ── Event handler ─────────────────────────────────────────────────────────────

function handleEvent(evt) {
  // Update phase timeline
  if (evt.type === 'autoloop_phase_start') {
    if (evt.attempt > 1) {
      phaseState[evt.phase]   = 'retrying';
      phaseAttempt[evt.phase] = evt.attempt;
    } else {
      phaseState[evt.phase] = 'running';
    }
    renderTimeline();

    // Populate phase data store
    if (phaseData[evt.phase]) {
      phaseData[evt.phase].push({
        attempt: evt.attempt,
        params:  evt.params_summary || {},
        gates:   null,
        changes: null,
      });
    }
    // Mark tab as having data
    const tab = document.querySelector(`.phase-tab[data-phase="${evt.phase}"]`);
    if (tab) tab.classList.add('has-data');
    // Show inspector, auto-select the active phase
    document.getElementById('data-inspector').style.display = 'block';
    if (evt.attempt === 1) {
      selectPhase(evt.phase);
    } else {
      renderInspector();
    }

  } else if (evt.type === 'autoloop_gate_results') {
    const attempts = phaseData[evt.phase];
    if (attempts && attempts.length) {
      attempts[attempts.length - 1].gates = evt.gates;
    }
    if (selectedPhaseId === evt.phase) renderInspector();

  } else if (evt.type === 'autoloop_update') {
    const attempts = phaseData[evt.phase];
    if (attempts) {
      const entry = attempts.find(a => a.attempt === evt.attempt);
      if (entry) entry.changes = evt.remediations || [];
    }
    if (selectedPhaseId === evt.phase) renderInspector();

  } else if (evt.type === 'autoloop_phase_complete') {
    phaseState[evt.phase]   = 'passed';
    phaseAttempt[evt.phase] = evt.attempts_used || evt.attempt || 1;
    renderTimeline();
    if (selectedPhaseId === evt.phase) renderInspector();

  } else if (evt.type === 'autoloop_escalation') {
    phaseState[evt.phase] = 'escalated';
    renderTimeline();
  }

  // Append to event log
  appendEventRow(evt);
}

function appendEventRow(evt) {
  const list = document.getElementById('event-list');
  if (list.querySelector('div[style]')) list.innerHTML = '';

  const tsRaw = evt.ts;
  let ts = '––';
  if (tsRaw) {
    const d = typeof tsRaw === 'number' ? new Date(tsRaw * 1000) : new Date(tsRaw);
    ts = isNaN(d.getTime()) ? '––' : d.toISOString().slice(11, 23);
  }

  let body = '';
  if (evt.type === 'autoloop_phase_start') {
    const paramCount = Object.keys(evt.params_summary || {}).length;
    body = `phase=${evt.phase}  attempt=${evt.attempt}  params=${paramCount}`;
  } else if (evt.type === 'autoloop_running') {
    body = evt.description || '';
  } else if (evt.type === 'autoloop_gate_results') {
    const haltCount = (evt.gates||[]).filter(g => g.action === 'halt').length;
    body = `passed=${evt.passed}  halts=${haltCount}  ` + (evt.gates||[]).map(g => `${g.gate}:${g.action}`).join('  ');
  } else if (evt.type === 'autoloop_update') {
    const changes = (evt.remediations||[]).flatMap(r =>
      Object.entries(r.param_changes||{}).map(([k,v]) => `${k}→${v}`)
    ).join(', ');
    body = `phase=${evt.phase} retry #${evt.next_attempt}  ${changes}`;
  } else if (evt.type === 'autoloop_phase_complete') {
    body = `phase=${evt.phase}  attempt=${evt.attempts_used || evt.attempt}  level=${evt.overall_level}`;
  } else if (evt.type === 'autoloop_escalation') {
    body = `phase=${evt.phase}  gates=[${(evt.gates_failed||[]).join(',')}]`;
  } else if (evt.type === 'autoloop_complete') {
    body = `passed=[${(evt.phases_passed||[]).join(',')}]  attempts=${evt.total_attempts}`;
  } else if (evt.type === 'run_complete') {
    body = JSON.stringify(evt.result);
  }

  const row = document.createElement('div');
  row.className = `event-row t-${evt.type}`;
  row.innerHTML =
    `<span class="ev-ts">${ts}</span>` +
    `<span class="ev-type">${evt.type}</span>` +
    `<span class="ev-body">${escapeHtml(body)}</span>`;

  // Citations on retry events
  const cits = (evt.remediations||[]).flatMap(r => (r.citations||[]).slice(0,2));
  if (cits.length) {
    const c = document.createElement('span');
    c.className = 'ev-cit';
    c.textContent = cits.map(x => `[${x.paper_ref}] ${x.finding}`).join(' · ');
    row.appendChild(c);
  }

  list.appendChild(row);
  list.scrollTop = list.scrollHeight;
  eventCount++;
  document.getElementById('event-count').textContent = `${eventCount} events`;
}

// ── Summary row ───────────────────────────────────────────────────────────────

function showSummary(result) {
  const row = document.getElementById('summary-row');
  row.style.display = 'flex';
  (result.phases_passed||[]).forEach(p => {
    const c = document.createElement('span');
    c.className = 'sum-chip badge-green'; c.textContent = `✓ ${p}`;
    row.appendChild(c);
  });
  (result.phases_escalated||[]).forEach(p => {
    const c = document.createElement('span');
    c.className = 'sum-chip badge-red'; c.textContent = `⚠ ${p}`;
    row.appendChild(c);
  });
  const s = document.createElement('span');
  s.className = 'sum-chip badge-gray';
  s.textContent = `${result.total_attempts} total attempts`;
  row.appendChild(s);
}

// ── Findings Report ───────────────────────────────────────────────────────────

async function fetchAndShowReport(runId) {
  try {
    const [summaryResp, auditResp] = await Promise.all([
      fetch(`/api/summary/${runId}`),
      fetch(`/api/audit/${runId}`),
    ]);
    const summaryText = await summaryResp.text();
    const auditLines  = await auditResp.json();

    // Build stats from audit lines
    const phaseFinals = auditLines.filter(l => l.event === 'phase_final');
    const passed      = phaseFinals.filter(l => l.outcome === 'pass').length;
    const escalated   = phaseFinals.filter(l => l.outcome === 'escalated').length;
    const totalAtts   = auditLines.filter(l => l.event === 'attempt').length;

    const body = document.getElementById('findings-body');
    let statsHtml = `<div class="findings-stats">
      <span class="stat-chip badge-green">${passed} phase${passed!==1?'s':''} passed</span>`;
    if (escalated) {
      statsHtml += `<span class="stat-chip badge-red">${escalated} escalated</span>`;
    }
    statsHtml += `<span class="stat-chip badge-gray">${totalAtts} total attempts</span>
                  <span class="stat-chip badge-gray">${auditLines.length} audit records</span>
                </div>`;

    body.innerHTML = statsHtml +
      `<div class="data-section-label" style="padding:0 0 6px">Summary Report</div>` +
      `<pre class="summary-pre" id="summary-pre">${escapeHtml(summaryText)}</pre>` +
      `<div class="dl-row">
         <button class="dl-btn" onclick="downloadFile('/api/summary/${runId}','summary.txt')">⬇ Summary TXT</button>
         <button class="dl-btn" onclick="downloadFile('/api/audit/${runId}','audit.jsonl')">⬇ Audit JSONL</button>
       </div>`;

    document.getElementById('findings-card').style.display = 'block';
  } catch(e) {
    document.getElementById('findings-body').innerHTML =
      `<div style="color:var(--danger);font-size:.78rem;padding:12px">Failed to load report: ${e.message}</div>`;
    document.getElementById('findings-card').style.display = 'block';
  }
}

function downloadFile(url, filename) {
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
}

// ── Utilities ─────────────────────────────────────────────────────────────────

function escapeHtml(s) {
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
</script>
</body>
</html>
"""


# ── HTTP handler ──────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def do_GET(self):
        if self.path in ('/', '/index.html'):
            self._send(200, 'text/html; charset=utf-8', HTML.encode())
        elif self.path.startswith('/api/events/'):
            self._stream_events(self.path.split('/api/events/')[-1])
        elif self.path.startswith('/api/audit/'):
            run_id = self.path.split('/api/audit/')[-1]
            if run_id not in _runs:
                self._send(404, 'text/plain', b'Run not found')
            else:
                data = json.dumps(_runs[run_id].get('audit_lines', [])).encode()
                self._send(200, 'application/json', data)
        elif self.path.startswith('/api/summary/'):
            run_id = self.path.split('/api/summary/')[-1]
            if run_id not in _runs:
                self._send(404, 'text/plain', b'Run not found')
            else:
                text = _runs[run_id].get('summary_text', '')
                self._send(200, 'text/plain; charset=utf-8', text.encode())
        else:
            self._send(404, 'text/plain', b'Not found')

    def do_POST(self):
        if self.path == '/api/run':
            length = int(self.headers.get('Content-Length', 0))
            config = json.loads(self.rfile.read(length))
            run_id = str(uuid.uuid4())[:8]
            _runs[run_id] = {
                'queue': queue.Queue(),
                'result': None,
                'done': False,
                'events': [],
                'audit_lines': [],
                'summary_text': '',
            }
            threading.Thread(target=_execute_run, args=(run_id, config), daemon=True).start()
            self._send(200, 'application/json', json.dumps({'run_id': run_id}).encode())
        else:
            self._send(404, 'text/plain', b'Not found')

    def _send(self, code, ctype, body):
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def _stream_events(self, run_id):
        if run_id not in _runs:
            self._send(404, 'text/plain', b'Run not found')
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        run = _runs[run_id]
        # Replay stored events first (for late connections).
        # Track whether run_complete was already sent so we can skip early exit
        # if the run finished between our snapshot and the done check.
        sent_run_complete = False
        for evt in list(run['events']):
            try:
                self.wfile.write(f"data: {json.dumps(evt)}\n\n".encode())
                self.wfile.flush()
                if evt.get('type') == 'run_complete':
                    sent_run_complete = True
            except Exception:
                return
        if sent_run_complete:
            return
        # Don't short-circuit on run['done'] here — there may be a run_complete
        # event still in the queue that wasn't captured in the replay snapshot
        # (race between append-to-events and done flag).
        q = run['queue']
        deadline = time.time() + 300
        while time.time() < deadline:
            try:
                evt = q.get(timeout=1.0)
                self.wfile.write(f"data: {json.dumps(evt)}\n\n".encode())
                self.wfile.flush()
                if evt.get('type') == 'run_complete':
                    break
            except queue.Empty:
                if run['done']:
                    break
                try:
                    self.wfile.write(b': keep-alive\n\n')
                    self.wfile.flush()
                except Exception:
                    break


if __name__ == '__main__':
    PORT = 7788
    server = ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
    print(f'\n  BioMate — CryoEM Auto-Loop Demo')
    print(f'  ────────────────────────────────')
    print(f'  http://localhost:{PORT}\n')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nStopped.')
