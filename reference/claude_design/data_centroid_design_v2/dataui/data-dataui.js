/* BioMate data-centric prototype — fixtures. No real coverage counts anywhere. */
window.DOMAINS = [
  { id:'gen', name:'Genomics', sub:'variants, WGS / WES', shapes:[
    { t:'Call variants across a sample set and flag the clinically relevant ones', s:'FASTQ or BAM in → annotated variant table, ACMG-style flags, audit report out.', time:'~2 h', needs:'needs: reads + reference build', seed:'Call variants on these WGS samples and flag the clinically relevant ones. Human GRCh38.' },
    { t:'Compare variant burden between two cohorts', s:'Shape only — the pipeline, its version and its parameters resolve inside the session.', time:'~50 min', needs:'needs: two variant sets', seed:'Compare variant burden between my responder and non-responder cohorts.' },
    { t:'Check a sample set for contamination and relatedness before analysis', s:'A quality-first entry point: gates run first, findings come back as prose plus a report.', time:'~25 min', needs:'needs: reads', seed:'Check these samples for contamination and relatedness before I analyse them.' } ] },
  { id:'txn', name:'Transcriptomics', sub:'bulk & single-cell', shapes:[
    { t:'Differential expression between two conditions', s:'Counts or FASTQ in → ranked genes, enrichment, audit-ready report out.', time:'~40 min', needs:'needs: counts matrix + design', seed:'Differential expression between treated and control, then GO enrichment. Human GRCh38.' },
    { t:'Cell-type composition shift across samples', s:'Single-cell entry point. Quality gates cover doublets, ambient RNA and depth.', time:'~1.5 h', needs:'needs: count matrices per sample', seed:'Compare cell-type composition across my four single-cell samples.' },
    { t:'Batch-corrected integration of several datasets', s:'Three shapes per domain, chosen editorially — fixed at three, by design.', time:'~2 h', needs:'needs: 2+ matrices', seed:'Integrate these datasets with batch correction and show me what survives.' } ] },
  { id:'dd', name:'Drug discovery', sub:'ADMET, docking', shapes:[
    { t:'Screen a compound set for ADMET liabilities', s:'SMILES in → per-property predictions with confidence, liability summary, report out.', time:'~15 min', needs:'needs: SMILES or SDF', seed:'Screen these SMILES for ADMET liabilities and rank them by developability.' },
    { t:'Dock a series against a target and rank poses', s:'Structure-based entry point; gates cover pose plausibility, not just score.', time:'~1 h', needs:'needs: ligands + target structure', seed:'Dock this series against my target and rank the poses.' },
    { t:'Explain why a hit series is failing on one property', s:'Instant tier: cited reasoning over literature, with the compute lane available inline.', time:'seconds', needs:'needs: nothing but the question', seed:'Why might this hit series be failing on hERG? Cite the evidence.' } ] },
  { id:'str', name:'Structural biology', sub:'cryo-EM, folding', shapes:[
    { t:'Process a cryo-EM set to a density map', s:'Micrographs in → refined map, resolution estimate, slice viewer, report out.', time:'~6 h', needs:'needs: micrographs', seed:'Process this cryo-EM dataset to a density map and report the resolution.' },
    { t:'Predict and assess a structure for a sequence', s:'Confidence per residue travels with the output, so downstream use inherits it.', time:'~30 min', needs:'needs: sequence', seed:'Predict the structure for this sequence and tell me where to trust it.' },
    { t:'Compare a model against an experimental map', s:'Validation-first shape: the deliverable is the discrepancy list.', time:'~20 min', needs:'needs: model + map', seed:'Compare this model against my experimental map and list the discrepancies.' } ] },
  { id:'clin', name:'Clinical', sub:'cohorts, endpoints', shapes:[
    { t:'Stratify a cohort by response and test the endpoint', s:'Table in → stratification, endpoint test with pre-registered method, report out.', time:'~20 min', needs:'needs: cohort table', seed:'Stratify this cohort by response and test the primary endpoint.' },
    { t:'Check a dataset against a statistical analysis plan', s:'The gates are the product: what the SAP requires versus what the data supports.', time:'~15 min', needs:'needs: cohort table + SAP', seed:'Check this dataset against my statistical analysis plan.' },
    { t:'Assemble the analysis section of a submission', s:'Ends in the IND report surface, with every number traced to a run.', time:'~1 h', needs:'needs: completed runs', seed:'Assemble the analysis section of my submission from these runs.' } ] },
  { id:'prot', name:'Proteomics', sub:'mass spec, abundance', shapes:[
    { t:'Quantify differential protein abundance between groups', s:'Search results in → normalised abundance, differential table, report out.', time:'~45 min', needs:'needs: search output + design', seed:'Quantify differential protein abundance between my two groups.' },
    { t:'Reconcile a proteomic signal with a transcriptomic one', s:'Cross-domain shape — two of your datasets, one narrative.', time:'~35 min', needs:'needs: two result tables', seed:'Reconcile my proteomic signal with the transcriptomic result.' },
    { t:'Assess run-to-run quality across a batch', s:'Quality-first again: the amber cases are the answer.', time:'~20 min', needs:'needs: raw or search output', seed:'Assess run-to-run quality across this proteomics batch.' } ] }
];
window.INSTANT = [
  { id:'ask', k:'Ask', t:'A cited answer', s:'Literature plus curated scientific databases. Every claim carries its reference, so the answer is checkable rather than plausible.', ex:'“What is known about this target in fibrosis?”', seed:'What is the evidence linking this target to fibrosis? Cite it.' },
  { id:'compute', k:'Compute', t:'Code that runs on your data', s:'A statistic, a plot, a table — written and executed in a secure sandbox against the file you attach. The code is shown, so the result is reproducible.', ex:'“Summarise this table and plot the two arms.”', seed:'Summarise this table and plot the two arms.' },
  { id:'experts', k:'Experts', t:'Reasoning packs you switch on', s:'Domain judgement layered over either lane — pharmacology, regulatory, biostatistics and more. Toggled in the composer, never browsed as a directory.', ex:'2 packs on for this workspace', seed:'' }
];
window.EMPTY_TILES = [
  { d:'Genomics', q:'“Call variants on these WGS samples and flag the clinically relevant ones.”', tier:'cloud', seed:'Call variants on these WGS samples and flag the clinically relevant ones.' },
  { d:'Transcriptomics', q:'“Which genes move between my treated and control groups?”', tier:'cloud', seed:'Differential expression between treated and control, then GO enrichment.' },
  { d:'Drug discovery', q:'“Screen these SMILES for ADMET liabilities.”', tier:'cloud', seed:'Screen these SMILES for ADMET liabilities.' },
  { d:'Literature', q:'“What is the evidence linking this target to fibrosis?”', tier:'instant', seed:'What is the evidence linking this target to fibrosis? Cite it.' },
  { d:'Structural', q:'“Process this cryo-EM set to a density map.”', tier:'cloud', seed:'Process this cryo-EM dataset to a density map.' },
  { d:'Clinical', q:'“Stratify this cohort by response and test the endpoint.”', tier:'cloud', seed:'Stratify this cohort by response and test the primary endpoint.' },
  { d:'My own data', q:'“Summarise this table and plot the two arms.”', tier:'instant', seed:'Summarise this table and plot the two arms.' },
  { d:'Something else', q:'Describe it in plain language — routing is automatic.', tier:'any', seed:'' }
];

/* ── datasets ─────────────────────────────────────── */
window.DATASETS = [
  { id:'d1', name:'GSE184880_counts.tsv', init:'CT', kind:'counts matrix', quality:'pass',
    hash:'sha256:9f2c…a41e', scope:'project', scopeNote:'Fibrosis target triage — shareable to the account',
    appearsIn:[['Chat attachment','2 sessions'],['Input mapping','1 workflow slot'],['Project files','Fibrosis target triage'],['Run outputs','—']],
    dupes:[['GSE184880_counts (1).tsv','re-uploaded 14 Aug, same content hash — merged into this dataset']],
    origin:{ type:'Public repository', label:'GEO · GSE184880', by:'you', when:'12 Aug 2026', note:'Fetched through the repository browser. Checksum recorded; the fetch is replayable from the audit trail.' },
    stats:[['Rows','38,214'],['Columns','24'],['Missing','0.4%'],['Size','14.2 MB']],
    qnotes:[['pass','24 columns match the declared sample design'],['pass','gene identifiers resolve against GRCh38 (99.7%)'],['watch','two samples sit below the library-size floor — kept, flagged']],
    preview:'counts table · 38,214 × 24', runs:['r1','r2'], derived:['o1','o2','o3'] },
  { id:'d2', name:'design.csv', init:'DS', kind:'sample design', quality:'watch',
    hash:'sha256:1b07…c8d2', scope:'project', scopeNote:'Fibrosis target triage only — not visible to other projects yet',
    appearsIn:[['Chat attachment','1 session'],['Input mapping','1 workflow slot'],['Project files','Fibrosis target triage']], dupes:[],
    origin:{ type:'Local upload', label:'design.csv', by:'you', when:'12 Aug 2026', note:'Dropped into the ingest panel alongside the counts matrix. No repository record, so provenance stops here.' },
    stats:[['Rows','24'],['Columns','5'],['Missing','8.3%'],['Size','1.1 KB']],
    qnotes:[['watch','the condition column contains two spellings of “control”'],['watch','batch is missing for two samples'],['pass','sample ids match the counts matrix exactly']],
    preview:'table · 24 × 5', runs:['r1'], derived:[] },
  { id:'d3', name:'cohort_variants.vcf.gz', init:'VC', kind:'variant call set', quality:'pass',
    hash:'sha256:74ea…30bb', scope:'account', scopeNote:'Account-wide — already reused in two projects without re-uploading',
    appearsIn:[['Project files','MG stratification'],['Project files','Cryo-EM batch 12']], dupes:[],
    origin:{ type:'Local upload', label:'cohort_variants.vcf.gz', by:'A. Dike', when:'9 Aug 2026', note:'Uploaded from the sequencing core delivery. Index present, contigs match GRCh38.' },
    stats:[['Variants','4,812,006'],['Samples','96'],['Missing','0.9%'],['Size','1.8 GB']],
    qnotes:[['pass','contigs and reference build consistent'],['pass','no sample-swap signal in the relatedness check']],
    preview:'variant records · 4.8 M', runs:[], derived:[] },
  { id:'o1', name:'de_results.tsv', init:'DE', kind:'derived · results table', quality:'watch', derivedFrom:'r1',
    hash:'sha256:c355…7f10', scope:'project', scopeNote:'Inherits the scope of the run that produced it',
    appearsIn:[['Run outputs','Differential expression'],['Chat attachment','1 session'],['Input mapping','2 workflow slots']], dupes:[],
    origin:{ type:'Produced by a run', label:'Bulk RNA-seq differential expression', by:'BioMate', when:'14 Aug 2026', note:'An output is a dataset. It inherits the weakest badge upstream — amber here, because the sample design was amber.' },
    stats:[['Rows','18,402'],['Columns','7'],['Missing','0%'],['Size','2.4 MB']],
    qnotes:[['pass','all four QC gates of the producing run passed'],['watch','inherited: sample design was amber (condition spelling)']],
    preview:'results table · 18,402 × 7', runs:['r2','r3'], derived:[] },
  { id:'rep1', name:'after-run_report.md', init:'RP', kind:'report · after-run', quality:'watch', derivedFrom:'r1',
    hash:'sha256:2ad9…b604', scope:'project', scopeNote:'Inherits the scope of the run that produced it',
    appearsIn:[['Run outputs','Differential expression'],['Project files','Fibrosis target triage']], dupes:[],
    origin:{ type:'Produced by a run', label:'Bulk RNA-seq differential expression', by:'BioMate', when:'14 Aug 2026', note:'Written from the project memo template v2. It is a file like any other: editable by hand, editable by asking, versioned, and downloadable in the formats people actually hand over.' },
    stats:[['Sections','5'],['Words','412'],['Citations','2'],['Size','9 KB']],
    qnotes:[['pass','every number in it resolves to an output of the run'],['watch','inherited: the sample design was amber']],
    preview:'document · 5 sections', runs:[], derived:[] },
  { id:'ans1', name:'evidence_IL11-fibrosis.md', init:'EV', kind:'document · saved answer', quality:'pass',
    hash:'sha256:5c81…9de2', scope:'project', scopeNote:'Fibrosis target triage — shareable to the account',
    appearsIn:[['Saved from a search','Literature'],['Project files','Fibrosis target triage']], dupes:[],
    origin:{ type:'Saved from a search', label:'Literature · IL-11 and idiopathic pulmonary fibrosis', by:'A. Dike', when:'2 Sep 2026', note:'Nothing ran on your data to produce this — it is a cited answer, saved so the next person asking gets the answer rather than the search. The retrieval that produced it is recorded with it.' },
    stats:[['Sections','4'],['References','7'],['Index date','2 Sep 2026'],['Size','6 KB']],
    qnotes:[['pass','every claim carries a reference, and every link resolved'],['pass','contradicting evidence kept in the record rather than dropped']],
    preview:'document · 4 sections', runs:[], derived:[] }
];
window.RUNS = {
  r1:{ id:'r1', name:'Bulk RNA-seq differential expression', status:'completed', version:'v1.4.2', dur:'41 min', when:'14 Aug 2026',
       gates:'4 / 4 gates passed', steps:3, inputs:[['counts matrix','d1','high','column headers and gene ids match the expected schema exactly'],['sample design','d2','medium','the condition column was normalised — two spellings of “control” merged']], outputs:['o1','o2','o3'] },
  r2:{ id:'r2', name:'GO enrichment', status:'failed', version:'v0.9.1', dur:'6 min', when:'15 Aug 2026',
       gates:'blocked at gate 2', steps:2, inputs:[['ranked genes','o1','high','a direct output of the previous run']], outputs:[] },
  r3:{ id:'r3', name:'Pathway scoring', status:'running', version:'v2.0.0', dur:'12 min elapsed', when:'16 Aug 2026',
       gates:'gates pending', steps:4, inputs:[['ranked genes','o1','high','a direct output of the previous run']], outputs:[] }
};
window.OUTPUTS = {
  o1:{ id:'o1', name:'de_results.tsv', kind:'table', meta:'18,402 rows · reused as an input', isDataset:true },
  o2:{ id:'o2', name:'volcano.png', kind:'figure', meta:'1600 × 1200' },
  o3:{ id:'o3', name:'after-run.pdf', kind:'report', meta:'findings · methods · citations · QC audit' }
};
window.CHAT_TAPE = [
  { who:'you', text:'Differential expression between treated and control, then GO enrichment. Human GRCh38.', chips:['d1','d2'] },
  { who:'bm', kind:'mapping', text:'Mapped to a validated pipeline — **Bulk RNA-seq Differential Expression**, 3 steps. Inputs resolved from the two files you attached:', run:'r1' },
  { who:'bm', kind:'steps', text:'', steps:[['ok','nf-core/rnaseq — 24 samples aligned'],['ok','differential abundance — 18,402 genes tested'],['warn','QC gate 3 — two low-depth samples excluded, noted in the report'],['ok','Workflow finished · 41 min']] },
  { who:'bm', kind:'result', text:'**412 genes** move at FDR < 0.05. The report is on the right; `de_results.tsv` is now a dataset in its own right, so the enrichment run can take it as an input.', outputs:['o1','o2','o3'] }
];

/* Finding 5 — one source registry every surface reads from. Grouped by kind, never counted. */
window.SOURCE_GROUPS = [
  { k:'Sequence & expression archives', note:'Read by chat, workflow generation and Connectors from the same registry.', items:['GEO','SRA','ENA','ArrayExpress','Expression Atlas'] },
  { k:'Variant & population', note:'', items:['gnomAD','ClinVar','dbSNP','1000 Genomes'] },
  { k:'Structures & maps', note:'', items:['PDB','EMDB','AlphaFold DB'] },
  { k:'Chemistry & pharmacology', note:'', items:['ChEMBL','PubChem','DrugBank','BindingDB'] },
  { k:'Pathways & annotation', note:'', items:['Ensembl','UniProt','Reactome','GO','KEGG'] },
  { k:'Literature', note:'', items:['PubMed','Europe PMC','bioRxiv'] }
];

/* ── real values for exploration & charts ─────────────────────
   Deterministic pseudo-data so plots are honest about the fixture. */
(function () {
  let s = 42; const R = () => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648;
  const norm = () => { let u = 0, v = 0; while (!u) u = R(); while (!v) v = R(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); };

  window.PROFILES = {
    d1: {
      columns: [
        { n:'gene_id', t:'string', miss:0, note:'Ensembl ids · 99.7% resolve against GRCh38', uniq:'38,214 unique' },
        { n:'gene_name', t:'string', miss:1.2, note:'HGNC symbols · 462 blank', uniq:'36,918 unique' },
        { n:'CTRL_01 … CTRL_12', t:'integer', miss:0, note:'raw counts · median 812', uniq:'12 columns' },
        { n:'TREAT_01 … TREAT_12', t:'integer', miss:0, note:'raw counts · median 774', uniq:'12 columns' }
      ],
      rows: [
        ['ENSG00000141510','TP53','1204','1187','980','1042'],
        ['ENSG00000012048','BRCA1','311','298','402','377'],
        ['ENSG00000171862','PTEN','842','869','651','688'],
        ['ENSG00000133703','KRAS','1553','1498','1610','1702'],
        ['ENSG00000146648','EGFR','96','88','412','455'],
        ['ENSG00000232810','TNF','44','51','268','301']
      ],
      cols: ['gene_id','gene_name','CTRL_01','CTRL_02','TREAT_01','TREAT_02'],
      libsize: [18.2,17.6,19.1,16.8,18.9,17.2,4.1,18.4,17.9,18.6,3.7,17.1,19.4,18.8,17.5,18.2,19.0,17.8,18.3,16.9,18.7,17.4,18.1,18.5],
      libLabels: Array.from({length:24},(_,i)=> (i<12?'CTRL_':'TREAT_') + String((i%12)+1).padStart(2,'0')),
      libFloor: 8,
      pca: Array.from({length:24},(_,i)=>({ x: (i<12? -1: 1) * (1.4 + R()*0.9) + norm()*0.35, y: norm()*1.1, g: i<12?'CTRL':'TREAT', l:(i<12?'CTRL_':'TREAT_')+String((i%12)+1).padStart(2,'0'), flag:(i===6||i===10) })),
      volcano: null
    },
    o1: {
      columns: [
        { n:'gene_id', t:'string', miss:0, note:'matches the input matrix exactly', uniq:'18,402 unique' },
        { n:'log2FC', t:'float', miss:0, note:'range −6.2 … 7.1', uniq:'—' },
        { n:'pvalue', t:'float', miss:0, note:'Wald test', uniq:'—' },
        { n:'padj', t:'float', miss:0.4, note:'BH · 412 below 0.05', uniq:'—' },
        { n:'baseMean', t:'float', miss:0, note:'median 214', uniq:'—' }
      ],
      rows: [
        ['ENSG00000232810','TNF','2.84','1.2e-11','4.1e-08'],
        ['ENSG00000146648','EGFR','2.11','8.7e-09','1.9e-06'],
        ['ENSG00000141510','TP53','-0.42','0.021','0.087'],
        ['ENSG00000171862','PTEN','-0.61','0.004','0.031'],
        ['ENSG00000012048','BRCA1','0.38','0.11','0.29']
      ],
      cols: ['gene_id','gene_name','log2FC','pvalue','padj'],
      volcano: Array.from({length:340},()=>{ const x = norm()*2.2; const p = Math.min(11, Math.abs(x)*1.6 + Math.abs(norm())*1.1); return { x, y:p, sig: Math.abs(x)>1 && p>2.6 }; }),
      libsize:null, pca:null
    }
  };
  window.PROFILES.d2 = {
    columns: [
      { n:'sample_id', t:'string', miss:0, note:'matches the counts matrix', uniq:'24 unique' },
      { n:'condition', t:'category', miss:0, note:'two spellings of “control” — normalised at mapping', uniq:'3 values, should be 2', bad:true },
      { n:'batch', t:'category', miss:8.3, note:'missing for 2 samples', uniq:'3 values', bad:true },
      { n:'sex', t:'category', miss:0, note:'', uniq:'2 values' },
      { n:'age', t:'integer', miss:0, note:'range 41 … 78', uniq:'—' }
    ],
    rows: [['S01','control','B1','F','58'],['S02','Control','B1','M','62'],['S03','control','—','F','47'],['S04','treated','B2','M','71'],['S05','treated','B2','F','55']],
    cols: ['sample_id','condition','batch','sex','age'], libsize:null, pca:null, volcano:null
  };
  window.PROFILES.d3 = {
    columns: [
      { n:'CHROM / POS', t:'locus', miss:0, note:'GRCh38 contigs', uniq:'4,812,006 records' },
      { n:'REF / ALT', t:'string', miss:0, note:'', uniq:'—' },
      { n:'QUAL', t:'float', miss:0, note:'median 48.2', uniq:'—' },
      { n:'96 sample genotypes', t:'genotype', miss:0.9, note:'no sample-swap signal', uniq:'96 columns' }
    ],
    rows: [['chr1','942451','T','C','62.1','0/1'],['chr1','1014143','G','A','48.9','1/1'],['chr2','21012512','C','T','51.4','0/1'],['chr7','55181378','G','T','39.8','0/1']],
    cols: ['CHROM','POS','REF','ALT','QUAL','S01'], libsize:null, pca:null, volcano:null
  };
})();

/* Which task shapes a dataset can actually feed — the analysis launch points. */
window.NEXT_FOR = {
  d1: [['txn',0,'ready'],['txn',1,'needs a per-cell matrix'],['txn',2,'ready']],
  d2: [['txn',0,'pairs with a counts matrix']],
  d3: [['gen',0,'ready'],['gen',1,'needs a second cohort'],['gen',2,'ready']],
  o1: [['txn',2,'ready'],['dd',2,'ready']]
};

/* Project tree, matching the shipped sidebar: projects expand to their chats. */
window.PROJECTS = [
  { name:'Fibrosis target triage', datasets:3, chats:[
    { id:'s1', title:'Paired-end RNA-seq analysis', run:true, data:['d1','d2','o1'], when:'14 Aug' },
    { id:'s2', title:'Target evidence review', run:false, data:[], when:'12 Aug' },
    { id:'s3', title:'New Chat', run:false, data:[], when:'today' } ] },
  { name:'MG stratification', datasets:1, chats:[{ id:'s4', title:'Cohort stratification', run:false, data:['d3'], when:'9 Aug' }] },
  { name:'ADMET screen — series 4', datasets:2, chats:[{ id:'s5', title:'Series 4 liabilities', run:false, data:[], when:'8 Aug' }] },
  { name:'Cryo-EM batch 12', datasets:1, chats:[] }
];
window.SESSION_OF = { d1:['s1'], d2:['s1'], o1:['s1'], d3:['s4'] };

/* Project-level instructions, output requirements and notes. */
/* The account library of skills and experts: what Connectors lists, flat, so
   a project selector and the composer read the same names. */
window.ACCOUNT_ADDONS = [
  'Write an IND 2.6.2 section', 'Build a figure to spec', 'Assemble a deposit archive',
  'Fit dose–response curves', 'Depict structures', 'Resolve compound identity',
  'Pharmacology', 'Regulatory', 'Biostatistics', 'Structural biology', 'Clinical trials', 'Bioinformatics QC'
];
/* Per project: which of them are on. Anything unlisted is off. */
window.PROJECT_SETUP = {
  'Fibrosis target triage': {
    rules: [
      'Human GRCh38 (Ensembl 110) unless a session says otherwise — never mix builds within a comparison.',
      'Report significance at FDR < 0.05 with the test named; do not report nominal p-values as headline numbers.',
      'Exclude samples that fail the library-size gate rather than imputing, and list every exclusion in the report.',
      'Cite a primary source for any claim about the target; review articles are supporting evidence, not evidence.',
      'Flag anything that would need IRB or data-use review before it leaves the project.'
    ],
    outputs: [
      ['report', 'Internal target-triage memo', 'Findings first (max 200 words), then methods, then the QC audit. Figures at 300 dpi, greyscale-safe palette.', true],
      ['figure', 'Manuscript figure spec', 'Vector SVG, Arial 8 pt axis labels, no chart junk, panel letters bottom-left.', true],
      ['table', 'Supplementary table format', 'One sheet per contrast, gene id in column A, effect size before p-value.', false],
      ['naming', 'File naming convention', '<project>_<assay>_<contrast>_<yyyymmdd> — applied at ingest and to every output.', true]
    ],
    addons: [['Regulatory', true], ['Pharmacology', false], ['Biostatistics', true],
             ['Write an IND 2.6.2 section', false], ['Build a figure to spec', true],
             ['Assemble a deposit archive', true], ['Fit dose–response curves', false]],
    notes: 'Collaborator prefers effect sizes over fold-change language in writing.\nThe 2 low-depth samples came from the second sequencing batch — the core is re-running them; do not delete.\nOpen question for the 21 Aug meeting: is the fibrosis signature confounded by age?'
  },
  'ADMET screen — series 4': {
    rules: [
      'Safety gates are floors, not objectives — never trade hERG margin for potency.',
      'Report predicted values with the model, its version and a confidence; never a bare number.',
      'Keep censored assay values censored: IC50 > 30 µM is an inequality, not 30.'
    ],
    outputs: [
      ['table', 'Series triage sheet', 'One row per candidate: per-objective values with units, confidence, gate verdict.', true],
      ['report', 'Round summary', 'Predicted versus measured for the round, then what the surrogate learned.', true]
    ],
    addons: [['Pharmacology', true], ['Regulatory', false], ['Biostatistics', false],
             ['Depict structures', true], ['Resolve compound identity', true],
             ['Fit dose–response curves', true], ['Build a figure to spec', false]],
    notes: 'Chemistry will not make anything with an unprotected aniline — excluded at generation, not at ranking.'
  },
  default: {
    rules: ['No standing instructions yet — anything you add here applies to every session in this project.'],
    outputs: [],
    addons: [],
    notes: 'No notes yet.'
  }
};

/* The existing file system: folders per project, plus per-file versions. */
window.FILETREE = {
  'Fibrosis target triage': [
    { folder:'uploads/', files:['d1','d2'] },
    { folder:'runs/2026-08-14_differential-expression/', files:['o1','rep1'] },
    { folder:'notes/', files:['ans1'] },
    { folder:'shared/ (account scope)', files:['d3'] }
  ],
  default: [{ folder:'uploads/', files:[] }]
};
window.VERSIONS = {
  d2: [
    { v:3, what:'condition column normalised — two spellings of “control” merged', by:'A. Dike', when:'14 Aug 2026, 09:12' },
    { v:2, what:'batch filled in for two samples', by:'A. Dike', when:'13 Aug 2026, 16:40', usedBy:'no runs' },
    { v:1, what:'uploaded from the sequencing core delivery', by:'A. Dike', when:'12 Aug 2026, 11:03', usedBy:'differential expression (first attempt)' }
  ],
  d1: [
    { v:2, what:'two low-depth samples flagged (no data changed)', by:'BioMate · quality check', when:'12 Aug 2026, 11:20' },
    { v:1, what:'fetched from GEO GSE184880', by:'A. Dike', when:'12 Aug 2026, 11:18' }
  ],
  o1: [{ v:1, what:'written by the differential-expression run', by:'BioMate', when:'14 Aug 2026, 14:02' }],
  rep1: [{ v:1, what:'written by the run, from the project memo template v2', by:'BioMate', when:'14 Aug 2026, 14:04' }],
  ans1: [{ v:1, what:'saved from a literature search, with its retrieval record', by:'A. Dike', when:'2 Sep 2026, 10:41' }],
  d3: [{ v:1, what:'uploaded from the sequencing core delivery', by:'A. Dike', when:'9 Aug 2026' }]
};
/* A run reads a different version of each input, so this is keyed per (run, file). */
window.RUNS.r1.usedVersions = { d1:2, d2:3 };
window.RUNS.r2.usedVersions = { o1:1 };
window.RUNS.r3.usedVersions = { o1:1 };
