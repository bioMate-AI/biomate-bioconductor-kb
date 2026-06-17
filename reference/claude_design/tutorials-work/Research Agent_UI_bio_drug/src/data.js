// Workflow scenario data. Keep this pure-data — no React here.
// Status values: 'pending' | 'running' | 'completed' | 'failed' | 'skipped'

const CRYOSPARC = {
  id: 'cryosparc',
  name: 'CryoSPARC SPA',
  subtitle: 'Single-particle analysis · 23 processes · 5 phases',
  domain: 'Cryo-EM',
  query: 'Run single-particle reconstruction on EMPIAR-10025 with 1.3 Å/px',
  globalParams: [
    { key: 'input',        label: 'Input micrographs',  value: 's3://cryo-data/empiar-10025/*.mrc' },
    { key: 'pixel_size',   label: 'Pixel size (Å)',     value: '1.30' },
    { key: 'accel_kv',     label: 'Acceleration (kV)',  value: '300' },
    { key: 'outdir',       label: 'Output directory',   value: 'results/cryosparc_2026-04-19/' },
    // { key: 'max_cpus',     label: 'Max CPUs',           value: '32' },     // commented out, leaving for future work
    // { key: 'max_memory',   label: 'Max memory',         value: '128 GB' }, // commented out, leaving for future work
  ],
  phases: [
    {
      id: 'A', name: 'Motion Correction + CTF',
      summary: 'Align beam-induced motion and estimate CTF per micrograph',
      steps: [
        { id: 'motioncor2',   name: 'MotionCor2',    status: 'completed',
          params: [{k:'patch_x',v:'5'},{k:'patch_y',v:'5'},{k:'max_shift',v:'20 Å'}],
          outputs: [
            {name:'motion_trace.star', type:'table', viz:'motion'},
            {name:'aligned_sums/', type:'folder', viz:'micrographs'},
          ]
        },
        { id: 'gctf',         name: 'Gctf',          status: 'completed',
          params: [{k:'resolution_range',v:'3.0–30 Å'},{k:'defocus_range',v:'0.5–4.0 µm'}],
          outputs: [
            {name:'ctf_estimates.star', type:'table', viz:'ctf_table'},
            {name:'ctf_diagnostic.png', type:'image', viz:'thon_rings'},
          ]
        },
        { id: 'ctffind4',     name: 'CTFFind4',      status: 'running',
          params: [{k:'box_size',v:'512'},{k:'min_resolution',v:'30 Å'}],
          outputs: []
        },
        { id: 'ctf_filter',   name: 'CTFFilter',     status: 'pending', params: [], outputs: [] },
        { id: 'ctf_qc',       name: 'CTFQualityGate',status: 'pending', params: [], outputs: [] },
      ],
      qc: [
        { metric: 'ctf_fit_quality', op: '>', threshold: '0.2' },
        { metric: 'astigmatism',     op: '<', threshold: '500 Å' },
      ],
      autoloop: false,  // off by default — trips halt card; user accepts/edits suggestion
    },
    {
      id: 'B', name: 'Particle Picking',
      summary: 'Template-free particle detection and extraction',
      steps: [
        { id: 'topaz_train',  name: 'Topaz Train',    status: 'pending',
          params: [{k:'arch',v:'resnet8'},{k:'epochs',v:'10'}],
          outputs: [
            {name:'topaz_model.pt', type:'table', viz:'training_curve'},
          ]
        },
        { id: 'topaz_pick',   name: 'Topaz Pick',     status: 'pending',
          params: [{k:'threshold',v:'-2'}],
          outputs: [
            {name:'particles.star', type:'table', viz:'pick_overlay'},
          ]
        },
        { id: 'extract',      name: 'Extract',        status: 'pending', params: [{k:'box_size',v:'320 px'}],
          outputs: [
            {name:'particle_stack.mrcs', type:'image', viz:'particle_grid'},
          ]
        },
        { id: 'rebalance',    name: 'Rebalance',      status: 'pending', params: [], outputs: [] },
      ],
      qc: [
        { metric: 'particle_count', op: '>', threshold: '50k' },
      ],
      autoloop: true,
    },
    {
      id: 'C', name: '2D Classification',
      summary: 'Reference-free 2D class averaging',
      steps: [
        { id: 'cls2d_1',  name: '2D Classify (50 classes)', status: 'pending', params: [{k:'iterations',v:'25'}],
          outputs: [
            {name:'2d_classes_round1.mrcs', type:'image', viz:'class2d'},
          ]
        },
        { id: 'cls2d_2',  name: 'Select Good Classes',      status: 'pending', params: [], outputs: [] },
        { id: 'cls2d_3',  name: '2D Classify (round 2)',    status: 'pending', params: [],
          outputs: [
            {name:'2d_classes_round2.mrcs', type:'image', viz:'class2d_clean'},
          ]
        },
        { id: 'cls2d_4',  name: 'Inspect',                  status: 'pending', params: [], outputs: [] },
        { id: 'cls2d_5',  name: 'Particle Subset',          status: 'pending', params: [], outputs: [] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'D', name: '3D Reconstruction',
      summary: 'Ab-initio model + homogeneous refinement',
      steps: [
        { id: 'abinit',   name: 'Ab-Initio (3 classes)',   status: 'pending', params: [],
          outputs: [
            {name:'abinit_classes.mrc', type:'image', viz:'volume_slices'},
          ]
        },
        { id: 'het_refine', name: 'Heterogeneous Refine', status: 'pending', params: [], outputs: [] },
        { id: 'hom_refine', name: 'Homogeneous Refine',   status: 'pending', params: [],
          outputs: [
            {name:'half_map_A.mrc', type:'image', viz:'volume_iso'},
            {name:'half_map_B.mrc', type:'image', viz:'volume_iso'},
          ]
        },
        { id: 'nu_refine',  name: 'Non-Uniform Refine',   status: 'pending', params: [], outputs: [] },
        { id: 'local_refine', name: 'Local Refinement',   status: 'pending', params: [], outputs: [] },
      ],
      qc: [
        { metric: 'gsfsc_resolution', op: '<', threshold: '4.0 Å' },
      ],
      autoloop: true,
    },
    {
      id: 'E', name: 'FSC Validation',
      summary: 'Resolution estimation and validation',
      steps: [
        { id: 'fsc_mask',     name: 'FSC Mask',          status: 'pending', params: [],
          outputs: [
            {name:'fsc_mask.mrc', type:'image', viz:'mask_slice'},
          ]
        },
        { id: 'fsc_gold',     name: 'Gold-Standard FSC', status: 'pending', params: [],
          outputs: [
            {name:'gsfsc.csv', type:'table', viz:'fsc_curve'},
          ]
        },
        { id: 'val_report',   name: 'Validation Report', status: 'pending', params: [],
          outputs: [
            {name:'validation.pdf', type:'table', viz:'val_report'},
          ]
        },
        { id: 'sharpen',      name: 'B-Factor Sharpen',  status: 'pending', params: [{k:'b_factor',v:'auto'}],
          outputs: [
            {name:'sharpened_map.mrc', type:'image', viz:'volume_sharp'},
          ]
        },
      ],
      qc: [
        { metric: 'gsfsc_0143', op: '<', threshold: '3.5 Å' },
      ],
      autoloop: true,
    },
  ],
};

const GATK = {
  id: 'gatk',
  name: 'WGS Germline — GATK4',
  subtitle: 'Short-variant calling · 8 processes · 3 phases',
  domain: 'Genomics',
  query: 'Call germline variants on SRR123456 with GATK4, hg38',
  globalParams: [
    { key: 'input',    label: 'Reads (paired FASTQ)', value: 'SRR123456_{1,2}.fastq.gz' },
    { key: 'genome',   label: 'Reference genome',     value: 'hg38' },
    { key: 'outdir',   label: 'Output directory',     value: 'results/gatk_2026-04-19/' },
    { key: 'aligner',  label: 'Aligner',              value: 'bwa-mem2' },
    { key: 'caller',   label: 'Variant caller',       value: 'HaplotypeCaller' },
    // { key: 'max_cpus', label: 'Max CPUs',             value: '16' }, // commented out, leaving for future work
  ],
  phases: [
    {
      id: 'A', name: 'Alignment',
      summary: 'Index, align paired reads, sort BAM',
      steps: [
        { id: 'fastqc',      name: 'FastQC',          status: 'pending', params: [{k:'threads',v:'4'}], outputs: [] },
        { id: 'bwa_mem2',    name: 'BWA-MEM2 Align',  status: 'pending', params: [{k:'threads',v:'16'},{k:'mark_shorter_splits',v:'true'}], outputs: [] },
        { id: 'sort_bam',    name: 'Sort + Index BAM',status: 'pending', params: [], outputs: [] },
      ],
      qc: [{ metric: 'mapping_rate', op: '>', threshold: '95%' }],
      autoloop: false,
    },
    {
      id: 'B', name: 'Preprocessing',
      summary: 'Mark duplicates, BQSR',
      steps: [
        { id: 'markdup',  name: 'MarkDuplicatesSpark', status: 'pending', params: [], outputs: [] },
        { id: 'bqsr',     name: 'BaseRecalibrator',    status: 'pending', params: [{k:'known_sites',v:'dbSNP v155'}], outputs: [] },
        { id: 'apply_bqsr', name: 'ApplyBQSR',          status: 'pending', params: [], outputs: [] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'C', name: 'Variant Calling',
      summary: 'HaplotypeCaller + filter',
      steps: [
        { id: 'hc',       name: 'HaplotypeCaller',   status: 'pending', params: [{k:'emit_ref_confidence',v:'GVCF'}], outputs: [] },
        { id: 'filter',   name: 'VariantFiltration', status: 'pending', params: [], outputs: [] },
      ],
      qc: [{ metric: 'ts_tv_ratio', op: 'between', threshold: '2.0–2.1' }],
      autoloop: false,
    },
  ],
};

const ADMET = {
  id: 'admet',
  name: 'ADMET Property Prediction',
  subtitle: 'Single process · 1 step · no phases',
  domain: 'Drug discovery',
  query: 'Run ADMET prediction for aspirin',
  globalParams: [
    { key: 'smiles',   label: 'SMILES',           value: 'CC(=O)Oc1ccccc1C(=O)O', note: 'auto-filled from query' },
    { key: 'endpoints',label: 'Endpoints',        value: 'absorption, hERG, CYP, hepatotox' },
    { key: 'outdir',   label: 'Output directory', value: 'results/admet_2026-04-19/' },
  ],
  phases: [
    {
      id: 'A', name: 'ADMET Prediction',
      summary: 'Single-step property predictor',
      steps: [
        { id: 'admet_pred', name: 'Admet Pred Workflow', status: 'pending',
          params: [{k:'model',v:'admet-ai v2.1'},{k:'device',v:'cpu'}],
          outputs: []
        },
      ],
      qc: [
        { metric: 'herg_ic50', op: '>', threshold: '10 µM' },
      ],
      autoloop: true,
    },
  ],
};

const NFCORE = {
  id: 'nfcore',
  name: 'nf-core · fastp QC',
  subtitle: 'Multi-accession QC · 4 processes · 2 phases',
  domain: 'Genomics',
  query: 'Run fastp QC on SRR14265340 and SRR14265341',
  globalParams: [
    { key: 'accessions', label: 'SRA accessions', value: 'SRR14265340, SRR14265341' },
    { key: 'outdir',     label: 'Output directory', value: 'results/fastp_2026-04-19/' },
    // { key: 'max_cpus',   label: 'Max CPUs',          value: '8' }, // commented out, leaving for future work
  ],
  phases: [
    { id: 'A', name: 'Download & Stage', summary: 'Fetch reads from SRA, stage on shared FS',
      steps: [
        { id: 'sra_pref',   name: 'SRA Prefetch',  status: 'pending', params: [{k:'threads',v:'4'}], outputs: [] },
        { id: 'fasterq',    name: 'fasterq-dump',  status: 'pending', params: [], outputs: [] },
      ],
      qc: [{ metric: 'download_success', op: '=', threshold: '100%' }],
      autoloop: false,
    },
    { id: 'B', name: 'Quality & Adapter Trim', summary: 'fastp with MultiQC aggregation',
      steps: [
        { id: 'fastp',     name: 'fastp (per accession)', status: 'pending', params: [{k:'q',v:'20'},{k:'len',v:'50'}], outputs: [] },
        { id: 'multiqc',   name: 'MultiQC',               status: 'pending', params: [], outputs: [] },
      ],
      qc: [{ metric: 'q30_pct', op: '>', threshold: '85%' }],
      autoloop: false,
    },
  ],
};

// ── Drug screening — multi-phase v1 panel scenario that mirrors the
//    chat-side `drugscreen` engine flow (ingest → ADMET → QC → ranking).
//    Keeps the panel structurally consistent with the chat narrative so
//    users on the drugscreen sidebar see the same phase breakdown in both.
const DRUGSCREEN = {
  id: 'drugscreen',
  name: 'Drug Screen · BBB Penetrants',
  subtitle: 'Library screen · 4 phases · 8 steps',
  domain: 'Drug discovery',
  query: 'Screen a 10k-compound library for blood-brain barrier penetrants. Filter on hERG and Ames; rank by predicted logBB.',
  globalParams: [
    { key: 'library',   label: 'Compound library', value: 'ChEMBL-bbb-10k.sdf' },
    { key: 'logp_max',  label: 'logP max',         value: '4.5' },
    { key: 'mw_max',    label: 'MW max',           value: '480' },
    { key: 'model_seed',label: 'Model seed',       value: '123' },
    { key: 'outdir',    label: 'Output directory', value: 'results/drugscreen_2026-05-17/' },
  ],
  phases: [
    {
      id: 'A', name: 'Library ingest',
      summary: 'SMILES normalize + dedupe',
      steps: [
        { id: 'ingest_load',  name: 'Load SDF',          status: 'pending',
          params: [{k:'format',v:'SDF v3000'}],
          outputs: [{name:'compounds_raw.parquet', type:'table'}] },
        { id: 'ingest_norm',  name: 'Standardize SMILES', status: 'pending',
          params: [{k:'standardizer',v:'RDKit 2024.3'}],
          outputs: [{name:'compounds_clean.parquet', type:'table'}] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'B', name: 'ADMET prediction',
      summary: 'MPNN ensemble · 7 endpoints',
      steps: [
        { id: 'admet_pred', name: 'ADMET ensemble', status: 'pending',
          params: [{k:'ensemble_size',v:'5'},{k:'model',v:'admet-ai v2.1'},{k:'device',v:'cuda'}],
          outputs: [{name:'admet_predictions.parquet', type:'table'}] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'C', name: 'QC gates',
      summary: 'hERG · Ames · logP filters',
      steps: [
        { id: 'qc_herg', name: 'hERG liability gate', status: 'pending',
          params: [{k:'threshold',v:'0.5'}],
          outputs: [{name:'herg_pass.parquet', type:'table'}] },
        { id: 'qc_ames', name: 'Ames mutagenicity gate', status: 'pending',
          params: [{k:'threshold',v:'negative'}],
          outputs: [{name:'ames_pass.parquet', type:'table'}] },
        { id: 'qc_logp', name: 'logP / MW filter', status: 'pending',
          params: [{k:'logp_max',v:'4.5'},{k:'mw_max',v:'480'}],
          outputs: [{name:'physchem_pass.parquet', type:'table'}] },
      ],
      qc: [
        { metric: 'herg_hit_rate', op: '<', threshold: '0.5' },
        { metric: 'ames_positive', op: '=', threshold: 'false' },
      ],
      autoloop: true,
    },
    {
      id: 'D', name: 'Ranking + report',
      summary: 'logBB ranker · candidate cards',
      steps: [
        { id: 'rank_logbb', name: 'Rank by predicted logBB', status: 'pending',
          params: [{k:'top_k',v:'50'}],
          outputs: [{name:'top_candidates.csv', type:'table'},{name:'candidate_cards.pdf', type:'image'}] },
      ],
      qc: [],
      autoloop: false,
    },
  ],
};

// ── Bioconductor · knowledge-based routing & execution — the v1 panel
//    counterpart to the chat-side `bioc_kb` engine flow. Phases A–F mirror
//    the DESeq2 chain the KB routes to (QC → normalise → DE → shrink →
//    enrich → visualise), so the panel phase breakdown tracks the chat
//    narrative 1-to-1. Dedicated scenario (not a renamed nf-core) so the
//    existing nf-core demos stay intact.
const BIOC_KB = {
  id: 'bioc_kb',
  name: 'Bioconductor · DESeq2 chain',
  subtitle: 'KB-routed DE analysis · 6 phases · 9 steps',
  domain: 'Bulk RNA-seq (Bioconductor)',
  query: 'Run an end-to-end differential expression analysis on my count matrix (human, control vs treated). Include pathway + GO enrichment.',
  globalParams: [
    { key: 'counts',    label: 'Count matrix',     value: 'counts_GRCh38.tsv', note: 'raw integer counts' },
    { key: 'design',    label: 'Design formula',   value: '~ condition' },
    { key: 'contrast',  label: 'Contrast',         value: 'treated vs control' },
    { key: 'chain',     label: 'Routed chain',     value: 'bulk_rnaseq_de_analysis', note: 'KB match 0.71' },
    { key: 'outdir',    label: 'Output directory', value: 'results/bioc_deseq2_2026-05-31/' },
  ],
  phases: [
    {
      id: 'A', name: 'QC & filtering',
      summary: 'edgeR::filterByExpr — drop low-count genes',
      steps: [
        { id: 'filter', name: 'filterByExpr', status: 'pending',
          params: [{k:'min_count',v:'10'},{k:'min_samples',v:'2'}],
          outputs: [{name:'filtered_counts.rds', type:'table'}] },
      ],
      qc: [{ metric: 'genes_retained', op: '>', threshold: '10k', observed: '14,203' }],
      autoloop: false,
    },
    {
      id: 'B', name: 'Normalisation',
      summary: 'DESeq2::estimateSizeFactors (median-of-ratios)',
      steps: [
        { id: 'dds_build', name: 'DESeqDataSetFromMatrix', status: 'pending',
          params: [{k:'design',v:'~ condition'}],
          outputs: [{name:'dds.rds', type:'table'}] },
        { id: 'sizefactors', name: 'estimateSizeFactors', status: 'pending',
          params: [{k:'method',v:'median-of-ratios'}],
          outputs: [{name:'size_factors.csv', type:'table'}] },
      ],
      qc: [{ metric: 'size_factor_range', op: 'between', threshold: '0.5–2.0', observed: '0.91–1.14' }],
      autoloop: false,
    },
    {
      id: 'C', name: 'DE testing',
      summary: 'Wald test · negative-binomial GLM',
      steps: [
        { id: 'deseq', name: 'DESeq (Wald)', status: 'pending',
          params: [{k:'test',v:'Wald'},{k:'fitType',v:'parametric'}],
          outputs: [{name:'deseq_results.rds', type:'table'}] },
      ],
      qc: [{ metric: 'replicates_per_group', op: '>=', threshold: '2', observed: '12 / group' }],
      autoloop: false,
    },
    {
      id: 'D', name: 'LFC shrinkage',
      summary: 'apeglm posterior estimation',
      steps: [
        { id: 'lfcshrink', name: 'lfcShrink (apeglm)', status: 'pending',
          params: [{k:'type',v:'apeglm'}],
          outputs: [{name:'shrunk_lfc.csv', type:'table'}] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'E', name: 'Pathway enrichment',
      summary: 'clusterProfiler gseGO (GO BP)',
      steps: [
        { id: 'gsego', name: 'gseGO', status: 'pending',
          params: [{k:'ont',v:'BP'},{k:'pvalueCutoff',v:'0.05'}],
          outputs: [{name:'gsea_GO_BP.csv', type:'table'}] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'F', name: 'Visualisation',
      summary: 'volcano · dotplot · heatmap',
      steps: [
        { id: 'viz', name: 'EnhancedVolcano + dotplot + heatmap', status: 'pending',
          params: [{k:'top_genes',v:'50'}],
          outputs: [
            {name:'volcano.png', type:'image', viz:'volcano'},
            {name:'pathway_dotplot.png', type:'image', viz:'go_dotplot'},
            {name:'heatmap_top50.png', type:'image', viz:'heatmap'},
          ] },
      ],
      qc: [],
      autoloop: false,
    },
  ],
  report: {
    findings: {
      headline: '2,841 differentially expressed genes; apoptotic regulation is the top enriched pathway.',
      bullets: [
        '14,203 of 18,421 genes passed expression filtering (low-count genes dropped before testing).',
        '2,841 genes significant at FDR < 0.05 after apeglm fold-change shrinkage — 1,612 up, 1,229 down in treated.',
        'GO BP enrichment is led by regulation of apoptotic process (adj. p = 2.1 × 10⁻¹¹).',
      ],
      figures: [
        { kind: 'bars', title: 'Top enriched GO terms (BP)', unit: '−log₁₀ adj. p',
          highlight: 'apoptotic process',
          data: [
            ['apoptotic process', 10.7], ['immune response', 8.4], ['cytokine signaling', 7.1],
            ['cell-cycle arrest', 6.2], ['inflammatory response', 5.5], ['response to stress', 4.8],
          ] },
        { kind: 'composition', title: 'DE direction · 2,841 genes',
          data: [['Up-regulated', 1612], ['Down-regulated', 1229]] },
        { kind: 'qc', title: 'Gene filtering', unit: 'genes retained', kept: 14203, total: 18421 },
      ],
      table: [
        ['DE genes (FDR < 0.05)', '2,841'],
        ['Up / down',            '1,612 / 1,229'],
        ['Top pathway (GO BP)',  'regulation of apoptotic process'],
        ['Routed chain',         'bulk_rnaseq_de_analysis'],
        ['Runtime',              '16m 41s'],
      ],
    },
    methods: [
      'Bulk RNA-seq counts (human; control vs treated, 24 samples) were analysed with BioMate orchestrating a Bioconductor DESeq2 workflow. A raw integer count matrix was the entry point, so the differential-expression model was the negative-binomial GLM in DESeq2 (not limma/voom, which targets continuous log₂ intensities).',
      'Genes were filtered with edgeR::filterByExpr (≥ 10 counts in ≥ 2 samples), retaining 14,203 of 18,421 genes. A DESeqDataSet was built (design ~ condition) and median-of-ratios size factors estimated with estimateSizeFactors.',
      'Differential expression used the DESeq Wald test; log₂ fold-changes were shrunk with apeglm (lfcShrink) to stabilise low-count estimates before ranking. 2,841 genes were significant at FDR < 0.05.',
      'Gene-set enrichment ran on the shrunk, ranked list with clusterProfiler::gseGO (ontology BP, p-value cutoff 0.05); the top term was regulation of apoptotic process. Figures (volcano, dotplot, top-50 heatmap) were produced with EnhancedVolcano, enrichplot and ComplexHeatmap.',
    ],
    params: [
      ['Global', 'design / contrast', '~ condition · treated vs control'],
      ['A · filterByExpr', 'min_count / min_samples', '10 / 2'],
      ['B · DESeqDataSet', 'design', '~ condition'],
      ['B · estimateSizeFactors', 'method', 'median-of-ratios'],
      ['C · DESeq', 'test / fitType', 'Wald / parametric'],
      ['D · lfcShrink', 'type', 'apeglm'],
      ['E · gseGO', 'ont / pvalueCutoff', 'BP / 0.05'],
      ['F · Visualisation', 'top_genes', '50'],
    ],
    software: [
      { name: 'BioMate', version: 'v0.9.4', note: 'workflow orchestrator' },
      { name: 'DESeq2', version: 'v1.44', note: 'differential expression (Love et al., 2014)' },
      { name: 'apeglm', version: 'v1.26', note: 'LFC shrinkage (Zhu et al., 2019)' },
      { name: 'edgeR', version: 'v4.2', note: 'expression filtering (Robinson et al., 2010)' },
      { name: 'clusterProfiler', version: 'v4.12', note: 'GO enrichment (Wu et al., 2021)' },
      { name: 'EnhancedVolcano', version: 'v1.22', note: 'volcano plots (Blighe et al.)' },
    ],
    citations: [
      'Love MI, Huber W, Anders S. Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2. Genome Biol. 2014;15:550.',
      'Zhu A, Ibrahim JG, Love MI. Heavy-tailed prior distributions for sequence count data: removing the noise and preserving large differences. Bioinformatics. 2019;35:2084–2092.',
      'Robinson MD, McCarthy DJ, Smyth GK. edgeR: a Bioconductor package for differential expression analysis of digital gene expression data. Bioinformatics. 2010;26:139–140.',
      'Wu T, Hu E, Xu S, et al. clusterProfiler 4.0: A universal enrichment tool for interpreting omics data. Innovation. 2021;2:100141.',
    ],
  },
};

// ── Bioconductor · single-cell (scRNA-seq) chain — the v1 panel
//    counterpart to the chat-side `bioc_sc` engine flow. Phases A–G mirror
//    the OSCA chain (QC → normalise → feature/PCA → cluster → markers ∥
//    annotation → pseudobulk DE). Phases E and F share `parallel: 'p1'`
//    so the panel renders the marker/annotation branch concurrently, and
//    phase G carries the pseudobulk-vs-naive QC gate.
const BIOC_SC = {
  id: 'bioc_sc',
  name: 'Bioconductor · scRNA-seq chain',
  subtitle: 'OSCA single-cell · 7 phases · pseudobulk DE',
  domain: 'Single-cell RNA-seq (Bioconductor)',
  query: 'Cluster and annotate my 10x single-cell dataset (12k cells, control vs treated, 6 samples), then find condition markers per cell type.',
  globalParams: [
    { key: 'matrix',    label: 'Input',            value: 'filtered_feature_bc_matrix/', note: '10x · 12,402 droplets' },
    { key: 'object',    label: 'Object class',     value: 'SingleCellExperiment' },
    { key: 'design',    label: 'Design formula',   value: '~ condition', note: 'pseudobulk' },
    { key: 'samples',   label: 'Samples',          value: '6 (3 control · 3 treated)' },
    { key: 'chain',     label: 'Routed chain',     value: 'scrna_osca_workflow', note: 'KB match 0.74' },
    { key: 'outdir',    label: 'Output directory', value: 'results/bioc_scrna_2026-05-31/' },
  ],
  phases: [
    {
      id: 'A', name: 'QC & filtering',
      summary: 'emptyDrops + perCellQCMetrics — drop ambient / low-quality cells',
      steps: [
        { id: 'emptydrops', name: 'emptyDrops', status: 'pending',
          params: [{k:'FDR',v:'0.001'},{k:'lower',v:'100'}],
          outputs: [{name:'sce_cells.rds', type:'table'}] },
        { id: 'percellqc', name: 'perCellQCMetrics + filter', status: 'pending',
          params: [{k:'mito_max_pct',v:'10'},{k:'nmads',v:'3'}],
          outputs: [{name:'sce_qc.rds', type:'table'}] },
      ],
      qc: [{ metric: 'cells_retained', op: '>', threshold: '8k', observed: '9,814' }],
      autoloop: false,
    },
    {
      id: 'B', name: 'Normalisation',
      summary: 'scran::computeSumFactors (deconvolution) → logNormCounts',
      steps: [
        { id: 'sumfactors', name: 'computeSumFactors', status: 'pending',
          params: [{k:'cluster',v:'quickCluster'},{k:'min.mean',v:'0.1'}],
          outputs: [{name:'size_factors.rds', type:'table'}] },
        { id: 'lognorm', name: 'logNormCounts', status: 'pending',
          params: [],
          outputs: [{name:'sce_logcounts.rds', type:'table'}] },
      ],
      qc: [{ metric: 'size_factor_range', op: 'between', threshold: '0.1–10', observed: '0.18–6.4' }],
      autoloop: false,
    },
    {
      id: 'C', name: 'Feature selection + PCA',
      summary: 'modelGeneVar → top 2k HVGs → runPCA',
      steps: [
        { id: 'modelvar', name: 'modelGeneVar + getTopHVGs', status: 'pending',
          params: [{k:'n',v:'2000'}],
          outputs: [{name:'hvg.rds', type:'table'}] },
        { id: 'pca', name: 'runPCA', status: 'pending',
          params: [{k:'ncomponents',v:'50'}],
          outputs: [{name:'sce_pca.rds', type:'table'}] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'D', name: 'Clustering',
      summary: 'buildSNNGraph (k=10) + Louvain',
      steps: [
        { id: 'snn', name: 'buildSNNGraph + cluster_louvain', status: 'pending',
          params: [{k:'k',v:'10'},{k:'use.dimred',v:'PCA'}],
          outputs: [{name:'clusters.csv', type:'table'}] },
        { id: 'umap', name: 'runUMAP', status: 'pending',
          params: [{k:'n_neighbors',v:'15'}],
          outputs: [{name:'umap.png', type:'image', viz:'umap'}] },
      ],
      qc: [{ metric: 'n_clusters', op: 'between', threshold: '8–15', observed: '11' }],
      autoloop: false,
    },
    {
      id: 'E', name: 'Marker detection',
      summary: 'scoreMarkers per cluster',
      parallel: 'p1',
      steps: [
        { id: 'scoremarkers', name: 'scoreMarkers', status: 'pending',
          params: [{k:'full.stats',v:'TRUE'}],
          outputs: [{name:'markers.rds', type:'table'}] },
      ],
      qc: [],
      autoloop: false,
    },
    {
      id: 'F', name: 'Annotation',
      summary: 'SingleR vs Human Primary Cell Atlas',
      parallel: 'p1',
      steps: [
        { id: 'singler', name: 'SingleR', status: 'pending',
          params: [{k:'ref',v:'HumanPrimaryCellAtlas'},{k:'prune',v:'TRUE'}],
          outputs: [{name:'celltypes.csv', type:'table'}] },
      ],
      qc: [{ metric: 'pruned_clusters', op: '<=', threshold: '2', observed: '1' }],
      autoloop: false,
    },
    {
      id: 'G', name: 'Pseudobulk DE',
      summary: 'aggregateAcrossCells → DESeq2 per cell type',
      steps: [
        { id: 'aggregate', name: 'aggregateAcrossCells', status: 'pending',
          params: [{k:'ids',v:'sample × celltype'}],
          outputs: [{name:'pseudobulk_se.rds', type:'table'}] },
        { id: 'deseq_pb', name: 'DESeq2 (per cell type)', status: 'pending',
          params: [{k:'design',v:'~ condition'},{k:'min_cells',v:'10'}],
          outputs: [
            {name:'de_by_celltype.csv', type:'table'},
            {name:'marker_heatmap.png', type:'image', viz:'markers'},
          ] },
      ],
      qc: [{ metric: 'replicate_unit', op: '=', threshold: 'sample (not cell)', observed: 'sample' }],
      autoloop: false,
    },
  ],
  report: {
    findings: {
      headline: '8 cell types resolved; CD8⁺ T cells are the strongest condition responder.',
      bullets: [
        '9,814 of 12,402 cells passed QC (2,588 dropped as ambient droplets or >10% mitochondrial reads).',
        '11 graph-based clusters annotated to 8 cell types; SingleR pruned 1 low-confidence cluster.',
        'Condition DE was run on pseudobulk — 48 profiles (6 samples × 8 types) — so significance rests on biological replicates, not individual cells.',
      ],
      figures: [
        { kind: 'bars', title: 'Differential expression by cell type', unit: 'DE genes · FDR < 0.05',
          highlight: 'CD8⁺ T',
          data: [
            ['CD8⁺ T', 214], ['CD4⁺ T', 156], ['NK', 121], ['Monocyte', 98],
            ['B', 74], ['Dendritic', 52], ['Treg', 39], ['Platelet', 12],
          ] },
        { kind: 'composition', title: 'Cell-type composition · 9,814 cells',
          data: [
            ['CD4⁺ T', 2840], ['CD8⁺ T', 2110], ['Monocyte', 1620], ['NK', 1180],
            ['B', 920], ['Dendritic', 540], ['Treg', 360], ['Platelet', 244],
          ] },
        { kind: 'qc', title: 'QC retention', unit: 'cells retained', kept: 9814, total: 12402 },
      ],
      table: [
        ['Cells after QC',       '9,814 / 12,402'],
        ['Clusters → cell types','11 → 8'],
        ['Pseudobulk profiles',  '48'],
        ['Top responder',        'CD8⁺ T — 214 DE genes'],
        ['Runtime',              '21m 07s'],
      ],
    },
    methods: [
      'Single-cell RNA-seq data (10x Genomics; 12,402 droplets across 6 samples — 3 control, 3 treated) were processed with BioMate orchestrating the Bioconductor OSCA workflow on a single SingleCellExperiment object.',
      'Empty droplets were removed with DropletUtils::emptyDrops (FDR < 0.001). Per-cell QC metrics (scater::perCellQCMetrics) flagged cells exceeding 10% mitochondrial reads or falling 3 MADs below the median library size / detected-gene count, retaining 9,814 cells. Counts were normalised with scran deconvolution size factors (computeSumFactors, quickCluster pre-grouping) followed by logNormCounts.',
      'The top 2,000 highly variable genes (scran::modelGeneVar) were used for runPCA (50 components). Cells were clustered on a shared-nearest-neighbour graph (k = 10, Louvain), yielding 11 clusters; a UMAP was computed for visualisation only.',
      'Cluster markers were scored with scran::scoreMarkers and cell types assigned by SingleR against the Human Primary Cell Atlas (1 low-confidence cluster pruned), giving 8 cell types. For condition differential expression, counts were aggregated to pseudobulk per (sample × cell type) with scuttle::aggregateAcrossCells, and DESeq2 was run within each cell type (design ~ condition; profiles with < 10 cells excluded).',
    ],
    params: [
      ['Global', 'object_class', 'SingleCellExperiment'],
      ['Global', 'design', '~ condition'],
      ['A · emptyDrops', 'FDR', '0.001'],
      ['A · perCellQCMetrics', 'mito_max_pct / nmads', '10 / 3'],
      ['B · computeSumFactors', 'cluster / min.mean', 'quickCluster / 0.1'],
      ['C · modelGeneVar', 'top_HVGs', '2000'],
      ['C · runPCA', 'ncomponents', '50'],
      ['D · buildSNNGraph', 'k / use.dimred', '10 / PCA'],
      ['F · SingleR', 'ref', 'HumanPrimaryCellAtlas'],
      ['G · DESeq2', 'design / min_cells', '~ condition / 10'],
    ],
    software: [
      { name: 'BioMate', version: 'v0.9.4', note: 'workflow orchestrator' },
      { name: 'DropletUtils', version: 'v1.24', note: 'emptyDrops (Lun et al., 2019)' },
      { name: 'scran', version: 'v1.32', note: 'normalisation, HVGs, clustering (Lun et al., 2016)' },
      { name: 'scater', version: 'v1.32', note: 'QC + dimensionality reduction (McCarthy et al., 2017)' },
      { name: 'SingleR', version: 'v2.6', note: 'reference-based annotation (Aran et al., 2019)' },
      { name: 'DESeq2', version: 'v1.44', note: 'pseudobulk differential expression (Love et al., 2014)' },
    ],
    citations: [
      'Amezquita RA, Lun ATL, Becht E, et al. Orchestrating single-cell analysis with Bioconductor. Nat Methods. 2020;17:137–145.',
      'Lun ATL, Riesenfeld S, Andrews T, et al. EmptyDrops: distinguishing cells from empty droplets in droplet-based single-cell RNA sequencing data. Genome Biol. 2019;20:63.',
      'Aran D, Looney AP, Liu L, et al. Reference-based analysis of lung single-cell sequencing reveals a transitional profibrotic macrophage. Nat Immunol. 2019;20:163–172.',
      'Love MI, Huber W, Anders S. Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2. Genome Biol. 2014;15:550.',
      'Crowell HL, Soneson C, Germain PL, et al. muscat detects subpopulation-specific state transitions from multi-sample multi-condition single-cell transcriptomics data. Nat Commun. 2020;11:6077.',
    ],
  },
};

// ── Bioconductor · 450k methylation (epigenomics) chain — the v1 panel
//    counterpart to the chat-side `bioc_methyl` engine flow. Phases A–E
//    mirror the minfi pipeline (read IDAT → QC/normalise → DMP → DMR →
//    CpG-corrected GO). Distinct from the other two Bioconductor demos in
//    its backbone object lineage: MethylSet → GenomicRatioSet → GRanges.
const BIOC_METHYL = {
  id: 'bioc_methyl',
  name: 'Bioconductor · 450k methylation chain',
  subtitle: 'minfi epigenomics · 5 phases · GRanges backbone',
  domain: 'DNA methylation array (Bioconductor)',
  query: 'Find differentially methylated regions between tumour and normal on my Illumina 450k array (24 samples), then run GO enrichment.',
  globalParams: [
    { key: 'idat',     label: 'Input',            value: 'idat/*_{Grn,Red}.idat', note: '24 samples · 450k' },
    { key: 'manifest', label: 'Array manifest',   value: 'IlluminaHumanMethylation450k' },
    { key: 'object',   label: 'Backbone object',  value: 'GenomicRatioSet → GRanges' },
    { key: 'design',   label: 'Design formula',   value: '~ group', note: 'tumour vs normal' },
    { key: 'chain',    label: 'Routed chain',     value: 'methylation_450k_array_analysis', note: 'KB match 0.78' },
    { key: 'outdir',   label: 'Output directory', value: 'results/bioc_methyl_2026-06-01/' },
  ],
  phases: [
    {
      id: 'A', name: 'Read IDAT',
      summary: 'minfi::read.metharray.exp → MethylSet',
      steps: [
        { id: 'readidat', name: 'read.metharray.exp', status: 'pending',
          params: [{k:'array',v:'450k'},{k:'force',v:'TRUE'}],
          outputs: [{name:'rgset.rds', type:'table'}] },
        { id: 'preprocessraw', name: 'preprocessRaw', status: 'pending',
          params: [],
          outputs: [{name:'methylset.rds', type:'table'}] },
      ],
      qc: [{ metric: 'samples_read', op: '=', threshold: '24', observed: '24' }],
      autoloop: false,
    },
    {
      id: 'B', name: 'QC + normalisation',
      summary: 'detection-p QC + drop SNP probes + preprocessQuantile',
      steps: [
        { id: 'detp', name: 'detectionP + filter', status: 'pending',
          params: [{k:'p_cutoff',v:'0.01'}],
          outputs: [{name:'qc_report.html', type:'image'}] },
        { id: 'dropsnp', name: 'dropLociWithSnps + xReactive', status: 'pending',
          params: [{k:'maf',v:'0'}],
          outputs: [{name:'probes_kept.csv', type:'table'}] },
        { id: 'quantile', name: 'preprocessQuantile', status: 'pending',
          params: [],
          outputs: [{name:'grset.rds', type:'table'}] },
      ],
      qc: [{ metric: 'probes_retained', op: '>', threshold: '400k', observed: '411,234' }],
      autoloop: false,
    },
    {
      id: 'C', name: 'DMP calling',
      summary: 'limma eBayes on M-values',
      steps: [
        { id: 'dmp', name: 'lmFit + eBayes (M-values)', status: 'pending',
          params: [{k:'design',v:'~ group'},{k:'value',v:'M'}],
          outputs: [{name:'dmps.csv', type:'table'}] },
      ],
      qc: [{ metric: 'sig_cpgs', op: '>', threshold: '0', observed: '12,403' }],
      autoloop: false,
    },
    {
      id: 'D', name: 'DMR calling',
      summary: 'bumphunter → GRanges of regions',
      steps: [
        { id: 'bumphunter', name: 'bumphunter', status: 'pending',
          params: [{k:'B',v:'1000'},{k:'cutoff',v:'0.1'}],
          outputs: [{name:'dmrs.rds', type:'table'}] },
      ],
      qc: [{ metric: 'n_dmrs', op: '>', threshold: '0', observed: '847' }],
      autoloop: false,
    },
    {
      id: 'E', name: 'GO enrichment',
      summary: 'missMethyl::gometh — CpG-density corrected',
      steps: [
        { id: 'gometh', name: 'gometh', status: 'pending',
          params: [{k:'collection',v:'GO'},{k:'array.type',v:'450K'}],
          outputs: [
            {name:'go_enrichment.csv', type:'table'},
            {name:'dmr_tracks.png', type:'image', viz:'manhattan'},
          ] },
      ],
      qc: [{ metric: 'cpg_bias_corrected', op: '=', threshold: 'TRUE', observed: 'TRUE' }],
      autoloop: false,
    },
  ],
  report: {
    findings: {
      headline: '847 differentially methylated regions; enrichment is led by developmental / morphogenesis pathways.',
      bullets: [
        '12,403 CpGs were differentially methylated (FDR < 0.05) between tumour and normal.',
        'bumphunter collapsed those CpGs into 847 regions (DMRs) — 503 hyper- and 344 hypo-methylated in tumour.',
        'Enrichment used missMethyl::gometh, which corrects for CpG-density bias, so the calibrated top term is tissue morphogenesis (adj. p = 3.4 × 10⁻⁸).',
      ],
      figures: [
        { kind: 'bars', title: 'Top enriched GO terms (CpG-corrected)', unit: '−log₁₀ adj. p',
          highlight: 'tissue morphogenesis',
          data: [
            ['tissue morphogenesis', 7.5], ['developmental process', 6.9], ['cell adhesion', 5.8],
            ['neuron differentiation', 5.1], ['signal transduction', 4.4], ['transcription regulation', 3.9],
          ] },
        { kind: 'composition', title: 'DMR direction · 847 regions',
          data: [['Hyper-methylated', 503], ['Hypo-methylated', 344]] },
        { kind: 'qc', title: 'Probe QC', unit: 'probes retained', kept: 411234, total: 450000 },
      ],
      table: [
        ['Significant CpGs (DMPs)', '12,403'],
        ['DMRs (bumphunter)',       '847'],
        ['Hyper / hypo',           '503 / 344'],
        ['Top term (gometh)',      'tissue morphogenesis'],
        ['Runtime',                '13m 22s'],
      ],
    },
    methods: [
      'Illumina Infinium 450k methylation arrays (24 samples, tumour vs normal) were processed with BioMate orchestrating a Bioconductor minfi pipeline. Raw IDAT pairs were read with read.metharray.exp and converted to a MethylSet; the whole chain was carried on a single genomic-coordinate-aware object so probe positions travelled with the data.',
      'Detection-p QC (cutoff 0.01) passed all 24 samples; SNP-overlapping and cross-reactive probes were dropped, and β/M-values were quantile-normalised with preprocessQuantile to produce a GenomicRatioSet (411,234 probes retained).',
      'Per-CpG differential methylation was tested with limma (lmFit + eBayes) on M-values (design ~ group), yielding 12,403 significant CpGs at FDR < 0.05. Adjacent CpGs were collapsed into regions with bumphunter (1,000 bootstraps, cutoff 0.1), giving 847 DMRs as a GRanges object.',
      'Gene-set enrichment used missMethyl::gometh, which weights each gene by its CpG-probe count to remove the array’s CpG-density bias (a standard GO test would over-represent CpG-rich promoters). The calibrated top term was tissue morphogenesis.',
    ],
    params: [
      ['Global', 'array / design', '450K · ~ group'],
      ['A · read.metharray.exp', 'force', 'TRUE'],
      ['B · detectionP', 'p_cutoff', '0.01'],
      ['B · dropLociWithSnps', 'maf', '0'],
      ['C · lmFit + eBayes', 'value', 'M'],
      ['D · bumphunter', 'B / cutoff', '1000 / 0.1'],
      ['E · gometh', 'collection / array.type', 'GO / 450K'],
    ],
    software: [
      { name: 'BioMate', version: 'v0.9.4', note: 'workflow orchestrator' },
      { name: 'minfi', version: 'v1.50', note: 'IDAT read, QC, normalisation (Aryee et al., 2014)' },
      { name: 'limma', version: 'v3.60', note: 'per-CpG differential methylation (Ritchie et al., 2015)' },
      { name: 'bumphunter', version: 'v1.46', note: 'DMR detection (Jaffe et al., 2012)' },
      { name: 'missMethyl', version: 'v1.38', note: 'CpG-bias-corrected enrichment (Phipson et al., 2016)' },
    ],
    citations: [
      'Aryee MJ, Jaffe AE, Corrada-Bravo H, et al. Minfi: a flexible and comprehensive Bioconductor package for the analysis of Infinium DNA methylation microarrays. Bioinformatics. 2014;30:1363–1369.',
      'Jaffe AE, Murakami P, Lee H, et al. Bump hunting to identify differentially methylated regions in epigenetic epidemiology studies. Int J Epidemiol. 2012;41:200–209.',
      'Phipson B, Maksimovic J, Oshlack A. missMethyl: an R package for analyzing data from Illumina’s HumanMethylation450 platform. Bioinformatics. 2016;32:286–288.',
      'Ritchie ME, Phipson B, Wu D, et al. limma powers differential expression analyses for RNA-sequencing and microarray studies. Nucleic Acids Res. 2015;43:e47.',
    ],
  },
};

window.SCENARIOS = { cryosparc: CRYOSPARC, gatk: GATK, admet: ADMET, nfcore: NFCORE, drugscreen: DRUGSCREEN, bioc_kb: BIOC_KB, bioc_sc: BIOC_SC, bioc_methyl: BIOC_METHYL };
