#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: APL
// APL is a package developed for computation of Association Plots (AP), a method for visualization and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/APL/inst/doc/APL.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("APL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-apl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-apl:1.10.2--r44_0' :
        'quay.io/biocontainers/bioconductor-apl:1.10.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_apl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_apl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_apl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DarmanisBrainData)
    library(jsonlite)

    # --- Compute size factors by pooling [] ---
    # Key functions: quickCluster, computeSumFactors, logNormCounts, modelGeneVar, getTopHVGs
    set.seed(100)
    clust <- quickCluster(darmanis)
    darmanis <- computeSumFactors(darmanis, cluster = clust, min.mean = 0.1)
    # --- DarmanisBrainData analysis [] ---
    # Key functions: install_github, DarmanisBrainData, runAPL, logcounts, cacomp, cacomp_slot, plotReducedDim, pick_dims
    endo <- which(darmanis$cell.type == "endothelial")
    ca_biplot(ca, col_labels = endo, type = "ggplot")
    ca_biplot(ca, type = "plotly", col_labels = platelets)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_apl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_apl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_apl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_APL:", paste0("    apl: ", packageVersion("APL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_apl_results.csv
    touch ${prefix}_apl_output.rds
    echo "BIOC_APL:" > versions.yml
    echo "    apl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_APL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_APL(ch_input)

    emit:
    results  = BIOC_APL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_APL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_APL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_APL.out.versions  // channel: path(versions.yml)
}
