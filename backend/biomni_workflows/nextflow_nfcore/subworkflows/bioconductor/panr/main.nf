#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PANR
// This package provides S4 classes and methods for inferring functional gene networks with edges encod
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PANR/inst/doc/PANR-Vignette.R
// Upstream  : RedeR, pvclust
// Downstream: none
//
// Install: BiocManager::install("PANR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-panr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-panr:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-panr:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_panr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_panr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_panr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PANR)
    library(jsonlite)

    # --- Model Fitting and Visualization [] ---
    # Key functions: view, summarize
    view(bm1, "fitNULL")
    view(bm1, "fitBM")
    bm_summary <- summarize(bm1, what = "ALL")


    # --- Posterior Association Network Inference [] ---
    # Key functions: new, infer
    pan <- new("PAN", bm1 = bm1)
    pan <- infer(
        pan,
        para = list(type = "SNR", log = TRUE, sign = TRUE, cutoff = log(5)),
        filter = FALSE,
        verbose = FALSE
    )


    # --- Network Building and Visualization [] ---
    # Key functions: buildPAN, summarize
    data(Bakal2007Cluster)
    nodeColor <- rep("blue", nrow(Bakal2007))
    names(nodeColor) <- rownames(Bakal2007)
    pan <- buildPAN(
        pan,
        engine = "RedeR",
        para = list(nodeColor = nodeColor, hideNeg = TRUE)
    )
    pan_graph <- summarize(pan, what = "graph")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_panr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_panr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_panr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PANR:", paste0("    panr: ", packageVersion("PANR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_panr_results.csv
    touch ${prefix}_panr_output.rds
    echo "BIOC_PANR:" > versions.yml
    echo "    panr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PANR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PANR(ch_input)

    emit:
    results  = BIOC_PANR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PANR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PANR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PANR.out.versions  // channel: path(versions.yml)
}
