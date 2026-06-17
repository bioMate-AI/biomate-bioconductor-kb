#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RAREsim — estimate_expected_variants_with_defaults
// Estimate the expected number of rare variants per MAC bin using ancestry-specific default parameters.
// Input: mac_bins.csv
// Container: quay.io/biocontainers/bioconductor-raresim:1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RAREsim
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the expected number of variants per Kb using
//  * 2. [Core Analysis] Estimate the proportion of variants in each MAC bin using
//  * 3. [Core Analysis] Combine the total expected variants (scaled by region

nextflow.enable.dsl = 2

process BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("RAREsim")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load the required library
        library(RAREsim)
        
        # Read the user input file from the working directory
        # The file mac_bins.csv must contain the lower and upper boundaries of the MAC bins
        mac <- read.csv("mac_bins.csv")
        
        # --- Calculate the expected number of variants per Kb using ---
        nvariant_default <- nvariant(N = 8128, pop = 'AFR')
        
        # --- Estimate the proportion of variants in each MAC bin using ---
        afs_default <- afs(mac_bins = mac, pop = 'AFR')
        
        # --- Combine the total expected variants (scaled by region ---
        # using expected_variants to get the expected number of variants per MAC bin.
        # This call uses the exact documented parameters and structure.
        bin_estimates <- expected_variants(Total_num_var = 19.029 * nvariant_default,
                                           mac_bin_prop = afs_default)
        
        # Write the final output to a CSV file
        write.csv(bin_estimates, "expected_variants.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS":',
        paste0('    RAREsim: ', as.character(packageVersion('RAREsim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_estimate_expected_variants_with_defaults.csv versions.yml
    """
}

workflow BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mac_bins.csv ] ]

    main:
    BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS(ch_input)

    emit:
    tables   = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS.out.tables
    plots    = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS.out.plots
    objects  = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS.out.objects
    versions = BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS.out.versions
}
