#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: planet
// This package contains R functions to predict biological variables to from placnetal DNA methylation 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/planet/inst/doc/planet.R
// Upstream  : EpiDISH, dplyr, ggplot2, minfi, tidyr
// Downstream: none
//
// Install: BiocManager::install("planet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLANET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-planet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-planet:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-planet:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_planet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_planet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_planet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(planet)
    library(jsonlite)

    # --- Projectcelltype [] ---
    # Key functions: projectCellType
    ---------------------------------------------------------------------
    houseman_estimates <- minfi:::projectCellType(
        plBetas[rownames(plCellCpGsThird), ],
        plCellCpGsThird,
        lessThanOne = FALSE
    # --- Epidish [] ---
    # Key functions: epidish, projection
    ---------------------------------------------------------------------
    # robust partial correlations
    epidish_RPC <- epidish(
        beta.m = plBetas[rownames(plCellCpGsThird), ],
        ref.m = plCellCpGsThird,
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # load example data
    data(plBetas)
    data(plPhenoData)
    dim(plBetas)
    # --- Mutate [] ---
    # Key functions: mutate, predictAge
    ---------------------------------------------------------------------
    plPhenoData <- plPhenoData %>%
        mutate(
            ga_RPC = predictAge(plBetas, type = "RPC"),
            ga_CPC = predictAge(plBetas, type = "CPC"),
    # --- Data [] ---
    # Key functions: all, predictEthnicity
    ---------------------------------------------------------------------
    data(ethnicityCpGs)
    all(ethnicityCpGs %in% rownames(plBetas))
    results <- predictEthnicity(plBetas)
    results %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_planet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_planet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_planet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLANET:", paste0("    planet: ", packageVersion("planet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_planet_results.csv
    touch ${prefix}_planet_output.rds
    echo "BIOC_PLANET:" > versions.yml
    echo "    planet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLANET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLANET(ch_input)

    emit:
    results  = BIOC_PLANET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLANET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLANET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLANET.out.versions  // channel: path(versions.yml)
}
