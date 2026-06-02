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

    # --- Binding Region Assignment [] ---
    # Key functions: assign_binding_regions
    template.df.uni <- assign_binding_regions(seq.df,
        fw = c(1, 50), rev = c(1, 40))
    l.fasta.file <- system.file("extdata", "IMGT_data", "templates",
        "Homo_sapiens_IGH_functional_leader.fasta", package = "openPrimeR")
    template.df <- assign_binding_regions(seq.df,
        fw = l.fasta.file, rev = NULL)


    # --- PCR Settings Configuration [] ---
    # Key functions: read_settings, constraints, conOptions
    settings.xml <- system.file("extdata", "settings",
        "C_Taq_PCR_high_stringency.xml", package = "openPrimeR")
    settings <- read_settings(settings.xml)
    design.settings <- settings
    constraints(design.settings)[["primer_length"]] <- c("min" = 25, "max" = 25)
    conOptions(design.settings)[["allowed_mismatches"]] <- 0


    # --- Primer Design and Loading [] ---
    # Key functions: design_primers, read_primers
    optimal.primers <- design_primers(template.df[1:2, ],
        mode.directionality = "fw", settings = design.settings)
    primer.location <- system.file("extdata", "IMGT_data", "primers",
        "IGHV", "Ippolito2012.fasta", package = "openPrimeR")
    primer.df <- read_primers(primer.location, fw.id = "_fw")


    # --- Constraint Evaluation and Coverage Analysis [] ---
    # Key functions: check_constraints, update_template_cvg, get_cvg_ratio, get_cvg_stats, plot_template_cvg
    conOptions(settings)$allowed_other_binding_ratio <- c("max" = 1.0)
    constraint.df <- check_constraints(primer.df, template.df,
        settings, active.constraints = names(constraints(settings)))
    template.df <- update_template_cvg(template.df, constraint.df)
    cvg.ratio <- get_cvg_ratio(constraint.df, template.df)
    cvg.stats <- get_cvg_stats(constraint.df, template.df,
        for.viewing = TRUE)
    plot_template_cvg(constraint.df, template.df)

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
