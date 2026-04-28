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
    { key: 'max_cpus',     label: 'Max CPUs',           value: '32' },
    { key: 'max_memory',   label: 'Max memory',         value: '128 GB' },
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
      autoloop: true,
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
    { key: 'max_cpus', label: 'Max CPUs',             value: '16' },
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
    { key: 'max_cpus',   label: 'Max CPUs',          value: '8' },
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

window.SCENARIOS = { cryosparc: CRYOSPARC, gatk: GATK, admet: ADMET, nfcore: NFCORE };
