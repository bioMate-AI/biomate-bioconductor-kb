// nf-core/mag — user-facing parameter stub
// Metagenome assembly and binning pipeline: assemble reads, bin contigs
// into MAGs, assess completeness with CheckM, and annotate with GTDB-Tk.
//
// Pipeline phases:
// * 1. Quality control — short-read trimming, host-genome decontamination
// * 2. Assembly — MEGAHIT / SPAdes hybrid or short-read assembly
// * 3. Binning — MetaBAT2, MaxBin2, CONCOCT + DAS Tool bin refinement
// * 4. QC & taxonomy — CheckM completeness, GTDB-Tk lineage assignment
// * 5. Report — MultiQC summary, bin stats TSV

params.input                    = null          // Samplesheet CSV (sample,group,short_reads_1,short_reads_2,long_reads)
params.outdir                   = null          // Output directory for results
params.single_end               = false         // Single-end short reads
params.assembly_type            = 'metagenome'  // Assembly mode: metagenome | isolate
params.assembler                = 'megahit'     // Short-read assembler: megahit | spades | spadeshybrid
params.spades_options           = null          // Extra options passed to SPAdes
params.bowtie2_mode             = '--very-sensitive-local' // Bowtie2 host-decontamination mode
params.host_genome              = null          // Host genome FASTA or Bowtie2 index for decontamination
params.skip_adapter_trimming    = false         // Skip Trim Galore adapter trimming
params.min_length               = 1000          // Minimum contig length (bp) for binning
params.min_size_bins            = 50000         // Minimum bin size (bp) to retain
params.binning_map_mode         = 'group'       // Binning read-mapping strategy: all | group | own
params.refine_bins_dastool      = false         // Refine bins with DAS Tool
params.postbinning_input        = 'raw_bins_dir' // Input to QC/taxonomy: raw_bins_dir | refined_bins_dir | both
params.run_gunc                 = false         // Run GUNC to detect chimeric bins
params.busco_reference          = null          // BUSCO lineage dataset (auto-detected if null)
params.checkm_db                = null          // CheckM database path (auto-downloaded if null)
params.cat_db                   = null          // CAT taxonomy database directory
params.gtdb_db                  = null          // GTDB-Tk reference database path
params.skip_prodigal            = false         // Skip Prodigal ORF prediction
params.skip_prokka              = true          // Skip Prokka gene annotation
params.skip_megahit             = false         // Skip MEGAHIT assembly
params.skip_spades              = true          // Skip SPAdes assembly
params.skip_binning             = false         // Skip all binning steps
params.skip_busco               = false         // Skip BUSCO assessment
params.skip_gtdbtk              = false         // Skip GTDB-Tk taxonomy assignment
params.skip_quast               = false         // Skip QUAST assembly QC
params.email                    = null
params.max_memory               = '128.GB'
params.max_cpus                 = 16
params.max_time                 = '240.h'

// [Quality Control]
process FASTP {
    script: """
    fastp \
        --in1 ${params.input} \
        ${params.single_end ? '' : '--in2 reads_2'} \
        --length_required ${params.min_length} \
        --out1 trimmed_1.fastq.gz \
        --out2 trimmed_2.fastq.gz
    """
}

// [Host Removal]
process BOWTIE2_HOST_REMOVAL {
    script: """
    bowtie2 ${params.bowtie2_mode} \
        -x ${params.host_genome} \
        -1 trimmed_1.fastq.gz \
        -2 trimmed_2.fastq.gz \
        --un-conc-gz clean_reads.fastq.gz
    """
}

// [Assembly]
process MEGAHIT {
    script: """
    megahit \
        -1 clean_reads_1.fastq.gz \
        -2 clean_reads_2.fastq.gz \
        --min-contig-len ${params.min_length} \
        -o assembly
    """
}

// [Binning]
process METABAT2 {
    script: """
    metabat2 \
        -i assembly/final.contigs.fa \
        -o bins/metabat2_bin \
        --minContig ${params.min_length} \
        --minClsSize ${params.min_size_bins}
    """
}

// [QC & Taxonomy]
process CHECKM_LINEAGEWF {
    script: """
    checkm lineage_wf \
        ${params.checkm_db ? "--db_dir ${params.checkm_db}" : ''} \
        bins/ checkm_output/
    """
}

// [Report]
process MULTIQC {
    script: """
    multiqc --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
