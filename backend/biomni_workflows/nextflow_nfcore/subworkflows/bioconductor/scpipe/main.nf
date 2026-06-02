#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scPipe
// A preprocessing pipeline for single cell RNA-seq/ATAC-seq data that starts from the fastq files and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scPipe/inst/doc/scPipe_atac_tutorial.R
// Upstream  : SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("scPipe")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCPIPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scpipe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scpipe:2.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scpipe:2.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scpipe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scpipe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scpipe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scPipe)
    library(jsonlite)

    # --- Sc Atac Trim Barcode [] ---
    # Key functions: sc_atac_trim_barcode
    ---------------------------------------------------------------------
    sc_atac_trim_barcode (r1            = r1,
                          r2            = r2,
                          bc_file       = barcode_fastq,
                          rmN           = FALSE,
    # --- Sc Atac Bam Tagging [] ---
    # Key functions: sc_atac_bam_tagging
    ---------------------------------------------------------------------
    sorted_tagged_bam <- sc_atac_bam_tagging (inbam = aligned_bam,
                           output_folder =  output_folder,
                           bam_tags      = list(bc="CB", mb="OX"),
                           nthreads      =  12)
    # --- Sc Atac Create Fragments [] ---
    # Key functions: sc_atac_create_fragments
    ---------------------------------------------------------------------
    sc_atac_create_fragments(inbam = sorted_tagged_bam,
                             output_folder = output_folder)
    # --- Sc Atac Feature Counting [] ---
    # Key functions: sc_atac_feature_counting, path
    ---------------------------------------------------------------------
    sc_atac_feature_counting (fragment_file = file.path(output_folder, "fragments.bed"),
                              feature_input = features,
                              bam_tags      = list(bc="CB", mb="OX"),
                              feature_type  = "peak",
    # --- Readrds [] ---
    # Key functions: path, glimpse
    ---------------------------------------------------------------------
    feature_matrix <- readRDS(file.path(output_folder, "unfiltered_feature_matrix.rds"))
    dplyr::glimpse(feature_matrix)
    sparseM <- readRDS(file.path(output_folder, "sparse_matrix.rds"))
    dplyr::glimpse(sparseM)
    # --- Sc Atac Create Sce [] ---
    # Key functions: sc_atac_create_sce
    ---------------------------------------------------------------------
    sce <- sc_atac_create_sce(input_folder = output_folder,
                       organism     = "hg38",
                       feature_type = "peak",
                       pheno_data   = NULL,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scpipe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scpipe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scpipe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCPIPE:", paste0("    scpipe: ", packageVersion("scPipe"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scpipe_results.csv
    touch ${prefix}_scpipe_output.rds
    echo "BIOC_SCPIPE:" > versions.yml
    echo "    scpipe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCPIPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCPIPE(ch_input)

    emit:
    results  = BIOC_SCPIPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCPIPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCPIPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCPIPE.out.versions  // channel: path(versions.yml)
}
