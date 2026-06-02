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

    # --- quick start  triming [] ---
    # Key functions: gunzip, remove_adapters
    library(R.utils)
    library(Rbowtie2)
    gunzip(fq, destname = file.path(ws, 'srna.fq'), overwrite = TRUE, remove = FALSE)
    # --- quick start  alignment [] ---
    # Key functions: build_index, align_reads
    ref_index <- build_index(input = genome_seq,
    output = file.path(ws, 'index'))
    # --- quick start  summary [] ---
    # Key functions: calc_coverage
    alncov <- calc_coverage(aln)
    head(get_slot_contents(alncov, 'forward'))  # alignment coverage in forward strand
    head(get_slot_contents(alncov, 'reverse')) # alignment coverage in reverse strand
    # --- implementation  build index [] ---
    # Key functions: build_index
    genome_seq <- system.file(package = 'CircSeqAlignTk', 'extdata', 'FR851463.fa')
    ref_index <- build_index(input = genome_seq, output = file.path(ws, 'index'))
    # --- implementation  build index output refseq [] ---
    # Key functions: get_slot_contents
    get_slot_contents(ref_index, 'fasta')
    # --- implementation  build index output index [] ---
    # Key functions: get_slot_contents
    get_slot_contents(ref_index, 'index')
    # --- access slot content [] ---
    # Key functions: slot
    slot(ref_index, 'fasta')
    slot(ref_index, 'index')
    # --- implementation  build index cutloci [] ---
    # Key functions: get_slot_contents
    get_slot_contents(ref_index, 'cut_loc')
    # --- implementation  build ht2index [] ---
    # Key functions: build_index

    # --- implementation  align read [] ---
    # Key functions: align_reads
    fq <- system.file(package = 'CircSeqAlignTk', 'extdata', 'srna.fq.gz')
    aln <- align_reads(input = fq,
    output = file.path(ws, 'align_results'))
    # --- implementation  align read output bam [] ---
    # Key functions: get_slot_contents
    get_slot_contents(aln, 'bam')
    get_slot_contents(aln, 'clean_bam')
    # --- implementation  align read stats [] ---
    # Key functions: get_slot_contents
    get_slot_contents(aln, 'stats')
    # --- implementation  align read  mismatch [] ---
    # Key functions: align_reads

    # --- implementation  align read  threads [] ---
    # Key functions: align_reads

    # --- implementation  align read  add params [] ---
    # Key functions: align_reads


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
