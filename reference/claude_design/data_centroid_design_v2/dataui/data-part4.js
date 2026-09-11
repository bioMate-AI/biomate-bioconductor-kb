/* Part 4 — fixtures for the eight update asks.
   Pre-trained inference, domain viewers, typed clarification, skip
   dependencies, human approval, agent trajectory, roles. */

/* ── Gap 1: pre-trained DL inference ──────────────────────────────────────
   Presented as achievements, not a package list — the no-inventory rule
   applies here exactly as it does to workflows. Three per domain, editorial. */
window.INFER = [
  { id:'struct', dom:'Structure prediction', goal:'Predict a structure and tell me where to trust it',
    out:'3D structure · per-residue confidence · pairwise error', t:'~8 min', ev:'perceptual + quantitative',
    ex:['Predict the fold of this sequence and show me where the model is unsure.',
        'Model this complex and tell me whether the predicted interface is reliable.',
        'Does this mutation change the predicted binding site?'] },
  { id:'geno', dom:'Genomic sequence models', goal:'Score a sequence and find what stands out',
    out:'per-base scores as tracks · flagged intervals', t:'~4 min', ev:'quantitative',
    ex:['Score this locus with the sequence model and mark what stands out.',
        'Which variants here look functionally consequential?',
        'Compare the predicted regulatory signal between these two haplotypes.'] },
  { id:'chem', dom:'Chemical screening models', goal:'Rank a library against a target',
    out:'ranked hits · 2D depictions · per-hit confidence', t:'~11 min', ev:'symbolic + quantitative',
    ex:['Screen this library against my target and rank the predicted hits.',
        'Which of these scaffolds does the model prefer, and why?',
        'Re-rank these hits with the safety model applied.'] }
];
/* A pre-trained model object differs from a trained one in exactly two ways:
   its evidence is published rather than held-out here, and it has no lineage
   into our data. Both are stated rather than hidden. */
window.INFER_MODEL = {
  name:'structure-predict', v:'v2.4', family:'Pre-trained · structure prediction',
  origin:'open-source · integrated, not trained here',
  evidence:[['Published benchmark', 'reported by the authors', 'CASP-class targets', 'external'],
            ['Local spot-check', '0.84 correlation on 40 internal structures', 'floor 0.80', 'pass'],
            ['Calibration of confidence', 'pLDDT tracks observed error', 'checked on our set', 'pass']],
  note:'Its evidence is published, not held out on your data — so the local spot-check is what earns it a gate here.'
};

/* Per-residue confidence. Generated so the chart is real data, not decoration. */
window.PLDDT = (() => {
  const n = 148, a = [];
  for (let i = 0; i < n; i++) {
    const loop = (i > 42 && i < 58) || (i > 104 && i < 116);
    const term = i < 5 || i > n - 7;
    let v = loop ? 54 + 18 * Math.sin(i * 0.7) : term ? 40 + 14 * Math.cos(i * 0.9) : 84 + 11 * Math.sin(i * 0.35);
    a.push(Math.max(22, Math.min(98, Math.round(v))));
  }
  return a;
})();
window.PLDDT_REGIONS = [
  { from:43, to:57, label:'Loop 43–57', why:'Low confidence — flexible loop, no template coverage.' },
  { from:105, to:115, label:'Loop 105–115', why:'Low confidence — disordered in every deposited homologue.' },
  { from:60, to:98, label:'Core 60–98', why:'High confidence — this is the region a binding-site claim can rest on.' }
];
/* Pairwise alignment error, coarse-binned for a legible heatmap. */
window.PAE = (() => {
  const n = 24, m = [];
  for (let i = 0; i < n; i++) { const row = [];
    for (let j = 0; j < n; j++) {
      const d = Math.abs(i - j);
      const dom = (i < 10 && j < 10) || (i >= 13 && j >= 13);
      row.push(Math.round(Math.min(30, dom ? 1.5 + d * 0.8 : 9 + d * 1.4)));
    } m.push(row); }
  return m;
})();

/* Genomic score tracks. */
window.TRACKS = {
  locus:'chr7:5,527,100–5,530,600', bp:3500,
  rows:[
    { k:'Model score', kind:'line', d:Array.from({ length:70 }, (_, i) => Math.round(50 + 42 * Math.sin(i / 5.5) * Math.cos(i / 11))) },
    { k:'Conservation', kind:'line', d:Array.from({ length:70 }, (_, i) => Math.round(40 + 30 * Math.cos(i / 7))) },
    { k:'Flagged', kind:'marks', d:[[9, 12], [31, 33], [52, 58]] },
    { k:'Variants', kind:'ticks', d:[6, 11, 12, 30, 32, 44, 55, 56, 61] }
  ],
  flags:[['chr7:5,527,540–5,527,690', 'promoter-proximal', 'score 3.1 sd above local background'],
         ['chr7:5,528,650–5,528,760', 'exonic', 'model disagrees with conservation — worth a look'],
         ['chr7:5,529,700–5,530,000', 'intronic', 'strongest signal in the locus']]
};

/* Ranked hits, with SMILES so a depiction grid has something real to key on. */
window.HITS = [
  { id:'BM-4471', smiles:'CC1=CC(=NO1)C(=O)Nc1ccc(F)cc1', score:8.5, conf:'high', herg:'>30 uM', dl:'4/4', v:'accepted' },
  { id:'BM-4488', smiles:'COc1ccc(cc1)C(=O)N1CCN(CC1)c1ncccn1', score:8.1, conf:'high', herg:'18 uM', dl:'4/4', v:'flagged' },
  { id:'BM-4502', smiles:'FC(F)(F)c1ccc(NC(=O)C2CC2)cc1', score:7.9, conf:'medium', herg:'>30 uM', dl:'4/4', v:'accepted' },
  { id:'BM-4519', smiles:'Nc1nc(nc2n(cnc12)C1CCCO1)N1CCOCC1', score:8.8, conf:'low', herg:'6 uM', dl:'3/4', v:'rejected' },
  { id:'BM-4523', smiles:'CN1CCN(CC1)c1ccc(cc1)S(=O)(=O)N', score:7.4, conf:'medium', herg:'>30 uM', dl:'4/4', v:'accepted' },
  { id:'BM-4541', smiles:'OC(=O)c1cc(Cl)ccc1Oc1ccccc1', score:7.1, conf:'out-of-domain', herg:'—', dl:'4/4', v:'held' }
];

/* ── Gap 2: typed clarification ───────────────────────────────────────────
   Every option carries the value it binds to. Answers select a schema value
   or a workflow id — never a sentence to re-parse. */
window.CLARIFY = {
  n:3,
  qs:[
    { q:'Which reference build?', field:'reference_build', binds:'schema value',
      why:'Your goal said “human” — this workflow needs a specific build, and the two are not interchangeable downstream.',
      opts:[{ label:'GRCh38 · Ensembl 110', val:'GRCh38.p14/ens110', note:'your project instruction 1 says GRCh38', pick:true },
            { label:'GRCh38 · GENCODE 44', val:'GRCh38.p14/gencode44', note:'same build, different annotation' },
            { label:'GRCh37 · Ensembl 75', val:'GRCh37/ens75', note:'legacy — only for re-analysing old cohorts' }] },
    { q:'Which analysis, exactly?', field:'workflow', binds:'workflow id',
      why:'Three validated workflows match your wording. Picking one selects it by id — we do not re-read the sentence.',
      opts:[{ label:'Differential expression (bulk, two conditions)', val:'wf.rnaseq.de.v4', note:'matches “treated vs control”', pick:true },
            { label:'Differential expression with covariates', val:'wf.rnaseq.de.cov.v2', note:'if batch must be modelled' },
            { label:'Transcript-level differential usage', val:'wf.rnaseq.dtu.v1', note:'a different question' }] },
    { q:'What should the run produce?', field:'output_template', binds:'schema value',
      why:'The report is written to a template, and this project has more than one.',
      opts:[{ label:'Internal target-triage memo', val:'tpl.memo.v3', note:'this project’s default output requirement', pick:true },
            { label:'Manuscript figure set', val:'tpl.figset.v2', note:'vector figures to the project figure spec' },
            { label:'Results tables only', val:'tpl.tables.v1', note:'no prose — for feeding another analysis' }] }
  ]
};

/* A clarification only makes sense for the kind of run it is asked about, so
   the set follows the routed domain. Anything unmapped keeps the set above. */
window.CLARIFY_BY_DOM = (() => {
  const q = (question, field, binds, why, opts) => ({ q:question, field:field, binds:binds, why:why,
    opts:opts.map((o, i) => ({ label:o[0], val:o[1], note:o[2], pick:i === 0 })) });
  const design = unit => ({ n:3, qs:[
    q('What is the hard constraint?', 'constraints', 'schema value',
      'A constraint is a rejection, not a soft score — so it has to be stated before anything is proposed.',
      [['Every project safety floor', 'cons.project.v3', 'this project’s own floors, as standing instructions'],
       ['Only the ones I name now', 'cons.adhoc', 'for this run only — the project defaults stay unchanged'],
       ['None — explore freely', 'cons.none', 'proposals may breach a floor, and are labelled as such']]),
    q('How many ' + unit + 's should be proposed?', 'n_candidates', 'schema value',
      'The count decides what you will actually read, and what the scorers will cost.',
      [['500', '500', 'enough to survive filtering'], ['5,000', '5000', 'for a wide first sweep'], ['50', '50', 'a focused set to look at by hand']]),
    q('Which scorers may gate a candidate?', 'gating_models', 'model ids',
      'A model may only reject a candidate if it has held-out evidence and the candidate is inside its applicability region.',
      [['Registered models only', 'models.registered', 'each named, with its version, on every score'],
       ['Include candidate models', 'models.incl_candidates', 'flagged as unregistered wherever a score appears'],
       ['No gating — score only', 'models.score_only', 'nothing is rejected automatically']])] });
  const M = {
    'Molecular design': design('molecule'), 'Property optimisation': design('analogue'),
    'Activity prediction': design('candidate'), 'Candidate ranking': design('candidate'),
    'Peptide design': design('peptide'), 'Protein & biologic design': design('design'),
    'Data analysis': { n:2, qs:[
      q('Which file should this run on?', 'input_file', 'file version',
        'An ad-hoc number is only meaningful against a stated version of a stated file.',
        [['assay_2026_08.csv · v4', 'file.assay.v4', 'the version this project’s runs currently read'],
         ['de_results.tsv · v1', 'file.de.v1', 'the output of the differential-expression run'],
         ['Something I will attach now', 'file.attach', 'it lands in this project as a file with a version']]),
      q('What should happen to the result?', 'keep_policy', 'schema value',
        'A number in a chat cannot be cited; a file can.',
        [['Show it, and let me decide', 'keep.ask', 'nothing is written unless you say so'],
         ['Save it as a project file', 'keep.save', 'becomes a file object with a version and provenance'],
         ['Show it only', 'keep.discard', 'the code and result stay in the transcript']])] },
    'Drug discovery': { n:2, qs:[
      q('Which endpoint decides the triage?', 'primary_endpoint', 'schema value',
        'Screening several endpoints is cheap; deciding on the wrong one is not.',
        [['hERG first, then the rest', 'ep.herg_first', 'this project’s order — a failure stops the rest'],
         ['All endpoints, no ordering', 'ep.parallel', 'costs more, ranks nothing until all return'],
         ['Solubility first', 'ep.sol_first', 'for a formulation-limited series']]),
      q('What happens to an out-of-region prediction?', 'oor_policy', 'schema value',
        'A confident number outside a model’s applicability region is the most common way a screen misleads.',
        [['Report it, but it cannot gate', 'oor.report_nogate', 'the default here'],
         ['Exclude the compound', 'oor.exclude', 'safest, and it hides chemistry you may want'],
         ['Treat it as any other value', 'oor.trust', 'not recommended — recorded in the audit trail']])] },
    'Models & training': { n:2, qs:[
      q('How should the held-out split be made?', 'split', 'schema value',
        'A random split leaks a series between train and test and flatters the model.',
        [['Scaffold split · 70/15/15', 'split.scaffold', 'no series appears on both sides'],
         ['Split by site or batch', 'split.site', 'when the risk is a site effect, not a series effect'],
         ['Random split', 'split.random', 'only for a sanity check — labelled as optimistic']]),
      q('What must it clear to be offered?', 'floor', 'schema value',
        'The floor is set before the run, so a passing model cannot be declared after the fact.',
        [['This project’s floor', 'floor.project', 'the numbers in the standing instructions'],
         ['A stricter floor I name now', 'floor.adhoc', 'for a model that will gate a design loop'],
         ['No floor — report and let me judge', 'floor.none', 'it may not gate anything']])] }
  };
  M['Structure prediction'] = M['Sequence scoring'] = M['Library screening'] = M['Optimisation loop'] = M['Models & training'];
  return M;
})();
window.clarifyFor = dom => (dom && window.CLARIFY_BY_DOM[dom]) || window.CLARIFY;

/* ── Gap 5: skip dependency gating ────────────────────────────────────────
   Skip is a declared workflow capability, DAG-validated — not a universal
   neutral toggle. */
window.SKIPDEP = {
  A:{ skippable:false, why:'Phase B and C read A\u2019s alignments directly. The workflow declares no skip parameter for it.', blocks:['B','C'] },
  B:{ skippable:true, param:'--skip-qc', why:'Declared skippable. Downstream reads the cached QC verdict from the previous run.' },
  C:{ skippable:true, param:'--skip-de', why:'Declared skippable, but D has nothing to enrich without it.', warn:['D'] },
  D:{ skippable:true, param:'--skip-enrich', why:'Declared skippable. Nothing downstream depends on it.' }
};

/* ── Gap 7: human approval ────────────────────────────────────────────────
   The human complement to a QC gate, in the same measured/threshold/verdict
   vocabulary. */
window.APPROVAL = {
  what:'Write this run’s outputs into the project record',
  why:'Phase D publishes counts.tsv v4 and the run report into the project. Two downstream runs read that file, and this version becomes the one future runs resolve by default.',
  cost:'writes counts.tsv v4 + report · notifies 2 downstream runs · reversible for 24 h',
  measured:[['Consumers affected', '2 downstream runs', 'approval required above 1', 'needs approval'],
            ['Overwrites the resolved version', 'writes v4', 'earlier versions kept, never deleted', 'pass'],
            ['Reversible', 'yes · 24 h rollback window', '—', 'pass']],
  who:'You can approve this — you own this project.',
  policy:'Publishing to the project record requires an owner. Overriding a quality gate requires a reviewer.'
};

/* ── Gap 8: agent trajectory ──────────────────────────────────────────────
   The agent-side complement to data lineage: what it decided, what it called,
   what you answered. */
window.TRAJ = [
  { t:'0.0s', kind:'route', k:'Routing decision', d:'Read the goal as a standardised differential-abundance analysis. Chose the validated lane over ad-hoc compute because the goal named a figure.', meta:'lane: Cloud · workflow' },
  { t:'0.4s', kind:'tool', k:'resolve_project_files', d:'Matched 2 of 2 input slots from this project.', meta:'0.4s · 2 results' },
  { t:'1.1s', kind:'clarify', k:'Asked you: reference build', d:'Extractor confidence was low on "human". You answered GRCh38 · Ensembl 110.', meta:'bound to reference_build' },
  { t:'1.3s', kind:'tool', k:'select_workflow', d:'Selected by id, not by re-reading the sentence.', meta:'wf.rnaseq.de.v4' },
  { t:'1.6s', kind:'note', k:'Progress update to you', d:'"Inputs resolved and the pipeline is pinned — starting alignment now."', meta:'mid-run narration' },
  { t:'4m 20s', kind:'gate', k:'Quality gate halted phase B', d:'Library-size floor. Surfaced the measurement and the suggested change rather than deciding.', meta:'awaiting you' },
  { t:'5m 02s', kind:'clarify', k:'You chose: apply the suggestion', d:'2 low-depth samples excluded; recorded in the QC audit.', meta:'bound to sample_exclude' },
  { t:'11m 48s', kind:'note', k:'Post-run reply to you', d:'"1,284 genes move at FDR < 0.05, dominated by interferon signalling. Two samples were excluded at the gate and the effect survives their removal."', meta:'substantive, not a sign-off' }
];

/* ── Gap 4: roles ─────────────────────────────────────────────────────────*/
window.ROLES = {
  you:'Owner', project:'Fibrosis target triage',
  caps:[['Run a workflow', 'Viewer and above', true],
        ['Edit a parameter', 'Contributor and above', true],
        ['Register a model', 'Owner', true],
        ['Override a quality gate', 'Reviewer or Owner', true],
        ['Promote a file to the account', 'Owner', true],
        ['Approve a spend above £500', 'Billing owner', false]]
};
/* Every gate in the product is one pattern: measured · threshold · verdict. */
window.VERIFY_KINDS = [
  ['Workflow QC gate', 'a measurement on your data', 'halts the run', 'Spec 07'],
  ['Model eval gate', 'held-out performance', 'blocks registration', 'Spec 03'],
  ['Safety gate', 'a predicted liability', 'rejects a proposal', 'Spec 05'],
  ['Chemistry validity gate', 'structural correctness', 'drops a generated structure', 'Spec 05'],
  ['Human approval', 'a person', 'pauses until answered', 'Spec 07']
];
