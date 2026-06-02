#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: easyreporting
// An S4 class for facilitating the automated creation of rmarkdown files inside other packages/softwar
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/easyreporting/inst/doc/bio_usage.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("easyreporting")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EASYREPORTING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-easyreporting"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-easyreporting:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-easyreporting:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_easyreporting_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_easyreporting_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_easyreporting_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(easyreporting)
    library(jsonlite)

    # --- Mkdtitle [] ---
    # Key functions: mkdTitle, mkdCodeChunkComplete, quote, importData
    ---------------------------------------------------------------------
    mkdTitle(bioEr, title="Loading Counts Data")
    mkdCodeChunkComplete(object=bioEr, code=quote(geneCounts <- importData(
          system.file("extdata/GSE134118_Table_S3.xlsx", package="easyreporting"))),
          sourceFilesList=system.file("script/importFunctions.R", package="easyreporting"))
    # --- Mkdtitle [] ---
    # Key functions: mkdTitle, mkdCodeChunkComplete, quote, plotPCA
    ---------------------------------------------------------------------
    mkdTitle(bioEr, title="Plot PCA on count data", level=2)
    mkdCodeChunkComplete(bioEr,
                            code=quote(EDASeq::plotPCA(as.matrix(geneCounts))))
    # --- Mkdtitle [] ---
    # Key functions: mkdTitle, mkdCodeChunkCommented, applyEdgeRExample
    ---------------------------------------------------------------------
    mkdTitle(bioEr, "Differential Expression Analysis")
    # --- Mkdtitle [] ---
    # Key functions: mkdTitle, mkdCodeChunkComplete, plotMD
    ---------------------------------------------------------------------
    mkdTitle(bioEr, "MD Plot of DEGs", level=2)
    mkdCodeChunkComplete(bioEr, code="limma::plotMD(degList$test)")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_easyreporting_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_easyreporting_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_easyreporting_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EASYREPORTING:", paste0("    easyreporting: ", packageVersion("easyreporting"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_easyreporting_results.csv
    touch ${prefix}_easyreporting_output.rds
    echo "BIOC_EASYREPORTING:" > versions.yml
    echo "    easyreporting: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EASYREPORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EASYREPORTING(ch_input)

    emit:
    results  = BIOC_EASYREPORTING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EASYREPORTING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EASYREPORTING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EASYREPORTING.out.versions  // channel: path(versions.yml)
}
