/* Fixtures for the two modules added from the Aug-2026 design doc:
   Part A2 — the input panel & interaction panel, brought into the project.
   Part A3 — machine learning: training, adaptation, inference. */

/* ── A2: the workflow card, before a run ─────────────────── */
window.WF_CARD = {
  name:'Bulk RNA-seq Differential Expression',
  domain:'Transcriptomics',
  version:'v1.4.2',
  why:'Proposed from the two files you selected in this project, and constrained by the project instructions.',
  slots:[
    { k:'counts matrix', req:true, ds:'d1', note:'from this project · uploads/' },
    { k:'sample design', req:true, ds:'d2', note:'from this project · uploads/' },
    { k:'reference annotation', req:true, ds:null, note:'GENCODE v44 — license acceptance required before it can be used', license:true },
    { k:'gene set collection', req:false, ds:null, note:'optional — only needed if enrichment runs in the same job' }
  ],
  params:[
    { k:'Species / build', v:'human · GRCh38 (Ensembl 110)', src:'project instructions',
      why:'Standing instruction 1 fixes the build for this project, so it is not inferred per run.', cite:'Fibrosis target triage · instruction 1' },
    { k:'Design formula', v:'~ condition + batch', src:'recommended',
      why:'The design file carries a batch column with two samples missing; including batch costs one degree of freedom but removes a visible batch split in the PCA.', cite:'Love, Huber & Anders 2014 · DESeq2' },
    { k:'Reference level', v:'control', src:'inferred',
      why:'Chosen so effect signs read as treated-vs-control. Taken from the condition column after the two spellings of “control” were merged.', cite:'design.csv · v3' },
    { k:'LFC shrinkage', v:'apeglm', src:'recommended',
      why:'With 12 samples per arm, shrinkage keeps ranking stable for low-count genes without biasing large effects.', cite:'Zhu, Ibrahim & Love 2019' },
    { k:'Alpha (FDR)', v:'0.05', src:'project instructions',
      why:'Instruction 2 requires FDR < 0.05 with the test named; nominal p-values may not be headline numbers.', cite:'Fibrosis target triage · instruction 2' },
    { k:'Minimum library size', v:'8 M reads', src:'recommended',
      why:'The floor two samples fall below. Instruction 3 says to exclude rather than impute, so the gate is set to exclude and report.', cite:'internal QC baseline · 41 runs' }
  ],
  editors:[
    ['toggle','Independent filtering','on','on / off'],
    ['select','Test','Wald','Wald · LRT'],
    ['number','Alpha','0.05','valid 0.001 – 0.20'],
    ['number','Minimum library size (M reads)','8','valid 1 – 40'],
    ['file','Gene set collection','—','pick from project files'],
    ['toggle','Auto-loop quality gates','on','on / off']
  ],
  outputs:[
    ['table','de_results.tsv','ranked genes — becomes a dataset in its own right'],
    ['figure','volcano.png','300 dpi, greyscale-safe, per the project figure spec'],
    ['report','after-run.pdf','findings · methods · parameters · citations · QC audit']
  ]
};

/* live phases for the interaction panel */
window.RUN_PHASES = [
  { id:'A', name:'Input & preparation', steps:['reads staged (24 samples)','nf-core/rnaseq alignment','count matrix assembled'], t:'6 min 40 s' },
  { id:'B', name:'Quality gates', steps:['contamination & relatedness','library-size floor','design consistency'], t:'2 min 05 s' },
  { id:'C', name:'Differential abundance', steps:['DESeq2 Wald fit','apeglm shrinkage','FDR correction'], t:'21 min 12 s' },
  { id:'D', name:'Report', steps:['figures to the project spec','report written to the memo template'], t:'3 min 58 s' }
];
window.QC_GATE = {
  gate:'Library-size floor · phase B',
  measured:[['Samples below floor','2 of 24','threshold: 0'],['Lowest library size','3.7 M reads','floor: 8 M reads'],['Effect stability without them','ρ = 0.97','acceptable: ≥ 0.90']],
  evidence:'strong — 41 previous runs on this baseline',
  before:'minimum library size = 8 M · action = halt',
  after:'minimum library size = 8 M · action = exclude 2 samples and list them in the report',
  rationale:'Standing instruction 3 says exclude rather than impute, and list every exclusion. The suggestion applies that instruction instead of stopping the run.'
};

/* ── A3: training ────────────────────────────────────────── */
window.MODEL_FAMILIES = [
  ['Language model','including reinforcement fine-tuning','document drafting, extraction, review'],
  ['Tabular AutoML','feature search + model selection','assay tables, clinical endpoints'],
  ['Diffusion','including single-cell','generative perturbation, augmentation'],
  ['Molecular property','graph & descriptor models','potency, ADMET, selectivity']
];
window.TRAIN_LOOP = [
  ['Dataset','a dataset object from your data — the same object the workflows use','de_results.tsv · 18,402 × 7'],
  ['Train','same cloud compute as a workflow run, same live phases','12 min elapsed'],
  ['Quality gate','held-out evaluation with a threshold, not a leaderboard','AUC 0.81 vs 0.75 floor'],
  ['Tracking','every run recorded: dataset version, params, metrics, artefacts','experiment 14 of 14'],
  ['Register','the trained model becomes a callable object','admet-herg · v3']
];
window.TRAIN_RUNS = [
  { name:'hERG liability — molecular property', family:'Molecular property', status:'running', when:'today', metric:'AUC 0.81 (held-out)', gate:'gate pending · floor 0.75', ds:'assay_2026_08.csv', v:'v3 candidate' },
  { name:'Endpoint response — tabular AutoML', family:'Tabular AutoML', status:'completed', when:'15 Aug', metric:'AUC 0.78 · calibration 0.04', gate:'2 / 2 gates passed', ds:'cohort_variants.vcf.gz', v:'registered as endpoint-resp v1' },
  { name:'IND section drafting — RFT', family:'Language model', status:'failed', when:'13 Aug', metric:'reward plateaued at 0.42', gate:'blocked at eval gate', ds:'edit pairs · 214', v:'not registered' }
];

/* ── A3: adaptation ─────────────────────────────────────── */
/* The run card is not one fixture. A composer request routed to a lane and a
   domain must open a panel that matches what it just promised — a biologics
   design request may not be answered with reference-build questions. Each entry
   overrides only what differs; anything unset falls back to WF_CARD. */
(() => {
  const S = (k, req, note, extra) => Object.assign({ k:k, req:req, ds:null, note:note }, extra || {});
  const P = (k, v, src, why) => ({ k:k, v:v, src:src, why:why });
  const card = (name, domain, slots, params) => ({ name:name, domain:domain, slots:slots, params:params,
    why:'Proposed from what you asked for, and constrained by this project’s standing instructions.' });
  const design = (name, what, unit) => Object.assign(card(name, 'Design', [
    S('target or epitope', true, 'the thing candidates are proposed against'),
    S(what + ' to stay on', false, 'optional — leave empty for unconstrained ' + unit + ' generation'),
    S('property envelope', true, 'the constraints a candidate must satisfy to be kept'),
    S('exclusion rules', false, 'motifs or chemistry your group will not make')], [
    P('Modality', unit, 'from your request', 'Set by the request; it decides which generator and which scorers are callable.'),
    P('Candidates to propose', '500', 'recommended', 'Enough to survive filtering without a queue nobody reads.'),
    P('Hard constraints', 'from the property envelope', 'project instructions', 'A constraint is a rejection, not a soft score — a breach never reaches the shortlist.'),
    P('Scoring models', 'registry · named per score', 'resolved', 'Every predicted number carries the model and version that produced it.')]),
    { kind:'Design run', version:'design pipeline v3.1', mod:true, phases:designPhases(unit) });
  const PH = (names, times) => names.map((n, i) => ({ id:'ABCD'[i], name:n[0], steps:n[1], t:times[i] }));
  const designPhases = unit => PH([
    ['Input & constraints', ['target and envelope resolved', 'exclusion rules compiled', 'scorers pinned by version']],
    ['Generation', ['candidates proposed', 'validity and duplication filtered', 'de-duplicated against our own series']],
    ['Scoring & constraints', ['activity predicted with confidence', 'developability scored', 'constraint breaches rejected with reasons']],
    ['Shortlist & report', ['ranked under your criteria', 'report written to the memo template']]],
    ['1 min 10 s', '4 min 20 s', '6 min 05 s', '2 min 40 s']);
  const modelPhases = PH([
    ['Input & split', ['data version resolved', 'scaffold split built', 'censored values separated']],
    ['Fit', ['features computed', 'model fitted', 'uncertainty calibrated']],
    ['Held-out evaluation', ['metrics against the floor', 'applicability region estimated', 'out-of-region behaviour checked']],
    ['Gate & offer', ['gate decision recorded', 'report written; registration offered']]],
    ['2 min 05 s', '19 min 40 s', '4 min 30 s', '1 min 50 s']);
  window.WF_BY_DOM = {
    'Molecular design': design('De novo candidate design', 'scaffold', 'small molecule'),
    'Peptide design': design('Peptide design & optimisation', 'sequence motif', 'peptide'),
    'Protein & biologic design': design('Protein / biologic design', 'framework', 'protein'),
    'Property optimisation': design('Multi-objective property optimisation', 'series', 'small molecule'),
    'Activity prediction': design('Activity prediction on a candidate set', 'candidate set', 'small molecule'),
    'Candidate ranking': design('Candidate triage', 'candidate set', 'small molecule'),
    'Data analysis': Object.assign(card('Ad-hoc analysis in a sandbox', 'Sandbox', [
      S('the table or file to work on', true, 'read from this project — a version, not a filename'),
      S('what to compute or plot', true, 'your sentence; the code written from it is shown before it runs'),
      S('output destination', false, 'optional — stays in the chat unless you save it as a file')], [
      P('Environment', 'Python 3.12 · pandas, numpy, matplotlib', 'fixed', 'A pinned environment, so the same code gives the same numbers next month.'),
      P('Network', 'isolated — no outbound access', 'fixed', 'The sandbox cannot reach the internet or another project’s files.'),
      P('Code', 'shown before it runs', 'fixed', 'An ad-hoc number is only as trustworthy as the code behind it, so the code is part of the answer.'),
      P('Provenance', 'saved outputs become files with versions', 'resolved', 'A plot you keep is a file object, not an image in a transcript.')]),
      { kind:'Ad-hoc · sandbox', version:'sandbox', phases:PH([
        ['Read the data', ['file version resolved', 'columns and types inspected']],
        ['Write the code', ['code drafted from your sentence', 'shown to you before running']],
        ['Run in the sandbox', ['executed with no network access', 'result and any warnings returned']],
        ['Keep or discard', ['saved as a project file only if you say so']]],
        ['0 min 04 s', '0 min 06 s', '0 min 09 s', '—']) }),
    'Drug discovery': Object.assign(card('ADMET liability screen', 'Drug discovery', [
      S('compound set', true, 'SMILES or a registry export'),
      S('liability panel', true, 'which endpoints to screen — hERG first, per this project'),
      S('internal thresholds', false, 'optional — defaults to the project’s safety floors')], [
      P('Endpoints', 'hERG · solubility · microsomal stability', 'project instructions', 'The order matters: a hERG failure stops the rest rather than paying for it.'),
      P('hERG floor', '30 µM', 'project instructions', 'The project’s own floor, not a model default.'),
      P('Confidence handling', 'out-of-region predictions cannot gate', 'resolved', 'A confident number outside the applicability region is not offered as one.')]),
      { version:'ADMET screen v2.4', phases:PH([
        ['Input & panel', ['compound set parsed', 'liability panel resolved', 'thresholds read from instructions']],
        ['Screening', ['hERG scored', 'solubility scored', 'metabolic stability scored']],
        ['Gates', ['project floors applied', 'out-of-region predictions flagged']],
        ['Triage & report', ['developability ranking', 'report written to the memo template']]],
        ['1 min 05 s', '8 min 10 s', '1 min 20 s', '2 min 30 s']) }),
    'Genomics': Object.assign(card('Variant calling & annotation', 'Genomics', [
      S('read alignments or FASTQ', true, 'per sample'),
      S('reference build', true, 'GRCh38 · fixed by instruction 1'),
      S('panel or region list', false, 'optional — whole genome if empty')], [
      P('Species / build', 'human · GRCh38 (Ensembl 110)', 'project instructions', 'Fixed for this project, so it is not inferred per run.'),
      P('Caller', 'DeepVariant', 'recommended', 'Chosen for this read type; the alternative is named in the methods.'),
      P('Filtering', 'hard filters, then VQSR', 'recommended', 'Two stages, so a borderline call stays visible instead of being dropped silently.')]),
      { version:'variant pipeline v5.0', phases:PH([
        ['Input & preparation', ['reads staged', 'alignment', 'duplicates marked']],
        ['Quality gates', ['contamination & relatedness', 'coverage floor', 'sex-check consistency']],
        ['Calling & annotation', ['variants called', 'hard filters then VQSR', 'annotation applied']],
        ['Report', ['clinically relevant calls flagged', 'report written']]],
        ['12 min 30 s', '3 min 10 s', '18 min 40 s', '2 min 20 s']) }),
    'Proteomics': Object.assign(card('Differential protein abundance', 'Proteomics', [
      S('spectra or a quant matrix', true, 'per run or per plex'),
      S('sample design', true, 'groups and any batch structure'),
      S('protein database', true, 'the search space — version recorded')], [
      P('Quantification', 'MaxLFQ', 'recommended', 'Stable across missing values without imputing them.'),
      P('Missing values', 'kept as missing', 'project instructions', 'Imputation would invent measurements; the count is reported instead.'),
      P('Alpha (FDR)', '0.05', 'project instructions', 'Instruction 2 requires FDR < 0.05 with the test named.')]),
      { version:'proteomics pipeline v3.3', phases:PH([
        ['Input & search', ['spectra staged', 'database search', 'FDR-controlled identification']],
        ['Quality gates', ['run-to-run consistency', 'missingness reported, not imputed']],
        ['Quantification', ['MaxLFQ quantification', 'differential abundance fit', 'FDR correction']],
        ['Report', ['figures to the project spec', 'report written']]],
        ['9 min 20 s', '2 min 00 s', '11 min 05 s', '2 min 40 s']) }),
    'Clinical': Object.assign(card('Cohort stratification & endpoint test', 'Clinical', [
      S('cohort table', true, 'one row per subject'),
      S('statistical analysis plan', true, 'the pre-specified plan this run is checked against'),
      S('covariate list', false, 'optional — adjusted model only')], [
      P('Primary endpoint', 'from the analysis plan', 'pre-specified', 'Read from the plan, never chosen by the run.'),
      P('Stratification', 'as pre-specified', 'pre-specified', 'A post-hoc subgroup is reported as post-hoc, never as the primary result.'),
      P('Multiplicity', 'per plan', 'pre-specified', 'The correction is the plan’s, not a default.')]),
      { version:'cohort analysis v2.1', phases:PH([
        ['Input & plan', ['cohort table read', 'analysis plan parsed', 'endpoint bound from the plan']],
        ['Quality gates', ['completeness by site', 'eligibility checks']],
        ['Endpoint analysis', ['pre-specified test', 'multiplicity correction', 'subgroups marked post-hoc']],
        ['Report', ['tables to the submission template', 'report written']]],
        ['0 min 50 s', '1 min 30 s', '3 min 40 s', '2 min 10 s']) }),
    'Structural biology': Object.assign(card('Map & model assessment', 'Structural biology', [
      S('density map or micrographs', true, 'the experimental data'),
      S('model or sequence', true, 'what is being fitted or predicted'),
      S('symmetry', false, 'optional — C1 if empty')], [
      P('Resolution estimate', 'FSC 0.143', 'recommended', 'Reported with the mask used, since the number means little without it.'),
      P('Model-to-map', 'per-residue fit + Q-score', 'recommended', 'A global number hides local misfit, so both are reported.'),
      P('Prediction use', 'only where the map is unresolved', 'project instructions', 'A prediction never overwrites measured density.')]),
      { version:'structure assessment v4.2', phases:PH([
        ['Input & preparation', ['map or micrographs staged', 'mask built', 'model or sequence read']],
        ['Quality gates', ['resolution estimate with its mask', 'model geometry checks']],
        ['Fit & assessment', ['model-to-map fit per residue', 'Q-score computed', 'unresolved regions marked']],
        ['Report', ['figures to the project spec', 'report written']]],
        ['5 min 10 s', '2 min 40 s', '9 min 30 s', '2 min 05 s']) }),
    'Assay quality': Object.assign(card('Run-to-run quality assessment', 'Assay quality', [
      S('plate readouts', true, 'the batch to assess'),
      S('control layout', true, 'which wells are controls'),
      S('historical baseline', false, 'optional — the project’s own 41-run baseline if empty')], [
      P('Metrics', 'Z′ · CV · drift across plates', 'recommended', 'Drift is what catches a failing lot; a single Z′ does not.'),
      P('Baseline', 'internal · 41 runs', 'resolved', 'Compared against your own history, not a literature figure.'),
      P('Failing lots', 'flagged, results down-weighted', 'project instructions', 'A suspect lot is recorded on every result it touched.')]),
      { version:'assay QC v1.9', phases:PH([
        ['Input & controls', ['plate readouts staged', 'control layout resolved']],
        ['Metrics', ['Z′ per plate', 'CV per control', 'drift across the batch']],
        ['Baseline comparison', ['compared against 41 internal runs', 'failing lots flagged']],
        ['Report', ['down-weighted results listed', 'report written']]],
        ['0 min 40 s', '1 min 50 s', '1 min 10 s', '1 min 30 s']) }),
    'Models & training': Object.assign(card('Model training run', 'Models', [
      S('training data', true, 'a file version in this project — not a filename'),
      S('held-out split', true, 'scaffold or site split, so a series cannot leak'),
      S('evaluation floor', true, 'what the model must clear before it is offered to you')], [
      P('Split', 'scaffold · 70/15/15', 'recommended', 'A random split leaks a series between train and test.'),
      P('Censored values', 'fitted as inequalities', 'project instructions', 'An IC50 > 30 µM is never coerced to 30.'),
      P('Registration', 'offered, never automatic', 'fixed', 'A passing model is offered for registration; nothing is registered silently.')]),
      { kind:'Training run', version:'training harness v2.0', phases:modelPhases })
  };
  window.WF_BY_DOM['Structure prediction'] = window.WF_BY_DOM['Sequence scoring'] =
    window.WF_BY_DOM['Library screening'] = window.WF_BY_DOM['Optimisation loop'] = window.WF_BY_DOM['Models & training'];
  /* One design card, told which modality it is working on. */
  window.wfFor = (dom, mod) => {
    const base = Object.assign({}, window.WF_CARD, (dom && window.WF_BY_DOM[dom]) || {});
    if (!base.mod || !mod) return base;
    const stay = mod === 'peptide' ? 'sequence motif' : mod === 'protein' ? 'framework' : 'scaffold';
    return Object.assign({}, base, {
      slots:base.slots.map(s => /to stay on$/.test(s.k)
        ? Object.assign({}, s, { k:stay + ' to stay on', note:'optional — leave empty for unconstrained ' + mod + ' generation' }) : s),
      params:base.params.map(x => x.k === 'Modality' ? Object.assign({}, x, { v:mod }) : x)
    });
  };
})();

window.ADAPT_LEVELS = [
  ['Prompt-level rules','cheapest · instant','8 rules learned from repeated edits','active'],
  ['Few-shot memory','cheap · seconds to index','214 before→after pairs indexed','active'],
  ['Fine-tuned adapter','costly · a training job','last built 11 Aug from 180 pairs','off']
];
window.EDIT_PAIRS = [
  { doc:'IND · Module 2.6.2 pharmacology', when:'16 Aug', before:'The compound showed good efficacy in the mouse model.',
    after:'In the bleomycin-induced mouse model, the compound reduced Ashcroft score by 2.1 points (95% CI 1.4–2.8).', learned:'Replace qualitative efficacy claims with the effect size and its interval.', scope:'organisation', on:true },
  { doc:'Target triage memo', when:'15 Aug', before:'fold-change of 7.2×',
    after:'log2FC 2.84', learned:'This team writes effect sizes, not fold-change language.', scope:'organisation', on:true },
  { doc:'IND · Module 2.6.4 toxicology', when:'14 Aug', before:'No adverse findings were noted.',
    after:'No test-article-related adverse findings were noted at doses up to 300 mg/kg/day.', learned:'Always bound a negative finding by the dose tested.', scope:'organisation', on:true },
  { doc:'Series 4 liabilities', when:'12 Aug', before:'hERG risk is low.',
    after:'Predicted hERG IC50 > 30 µM (model admet-herg v2, medium confidence).', learned:'Name the model and confidence when reporting a prediction.', scope:'this project only', on:false }
];
window.DMTA = {
  state:'running',
  round:4,
  rounds:[
    ['Round 4','proposing','96 compounds re-scored · 12 proposed for assay','today'],
    ['Round 3','assay results in','24 tested · 5 improved on potency, 2 on hERG','14 Aug'],
    ['Round 2','complete','24 tested · surrogate refit, MAE 0.41 → 0.33','9 Aug'],
    ['Round 1','complete','baseline library scored from literature only','2 Aug']
  ],
  surrogate:'admet-herg v3 + potency-gp v2',
  /* refit policy lives in WETLAB.refit — one source, since the trigger is a
     wet-lab event, not a compute event */
  proposal:[
    ['BM-4471','potency 8.4 · hERG > 30 µM','high confidence','accepted'],
    ['BM-4488','potency 8.1 · hERG 18 µM','medium confidence','flagged by the safety gate'],
    ['BM-4502','potency 7.9 · hERG > 30 µM','high confidence','accepted'],
    ['BM-4519','potency 8.8 · hERG 6 µM','high confidence','rejected by the safety gate']
  ]
};

/* ── A3: inference ──────────────────────────────────────── */
window.REGISTRY = [
  { name:'admet-herg', v:'v3', family:'Molecular property', plug:'Python function', by:'trained here · 16 Aug', used:'ADMET screen · safety gate · DMTA scoring', conf:'high' },
  { name:'endpoint-resp', v:'v1', family:'Tabular AutoML', plug:'Python function', by:'trained here · 15 Aug', used:'Clinical stratification workflow', conf:'medium' },
  { name:'potency-gp', v:'v2', family:'Molecular property', plug:'Container', by:'your lab · imported 4 Aug', used:'DMTA scoring', conf:'high' },
  { name:'struct-conf', v:'v7', family:'External service', plug:'REST endpoint', by:'vendor · contract to Mar 2027', used:'Structure confidence in cryo-EM runs', conf:'medium' },
  { name:'fold-predict', v:'v2.3', family:'Protein structure', plug:'Python function', by:'open-source · integrated, weights pinned', used:'Fold prediction · cryo-EM gap filling', conf:'high' },
  { name:'molgen', v:'v4.1', family:'Generative chemistry', plug:'Python function', by:'public base · your adapter as a delta', used:'Series 4 generation', conf:'medium' }
];
window.PLUG_WAYS = [
  ['Python function','a scored() entry point in your package','no container build; runs in the workflow sandbox'],
  ['Container','your own image and dependencies','for models with a fixed environment or GPU needs'],
  ['REST endpoint','a URL and a key','for vendor or internal services you do not host here']
];
window.INFER_USES = [
  ['Scoring','virtual library ranking in a campaign','DMTA round 4 · 96 compounds'],
  ['Safety / QC gates','a prediction can halt a run','ADMET gate rejected 1 of 12 proposals'],
  ['Auto-proposal','the closed loop reads the same predictions','next round proposed automatically']
];

/* Which surfaces a project has earned — nothing in the nav is advertised
   because the product has the feature; it appears because this project uses it. */
window.PROJECT_CAPS = {
  'Fibrosis target triage': { runs:['r1','r2','r3'], ml:false, ind:false },
  'MG stratification':      { runs:[], ml:false, ind:true },
  'ADMET screen — series 4':{ runs:['r1'], ml:true, ind:false },
  'Cryo-EM batch 12':       { runs:[], ml:false, ind:false },
  default:                  { runs:[], ml:false, ind:false }
};
window.PROJECT_RUNS = {
  'Fibrosis target triage': [
    { id:'pr1', name:'Bulk RNA-seq differential expression', status:'completed', when:'14 Aug', from:'started in “Paired-end RNA-seq analysis”', gates:'gate 2 halted · suggestion applied' },
    { id:'pr2', name:'GO enrichment', status:'failed', when:'15 Aug', from:'started from de_results.tsv in Files', gates:'blocked at gate 2' },
    { id:'pr3', name:'Pathway scoring', status:'running', when:'today', from:'started in “Paired-end RNA-seq analysis”', gates:'gates pending' }
  ],
  'ADMET screen — series 4': [
    { id:'pr4', name:'ADMET liability screen', status:'completed', when:'8 Aug', from:'started in “Series 4 liabilities”', gates:'4 / 4 gates passed' }
  ],
  default: []
};

/* A chat cannot exist outside a project. Quick questions land in a scratch
   project you never had to name, promotable later. */
window.PROJECTS.push({ name:'Unfiled (scratch)', datasets:0, scratch:true, chats:[] });
window.PROJECT_CAPS['Unfiled (scratch)'] = { runs:[], ml:false, ind:false };
