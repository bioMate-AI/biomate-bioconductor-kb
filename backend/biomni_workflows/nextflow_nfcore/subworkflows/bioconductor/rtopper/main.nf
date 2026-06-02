#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RTopper
// the RTopper package is designed to perform and integrate gene set enrichment results across multiple
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RTopper/inst/doc/RTopper.R
// Upstream  : KEGGREST, limma
// Downstream: none
//
// Install: BiocManager::install("RTopper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTOPPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtopper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtopper:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtopper:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_rtopper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtopper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtopper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RTopper)
    library(GO)
    library(Term)
    library(jsonlite)

    # --- Gene Set Score Computation [] ---
    # Key functions: computeDrStat
    bicStatInt <- computeDrStat(
        dataDr, columns = c(1:4),
        method = "bic", integrate = TRUE
    )
    bicStatSep <- computeDrStat(
        dataDr, columns = c(1:4),
        method = "bic", integrate = FALSE
    )


    # --- Gene Set Enrichment Integration [] ---
    # Key functions: combineGSE, adjustPvalGSE
    data(exampleData, package = "RTopper")
    gse_geo <- combineGSE(gseABS.sep, method = "geometricMean")
    gse_max <- combineGSE(gseABS.sep, method = "max")
    gse_adj <- adjustPvalGSE(gse_geo, proc = "BH")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtopper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtopper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtopper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTOPPER:", paste0("    rtopper: ", packageVersion("RTopper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtopper_results.csv
    touch ${prefix}_rtopper_output.rds
    echo "BIOC_RTOPPER:" > versions.yml
    echo "    rtopper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTOPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_RTOPPER(ch_input)

    emit:
    results  = BIOC_RTOPPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTOPPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTOPPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTOPPER.out.versions  // channel: path(versions.yml)
}
