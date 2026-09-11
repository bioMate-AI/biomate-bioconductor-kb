/* Documents that a run (or a saved answer) leaves behind, as editable objects.
   A report is a file: it is downloadable, it sits in the project file list, it
   has versions, and it can be edited by hand or by asking. */

window.DOCS = {
  rep1: {
    id:'rep1', name:'after-run_report.md', title:'Bulk RNA-seq differential expression — after-run report',
    kicker:'Fibrosis target triage · run r1 · v1.4.2', when:'14 Aug 2026, 14:04', by:'BioMate, from the project memo template v2',
    sections:[
      { id:'s1', h:'Summary', p:['1,284 genes move at FDR < 0.05 between treated and control (DESeq2 Wald test), and the response is dominated by interferon signalling. Two low-depth samples were excluded at the phase-B quality gate, as project instruction 3 requires; the effect survives their removal (Spearman ρ = 0.97 between the 22- and 24-sample fits).'] },
      { id:'s2', h:'Methods', p:['Counts were read from GSE184880_counts.tsv (v2) and the sample design from design.csv (v3). Library sizes were computed per sample and tested against a floor of 10 M assigned reads; CTRL_07 and TREAT_11 fell below it and were excluded.',
        'Differential expression used DESeq2 1.42.0 with a ~ batch + condition design, Wald test, and Benjamini–Hochberg control at α = 0.05. Gene identifiers were resolved against GENCODE v44.'] },
      { id:'s3', h:'Results', p:['1,284 genes reached significance, 812 up and 472 down in treated samples. The top-ranked set is enriched for type-I interferon response (GO:0034340, adjusted p = 2.1 × 10⁻¹⁴) and antigen presentation.',
        'Effect sizes are modest: the median absolute log2 fold change among significant genes is 0.61, so this is a broad, coordinated shift rather than a few large movers.'] },
      { id:'s4', h:'Limitations', p:['The sample design arrived amber — two spellings of “control” were normalised before the run, and batch was missing for two samples and imputed from submission date. Anything downstream of this table inherits that amber badge until a human clears it.'] },
      { id:'s5', h:'Citations', p:['Love M.I. et al. Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2. Genome Biology 15:550 (2014).', 'Frankish A. et al. GENCODE reference annotation. Nucleic Acids Research 51:D942 (2023).'] }
    ]
  },
  ans1: {
    id:'ans1', name:'evidence_IL11-fibrosis.md', title:'Evidence linking IL-11 to idiopathic pulmonary fibrosis',
    kicker:'Saved search answer · Literature · 7 references', when:'2 Sep 2026, 10:41', by:'saved by A. Dike from a search',
    sections:[
      { id:'s1', h:'Answer', p:['Human fibrotic lung tissue shows raised IL-11 in fibroblasts relative to matched non-fibrotic controls across three independently collected cohorts (Ng 2019; Cook 2021).',
        'Loss of function in mouse models attenuates bleomycin-induced fibrosis, and a neutralising antibody reverses established disease in one of two reported models (Schafer 2017; Widjaja 2022).'] },
      { id:'s2', h:'Boundary', p:['Association in human tissue plus causal evidence in mouse is not a validated human target. No interventional human data exists as of the index date, 2 Sep 2026.'] },
      { id:'s3', h:'Where the literature disagrees', p:['Two groups report that the anti-fibrotic effect does not separate from the anti-inflammatory effect of the antibody backbone (Adami 2023; Marchetti 2024). Kept in the record rather than dropped.'] },
      { id:'s4', h:'References', p:['Ng B. et al. Sci Transl Med (2019) · Cook S. et al. Nat Med (2021) · Schafer S. et al. Nature (2017) · Widjaja A. et al. JCI Insight (2022) · Corden B. et al. Cell Rep (2020) · Adami E. et al. bioRxiv (2023) · Marchetti L. et al. AJRCMB (2024).'] }
    ]
  }
};

/* One source of truth for a file's version history. Edits made to a document —
   by hand or by asking — are written under bm-doc-<id>-v; the file list, the
   object badge and the Versions tab all read through here, so the file list can
   never claim v1 is current while the open document says v2. */
window.fileVersions = id => {
  try { const s = localStorage.getItem('bm-doc-' + id + '-v'); if (s) { const v = JSON.parse(s); if (v && v.length) return v; } } catch (e) {}
  return (window.VERSIONS || {})[id] || [];
};
window.notifyVersions = () => window.dispatchEvent(new CustomEvent('bm-versions'));
window.useVersionTick = () => {
  const [, set] = React.useState(0);
  React.useEffect(() => { const f = () => set(n => n + 1);
    window.addEventListener('bm-versions', f); return () => window.removeEventListener('bm-versions', f); }, []);
};

/* One report per model use case, so a page never offers to open a document
   that belongs to a different run. Same shape as any other document: editable,
   versioned, downloadable, and present in the project file list. */
Object.assign(window.DOCS, {
  rep_fold: {
    id:'rep_fold', name:'fold_report.md', title:'IL11RA fold prediction — after-run report',
    kicker:'fold-predict v2.3 · pre-trained · nothing of yours was trained', when:'4 Sep 2026, 15:12', by:'BioMate, from the project memo template v2',
    sections:[
      { id:'s1', h:'Summary', p:['The chain folds to pLDDT 84.2 with predicted TM-score 0.79 — usable for docking and interpretation. Two regions fall below the usable floor: the D2–D3 hinge (res 178–196, pLDDT 61) and the cytoplasmic tail (res 371–422, pLDDT 48).'] },
      { id:'s2', h:'Methods', p:['Input IL11RA.fasta v1, resolved from project files. Monomer mode, no templates, 3 recycles, fold-predict v2.3 with pinned weights on 1×A100 (11 m 20 s). Confidence is reported as pLDDT per residue and PAE per residue pair; the structure file carries pLDDT in the B-factor column.'] },
      { id:'s3', h:'Limitations', p:['A predicted structure is a hypothesis with a confidence field, not a measurement. Binding-site work should use the experimental complex (PDB 8BF2); this prediction is appropriate only for the regions that structure does not resolve. The low tail score agrees with every deposited structure, where the tail is disordered.'] }
    ]
  },
  rep_train: {
    id:'rep_train', name:'train_report.md', title:'Potency predictor — training report',
    kicker:'potency-gp v3 candidate · gate passed · not yet registered', when:'5 Sep 2026, 11:48', by:'BioMate, from the project memo template v2',
    sections:[
      { id:'s1', h:'Summary', p:['A potency model fit to 4,182 internal compounds clears the project floor on a scaffold-held-out split: RMSE 0.62 log units, Spearman ρ 0.71, 80% interval coverage 0.78. It is offered for registration as potency-gp v3 and has not been registered.'] },
      { id:'s2', h:'Methods', p:['Training data assay_2026_08.csv v4 — a version, not a filename. Scaffold split 70/15/15, because a random split leaks a series between train and test. Single assay protocol; mixed protocols were excluded rather than merged. 311 censored values were held out of the fit and evaluated as inequalities.'] },
      { id:'s3', h:'Limitations', p:['The applicability region is the internal chemical space: aminopyrimidines and three neighbouring series. Outside it the model still returns a number, reported with low confidence and unable to satisfy a gate. Compounds from 2020–21 carry a systematic offset from a protocol change, and the fit reproduces it — the fix belongs upstream in the assay file, not in the model.'] }
    ]
  },
  rep_adapt: {
    id:'rep_adapt', name:'adapt_report.md', title:'Model tuned on our series — report',
    kicker:'molgen v4.1 + adapter a1 · gate passed with a novelty flag', when:'5 Sep 2026, 17:05', by:'BioMate, from the project memo template v2',
    sections:[
      { id:'s1', h:'Summary', p:['A LoRA adapter (rank 16) over molgen v4.1, fit to 1,204 in-house aminopyrimidines, raises the in-series sampling rate from 12% to 71% and improves median synthetic accessibility from 4.1 to 3.4. Validity is unchanged at 99.4%.'] },
      { id:'s2', h:'The flag', p:['Novelty fell below the ceiling: 8% of samples are within one atom of a training compound, against a 5% limit. The adapter is partly memorising. Registration is allowed, and the design pipeline must de-duplicate against the training set before anything is ordered.'] },
      { id:'s3', h:'Limitations', p:['Adaptation changes what a model prefers, not what is true. A sampled molecule is a proposal in your style and carries no evidence of activity until something scores it. The base model stays callable, unchanged, at its own version — the delta is recorded separately and can be switched off.'] }
    ]
  },
  rep_loop: {
    id:'rep_loop', name:'loop_report.md', title:'Series 4 optimisation loop — rounds 1–4',
    kicker:'admet-herg v3 + potency-gp v2 · 96 assays per round', when:'6 Sep 2026, 09:20', by:'BioMate, from the project memo template v2',
    sections:[
      { id:'s1', h:'Summary', p:['Three closed rounds moved best measured pIC50 from 7.1 to 7.9 on 271 of 288 budgeted assays. Two round-3 proposals were rejected before ordering for breaching the hERG constraint; both stay on the list with the reason. Round 4 is at the bench.'] },
      { id:'s2', h:'What the loop is learning', p:['The surrogate now predicts hERG liability tracking amine basicity, which matches the November ADMET report’s conclusion from a separate run. Two independent paths to the same finding is the strongest signal in this campaign so far.'] },
      { id:'s3', h:'Round 4, honestly', p:['7 of 12 results are back, 3 returned no data with reasons recorded, and 2 came back censored as IC50 > 30 µM — fitted as inequalities, never as 30. The refit will run on what is back rather than waiting for the rest, and produces a new model version that does not score anything until it passes its gate.'] },
      { id:'s4', h:'Limitations', p:['A loop optimises what it was told to optimise. It has no view on whether potency is the right objective, and a proposal it likes is a suggestion for the bench — the measurement is the evidence, not the score.'] }
    ]
  }
});
/* Formats an artifact can leave in. The bundle is the honest one: a report
   without its outputs and its manifest is not reproducible. */
window.DOC_FORMATS = [
  ['pdf', 'PDF', 'typeset from the project memo template v2'],
  ['docx', 'Word (.docx)', 'styles mapped, comments preserved'],
  ['md', 'Markdown (.md)', 'the source this document is stored as'],
  ['html', 'HTML', 'self-contained, figures inlined'],
  ['zip', 'Report bundle (.zip)', 'report + every output + run manifest + checksums']
];

/* What "ask BioMate to edit" can be asked for, and exactly what it would change.
   Each proposal is a real before/after on a real paragraph, so an edit can be
   read and refused rather than applied invisibly. */
window.DOC_EDITS = {
  rep1: [
    { id:'e1', ask:'Rewrite the summary for a regulatory reader', sec:'s1', pi:0,
      why:'Regulatory readers want the decision rule and the exclusion stated before the number, and no test-statistic shorthand.',
      after:'Between treated and control samples, 1,284 genes met the pre-specified significance criterion (Benjamini–Hochberg adjusted p < 0.05), with the response dominated by interferon signalling. Two samples (CTRL_07, TREAT_11) were excluded at the phase-B quality gate under project instruction 3. The finding is robust to that exclusion: the fitted effects with and without those samples correlate at Spearman ρ = 0.97.' },
    { id:'e2', ask:'Say plainly that the batch values were imputed', sec:'s4', pi:0,
      why:'“Imputed from submission date” is buried mid-sentence in a limitation a reader may skim. It is the weakest input in the run and should lead.',
      after:'Batch was missing for two samples and was imputed from submission date — an assumption, not a measurement, and the weakest input in this run. The sample design also arrived amber because two spellings of “control” had to be normalised before the run. Anything downstream inherits that amber badge until a human clears it.' },
    { id:'e3', ask:'Shorten the methods to one paragraph', sec:'s2', pi:0,
      why:'Two paragraphs repeat the file provenance that the Parameters tab already carries in full.',
      after:'Counts (GSE184880_counts.tsv v2) and design (design.csv v3) were read from project files; samples below a 10 M assigned-read floor (CTRL_07, TREAT_11) were excluded at the phase-B gate. Differential expression used DESeq2 1.42.0, design ~ batch + condition, Wald test, Benjamini–Hochberg at α = 0.05, against GENCODE v44.' },
    { id:'e4', ask:'Add the effect-size caveat to the results', sec:'s3', pi:1,
      why:'A median |log2FC| of 0.61 is easy to over-read as a strong effect. Naming the interpretation avoids that.',
      after:'Effect sizes are modest: the median absolute log2 fold change among significant genes is 0.61 — roughly a 1.5-fold change. This is a broad, coordinated shift rather than a few large movers, and single-gene follow-up should not be prioritised on rank alone.' }
  ],
  ans1: [
    { id:'e1', ask:'Make the boundary harder to miss', sec:'s2', pi:0,
      why:'A boundary that reads like a footnote gets quoted without its caveat.',
      after:'No interventional human data exists for this target as of 2 Sep 2026. What follows is therefore association in human tissue plus causal evidence in mouse — sufficient to justify a programme, not sufficient to call the target validated in humans.' },
    { id:'e2', ask:'Add what would change our mind', sec:'s3', pi:0,
      why:'A disagreement is more useful with the experiment that would resolve it attached.',
      after:'Two groups report that the anti-fibrotic effect does not separate from the anti-inflammatory effect of the antibody backbone (Adami 2023; Marchetti 2024). What would settle it: a backbone-matched isotype control in the therapeutic-dosing model, powered on collagen deposition. Until that exists, treat the reversal claim as single-lab.' }
  ]
};

/* The same affordance on a data file: ask for a change, read the diff, accept
   into a new version. Table edits describe cells, not prose. */
window.FILE_EDITS = {
  d2: [
    { id:'f1', ask:'Fill the missing batch values', why:'Two rows have no batch. Submission date groups them cleanly into the two existing batches — an inference, and it is recorded as one.',
      rows:[['CTRL_07', 'batch', '—', 'B1'], ['TREAT_11', 'batch', '—', 'B2']] },
    { id:'f2', ask:'Normalise the condition column', why:'“control” and “Control” are the same level. Left as-is, DESeq2 would fit three levels instead of two.',
      rows:[['CTRL_03', 'condition', 'Control', 'control'], ['CTRL_09', 'condition', 'Control', 'control'], ['CTRL_12', 'condition', 'Control', 'control']] }
  ],
  d1: [
    { id:'f1', ask:'Drop the two samples below the depth floor', why:'CTRL_07 and TREAT_11 sit below the 10 M floor. Dropping them here would silently change what a finished run consumed — so it writes a new version and leaves v2 in place.',
      rows:[['CTRL_07', 'column', 'present', 'removed'], ['TREAT_11', 'column', 'present', 'removed']] }
  ],
  o1: [
    { id:'f1', ask:'Add a column flagging genes below the effect-size floor', why:'Rank alone over-reads small effects. A boolean column is cheaper than re-reading the report each time.',
      rows:[['(all rows)', 'small_effect', '—', '|log2FC| < 0.5'], ['header', 'columns', '7', '8']] }
  ]
};

Object.assign(window.DOC_EDITS, {
  rep_fold: [
    { id:'e1', ask:'Lead with the unusable regions', sec:'s1', pi:0,
      why:'A reader who stops after the first sentence should already know which parts of this model not to build on.',
      after:'Two regions of this prediction are not usable: the D2–D3 hinge (res 178–196, pLDDT 61) and the cytoplasmic tail (res 371–422, pLDDT 48). Elsewhere the chain folds to pLDDT 84.2 with predicted TM-score 0.79, which is sufficient for docking and interpretation.' },
    { id:'e2', ask:'State plainly that no data of ours was used', sec:'s2', pi:0,
      why:'Colleagues assume any model run consumed project data. Here none was, and saying so avoids a governance question later.',
      after:'No data of ours entered this model: fold-predict v2.3 arrives already fitted, with weights pinned at that version. Input IL11RA.fasta v1 was read from project files. Monomer mode, no templates, 3 recycles, 1×A100, 11 m 20 s. Confidence is reported as pLDDT per residue and PAE per residue pair, with pLDDT carried in the structure file’s B-factor column.' }
  ],
  rep_train: [
    { id:'e1', ask:'Say it is not registered in the first line', sec:'s1', pi:0,
      why:'“Offered for registration” at the end of a paragraph reads as registered to anyone skimming.',
      after:'This model is not registered. It is offered as potency-gp v3, having cleared the project floor on a scaffold-held-out split of 4,182 internal compounds: RMSE 0.62 log units, Spearman ρ 0.71, 80% interval coverage 0.78.' },
    { id:'e2', ask:'Make the 2020–21 offset its own recommendation', sec:'s3', pi:0,
      why:'A limitation that contains an action should end in that action, not in a clause.',
      after:'Compounds from 2020–21 carry a systematic offset from a protocol change, and the fit reproduces it. Recommendation: correct or exclude that period in assay_2026_08.csv, save it as a new version, and re-train against it before this model gates anything. Separately, the applicability region is the internal chemical space — outside it predictions are returned with low confidence and cannot satisfy a gate.' }
  ],
  rep_adapt: [
    { id:'e1', ask:'Put the de-duplication requirement in the summary', sec:'s1', pi:0,
      why:'The condition on using this model belongs where the result is stated, not one section later.',
      after:'A LoRA adapter (rank 16) over molgen v4.1, fit to 1,204 in-house aminopyrimidines, raises the in-series sampling rate from 12% to 71% and improves median synthetic accessibility from 4.1 to 3.4, with validity unchanged at 99.4%. It may only be used with de-duplication against the training set enabled — see the novelty flag below.' },
    { id:'e2', ask:'Explain what turning the adapter off would mean', sec:'s3', pi:0,
      why:'“Can be switched off” invites the obvious question and does not answer it.',
      after:'Adaptation changes what a model prefers, not what is true. The base model stays callable at its own version and the delta is recorded separately: switching the adapter off restores base behaviour immediately and completely, because nothing was merged into the base weights. Molecules already proposed under the adapter keep their provenance and are unaffected.' }
  ],
  rep_loop: [
    { id:'e1', ask:'Give the two rejections their reasons here', sec:'s1', pi:0,
      why:'A rejection without its reason reads as the loop being arbitrary.',
      after:'Three closed rounds moved best measured pIC50 from 7.1 to 7.9 on 271 of 288 budgeted assays. Two round-3 proposals were rejected before ordering — predicted hERG 12 µM and 19 µM against the 30 µM constraint — and both remain on the list with those numbers. Round 4 is at the bench.' },
    { id:'e2', ask:'Add what would end the campaign', sec:'s4', pi:0,
      why:'The stop rule was set before round 1 and should appear in the report that reviews the rounds.',
      after:'A loop optimises what it was told to optimise. It has no view on whether potency is the right objective, and a proposal it likes is a suggestion for the bench. The stop rule, set before round 1: no improvement over two consecutive rounds, or the budget spent — whichever comes first.' }
  ]
});
/* A report is a file. Registering the four here keeps that true without a
   second copy of the file-object shape. */
(() => {
  const meta = { rep_fold:['FP', 'fold-predict v2.3 · IL11RA', [['Sections', '3'], ['Words', '236'], ['Model', 'fold-predict v2.3'], ['Size', '7 KB']]],
    rep_train:['TR', 'potency-gp v3 candidate', [['Sections', '3'], ['Words', '271'], ['Model', 'potency-gp v3'], ['Size', '8 KB']]],
    rep_adapt:['AD', 'molgen v4.1 + adapter a1', [['Sections', '3'], ['Words', '248'], ['Model', 'molgen v4.1+a1'], ['Size', '7 KB']]],
    rep_loop:['OL', 'admet-herg v3 + potency-gp v2', [['Sections', '4'], ['Words', '302'], ['Rounds', '4'], ['Size', '9 KB']]] };
  const folder = { folder:'runs/models/', files:[] };
  Object.keys(meta).forEach(id => {
    const d = window.DOCS[id], [init, sub, stats] = meta[id];
    window.DATASETS.push({ id:id, name:d.name, init:init, kind:'report · model work', quality:id === 'rep_adapt' ? 'watch' : 'pass',
      hash:'sha256:' + id.slice(4) + '…f1c0', scope:'project', scopeNote:'Inherits the scope of the model work that produced it',
      appearsIn:[['Model use case', d.kicker.split(' · ')[0]], ['Project files', 'Fibrosis target triage']], dupes:[],
      origin:{ type:'Produced by model work', label:sub, by:'BioMate', when:d.when.split(',')[0],
        note:'Written from the project memo template v2, and it keeps the model version that produced it — so this report stays readable after that model is superseded.' },
      stats:stats,
      qnotes:id === 'rep_adapt' ? [['pass', 'every number resolves to the adaptation run'], ['watch', 'carries a novelty flag that constrains how the model may be used']]
        : [['pass', 'every number resolves to an output of the run']],
      preview:'document · ' + d.sections.length + ' sections', runs:[], derived:[] });
    folder.files.push(id);
    window.VERSIONS[id] = [{ v:1, what:'written by the model run, from the project memo template v2', by:'BioMate', when:d.when }];
  });
  window.FILETREE['Fibrosis target triage'].splice(2, 0, folder);
})();
