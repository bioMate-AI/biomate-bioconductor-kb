#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: YAPSA — signature_confidence_intervals
// Compute and plot 95% confidence intervals for mutational signature exposures using the profile likelihood method.
// Input: lymphomaNature2013_mutCat_df, lymphoma_COSMIC_listsList, COSMIC_subgroups_df
// Container: quay.io/biocontainers/bioconductor-yapsa:1.36.1--r45hdfd78af_0
// R packages: YAPSA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-yapsa:1.36.1--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("YAPSA")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(YAPSA)
    
    # Read user input files from the working directory
    # Since lymphoma_COSMIC_listsList is a complex list structure, RDS is the standard format.
    lymphoma_COSMIC_listsList <- readRDS("lymphoma_COSMIC_listsList.rds")
    lymphomaNature2013_mutCat_df <- readRDS("lymphomaNature2013_mutCat_df.rds")
    COSMIC_subgroups_df <- readRDS("COSMIC_subgroups_df.rds")
    
    # --- Compute confidence intervals for the exposures using ---
    complete_df <- variateExp(
      in_catalogue_df = lymphomaNature2013_mutCat_df,
      in_sig_df = lymphoma_COSMIC_listsList\$cohort\$signatures,
      in_exposures_df = lymphoma_COSMIC_listsList\$cohort\$exposures,
      in_sigLevel = 0.025,
      in_delta = 0.4)
    
    # Save the computed confidence intervals to disk
    write.csv(complete_df, "confidence_intervals_exposures.csv", row.names = FALSE)
    saveRDS(complete_df, "confidence_intervals_exposures.rds")
    
    # --- Plot the exposures with confidence interval whiskers and ---
    pdf("exposures_confidence_intervals_plot.pdf", width = 12, height = 10)
    plotExposuresConfidence(
      in_complete_df = complete_df,
      in_subgroups_df = COSMIC_subgroups_df,
      in_sigInd_df = lymphoma_COSMIC_listsList\$cohort\$out_sig_ind_df)
    dev.off()

    writeLines(c(
        '"BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS":',
        paste0('        YAPSA: ', as.character(packageVersion("YAPSA")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signature_confidence_intervals.csv versions.yml
    """
}

workflow BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lymphomaNature2013_mutCat_df, lymphoma_COSMIC_listsList, COSMIC_subgroups_df ] ]

    main:
    BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS(ch_input)

    emit:
    tables   = BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS.out.tables
    plots    = BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS.out.plots
    objects  = BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS.out.objects
    versions = BIOC_YAPSA_SIGNATURE_CONFIDENCE_INTERVALS.out.versions
}
