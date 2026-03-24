#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpliceWiz
// The analysis and visualization of alternative splicing (AS) events from RNA sequencing data remains 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpliceWiz/inst/doc/SW_Cookbook.R
// Upstream  : AnnotationHub, DESeq2, DoubleExpSeq, edgeR, ggplot2
// Downstream: none
//
// Install: BiocManager::install("SpliceWiz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLICEWIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splicewiz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splicewiz:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splicewiz:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_splicewiz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splicewiz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splicewiz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(STAR_version)
    library(SpliceWiz_example_NxtSE)
    library(jsonlite)

    # --- Annotationhub [] ---
    # Key functions: AnnotationHub, query
    ---------------------------------------------------------------------
    require(AnnotationHub)
    ah <- AnnotationHub()
    query(ah, "Ensembl")
    # --- Query [] ---
    # Key functions: query
    ---------------------------------------------------------------------
    query(ah, c("Homo Sapiens", "release-94"))
    # --- Getavailablego [] ---
    # Key functions: getAvailableGO
    ---------------------------------------------------------------------
    getAvailableGO()
    # --- Star Version [] ---
    # Key functions: STAR_version
    ---------------------------------------------------------------------
    STAR_version()
    # --- Splicewiz Example Nxtse [] ---
    # Key functions: SpliceWiz_example_NxtSE, covfile, getCoverage, path, tempdir, export
    ---------------------------------------------------------------------
    se <- SpliceWiz_example_NxtSE()
    cov_file <- covfile(se)[1]
    cov_negstrand <- getCoverage(cov_file, strand = "-")
    bw_file <- file.path(tempdir(), "sample_negstrand.bw")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splicewiz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splicewiz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splicewiz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLICEWIZ:", paste0("    splicewiz: ", packageVersion("SpliceWiz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splicewiz_results.csv
    touch ${prefix}_splicewiz_output.rds
    echo "BIOC_SPLICEWIZ:" > versions.yml
    echo "    splicewiz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLICEWIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPLICEWIZ(ch_input)

    emit:
    results  = BIOC_SPLICEWIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLICEWIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLICEWIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLICEWIZ.out.versions  // channel: path(versions.yml)
}
