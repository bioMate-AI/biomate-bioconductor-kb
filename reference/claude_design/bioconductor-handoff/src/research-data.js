// Research-Agent UI — scenario event tapes.
// Each scenario is a sequence of typed events. The engine in ResearchApp.jsx
// walks the tape, applying state changes and waiting either for the
// declared delay (event.t) or for the matching user-action `await` label.
//
// All `t` values are ms — they're multiplied by the tweak speed factor at
// playback time. Use 0 for "immediately after previous event".
//
// Event kinds (all optional fields documented inline):
//   { kind: 'chatLine', s, m, k?, ts? }       — append a speaker-pilled chat line
//   { kind: 'collapseLines', count }           — fold the previous N same-speaker lines into a caret
//   { kind: 'planShow', items }                — display the plan checklist
//   { kind: 'planUpdate', id, status, meta? }  — change one plan-item's status
//   { kind: 'planLock' }                       — leave edit mode (the auto-lock fires)
//   { kind: 'planFail', id, reason }           — mark item failed + show inline failure block
//   { kind: 'planUnfail', id, status }         — collapse failure block back into a status
//   { kind: 'showCard', card, data }           — push a chat card (pilot/comparison/findings)
//   { kind: 'phaseUpdate', id, status }        — recolour a phase card in the panel
//   { kind: 'runState', value }                — flip the panel-level run state
//   { kind: 'showPilotToggle' } | 'hidePilotToggle'
//   { kind: 'showFindings' }
//   { kind: 'await', label }                   — pause; resumes when user fires action `label`
//   { kind: 'startCountdown', label, seconds } — kick off a real countdown that fires `label`

// ─────────────────────────────────────────────────────────────────
// Speaker codes: 'plan' | 'wf' | 'qc' | 'qc-err' | 'loop' | 'agent' | 'find'
// ─────────────────────────────────────────────────────────────────

const SCEN_RNASEQ = {
  id: 'rnaseq',
  name: 'Bulk RNA-seq · happy path',
  oneLiner: 'Decompose → pilot → QC pass → promote → full → done',
  domain: 'Bulk RNA-seq',
  user: 'Kira M.',
  query: 'Run differential expression on 120 bulk RNA-seq samples (control vs treated), human GRCh38. Include pathway + GO enrichment.',
  // cost: { full_usd: 8.20, full_min: 45, pilot_usd: 0.47, pilot_min: 5 }, // cost commented out, leaving for future work
  cost: { full_min: 45, pilot_min: 5 },
  pilot: { total: 120, sampled: 12, fraction: 0.10, strategy: 'random' },

  initialPlan: [
    { id: 'qc',      title: 'Quality control on FASTQ files',  est_s: 60,  status: 'pending' },
    { id: 'star',    title: 'STAR alignment',                  est_s: 600, status: 'pending' },
    { id: 'de',      title: 'Differential expression analysis',est_s: 240, status: 'pending' },
    { id: 'path',    title: 'Pathway enrichment',              est_s: 180, status: 'pending', parallel: 'p1' },
    { id: 'go',      title: 'GO term annotation',              est_s: 180, status: 'pending', parallel: 'p1' },
  ],

  phases: [
    { id: 'A', name: 'Quality control',           summary: 'FastQC + adapter trim',                     status: 'pending' },
    { id: 'B', name: 'Alignment',                 summary: 'STAR + index + read-counts',                status: 'pending' },
    { id: 'C', name: 'Differential expression',   summary: 'DESeq2 control vs treated',                 status: 'pending' },
    { id: 'D', name: 'Enrichment',                summary: 'Pathway + GO term (parallel)',              status: 'pending' },
  ],

  tape: [
    // ── Scene 0: plan appears, pilot offered ──────────────────────
    { t: 200,  kind: 'planShow' },
    { t: 600,  kind: 'chatLine', s: 'plan', m: 'Decomposed your request into 5 sub-tasks.' },
    { t: 800,  kind: 'chatLine', s: 'plan', m: 'Pathway and GO enrichment can run in parallel — grouped them.' },
    { t: 700,  kind: 'chatLine', s: 'agent', m: 'Heavy enough for a quick pilot first — worth validating QC before the full run.' },
    { t: 200,  kind: 'showCard', card: 'pilotPrompt' },
    { t: 0,    kind: 'await', label: 'pilot_started' },

    // ── Scene 1: pilot runs ───────────────────────────────────────
    { t: 0,    kind: 'chatLine', s: 'wf', m: 'Running a pilot on 12 of 120 samples first.' },
    { t: 700,  kind: 'planUpdate', id: 'qc', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Step 1/5: FastQC on the 12 pilot samples…' },
    { t: 900,  kind: 'chatLine', s: 'wf', m: 'Submitted to AWS Batch · job 8f3e21…' },
    { t: 800,  kind: 'chatLine', s: 'wf', m: 'Container pulled (8s).' },
    { t: 0,    kind: 'collapseLines', count: 2 },
    { t: 1200, kind: 'planUpdate', id: 'qc', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'FastQC — all 12 samples passed adapter + quality checks.' },
    { t: 800,  kind: 'planUpdate', id: 'star', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Step 2/5: STAR alignment…', rationaleId: 'rnaseq:B' },
    { t: 1400, kind: 'planUpdate', id: 'star', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'Alignment — mean 97.2% mapped, all samples ≥95%.' },
    { t: 500,  kind: 'chatLine', s: 'qc', m: 'Strand — auto-detected reverse (confidence 0.99).' },
    { t: 600,  kind: 'chatLine', s: 'wf', m: 'Pilot done. All QC passed.' },
    { t: 200,  kind: 'showCard', card: 'pilotPromotion', data: {
        result: 'pass',
        runtime: '4m 38s', /* cost: '$0.47', */ sampled: 12, total: 120,
        full_min: 45, /* full_cost: 8.20, */
        qc: [
          { name: 'FastQC',     status: 'pass', desc: 'all 12 samples passed' },
          { name: 'Alignment',  status: 'pass', desc: '≥95% mapped (mean 97.2%)' },
          { name: 'Strand',     status: 'pass', desc: 'auto-detected reverse, confidence 0.99' },
        ],
    }},
    { t: 0,    kind: 'startCountdown', label: 'pilot_promote_auto', seconds: 10 },
    { t: 0,    kind: 'await', label: 'promote_or_stop' },

    // ── Scene 2: full run ─────────────────────────────────────────
    { t: 0,    kind: 'dismissCard', card: 'pilotPrompt' },
    { t: 0,    kind: 'dismissCard', card: 'pilotPromotion' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: 'Promoted to full run on 120 samples.' },
    { t: 600,  kind: 'planUpdate', id: 'qc',   status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'star', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'de',   status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 100,  kind: 'chatLine', s: 'wf', m: 'Step 3/5: DESeq2 differential expression…', rationaleId: 'rnaseq:C' },
    { t: 1800, kind: 'planUpdate', id: 'de', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0,    kind: 'chatLine', s: 'find', m: 'Found 1,284 DE genes at FDR < 0.05 (812 up, 472 down).' },
    { t: 500,  kind: 'planUpdate', id: 'path', status: 'running' },
    { t: 0,    kind: 'planUpdate', id: 'go',   status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Steps 4/5 + 5/5: pathway and GO running in parallel.' },
    { t: 1600, kind: 'planUpdate', id: 'path', status: 'done' },
    { t: 200,  kind: 'planUpdate', id: 'go',   status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'chatLine', s: 'find', m: 'Top pathway: TNF signalling (NES = 2.31, p_adj = 1.4e-4).' },
    { t: 600,  kind: 'chatLine', s: 'plan', m: 'Plan finished — 5 of 5 succeeded.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
        title: '1,284 DE genes · TNF signalling on top',
        runtime: '38m 12s', /* cost: '$7.94', */ samples: 120,
        rows: [
          ['DE genes (FDR < 0.05)', '1,284  ↑812 ↓472'],
          ['Top pathway (GSEA)',    'TNF signalling — NES 2.31'],
          ['Top GO term',           'inflammatory response (BP)'],
          ['Methods report',        'methods_2026-05-17.md'],
        ],
    }},
  ],
};


const SCEN_DRUGSCREEN = {
  id: 'drugscreen',
  name: 'Drug screen · auto-loop comparison',
  oneLiner: 'Pilot fails QC → auto-loop fixes params → Run-A vs Run-B compare',
  domain: 'ADMET / drug screen',
  user: 'Kira M.',
  query: 'Screen a 10k-compound library for blood-brain barrier penetrants. Filter on hERG and Ames; rank by predicted logBB.',
  // cost: { full_usd: 12.40, full_min: 62, pilot_usd: 0.41, pilot_min: 4 }, // cost commented out, leaving for future work
  cost: { full_min: 62, pilot_min: 4 },
  pilot: { total: 10000, sampled: 500, fraction: 0.05, strategy: 'random' },

  initialPlan: [
    { id: 'ingest', title: 'Ingest compound library + standardize SMILES', est_s: 90,  status: 'pending' },
    { id: 'admet',  title: 'ADMET property prediction',                    est_s: 1800, status: 'pending' },
    { id: 'hergQ',  title: 'hERG liability gate',                          est_s: 90,  status: 'pending' },
    { id: 'amesQ',  title: 'Ames mutagenicity gate',                       est_s: 90,  status: 'pending' },
    { id: 'rank',   title: 'Rank by predicted logBB',                      est_s: 60,  status: 'pending' },
  ],

  phases: [
    { id: 'A', name: 'Library ingest',        summary: 'SMILES normalize + dedupe',           status: 'pending' },
    { id: 'B', name: 'ADMET prediction',      summary: 'Multi-property MPNN ensemble',         status: 'pending' },
    { id: 'C', name: 'QC gates',              summary: 'hERG · Ames · logP',                   status: 'pending' },
    { id: 'D', name: 'Ranking + report',      summary: 'logBB ranker · cards',                 status: 'pending' },
  ],

  tape: [
    { t: 200,  kind: 'planShow' },
    { t: 600,  kind: 'chatLine', s: 'plan', m: 'Decomposed your request into 5 sub-tasks.' },
    { t: 700,  kind: 'chatLine', s: 'agent', m: '10k compounds is heavy — start with a 5% pilot to size the QC gates.' },
    { kind: 'marker', id: 'plan_visible' },
    { t: 200,  kind: 'showCard', card: 'pilotPrompt' },
    { kind: 'marker', id: 'pilot_prompt' },
    { t: 0,    kind: 'await', label: 'pilot_started' },

    // Pilot run — fails QC
    { t: 0,    kind: 'dismissCard', card: 'pilotPrompt' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: 'Running pilot on 500 of 10,000 compounds.' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 600,  kind: 'planUpdate', id: 'ingest', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 1200, kind: 'planUpdate', id: 'ingest', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'admet', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { kind: 'marker', id: 'pilot_running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'ADMET prediction on 500 compounds…', rationaleId: 'drugscreen:B' },
    { t: 1800, kind: 'planUpdate', id: 'admet', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'hergQ', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 1000, kind: 'planUpdate', id: 'hergQ', status: 'warn', meta: { reason: 'hERG = 0.62 (threshold 0.5)' }},
    { t: 200,  kind: 'chatLine', s: 'qc', k: 'qc-err', m: '⚠ QC flagged hERG = 0.62 (threshold 0.5).' },
    { t: 600,  kind: 'planUpdate', id: 'amesQ', status: 'warn', meta: { reason: 'Ames positive' }},
    { t: 0,    kind: 'chatLine', s: 'qc', k: 'qc-err', m: '⚠ QC flagged Ames — positive.' },
    { kind: 'marker', id: 'qc_failed' },
    { t: 500,  kind: 'chatLine', s: 'wf', m: 'Pilot stopped — 2 QC gates triggered.' },
    { t: 300,  kind: 'showCard', card: 'pilotPromotion', data: {
        result: 'fail',
        runtime: '4m 12s', /* cost: '$0.41', */ sampled: 500, total: 10000,
        qc: [
          { name: 'hERG',  status: 'fail', desc: 'hit rate 0.62, threshold 0.5' },
          { name: 'Ames',  status: 'fail', desc: 'positive — 31 hits' },
          { name: 'logP',  status: 'pass', desc: 'mean 4.1, within range' },
        ],
        suggestion: {
          text: 'Auto-loop suggests',
          changes: [['logp_max', '5.5', '4.5'], ['mw_max', '550', '480']],
        },
    }},
    { kind: 'marker', id: 'pilot_promotion_shown' },
    { t: 0,    kind: 'await', label: 'apply_fixes' },

    // Auto-loop run
    { t: 0,    kind: 'dismissCard', card: 'pilotPromotion' },
    { t: 0,    kind: 'chatLine', s: 'loop', m: 'Trying again with logp_max=4.5, mw_max=480.' },
    { t: 600,  kind: 'planUpdate', id: 'hergQ', status: 'running' },
    { t: 0,    kind: 'planUpdate', id: 'amesQ', status: 'pending' },
    { kind: 'marker', id: 'autoloop_running' },
    { t: 1500, kind: 'planUpdate', id: 'hergQ', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'amesQ', status: 'running' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'hERG now 0.38 ✓ (was 0.62).' },
    { t: 1300, kind: 'planUpdate', id: 'amesQ', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'Ames now negative ✓ (was positive).' },
    { t: 400,  kind: 'chatLine', s: 'loop', m: 'Both QC gates pass after fix.' },
    { t: 500,  kind: 'chatLine', s: 'wf', m: 'Two pilots done — comparing.' },
    { t: 300,  kind: 'showCard', card: 'comparison', data: {
        runA: { label: 'Run A', sub: 'original params' },
        runB: { label: 'Run B', sub: 'after auto-loop fix' },
        metrics: [          { name: 'Peak memory', a: '31 GB',   b: '29 GB',   delta: '−6%',  dir: 'up' },
          { name: 'hERG',        a: '0.62',    b: '0.38',    delta: '−0.24',dir: 'up',  aQc: 'fail', bQc: 'pass' },
          { name: 'Ames',        a: 'positive',b: 'negative',delta: 'fixed',dir: 'up',  aQc: 'fail', bQc: 'pass' },
          { name: 'logP (mean)', a: '4.1',     b: '3.2',     delta: '−0.9', dir: 'neu' },
        ],
        params: [
          { name: 'logp_max', a: '5.5', b: '4.5', origin: 'autoloop' },
          { name: 'mw_max',   a: '550', b: '480', origin: 'autoloop' },
          { name: 'model_seed', a: '42', b: '123', origin: 'user' },
        ],
        recommendation: {
          preferred: 'B',
          confidence: 'high',
          reason: 'Run B passes all 3 QC gates with similar resource cost.',
          pvalue: '< 0.01',
          test: 'hERG distribution shift',
          autoProceed: true,
        },
    }},
    { kind: 'marker', id: 'comparison_shown' },
    { t: 0,    kind: 'startCountdown', label: 'compare_use_b_auto', seconds: 10 },
    { t: 0,    kind: 'await', label: 'compare_decision' },

    // Full run on Run B params
    { t: 0,    kind: 'dismissCard', card: 'comparison' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: 'Using Run B params · full screen on 10k compounds.' },
    { t: 800,  kind: 'planUpdate', id: 'ingest', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'admet', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { kind: 'marker', id: 'fullrun_running' },
    { t: 2400, kind: 'planUpdate', id: 'admet', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'hergQ', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'amesQ', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'rank', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 1500, kind: 'planUpdate', id: 'rank', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'chatLine', s: 'find', m: '47 BBB-penetrant candidates after all QC gates.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
        title: '47 BBB-penetrant candidates',
        runtime: '58m 04s', /* cost: '$11.80', */ samples: 10000,
        rows: [
          ['Final candidates',     '47'],
          ['Mean predicted logBB', '0.41 ± 0.18'],
          ['QC pass-rate',         '99.2%  (53 dropped)'],
          ['Methods report',       'methods_2026-05-17.md'],
        ],
    }},
    { kind: 'marker', id: 'findings_shown' },
  ],
};


const SCEN_VARIANT = {
  id: 'variant',
  name: 'Variant calling · nested plan + failure',
  oneLiner: 'Edit plan → nested steps → one fails → retry → done',
  domain: 'Germline variants',
  user: 'Kira M.',
  query: 'Call germline variants on SRR123456 (human GRCh38) using GATK4. Include reference indexing if needed.',
  // cost: { full_usd: 3.20, full_min: 28, pilot_usd: 0, pilot_min: 0 }, // cost commented out, leaving for future work
  cost: { full_min: 28, pilot_min: 0 },
  pilot: null,

  // Plan items mirror the panel's phases 1-to-1 — consistent with the
  // other scenarios (rnaseq, drugscreen, cryosparc, etc.) where plan
  // checklist items are phase-level, not step-level. Step detail still
  // lives in the workflow panel's phase cards.
  initialPlan: [
    { id: 'align', title: 'Reference + alignment',  status: 'pending', est_s: 780 },
    { id: 'call',  title: 'Variant calling',        status: 'pending', est_s: 960 },
    { id: 'annot', title: 'Variant annotation',     status: 'pending', est_s: 180 },
  ],

  phases: [
    { id: 'A', name: 'Reference + alignment', summary: 'Indexing + BWA-MEM',         status: 'pending' },
    { id: 'B', name: 'Variant calling',       summary: 'HaplotypeCaller + VQSR',     status: 'pending' },
    { id: 'C', name: 'Annotation',            summary: 'VEP + ClinVar',              status: 'pending' },
  ],

  tape: [
    { t: 200,  kind: 'planShow', editing: true },
    { t: 600,  kind: 'chatLine', s: 'plan', m: 'Decomposed your request into 4 main steps (3 inside variant calling).' },
    { t: 700,  kind: 'chatLine', s: 'plan', m: 'Edit the plan if you want; locking automatically in 10s.' },
    { t: 0,    kind: 'startCountdown', label: 'plan_auto_lock', seconds: 10 },
    { t: 0,    kind: 'await', label: 'plan_locked' },

    { t: 0,    kind: 'planLock' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: 'Got it — starting the workflow.' },
    { t: 600,  kind: 'planUpdate', id: 'align', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 1400, kind: 'chatLine', s: 'wf', m: 'Reference index ready (cached: bwa-mem2 GRCh38).' },
    { t: 1500, kind: 'planUpdate', id: 'align', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'BWA-MEM — 99.1% mapped, duplicate rate 12%.' },
    { t: 200,  kind: 'planUpdate', id: 'call', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 1300, kind: 'planFail', id: 'call', reason: 'HaplotypeCaller died — chromosome 17 contig mismatch with GRCh38 build hg38-d1.' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'failed' },
    { t: 0,    kind: 'chatLine', s: 'qc', k: 'qc-err', m: '✕ GATK HaplotypeCaller failed (chr17 contig mismatch).' },
    { t: 300,  kind: 'chatLine', s: 'agent', m: 'Investigating — looks like a reference build conflict, not a data issue.' },
    { t: 700,  kind: 'chatLine', s: 'agent', m: 'Suggested fix: re-index with hg38-noalt; chr17_KI270857v1 is the culprit.' },
    { t: 0,    kind: 'await', label: 'retry_or_skip' },

    // Retry path
    { t: 0,    kind: 'planUnfail', id: 'call', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 0,    kind: 'chatLine', s: 'loop', m: 'Re-running with hg38-noalt reference.' },
    { t: 1800, kind: 'chatLine', s: 'wf', m: 'HaplotypeCaller — 4.21M raw variants called.', rationaleId: 'variant:B' },
    { t: 1200, kind: 'planUpdate', id: 'call', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'VQSR — 3.84M PASS variants (ts/tv = 2.04 ✓).' },
    { t: 200,  kind: 'planUpdate', id: 'annot', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 1200, kind: 'planUpdate', id: 'annot', status: 'done' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'chatLine', s: 'find', m: '3.84M annotated variants · 142 ClinVar pathogenic hits.' },
    { t: 0,    kind: 'chatLine', s: 'plan', m: 'Plan finished — 3 of 3 succeeded (variant calling retried once).' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
        title: '3.84M variants · 142 ClinVar pathogenic',
        runtime: '34m 18s', /* cost: '$3.42', */ samples: 1,
        rows: [
          ['PASS variants',           '3,840,217'],
          ['Ts/Tv ratio',             '2.04'],
          ['ClinVar pathogenic',      '142'],
          ['Retried steps',           '1  (HaplotypeCaller)'],
          ['Methods report',          'methods_2026-05-17.md'],
        ],
    }},
  ],
};


// ─────────────────────────────────────────────────────────────────
// v1 SCENARIO ADAPTERS — give the existing v1 scenarios a chat-side
// counterpart so the new surfaces (plan / speaker pills / findings)
// render around them too. Tapes are intentionally shorter than the
// 3 research scenarios: no pilot prompt, no comparison card — those
// flows aren't part of these pipelines.
// ─────────────────────────────────────────────────────────────────

const SCEN_CRYOSPARC = {
  id: 'cryosparc',
  name: 'CryoSPARC SPA',
  oneLiner: 'Single-particle reconstruction — 23 processes · 5 phases',
  domain: 'Cryo-EM',
  user: 'Kira M.',
  query: 'Run single-particle reconstruction on EMPIAR-10025 with 1.3 Å/px',
  // cost: { full_usd: 2.41, full_min: 42, pilot_usd: 0, pilot_min: 0 }, // cost commented out, leaving for future work
  cost: { full_min: 42, pilot_min: 0 },
  pilot: null,
  initialPlan: [
    { id: 'mc',    title: 'Motion correction + CTF', est_s: 600, status: 'pending' },
    { id: 'pick',  title: 'Particle picking',         est_s: 480, status: 'pending' },
    { id: '2d',    title: '2D classification',        est_s: 720, status: 'pending' },
    { id: '3d',    title: '3D refinement',            est_s: 600, status: 'pending' },
    { id: 'sharp', title: 'Sharpening + FSC',         est_s: 180, status: 'pending' },
  ],
  phases: [],
  tape: [
    { t: 200,  kind: 'planShow' },
    { t: 500,  kind: 'chatLine', s: 'plan', m: 'Decomposed into 5 phases: motion correction, picking, 2D, 3D, sharpening.' },
    { t: 700,  kind: 'chatLine', s: 'wf',   m: 'Starting Phase A — MotionCor2 on 842 micrographs.' },
    { t: 0,    kind: 'planUpdate', id: 'mc', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 1400, kind: 'planUpdate', id: 'mc', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'Mean total motion 3.42 Å — all micrographs within tolerance.' },
    { t: 400,  kind: 'planUpdate', id: 'pick', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase B — Topaz picked 1.24M candidate particles.' },
    { t: 1300, kind: 'planUpdate', id: 'pick', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: '2d', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase C — 2D classification, 2 rounds.' },
    { t: 1500, kind: 'planUpdate', id: '2d', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: '4 junk classes excluded · 823,401 particles retained.' },
    { t: 400,  kind: 'planUpdate', id: '3d', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase D — homogeneous → non-uniform → local refinement.' },
    { t: 1800, kind: 'planUpdate', id: '3d', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'sharp', status: 'running' },
    { t: 1000, kind: 'planUpdate', id: 'sharp', status: 'done' },
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'chatLine', s: 'find', m: 'Reconstruction converged at 3.21 Å (FSC 0.143).' },
    { t: 300,  kind: 'chatLine', s: 'plan', m: 'Plan finished — 5 of 5 succeeded.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
      title: '3.21 Å reconstruction · half-map gold-standard',
      runtime: '42m 18s', /* cost: '$2.41', */ samples: 842,
      rows: [
        ['Resolution (FSC 0.143)', '3.21 Å'],
        ['Particles (final)',      '823,401'],
        ['Sharpening B-factor',    '−84 Å²'],
        ['Methods report',         'methods_2026-04-19.md'],
      ],
    }},
  ],
};

const SCEN_GATK = {
  id: 'gatk',
  name: 'WGS Germline · GATK4',
  oneLiner: 'SRA fetch → BWA-MEM2 → HaplotypeCaller → VQSR',
  domain: 'Germline variants',
  user: 'Kira M.',
  query: 'Call germline variants on SRR123456 (human, hg38) with GATK4',
  // cost: { full_usd: 1.84, full_min: 56, pilot_usd: 0, pilot_min: 0 }, // cost commented out, leaving for future work
  cost: { full_min: 56, pilot_min: 0 },
  pilot: null,
  initialPlan: [
    { id: 'fastq', title: 'FASTQ download from SRA',    est_s: 600, status: 'pending' },
    { id: 'align', title: 'BWA-MEM2 alignment + BQSR',  est_s: 1200, status: 'pending' },
    { id: 'call',  title: 'HaplotypeCaller + VQSR',     est_s: 900,  status: 'pending' },
  ],
  phases: [],
  tape: [
    { t: 200,  kind: 'planShow' },
    { t: 500,  kind: 'chatLine', s: 'plan', m: 'Decomposed into 3 phases: SRA fetch, alignment, calling.' },
    { t: 600,  kind: 'chatLine', s: 'wf',   m: 'Phase A — staging reads from SRA via fasterq-dump.' },
    { t: 0,    kind: 'planUpdate', id: 'fastq', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 1400, kind: 'planUpdate', id: 'fastq', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'align', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase B — BWA-MEM2 alignment to GRCh38-noalt.' },
    { t: 1600, kind: 'planUpdate', id: 'align', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: '99.1% mapped · duplicate rate 12% · mean depth 32×.' },
    { t: 400,  kind: 'planUpdate', id: 'call', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase C — HaplotypeCaller → VQSR filtering.' },
    { t: 1500, kind: 'planUpdate', id: 'call', status: 'done' },
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'chatLine', s: 'qc',   m: 'VQSR — 3.84M PASS variants · Ts/Tv = 2.07.' },
    { t: 200,  kind: 'chatLine', s: 'find', m: 'Called 4.2M variants · dbSNP overlap 96.4%.' },
    { t: 300,  kind: 'chatLine', s: 'plan', m: 'Plan finished — 3 of 3 succeeded.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
      title: '3.84M PASS variants · Ts/Tv 2.07',
      runtime: '52m 04s', /* cost: '$1.84', */ samples: 1,
      rows: [
        ['PASS variants',      '3,840,217'],
        ['Ts/Tv ratio',        '2.07'],
        ['dbSNP overlap',      '96.4%'],
        ['Methods report',     'methods_2026-04-19.md'],
      ],
    }},
  ],
};

const SCEN_ADMET = {
  id: 'admet',
  name: 'ADMET Property Prediction',
  oneLiner: 'Single-step ADMET endpoints from SMILES',
  domain: 'ADMET',
  user: 'Kira M.',
  query: 'Predict ADMET endpoints for aspirin (CC(=O)Oc1ccccc1C(=O)O)',
  // cost: { full_usd: 0.02, full_min: 1, pilot_usd: 0, pilot_min: 0 }, // cost commented out, leaving for future work
  cost: { full_min: 1, pilot_min: 0 },
  pilot: null,
  // ADMET is a single-step workflow. Plan only renders for ≥2 sub-tasks,
  // so this scenario intentionally has 1 item — chat-stream + findings
  // card carry the surface demo on their own.
  initialPlan: [
    { id: 'admet', title: 'ADMET endpoint prediction (MPNN ensemble)', est_s: 8, status: 'pending' },
  ],
  phases: [],
  tape: [
    { t: 200,  kind: 'chatLine', s: 'plan', m: 'Single-step workflow — no decomposition needed.' },
    { t: 400,  kind: 'chatLine', s: 'wf',   m: 'Featurizing SMILES · loading MPNN ensemble.' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 1200, kind: 'chatLine', s: 'wf',   m: 'Predictions complete · 7 endpoints.' },
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'chatLine', s: 'qc',   m: 'Lipinski Ro5 — 0 violations.' },
    { t: 200,  kind: 'chatLine', s: 'find', m: 'Favorable oral absorption · moderate hERG risk.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
      title: '7 endpoints predicted · moderate hERG risk',
      runtime: '8s', /* cost: '$0.02', */ samples: 1,
      rows: [
        ['Endpoints predicted', '7'],
        ['Ro5 violations',      '0'],
        ['hERG flag',           'moderate'],
        ['Methods report',      'methods_2026-04-19.md'],
      ],
    }},
  ],
};

const SCEN_NFCORE = {
  id: 'nfcore',
  name: 'nf-core · fastp QC',
  oneLiner: 'Multi-accession read QC with fastp',
  domain: 'Read QC',
  user: 'Kira M.',
  query: 'Run fastp QC on SRR8651520 and SRR8651521 (paired-end).',
  // cost: { full_usd: 0.21, full_min: 6, pilot_usd: 0, pilot_min: 0 }, // cost commented out, leaving for future work
  cost: { full_min: 6, pilot_min: 0 },
  pilot: null,
  initialPlan: [
    { id: 'fetch1', title: 'Fetch SRR8651520',  est_s: 60, status: 'pending', parallel: 'p1' },
    { id: 'fetch2', title: 'Fetch SRR8651521',  est_s: 60, status: 'pending', parallel: 'p1' },
    { id: 'qc1',    title: 'fastp QC · run 1',  est_s: 90, status: 'pending', parallel: 'p2' },
    { id: 'qc2',    title: 'fastp QC · run 2',  est_s: 90, status: 'pending', parallel: 'p2' },
  ],
  phases: [],
  tape: [
    { t: 200,  kind: 'planShow' },
    { t: 500,  kind: 'chatLine', s: 'plan', m: 'Both accessions run in parallel — grouped.' },
    { t: 600,  kind: 'chatLine', s: 'wf',   m: 'Phase A — staging both accessions from SRA.' },
    { t: 0,    kind: 'planUpdate', id: 'fetch1', status: 'running' },
    { t: 0,    kind: 'planUpdate', id: 'fetch2', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 1300, kind: 'planUpdate', id: 'fetch1', status: 'done' },
    { t: 200,  kind: 'planUpdate', id: 'fetch2', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: 'qc1', status: 'running' },
    { t: 0,    kind: 'planUpdate', id: 'qc2', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf',   m: 'Phase B — fastp QC running on both samples.' },
    { t: 1400, kind: 'planUpdate', id: 'qc1', status: 'done' },
    { t: 100,  kind: 'planUpdate', id: 'qc2', status: 'done' },
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'chatLine', s: 'qc',   m: '93.4% reads passed Q30 — no adapter contamination.' },
    { t: 200,  kind: 'chatLine', s: 'find', m: 'Mean Phred 36.2 across both accessions.' },
    { t: 300,  kind: 'chatLine', s: 'plan', m: 'Plan finished — 4 of 4 succeeded.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
      title: '93.4% reads passing Q30 · clean inputs',
      runtime: '6m 04s', /* cost: '$0.21', */ samples: 2,
      rows: [
        ['Reads passing Q30',     '93.4%'],
        ['Adapter contamination', 'none'],
        ['Mean Phred',            '36.2'],
        ['Methods report',        'methods_2026-04-19.md'],
      ],
    }},
  ],
};


// ─────────────────────────────────────────────────────────────────
// Bioconductor handoff — 3 scenario tapes. Markers + numbers + phase
// IDs match BiocTours.jsx callout text exactly so chat + panel + audio
// agree at every FF-target.
// ─────────────────────────────────────────────────────────────────
const SCEN_BIOC_KB = {
  id: 'bioc_kb', name: 'Bioconductor · DESeq2 chain',
  oneLiner: 'Match → route → run → report',
  domain: 'Bulk RNA-seq · Bioconductor',
  user: 'Kira M.',
  query: 'DESeq2 differential expression on 120 salmon quants (control vs treated).',
  cost: { full_min: 22 },
  initialPlan: [
    { id: 'qc',     title: 'QC (filterByExpr)',          est_s: 30,  status: 'pending' },
    { id: 'norm',   title: 'Normalise → DESeqDataSet',   est_s: 30,  status: 'pending' },
    { id: 'de',     title: 'Wald DE test',               est_s: 60,  status: 'pending' },
    { id: 'shrink', title: 'apeglm shrinkage',           est_s: 30,  status: 'pending' },
    { id: 'enrich', title: 'clusterProfiler gseGO',      est_s: 120, status: 'pending' },
    { id: 'viz',    title: 'Volcano / dotplot / heatmap',est_s: 30,  status: 'pending' },
  ],
  phases: [
    { id: 'A', name: 'QC',         summary: 'edgeR::filterByExpr',        status: 'pending' },
    { id: 'B', name: 'Normalise',  summary: 'DESeq2 size factors',         status: 'pending' },
    { id: 'C', name: 'DE test',    summary: 'Wald · ~ condition',          status: 'pending' },
    { id: 'D', name: 'Shrink',     summary: 'apeglm',                      status: 'pending' },
    { id: 'E', name: 'Enrich',     summary: 'clusterProfiler::gseGO',      status: 'pending' },
    { id: 'F', name: 'Visualise',  summary: 'volcano · dotplot · heatmap', status: 'pending' },
  ],
  tape: [
    // Every chat line below is grounded in the BiocTours.jsx callout text for
    // this tour — no fabricated numbers, no infrastructure details, no
    // invented sample splits or convergence iterations.
    { t: 0, kind: 'planShow' },
    { t: 0, kind: 'chatLine', s: 'plan', m: 'Embedding your request against the Bioconductor knowledge base.' },
    { t: 0, kind: 'marker', id: 'bioc_kb_plan' },
    { t: 0, kind: 'showCard', card: 'disambig', data: { candidates: [
        { id: 'bulk_rnaseq_de_analysis',   name: 'Count-matrix DESeq2', tag: 'recommended', score: 0.71, why: 'Salmon quants → DESeq2 chain.' },
        { id: 'bp4_rnaseq_best_practices', name: 'FASTQ pipeline',      tag: 'alt',         score: 0.66, why: 'Starts from raw FASTQ.' },
    ]}},
    { t: 0, kind: 'marker', id: 'bioc_kb_disambig' },
    { t: 0, kind: 'chatLine', s: 'agent', m: 'Selected bulk_rnaseq_de_analysis. Panel populates with the six phases.' },
    { t: 0, kind: 'marker', id: 'bioc_kb_selected' },
    { t: 0, kind: 'agent',   s: 'agent', m: 'Raw integer count matrix → negative-binomial model (DESeq2), not limma/voom (which expects continuous log₂ intensities).' },
    { t: 0, kind: 'marker', id: 'bioc_kb_routed' },
    { t: 0, kind: 'runState', value: 'running' },
    { t: 0, kind: 'planUpdate', id: 'qc', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'Phase A · QC — edgeR::filterByExpr drops genes under 10 counts.' },
    { t: 0, kind: 'marker', id: 'bioc_kb_A_run' },
    { t: 0, kind: 'planUpdate', id: 'qc', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0, kind: 'planUpdate', id: 'norm', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'Phase B · Normalise — counts + metadata + size factors fold into a single DESeqDataSet.' },
    { t: 0, kind: 'planUpdate', id: 'norm', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0, kind: 'marker', id: 'bioc_kb_norm_done' },
    { t: 0, kind: 'planUpdate', id: 'de', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'Phase C · DE test — Wald test on design ~ condition.' },
    { t: 0, kind: 'marker', id: 'bioc_kb_C_run' },
    { t: 0, kind: 'chatLine', s: 'find', m: '2,841 genes DE at FDR < 0.05 → DESeqResults table (log₂FC, p-adj, baseMean per gene).' },
    { t: 0, kind: 'planUpdate', id: 'de', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0, kind: 'planUpdate', id: 'shrink', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'Phase D · Shrink — apeglm shrinks low-count fold-changes toward zero.' },
    { t: 0, kind: 'agent',   s: 'agent', m: 'So the gene list feeding enrichment isn’t dominated by noisy extremes.' },
    { t: 0, kind: 'planUpdate', id: 'shrink', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0, kind: 'marker', id: 'bioc_kb_shrink_done' },
    { t: 0, kind: 'planUpdate', id: 'enrich', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'E', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'Phase E · Enrich — clusterProfiler gseGO on the shrunk ranked list.' },
    { t: 0, kind: 'marker', id: 'bioc_kb_E_run' },
    { t: 0, kind: 'planUpdate', id: 'enrich', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'E', status: 'completed' },
    { t: 0, kind: 'chatLine', s: 'find', m: 'Top GO term: regulation of apoptotic process.' },
    { t: 0, kind: 'planUpdate', id: 'viz', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'F', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'Phase F · Visualise — volcano, dotplot, heatmap.' },
    { t: 0, kind: 'planUpdate', id: 'viz', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'F', status: 'completed' },
    { t: 0, kind: 'runState', value: 'completed' },
    { t: 0, kind: 'showCard', card: 'findings', data: {
        title: '2,841 DE genes · apoptotic process on top',
        runtime: '21m 04s', samples: 120,
        rows: [
          ['DE genes (FDR < 0.05)', '2,841'],
          ['Top GO BP',             'regulation of apoptotic process'],
          ['Methods report',        'methods_deseq2.md'],
        ],
    }},
    { t: 0, kind: 'marker', id: 'bioc_kb_done' },
  ],
};

const SCEN_BIOC_SC = {
  id: 'bioc_sc', name: 'Bioconductor · scRNA-seq chain',
  oneLiner: 'OSCA → cluster → markers ∥ annotation → pseudobulk DESeq2',
  domain: 'single-cell RNA-seq · Bioconductor',
  user: 'Kira M.',
  query: 'Condition DE on 12,402 PBMCs — OSCA stack, pseudobulk DESeq2 the statistically correct way.',
  cost: { full_min: 28 },
  initialPlan: [
    { id: 'qc',     title: 'emptyDrops + per-cell QC',     est_s: 60,  status: 'pending' },
    { id: 'norm',   title: 'scran normalisation',          est_s: 60,  status: 'pending' },
    { id: 'feat',   title: 'modelGeneVar + PCA',           est_s: 90,  status: 'pending' },
    { id: 'cluster',title: 'buildSNNGraph + Louvain',      est_s: 90,  status: 'pending' },
    { id: 'mk',     title: 'scoreMarkers',                 est_s: 120, status: 'pending', parallel: 'p1' },
    { id: 'sr',     title: 'SingleR annotation',           est_s: 120, status: 'pending', parallel: 'p1' },
    { id: 'pb',     title: 'Pseudobulk DESeq2',            est_s: 180, status: 'pending' },
  ],
  phases: [
    { id: 'A', name: 'QC',             summary: 'emptyDrops + perCellQCMetrics', status: 'pending' },
    { id: 'B', name: 'Normalise',      summary: 'scran pooled size factors',      status: 'pending' },
    { id: 'C', name: 'Feature / PCA',  summary: 'modelGeneVar + runPCA',           status: 'pending' },
    { id: 'D', name: 'Cluster',        summary: 'buildSNNGraph + Louvain',         status: 'pending' },
    { id: 'E', name: 'Markers',        summary: 'scoreMarkers (∥ Annotation)',     status: 'pending' },
    { id: 'F', name: 'Annotation',     summary: 'SingleR (∥ Markers)',             status: 'pending' },
    { id: 'G', name: 'Pseudobulk DE',  summary: 'aggregateAcrossCells + DESeq2',   status: 'pending' },
  ],
  tape: [
    { t: 0, kind: 'planShow' },
    { t: 0, kind: 'chatLine', s: 'plan', m: 'Seven sub-tasks · emptyDrops → scran → cluster → markers ∥ annotation → pseudobulk DESeq2.' },
    { t: 0, kind: 'marker', id: 'bioc_sc_plan' },
    { t: 0, kind: 'chatLine', s: 'agent', m: 'Routed to the OSCA stack: SingleCellExperiment + scran/scater, not Seurat — pseudobulk DESeq2 hands off without lossy conversion.' },
    { t: 0, kind: 'marker', id: 'bioc_sc_routed' },
    { t: 0, kind: 'runState', value: 'running' },
    { t: 0, kind: 'planUpdate', id: 'qc', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'emptyDrops · separating cells from ambient barcodes.' },
    { t: 0, kind: 'chatLine', s: 'qc', m: 'perCellQCMetrics · 9,814 of 12,402 cells retained.' },
    { t: 0, kind: 'marker', id: 'bioc_sc_A_run' },
    { t: 0, kind: 'planUpdate', id: 'qc', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0, kind: 'chatLine', s: 'agent', m: 'SingleCellExperiment carries counts, logcounts, metadata, size factors — one object end to end.' },
    { t: 0, kind: 'marker', id: 'bioc_sc_sce_handoff' },
    { t: 0, kind: 'planUpdate', id: 'norm', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'scran::computeSumFactors + logNormCounts.' },
    { t: 0, kind: 'planUpdate', id: 'norm', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0, kind: 'planUpdate', id: 'feat', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'modelGeneVar → 2,142 HVGs · runPCA on top 30 components.' },
    { t: 0, kind: 'planUpdate', id: 'feat', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0, kind: 'planUpdate', id: 'cluster', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'buildSNNGraph + Louvain · 11 clusters (UMAP is a picture, not the cluster source).' },
    { t: 0, kind: 'planUpdate', id: 'cluster', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0, kind: 'marker', id: 'bioc_sc_cluster_done' },
    { t: 0, kind: 'planUpdate', id: 'mk', status: 'running' },
    { t: 0, kind: 'planUpdate', id: 'sr', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'E', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'F', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'scoreMarkers and SingleR (vs Human Primary Cell Atlas) fan out in parallel.' },
    { t: 0, kind: 'marker', id: 'bioc_sc_parallel_run' },
    { t: 0, kind: 'planUpdate', id: 'mk', status: 'done' },
    { t: 0, kind: 'planUpdate', id: 'sr', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'E', status: 'completed' },
    { t: 0, kind: 'phaseUpdate', id: 'F', status: 'completed' },
    { t: 0, kind: 'planUpdate', id: 'pb', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'G', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'qc', m: 'Per-cell DE would treat cells as replicates — pseudoreplication.' },
    { t: 0, kind: 'chatLine', s: 'agent', m: 'Fix: aggregateAcrossCells by sample × cluster, then DESeq2 per cell type — 6 samples are the real replicates.' },
    { t: 0, kind: 'marker', id: 'bioc_sc_pseudobulk_warn' },
    { t: 0, kind: 'planUpdate', id: 'pb', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'G', status: 'completed' },
    { t: 0, kind: 'runState', value: 'completed' },
    { t: 0, kind: 'chatLine', s: 'find', m: '326 pseudobulk DE genes in CD14 monocytes (FDR < 0.05).' },
    { t: 0, kind: 'showCard', card: 'findings', data: {
        title: '11 clusters · 326 monocyte DEGs (pseudobulk)', runtime: '27m 50s',
        rows: [
          ['Cells retained',  '9,814 / 12,402'],
          ['Clusters',        '11'],
          ['Top DE cluster',  'CD14 mono — 326 DEGs'],
        ],
    }},
    { t: 0, kind: 'marker', id: 'bioc_sc_done' },
  ],
};

const SCEN_BIOC_METHYL = {
  id: 'bioc_methyl', name: 'Bioconductor · 450k methylation chain',
  oneLiner: 'minfi → limma DMPs → DMRcate DMRs → CpG-corrected GO',
  domain: '450k methylation · Bioconductor',
  user: 'Kira M.',
  query: 'DMRs on this 450k IDAT cohort (12 case / 12 control) with CpG-bias-corrected GO.',
  cost: { full_min: 18 },
  initialPlan: [
    { id: 'read',  title: 'Read IDATs (minfi)',          est_s: 60,  status: 'pending' },
    { id: 'norm',  title: 'QC + preprocessQuantile',     est_s: 90,  status: 'pending' },
    { id: 'dmp',   title: 'limma DMPs',                  est_s: 60,  status: 'pending' },
    { id: 'dmr',   title: 'DMRcate region call',         est_s: 120, status: 'pending' },
    { id: 'go',    title: 'gometh CpG-corrected GO',     est_s: 90,  status: 'pending' },
  ],
  phases: [
    { id: 'A', name: 'Read IDAT',                summary: 'minfi::read.metharray.exp',           status: 'pending' },
    { id: 'B', name: 'QC + Normalise',           summary: 'preprocessQuantile → GenomicRatioSet', status: 'pending' },
    { id: 'C', name: 'DMP calling',              summary: 'limma eBayes on M-values',             status: 'pending' },
    { id: 'D', name: 'DMR calling',              summary: 'DMRcate kernel smoothing',             status: 'pending' },
    { id: 'E', name: 'CpG-corrected enrichment', summary: 'missMethyl::gometh',                   status: 'pending' },
  ],
  tape: [
    { t: 0, kind: 'planShow' },
    { t: 0, kind: 'chatLine', s: 'plan', m: 'Five sub-tasks · minfi → preprocessQuantile → limma DMPs → DMRcate → gometh.' },
    { t: 0, kind: 'marker', id: 'bioc_methyl_plan' },
    { t: 0, kind: 'chatLine', s: 'agent', m: 'IDAT + 450k manifest → minfi; downstream DMR needs a genomic object, not a plain matrix.' },
    { t: 0, kind: 'marker', id: 'bioc_methyl_routed' },
    { t: 0, kind: 'runState', value: 'running' },
    { t: 0, kind: 'planUpdate', id: 'read', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'read.metharray.exp · 24 IDAT pairs → MethylSet (450k probes × 24 samples).' },
    { t: 0, kind: 'marker', id: 'bioc_methyl_A_run' },
    { t: 0, kind: 'planUpdate', id: 'read', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0, kind: 'planUpdate', id: 'norm', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'qc', m: 'Detection-p + SNP/cross-reactive filter · 452,019 probes retained.' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'preprocessQuantile · GenomicRatioSet with probe coordinates.' },
    { t: 0, kind: 'planUpdate', id: 'norm', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0, kind: 'marker', id: 'bioc_methyl_grset_done' },
    { t: 0, kind: 'planUpdate', id: 'dmp', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'limma eBayes on M-values · ~ group.' },
    { t: 0, kind: 'marker', id: 'bioc_methyl_C_run' },
    { t: 0, kind: 'chatLine', s: 'find', m: '12,403 significant CpGs at FDR < 0.05.' },
    { t: 0, kind: 'planUpdate', id: 'dmp', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0, kind: 'planUpdate', id: 'dmr', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'wf', m: 'DMRcate · kernel λ = 1000, C = 2.' },
    { t: 0, kind: 'planUpdate', id: 'dmr', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0, kind: 'chatLine', s: 'find', m: '847 DMRs from 12,403 significant CpGs.' },
    { t: 0, kind: 'marker', id: 'bioc_methyl_dmr_done' },
    { t: 0, kind: 'planUpdate', id: 'go', status: 'running' },
    { t: 0, kind: 'phaseUpdate', id: 'E', status: 'running' },
    { t: 0, kind: 'chatLine', s: 'qc', m: 'Generic GO would over-call CpG-rich promoters on the array.' },
    { t: 0, kind: 'chatLine', s: 'agent', m: 'Fix: missMethyl::gometh weights genes by CpG count so enrichment p-values stay calibrated.' },
    { t: 0, kind: 'marker', id: 'bioc_methyl_cpg_warn' },
    { t: 0, kind: 'planUpdate', id: 'go', status: 'done' },
    { t: 0, kind: 'phaseUpdate', id: 'E', status: 'completed' },
    { t: 0, kind: 'runState', value: 'completed' },
    { t: 0, kind: 'showCard', card: 'findings', data: {
        title: '847 DMRs · CpG-bias-corrected GO', runtime: '17m 22s',
        rows: [
          ['Significant CpGs', '12,403'],
          ['DMRs (DMRcate)',   '847'],
          ['Methods report',   'methods_minfi.md'],
        ],
    }},
    { t: 0, kind: 'marker', id: 'bioc_methyl_done' },
  ],
};

window.RESEARCH_SCENARIOS = {
  rnaseq:     SCEN_RNASEQ,
  drugscreen: SCEN_DRUGSCREEN,
  variant:    SCEN_VARIANT,
  // v1 adapters — make the four legacy scenarios render in the new chat surfaces
  cryosparc:  SCEN_CRYOSPARC,
  gatk:       SCEN_GATK,
  admet:      SCEN_ADMET,
  nfcore:     SCEN_NFCORE,
  bioc_kb:     SCEN_BIOC_KB,
  bioc_sc:     SCEN_BIOC_SC,
  bioc_methyl: SCEN_BIOC_METHYL,
};

// ── Phase-trace lookup (Surface 3 expansion data) ─────────────────
// Mapped by (scenarioId, phaseId). The engine reads this to populate
// the "Why this step / Live events / Parameters / Cost" sub-sections.
window.RESEARCH_PHASE_TRACE = {
  'rnaseq:B': {
    rationale: {
      text: 'STAR was selected over HISAT2 because the input is human GRCh38 with average read length 150bp, which sits in STAR\'s optimal regime. HISAT2 wins on RAM but loses ~3% mapping rate at this read length.',
      cite: { title: 'BioMate rationale KB · aligners', href: '#' },
    },
    events: [
      { ts: '4:23:01', s: 'wf', m: 'Submitted to AWS Batch · job 8f3e21…' },
      { ts: '4:23:09', s: 'wf', m: 'Container pulled · 8s.' },
      { ts: '4:23:10', s: 'wf', m: 'Running on m5.4xlarge — 16 vCPU, 64 GB RAM.' },
      { ts: '4:23:12', s: 'wf', m: 'Read SRR_…_R1.fastq.gz (2.4 GB) from S3.' },
      { ts: '4:23:14', s: 'wf', m: 'Read SRR_…_R2.fastq.gz (2.4 GB) from S3.' },
      { ts: '4:23:31', s: 'wf', m: 'STAR genome loaded — 28s.' },
      { ts: '4:24:18', s: 'wf', m: 'Pass 1 of 2 done — 14M reads.' },
      { ts: '4:24:43', s: 'wf', m: 'Pass 2 of 2 done — 14M reads.' },
      { ts: '4:24:47', s: 'qc', m: 'Mapping rate 97.2% ✓ (gate ≥ 95%).' },
      { ts: '4:24:48', s: 'wf', m: 'BAM sorted + indexed.' },
      { ts: '4:24:50', s: 'wf', m: 'Outputs uploaded to s3://biomate/runs/…' },
      { ts: '4:24:51', s: 'wf', m: 'Phase exited cleanly.' },
    ],
    params: [
      { k: '--outSAMtype',     v: 'BAM SortedByCoordinate', tag: 'edited' },
      { k: '--alignIntronMax', v: '500000',                 tag: 'default' },
      { k: '--runThreadN',     v: '16',                     tag: 'default' },
      { k: '--genomeDir',      v: 'refs/star/GRCh38_2.7.10/',tag: 'default' },
      { k: '--readFilesIn',    v: 'SRR_…_R1.fq.gz SRR_…_R2.fq.gz', tag: 'default' },
    ],
    // cost: { used: '$0.32', est: '$0.30', vcpuh: '3 vCPU-h' }, // commented out, leaving for future work
  },
  'rnaseq:C': {
    rationale: {
      text: 'DESeq2 selected because the design is a 2-condition control vs. treated with > 8 replicates per group; the negative-binomial fit is well-powered. edgeR was the runner-up but DESeq2 has slightly tighter Type-I error in this regime.',
      cite: { title: 'BioMate rationale KB · DE tools', href: '#' },
    },
    events: [
      { ts: '4:26:01', s: 'wf', m: 'Submitted to AWS Batch · job 8f3e29…' },
      { ts: '4:26:08', s: 'wf', m: 'Counts matrix loaded — 60,233 genes × 120 samples.' },
      { ts: '4:26:12', s: 'wf', m: 'Size factor estimation done.' },
      { ts: '4:26:24', s: 'wf', m: 'Dispersion fit converged after 4 iterations.' },
      { ts: '4:26:39', s: 'find', m: '1,284 genes DE at FDR < 0.05 (812 up, 472 down).' },
    ],
    params: [
      { k: 'design',     v: '~ condition',                  tag: 'default' },
      { k: 'reference',  v: 'control',                      tag: 'default' },
      { k: 'fdr_cutoff', v: '0.05',                         tag: 'default' },
      { k: 'min_count',  v: '10',                           tag: 'default' },
    ],
    // cost: { used: '$0.18', est: '$0.20', vcpuh: '0.6 vCPU-h' }, // commented out, leaving for future work
  },
  'drugscreen:B': {
    rationale: {
      text: 'Chose the MPNN ensemble over single-model because for libraries > 5k compounds the calibration error per gate matters more than peak accuracy — ensembles give smoother score distributions at the QC threshold.',
      cite: { title: 'BioMate rationale KB · ADMET models', href: '#' },
    },
    events: [
      { ts: '4:30:01', s: 'wf', m: 'Submitted to AWS Batch · job 9c4d18…' },
      { ts: '4:30:14', s: 'wf', m: 'Model bundle pulled — 1.8 GB.' },
      { ts: '4:30:22', s: 'wf', m: 'Featurizing 500 compounds…' },
      { ts: '4:30:38', s: 'wf', m: 'Predictions complete · 7 endpoints × 500.' },
    ],
    params: [
      { k: 'ensemble_size', v: '5',         tag: 'default' },
      { k: 'logp_max',      v: '4.5',       tag: 'autoloop' },
      { k: 'mw_max',        v: '480',       tag: 'autoloop' },
      { k: 'model_seed',    v: '123',       tag: 'user' },
    ],
    // cost: { used: '$0.21', est: '$0.25', vcpuh: '0.8 vCPU-h' }, // commented out, leaving for future work
  },
  'variant:B': {
    rationale: {
      text: 'GATK4 HaplotypeCaller is the standard for germline calling on Illumina reads at this depth (~30×). The first attempt failed on chr17 due to a contig naming mismatch between bwa-mem2 (hg38-d1) and the GATK reference dict — re-indexing to hg38-noalt resolved it.',
      cite: { title: 'BioMate rationale KB · GATK pipelines', href: '#' },
    },
    events: [
      { ts: '4:38:21', s: 'wf',     m: 'Submitted to AWS Batch · job a3f7…' },
      { ts: '4:38:44', s: 'qc',     m: '✕ chr17 contig mismatch — first attempt failed.' },
      { ts: '4:38:46', s: 'agent',  m: 'Suggested re-index with hg38-noalt.' },
      { ts: '4:38:50', s: 'loop',   m: 'Re-running with patched reference.' },
      { ts: '4:42:12', s: 'find',   m: '4.21M raw variants called.' },
    ],
    params: [
      { k: 'reference',         v: 'hg38-noalt',    tag: 'autoloop' },
      { k: '--emit-ref-confidence', v: 'GVCF',      tag: 'default' },
      { k: '--min-base-quality',v: '10',            tag: 'default' },
      { k: '--max-mnp-distance',v: '0',             tag: 'default' },
    ],
    // cost: { used: '$0.78', est: '$0.60', vcpuh: '2.4 vCPU-h' }, // commented out, leaving for future work
  },
};
