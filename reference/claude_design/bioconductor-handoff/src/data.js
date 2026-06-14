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

// ─────────────────────────────────────────────────────────────────
// Bioconductor handoff — 3 panel scenarios driving the v1 WorkflowPanel.
// Phase names match the BiocTours.jsx callout text exactly so chat + panel agree.
// ─────────────────────────────────────────────────────────────────
const BIOC_KB = {
  id: 'bioc_kb',
  name: 'Bioconductor · DESeq2 chain',
  subtitle: 'Bulk RNA-seq · 6 phases · DESeq2 + apeglm + clusterProfiler',
  domain: 'Bulk RNA-seq · Bioconductor',
  query: 'DESeq2 differential expression on 120 salmon quants (control vs treated)',
  globalParams: [
    { key: 'quants',   label: 'Salmon quants', value: 's3://biomate/rnaseq/quants/' },
    { key: 'design',   label: 'Design',        value: '~ condition' },
    { key: 'reference',label: 'Reference',     value: 'control' },
    { key: 'organism', label: 'Organism',      value: 'Homo sapiens (GRCh38)' },
    { key: 'fdr',      label: 'FDR',           value: '0.05' },
  ],
  phases: [
    { id: 'A', name: 'QC', summary: 'edgeR::filterByExpr',
      steps: [{ id: 'filter', name: 'filterByExpr', status: 'pending', params: [], outputs: [] }],
      qc: [], autoloop: false },
    { id: 'B', name: 'Normalise', summary: 'DESeq2 size factors → DESeqDataSet',
      steps: [
        { id: 'dds', name: 'DESeqDataSetFromTximport', status: 'pending', params: [], outputs: [] },
        { id: 'sf',  name: 'estimateSizeFactors',      status: 'pending', params: [], outputs: [{name:'size_factors.tsv',type:'table',viz:'sf'}] },
      ], qc: [], autoloop: false },
    { id: 'C', name: 'DE test', summary: 'Wald test · ~ condition',
      steps: [
        { id: 'deseq',   name: 'DESeq()',  status: 'pending', params: [{k:'test',v:'Wald'}], outputs: [] },
        { id: 'results', name: 'results()', status: 'pending', params: [{k:'alpha',v:'0.05'}], outputs: [{name:'de_results.tsv',type:'table',viz:'volcano'}] },
      ], qc: [{metric:'de_genes_fdr05',op:'>',threshold:'10'}], autoloop: false },
    { id: 'D', name: 'Shrink', summary: 'apeglm LFC shrinkage',
      steps: [{ id: 'shrink', name: 'lfcShrink (apeglm)', status: 'pending', params: [{k:'type',v:'apeglm'}], outputs: [{name:'de_shrunk.tsv',type:'table',viz:'ma'}] }],
      qc: [], autoloop: false },
    { id: 'E', name: 'Enrich', summary: 'clusterProfiler::gseGO',
      steps: [
        { id: 'anno', name: 'org.Hs.eg.db', status: 'pending', params: [], outputs: [] },
        { id: 'gsea', name: 'gseGO',        status: 'pending', params: [{k:'ont',v:'BP'}], outputs: [{name:'go_bp.tsv',type:'table',viz:'gsea_bar'}] },
      ], qc: [], autoloop: false },
    { id: 'F', name: 'Visualise', summary: 'volcano · dotplot · heatmap',
      steps: [{ id: 'viz', name: 'plots', status: 'pending', params: [], outputs: [{name:'volcano.pdf',type:'image',viz:'volcano'}] }],
      qc: [], autoloop: false },
  ],
};

const BIOC_SC = {
  id: 'bioc_sc',
  name: 'Bioconductor · scRNA-seq chain',
  subtitle: 'single-cell · 7 phases · OSCA → pseudobulk DESeq2',
  domain: 'single-cell RNA-seq · Bioconductor',
  query: 'condition DE on 12,402 PBMCs, OSCA stack, pseudobulk DESeq2',
  globalParams: [
    { key: 'counts',     label: '10x counts',  value: 's3://biomate/scrna/pbmc/' },
    { key: 'mito_max',   label: 'Mito %',      value: '12' },
    { key: 'resolution', label: 'Resolution',  value: '0.8' },
    { key: 'reference',  label: 'SingleR ref', value: 'HumanPrimaryCellAtlas' },
  ],
  phases: [
    { id: 'A', name: 'QC', summary: 'emptyDrops + perCellQCMetrics',
      steps: [
        { id: 'drops', name: 'emptyDrops',       status: 'pending', params: [], outputs: [] },
        { id: 'qcm',   name: 'perCellQCMetrics', status: 'pending', params: [], outputs: [{name:'qc.tsv',type:'table',viz:'qc_violin'}] },
      ], qc: [{metric:'cells_passed',op:'>',threshold:'8000'}], autoloop: false },
    { id: 'B', name: 'Normalise', summary: 'scran pooled size factors',
      steps: [
        { id: 'sf',  name: 'computeSumFactors', status: 'pending', params: [], outputs: [] },
        { id: 'log', name: 'logNormCounts',     status: 'pending', params: [], outputs: [] },
      ], qc: [], autoloop: false },
    { id: 'C', name: 'Feature / PCA', summary: 'modelGeneVar + runPCA',
      steps: [
        { id: 'hvg', name: 'modelGeneVar', status: 'pending', params: [], outputs: [{name:'hvgs.tsv',type:'table',viz:'mean_var'}] },
        { id: 'pca', name: 'runPCA',       status: 'pending', params: [{k:'ncomponents',v:'30'}], outputs: [] },
      ], qc: [], autoloop: false },
    { id: 'D', name: 'Cluster', summary: 'buildSNNGraph + Louvain',
      steps: [
        { id: 'snn', name: 'buildSNNGraph', status: 'pending', params: [{k:'k',v:'10'}], outputs: [] },
        { id: 'cls', name: 'clusterCells',  status: 'pending', params: [{k:'algorithm',v:'louvain'}], outputs: [{name:'clusters.tsv',type:'table',viz:'umap'}] },
      ], qc: [], autoloop: false },
    { id: 'E', name: 'Markers', summary: 'scoreMarkers per cluster (∥ Annotation)',
      steps: [{ id: 'mk', name: 'scoreMarkers', status: 'pending', params: [], outputs: [{name:'markers.rds',type:'table',viz:'marker_heatmap'}] }],
      qc: [], autoloop: false },
    { id: 'F', name: 'Annotation', summary: 'SingleR vs HumanPrimaryCellAtlas (∥ Markers)',
      steps: [{ id: 'sr', name: 'SingleR', status: 'pending', params: [{k:'reference',v:'HumanPrimaryCellAtlasData'}], outputs: [{name:'celltype.tsv',type:'table',viz:'celltype'}] }],
      qc: [], autoloop: false },
    { id: 'G', name: 'Pseudobulk DE', summary: 'aggregateAcrossCells + DESeq2',
      steps: [
        { id: 'agg', name: 'aggregateAcrossCells', status: 'pending', params: [{k:'group_by',v:'sample + cluster'}], outputs: [] },
        { id: 'pb',  name: 'DESeq2 (pseudobulk)',  status: 'pending', params: [{k:'design',v:'~ condition'}], outputs: [{name:'pb_de.tsv',type:'table',viz:'pb_volcano'}] },
      ], qc: [], autoloop: false },
  ],
};

const BIOC_METHYL = {
  id: 'bioc_methyl',
  name: 'Bioconductor · 450k methylation chain',
  subtitle: '450k methylation · 5 phases · minfi + DMRcate + missMethyl',
  domain: '450k methylation · Bioconductor',
  query: 'DMRs on 12-case / 12-control 450k cohort, CpG-corrected GO',
  globalParams: [
    { key: 'idats', label: 'IDAT dir',     value: 's3://biomate/methyl/idats/' },
    { key: 'sheet', label: 'Sample sheet', value: 's3://biomate/methyl/samples.csv' },
    { key: 'array', label: 'Array',        value: '450k' },
    { key: 'fdr',   label: 'FDR',          value: '0.05' },
  ],
  phases: [
    { id: 'A', name: 'Read IDAT', summary: 'minfi::read.metharray.exp',
      steps: [{ id: 'read', name: 'read.metharray.exp', status: 'pending', params: [{k:'extended',v:'TRUE'}], outputs: [{name:'mset.rds',type:'table',viz:'mset'}] }],
      qc: [{metric:'samples_read',op:'==',threshold:'24'}], autoloop: false },
    { id: 'B', name: 'QC + Normalise', summary: 'detection-p → preprocessQuantile → GenomicRatioSet',
      steps: [
        { id: 'detp', name: 'detectionP',         status: 'pending', params: [], outputs: [] },
        { id: 'pp',   name: 'preprocessQuantile', status: 'pending', params: [], outputs: [{name:'grset.rds',type:'table',viz:'beta_density'}] },
        { id: 'flt',  name: 'SNP/cross-reactive filter', status: 'pending', params: [{k:'maf',v:'0.01'}], outputs: [{name:'grset_filtered.rds',type:'table',viz:'probe_retention'}] },
      ], qc: [{metric:'probes_retained',op:'>',threshold:'400000'}], autoloop: false },
    { id: 'C', name: 'DMP calling', summary: 'limma eBayes on M-values',
      steps: [
        { id: 'mv', name: 'getM',           status: 'pending', params: [], outputs: [] },
        { id: 'lm', name: 'lmFit + eBayes', status: 'pending', params: [{k:'design',v:'~ group'}], outputs: [{name:'dmps.tsv',type:'table',viz:'dmp_volcano'}] },
      ], qc: [{metric:'sig_cpgs_fdr05',op:'>',threshold:'100'}], autoloop: false },
    { id: 'D', name: 'DMR calling', summary: 'DMRcate kernel smoothing',
      steps: [{ id: 'dmr', name: 'DMRcate', status: 'pending', params: [{k:'lambda',v:'1000'},{k:'C',v:'2'}], outputs: [{name:'dmrs.rds',type:'table',viz:'dmr_tracks'}] }],
      qc: [{metric:'dmrs_called',op:'>',threshold:'50'}], autoloop: false },
    { id: 'E', name: 'CpG-corrected enrichment', summary: 'missMethyl::gometh',
      steps: [{ id: 'go', name: 'gometh', status: 'pending', params: [{k:'array.type',v:'450K'},{k:'collection',v:'GO'}], outputs: [{name:'go_enrichment.tsv',type:'table',viz:'go_bar'}] }],
      qc: [], autoloop: false },
  ],
};

window.SCENARIOS = {
  cryosparc: CRYOSPARC, gatk: GATK, admet: ADMET, nfcore: NFCORE, drugscreen: DRUGSCREEN,
  bioc_kb: BIOC_KB, bioc_sc: BIOC_SC, bioc_methyl: BIOC_METHYL,
};
