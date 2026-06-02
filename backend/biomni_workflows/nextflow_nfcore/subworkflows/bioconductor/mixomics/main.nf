#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mixOmics
// Multivariate methods are well suited to large omics data sets where the number of variables (e.g. ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mixOmics/inst/doc/vignette.R
// Upstream  : igraph, kableExtra, knitr
// Downstream: timeOmics, mixKernel, sgPLS
//
// Install: BiocManager::install("mixOmics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIXOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mixomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mixomics:6.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mixomics:6.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mixomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mixomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mixomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(X11)
    library(jsonlite)

    # --- Html document analysis [] ---
    # Key functions: html_document, img, write_lines, plotIndiv, plotVar, biplot, plotLoadings, detectCores
    set.seed(33) # For reproducibility with this handbook, remove otherwise
    train <- sample(1:nrow(X), 50)    # Randomly select 50 samples in training
    test <- setdiff(1:nrow(X), train) # Rest is part of the test set
    # --- Network and co-expression analysis [] ---
    # Key functions: X11, network
    If facing margin issues, use either X11() or save the plot using the
    # --- Visualization and reporting [] ---
    # Key functions: kable
    knitr::kable(extr.stab.spls2.liver.comp1[21:40], caption = 'Stability measure (occurence of selection) of the bottom 20 variables from X selected with sPLS2 across repeated 10-fold subsampling on component 1.', longtable = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mixomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mixomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mixomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIXOMICS:", paste0("    mixomics: ", packageVersion("mixOmics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixomics_results.csv
    touch ${prefix}_mixomics_output.rds
    echo "BIOC_MIXOMICS:" > versions.yml
    echo "    mixomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIXOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIXOMICS(ch_input)

    emit:
    results  = BIOC_MIXOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIXOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIXOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIXOMICS.out.versions  // channel: path(versions.yml)
}
