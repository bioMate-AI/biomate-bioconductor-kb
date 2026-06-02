#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gCrisprTools
// Set of tools for evaluating pooled high-throughput screening experiments, typically employing CRISPR
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gCrisprTools/inst/doc/Contrast_Comparisons.R
// Upstream  : Biobase, limma
// Downstream: none
//
// Install: BiocManager::install("gCrisprTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GCRISPRTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gcrisprtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gcrisprtools:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gcrisprtools:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(marraylm)

    output:
    tuple val(meta), path("${meta.id}_gcrisprtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gcrisprtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gcrisprtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gCrisprTools)
    library(jsonlite)


    # --- Contrastbarchart [] ---
    # Key functions: ct.contrastBarchart
    ct.contrastBarchart(regularized, background = FALSE, statistic = 'best.p')

    # --- Contrast Interaction [] ---
    # Key functions: model.matrix, pData, makeContrasts, gCrisprTools, ann
    library(Biobase)
    library(limma)
    library(gCrisprTools)

    #Create a complex model design; removing the replicate term for clarity
    data("es", package = "gCrisprTools")
    data("ann", package = "gCrisprTools")

    design <- model.matrix(~ 0 + TREATMENT_NAME, pData(es))
    colnames(design) <- gsub('TREATMENT_NAME', '', colnames(design))
    contrasts <-makeContrasts(ControlTime = ControlExpansion - ControlReference,
                              DeathOverTime = DeathExpansion - ControlReference,
                              Interaction = DeathExpansion - ControlExpansion, 
                              levels = design)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gcrisprtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gcrisprtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gcrisprtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GCRISPRTOOLS:", paste0("    gcrisprtools: ", packageVersion("gCrisprTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gcrisprtools_results.csv
    touch ${prefix}_gcrisprtools_output.rds
    echo "BIOC_GCRISPRTOOLS:" > versions.yml
    echo "    gcrisprtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GCRISPRTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(marraylm) ]

    main:
    BIOC_GCRISPRTOOLS(ch_input)

    emit:
    results  = BIOC_GCRISPRTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GCRISPRTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GCRISPRTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GCRISPRTOOLS.out.versions  // channel: path(versions.yml)
}
