#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RAREsim — estimate_expected_variants_with_defaults
// Estimate the expected number of rare variants per MAC bin using ancestry-specific default parameters.
// Input: mac_bins.csv
// Container: quay.io/biocontainers/bioconductor-raresim:1.14.0--r45hdfd78af_0
// Requires: RAREsim
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the expected number of variants per Kb using default parameters for a specified ancestry with nvariant. 2. Scale the var

nextflow.enable.dsl = 2

process BIOC_RARESIM_ESTIMATE_EXPECTED_VARIANTS_WITH_DEFAULTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load the required library
        library(RAREsim)
        
        # Read the user input file from the working directory
        # The file mac_bins.csv must contain the lower and upper boundaries of the MAC bins
        mac <- read.csv("mac_bins.csv")
        
        # 1. Calculate the expected number of variants per Kb using default parameters for AFR ancestry
        nvariant_default <- nvariant(N = 8128, pop = 'AFR')
        
        # 2. Estimate the proportion of variants in each MAC bin using default parameters
        afs_default <- afs(mac_bins = mac, pop = 'AFR')
        
        # 3. Combine the total expected variants (scaled by region size 19.029 Kb) and default AFS proportions
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
