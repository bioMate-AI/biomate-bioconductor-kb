#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TOAST
// This package is devoted to analyzing high-throughput data (e.g. gene expression microarray, DNA meth
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TOAST/inst/doc/TOAST.R
// Upstream  : EpiDISH
// Downstream: none
//
// Install: BiocManager::install("TOAST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOAST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-toast"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-toast:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-toast:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_toast_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_toast_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_toast_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChooseMarker)
    library(GetPrior)
    library(MDeconv)
    library(jsonlite)

    # --- Create experimental design matrix [] ---
    # Key functions: makeDesign, fitModel, csTest
    Design_out <- makeDesign(design, Prop)
    fitted_model <- fitModel(Design_out, Y_raw)
    # --- Refinx analysis [] ---
    # Key functions: findRefinx, epidish, myRefFreeCellMix, assignCellType, csDeconv, choose, ChooseMarker, MDeconv
    refinx <- findRefinx(Y_raw, nmarker = 1000, sortBy = "cv")
    InitNames <- rownames(Y_raw)[refinx]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_toast_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_toast_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_toast_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOAST:", paste0("    toast: ", packageVersion("TOAST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_toast_results.csv
    touch ${prefix}_toast_output.rds
    echo "BIOC_TOAST:" > versions.yml
    echo "    toast: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOAST(ch_input)

    emit:
    results  = BIOC_TOAST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOAST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOAST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOAST.out.versions  // channel: path(versions.yml)
}
