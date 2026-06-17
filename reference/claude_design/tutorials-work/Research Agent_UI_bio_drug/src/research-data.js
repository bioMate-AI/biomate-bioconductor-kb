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
        metrics: [
          { name: 'Runtime',     a: '12m 04s', b: '9m 18s',  delta: '−23%', dir: 'up' },
          { name: 'Peak memory', a: '31 GB',   b: '29 GB',   delta: '−6%',  dir: 'up' },
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
    { kind: 'marker', id: 'cryo_plan' },
    { t: 700,  kind: 'chatLine', s: 'wf',   m: 'Starting Phase A — MotionCor2 on 842 micrographs.' },
    { t: 0,    kind: 'planUpdate', id: 'mc', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { kind: 'marker', id: 'cryo_a_run' },
    { t: 1400, kind: 'planUpdate', id: 'mc', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'Mean total motion 3.42 Å — all micrographs within tolerance.' },
    { kind: 'marker', id: 'cryo_a_done' },
    { t: 400,  kind: 'planUpdate', id: 'pick', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase B — Topaz picked 1.24M candidate particles.' },
    { kind: 'marker', id: 'cryo_b_run' },
    { t: 1300, kind: 'planUpdate', id: 'pick', status: 'done' },
    { t: 0,    kind: 'planUpdate', id: '2d', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase C — 2D classification, 2 rounds.' },
    { t: 1500, kind: 'planUpdate', id: '2d', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: '4 junk classes excluded · 823,401 particles retained.' },
    { t: 400,  kind: 'planUpdate', id: '3d', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase D — homogeneous → non-uniform → local refinement.' },
    { kind: 'marker', id: 'cryo_de_run' },
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
    { kind: 'marker', id: 'cryo_done' },
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
// BIOCONDUCTOR · knowledge-based routing & execution.
//
// One flagship scenario that shows the whole story the Bioconductor KB
// is built to demonstrate:
//   1. Ranked KB match returns two close chains → disambiguation card.
//   2. Context-based routing of the DE step by data format (DESeq2 vs
//      limma) — the "why this package" teaching moment, with a (why?).
//   3. Execution of the routed DESeq2 chain, narrating the typed object
//      handoffs (DESeqDataSet → DESeqResults → apeglm) that let
//      Bioconductor packages compose.
//
// Teaching lines that deserve inline visibility use the AGENT speaker
// (it breaks the progress-fold); mechanical phase progress uses WF
// (folds into the "Working" block). Phase ids A–F match SCENARIOS.bioc_kb
// in data.js so the panel breakdown tracks the chat 1-to-1.
// ─────────────────────────────────────────────────────────────────
const SCEN_BIOC_KB = {
  id: 'bioc_kb',
  name: 'Bioconductor · DESeq2 chain',
  oneLiner: 'KB match → disambiguate → route by data format → run chain',
  domain: 'Bulk RNA-seq (Bioconductor)',
  user: 'Kira M.',
  query: 'Run an end-to-end differential expression analysis on my count matrix (human, control vs treated). Include pathway + GO enrichment.',
  cost: { full_min: 18, pilot_min: 0 },
  pilot: null,

  initialPlan: [
    { id: 'c1', title: 'QC & filtering',     status: 'pending', est_s: 10 },
    { id: 'c2', title: 'Normalisation',      status: 'pending', est_s: 15 },
    { id: 'c3', title: 'DE testing',         status: 'pending', est_s: 30 },
    { id: 'c4', title: 'LFC shrinkage',      status: 'pending', est_s: 8  },
    { id: 'c5', title: 'Pathway enrichment', status: 'pending', est_s: 20 },
    { id: 'c6', title: 'Visualisation',      status: 'pending', est_s: 10 },
  ],

  phases: [
    { id: 'A', name: 'QC & filtering',     summary: 'edgeR::filterByExpr',           status: 'pending' },
    { id: 'B', name: 'Normalisation',      summary: 'estimateSizeFactors',           status: 'pending' },
    { id: 'C', name: 'DE testing',         summary: 'DESeq2 Wald',                   status: 'pending' },
    { id: 'D', name: 'LFC shrinkage',      summary: 'apeglm',                        status: 'pending' },
    { id: 'E', name: 'Pathway enrichment', summary: 'clusterProfiler gseGO',         status: 'pending' },
    { id: 'F', name: 'Visualisation',      summary: 'volcano · dotplot · heatmap',   status: 'pending' },
  ],

  tape: [
    // ── Scene 0: KB query + ranked disambiguation ─────────────────
    { t: 0,    kind: 'section', n: 1, total: 4, title: 'Understanding the request' },
    { t: 200,  kind: 'planShow' },
    { t: 600,  kind: 'chatLine', s: 'plan', m: 'Querying the Bioconductor knowledge base — embedding your request against 15 curated workflow chains.' },
    { t: 800,  kind: 'chatLine', s: 'plan', m: 'Two chains matched at similar confidence, so I’ll surface both rather than guess before committing compute.' },
    { kind: 'marker', id: 'bioc_kb_plan' },
    { t: 300,  kind: 'section', n: 2, total: 4, title: 'Choosing the approach' },
    { t: 200,  kind: 'showCard', card: 'disambig', data: {
        prompt: 'Two workflows match your request at similar confidence.',
        options: [
          { id: 'bulk_rnaseq_de_analysis', label: 'Standard DE Analysis',
            sub: '6 steps · starts from a count matrix', score: '0.71', badge: 'top match', recommended: true,
            detail: 'DESeq2 → apeglm → clusterProfiler → EnhancedVolcano',
            action: 'disambig_select_a' },
          { id: 'bp4_rnaseq_best_practices_pipeline', label: 'Best-Practices Pipeline (BP4)',
            sub: '9 steps · starts from raw FASTQ', score: '0.66', badge: 'fuller run',
            detail: 'STAR → featureCounts → DESeq2 → fgsea',
            action: 'disambig_select_b' },
        ],
    }},
    { kind: 'marker', id: 'bioc_kb_disambig' },
    { t: 0,    kind: 'startCountdown', label: 'disambig_auto', seconds: 10 },
    { t: 0,    kind: 'await', label: 'disambig_selected' },

    // ── Scene 1: context-based routing decision ───────────────────
    { t: 0,    kind: 'dismissCard', card: 'disambig' },
    { t: 0,    kind: 'chatLine', s: 'plan', m: 'Selected **bulk_rnaseq_de_analysis** — your input already starts at the count matrix.' },
    { kind: 'marker', id: 'bioc_kb_selected' },
    { t: 600,  kind: 'chatLine', s: 'agent',
      lead: 'Route by the data type, not by habit',
      explain: true,
      m: 'I pick the DE tool from the data format: your input is a raw integer **count matrix**, so I use DESeq2 (a negative-binomial model). Not limma/voom — that path is for continuous log₂ intensities, a different kind of data.',
      rationaleId: 'bioc_kb:routing' },
    { kind: 'marker', id: 'bioc_kb_routed' },

    // ── Phase 1 · QC ──────────────────────────────────────────────
    { t: 300,  kind: 'section', n: 3, total: 4, title: 'Running the chain' },
    { t: 200,  kind: 'planUpdate', id: 'c1', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase 1 · QC. `edgeR::filterByExpr` — dropping genes with <10 counts in ≥2 samples.' },
    { kind: 'marker', id: 'bioc_kb_A_run' },
    { t: 1200, kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'c1', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'Filter — 14,203 of 18,421 genes retained (77%).' },

    // ── Phase 2 · Normalisation + object handoff ──────────────────
    { t: 400,  kind: 'planUpdate', id: 'c2', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase 2 · Normalisation. `DESeq2::estimateSizeFactors` (median-of-ratios). Size factors 0.91–1.14 — healthy range.' },
    { t: 1200, kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'c2', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'agent',
      lead: 'One typed object carries the whole analysis',
      explain: true,
      m: 'QC and normalisation fold into a single `DESeqDataSet` — counts, sample metadata, the design and size factors all travel together as one object. That object class is the contract every downstream DESeq2 step reads from.',
      rationaleId: 'bioc_kb:dds_handoff' },
    { kind: 'marker', id: 'bioc_kb_norm_done' },

    // ── Phase 3 · DE testing ──────────────────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'c3', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase 3 · DE testing. Wald test, design `~ condition`. 2,841 genes at FDR < 0.05.' },
    { kind: 'marker', id: 'bioc_kb_C_run' },
    { t: 1400, kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'c3', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: '→ `DESeqResults` (log2FC, padj, baseMean per gene). Passing to LFC shrinkage.' },

    // ── Phase 4 · Shrinkage ───────────────────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'c4', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'agent',
      lead: 'Shrink noisy fold-changes before ranking',
      explain: true,
      m: 'Low-count genes get wild fold-change estimates. `apeglm` shrinks those toward zero, so the ranked gene list feeding enrichment isn’t dominated by noisy extremes.',
      rationaleId: 'bioc_kb:apeglm_why' },
    { t: 1100, kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'c4', status: 'done' },
    { kind: 'marker', id: 'bioc_kb_shrink_done' },

    // ── Phase 5 · Enrichment ──────────────────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'c5', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'E', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase 5 · Enrichment. clusterProfiler `gseGO` (GO BP). Top: regulation of apoptotic process (p.adj 2.1e-11).' },
    { kind: 'marker', id: 'bioc_kb_E_run' },
    { t: 1300, kind: 'phaseUpdate', id: 'E', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'c5', status: 'done' },

    // ── Phase 6 · Visualisation ───────────────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'c6', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'F', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase 6 · Visualisation. EnhancedVolcano, enrichplot dotplot, ComplexHeatmap (top 50 DE genes).' },
    { t: 1200, kind: 'phaseUpdate', id: 'F', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'c6', status: 'done' },

    // ── Done ──────────────────────────────────────────────────────
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'section', n: 4, total: 4, title: 'What we found' },
    { t: 0,    kind: 'chatLine', s: 'find', m: '**2,841 DE genes** at FDR < 0.05. Full chain: DESeq2 → apeglm → clusterProfiler → EnhancedVolcano.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
        title: '2,841 DE genes · apoptotic process on top',
        runtime: '16m 41s', samples: 24,
        rows: [
          ['DE genes (FDR < 0.05)', '2,841'],
          ['Routed chain',          'bulk_rnaseq_de_analysis'],
          ['Top pathway (GO BP)',   'regulation of apoptotic process'],
          ['Outputs',               'DE table · volcano · dotplot · heatmap'],
          ['Methods report',        'methods_2026-05-31.md'],
        ],
    }},
    { kind: 'marker', id: 'bioc_kb_done' },
  ],
};


// ─────────────────────────────────────────────────────────────────
// SCEN_BIOC_SC — Bioconductor single-cell RNA-seq chain.
// The distinct beats vs. bioc_kb:
//   1. Routing to the OSCA / SingleCellExperiment ecosystem (scran +
//      scater), with a (why?) on why not Seurat for a Bioconductor demo.
//   2. A PARALLEL plan branch — marker detection (q5) and cell-type
//      annotation (q6) share `parallel: 'p1'` and run concurrently.
//   3. The pseudobulk-vs-naive QC warning: naive per-cell DE treats
//      thousands of cells as replicates (pseudoreplication) and inflates
//      FDR; aggregateAcrossCells → DESeq2 on true biological replicates.
// Phase ids A–G match SCENARIOS.bioc_sc in data.js 1-to-1.
// ─────────────────────────────────────────────────────────────────
const SCEN_BIOC_SC = {
  id: 'bioc_sc',
  name: 'Bioconductor · scRNA-seq chain',
  oneLiner: 'route to OSCA → cluster + annotate (parallel) → pseudobulk DE',
  domain: 'Single-cell RNA-seq (Bioconductor)',
  user: 'Devin O.',
  query: 'Cluster and annotate my 10x single-cell dataset (12k cells, control vs treated, 6 samples), then find condition markers per cell type.',
  cost: { full_min: 24, pilot_min: 0 },
  pilot: null,

  initialPlan: [
    { id: 'q1', title: 'QC & empty-drop filtering',  status: 'pending', est_s: 20 },
    { id: 'q2', title: 'Normalisation (scran)',      status: 'pending', est_s: 18 },
    { id: 'q3', title: 'Feature selection + PCA',     status: 'pending', est_s: 16 },
    { id: 'q4', title: 'Graph-based clustering',      status: 'pending', est_s: 22 },
    { id: 'q5', title: 'Marker detection',            status: 'pending', est_s: 18, parallel: 'p1' },
    { id: 'q6', title: 'Cell-type annotation',        status: 'pending', est_s: 18, parallel: 'p1' },
    { id: 'q7', title: 'Pseudobulk DE',               status: 'pending', est_s: 26 },
  ],

  phases: [
    { id: 'A', name: 'QC & filtering',     summary: 'emptyDrops + perCellQCMetrics',   status: 'pending' },
    { id: 'B', name: 'Normalisation',      summary: 'scran deconvolution',             status: 'pending' },
    { id: 'C', name: 'Feature sel. + PCA', summary: 'modelGeneVar → PCA',              status: 'pending' },
    { id: 'D', name: 'Clustering',         summary: 'buildSNNGraph + Louvain',         status: 'pending' },
    { id: 'E', name: 'Marker detection',   summary: 'scoreMarkers (parallel)',         status: 'pending' },
    { id: 'F', name: 'Annotation',         summary: 'SingleR (parallel)',              status: 'pending' },
    { id: 'G', name: 'Pseudobulk DE',      summary: 'aggregateAcrossCells → DESeq2',   status: 'pending' },
  ],

  tape: [
    // ── Scene 0: KB query + routing to the OSCA ecosystem ─────────
    { t: 0,    kind: 'section', n: 1, total: 4, title: 'Understanding the request' },
    { t: 200,  kind: 'planShow' },
    { t: 600,  kind: 'chatLine', s: 'plan', m: 'Querying the Bioconductor knowledge base — your single-cell request best-matched the **scrna_osca_workflow** chain (0.74 confidence).' },
    { t: 700,  kind: 'chatLine', s: 'plan', m: 'Broke it into 7 phases. Marker detection and annotation both read the clustered object, so I grouped them to run in parallel.' },
    { kind: 'marker', id: 'bioc_sc_plan' },
    { t: 400,  kind: 'section', n: 2, total: 4, title: 'Choosing the approach' },
    { t: 700,  kind: 'chatLine', s: 'agent',
      lead: 'Pick the toolkit by working backward from the goal',
      explain: true,
      m: 'Your last step is condition DE, which I want to run with DESeq2. So I route to the **OSCA** stack — a `SingleCellExperiment` held by scran/scater — not Seurat. Staying Bioconductor-native means the final pseudobulk step hands off to DESeq2 with no lossy object conversion.',
      rationaleId: 'bioc_sc:routing' },
    { kind: 'marker', id: 'bioc_sc_routed' },

    // ── Phase A · QC & empty-drop filtering ──────────────────────
    { t: 300,  kind: 'section', n: 3, total: 4, title: 'Running the chain' },
    { t: 200,  kind: 'planUpdate', id: 'q1', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase A · QC. `emptyDrops` (FDR < 0.001) to separate cells from ambient barcodes, then `perCellQCMetrics`.' },
    { kind: 'marker', id: 'bioc_sc_A_run' },
    { t: 900,  kind: 'chatLine', s: 'wf', m: 'Flagging cells: high mito %, low library size / detected genes (3 MADs).' },
    { t: 0,    kind: 'collapseLines', count: 1 },
    { t: 1200, kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'q1', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'QC — 9,814 of 12,402 cells retained (2,588 dropped: ambient or >10% mito).' },

    // ── Phase B · Normalisation + object handoff ─────────────────
    { t: 400,  kind: 'planUpdate', id: 'q2', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase B · Normalisation. `scran::computeSumFactors` (deconvolution, quick-cluster pre-grouping) → `logNormCounts`.' },
    { t: 1200, kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'q2', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'agent',
      lead: 'Everything downstream rides on one shared object',
      explain: true,
      m: 'QC and normalisation are done, and they fold into one `SingleCellExperiment` carrying counts, logcounts, sample metadata and per-cell size factors. Every step below — including the DESeq2 pseudobulk — reads from this single object.',
      rationaleId: 'bioc_sc:sce_handoff' },
    { kind: 'marker', id: 'bioc_sc_sce_handoff' },

    // ── Phase C · Feature selection + PCA ────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'q3', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase C · `modelGeneVar` → top 2,000 HVGs → `runPCA` (50 PCs, ~38% variance).' },
    { t: 1200, kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'q3', status: 'done' },

    // ── Phase D · Clustering ─────────────────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'q4', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase D · `buildSNNGraph` (k=10) + Louvain. 11 clusters; UMAP for visualisation only.' },
    { t: 1300, kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'q4', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: '→ Clustered `SingleCellExperiment`. Marker detection and annotation both read it — dispatching them together.' },
    { kind: 'marker', id: 'bioc_sc_cluster_done' },

    // ── Phases E + F · PARALLEL branch ───────────────────────────
    { t: 300,  kind: 'planUpdate', id: 'q5', status: 'running' },
    { t: 0,    kind: 'planUpdate', id: 'q6', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'E', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'F', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Parallel branch open: `scoreMarkers` (E) + `SingleR` annotation (F) against the Human Primary Cell Atlas.' },
    { kind: 'marker', id: 'bioc_sc_parallel_run' },
    { t: 1300, kind: 'phaseUpdate', id: 'E', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'q5', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'Markers — 11 clusters resolved (CD8⁺ T, CD4⁺ T, NK, B, mono, DC, …).' },
    { t: 500,  kind: 'phaseUpdate', id: 'F', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'q6', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'qc', m: 'Annotation — 8 cell types assigned (SingleR pruned 1 low-confidence cluster).' },
    { kind: 'marker', id: 'bioc_sc_parallel_done' },

    // ── Phase G · Pseudobulk DE — the teaching warning ───────────
    { t: 400,  kind: 'planUpdate', id: 'q7', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'G', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'qc', k: 'qc-err',
      lead: 'A trap to avoid: pseudoreplication',
      explain: true,
      m: 'The obvious move — test every cell as a replicate — is wrong here. The 9,814 cells come from just 6 samples, so they aren\u2019t independent. Treating them as 9,814 replicates would make almost everything look significant.',
      why: 'Differential-expression statistics assume replicates are independent. Cells from the same sample share its biology, so the real number of independent units is the 6 samples, not the thousands of cells.' },
    { t: 600,  kind: 'chatLine', s: 'agent',
      lead: 'The fix: collapse to pseudobulk, then test',
      explain: true,
      m: 'So I sum counts per (sample × cell type) with `aggregateAcrossCells` — now the 6 samples are the real replicates — and run DESeq2 within each cell type. This is the statistically correct unit for condition DE.',
      rationaleId: 'bioc_sc:pseudobulk_why' },
    { kind: 'marker', id: 'bioc_sc_pseudobulk_warn' },
    { t: 1100, kind: 'chatLine', s: 'wf', m: 'Aggregated to 48 pseudobulk profiles (6 samples × 8 cell types). Running DESeq2 within each type.' },
    { t: 1300, kind: 'phaseUpdate', id: 'G', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'q7', status: 'done' },

    // ── Done ─────────────────────────────────────────────────────
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'section', n: 4, total: 4, title: 'What we found' },
    { t: 0,    kind: 'chatLine', s: 'find', m: 'Strongest condition response in **CD8⁺ T cells** — 214 DE genes (FDR < 0.05), measured on true biological replicates.' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
        title: '8 cell types · CD8⁺ T strongest responder',
        runtime: '21m 07s', samples: 6,
        rows: [
          ['Cells after QC',        '9,814 of 12,402'],
          ['Clusters → cell types', '11 → 8 (SingleR)'],
          ['DE unit',               'pseudobulk · 48 profiles'],
          ['Top responder',         'CD8⁺ T — 214 DE genes'],
          ['Outputs',               'UMAP · marker heatmap · per-type DE tables'],
        ],
    }},
    { kind: 'marker', id: 'bioc_sc_done' },
  ],
};


// ─────────────────────────────────────────────────────────────────
// SCEN_BIOC_METHYL — Bioconductor 450k methylation (epigenomics) chain.
// The distinct beat vs. the other two Bioconductor demos is the BACKBONE
// OBJECT: a GRanges / GenomicRatioSet lineage (MethylSet → GenomicRatioSet
// → DMP data.frame → GRanges of DMRs) rather than DESeqDataSet. The
// teaching moment is CpG-density bias: naive GO over-represents CpG-rich
// promoters, so missMethyl::gometh corrects per-gene CpG count.
// Phase ids A–E match SCENARIOS.bioc_methyl in data.js 1-to-1.
// ─────────────────────────────────────────────────────────────────
const SCEN_BIOC_METHYL = {
  id: 'bioc_methyl',
  name: 'Bioconductor · 450k methylation chain',
  oneLiner: 'IDAT → GenomicRatioSet → DMP → GRanges DMRs → CpG-corrected GO',
  domain: 'DNA methylation array (Bioconductor)',
  user: 'Lena R.',
  query: 'Find differentially methylated regions between tumour and normal on my Illumina 450k array (24 samples), then run GO enrichment.',
  cost: { full_min: 15, pilot_min: 0 },
  pilot: null,

  initialPlan: [
    { id: 'm1', title: 'Read IDAT files',                status: 'pending', est_s: 20 },
    { id: 'm2', title: 'QC + normalisation',             status: 'pending', est_s: 30 },
    { id: 'm3', title: 'DMP calling',                    status: 'pending', est_s: 25 },
    { id: 'm4', title: 'DMR calling',                    status: 'pending', est_s: 40 },
    { id: 'm5', title: 'GO enrichment (CpG-corrected)',  status: 'pending', est_s: 15 },
  ],

  phases: [
    { id: 'A', name: 'Read IDAT',          summary: 'minfi::read.metharray → MethylSet',  status: 'pending' },
    { id: 'B', name: 'QC + normalisation', summary: 'preprocessQuantile → GenomicRatioSet',status: 'pending' },
    { id: 'C', name: 'DMP calling',        summary: 'limma eBayes on M-values',            status: 'pending' },
    { id: 'D', name: 'DMR calling',        summary: 'bumphunter → GRanges',                status: 'pending' },
    { id: 'E', name: 'GO enrichment',      summary: 'missMethyl::gometh (CpG-corrected)',  status: 'pending' },
  ],

  tape: [
    // ── Scene 0: KB query + routing to the minfi/450k pipeline ────
    { t: 0,    kind: 'section', n: 1, total: 4, title: 'Understanding the request' },
    { t: 200,  kind: 'planShow' },
    { t: 600,  kind: 'chatLine', s: 'plan', m: 'Querying the Bioconductor knowledge base — IDAT input + 450k matched **methylation_450k_array_analysis** (0.78).' },
    { t: 700,  kind: 'chatLine', s: 'plan', m: 'Broke it into 5 phases: read → QC/normalise → DMP → DMR → enrichment.' },
    { kind: 'marker', id: 'bioc_methyl_plan' },
    { t: 400,  kind: 'section', n: 2, total: 4, title: 'Choosing the approach' },
    { t: 700,  kind: 'chatLine', s: 'agent',
      lead: 'The input format picks the whole toolkit',
      explain: true,
      m: 'Your data is raw Illumina **IDAT** with a 450k manifest, so I route to the **minfi** pipeline. The whole chain rides one genomic backbone object — each probe’s genomic coordinates travel with the data the entire way, which is what makes region-level analysis possible later.',
      rationaleId: 'bioc_methyl:routing' },
    { kind: 'marker', id: 'bioc_methyl_routed' },

    // ── Phase A · Read IDAT → MethylSet ──────────────────────────
    { t: 300,  kind: 'section', n: 3, total: 4, title: 'Running the chain' },
    { t: 200,  kind: 'planUpdate', id: 'm1', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'A', status: 'running' },
    { t: 0,    kind: 'runState', value: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase A · `minfi::read.metharray.exp` on the IDAT pairs.' },
    { kind: 'marker', id: 'bioc_methyl_A_run' },
    { t: 1200, kind: 'phaseUpdate', id: 'A', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'm1', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: '→ `MethylSet` — raw methylated + unmethylated intensities from IDAT. 450,000 probes × 24 samples.' },

    // ── Phase B · QC + normalisation → GenomicRatioSet ───────────
    { t: 400,  kind: 'planUpdate', id: 'm2', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'B', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase B · detection-p QC (all 24 samples pass), drop SNP/cross-reactive probes, `preprocessQuantile`.' },
    { t: 1300, kind: 'phaseUpdate', id: 'B', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'm2', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'agent',
      lead: 'Coordinates travel with the data',
      explain: true,
      m: 'After QC + normalisation the object is a `GenomicRatioSet`: β-values with **each probe’s genomic coordinate attached**. That GRanges backbone is the contract every downstream step reads — and it’s what lets the next step collapse CpGs into regions.',
      rationaleId: 'bioc_methyl:granges_handoff' },
    { kind: 'marker', id: 'bioc_methyl_grset_done' },

    // ── Phase C · DMP calling ────────────────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'm3', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'C', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase C · per-CpG DMP test — limma eBayes on **M-values** (logit β), design `~ group`.' },
    { kind: 'marker', id: 'bioc_methyl_C_run' },
    { t: 1300, kind: 'phaseUpdate', id: 'C', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'm3', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: '→ `data.frame` of 12,403 significant CpGs (FDR < 0.05). Passing to bumphunter for regional analysis.' },

    // ── Phase D · DMR calling → GRanges ──────────────────────────
    { t: 400,  kind: 'planUpdate', id: 'm4', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'D', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'wf', m: 'Phase D · `bumphunter` — collapsing adjacent CpGs into regions (1000 bootstraps).' },
    { t: 1400, kind: 'phaseUpdate', id: 'D', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'm4', status: 'done' },
    { t: 0,    kind: 'chatLine', s: 'wf', m: '→ `GRanges` of 847 DMRs. Passing to missMethyl for enrichment.' },
    { kind: 'marker', id: 'bioc_methyl_dmr_done' },

    // ── Phase E · CpG-bias-corrected GO — teaching beat ──────────
    { t: 400,  kind: 'planUpdate', id: 'm5', status: 'running' },
    { t: 0,    kind: 'phaseUpdate', id: 'E', status: 'running' },
    { t: 200,  kind: 'chatLine', s: 'qc', k: 'qc-err',
      lead: 'A trap to avoid: CpG-density bias',
      explain: true,
      m: 'A normal GO enrichment (clusterProfiler / topGO) would be biased here. CpG-dense promoters carry more probes on the 450k array, so they look over-represented for purely technical reasons — inflating CpG-rich gene sets.',
      why: 'Standard enrichment assumes every gene is equally likely to be hit. On a methylation array that isn’t true: genes with more CpG probes are more likely to land a hit by chance, so the p-values are miscalibrated.' },
    { t: 600,  kind: 'chatLine', s: 'agent',
      lead: 'The fix: correct for CpG count',
      explain: true,
      m: 'So I use **`missMethyl::gometh`** instead: it weights each gene by how many CpGs it has, cancelling the array bias so the enrichment p-values are calibrated.',
      rationaleId: 'bioc_methyl:cpg_bias' },
    { kind: 'marker', id: 'bioc_methyl_cpg_warn' },
    { t: 1200, kind: 'phaseUpdate', id: 'E', status: 'completed' },
    { t: 0,    kind: 'planUpdate', id: 'm5', status: 'done' },

    // ── Done ─────────────────────────────────────────────────────
    { t: 0,    kind: 'runState', value: 'completed' },
    { t: 200,  kind: 'section', n: 4, total: 4, title: 'What we found' },
    { t: 0,    kind: 'chatLine', s: 'find', m: '**847 DMRs** · top term: developmental / morphogenesis pathways (CpG-corrected p.adj 3.4e-8).' },
    { t: 200,  kind: 'showCard', card: 'findings', data: {
        title: '847 DMRs · CpG-bias-corrected enrichment',
        runtime: '13m 22s', samples: 24,
        rows: [
          ['Significant CpGs (DMPs)', '12,403'],
          ['DMRs (bumphunter)',       '847'],
          ['Backbone object',         'GenomicRatioSet → GRanges'],
          ['Enrichment',              'missMethyl gometh (CpG-corrected)'],
          ['Outputs',                 'DMP table · DMR GRanges · GO table'],
        ],
    }},
    { kind: 'marker', id: 'bioc_methyl_done' },
  ],
};


window.RESEARCH_SCENARIOS = {
  rnaseq:     SCEN_RNASEQ,
  bioc_kb:    SCEN_BIOC_KB,
  bioc_sc:    SCEN_BIOC_SC,
  bioc_methyl: SCEN_BIOC_METHYL,
  drugscreen: SCEN_DRUGSCREEN,
  variant:    SCEN_VARIANT,
  // v1 adapters — make the four legacy scenarios render in the new chat surfaces
  cryosparc:  SCEN_CRYOSPARC,
  gatk:       SCEN_GATK,
  admet:      SCEN_ADMET,
  nfcore:     SCEN_NFCORE,
};

// ── Phase-trace lookup (Surface 3 expansion data) ─────────────────
// Mapped by (scenarioId, phaseId). The engine reads this to populate
// the "Why this step / Live events / Parameters / Cost" sub-sections.
window.RESEARCH_PHASE_TRACE = {
  'bioc_kb:routing': {
    rationale: {
      text: 'DESeq2 and edgeR model raw integer counts with the negative-binomial distribution. The input here is a raw count matrix, so DESeq2 is in its native regime. limma/voom is the canonical Bioconductor tool when data are continuous (microarray log\u2082 intensities, or pre-normalised values) — applying a count model there violates the distributional assumptions.',
      cite: { title: 'Love et al. (2014) Genome Biology 15:550 · limma User\u2019s Guide §7', href: '#' },
    },
  },
  'bioc_kb:dds_handoff': {
    rationale: {
      text: 'DESeqDataSet is the S4 object that carries the raw count matrix, colData (sample metadata), the design formula and the estimated size factors. Every downstream DESeq2 function operates on this one object — the immutable-input pattern prevents accidental use of pre-normalised values, and is why the packages in the chain compose cleanly.',
      cite: { title: 'Love et al. (2014) Genome Biology 15:550', href: '#' },
    },
  },
  'bioc_kb:apeglm_why': {
    rationale: {
      text: 'Maximum-likelihood log2 fold-change estimates are noisy for low-count genes. apeglm applies an adaptive t-prior: high-variance (low-count) genes are shrunk toward zero while well-powered genes are barely moved. This matters because the next step ranks genes for gene-set enrichment (gseGO) — un-shrunk extreme LFCs from low-count genes would pollute the ranking.',
      cite: { title: 'Zhu et al. (2019) Bioinformatics 35:2084', href: '#' },
    },
  },
  'bioc_sc:routing': {
    rationale: {
      text: 'The OSCA (Orchestrating Single-Cell Analysis) stack is the Bioconductor-native path: a SingleCellExperiment held by scran (normalisation, variance modelling, clustering) and scater (QC, dimensionality reduction). It is chosen here over Seurat because the request ends in a DESeq2 pseudobulk DE step — keeping a SingleCellExperiment throughout means aggregateAcrossCells hands a SummarizedExperiment straight to DESeq2 with no lossy object conversion.',
      cite: { title: 'Amezquita et al. (2020) Nature Methods 17:137 · OSCA book', href: '#' },
    },
  },
  'bioc_sc:sce_handoff': {
    rationale: {
      text: 'SingleCellExperiment extends SummarizedExperiment with slots for reduced dimensions (PCA/UMAP), alternative experiments (e.g. spike-ins) and per-cell size factors, all aligned to the same cells. Because every package in the OSCA chain reads and writes this one object, QC metrics, HVGs, cluster labels and annotations accumulate on it in place — and aggregateAcrossCells can later collapse it to pseudobulk while preserving the colData needed for the DESeq2 design.',
      cite: { title: 'Amezquita et al. (2020) Nature Methods 17:137', href: '#' },
    },
  },
  'bioc_sc:pseudobulk_why': {
    rationale: {
      text: 'Cells from the same sample are not independent replicates — treating each of ~9,800 cells as a replicate is pseudoreplication and dramatically inflates the false-positive rate (DE p-values collapse toward zero regardless of true effect). The fix is pseudobulk: aggregateAcrossCells sums raw counts within each sample × cell-type group, recovering one profile per biological replicate, which is then modelled with DESeq2 exactly as in the bulk case. The replicate unit becomes the 6 samples, not the cells.',
      cite: { title: 'Squair et al. (2021) Nature Communications 12:5692 · Crowell et al. (2020) muscat', href: '#' },
    },
  },
  'bioc_methyl:routing': {
    rationale: {
      text: 'minfi is the canonical Bioconductor entry point for Illumina methylation arrays: it reads raw IDAT pairs with the 450k/EPIC manifest and produces a genomic object whose probes carry their chromosomal coordinates. That is what makes regional (DMR) analysis possible downstream — a count- or matrix-based tool would lose the probe-to-genome mapping that bumphunter needs to collapse adjacent CpGs into regions.',
      cite: { title: 'Aryee et al. (2014) Bioinformatics 30:1363', href: '#' },
    },
  },
  'bioc_methyl:granges_handoff': {
    rationale: {
      text: 'GenomicRatioSet is a SummarizedExperiment whose rows are a GRanges — each CpG probe carries its genomic coordinate alongside its β/M-value. Because the coordinate travels with the data, the per-CpG DMP results can be handed to bumphunter as a coordinate-aware object, which collapses adjacent significant CpGs into differentially methylated regions (a GRanges of DMRs). The shared genomic backbone is why the minfi → limma → bumphunter → missMethyl chain composes without re-annotating probes at each step.',
      cite: { title: 'Aryee et al. (2014) Bioinformatics 30:1363', href: '#' },
    },
  },
  'bioc_methyl:cpg_bias': {
    rationale: {
      text: 'Standard GO over-representation (clusterProfiler, topGO) treats every gene as equally likely to be hit. But on the 450k array, CpG-dense gene promoters carry far more probes, so any DMR list is biased toward CpG-rich gene sets — naive enrichment then reports those terms as significant by construction. missMethyl::gometh models the number of CpGs per gene as a prior probability of selection, correcting the bias so the enrichment p-values are calibrated.',
      cite: { title: 'Phipson et al. (2016) Bioinformatics 32:1165', href: '#' },
    },
  },
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
