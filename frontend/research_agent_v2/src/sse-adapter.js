// sse-adapter.js — bridge between BioMate's SSE event shape and the
// Claude-Design event vocabulary the sandbox engine consumes.
//
// Two factories:
//   createMockBiomateStream(scenarioId) — synthesizes realistic BioMate
//     chat_progress events for the sandbox to play, without a live backend.
//     Used by index-live.html. SSE mocking in sandbox is allowed (user
//     direction 2026-05-18); production promotion requires real workflow E2E.
//
//   connectRealBiomateStream(invocationId) — opens an EventSource against
//     BioMate's existing /api/workflows/{invocationId}/events endpoint.
//     Drop-in replacement for the mock when wiring to a running backend.
//
// Both expose the SAME shape:
//   start(onEvent, opts?) → { close() }
// where `onEvent({kind, invocation_id, friendly_message, speaker, ts, technical})`
// is called for each BioMate chat_progress event.
//
// All times in ms. `speed` defaults to 1.0; pass 5 to fast-forward demos.

(function () {
  'use strict';

  // ── Speaker derivation (matches backend narrator's derive_speaker logic) ──
  function deriveSpeaker(kind) {
    if (kind.startsWith('workflow.qc_'))      return 'qc';
    if (kind.startsWith('workflow.autoloop')) return 'loop';
    if (kind.startsWith('workflow.'))         return 'wf';
    if (kind.startsWith('deepagent.'))        return 'agent';
    if (kind.startsWith('plan.'))             return 'plan';
    if (kind.startsWith('findings.'))         return 'find';
    return 'wf';
  }

  // ── Friendly text renderer (matches backend narrator's _TEMPLATES) ──
  function renderFriendly(kind, t) {
    t = t || {};
    switch (kind) {
      case 'workflow.submitted':  return 'Got it — starting your workflow now.';
      case 'workflow.queued':     return 'Your workflow is in the AWS Batch queue.';
      case 'workflow.running':    return 'Workflow is running.';
      case 'workflow.phase_started': {
        const name = t.phase_name || t.name || 'step';
        if (Number.isInteger(t.n) && Number.isInteger(t.of)) return `Step ${t.n}/${t.of}: ${name}…`;
        return `Step ${name}…`;
      }
      case 'workflow.phase_completed': {
        const name = t.phase_name || t.name || 'step';
        if (t.detail) return `${name} done — ${t.detail}.`;
        return `${name} done.`;
      }
      case 'workflow.phase_failed': {
        const name = t.phase_name || t.name || 'Step';
        if (t.reason) return `${name} failed — ${t.reason}.`;
        return `${name} failed. Looking into why…`;
      }
      case 'workflow.qc_gate_warning': {
        const m = t.metric || 'metric';
        if (t.value != null && t.threshold != null) return `QC flagged ${m} = ${t.value} (threshold ${t.threshold}).`;
        return `QC flagged ${m}.`;
      }
      case 'workflow.qc_gate_blocked':
        return t.metric ? `QC blocked on ${t.metric} — adjusting parameters.` : 'QC blocked — adjusting parameters.';
      case 'workflow.autoloop_started': {
        const c = t.changes || {};
        const keys = Object.keys(c);
        if (keys.length) {
          const pairs = keys.slice(0, 2).map(k => `${k}=${c[k]}`).join(', ');
          return `Trying again with ${pairs}.`;
        }
        return 'Trying again with adjusted parameters.';
      }
      case 'workflow.completed':
        if (Number.isInteger(t.steps_succeeded) && Number.isInteger(t.steps_total)) {
          return `Workflow finished. ${t.steps_succeeded}/${t.steps_total} steps succeeded.`;
        }
        return 'Workflow finished.';
      case 'workflow.failed':
        return t.reason ? `Workflow stopped — ${t.reason}. Looking into why…` : 'Workflow stopped. Looking into why…';
      case 'workflow.cancelled': return 'Workflow cancelled by you.';
      case 'workflow.paused':    return 'Workflow paused. Tap Resume when you\'re ready to continue.';
      case 'workflow.resumed':   return 'Resuming your workflow.';
      case 'workflow.pilot_started':       return t.sampled ? `Running a quick pilot on ${t.sampled} samples first.` : 'Running a quick pilot first.';
      case 'workflow.pilot_completed':     return t.qc_pass ? 'Pilot done. All QC gates passed.' : 'Pilot done — see the promotion card.';
      case 'workflow.pilot_failed_qc':     return 'Pilot stopped — QC gates triggered.';
      case 'workflow.pilot_promoted':      return 'Promoted to full run.';
      case 'deepagent.start':              return 'Looking into why your workflow failed…';
      case 'plan.shown':                   return 'Decomposed into sub-tasks.';
      case 'findings.generated':           return 'Findings are ready in the After-run report.';
      default:                             return `Workflow update: ${kind}.`;
    }
  }

  // ── Event factory ──
  function makeEvent(kind, invocation_id, technical) {
    return {
      kind,
      invocation_id,
      friendly_message: renderFriendly(kind, technical),
      speaker: deriveSpeaker(kind),
      ts: Date.now() / 1000,
      technical: technical || {},
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // SCENARIO TAPES — real BioMate event sequences for sandbox playback
  // ═══════════════════════════════════════════════════════════════════
  //
  // Each tape is a list of {delay_ms, event}. The mock stream emits each event
  // after `delay_ms` (modified by speed) since the previous event. Phases and
  // metric values are aligned with BioMate's real workflows:
  //   - drugscreen: id=12826 Predict ADMET Properties (AI) + autoloop;
  //                 thresholds from backend/experiments/admet_autoloop/params.py
  //   - cryoem:     id=12833 CryoSPARC Standard SPA; 5 phases A-E per
  //                 backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py
  //                 _CRYOSPARC_STEP_PHASES (lines 607-631).

  const TAPES = {

    // ──────────────────────────────────────────────────────────────────
    // DRUG SCREEN — happy auto-loop path:
    //   submit → plan → pilot → 2 QC fails → autoloop → re-pilot pass
    //   → comparison → full → findings
    // ──────────────────────────────────────────────────────────────────
    drugscreen: function (inv) {
      const e = (k, t) => makeEvent(k, inv, t);
      return [
        // Plan setup
        [200,   { ...e('workflow.submitted'),  technical: { workflow: 'Predict ADMET Properties (AI)' } }],
        [800,   { ...e('plan.shown'),          technical: { items: [
          { id: 'ingest',  title: 'Ingest compounds',         status: 'pending', est_s: 30 },
          { id: 'admet',   title: 'ADMET prediction',         status: 'pending', est_s: 300 },
          { id: 'herg',    title: 'hERG gate',                status: 'pending', est_s: 60 },
          { id: 'ames',    title: 'Ames + DILI gates',        status: 'pending', est_s: 60 },
          { id: 'rank',    title: 'Composite ranking',        status: 'pending', est_s: 30 },
        ] } }],

        // Pilot decision
        [600,   { ...e('deepagent.start'),     friendly_message: 'Heavy — worth a pilot first.', speaker: 'agent' }],
        [400,   { kind: '__showCard', card: 'pilotPrompt', data: {
          total: 10000, sampled: 500, fraction: 0.05,
          full_min: 45, pilot_min: 5,
        } }],
        [0,     { kind: '__await', label: 'pilot_started' }],

        // Pilot running
        [500,   { ...e('workflow.pilot_started'), technical: { sampled: 500 } }],
        [300,   { ...e('workflow.phase_started'),  technical: { phase_name: 'Ingest compounds', n: 1, of: 5 } }],
        [600,   { kind: '__planUpdate', id: 'ingest', status: 'running' }],
        [800,   { ...e('workflow.phase_completed'), technical: { phase_name: 'Ingest compounds' } }],
        [200,   { kind: '__planUpdate', id: 'ingest', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),  technical: { phase_name: 'ADMET prediction', n: 2, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'admet', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'ADMET prediction', detail: '500 compounds predicted' } }],
        [200,   { kind: '__planUpdate', id: 'admet', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),  technical: { phase_name: 'hERG gate', n: 3, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'herg', status: 'running' }],

        // hERG fails — 18% of 500 = 90 compounds over threshold
        [800,   { ...e('workflow.qc_gate_warning'), technical: { metric: 'hERG_fail_rate', value: 0.18, threshold: 0.10 } }],
        [600,   { ...e('workflow.qc_gate_blocked'), technical: { metric: 'hERG_fail_rate' } }],
        [200,   { kind: '__planUpdate', id: 'herg', status: 'warn' }],
        [200,   { kind: '__planUpdate', id: 'ames', status: 'warn' }],

        // Ames also flags
        [400,   { ...e('workflow.qc_gate_warning'), technical: { metric: 'Ames_fail_rate', value: 0.12, threshold: 0.08 } }],

        // Pilot promotion card with autoloop suggestion
        [500,   { kind: '__showCard', card: 'pilotPromotion', data: {
          result: 'fail',
          runtime: '4m 38s',
          sampled: 500,
          total: 10000,
          full_min: 45,
          qc: [
            { name: 'hERG_fail_rate',  status: 'fail', desc: 'fail-rate 0.18 > threshold 0.10' },
            { name: 'Ames_fail_rate',  status: 'fail', desc: 'fail-rate 0.12 > threshold 0.08' },
            { name: 'DILI_probability', status: 'pass', desc: 'all compounds below 0.5 threshold' },
          ],
          suggestion: {
            text: 'Tighten chemical space to prune systematic hERG / Ames offenders.',
            changes: [['logp_max', 5.5, 4.5], ['mw_max_da', 600, 480]],
          },
        } }],
        [0,     { kind: '__await', label: 'apply_fixes' }],

        // Auto-loop applies + re-pilot
        [500,   { ...e('workflow.autoloop_started'), technical: { changes: { logp_max: 4.5, mw_max_da: 480 } } }],
        [800,   { ...e('workflow.pilot_started'), technical: { sampled: 500, iteration: 2 } }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'ADMET prediction', detail: 'rerun on tightened space' } }],
        [800,   { kind: '__planUpdate', id: 'herg', status: 'done' }],
        [400,   { kind: '__planUpdate', id: 'ames', status: 'done' }],
        [400,   { ...e('workflow.pilot_completed'), technical: { qc_pass: true } }],

        // Run-vs-Run comparison card
        [600,   { kind: '__showCard', card: 'comparison', data: {
          runA: { label: 'Pilot Run A', sub: 'logp_max=5.5 · mw_max=600' },
          runB: { label: 'Pilot Run B', sub: 'logp_max=4.5 · mw_max=480' },
          metrics: [
            { name: 'hERG fail-rate',   a: '18%',   b: '4%',    delta: '−14%', dir: 'up',  aQc: 'fail', bQc: 'pass' },
            { name: 'Ames fail-rate',   a: '12%',   b: '3%',    delta: '−9%',  dir: 'up',  aQc: 'fail', bQc: 'pass' },
            { name: 'Candidate count',  a: '410',   b: '478',   delta: '+17%', dir: 'up' },
            { name: 'Runtime',          a: '4m 38s', b: '5m 02s', delta: '+5%', dir: 'neu' },
          ],
          params: [
            { name: 'logp_max',  a: '5.5', b: '4.5', origin: 'autoloop' },
            { name: 'mw_max_da', a: '600', b: '480', origin: 'autoloop' },
          ],
          recommendation: {
            preferred: 'B', confidence: 'high',
            reason: 'Both QC gates pass on Run B with similar runtime and a larger candidate set.',
            pvalue: 0.008, test: 'Fisher exact, hERG fail-rate',
          },
        } }],
        [0,     { kind: '__startCountdown', label: 'compare_use_b_auto', seconds: 10 }],
        [0,     { kind: '__await', label: 'compare_decision' }],

        // Full run
        [400,   { ...e('workflow.autoloop_started'), technical: { changes: { compounds: 10000 }, detail: 'full library' } }],
        [200,   { kind: '__planUpdate', id: 'rank', status: 'running' }],
        [2000,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Composite ranking', detail: '47 BBB-penetrant candidates' } }],
        [200,   { kind: '__planUpdate', id: 'rank', status: 'done' }],
        [400,   { ...e('workflow.completed'), technical: { steps_succeeded: 5, steps_total: 5 } }],
        [400,   { kind: '__showCard', card: 'findings', data: {
          title: '47 BBB-penetrant candidates',
          runtime: '38m 12s',
          samples: 10000,
          rows: [
            ['Compounds passing all gates', '47'],
            ['hERG pass-rate',               '96%'],
            ['Ames pass-rate',               '97%'],
            ['Mean composite score',         '0.82'],
          ],
        } }],
      ];
    },

    // ──────────────────────────────────────────────────────────────────
    // CRYO-EM — 5 phases A-E with CTF gate trip in Phase A.
    // Phase names match _CRYOSPARC_STEP_PHASES exactly.
    // ──────────────────────────────────────────────────────────────────
    cryoem: function (inv) {
      const e = (k, t) => makeEvent(k, inv, t);
      return [
        [200,   { ...e('workflow.submitted'), technical: { workflow: 'CryoSPARC Standard SPA', dataset: 'EMPIAR-10025' } }],
        [800,   { ...e('plan.shown'),         technical: { items: [
          { id: 'A', title: 'Phase A — Motion Correction & CTF',     status: 'pending', est_s: 360 },
          { id: 'B', title: 'Phase B — Particle Picking',            status: 'pending', est_s: 480 },
          { id: 'C', title: 'Phase C — 2D Classification',           status: 'pending', est_s: 420 },
          { id: 'D', title: 'Phase D — 3D Reconstruction',           status: 'pending', est_s: 1200 },
          { id: 'E', title: 'Phase E — Validation & Post-processing', status: 'pending', est_s: 480 },
        ] } }],

        [500,   { ...e('workflow.phase_started'), technical: { phase_name: 'Phase A — Motion Correction & CTF', n: 1, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'A', status: 'running' }],
        [1200,  { ...e('workflow.qc_gate_warning'), technical: { metric: 'CTF_fit_resolution_max', value: 4.2, threshold: 3.5 } }],
        [600,   { ...e('workflow.qc_gate_blocked'), technical: { metric: 'CTF_fit_resolution_max' } }],
        [200,   { kind: '__planUpdate', id: 'A', status: 'warn' }],
        [0,     { kind: '__await', label: 'apply_fixes' }],

        [500,   { ...e('workflow.autoloop_started'), technical: { changes: { defocus_search_min: 0.5, defocus_search_max: 4.0 } } }],
        [1200,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Phase A — Motion Correction & CTF', detail: 'CTF gate cleared at 3.1 Å' } }],
        [200,   { kind: '__planUpdate', id: 'A', status: 'done' }],

        [400,   { ...e('workflow.phase_started'), technical: { phase_name: 'Phase B — Particle Picking', n: 2, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'B', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Phase B — Particle Picking', detail: '124,830 particles' } }],
        [200,   { kind: '__planUpdate', id: 'B', status: 'done' }],

        [400,   { ...e('workflow.phase_started'), technical: { phase_name: 'Phase C — 2D Classification', n: 3, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'C', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Phase C — 2D Classification', detail: '78,412 particles after select' } }],
        [200,   { kind: '__planUpdate', id: 'C', status: 'done' }],

        [400,   { ...e('workflow.phase_started'), technical: { phase_name: 'Phase D — 3D Reconstruction', n: 4, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'D', status: 'running' }],
        [2000,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Phase D — 3D Reconstruction', detail: '3.4 Å unsharpened' } }],
        [200,   { kind: '__planUpdate', id: 'D', status: 'done' }],

        [400,   { ...e('workflow.phase_started'), technical: { phase_name: 'Phase E — Validation & Post-processing', n: 5, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'E', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Phase E — Validation & Post-processing', detail: '3.1 Å GSFSC 0.143' } }],
        [200,   { kind: '__planUpdate', id: 'E', status: 'done' }],

        [400,   { ...e('workflow.completed'), technical: { steps_succeeded: 23, steps_total: 23 } }],
        [400,   { kind: '__showCard', card: 'findings', data: {
          title: '3.1 Å reconstruction · publication-ready',
          runtime: '52m 07s',
          samples: 23,
          rows: [
            ['Final resolution (GSFSC 0.143)', '3.1 Å'],
            ['Particles in final reconstruction', '78,412'],
            ['B-factor (sharpening)', '−85 Å²'],
            ['Map symmetry', 'C1'],
            ['EMDB deposition ready', 'yes'],
          ],
        } }],
      ];
    },

    // ──────────────────────────────────────────────────────────────────
    // BULK RNA-SEQ — nf-core/rnaseq happy path; 5 phases, no QC trip.
    //   submit → plan → fastqc → STAR → quant → DE → enrichment → findings
    // ──────────────────────────────────────────────────────────────────
    rnaseq: function (inv) {
      const e = (k, t) => makeEvent(k, inv, t);
      return [
        [200,   { ...e('workflow.submitted'),  technical: { workflow: 'nf-core/rnaseq', dataset: '12 samples · GRCh38' } }],
        [800,   { ...e('plan.shown'),          technical: { items: [
          { id: 'qc',      title: 'FastQC + trimming',         status: 'pending', est_s: 180 },
          { id: 'align',   title: 'STAR alignment',            status: 'pending', est_s: 1200 },
          { id: 'quant',   title: 'Salmon quantification',     status: 'pending', est_s: 420 },
          { id: 'de',      title: 'DESeq2 differential expr',  status: 'pending', est_s: 120 },
          { id: 'enrich',  title: 'GO + pathway enrichment',   status: 'pending', est_s: 60 },
        ] } }],

        [400,   { ...e('workflow.running') }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'FastQC + trimming', n: 1, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'qc', status: 'running' }],
        [1200,  { ...e('workflow.phase_completed'), technical: { phase_name: 'FastQC + trimming', detail: '12 samples · mean Q33' } }],
        [200,   { kind: '__planUpdate', id: 'qc', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'STAR alignment', n: 2, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'align', status: 'running' }],
        [2000,  { ...e('workflow.phase_completed'), technical: { phase_name: 'STAR alignment', detail: 'uniquely mapped 91.4%' } }],
        [200,   { kind: '__planUpdate', id: 'align', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'Salmon quantification', n: 3, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'quant', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Salmon quantification', detail: '60,498 transcripts quantified' } }],
        [200,   { kind: '__planUpdate', id: 'quant', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'DESeq2 differential expr', n: 4, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'de', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'DESeq2', detail: '1,847 DEGs at padj<0.05' } }],
        [200,   { kind: '__planUpdate', id: 'de', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'GO + pathway enrichment', n: 5, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'enrich', status: 'running' }],
        [1200,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Enrichment', detail: '23 pathways at FDR<0.05' } }],
        [200,   { kind: '__planUpdate', id: 'enrich', status: 'done' }],

        [400,   { ...e('workflow.completed'),       technical: { steps_succeeded: 5, steps_total: 5 } }],
        [400,   { kind: '__showCard', card: 'findings', data: {
          title: '1,847 DEGs · 23 enriched pathways',
          runtime: '34m 18s',
          samples: 12,
          rows: [
            ['Differentially expressed genes (padj<0.05)', '1,847'],
            ['Upregulated / downregulated',                '982 / 865'],
            ['Top GO term',                                'inflammatory response (FDR 1.2e-12)'],
            ['Top KEGG pathway',                           'TNF signaling (FDR 4.8e-09)'],
            ['Mean unique alignment rate',                 '91.4%'],
          ],
        } }],
      ];
    },

    // ──────────────────────────────────────────────────────────────────
    // VARIANT CALLING — nf-core/sarek; 5 phases with one QC warning
    // (low mapping rate flagged advisory, not blocking).
    // ──────────────────────────────────────────────────────────────────
    variant: function (inv) {
      const e = (k, t) => makeEvent(k, inv, t);
      return [
        [200,   { ...e('workflow.submitted'),  technical: { workflow: 'nf-core/sarek', dataset: 'SRR123456 · GRCh38' } }],
        [800,   { ...e('plan.shown'),          technical: { items: [
          { id: 'prep',    title: 'Reference indexing',        status: 'pending', est_s: 240 },
          { id: 'align',   title: 'BWA-MEM2 alignment',        status: 'pending', est_s: 1800 },
          { id: 'recal',   title: 'BQSR recalibration',        status: 'pending', est_s: 600 },
          { id: 'call',    title: 'HaplotypeCaller',           status: 'pending', est_s: 1200 },
          { id: 'vqsr',    title: 'VQSR + annotation',         status: 'pending', est_s: 360 },
        ] } }],

        [400,   { ...e('workflow.running') }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'Reference indexing', n: 1, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'prep', status: 'running' }],
        [1200,  { ...e('workflow.phase_completed'), technical: { phase_name: 'Reference indexing', detail: 'GRCh38 .fai + .bwt2 cached' } }],
        [200,   { kind: '__planUpdate', id: 'prep', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'BWA-MEM2 alignment', n: 2, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'align', status: 'running' }],

        // Advisory QC warning (not blocking)
        [1200,  { ...e('workflow.qc_gate_warning'), technical: { metric: 'mapping_rate', value: 0.948, threshold: 0.95, severity: 'advisory' } }],
        [200,   { kind: '__planUpdate', id: 'align', status: 'warn' }],
        [800,   { ...e('workflow.phase_completed'), technical: { phase_name: 'BWA-MEM2 alignment', detail: '94.8% mapped (advisory)' } }],
        [200,   { kind: '__planUpdate', id: 'align', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'BQSR recalibration', n: 3, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'recal', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'BQSR', detail: 'recal table applied' } }],
        [200,   { kind: '__planUpdate', id: 'recal', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'HaplotypeCaller', n: 4, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'call', status: 'running' }],
        [2000,  { ...e('workflow.phase_completed'), technical: { phase_name: 'HaplotypeCaller', detail: '4.21M raw variants' } }],
        [200,   { kind: '__planUpdate', id: 'call', status: 'done' }],

        [400,   { ...e('workflow.phase_started'),   technical: { phase_name: 'VQSR + annotation', n: 5, of: 5 } }],
        [200,   { kind: '__planUpdate', id: 'vqsr', status: 'running' }],
        [1500,  { ...e('workflow.phase_completed'), technical: { phase_name: 'VQSR', detail: '3.84M PASS · ts/tv 2.04' } }],
        [200,   { kind: '__planUpdate', id: 'vqsr', status: 'done' }],

        [400,   { ...e('workflow.completed'),       technical: { steps_succeeded: 5, steps_total: 5 } }],
        [400,   { kind: '__showCard', card: 'findings', data: {
          title: '3.84M PASS variants · ts/tv 2.04',
          runtime: '1h 12m',
          samples: 1,
          rows: [
            ['Raw variants called',           '4,213,902'],
            ['VQSR PASS',                     '3,841,267'],
            ['Transition/transversion ratio', '2.04 (expected ~2.0–2.1)'],
            ['Mean coverage',                 '37×'],
            ['Mapping rate',                  '94.8% (advisory: below 95%)'],
            ['Annotated (VEP)',               'yes · gnomAD AF + ClinVar'],
          ],
        } }],
      ];
    },

  };

  // ── Mock stream: walks a tape with setTimeout, calls onEvent for each ──
  function createMockBiomateStream(scenarioId, invocationId) {
    invocationId = invocationId || ('mock-' + scenarioId + '-' + Date.now());
    const builder = TAPES[scenarioId];
    if (!builder) throw new Error('Unknown scenarioId: ' + scenarioId);
    const tape = builder(invocationId);

    let timer = null;
    let closed = false;

    function start(onEvent, opts) {
      // speed: higher = faster. speed=2 → delays halved. speed=0.5 → delays doubled.
      const speed = Math.max(0.01, (opts && opts.speed) || 1.0);
      let i = 0;
      function next() {
        if (closed || i >= tape.length) return;
        const [delayMs, event] = tape[i++];
        timer = setTimeout(() => {
          if (closed) return;
          try { onEvent(event); } catch (e) { console.warn('[mock-sse] onEvent threw:', e); }
          next();
        }, Math.max(0, delayMs / speed));
      }
      next();
      return { close: () => { closed = true; if (timer) clearTimeout(timer); } };
    }

    return { start, invocationId, expectedEventCount: tape.length };
  }

  // ── Real stream: opens an EventSource against BioMate's chat_progress SSE ──
  function connectRealBiomateStream(invocationId, opts) {
    opts = opts || {};
    const url = (opts.baseUrl || '') + '/api/workflows/' + encodeURIComponent(invocationId) + '/events';

    function start(onEvent) {
      const es = new EventSource(url, { withCredentials: true });
      es.addEventListener('chat_progress', function (msg) {
        try {
          const data = JSON.parse(msg.data);
          onEvent(data);
        } catch (e) {
          console.warn('[real-sse] bad payload:', e);
        }
      });
      es.addEventListener('error', function (e) {
        console.warn('[real-sse] error event', e);
      });
      return { close: () => es.close() };
    }

    return { start, invocationId };
  }

  // ── Expose globally for inline-Babel script tags ──
  window.SseAdapter = {
    deriveSpeaker,
    renderFriendly,
    makeEvent,
    createMockBiomateStream,
    connectRealBiomateStream,
    TAPES,        // exposed for inspection / tests
  };
})();
