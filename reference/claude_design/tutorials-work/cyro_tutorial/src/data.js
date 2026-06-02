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
      qc: [{ metric: 'genes_retained', op: '>', threshold: '10k' }],
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
      qc: [{ metric: 'size_factor_range', op: 'between', threshold: '0.5–2.0' }],
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
      qc: [{ metric: 'replicates_per_group', op: '>=', threshold: '2' }],
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
            {name:'volcano.png', type:'image'},
            {name:'pathway_dotplot.png', type:'image'},
            {name:'heatmap_top50.png', type:'image'},
          ] },
      ],
      qc: [],
      autoloop: false,
    },
  ],
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
      qc: [{ metric: 'cells_retained', op: '>', threshold: '8k' }],
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
      qc: [{ metric: 'size_factor_range', op: 'between', threshold: '0.1–10' }],
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
          outputs: [{name:'umap.png', type:'image'}] },
      ],
      qc: [{ metric: 'n_clusters', op: 'between', threshold: '8–15' }],
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
      qc: [{ metric: 'pruned_clusters', op: '<=', threshold: '2' }],
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
            {name:'marker_heatmap.png', type:'image'},
          ] },
      ],
      qc: [{ metric: 'replicate_unit', op: '=', threshold: 'sample (not cell)' }],
      autoloop: false,
    },
  ],
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
      qc: [{ metric: 'samples_read', op: '=', threshold: '24' }],
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
      qc: [{ metric: 'probes_retained', op: '>', threshold: '420k' }],
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
      qc: [{ metric: 'sig_cpgs', op: '>', threshold: '0' }],
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
      qc: [{ metric: 'n_dmrs', op: '>', threshold: '0' }],
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
            {name:'dmr_tracks.png', type:'image'},
          ] },
      ],
      qc: [{ metric: 'cpg_bias_corrected', op: '=', threshold: 'TRUE' }],
      autoloop: false,
    },
  ],
};

window.SCENARIOS = { cryosparc: CRYOSPARC, gatk: GATK, admet: ADMET, nfcore: NFCORE, drugscreen: DRUGSCREEN, bioc_kb: BIOC_KB, bioc_sc: BIOC_SC, bioc_methyl: BIOC_METHYL };
