/* Models — the four tracks as worked use cases, so clicking an example lands on
   a real page rather than a configuration form. Each case answers the same four
   questions: what model, what it was given, what came back, and how much of the
   answer to trust. Nothing here is a leaderboard or a loss curve. */

window.MODEL_CASES = {

  /* ── Run a pre-trained model ──────────────────────────── */
  run_fold: {
    id:'run_fold', track:'Run a model', lane:'Pre-trained · nothing of yours is trained',
    q:'Predict the fold of this sequence and show me where the model is unsure.',
    subject:'IL11RA · 422 aa · single chain', took:'11 m 20 s on 1×A100',
    model:{ name:'fold-predict', v:'v2.3', family:'Protein structure', origin:'open-source, integrated · weights pinned', conf:'high' },
    setup:[['Input', 'IL11RA.fasta · v1', 'resolved from this project’s files'],
      ['Mode', 'monomer', 'a complex needs the multimer case instead'],
      ['Templates', 'none used', 'so this is a prediction, not a threading of a known structure'],
      ['Recycles', '3', 'default for this model version']],
    stages:[['Search & features', 'done'], ['Fold', 'done'], ['Relax', 'done'], ['Confidence', 'done']],
    result:{ head:'A confident core with two soft regions',
      blocks:[{ lead:'Global', t:'pLDDT 84.2 across the chain, and predicted TM-score 0.79 — a fold you can dock into and reason about, with the caveats below held in view.' },
        { lead:'Where it is unsure', t:'Two regions fall below the usable floor: the D2–D3 hinge (res 178–196, pLDDT 61) and the cytoplasmic tail (res 371–422, pLDDT 48). The tail is disordered in every deposited structure too, so the low score there is agreement with reality rather than a failure.' },
        { lead:'What changes because of that', t:'A pose built across the hinge inherits its uncertainty. Any binding-site work should be run against the experimental complex (PDB 8BF2) and this prediction used only for the regions that structure does not resolve.' }]},
    metrics:[['pLDDT · mean', '84.2', '≥ 70 usable', 'pass'],
      ['pLDDT · minimum window', '48.0', 'res 371–422', 'flag'],
      ['pTM', '0.79', '≥ 0.70 for fold-level claims', 'pass'],
      ['Sequence identity to nearest PDB', '31%', 'below 30% weakens the prior', 'pass']],
    boundary:'A predicted structure is a hypothesis with a confidence field, not a measurement. This model was not trained on your data and cannot speak to your compound series, your assay, or whether the protein adopts this fold in your cell type.',
    artifacts:[['IL11RA_predicted.cif', 'structure · 422 residues, B-factor column carries pLDDT'],
      ['confidence_per_residue.tsv', 'table · pLDDT and PAE per residue'],
      ['fold_report.md', 'report · what ran, on what version, with the two soft regions named']],
    next:[['model', 'Open the model object', 'Evidence, applicability region, versions, and who else calls it'],
      ['data', 'Open the report', 'The document this produced — editable, versioned, downloadable'],
      ['run', 'Model the complex instead', 'Multimer mode with gp130, where the interface is the question']]
  },

  /* ── Train ────────────────────────────────────────────── */
  train_potency: {
    id:'train_potency', track:'Train', lane:'From scratch, on your data',
    q:'Train a potency predictor on our in-house assay data.',
    subject:'4,182 compounds · pIC50 · 6 years of internal assays', took:'38 m',
    model:{ name:'potency-gp', v:'v3 (candidate)', family:'Molecular property', origin:'trained here, on your data', conf:'medium' },
    setup:[['Training data', 'assay_2026_08.csv · v4', 'a version, not a filename — the run keeps pointing at v4'],
      ['Split', 'scaffold split · 70/15/15', 'random split leaks series between train and test; scaffold split does not'],
      ['Target', 'pIC50 · single assay protocol', 'mixed protocols were excluded rather than merged'],
      ['Excluded', '311 censored values held out of the fit', 'kept as inequalities for evaluation, never coerced to a number']],
    stages:[['Featurise', 'done'], ['Fit', 'done'], ['Held-out evaluation', 'done'], ['Gate', 'passed'], ['Offer to register', 'waiting on you']],
    result:{ head:'It clears the floor, and it is narrower than it looks',
      blocks:[{ lead:'Held out', t:'RMSE 0.62 log units and Spearman ρ 0.71 on the scaffold-held-out test set — inside the floor this project set for a model allowed to gate a design loop.' },
        { lead:'Where it applies', t:'The applicability region is the internal chemical space: aminopyrimidines and three neighbouring series. Outside it the model still returns a number, and that number is reported with low confidence and does not satisfy a gate.' },
        { lead:'What it learned that you may not want', t:'Compounds from 2020–2021 carry a systematic offset in the training data (a protocol change). The fit reproduces it. If the offset is an artefact rather than chemistry, the right fix is upstream in the assay file, not in the model.' }]},
    metrics:[['RMSE · held out', '0.62 log', '≤ 0.75 to gate a loop', 'pass'],
      ['Spearman ρ', '0.71', '≥ 0.60', 'pass'],
      ['Calibration · 80% interval coverage', '0.78', '0.75–0.85', 'pass'],
      ['Out-of-region behaviour', 'low confidence returned', 'must not gate', 'pass']],
    boundary:'A model trained on your data inherits your data’s biases, including ones nobody has noticed. Passing a gate means it cleared a floor on one held-out split — it is not a claim that predictions are correct for a series the training set never saw.',
    artifacts:[['potency-gp_v3.pkl', 'model artefact · pinned features and preprocessing'],
      ['heldout_predictions.tsv', 'table · predicted vs measured per test compound'],
      ['train_report.md', 'report · dataset version, split, metrics, gate decision']],
    next:[['register', 'Register it as v3', 'Callable from any project — supersede is a decision, not a silent swap'],
      ['model', 'Open the model object', 'Evidence, lineage back to assay_2026_08.csv v4, consumers'],
      ['run', 'Fix the 2020–21 offset first', 'Upstream in the assay file, then re-train against a new version']]
  },

  /* ── Adapt ────────────────────────────────────────────── */
  adapt_gen: {
    id:'adapt_gen', track:'Tune on our data', lane:'Fine-tune · base frozen, your delta kept separate',
    q:'Adapt the generative model to our chemical series.',
    subject:'1,204 in-house compounds · aminopyrimidine programme', took:'2 h 10 m',
    model:{ name:'molgen', v:'v4.1 + adapter', family:'Generative chemistry', origin:'public base + your delta', conf:'medium' },
    setup:[['Base model', 'molgen-public v4.1', 'frozen; the adapter is what changes'],
      ['Your data', 'series_aminopyrimidine.smi · v2', '1,204 compounds, 96 with measured potency'],
      ['Method', 'LoRA adapter · rank 16', 'cheapest level that moved the metric — a rule and an index were tried first'],
      ['Held back', '120 compounds', 'never seen by the adapter, used to check novelty and drift']],
    stages:[['Prepare pairs', 'done'], ['Fit adapter', 'done'], ['Novelty & drift check', 'done'], ['Gate', 'passed with a flag'], ['Offer to register', 'waiting on you']],
    result:{ head:'It writes like your series now — and that is also the risk',
      blocks:[{ lead:'What changed', t:'Sampled molecules land in your series 71% of the time, against 12% for the base model. Median synthetic-accessibility score improved from 4.1 to 3.4, because your compounds are makeable and the base model’s were often not.' },
        { lead:'The flag', t:'Novelty fell: 8% of samples are within one atom of a training compound, against a 5% ceiling. The adapter is partly memorising. Registering it is allowed, but the design loop should de-duplicate against the training set before anything is ordered.' },
        { lead:'What it did not forget', t:'Base-model chemistry validity held (99.4% parseable, unchanged), so the adaptation narrowed the distribution without breaking it. The base model stays callable, unchanged, at its own version.' }]},
    metrics:[['In-series rate', '71%', 'base model: 12%', 'pass'],
      ['Validity', '99.4%', '≥ 99% — must not degrade', 'pass'],
      ['Novelty · not within 1 atom', '92%', '≥ 95%', 'flag'],
      ['Synthetic accessibility · median', '3.4', 'lower is better · base 4.1', 'pass']],
    boundary:'Adaptation changes what a model prefers, not what is true. A molecule sampled from an adapted model is a proposal in your style — it carries no evidence of activity until something scores it, and the memorisation flag above means some proposals are not new.',
    artifacts:[['molgen-adapted_v1.adapter', 'adapter weights · 41 MB, base model unchanged'],
      ['samples_1000.smi', 'table · 1,000 samples with novelty and SA per row'],
      ['adapt_report.md', 'report · base version, delta, drift check, the novelty flag']],
    next:[['register', 'Register with the novelty flag attached', 'The flag travels with the model, into every consumer'],
      ['model', 'Open the model object', 'Base model, delta, and what turning the adapter off would mean'],
      ['run', 'Generate under a de-duplication rule', 'Samples screened against the training set before proposal']]
  },

  /* ── Optimise ─────────────────────────────────────────── */
  opt_loop: {
    id:'opt_loop', track:'Propose & test in rounds', lane:'Rounds under a budget you set',
    q:'Run the design–make–test loop on this series under a 96-assay budget.',
    subject:'aminopyrimidine series · round 4 of an open loop', took:'round 4 running · 3 rounds closed',
    model:{ name:'admet-herg', v:'v3', family:'Optimisation loop', origin:'surrogate pair · admet-herg v3 with potency-gp v2', conf:'medium' },
    setup:[['Budget', '96 assays per round', 'set by you — never inferred, never exceeded'],
      ['Objectives', 'potency ↑ · hERG ≥ 30 µM · solubility ≥ 10 µM', 'a constraint is not a soft score; a violation is a rejection'],
      ['Stop rule', 'no improvement over two rounds, or budget spent', 'stated before round 1'],
      ['Wet-lab route', 'plate export → mapping template v2', 'partial returns and censored values both expected']],
    stages:[['Round 1', 'closed'], ['Round 2', 'closed'], ['Round 3', 'closed'], ['Round 4', 'at the bench'], ['Refit', 'on 7 of 12 back']],
    result:{ head:'Three rounds bought 0.8 log of potency and cost the safety margin twice',
      blocks:[{ lead:'Progress', t:'Best measured pIC50 moved 7.1 → 7.9 across three closed rounds, on 271 of the 288 assays budgeted. Two proposals in round 3 were rejected before ordering for breaching the hERG constraint — they stay on the list with the reason.' },
        { lead:'What the loop is learning', t:'The surrogate now predicts hERG liability tracking amine basicity, which matches the November report’s conclusion from an entirely separate run. Two independent paths to the same finding is the strongest signal in this loop so far.' },
        { lead:'Honest about the round in flight', t:'Round 4 is at the bench: 7 of 12 results are back, 3 returned no data with reasons recorded, and 2 came back censored as IC50 > 30 µM — fitted as inequalities, never as 30. The refit will run on what is back rather than waiting a week for the rest.' }]},
    metrics:[['Best measured pIC50', '7.9', 'round 1 baseline 7.1', 'pass'],
      ['Budget spent', '271 / 288', 'three rounds', 'pass'],
      ['Constraint breaches ordered', '0', 'must be zero', 'pass'],
      ['Proposals returning no data', '3 of 12 this round', 'reasons recorded, kept in the fit', 'flag']],
    boundary:'A loop optimises what you told it to optimise. It has no view on whether potency is the right objective, and a proposal it likes is a suggestion for the bench — the measurement is the evidence, not the score.',
    artifacts:[['round4_order_sheet.csv', 'order sheet · your registry ids paired with candidate ids'],
      ['loop_state_round4.json', 'state · surrogate versions, budget ledger, rejections with reasons'],
      ['loop_report.md', 'report · three closed rounds, the refit policy, what is still out']],
    next:[['run', 'Refit on what is back', 'A tracked training run with its own gate — the new version does not score until it passes'],
      ['model', 'Open a surrogate', 'admet-herg v3 — evidence, applicability region, consumers'],
      ['data', 'Open the round report', 'Three closed rounds and what is still out — editable and downloadable']]
  }
};

window.MODEL_MATCH = [
  [/(fold|structure of this|model this complex|predicted interface|where the model is unsure|score this locus|sequence model|screen this library|predicted hits|pre-?trained)/i, 'run_fold'],
  [/(design.?make.?test|dmta|closed.?loop|active learning|next round|assay budget|\d+.?assay|propose the next)/i, 'opt_loop'],
  [/(adapt|fine-?tune)/i, 'adapt_gen'],
  [/(train|re-?train|classifier|predictor)/i, 'train_potency']
];
window.MTRACK_CASE = { 'Run a model':'run_fold', Train:'train_potency', 'Tune on our data':'adapt_gen', 'Propose & test in rounds':'opt_loop' };
/* Each case's own report — the artefact the page offers to open and edit. */
window.CASE_DOC = { run_fold:'rep_fold', train_potency:'rep_train', adapt_gen:'rep_adapt', opt_loop:'rep_loop' };
/* What registering a candidate does to the registry, so the toast and the
   registry can never disagree. */
window.CASE_REGISTER = { train_potency:['potency-gp', 'v3'], adapt_gen:['molgen', 'v4.1-a1'] };
window.modelCaseFor = (q, track) => {
  const hit = (window.MODEL_MATCH.find(([m]) => m.test(q || '')) || [])[1];
  return MODEL_CASES[hit] || MODEL_CASES[MTRACK_CASE[track] || ''] || null;
};
