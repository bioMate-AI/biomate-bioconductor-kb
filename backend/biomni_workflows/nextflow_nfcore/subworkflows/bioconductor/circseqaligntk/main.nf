#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CircSeqAlignTk
// CircSeqAlignTk is designed for end-to-end RNA-Seq data analysis of circular genome sequences, from a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CircSeqAlignTk/inst/doc/CircSeqAlignTk.R
// Upstream  : Rbowtie2, ggplot2, shiny
// Downstream: none
//
// Install: BiocManager::install("CircSeqAlignTk")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CIRCSEQALIGNTK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-circseqaligntk"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-circseqaligntk:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-circseqaligntk:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_circseqaligntk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_circseqaligntk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_circseqaligntk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CircSeqAlignTk)
    library(jsonlite)

    # --- Adapter Trimming [Adapter Removal] ---
    # Key functions: remove_adapters
    ws <- tempdir()
    fq_in <- file.path(ws, "srna.fq")
    trimmed_fq <- file.path(ws, "srna_trimmed.fq")
    params <- "--maxns 1 --trimqualities --minquality 30 --minlength 21"
    remove_adapters(
        file1 = fq_in,
        adapter1 = "AGATCGGAAGAGCACACGTCTGAACTCCAGTCAC",
        adapter2 = NULL,
        output1 = trimmed_fq,
        params = params,
        basename = file.path(ws, "AdapterRemoval.log"),
        overwrite = TRUE
    )

    # --- Reference Indexing [Index Generation] ---
    # Key functions: build_index, get_slot_contents
    ws <- tempdir()
    genome_seq <- system.file(
        package = "CircSeqAlignTk",
        "extdata",
        "FR851463.fa"
    )
    ref_index <- build_index(
        input = genome_seq,
        output = file.path(ws, "index")
    )
    fasta_path <- get_slot_contents(ref_index, "fasta")
    index_path <- get_slot_contents(ref_index, "index")
    cut_loci <- get_slot_contents(ref_index, "cut_loc")

    # --- Read Alignment [Alignment] ---
    # Key functions: align_reads, get_slot_contents
    ws <- tempdir()
    trimmed_fq <- file.path(ws, "srna_trimmed.fq")
    aln <- align_reads(
        input = trimmed_fq,
        index = ref_index,
        output = file.path(ws, "align_results"),
        n_mismatch = 0,
        n_threads = 2
    )
    bam_path <- get_slot_contents(aln, "bam")
    stats_info <- get_slot_contents(aln, "stats")

    # --- Coverage Calculation [Coverage Analysis] ---
    # Key functions: calc_coverage, get_slot_contents
    alncov <- calc_coverage(aln)
    fwd_cov <- get_slot_contents(alncov, "forward")
    rev_cov <- get_slot_contents(alncov, "reverse")

    # --- Visualisation [Plotting Coverage] ---
    # Key functions: plot
    plot(alncov)
    plot(alncov, read_lengths = c(21, 22))

    # --- Synthetic Read Generation [Simulation] ---
    # Key functions: generate_reads, get_slot_contents
    ws <- tempdir()
    sim <- generate_reads(
        n = 1000,
        output = file.path(ws, "synthetic_reads.fq.gz"),
        mismatch_prob = 0.05
    )
    sim_cov <- get_slot_contents(sim, "coverage")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_circseqaligntk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_circseqaligntk_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_circseqaligntk_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CIRCSEQALIGNTK:", paste0("    circseqaligntk: ", packageVersion("CircSeqAlignTk"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_circseqaligntk_results.csv
    touch ${prefix}_circseqaligntk_output.rds
    echo "BIOC_CIRCSEQALIGNTK:" > versions.yml
    echo "    circseqaligntk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CIRCSEQALIGNTK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CIRCSEQALIGNTK(ch_input)

    emit:
    results  = BIOC_CIRCSEQALIGNTK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CIRCSEQALIGNTK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CIRCSEQALIGNTK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CIRCSEQALIGNTK.out.versions  // channel: path(versions.yml)
}
