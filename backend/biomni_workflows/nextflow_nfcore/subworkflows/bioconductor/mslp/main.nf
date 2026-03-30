#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mslp
// An integrated pipeline to predict the potential synthetic lethality partners (SLPs) of tumour mutati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mslp/inst/doc/mslp.R
// Upstream  : doFuture, future, magrittr
// Downstream: none
//
// Install: BiocManager::install("mslp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSLP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mslp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mslp:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mslp:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mslp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mslp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mslp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mslp)
    library(jsonlite)

    # --- Data Preprocessing [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    require(future)
    require(doFuture)
    library(magrittr)
    library(mslp)
    # --- Call SLPs from Compensation Module [] ---
    # Key functions: plan, comp_slp
    ---------------------------------------------------------------------
    plan(multisession, workers = 2)
    res_comp <- comp_slp(example_z, example_comp_mut)
    saveRDS(res_comp, file = "compSLP_res.rds")
    plan(sequential)
    # --- Call SLPs from Compensation Module [] ---
    # Key functions: plan, corr_slp
    ---------------------------------------------------------------------
    plan(multisession, workers = 2)
    res_corr <- corr_slp(example_expr, example_corr_mut)
    saveRDS(res_corr, "corrSLP_res.rds")
    #- Filter res by importance threshold to reduce false positives.
    # --- Call SLPs from Compensation Module [] ---
    # Key functions: plan, sample, intersect, corr_slp
    ---------------------------------------------------------------------
    plan(multisession, workers = 2)
    #- Random mutations and runs
    mutgene    <- sample(intersect(example_corr_mut$mut_entrez, rownames(example_expr)), 5)
    nperm      <- 3
    # --- Call SLPs from Compensation Module [] ---
    # Key functions: plan, merge_slp, sample, setnames
    ---------------------------------------------------------------------
    plan(multisession, workers = 2)
    #- Merge data.
    #- Load previous results.
    res_comp   <- readRDS("compSLP_res.rds")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mslp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mslp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mslp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSLP:", paste0("    mslp: ", packageVersion("mslp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mslp_results.csv
    touch ${prefix}_mslp_output.rds
    echo "BIOC_MSLP:" > versions.yml
    echo "    mslp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSLP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSLP(ch_input)

    emit:
    results  = BIOC_MSLP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSLP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSLP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSLP.out.versions  // channel: path(versions.yml)
}
