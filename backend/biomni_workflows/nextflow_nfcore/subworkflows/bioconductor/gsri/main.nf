#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSRI
// The GSRI package estimates the number of differentially expressed genes in gene sets, utilizing the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSRI/inst/doc/gsri.R
// Upstream  : Biobase, GSEABase, limma
// Downstream: none
//
// Install: BiocManager::install("GSRI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSRI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsri"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsri:2.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsri:2.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsri_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsri_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsri_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSRI)
    library(F)
    library(GeneSet)
    library(Lkeys)
    library(jsonlite)

    # --- GSRI with Gene Set Collections [] ---
    # Key functions: gsri
    data(sample.ExpressionSet, package="Biobase")
    eset <- sample.ExpressionSet
    groups <- Biobase::pData(eset)$type
    gmt_file <- system.file("extdata", "c1c10.gmt", package="GSRI")
    gmt <- GSEABase::getGmt(gmt_file)
    g_multi <- GSRI::gsri(eset, groups, gmt)


    # --- Sorting and Exporting Results [] ---
    # Key functions: sortGsri, export
    data(sample.ExpressionSet, package="Biobase")
    eset <- sample.ExpressionSet
    groups <- Biobase::pData(eset)$type
    gmt_file <- system.file("extdata", "c1c10.gmt", package="GSRI")
    gmt <- GSEABase::getGmt(gmt_file)
    g_multi <- GSRI::gsri(eset, groups, gmt)
    g_sorted <- GSRI::sortGsri(g_multi, by = c("nRegGenes", "pRegGenes"))
    export_file <- tempfile(fileext = ".txt")
    GSRI::export(g_sorted, export_file)


    # --- Custom Statistical Testing [] ---
    # Key functions: gsri, rowF
    data(sample.ExpressionSet, package="Biobase")
    eset <- sample.ExpressionSet
    scores <- Biobase::pData(eset)$score
    classes <- cut(scores, seq(0, 1, length.out=4), label=c("low", "med", "high"))
    gmt_file <- system.file("extdata", "c1c10.gmt", package="GSRI")
    gmt <- GSEABase::getGmt(gmt_file)
    g_custom <- GSRI::gsri(eset, classes, gmt, test = GSRI::rowF, nBoot = 50,
        alpha = 0.1, grenander = FALSE)


    # --- Visualization of GSRI Results [] ---
    # Key functions: gsri, plot
    data(sample.ExpressionSet, package="Biobase")
    eset <- sample.ExpressionSet
    groups <- Biobase::pData(eset)$type
    g_res <- GSRI::gsri(eset, groups)
    plot(g_res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsri_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsri_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsri_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSRI:", paste0("    gsri: ", packageVersion("GSRI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsri_results.csv
    touch ${prefix}_gsri_output.rds
    echo "BIOC_GSRI:" > versions.yml
    echo "    gsri: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSRI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSRI(ch_input)

    emit:
    results  = BIOC_GSRI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSRI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSRI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSRI.out.versions  // channel: path(versions.yml)
}
