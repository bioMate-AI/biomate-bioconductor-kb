#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CGHnormaliter
// Normalization and centralization of array comparative genomic hybridization (aCGH) data. The algorit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CGHnormaliter/inst/doc/CGHnormaliter.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CGHnormaliter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CGHNORMALITER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cghnormaliter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cghnormaliter:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cghnormaliter:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cghnormaliter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cghnormaliter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cghnormaliter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CGHnormaliter)
    library(jsonlite)

    # --- Cghnormaliterpackage [] ---
    # Key functions: packageDescription
    options(keep.source=TRUE)
    CGHnormaliterPackage <- packageDescription("CGHnormaliter")
    # --- Loaddata [] ---
    # Key functions: data
    library(CGHnormaliter)
    data(Leukemia)
    # --- Runcghnormaliter [] ---
    # Key functions: CGHnormaliter
    result <- CGHnormaliter(Leukemia, nchrom=4, cellularity=0.9)
    # --- Accessresults [] ---
    # Key functions: copynumber, segmented, calls
    normalized.data <- copynumber(result)  # log2 ratios
    segmented.data <- segmented(result)
    called.data <- calls(result)
    # --- Densityplotcommand [] ---
    # Key functions: density
    plot(density(normalized.data[, 2]), col=1, xlab="log2 ratio",
                                        main="Density plot")
    abline(v=0, lty=2)
    # --- Densityplotfigure [] ---
    # Key functions: density
    plot(density(normalized.data[, 2]), col=1, xlab="log2 ratio",
                                        main="Density plot")
    abline(v=0, lty=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cghnormaliter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cghnormaliter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cghnormaliter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CGHNORMALITER:", paste0("    cghnormaliter: ", packageVersion("CGHnormaliter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cghnormaliter_results.csv
    touch ${prefix}_cghnormaliter_output.rds
    echo "BIOC_CGHNORMALITER:" > versions.yml
    echo "    cghnormaliter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CGHNORMALITER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CGHNORMALITER(ch_input)

    emit:
    results  = BIOC_CGHNORMALITER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CGHNORMALITER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CGHNORMALITER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CGHNORMALITER.out.versions  // channel: path(versions.yml)
}
