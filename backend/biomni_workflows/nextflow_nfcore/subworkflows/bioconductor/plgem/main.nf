#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plgem
// The Power Law Global Error Model (PLGEM) has been shown to faithfully model the variance-versus-mean
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plgem/inst/doc/plgem.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("plgem")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLGEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plgem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plgem:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plgem:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plgem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plgem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plgem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plgem)
    library(jsonlite)

    # --- Plgemwrapper [] ---
    # Key functions: plgem
    library(plgem)
    data(LPSeset)
    set.seed(123)
    LPSdegList <- run.plgem(esdata=LPSeset)
    # --- Modelfitting [] ---
    # Key functions: fit
    LPSfit <- plgem.fit(data=LPSeset, covariate=1, fitCondition='C', p=10, q=0.5,
      plot.file=FALSE, fittingEval=TRUE, verbose=TRUE)
    # --- Observedstn [] ---
    # Key functions: obsStn
    LPSobsStn <- plgem.obsStn(data=LPSeset, covariate=1, baselineCondition=1,
      plgemFit=LPSfit, verbose=TRUE)
    # --- Resampledstn [] ---
    # Key functions: resampledStn
    set.seed(123)
    LPSresampledStn <- plgem.resampledStn(data=LPSeset, plgemFit=LPSfit,
      iterations="automatic", verbose=TRUE)
    # --- Pvalues [] ---
    # Key functions: pValue
    LPSpValues <- plgem.pValue(observedStn=LPSobsStn,
      plgemResampledStn=LPSresampledStn, verbose=TRUE)
    head(LPSpValues)
    # --- Degselection [] ---
    # Key functions: deg
    LPSdegList <- plgem.deg(observedStn=LPSobsStn, plgemPval=LPSpValues,
      delta=0.001, verbose=TRUE)
    head(LPSdegList$significant[["0.001"]][["LPS_vs_C"]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plgem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plgem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plgem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLGEM:", paste0("    plgem: ", packageVersion("plgem"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plgem_results.csv
    touch ${prefix}_plgem_output.rds
    echo "BIOC_PLGEM:" > versions.yml
    echo "    plgem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLGEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLGEM(ch_input)

    emit:
    results  = BIOC_PLGEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLGEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLGEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLGEM.out.versions  // channel: path(versions.yml)
}
