#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GARS
// Feature selection aims to identify and remove redundant, irrelevant and noisy variables from high-di
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GARS/inst/doc/GARS.R
// Upstream  : DaMiRseq, MLSeq
// Downstream: none
//
// Install: BiocManager::install("GARS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GARS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gars"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gars:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gars:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gars_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gars_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gars_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AllPop)
    library(FitScore)
    library(GARS_GA)
    library(GARS_PlotFeaturesUsage)
    library(GARS_PlotFitnessEvolution)
    library(MatrixFeatures)
    library(jsonlite)

    # --- chu 2 [] ---
    # Key functions: GARS_GA
    set.seed(123)
    # --- chu 2 bis [] ---
    # Key functions: FitScore, GARS_PlotFitnessEvolution, AllPop, GARS_PlotFeaturesUsage
    fitness_scores <- FitScore(res_GA)
    GARS_PlotFitnessEvolution(fitness_scores)
    Allfeat_names <- rownames(datanorm)
    # --- chu 3 [] ---
    # Key functions: MatrixFeatures
    data_reduced_GARS <- MatrixFeatures(res_GA)
    data_reduced_DaMiR <- as.data.frame(data_reduced_GARS)
    classes_DaMiR <- as.data.frame(colData(datanorm))
    # --- to Latex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gars_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gars_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gars_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GARS:", paste0("    gars: ", packageVersion("GARS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gars_results.csv
    touch ${prefix}_gars_output.rds
    echo "BIOC_GARS:" > versions.yml
    echo "    gars: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GARS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GARS(ch_input)

    emit:
    results  = BIOC_GARS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GARS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GARS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GARS.out.versions  // channel: path(versions.yml)
}
