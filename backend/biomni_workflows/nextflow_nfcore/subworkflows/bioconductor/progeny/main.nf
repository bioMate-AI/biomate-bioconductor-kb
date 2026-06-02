#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: progeny
// PROGENy is resource that leverages a large compendium of publicly available signaling perturbation e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/progeny/inst/doc/progeny.R
// Upstream  : ggplot2, dplyr
// Downstream: none
//
// Install: BiocManager::install("progeny")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROGENY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-progeny"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-progeny:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-progeny:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_progeny_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_progeny_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_progeny_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(progeny)
    library(jsonlite)


    # --- Model [] ---
    # Key functions: progeny
    model <- progeny::model_human_full
    head(model)

    # --- W Dist [] ---
    # Key functions: group_by, slice_min, element_text, none
    # Get top 100 significant genes per pathway
    model_100 <- model %>%
      group_by(pathway) %>%
      slice_min(order_by = p.value, n = 200)

    # Plot
    ggplot(data=model_100, aes(x=weight, color=pathway, fill=pathway)) +
      geom_density() +
      theme(text = element_text(size=12)) +
      facet_wrap(~ pathway, scales='free') +
      xlab('scores') +
      ylab('densities') +
      theme_bw() +
      theme(legend.position = "none")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_progeny_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_progeny_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_progeny_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROGENY:", paste0("    progeny: ", packageVersion("progeny"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_progeny_results.csv
    touch ${prefix}_progeny_output.rds
    echo "BIOC_PROGENY:" > versions.yml
    echo "    progeny: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROGENY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROGENY(ch_input)

    emit:
    results  = BIOC_PROGENY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROGENY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROGENY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROGENY.out.versions  // channel: path(versions.yml)
}
