#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Pirat
// Pirat enables the imputation of missing values (either MNARs or MCARs) in bottom-up LC-MS/MS proteom
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Pirat/inst/doc/Pirat.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Pirat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PIRAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pirat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pirat:1.0.2--r44_0' :
        'quay.io/biocontainers/bioconductor-pirat:1.0.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pirat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pirat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pirat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Pirat)
    library(jsonlite)


    # --- Load Data [] ---
    # Key functions: my_pipeline_llkimpute
    library(Pirat)
    library(utils)
    data(subbouyssie)
    imp.res <- my_pipeline_llkimpute(subbouyssie)

    # --- Test1 [] ---
    # Key functions: pirat
    head(imp.res$data.imputed[ ,seq(5)])
    imp.res$params

    # --- Correlations [] ---
    # Key functions: plot_pep_correlations, pipeline_llkimpute
    data(ropers)
    plot_pep_correlations(ropers, titlename = "Ropers2021")
    data(subropers)
    imp.res = pipeline_llkimpute(subropers, extension = "2")

    # --- Impute4 [] ---
    # Key functions: colSums, rowSums, my_pipeline_llkimpute
    mask.sing.pg = colSums(subropers$adj) == 1
    mask.sing.pep = rowSums(subropers$adj[, mask.sing.pg]) >= 1
    imp.res$data.imputed[, mask.sing.pep]
    imp.res = my_pipeline_llkimpute(subropers, extension = "S")

    # --- Impute2 [] ---
    # Key functions: colSums, rowSums, my_pipeline_llkimpute
    mask.sing.pg = colSums(subropers$adj) == 1
    mask.sing.pep = rowSums(subropers$adj[, mask.sing.pg]) >= 1
    imp.res$data.imputed[, mask.sing.pep]
    imp.res = my_pipeline_llkimpute(subropers,
        extension = "T",
        rna.cond.mask = seq(nrow(subropers$peptides_ab)),
        pep.cond.mask = seq(nrow(subropers$peptides_ab)),
        max.pg.size.pirat.t = 1)

    # --- Data Imputed3 [] ---
    # Key functions: colSums, rowSums, my_pipeline_llkimpute, rep
    mask.sing.pg = colSums(subropers$adj) == 1
    mask.sing.pep = rowSums(subropers$adj[, mask.sing.pg]) >= 1
    imp.res$data.imputed[, mask.sing.pep]
    imp.res = my_pipeline_llkimpute(subropers,
                                 extension = "T",
                                 rna.cond.mask = rep(seq(6), each = 3),
                                 pep.cond.mask = rep(seq(6), each = 3),
                                 max.pg.size.pirat.t = 1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pirat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pirat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pirat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PIRAT:", paste0("    pirat: ", packageVersion("Pirat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pirat_results.csv
    touch ${prefix}_pirat_output.rds
    echo "BIOC_PIRAT:" > versions.yml
    echo "    pirat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PIRAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PIRAT(ch_input)

    emit:
    results  = BIOC_PIRAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PIRAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PIRAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PIRAT.out.versions  // channel: path(versions.yml)
}
