#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: openPrimeR
// An implementation of methods for designing, evaluating, and comparing primer sets for multiplex PCR.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/openPrimeR/inst/doc/openPrimeR_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("openPrimeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPENPRIMER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-openprimer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-openprimer:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-openprimer:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_openprimer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_openprimer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_openprimer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(openPrimeR)
    library(jsonlite)

    # --- theme_set [] ---
    # Key functions: theme_set
    knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
    library(openPrimeR)
    ggplot2::theme_set(ggplot2::theme_grey(base_size = 12))
    # --- read_settings [] ---
    # Key functions: read_settings

    # --- cvg constraint setup [] ---
    # Key functions: cvg_constraints, conOptions
    No constraints on primer coverage (not recommended!)
    cvg_constraints(settings) <- list()
    conOptions(settings)$allowed_mismatches <- 3
    # --- change settings1 [] ---
    # Key functions: constraints
    constraints(design.settings) <- constraints(design.settings)[!grepl(
    "gc_clamp", names(constraints(design.settings)))]
    # --- change settings2 [] ---
    # Key functions: constraints
    constraints(design.settings)[["primer_length"]] <- c("min" = 25, "max" = 25)
    # --- change settings3 [] ---
    # Key functions: conOptions
    conOptions(design.settings)[["allowed_mismatches"]] <- 0
    # --- write_settings [] ---
    # Key functions: write_settings
    out.file <- tempfile("settings", fileext = ".xml")
    write_settings(design.settings, out.file)
    # --- write_primers [] ---
    # Key functions: write_primers
    out.file <- tempfile("my_primers", fileext = ".fasta")
    write_primers(optimal.primers$opti, out.file)
    # --- check constraints [] ---
    # Key functions: conOptions
    conOptions(settings)$allowed_other_binding_ratio <- c("max" = 1.0)
    constraint.df <- check_constraints(primer.df, template.df,
    settings, active.constraints = names(constraints(settings)))
    # --- kable [] ---
    # Key functions: kable
    knitr::kable(cvg.stats[, !(grepl("_fw", colnames(cvg.stats)) | grepl("_rev", colnames(cvg.stats)))], row.names = FALSE)
    # --- template cvg plot [] ---
    # Key functions: plot_template_cvg
    plot_template_cvg(constraint.df, template.df)
    # --- plot_primer_subsets [] ---
    # Key functions: plot_primer_subsets
    plot_primer_subsets(primer.subsets, template.df)
    # --- plot_primer_binding_regions [] ---
    # Key functions: plot_primer_binding_regions
    plot_primer_binding_regions(constraint.df, template.df)
    # --- cvg primer view [] ---
    # Key functions: plot_primer
    plot_primer(constraint.df[1,], template.df[1:10,])
    # --- plot constraints [] ---
    # Key functions: plot_constraint_fulfillment
    plot_constraint_fulfillment(constraint.df, settings)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_openprimer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_openprimer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_openprimer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPENPRIMER:", paste0("    openprimer: ", packageVersion("openPrimeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_openprimer_results.csv
    touch ${prefix}_openprimer_output.rds
    echo "BIOC_OPENPRIMER:" > versions.yml
    echo "    openprimer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPENPRIMER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPENPRIMER(ch_input)

    emit:
    results  = BIOC_OPENPRIMER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPENPRIMER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPENPRIMER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPENPRIMER.out.versions  // channel: path(versions.yml)
}
