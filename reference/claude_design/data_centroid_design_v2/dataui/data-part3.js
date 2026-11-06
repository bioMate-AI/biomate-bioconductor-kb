/* Part 3 fixtures — step deep-view, evidence typing, cold-start modules,
   number→source claims. No coverage counts, no named inventories. */

/* ── D1: the four evidence classes ───────────────────────── */
window.EVIDENCE = {
  perceptual:  { label:'perceptual',  icon:'image',    hue:'oklch(0.62 0.13 250)', soft:'oklch(0.95 0.03 250)', what:'something you look at — image, micrograph, density map, spectrum' },
  symbolic:    { label:'symbolic',    icon:'dna',      hue:'oklch(0.58 0.12 300)', soft:'oklch(0.95 0.03 300)', what:'something you read — sequence, formula, annotation, graph' },
  quantitative:{ label:'quantitative',icon:'table',    hue:'oklch(0.55 0.11 165)', soft:'oklch(0.95 0.03 165)', what:'something you measure — table, metric, distribution' },
  procedural:  { label:'procedural',  icon:'terminal', hue:'oklch(0.55 0.02 260)', soft:'oklch(0.95 0.005 260)',what:'something that happened — log, trace, trajectory' }
};

/* ── A: per-step resolved parameters + outputs ────────────── */
const RAW_LOG = `[12:04:11] nextflow  | launching nf-core/rnaseq v3.14.0
[12:04:12] executor  | awsbatch (queue biomate-std, 24 tasks)
[12:04:40] STAR      | CTRL_01 · 18,214,882 reads in · 96.1% uniquely mapped
[12:05:02] STAR      | CTRL_07 ·  4,102,331 reads in · 94.8% uniquely mapped   <-- low depth
[12:06:55] STAR      | TREAT_11 · 3,703,118 reads in · 95.2% uniquely mapped   <-- low depth
[12:08:20] salmon    | quantification complete for 24/24 samples
[12:08:23] biomate   | writing counts matrix (38,214 × 24) → counts.tsv`;

const RAW_TSV = `gene_id\tgene_name\tlog2FC\tlfcSE\tstat\tpvalue\tpadj
ENSG00000232810\tTNF\t2.8412\t0.3106\t9.147\t1.2e-11\t4.1e-08
ENSG00000146648\tEGFR\t2.1104\t0.2894\t7.292\t8.7e-09\t1.9e-06
ENSG00000171862\tPTEN\t-0.6088\t0.1901\t-3.203\t0.00136\t0.0310
ENSG00000141510\tTP53\t-0.4210\t0.1822\t-2.311\t0.02083\t0.0871
ENSG00000012048\tBRCA1\t0.3814\t0.2390\t1.596\t0.11049\t0.2903`;

const RAW_ALIGN = `sample_id\treads_in\tuniquely_mapped\tpct_unique\tmulti_mapped
CTRL_01\t18214882\t17504497\t96.1\t2.9
CTRL_07\t4102331\t3889009\t94.8\t3.4
TREAT_11\t3703118\t3524366\t95.2\t3.1
TREAT_12\t18512004\t17845571\t96.4\t2.7`;

const RAW_COUNTS = `gene_id\tgene_name\tCTRL_01\tCTRL_02\tTREAT_01\tTREAT_02
ENSG00000141510\tTP53\t1042\t1118\t908\t951
ENSG00000012048\tBRCA1\t318\t341\t377\t362
ENSG00000171862\tPTEN\t884\t902\t611\t648
ENSG00000146648\tEGFR\t512\t488\t2104\t1988
ENSG00000232810\tTNF\t44\t51\t268\t301`;

const RAW_CONTAM = `sample_id\tcross_species_pct\ttop_foreign_taxon\trelatedness_max\tverdict
CTRL_01\t0.08\tnone\t0.041\tpass
CTRL_07\t0.11\tnone\t0.038\tpass
TREAT_11\t0.09\tnone\t0.052\tpass
TREAT_12\t0.07\tnone\t0.044\tpass`;

const RAW_DISP = `gene_id\tbase_mean\tdispersion_gene\tdispersion_fit\tdispersion_final
ENSG00000232810\t184.2\t0.2841\t0.2610\t0.2688
ENSG00000146648\t1290.6\t0.1104\t0.0994\t0.1021
ENSG00000171862\t742.1\t0.0688\t0.0721\t0.0709
ENSG00000141510\t1018.4\t0.0410\t0.0482\t0.0461
ENSG00000012048\t344.8\t0.1814\t0.1590\t0.1662`;

const RAW_SHRUNK = `gene_id\tgene_name\tlog2FC_mle\tlog2FC_shrunk\tlfcSE_shrunk
ENSG00000232810\tTNF\t2.8412\t2.7908\t0.2884
ENSG00000146648\tEGFR\t2.1104\t2.0611\t0.2701
ENSG00000171862\tPTEN\t-0.6088\t-0.5104\t0.1744
ENSG00000141510\tTP53\t-0.4210\t-0.3188\t0.1610
ENSG00000012048\tBRCA1\t0.3814\t0.2094\t0.1902`;

const RAW_QC = `sample_id\tlibrary_size\tpass_floor\taction
CTRL_01\t18214882\ttrue\tkeep
CTRL_07\t4102331\tfalse\texclude
TREAT_11\t3703118\tfalse\texclude
TREAT_12\t18512004\ttrue\tkeep`;

window.STEP_DEEP = {
  A1:{ tool:'biomate-stage', ver:'1.2.0', dur:'0 min 51 s', inputs:['d1'],
    params:[['Sample sheet','design.csv v3','inherited','resolved from the project’s Files, not re-uploaded'],
            ['Read layout','paired-end','detected','inferred from the FASTQ headers'],
            ['Concurrency','24 tasks','default','']],
    outs:[{ id:'A1o1', ev:'procedural', name:'stage.log', meta:'412 lines', summary:'24 sample pairs staged from the project’s uploads. No checksum mismatch.', raw:RAW_LOG }] },
  A2:{ tool:'nf-core/rnaseq', ver:'3.14.0', dur:'4 min 12 s', inputs:['d1'],
    params:[['Aligner','STAR','default','pipeline default for this version'],
            ['Reference build','human · GRCh38 (Ensembl 110)','override','project instruction 1 fixes the build'],
            ['Annotation','GENCODE v44','override','licence accepted at configuration'],
            ['Trim adapters','on','default','']],
    outs:[{ id:'A2o1', ev:'quantitative', name:'alignment_metrics.tsv', meta:'24 × 5', summary:'Uniquely-mapped rate 94.8–96.4%. Two samples came in well under the read-count floor.', raw:RAW_ALIGN },
          { id:'A2o2', ev:'perceptual', name:'mapping_rates.png', meta:'1600 × 1200 · 300 dpi', summary:'Per-sample mapping bar chart; the two low-depth samples are the short bars.', plot:'lib' },
          { id:'A2o3', ev:'procedural', name:'nextflow.log', meta:'8,204 lines', summary:'Executor trace for all 24 tasks.', raw:RAW_LOG }] },
  A3:{ tool:'biomate-assemble', ver:'1.2.0', dur:'1 min 37 s', inputs:['d1'],
    params:[['Counting mode','gene-level','default',''],['Minimum count','0','default','filtering happens later, in phase C']],
    outs:[{ id:'A3o1', ev:'quantitative', name:'counts.tsv', meta:'38,214 × 24 · 14.2 MB', summary:'The assembled count matrix — a dataset object in its own right.', raw:RAW_COUNTS, dataset:'d1' }] },
  B1:{ tool:'biomate-qc', ver:'2.1.4', dur:'0 min 44 s', inputs:['d1'],
    params:[['Contamination panel','standard human','default',''],['Relatedness threshold','π̂ < 0.2','default','']],
    outs:[{ id:'B1o1', ev:'quantitative', name:'contamination.tsv', meta:'24 × 5', summary:'No cross-species signal; no sample-swap signal in the relatedness check.', raw:RAW_CONTAM }] },
  B2:{ tool:'biomate-qc', ver:'2.1.4', dur:'0 min 31 s', inputs:['d1'], gate:true,
    params:[['Minimum library size','8 M reads','override','recommended from the internal QC baseline (41 runs)'],
            ['Action on failure','exclude and list','override','project instruction 3 — exclude rather than impute'],
            ['Auto-loop','on','default','']],
    outs:[{ id:'B2o1', ev:'quantitative', name:'library_sizes.tsv', meta:'24 × 4', summary:'2 of 24 samples fall below the floor: CTRL_07 (4.1 M) and TREAT_11 (3.7 M).', raw:RAW_QC },
          { id:'B2o2', ev:'perceptual', name:'library_size.png', meta:'1200 × 700', summary:'Library size per sample against the 8 M floor.', plot:'lib' }] },
  B3:{ tool:'biomate-qc', ver:'2.1.4', dur:'0 min 50 s', inputs:['d2'],
    params:[['Design formula','~ condition + batch','override','recommended — batch removes a visible split in the PCA'],
            ['Reference level','control','inferred','after the two spellings of “control” were merged']],
    outs:[{ id:'B3o1', ev:'perceptual', name:'pca.png', meta:'1200 × 1200', summary:'Arms separate on PC1; the two low-depth samples sit apart on PC2.', plot:'pca' },
          { id:'B3o2', ev:'symbolic', name:'design_normalised.csv', meta:'24 records', summary:'The design table as the run actually read it, after normalisation.', records:'design' }] },
  C1:{ tool:'DESeq2', ver:'1.42.0', dur:'14 min 08 s', inputs:['d1','d2'],
    params:[['Test','Wald','default',''],['Design formula','~ condition + batch','override',''],
            ['Independent filtering','on','default',''],['Samples used','22 of 24','override','2 excluded at the phase-B gate']],
    outs:[{ id:'C1o1', ev:'quantitative', name:'dispersion.tsv', meta:'18,402 × 5', summary:'Dispersion fit converged; no outlier refit needed.', raw:RAW_DISP },
          { id:'C1o2', ev:'procedural', name:'deseq2_session.log', meta:'214 lines', summary:'R session, package versions and the exact call.', raw:'> dds <- DESeqDataSetFromMatrix(countData = counts, colData = design, design = ~ condition + batch)\n> dds <- DESeq(dds, test = "Wald", fitType = "parametric")\nestimating size factors\nestimating dispersions\ngene-wise dispersion estimates\nmean-dispersion relationship\nfinal dispersion estimates\nfitting model and testing\n> sessionInfo()\nR 4.3.2 · DESeq2 1.42.0 · apeglm 1.24.0' }] },
  C2:{ tool:'apeglm', ver:'1.24.0', dur:'3 min 22 s', inputs:[],
    params:[['Shrinkage estimator','apeglm','override','recommended — keeps ranking stable at low counts'],['Coefficient','condition_treated_vs_control','inferred','']],
    outs:[{ id:'C2o1', ev:'quantitative', name:'shrunk_lfc.tsv', meta:'18,402 × 5', summary:'Shrunk log2 fold-changes; large effects essentially unchanged.', raw:RAW_SHRUNK }] },
  C3:{ tool:'DESeq2', ver:'1.42.0', dur:'3 min 42 s', inputs:[],
    params:[['Alpha (FDR)','0.05','override','project instruction 2 — FDR, with the test named'],['Method','Benjamini–Hochberg','default','']],
    outs:[{ id:'C3o1', ev:'quantitative', name:'de_results.tsv', meta:'18,402 × 7 · 2.4 MB', summary:'412 genes below padj 0.05. Becomes a dataset in its own right.', raw:RAW_TSV, dataset:'o1' },
          { id:'C3o2', ev:'perceptual', name:'volcano.png', meta:'1600 × 1200 · 300 dpi', summary:'Volcano to the project figure spec — greyscale-safe.', plot:'volcano' }] },
  D1:{ tool:'biomate-figures', ver:'1.0.7', dur:'1 min 10 s', inputs:[],
    params:[['Figure spec','project · manuscript figure spec','inherited','vector SVG, Arial 8 pt, panel letters bottom-left'],['DPI','300','inherited','']],
    outs:[{ id:'D1o1', ev:'perceptual', name:'figure_1.svg', meta:'vector · 3 panels', summary:'Panels A–C assembled to the project spec.', plot:'volcano' }] },
  D2:{ tool:'biomate-report', ver:'1.0.7', dur:'2 min 48 s', inputs:[],
    params:[['Template','Internal target-triage memo v3','inherited','project output requirement'],['Findings length','max 200 words','inherited','']],
    outs:[{ id:'D2o1', ev:'symbolic', name:'after-run.pdf', meta:'7 sections', summary:'Findings, methods, parameters, software, citations, QC audit.', records:'report' }] }
};

/* ── D3: every number in the findings, and the output it came from ── */
window.CLAIMS = {
  c1:{ n:'412 genes', step:'C3', out:'C3o1', how:'count of rows with padj < 0.05 in de_results.tsv', val:'412 / 18,402' },
  c2:{ n:'FDR < 0.05', step:'C3', out:'C3o1', how:'alpha as run — project instruction 2', val:'0.05 · Benjamini–Hochberg' },
  c3:{ n:'two low-depth samples', step:'B2', out:'B2o1', how:'rows with pass_floor = false in library_sizes.tsv', val:'CTRL_07 · TREAT_11' },
  c4:{ n:'ρ = 0.97', step:'B2', out:'B2o1', how:'effect stability with and without the excluded samples', val:'Spearman ρ, 22 vs 24 samples' }
};

/* ── B: cold-start function modules. Categories and shapes, never a catalog ── */
/* Four things you can do: Search, Design, Analyse, Model.
   Design & generate earned its own module — de novo molecule design is a
   distinct intent from analysing data or training a predictor, and it is the
   spine of a lead-discovery programme.
   Skills & experts is not a peer — it modifies all four, so it is a strip. */
window.MODULES = [
  { id:'design', k:'Design & generate', icon:'dna', lane:'Instant → Cloud',
    t:'Propose candidates — molecules, peptides, proteins — then optimise and rank them',
    s:'The pipeline that produces candidates for any modality: generate under constraints, predict and filter, optimise the properties that matter, rank what survives. It ends in a shortlist you can order. It calls models; it is not where models are made — every score names the model version behind it, and that name opens in Models.',
    modalities:true,
    tracks:[
      { k:'Generate', lane:'de novo & scaffold', s:'Valid structures or sequences proposed under your constraints — a target, a scaffold or framework to stay on, a property envelope to respect.',
        exBy:{ sm:['Generate 500 candidates for this target with drug-like properties.','Scaffold-hop away from this series but keep the binding pharmacophore.','Grow this fragment into a lead-like molecule.'],
          pep:['Design cyclic peptide binders to this epitope.','Stapled-peptide analogues of this helix, with the binding face fixed.','Macrocyclise this linear peptide and keep the pharmacophore.'],
          bio:['Design nanobody candidates against this epitope.','Graft these CDRs onto a stable human framework.','Propose enzyme variants with a redesigned active-site pocket.'] } },
      { k:'Predict & filter', lane:'activity & structure', s:'Predicted activity, and a structural rationale for it, with the applicability region stated so a confident number outside it is not offered as one.',
        exBy:{ sm:['Predict binding affinity for these candidates against my target.','Which of these would you expect to bind, and why?','Dock the top 50 and check the poses are plausible.'],
          pep:['Predict which of these peptides stay bound, and why.','Check the predicted helicity of these analogues.','Flag the candidates likely to be cleaved in serum.'],
          bio:['Predict the complex for these designs and filter on interface quality.','Which variants keep the fold at 40 °C?','Flag designs with exposed hydrophobic patches.'] } },
      { k:'Optimise properties', lane:'multi-objective · one pass', s:'Druglikeness or developability and activity optimised together, with the trade-off shown rather than collapsed into one score. One pass — a loop with bench rounds is Models → Optimise.',
        exBy:{ sm:['Optimise this series for potency without losing solubility.','Improve druglikeness while keeping hERG above 30 µM.','Fix the metabolic liability on this scaffold and re-score.'],
          pep:['Improve serum stability without losing affinity.','Reduce charge while keeping cell permeability.','Optimise these macrocycles for both potency and solubility.'],
          bio:['Optimise this antibody for developability — aggregation and viscosity.','Humanise this nanobody and keep affinity.','Raise thermostability without losing catalytic activity.'] } },
      { k:'Rank candidates', lane:'triage', s:'A ranked shortlist under criteria you set, each row traceable to the predictions and the model versions that produced it.',
        exBy:{ sm:['Rank these 500 candidates for developability and show me the top 20.','Which candidates pass every safety gate?','Triage this library into synthesise-now and park.'],
          pep:['Rank these peptides for synthesisability and stability.','Which analogues pass every liability filter?'],
          bio:['Rank these designs for expression and developability risk.','Which constructs pass every manufacturability gate?'] } }]
  },
  { id:'search', k:'Search & evidence', icon:'search', lane:'Instant · seconds',
    t:'A cited answer over literature, databases and patents',
    s:'Every claim carries its reference, so an answer is checkable rather than plausible. Nothing here runs on your data.',
    tracks:[
      { k:'Literature', lane:'papers, preprints', s:'Peer-reviewed and preprint corpora, read with the debate intact rather than flattened into a summary. Also: SAR for a chemotype, standard assays for an endpoint, why a target class fails.',
        ex:['What is the evidence linking this target to disease?'] },
      { k:'Databases', lane:'curated', s:'Curated biological and chemical resources — sequence, structure, pathway, assay and clinical registries.',
        ex:['Pull every reported structure for this target.'] },
      { k:'Patents', lane:'claim-level', s:'Claim-level retrieval, so an answer tells you who holds what rather than that a filing exists. Also: a freedom-to-operate picture, or your own candidates checked against live claims.',
        ex:['Who holds composition-of-matter claims on this scaffold?'] },
      { k:'Internal', lane:'your org', s:'Your organisation’s own reports and run history, searched under the same citation rules.',
        ex:['Have we assayed this scaffold before, and what did we conclude?'] }]
  },
  { id:'analysis', k:'Data analysis', icon:'beaker', lane:'Instant → Cloud',
    t:'Work on your own data — ad-hoc or validated',
    s:'One intent, two gears. BioMate chooses by how much rigour the question needs, and says which it picked; you can force either.',
    tracks:[
      { k:'Ad-hoc compute', lane:'seconds', s:'Code written and run in a network-isolated sandbox, with the code shown. Right when you want a number or a look.',
        ex:['Summarise this assay table and plot potency against logP.','Correlate predicted and measured IC50 for these compounds.','Reshape this plate readout into long format and save it.'] },
      { k:'Validated workflows', lane:'minutes–hours', s:'Multi-step pipelines with quality gates, a resolved-parameter record per step, and an audit-ready report. Pick a domain to see the shapes it covers.',
        domains:true,
        ex:['Screen these SMILES for ADMET liabilities.','Fit dose–response curves across these plates.','Assess run-to-run quality across this assay batch.'] }]
  },
  { id:'models', k:'Models', icon:'sparkles', lane:'Cloud · hours',
    t:'The instruments a design or analysis run calls — run, train, adapt, loop',
    s:'Ask here when the answer you want is a model rather than a candidate: what it can speak to, how it was evaluated, or a new one fit to your data. Trained artifacts are first-class objects — versioned, gated on held-out data, carrying the dataset they learned from — and the design pipeline scores with them.',
    tracks:[
      { k:'Run a model', lane:'pre-trained · minutes', s:'A single-shot call to an integrated open-source model — structure prediction, genomic sequence models, chemical screening. Nothing of yours is trained; the questions are what it can speak to and how much of its answer to trust.',
        ex:['Predict the fold of this sequence and show me where the model is unsure.'] },
      { k:'Train', lane:'from scratch', s:'A predictive model fit to your data, evaluated on a held-out split before it is offered to you.',
        ex:['Train a potency predictor on our in-house assay data.'] },
      { k:'Tune on our data', lane:'fine-tune · base frozen, your delta kept separate', s:'A public or foundation model taught your chemistry, your series or your assay — the base model stays callable and unchanged, and what it learned from you is a separate delta you can switch off.',
        ex:['Adapt the generative model to our chemical series.'] },
      { k:'Propose & test in rounds', lane:'a budget you set, not an algorithm you pick', s:'The model proposes, the bench or a simulator measures, the model refits, and the next round is proposed — until the budget is spent or nothing improves. A single improvement pass with no bench round-trip belongs in Design & generate.',
        ex:['Run the design–make–test loop on this series under a 96-assay budget.'] }]
  }
];

/* Not a module — a modifier over all four. */
window.EXPERT_NOTE = { k:'Skills & experts',
  s:'Connected once for the account, switched on per project, and adjustable for a single question — they change how work is done and read, not what BioMate can do.' };

/* Intent router — matches a described goal to a lane and a domain, never to a list of names. */
window.MODALITIES = [['sm', 'Small molecule'], ['pep', 'Peptide'], ['bio', 'Protein / biologic']];
/* Modality is a property of the request, not of the domain: ranking a set of
   nanobodies and ranking a set of small molecules are the same job on different
   objects. A card therefore takes the modality from the request. */
window.MOD_WORD = { sm:'small molecule', pep:'peptide', bio:'protein' };
window.modalityOf = t => /(peptide|macrocyc|stapled|helicit|cleaved in serum|serum stab)/i.test(t || '') ? 'peptide'
  : /(antibod|nanobod|\bcdr\b|humanis|framework|enzyme|thermostab|construct|these designs|interface quality|predicted complex|keep the fold|expression (system|host|titre|titer|yield|risk))/i.test(t || '') ? 'protein'
  : 'small molecule';
window.ROUTES = [
  /* Evidence intents first: a question about what is known must not be
     swallowed by a topic keyword that appears in it. */
  { m:/(patent|freedom.?to.?operate|\bfto\b|claims?\b|composition-of-matter)/i, lane:'Instant · search', dom:'Patents',
    read:'reads as a claim-level patent question', seed:'Who holds composition-of-matter claims on this scaffold?' },
  { m:/(have we|did we|do we (have|know)|our (last|previous|in-house) .*(baseline|result)|find the last|what did we conclude)/i, lane:'Instant · search', dom:'Internal',
    read:'reads as a question about our own record', seed:'Have we assayed this scaffold before, and what did we conclude?' },
  { m:/(pull every|reported (structure|activit)|structures? for this|registr(y|ies)|curated)/i, lane:'Instant · search', dom:'Databases',
    read:'reads as a lookup over curated databases', seed:'Pull every reported structure for this target.' },
  { m:/(evidence|literature|\bsar\b|standard for|known (off-?target|sar)|why do|mechanism|debate|cite it|trials?\b|endpoints\?)/i, lane:'Instant · search', dom:'Literature',
    read:'reads as a question about what is known', seed:'What is the evidence for this? Cite it.' },

  /* Then the model-side intents, before anything that merely mentions potency. */
  /* Pre-trained inference, before the domain-workflow rules that would
     otherwise swallow “predict the fold” or “score this locus”. */
  { m:/(predict the (fold|structure)|model this complex|predicted interface|predicted binding site|does this mutation|fold of this|low-?confidence region|where the model is unsure|structure confidence|\bplddt\b|\bpae\b)/i, lane:'Cloud · models', dom:'Structure prediction',
    read:'reads as a pre-trained structure prediction', seed:'Predict the fold of this sequence and show me where the model is unsure.' },
  { m:/(score this (locus|sequence|region)|sequence model|per-?base score|regulatory signal|finds unusual|what stands out|functionally consequential)/i, lane:'Cloud · models', dom:'Sequence scoring',
    read:'reads as scoring a sequence with a pre-trained model', seed:'Score this locus with the sequence model and mark what stands out.' },
  { m:/(screen this library|virtual (library|screen)|predicted hits|which of these scaffolds|model prefer|re-?rank these hits)/i, lane:'Cloud · models', dom:'Library screening',
    read:'reads as screening a library with a pre-trained model', seed:'Screen this library against my target and rank the predicted hits.' },
  { m:/(dmta|design.?make.?test|closed.?loop|active learning|next round|per round|assay budget|\d+.?assay)/i, lane:'Cloud · models', dom:'Optimisation loop',
    read:'reads as a closed design–make–test loop under a budget', seed:'Run the design–make–test loop on this series under a 96-assay budget.' },
  { m:/(train|fine-?tune|adapt|re-?train)\b/i, lane:'Cloud · models', dom:'Models & training',
    read:'reads as training or adapting a model on your own data', seed:'Train a potency predictor on our assay data and report held-out performance.' },

  /* The design pipeline, most specific first. */
  { m:/(peptide|macrocyc|stapled|cyclic peptide|helicity|cleaved in serum|serum stab|proteolytic|cell permeab|reduce charge)/i, lane:'Cloud · design', dom:'Peptide design',
    read:'reads as peptide design or peptide property optimisation', seed:'Design cyclic peptide binders to this epitope.' },
  { m:/(antibody|nanobody|\bcdr\b|humanis|framework|enzyme variant|thermostab|aggregation|viscosity|expression (system|host|titre|titer|yield)|interface quality|predicted complex|predict the complex|keep the fold|hydrophobic patch|manufacturab)/i, lane:'Cloud · design', dom:'Protein & biologic design',
    read:'reads as protein or biologic design', seed:'Optimise this antibody for developability — aggregation and viscosity.' },
  { m:/(optimis|optimiz|multi-?objective|trade-?off|without losing|re-?score|fix the .*liabilit|improve.*(while|but|without))/i, lane:'Cloud · design', dom:'Property optimisation',
    read:'reads as multi-objective optimisation across druglikeness, affinity and safety', seed:'Optimise this series for potency without losing solubility or hERG margin.' },
  { m:/(generate|de novo|design (a |some )?molecul|scaffold.?hop|enumerat|analogue|grow this fragment)/i, lane:'Cloud · design', dom:'Molecular design',
    read:'reads as de novo generation under constraints', seed:'Generate candidates for this target with drug-like properties, then rank them.' },
  { m:/(affinity|binding|expect to bind|dock|pose|selectiv|predict.*potenc)/i, lane:'Cloud · design', dom:'Activity prediction',
    read:'reads as activity prediction on a compound set', seed:'Predict binding affinity for these candidates against my target, with a rationale.' },

  /* Validated workflows by domain. ADMET before ranking: a screen request
     usually ends "and rank them". */
  { m:/(herg|admet|smiles|liabilit|toxic|metabolic|solubil)/i, lane:'Cloud · workflow', dom:'Drug discovery',
    read:'reads as a property-screening task on a compound set', seed:'Screen these compounds for ADMET liabilities, hERG first, and rank them by developability.' },
  { m:/(rank|triage|shortlist|developab|prioriti|top \d+|pass every)/i, lane:'Cloud · design', dom:'Candidate ranking',
    read:'reads as triage over a candidate set', seed:'Rank these candidates for developability and show me the top 20.' },
  { m:/(proteom|mass spec|protein abundance)/i, lane:'Cloud · workflow', dom:'Proteomics',
    read:'reads as a quantitative proteomics comparison', seed:'Quantify differential protein abundance between my two groups.' },
  { m:/(single-?cell|cell type|composition|doublet)/i, lane:'Cloud · workflow', dom:'Transcriptomics',
    read:'reads as a single-cell composition question', seed:'Compare cell-type composition across my samples.' },
  { m:/(differential expression|rna-?seq|counts matrix|deseq|enrichment)/i, lane:'Cloud · workflow', dom:'Transcriptomics',
    read:'reads as a standardised differential-abundance analysis', seed:'Differential expression between treated and control, then GO enrichment.' },
  { m:/(variant calling|call variants|\bwgs\b|\bwes\b|\bvcf\b|burden test|contaminat|relatedness|clinically relevant variant)/i, lane:'Cloud · workflow', dom:'Genomics',
    read:'reads as a variant analysis over a sample set', seed:'Call variants on these samples and flag the clinically relevant ones.' },
  { m:/(cryo|density map|micrograph|fold|structure prediction)/i, lane:'Cloud · workflow', dom:'Structural biology',
    read:'reads as a structure determination or assessment task', seed:'Process this cryo-EM dataset to a density map and report the resolution.' },
  { m:/(cohort|stratif|\bsap\b|primary endpoint)/i, lane:'Cloud · workflow', dom:'Clinical',
    read:'reads as a cohort analysis against a pre-specified endpoint', seed:'Stratify this cohort by response and test the primary endpoint.' },
  { m:/(batch correction|batch effect|correct for batch)/i, lane:'Cloud · workflow', dom:'Transcriptomics',
    read:'reads as batch correction with a before-and-after check', seed:'Run batch correction and show me what survives.' },
  { m:/(experimental map|against my map|density fit|model-to-map|discrepanc)/i, lane:'Cloud · workflow', dom:'Structural biology',
    read:'reads as comparing a model against an experimental map', seed:'Compare this model against my experimental map and list the discrepancies.' },
  { m:/(statistical analysis plan|\bsap\b|pre-?specified plan|check this dataset against)/i, lane:'Cloud · workflow', dom:'Clinical',
    read:'reads as checking data against a pre-specified plan', seed:'Check this dataset against my statistical analysis plan.' },
  { m:/(submission|assemble the analysis section|regulatory package|ind\b)/i, lane:'Cloud · workflow', dom:'Assay quality',
    read:'reads as assembling an audit-ready section from finished runs', seed:'Assemble the analysis section of my submission from these runs.' },
  { m:/(run-to-run|batch quality|assay batch)/i, lane:'Cloud · workflow', dom:'Assay quality',
    read:'reads as a quality assessment across a batch', seed:'Assess run-to-run quality across this assay batch.' },

  /* Ad-hoc compute last: it is the cheap default, not a competitor. */
  { m:/(plot|summari|mean|median|correlat|reshape|table|dose.?response|plate|curve)/i, lane:'Instant · compute', dom:'Data analysis',
    read:'reads as a calculation on a file you already have', seed:'Summarise this assay table and plot potency against logP.' }
];

/* Self-test: every authored example must route to its own module. Logs any
   example that misroutes or matches nothing, so the promise the cards make
   cannot drift away from the router. */
window.ROUTE_LANE_OF_MODULE = { design:['Cloud · design'], models:['Cloud · models'], analysis:['Instant · compute', 'Cloud · workflow'], search:['Instant · search'] };
/* One source of truth: the pattern that DETECTS mechanism-narration is the
   same one that EXTRACTS the offending clause, so they cannot disagree. */
window.NARRATES_MECHANISM = /[^—.]*\b(?:(?:cloud|instant) lane|runs on the|routed? to|classif(?:ies|ied) as)\b[^.]*/i;
window.checkRoutes = () => {
  const bad = [];
  /* A self-test that throws is worse than no self-test: it reports nothing
     while looking like it passed. Any assertion that blows up becomes a
     finding instead of killing the suite. */
  const guard = (what, fn) => { try { fn(); } catch (e) { bad.push({ module:'SELF-TEST', ex:what, got:'assertion threw: ' + e.message }); } };
  const check = (label, ex, want) => {
    const hit = ROUTES.find(r => r.m.test(ex));
    if (!hit) bad.push({ module:label, ex, got:'NO MATCH' });
    else if (!want.includes(hit.lane)) bad.push({ module:label, ex, got:hit.lane + ' / ' + hit.dom });
  };
  MODULES.forEach(m => m.tracks.forEach(t => (t.ex || []).forEach(ex => check(m.k, ex, ROUTE_LANE_OF_MODULE[m.id]))));
  /* The pre-trained examples are clickable seeds too, so they are part of the
     same promise and must route to Models like everything else there. */
  (window.INFER || []).forEach(d => (d.ex || []).forEach(ex => check('INFER · ' + d.dom, ex, ['Cloud · models'])));
  ROUTES.forEach(r => { const h = ROUTES.find(x => x.m.test(r.seed)); if (h !== r) bad.push({ module:'ROUTE seed', ex:r.seed, got:(h ? h.dom : 'NO MATCH') + ' (expected ' + r.dom + ')' }); });
  /* The composer's lane preview is what the user actually reads before
     sending. It must resolve to the same lane the router will use, or the
     front door contradicts itself inside one interaction. */
  if (window.LANE_COPY) {
    const all = MODULES.flatMap(m => m.tracks.flatMap(t => t.ex || []))
      .concat((window.INFER || []).flatMap(d => d.ex || []))
      .concat(ROUTES.map(r => r.seed));
    all.forEach(ex => {
      const hit = ROUTES.find(r => r.m.test(ex));
      const lane = hit ? hit.lane : 'Instant · search';
      if (!LANE_COPY[lane]) bad.push({ module:'LANE PREVIEW', ex, got:'no sentence for lane ' + lane });
    });
    Object.keys(LANE_COPY).forEach(lane => guard('LANE_COPY ' + lane, () => {
      if (!ROUTES.some(r => r.lane === lane) && lane !== 'Instant · search') bad.push({ module:'LANE PREVIEW', ex:lane, got:'sentence for a lane no route emits' });
      const s = LANE_COPY[lane][1];
      /* Spec 06 §6.6.1 — the chip states the lane, so the sentence must not
         narrate the routing. Spec 06 §6.2 — an expensive lane must say how
         long it takes; that is the question this element exists to answer. */
      const m = s.match(NARRATES_MECHANISM);
      if (m) bad.push({ module:'LANE COPY', ex:lane, got:'narrates the mechanism: “' + m[0].trim() + '”' });
      if (/^Cloud/.test(lane) && !/\b(second|minute|hour|day)s?\b/i.test(s)) bad.push({ module:'LANE COPY', ex:lane, got:'expensive lane with no duration' });
    }));
  }
  /* The Connectors surface claims "each one carries where it lives". A row
     with no residency makes that claim false, and within one tab it is worse
     than false — the user cannot tell which rows move their data. */
  guard('CONNECTORS residency', () => {
    (window.CONNECTORS || []).forEach(k => k.rows.forEach(r => {
      if (!r[2]) bad.push({ module:'CONNECTORS', ex:k.k + ' · ' + r[0], got:'no residency' });
      else if (window.RESIDENCY && !window.RESIDENCY[r[2]]) bad.push({ module:'CONNECTORS', ex:k.k + ' · ' + r[0], got:'unknown residency ' + r[2] });
    }));
  });
  return bad;
};

/* Records for the symbolic viewer. */
window.RECORDS = {
  design: [
    ['S01','control','B1','F','58','kept'],['S02','control','B1','M','62','kept'],
    ['S03','control','—','F','47','kept · batch missing'],['S07','control','B2','M','51','excluded · 4.1 M reads'],
    ['S13','treated','B2','M','71','kept'],['S23','treated','B3','F','55','excluded · 3.7 M reads']
  ],
  report: [
    ['§1','Findings','412 genes move at FDR < 0.05; interferon signalling dominates.'],
    ['§2','Outputs','de_results.tsv · volcano.png · figure_1.svg'],
    ['§3','Methods','STAR → DESeq2 Wald → apeglm → BH.'],
    ['§4','Parameters','as resolved per step — see the deep-view of each.'],
    ['§5','Software','nf-core/rnaseq 3.14.0 · DESeq2 1.42.0 · apeglm 1.24.0'],
    ['§6','Citations','Love 2014 · Zhu 2019 · Dobin 2013'],
    ['§7','QC audit','gate 2 halted; suggestion applied, 2 samples excluded and listed.']
  ]
};
